// osble.dll — tiny Bluetooth LE bridge for Open Sports on Windows.
// Finds Switch 2 controllers (Joy-Con 2 L/R, Pro Controller 2), connects over GATT,
// runs their init sequence and queues the 63-byte input reports for the game (LuaJIT FFI).
//
// Protocol facts from community reverse engineering: joycon2cpp (MIT), linux-switch2
// PROTOCOL.md, bit-axis-labs. No Nintendo code. GPL-3.0 as part of Open Sports.
#define NOMINMAX
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Storage::Streams;

#define API extern "C" __declspec(dllexport)

enum { EV_FOUND = 1, EV_CONNECTED = 2, EV_DISCONNECTED = 3, EV_STATUS = 4, EV_FAILED = 5 };

struct osble_event {
  int type;
  int id;
  uint64_t addr;
  int pid;
  int rssi;
  char text[96];
};

static const uint16_t NINTENDO = 0x0553;
static const wchar_t* INPUT_UUID = L"ab7de9be-89fe-49ad-828f-118f09df7fd2";   // common report 0x05
static const wchar_t* CMD_UUID = L"649d4ac9-8eb7-4e6c-af44-1ea54fe5f005";     // basic command out
static const wchar_t* REPLY_UUID = L"c765a961-d9d8-4d36-a20a-5315b111836a";   // basic command reply
static const wchar_t* VIBCMD_L = L"ce49a830-dced-48ae-931e-c8cf88aadbea";     // vibration + command (JC2 L)
static const wchar_t* VIBCMD_R = L"65a724b3-f1e7-4a61-8078-a342376b27ff";     // vibration + command (JC2 R)
static const wchar_t* VIBCMD_PRO = L"3dacbc7e-6955-40b5-8eaf-6f9809e8b379";   // Pro Controller 2

struct Report { uint8_t data[64]; };

struct Pad {
  int id = 0;
  uint64_t addr = 0;
  int pid = 0;
  BluetoothLEDevice device{ nullptr };
  GattCharacteristic input{ nullptr }, cmd{ nullptr }, reply{ nullptr }, vibcmd{ nullptr };
  std::mutex m;
  std::deque<Report> reports;
  std::atomic<bool> alive{ false };
};

static std::mutex g_m;
static std::deque<osble_event> g_events;
static std::map<int, std::shared_ptr<Pad>> g_pads;
static std::map<uint64_t, int> g_seen; // addr -> last rssi, so FOUND fires once per scan
static int g_nextId = 1;
static BluetoothLEAdvertisementWatcher g_watcher{ nullptr };
static event_token g_watchToken{};

static void push(int type, int id, uint64_t addr, int pid, int rssi, const char* text) {
  osble_event e{};
  e.type = type; e.id = id; e.addr = addr; e.pid = pid; e.rssi = rssi;
  if (text) strncpy_s(e.text, text, _TRUNCATE);
  std::lock_guard<std::mutex> lk(g_m);
  g_events.push_back(e);
  if (g_events.size() > 256) g_events.pop_front();
}

static bool parseAd(std::vector<uint8_t> const& d, int& pid) {
  // 01 00 03 | 7e 05 (vendor) | pid LE
  if (d.size() < 7 || d[0] != 0x01 || d[1] != 0x00 || d[2] != 0x03 || d[3] != 0x7E || d[4] != 0x05) return false;
  pid = d[5] | (d[6] << 8);
  return pid >= 0x2060;
}

static std::vector<uint8_t> readBuf(IBuffer const& b) {
  auto r = DataReader::FromBuffer(b);
  std::vector<uint8_t> v(r.UnconsumedBufferLength());
  if (!v.empty()) r.ReadBytes(v);
  return v;
}

static bool write(GattCharacteristic const& ch, std::vector<uint8_t> const& bytes) {
  if (!ch) return false;
  try {
    DataWriter w;
    w.WriteBytes(bytes);
    auto st = ch.WriteValueAsync(w.DetachBuffer(), GattWriteOption::WriteWithoutResponse).get();
    return st == GattCommunicationStatus::Success;
  } catch (...) { return false; }
}

// command with the 8-byte header: cmd 91 01 sub 00 len 00 00 | payload
static std::vector<uint8_t> command(uint8_t cmd, uint8_t sub, std::vector<uint8_t> payload) {
  std::vector<uint8_t> p = { cmd, 0x91, 0x01, sub, 0x00, (uint8_t)payload.size(), 0x00, 0x00 };
  p.insert(p.end(), payload.begin(), payload.end());
  return p;
}

static void sendCommand(Pad& p, std::vector<uint8_t> const& c) {
  if (p.vibcmd) { // vibration + command char: report id 0x00 + 16 bytes of (idle) rumble, then the command
    std::vector<uint8_t> pkt(p.pid == 0x2069 ? 33 : 17, 0x00);
    pkt.insert(pkt.end(), c.begin(), c.end());
    write(p.vibcmd, pkt);
  } else {
    write(p.cmd, c);
  }
}

static void runInit(Pad& p) {
  bool joycon = p.pid == 0x2066 || p.pid == 0x2067;
  uint8_t features = joycon ? 0x37 : 0x2F;
  // Known-good Windows sequence (joycon2cpp "official init"); SPI reads are harmless and
  // keep the controller's state machine identical to a console connection.
  std::vector<std::vector<uint8_t>> seq = {
    { 0x07, 0x91, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00 },
    { 0x02, 0x91, 0x01, 0x04, 0x00, 0x08, 0x00, 0x00, 0x40, 0x7E, 0x00, 0x00, 0x00, 0x30, 0x01, 0x00 },
    { 0x10, 0x91, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00 },
    { 0x16, 0x91, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00 },
    { 0x0A, 0x91, 0x01, 0x02, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00 },
    { 0x09, 0x91, 0x01, 0x07, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    { 0x0C, 0x91, 0x01, 0x02, 0x00, 0x04, 0x00, 0x00, features, 0x00, 0x00, 0x00 },
    { 0x02, 0x91, 0x01, 0x04, 0x00, 0x08, 0x00, 0x00, 0x40, 0x7E, 0x00, 0x00, 0x80, 0x30, 0x01, 0x00 },
    { 0x02, 0x91, 0x01, 0x04, 0x00, 0x08, 0x00, 0x00, 0x40, 0x7E, 0x00, 0x00, 0x40, 0xC0, 0x1F, 0x00 },
    { 0x02, 0x91, 0x01, 0x04, 0x00, 0x08, 0x00, 0x00, 0x10, 0x7E, 0x00, 0x00, 0x40, 0x30, 0x01, 0x00 },
    { 0x02, 0x91, 0x01, 0x04, 0x00, 0x08, 0x00, 0x00, 0x18, 0x7E, 0x00, 0x00, 0x00, 0x31, 0x01, 0x00 },
    { 0x11, 0x91, 0x01, 0x03, 0x00, 0x00, 0x00, 0x00 },
    { 0x02, 0x91, 0x01, 0x04, 0x00, 0x08, 0x00, 0x00, 0x20, 0x7E, 0x00, 0x00, 0x60, 0x30, 0x01, 0x00 },
    { 0x0A, 0x91, 0x01, 0x08, 0x00, 0x14, 0x00, 0x00,
      0x01, (uint8_t)(joycon ? 0x59 : 0xFF), (uint8_t)(joycon ? 0x09 : 0xFF), (uint8_t)(joycon ? 0x00 : 0xFF), (uint8_t)(joycon ? 0x00 : 0xFF),
      0xFF, 0xFF, 0xFF, 0xFF, 0x35, 0x00, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    { 0x11, 0x91, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00 },
    { 0x0C, 0x91, 0x01, 0x04, 0x00, 0x04, 0x00, 0x00, features, 0x00, 0x00, 0x00 },
  };
  for (auto& c : seq) {
    sendCommand(p, c);
    std::this_thread::sleep_for(std::chrono::milliseconds(80));
  }
}

static GattCharacteristic findChar(std::vector<GattCharacteristic> const& all, const wchar_t* uuid) {
  guid g(uuid);
  for (auto& c : all) if (c.Uuid() == g) return c;
  return nullptr;
}

static void connectThread(std::shared_ptr<Pad> p) {
  init_apartment(apartment_type::multi_threaded);
  try {
    push(EV_STATUS, p->id, p->addr, p->pid, 0, "Opening device");
    p->device = BluetoothLEDevice::FromBluetoothAddressAsync(p->addr).get();
    if (!p->device) { push(EV_FAILED, p->id, p->addr, p->pid, 0, "Could not open the controller"); return; }

    GattDeviceServicesResult sr{ nullptr };
    for (int i = 0; i < 10; i++) {
      sr = p->device.GetGattServicesAsync(BluetoothCacheMode::Uncached).get();
      if (sr.Status() == GattCommunicationStatus::Success) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(400));
    }
    if (!sr || sr.Status() != GattCommunicationStatus::Success) {
      push(EV_FAILED, p->id, p->addr, p->pid, 0, "No GATT services (press SYNC again)"); return;
    }
    std::vector<GattCharacteristic> chars;
    for (auto svc : sr.Services()) {
      auto cr = svc.GetCharacteristicsAsync(BluetoothCacheMode::Uncached).get();
      if (cr.Status() != GattCommunicationStatus::Success) continue;
      for (auto c : cr.Characteristics()) chars.push_back(c);
    }
    p->input = findChar(chars, INPUT_UUID);
    p->cmd = findChar(chars, CMD_UUID);
    p->reply = findChar(chars, REPLY_UUID);
    p->vibcmd = findChar(chars, p->pid == 0x2067 ? VIBCMD_L : (p->pid == 0x2066 ? VIBCMD_R : VIBCMD_PRO));
    if (!p->input || !p->cmd) { push(EV_FAILED, p->id, p->addr, p->pid, 0, "Not a supported controller"); return; }

    std::weak_ptr<Pad> wp = p;
    p->input.ValueChanged([wp](GattCharacteristic const&, GattValueChangedEventArgs const& a) {
      auto sp = wp.lock();
      if (!sp) return;
      auto v = readBuf(a.CharacteristicValue());
      Report r{};
      memcpy(r.data, v.data(), std::min<size_t>(v.size(), 63));
      std::lock_guard<std::mutex> lk(sp->m);
      sp->reports.push_back(r);
      if (sp->reports.size() > 512) sp->reports.pop_front();
    });
    p->input.WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue::Notify).get();
    if (p->reply) {
      try { p->reply.WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue::Notify).get(); } catch (...) {}
    }
    p->device.ConnectionStatusChanged([wp](BluetoothLEDevice const& d, auto const&) {
      auto sp = wp.lock();
      if (sp && d.ConnectionStatus() == BluetoothConnectionStatus::Disconnected && sp->alive.exchange(false))
        push(EV_DISCONNECTED, sp->id, sp->addr, sp->pid, 0, "Disconnected");
    });
    try {
      p->device.RequestPreferredConnectionParameters(BluetoothLEPreferredConnectionParameters::ThroughputOptimized());
    } catch (...) {}

    push(EV_STATUS, p->id, p->addr, p->pid, 0, "Starting controller");
    runInit(*p);
    p->alive = true;
    push(EV_CONNECTED, p->id, p->addr, p->pid, 0, "Connected");
  } catch (hresult_error const& e) {
    std::string msg = "Bluetooth error: " + to_string(e.message());
    push(EV_FAILED, p->id, p->addr, p->pid, 0, msg.c_str());
  } catch (...) {
    push(EV_FAILED, p->id, p->addr, p->pid, 0, "Bluetooth error");
  }
}

API int osble_version() { return 1; }

API int osble_scan(int on) {
  try {
    if (on) {
      if (!g_watcher) {
        g_watcher = BluetoothLEAdvertisementWatcher();
        g_watcher.ScanningMode(BluetoothLEScanningMode::Active);
        g_watchToken = g_watcher.Received([](auto const&, BluetoothLEAdvertisementReceivedEventArgs const& a) {
          int pid = 0;
          for (auto sec : a.Advertisement().ManufacturerData()) {
            if (sec.CompanyId() != NINTENDO) continue;
            if (parseAd(readBuf(sec.Data()), pid)) {
              uint64_t addr = a.BluetoothAddress();
              bool fresh;
              { std::lock_guard<std::mutex> lk(g_m); fresh = g_seen.find(addr) == g_seen.end(); g_seen[addr] = a.RawSignalStrengthInDBm(); }
              if (fresh) push(EV_FOUND, 0, addr, pid, a.RawSignalStrengthInDBm(), nullptr);
              return;
            }
          }
        });
      }
      { std::lock_guard<std::mutex> lk(g_m); g_seen.clear(); }
      g_watcher.Start();
    } else if (g_watcher) {
      g_watcher.Stop();
    }
    return 1;
  } catch (...) {
    push(EV_FAILED, 0, 0, 0, 0, "Bluetooth is off or missing");
    return 0;
  }
}

API int osble_poll(osble_event* out, int max) {
  std::lock_guard<std::mutex> lk(g_m);
  int n = 0;
  while (n < max && !g_events.empty()) { out[n++] = g_events.front(); g_events.pop_front(); }
  return n;
}

API int osble_connect(uint64_t addr, int pid) {
  auto p = std::make_shared<Pad>();
  {
    std::lock_guard<std::mutex> lk(g_m);
    p->id = g_nextId++;
    g_pads[p->id] = p;
  }
  p->addr = addr; p->pid = pid;
  std::thread(connectThread, p).detach();
  return p->id;
}

// copy queued 63-byte reports (64-byte stride) into out; returns count
API int osble_reports(int id, uint8_t* out, int max) {
  std::shared_ptr<Pad> p;
  { std::lock_guard<std::mutex> lk(g_m); auto it = g_pads.find(id); if (it == g_pads.end()) return -1; p = it->second; }
  std::lock_guard<std::mutex> lk(p->m);
  int n = 0;
  while (n < max && !p->reports.empty()) { memcpy(out + n * 64, p->reports.front().data, 64); p->reports.pop_front(); n++; }
  return n;
}

API int osble_leds(int id, int pattern) {
  std::shared_ptr<Pad> p;
  { std::lock_guard<std::mutex> lk(g_m); auto it = g_pads.find(id); if (it == g_pads.end()) return 0; p = it->second; }
  if (!p->alive) return 0;
  std::thread([p, pattern] {
    init_apartment(apartment_type::multi_threaded);
    sendCommand(*p, command(0x09, 0x07, { (uint8_t)pattern, 0, 0, 0, 0, 0, 0, 0 }));
  }).detach();
  return 1;
}

API void osble_disconnect(int id) {
  std::shared_ptr<Pad> p;
  {
    std::lock_guard<std::mutex> lk(g_m);
    auto it = g_pads.find(id);
    if (it == g_pads.end()) return;
    p = it->second;
    g_pads.erase(it);
  }
  p->alive = false;
  try { if (p->device) p->device.Close(); } catch (...) {}
}

API void osble_shutdown() {
  try { if (g_watcher) g_watcher.Stop(); } catch (...) {}
  std::vector<int> ids;
  { std::lock_guard<std::mutex> lk(g_m); for (auto& kv : g_pads) ids.push_back(kv.first); }
  for (int id : ids) osble_disconnect(id);
}
