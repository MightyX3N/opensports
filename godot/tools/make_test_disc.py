"""Builds a small, valid Wii disc image (.iso and .wbfs) from a folder of files, to test the
game's disc reader without a real disc. The layout follows Dolphin's DiscIO: the partition
table at 0x40000, a ticket whose title key is encrypted with the common key, and data in
0x8000-byte clusters (0x400 hash area holding the IV at 0x3D0, then 0x7C00 encrypted bytes).

    python3 make_test_disc.py <folder> <out.iso> <out.wbfs>
"""
import os, struct, sys
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

COMMON_KEY = bytes([0xeb, 0xe4, 0x2a, 0x22, 0x5e, 0x85, 0x93, 0xe4, 0x48, 0xd9, 0xc5, 0x45, 0x73, 0x81, 0xaa, 0xf7])
TITLE_KEY = bytes(range(16, 32))
TITLE_ID = bytes([0, 1, 0, 0, 0x53, 0x50, 0x32, 0x50])  # 00010000 "SP2P"
PART_OFF = 0x50000
DATA_OFF = 0x20000  # inside the partition


def aes_cbc(key, iv, data, enc=True):
    c = Cipher(algorithms.AES(key), modes.CBC(iv))
    x = c.encryptor() if enc else c.decryptor()
    return x.update(data) + x.finalize()


def build_partition_data(root):
    # file system: a tree from the folder
    entries, names = [], bytearray(b"\0")
    blobs = []
    def add_dir(path, parent):
        items = sorted(os.listdir(path))
        for it in items:
            full = os.path.join(path, it)
            name_off = len(names); names.extend(it.encode() + b"\0")
            if os.path.isdir(full):
                idx = len(entries); entries.append([1, name_off, parent, 0])
                add_dir(full, idx)
                entries[idx][3] = len(entries)
            else:
                data = open(full, "rb").read()
                entries.append([0, name_off, len(blobs), len(data)]); blobs.append(data)
    entries.append([1, 0, 0, 0])
    add_dir(root, 0)
    entries[0][3] = len(entries)
    fst_size = len(entries) * 12 + len(names)
    fst_off = 0x2440
    pos = (fst_off + fst_size + 0x7FFF) & ~0x7FFF
    offsets = []
    for b in blobs:
        offsets.append(pos); pos = (pos + len(b) + 0x1F) & ~0x1F
    part = bytearray(pos)
    for b, o in zip(blobs, offsets):
        part[o:o + len(b)] = b
    fst = bytearray()
    for t, n, a, s in entries:
        if t == 0:
            a = offsets[a] >> 2
        fst += struct.pack(">I", (t << 24) | n) + struct.pack(">II", a, s)
    fst += names
    part[fst_off:fst_off + len(fst)] = fst
    part[0:6] = b"SP2P01"
    struct.pack_into(">I", part, 0x18, 0x5D1C9EA3)
    struct.pack_into(">II", part, 0x424, fst_off >> 2, len(fst) >> 2)
    return bytes(part)


def main(root, iso_path, wbfs_path):
    part = build_partition_data(root)
    nblocks = (len(part) + 0x7BFF) // 0x7C00
    part = part + bytes(nblocks * 0x7C00 - len(part))
    enc = bytearray()
    for i in range(nblocks):
        head = bytearray(0x400)
        iv = bytes((i * 7 + k) & 0xFF for k in range(16))
        head[0x3D0:0x3E0] = iv  # (real discs hold hashes here; the IV is what readers use)
        enc += head + aes_cbc(TITLE_KEY, iv, part[i * 0x7C00:(i + 1) * 0x7C00])
    disc = bytearray(PART_OFF + DATA_OFF)
    disc[0:6] = b"SP2P01"
    struct.pack_into(">I", disc, 0x18, 0x5D1C9EA3)
    disc[0x20:0x20 + 30] = b"Wii Sports + Wii Sports Resort"
    struct.pack_into(">II", disc, 0x40000, 1, 0x40020 >> 2)
    struct.pack_into(">II", disc, 0x40020, PART_OFF >> 2, 0)
    ticket = bytearray(0x2A4)
    ticket[0x1BF:0x1CF] = aes_cbc(COMMON_KEY, TITLE_ID + bytes(8), TITLE_KEY)
    ticket[0x1DC:0x1E4] = TITLE_ID
    ticket[0x1F1] = 0
    disc[PART_OFF:PART_OFF + 0x2A4] = ticket
    struct.pack_into(">II", disc, PART_OFF + 0x2B8, DATA_OFF >> 2, len(enc) >> 2)
    disc += enc
    open(iso_path, "wb").write(disc)
    # WBFS: 512-byte "hd sectors", 2 MiB blocks
    hd_shift, wb_shift = 9, 21
    bsize = 1 << wb_shift
    blocks_per_disc = (143432 * 2 * 0x8000 + bsize - 1) // bsize
    nb = (len(disc) + bsize - 1) // bsize
    out = bytearray(bsize)  # block 0: header and disc info
    out[0:4] = b"WBFS"
    out[9] = wb_shift; out[8] = hd_shift
    out[12] = 1
    info = 1 << hd_shift
    out[info:info + 0x100] = disc[:0x100]
    # store disc blocks in reverse order, so a reader that ignores the table would fail
    for i in range(nb):
        mapped = nb - i
        struct.pack_into(">H", out, info + 0x100 + i * 2, mapped)
    out += bytes(nb * bsize)
    for i in range(nb):
        mapped = nb - i
        chunk = disc[i * bsize:(i + 1) * bsize]
        out[mapped * bsize:mapped * bsize + len(chunk)] = chunk
    total = len(out) // (1 << hd_shift)
    struct.pack_into(">I", out, 4, total)
    open(wbfs_path, "wb").write(out)
    print("wrote", iso_path, len(disc), wbfs_path, len(out))


if __name__ == "__main__":
    main(*sys.argv[1:4])
