#!/usr/bin/env python3 -I
"""Print ISG1/OSG1/PSG1 signature chunks of DXBC files. Usage: dump_sig.py FILE..."""
import struct, sys
for path in sys.argv[1:]:
    d = open(path, "rb").read()
    n = struct.unpack_from("<I", d, 28)[0]
    print("==", path.split("/")[-1])
    for i in range(n):
        off = struct.unpack_from("<I", d, 32 + 4 * i)[0]
        cc = d[off:off+4].decode(); size = struct.unpack_from("<I", d, off+4)[0]
        c = d[off+8:off+8+size]
        if cc in ("ISG1", "OSG1", "PSG1"):
            cnt, base = struct.unpack_from("<II", c, 0)
            print(" ", cc, cnt)
            for j in range(cnt):
                (stream, nameoff, idx, sysval, comp, reg, mask, rwmask, _, mincp) = struct.unpack_from("<IIIIIIBBHI", c, base + j*32)
                end = c.index(b"\0", nameoff)
                print(f"    {c[nameoff:end].decode()}{idx} reg={reg} sysval={sysval} comp={comp} mask={mask:#x} rw={rwmask:#x} stream={stream}")
        elif cc == "PSV0":
            print("  PSV0 size", size)
