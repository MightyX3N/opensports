// Godot binding for osble (native/osble/osble.cpp): the Bluetooth LE bridge for Joy-Con 2 /
// Pro Controller 2 on Windows. Built as a GDExtension (godot-cpp) so the Godot game can scan,
// connect and read the controllers' input reports. GPL-3.0 as part of Open Sports.
#include "../../osble/osble.cpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class OSBLE : public RefCounted {
  GDCLASS(OSBLE, RefCounted)

protected:
  static void _bind_methods() {
    ClassDB::bind_static_method("OSBLE", D_METHOD("version"), &OSBLE::version);
    ClassDB::bind_static_method("OSBLE", D_METHOD("scan", "on"), &OSBLE::scan);
    ClassDB::bind_static_method("OSBLE", D_METHOD("poll"), &OSBLE::poll);
    ClassDB::bind_static_method("OSBLE", D_METHOD("connect_pad", "addr", "pid"), &OSBLE::connect_pad);
    ClassDB::bind_static_method("OSBLE", D_METHOD("reports", "id"), &OSBLE::reports);
    ClassDB::bind_static_method("OSBLE", D_METHOD("leds", "id", "pattern"), &OSBLE::leds);
    ClassDB::bind_static_method("OSBLE", D_METHOD("disconnect_pad", "id"), &OSBLE::disconnect_pad);
    ClassDB::bind_static_method("OSBLE", D_METHOD("shutdown"), &OSBLE::shutdown);
  }

public:
  static int version() { return osble_version(); }
  static int scan(bool on) { return osble_scan(on ? 1 : 0); }

  // events since the last call: [{ type, id, addr, pid, rssi, text }]
  static Array poll() {
    Array out;
    osble_event ev[32];
    int n = osble_poll(ev, 32);
    for (int i = 0; i < n; i++) {
      Dictionary d;
      d["type"] = ev[i].type;
      d["id"] = ev[i].id;
      d["addr"] = (int64_t)ev[i].addr;
      d["pid"] = ev[i].pid;
      d["rssi"] = ev[i].rssi;
      d["text"] = String::utf8(ev[i].text);
      out.push_back(d);
    }
    return out;
  }

  static int connect_pad(int64_t addr, int pid) { return osble_connect((uint64_t)addr, pid); }

  // queued 64-byte reports (63 bytes + a kind byte) as one PackedByteArray each
  static Array reports(int id) {
    Array out;
    static uint8_t buf[64 * 64];
    int n = osble_reports(id, buf, 64);
    for (int i = 0; i < n; i++) {
      PackedByteArray p;
      p.resize(64);
      memcpy(p.ptrw(), buf + i * 64, 64);
      out.push_back(p);
    }
    return out;
  }

  static int leds(int id, int pattern) { return osble_leds(id, pattern); }
  static void disconnect_pad(int id) { osble_disconnect(id); }
  static void shutdown() { osble_shutdown(); }
};

} // namespace godot

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

static void initialize(godot::ModuleInitializationLevel level) {
  using namespace godot;
  if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
  GDREGISTER_CLASS(OSBLE);
}
static void uninitialize(godot::ModuleInitializationLevel level) {
  using namespace godot;
  if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
  osble_shutdown();
}

extern "C" GDExtensionBool GDE_EXPORT osble_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
    const GDExtensionClassLibraryPtr library, GDExtensionInitialization* init) {
  godot::GDExtensionBinding::InitObject init_obj(get_proc_address, library, init);
  init_obj.register_initializer(initialize);
  init_obj.register_terminator(uninitialize);
  init_obj.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
  return init_obj.init();
}
