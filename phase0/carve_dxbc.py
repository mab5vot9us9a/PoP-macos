#!/usr/bin/env python3 -I
"""Carve DXBC containers (DXIL shaders) out of arbitrary binary files.

Usage: python3 -I carve_dxbc.py OUT_DIR FILE [FILE...]

Treats inputs as untrusted. Writes each valid container to
OUT_DIR/<srcname>_<offset:#x>_<type>.dxbc and an inventory.tsv.
"""
import mmap, os, struct, sys

SHADER_TYPES = {0: "ps", 1: "vs", 2: "gs", 3: "hs", 4: "ds", 5: "cs",
                6: "lib", 7: "rgs", 8: "int", 9: "ah", 10: "ch", 11: "miss",
                12: "call", 13: "ms", 14: "as"}
MAX_SIZE = 16 * 1024 * 1024


def parse_container(mm, off):
    """Return (total_size, chunks{fourcc: (data_off, size)}) or None."""
    if off + 32 > len(mm):
        return None
    total = struct.unpack_from("<I", mm, off + 24)[0]
    nchunks = struct.unpack_from("<I", mm, off + 28)[0]
    if total < 32 or total > MAX_SIZE or off + total > len(mm) or nchunks > 64:
        return None
    if 32 + 4 * nchunks > total:
        return None
    chunks = {}
    for i in range(nchunks):
        coff = struct.unpack_from("<I", mm, off + 32 + 4 * i)[0]
        if coff + 8 > total:
            return None
        fourcc = bytes(mm[off + coff: off + coff + 4])
        csize = struct.unpack_from("<I", mm, off + coff + 4)[0]
        if coff + 8 + csize > total:
            return None
        try:
            name = fourcc.decode("ascii")
        except UnicodeDecodeError:
            return None
        if not name.isprintable():
            return None
        chunks[name] = (off + coff + 8, csize)
    return total, chunks


def shader_type(mm, chunks):
    for key in ("DXIL", "SHDR", "SHEX"):
        if key in chunks:
            doff, dsize = chunks[key]
            if dsize < 4:
                return "?"
            ver = struct.unpack_from("<I", mm, doff)[0]
            if key == "DXIL":
                t = (ver >> 16) & 0xFFFF
                major, minor = (ver >> 4) & 0xF, ver & 0xF
            else:
                t = (ver >> 16) & 0xFFFF
                major, minor = (ver >> 4) & 0xF, ver & 0xF
            return f"{SHADER_TYPES.get(t, 't%d' % t)}{major}_{minor}{'' if key == 'DXIL' else '_dxbc'}"
    return "nocode"


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    inv = open(os.path.join(out_dir, "inventory.tsv"), "a")
    for path in sys.argv[2:]:
        src = os.path.basename(path)
        counts = {}
        with open(path, "rb") as f:
            mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
            pos = 0
            while True:
                pos = mm.find(b"DXBC", pos)
                if pos < 0:
                    break
                parsed = parse_container(mm, pos)
                if parsed is None:
                    pos += 4
                    continue
                total, chunks = parsed
                st = shader_type(mm, chunks)
                name = f"{src}_{pos:#x}_{st}.dxbc"
                with open(os.path.join(out_dir, name), "wb") as o:
                    o.write(mm[pos:pos + total])
                inv.write(f"{src}\t{pos:#x}\t{total}\t{st}\t{','.join(chunks)}\t{name}\n")
                counts[st] = counts.get(st, 0) + 1
                pos += total
            mm.close()
        print(f"{src}: {sum(counts.values())} containers {dict(sorted(counts.items()))}", flush=True)
    inv.close()


if __name__ == "__main__":
    main()
