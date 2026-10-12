# gpuagg.py <trace.trace> [topN]: GPU time per channel and per encoder label (joined via submission ids)
import sys, subprocess, xml.etree.ElementTree as ET, collections, re
trace = sys.argv[1]; topn = int(sys.argv[2]) if len(sys.argv) > 2 else 40
def table(schema):
    xml = subprocess.run(["xcrun","xctrace","export","--input",trace,"--xpath",
        f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'], capture_output=True, text=True).stdout
    root = ET.fromstring(xml)
    cols = [c.find('mnemonic').text for c in root.iter('col')]
    ids = {}
    def reg(el):
        for sub in el.iter():
            if 'id' in sub.attrib: ids[sub.attrib['id']] = sub
    def val(el):
        if 'ref' in el.attrib: el = ids[el.attrib['ref']]
        if el.tag in ('metal-command-buffer-id','uint64','metal-encoder-id'): return (el.text or '').strip()
        return el.attrib.get('fmt', el.text)
    out = []
    for row in root.iter('row'):
        reg(row)
        cells = [c for c in row if c.tag != 'sentinel']
        # sentinels are empty cells; rebuild with positions
        d = {}; i = 0
        for c in row:
            if i >= len(cols): break
            d[cols[i]] = None if c.tag == 'sentinel' else val(c); i += 1
        out.append(d)
    return out
def ms(s):
    if not s: return 0.0
    v, u = s.split(); v = float(v)
    return v/1000 if u in ('µs','us') else v*1000 if u == 's' else v/1e6 if u == 'ns' else v
enc_label = {}
for r in table("metal-application-encoders-list"):
    enc_label[r['encoder-id']] = r['encoder-label']
sub2enc = {}
for r in table("metal-gpu-submission-to-command-buffer-id"):
    sub2enc[r['gpu-submission-id']] = r['encoder-id']
rows = table("metal-gpu-intervals")
by_chan = collections.Counter(); n_chan = collections.Counter(); by_label = collections.Counter(); n_label = collections.Counter()
tmin = None; tmax = 0
for d in rows:
    if d.get('event-depth') != '0': continue
    dur = ms(d['duration']); chan = d['channel-name']
    st = int(re.sub(r'\D','', d['start'] or '0')) if False else None
    by_chan[chan] += dur; n_chan[chan] += 1
    lab = enc_label.get(sub2enc.get(d['gpu-submission-id'], ''), '?')
    # collapse the sequence number: "R#123 vs|ps WxH" -> "R vs|ps WxH"
    key = (chan, re.sub(r'^([RCB])#\d+', r'\1', lab or '?'))
    by_label[key] += dur; n_label[key] += 1
tot = sum(by_chan.values())
print("intervals", len(rows), "top-level GPU ms (channels overlap):", round(tot,1))
for c, m in by_chan.most_common(): print(f"  {c:10s} {m:9.1f} ms  n={n_chan[c]}")
print(f"top {topn} encoders by label:")
for k, m in by_label.most_common(topn): print(f"  {m:9.1f} ms n={n_label[k]:6d} avg={m/n_label[k]:.3f}  {k[0]:9s} {k[1]}")
