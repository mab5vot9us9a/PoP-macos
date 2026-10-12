#!/usr/bin/env python3 -I
"""Pair hull shaders with vertex shaders (VS OSG1 == HS ISG1), domain shaders
(DS ISG1 == HS OSG1 and DS PSG1 == HS PSG1), and pixel shaders (PS ISG1 minus
system values is a subset of DS OSG1). Usage: pair_shaders.py SHADER_DIR"""
import glob, os, struct, sys

def sigs(path):
    d = open(path, "rb").read()
    n = struct.unpack_from("<I", d, 28)[0]
    out = {}
    for i in range(n):
        off = struct.unpack_from("<I", d, 32 + 4 * i)[0]
        cc = d[off:off+4].decode(); size = struct.unpack_from("<I", d, off+4)[0]
        c = d[off+8:off+8+size]
        if cc in ("ISG1", "OSG1", "PSG1"):
            cnt, base = struct.unpack_from("<II", c, 0)
            s = set()
            for j in range(cnt):
                (stream, nameoff, idx, sysval, comp, reg, mask, rwmask, _, mincp) = struct.unpack_from("<IIIIIIBBHI", c, base + j*32)
                end = c.index(b"\0", nameoff)
                name = c[nameoff:end].decode()
                s.add((name, idx, sysval, mask))
            out[cc] = frozenset(s)
    return out

def user(sig):  # drop system values
    return frozenset(x for x in sig if x[2] == 0)

d = sys.argv[1]
def load(kind):
    return {os.path.basename(p): sigs(p) for p in sorted(glob.glob(os.path.join(d, f"*_{kind}6_0.dxbc")))}
VS, HS, DS, PS = load("vs"), load("hs"), load("ds"), load("ps")
for h, hs in HS.items():
    print("HS", h)
    vs_m = [v for v, s in VS.items() if user(s.get("OSG1", frozenset())) == user(hs["ISG1"])]
    ds_m = [x for x, s in DS.items() if user(s.get("ISG1", frozenset())) == user(hs["OSG1"]) and user(s.get("PSG1", frozenset())) == user(hs["PSG1"])]
    print("  VS:", vs_m or "NONE")
    print("  DS:", ds_m or "NONE")
    for x in ds_m:
        dso = user(DS[x]["OSG1"])
        ps_m = [p for p, s in PS.items() if user(s.get("ISG1", frozenset())) and user(s["ISG1"]) <= dso]
        print(f"    PS for {x}: {len(ps_m)} candidates, first: {ps_m[:2]}")

# Emit one line per (VS, HS, DS, PS) combination, up to 2 PS per DS, to pairs.tsv
with open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "pairs.tsv"), "w") as out:
    for h, hs in HS.items():
        vs_m = [v for v, s in VS.items() if user(s.get("OSG1", frozenset())) == user(hs["ISG1"])]
        ds_m = [x for x, s in DS.items() if user(s.get("ISG1", frozenset())) == user(hs["OSG1"]) and user(s.get("PSG1", frozenset())) == user(hs["PSG1"])]
        for v in vs_m:
            for x in ds_m:
                dso = user(DS[x]["OSG1"])
                ps_m = [p for p, s in PS.items() if user(s.get("ISG1", frozenset())) and user(s["ISG1"]) <= dso][:2]
                for p in ps_m or ["NONE"]:
                    out.write(f"{v}\t{h}\t{x}\t{p}\n")
