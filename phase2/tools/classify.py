import sys, struct, re, collections
log, cb = sys.argv[1], sys.argv[2]
heap = {}
for line in open(log, errors='replace'):
    if line.startswith('[capture-heap] p13 '):
        for m in re.finditer(r'(\d+):(\d+)x(\d+)/(\d+)/(\d+)', line):
            heap[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
print('heap listing entries (real textures):', len(heap), 'max idx', max(heap) if heap else None)
d = open(cb, 'rb').read()
n = len(d)//32
cls = collections.Counter(); first_bad = None; runs = []
prev = None
for k in range(n):
    sx,sy,ox,oy, a,b,c,w = struct.unpack_from('<4f4I', d, k*32)
    if (a,b,c,w)==(0,0,0,0) and sx==sy==ox==oy==0: tag='zero'
    else:
        ok = [i in heap for i in (a,b,c)]
        tag = 'real' if all(ok) else ('partial' if any(ok) else 'absent')
    cls[tag]+=1
    if tag != prev: runs.append([k, tag, (a,b,c,w)]); prev = tag
print('records:', n, dict(cls))
for r in runs[:60]: print('  from %4d: %-7s first=%s' % (r[0], r[1], r[2]))
