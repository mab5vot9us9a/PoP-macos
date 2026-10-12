# Phase 2 log: Pioneers of Pagonia on Madeira's D3D12 layer (handoff)

Date: 2026-10-12 (sessions 1-3). Continues `PHASE1_BUILD.md`. Read `MADEIRA_PORT_PLAN.md` section "Phase 2" first.

## Status in one paragraph

The game runs on Madeira's D3D12 layer: intro cinematic, main menu at ~60 presents/s, zero
command buffers in error, and as of session 3 (2026-10-12, 19:20) THE TERRAIN RENDERS
COMPLETELY: grass, sand, water, rock, paths, every tile textured (`phase2/win_staged_copy.png`,
`phase2/win_staged_copy2.png`). Two root causes, both fixed: session 2 found that Madeira never
bound Apple's tessellator tables (#9, patch constants garbage); session 3 found that the
engine's terrain pages are BC1 textures filled by a GPU compressor through a
format-reinterpreting texture copy (R32G32_UINT render target -> BC1) that Madeira handed to
Metal's blit unchanged, which cannot do it, so most pages stayed black (#11). A MAP LOADS AND
PLAYS (session 3, 19:30, `phase2/ingame1.png`, `phase2/ingame2.png`): terrain, water, trees,
units, buildings, roads, UI, minimap, the tutorial video in the camera-controls popup (NV12 is
not needed for it), nothing flickers (user-tested: scroll, rotate, zoom, build). The log stays
at `0 skipped`, no `not implemented`, no command buffer errors. In-game frame rate was a steady
~23-26 presents/s at 2560x1347; session 4 (see the last section) measured where the GPU time goes
(tessellation ~40%, 10.6k single-instance plain draws ~40%, grass GS-mesh ~12%) and the cfg now
clamps the terrain hull factor (`dtess-max-factor = 8`, 26 -> 32.5 fps on the reference scene).

## How to run

```bash
# wrapper copy ~/Applications/Steambuild-Madeira.app (Info.plist D3DMETAL=0, D3DMETAL_FORCE=0)
cd ~/Documents/Programming/private/PoP/phase2
WINEDLLOVERRIDES="dxgi,d3d12,d3d12core=n,b;GfnRuntimeSdk=d" ./run_game.sh game   # Steam.exe -applaunch 2155180
./run_game.sh kill                                                               # wineserver -k for the copy
echo 1 > madeira-capture.txt      # while running: capture the next frame (see Diagnostics)
screencapture -x -l $(scratchpad/wincap | awk '/^TARGET/{print $2}') x.png   # grabs the game window; plain screencapture -x is black while the desktop is in use
```

Rules: quit any other Steam instance of the same account first (the working wrapper's Steam
logs the copy out). Steam takes ~30 s to boot, the game ~40 s to the main menu. Logs go to
`phase2/logs/run-<ts>.log` (stderr of every Wine process). `MADEIRA_DOCS_DIR` is set to
`phase2/` by the script, so the runtime reads `phase2/madeira.cfg`, writes captures to
`phase2/capture/`, its DXIL cache to `phase2/shadercache/` (delete it after changing
conversion code, or old conversions are served).

Files in the game folder (`.../steamapps/common/Pioneers of Pagonia/`): Madeira's `d3d12.dll`,
`d3d12core.dll`, DXMT's `dxgi.dll`. `winemetal.dll` (builtin, `lib/wine/x86_64-windows`),
`winemetal.so` + `libmetalirconverter.dylib` (`lib/wine/x86_64-unix`) as in Phase 1.

Rebuild + install after a change (the whole loop is ~1 min build + 2.5 min to the menu):

```bash
M=~/Documents/Programming/private/madeira-src/Madeira; A=~/Applications/Steambuild-Madeira.app
G="$A/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Pioneers of Pagonia"
# PE side (d3d12.dll): writes build/madeira-d3d12/out-pe/, NOT out-macos
cd $M && MADEIRA_PE_ARCH=x86_64 bash build/madeira-d3d12/build-pe.sh && cp build/madeira-d3d12/out-pe/d3d12.dll "$G/" && cp build/madeira-d3d12/out-pe/d3d12.dll build/madeira-d3d12/out-macos/
# unix side (winemetal.so, includes madeira_ir_unix.mm): copy via a temp name, the file is mapped while the game runs
cd $M/dxmt/build-x86_64 && ninja src/winemetal/unix/winemetal.so && cp src/winemetal/unix/winemetal.so "$A/Contents/SharedSupport/wine/lib/wine/x86_64-unix/winemetal.so.new" && mv "$A/Contents/SharedSupport/wine/lib/wine/x86_64-unix/winemetal.so.new" "$A/Contents/SharedSupport/wine/lib/wine/x86_64-unix/winemetal.so"
```

`build/madeira-d3d12/build-macos-x86_64.sh` does everything (now including `dxgi.dll` and the
indirect-mesh kernel) into `out-macos/`.

## What was fixed in Phase 2 (all uncommitted in the Madeira clone; `git status` lists the files)

| # | Symptom | Cause | Fix | Where |
| - | ------- | ----- | --- | ----- |
| 1 | no swapchain possible | Madeira's swapchain is created by DXMT's `dxgi.dll` asking the queue for `IMTLDXGIDevice`; Phase 1 had not built that DLL | `ninja src/dxgi/dxgi.dll`, in the game folder with `dxgi=n,b`; added to `build-macos-x86_64.sh` | dxmt build |
| 2 | launcher forces D3DMetal | `D3DMETAL=1` in Info.plist exports `WINEDLLOVERRIDES=*dxgi,*d3d11,*d3d12=b` | `D3DMETAL=0`, `D3DMETAL_FORCE=0` in the copy's Info.plist; `run_game.sh` launches `wine64` directly | wrapper copy |
| 3 | execute-access page fault at `GfnRuntimeSdk.dll+0x4CE1` right after the engine unloads it (every run) | GeForce NOW SDK thread still running at FreeLibrary; timing-dependent | `GfnRuntimeSdk=d` override | launch env |
| 4 | "No Compatible Graphics Hardware", every box unchecked | winemetal's video budget used the iOS jetsam formula (process limit unknown on macOS → 1 GB); the engine needs 1.5 GB local + 1.75 GB non-local and fails the whole probe | macOS: budget = Metal `recommendedMaxWorkingSetSize`; `madeira.cfg vram-mb` still overrides | `dxmt/src/winemetal/unix/winemetal_unix.c` `madeira_ml1042_video_budget` |
| 5 | "GPU Error 80004001" after the splash | `Evict`/`MakeResident` were E_NOTIMPL stubs | S_OK (unified memory) | `madeira_d3d12.c` device vtable |
| 6 | Metal assertion: 832x512 texture with 12 mips | engine asks for 12 mips on an 832x512 R32G32_UINT transient; E_INVALIDARG (what D3D12 does) makes the engine quit with 80070057 | clamp to the full chain; RTV/SRV levels past the clamp map to the last level | `mad_texinfo_from_desc`, `mad_texture_view`, `mad_resolve_view` |
| 7 | every geometry-shader pipeline failed: `VS(gs): converted library has no function 'vs_main'` | with a separate stage-in function the converter emits the object stage only as `vs_main.dxil_irconverter_object_shader`; the IR runtime links it at pipeline build; a lookup by name is wrong | GS path converts the VS `lib_only`, like the DXIL tessellation path; layout always passed | `device_CreateGraphicsPipelineState` GS branch |
| 8 | `indirect draw on a geometry-shader pipeline is not implemented; skipped` (~2000/min) | mesh pipelines need a threadgroup grid, not a vertex count | CPU-visible records (UPLOAD heaps) are read at replay and run as direct draws; GPU-written records go through a one-thread Metal kernel (`indirect_mesh.metal`, built by `build-pe.sh` into `indirect_mesh_metallib.h` when `xcrun metal` exists) that writes `MTLDispatchThreadgroupsIndirectArguments` + patches the draw info in a 64-byte scratch slot, then `drawMeshThreadgroupsWithIndirectBuffer`; CPU-visible count buffers are honoured | `exec_draw`, `mad_indmesh_init`, winemetal `DrawMeshThreadgroupsIndirect` (object TG memory marker added) |
| 9 | terrain/grass black (session 1's whole investigation); Metal shader validation: ~2000/frame `Invalid load in 'device' or 'constant' address space at GPU address 0x200..0x1248, executing object function vs_main.dxil_irconverter_object_shader` | the converter's emulated hull/tessellator stages read Apple's tessellator tables (`ir_tessellator_tables.h`: counts[64][64][2] u32 + a 701 KB u8 lookup table) from the buffer at `kIRRuntimeTessellatorTablesBindPoint = 7` (object AND mesh stage); Madeira never bound one, so the hull indexed address 0 (`in*512 + out*8`) and all patch constants were garbage | `build-pe.sh` runs `gen-tess-tables.py` (runtime header -> `out-pe/tess_tables.h`, verified byte-identical to a native compile), the device creates one resident shared buffer at init, DXIL tessellation draws bind it at object+mesh buffer 7 (`ml1152`) | `madeira_d3d12.c` device init + `exec_draw` gsemu==2 branch, `build/madeira-d3d12/gen-tess-tables.py` |
| 11 | most terrain tiles black although every page-table record was valid (session 2's leftover) | the "material table" is a PAGE TABLE: blocks of 256 records share three 512x512 BC1 textures (albedo sRGB + two UNORM) plus a world-space UV offset, 14 pages in the menu scene; the engine compresses pages on the GPU into an 832x512 R32G32_UINT render target (the 12-mip transient of #6: one 64-bit texel = one BC1 block) and `CopyTextureRegion`s regions of it into the BC1 textures; Madeira passed the copy to Metal's `copyFromTexture:toTexture:` as-is, which does not copy between an uncompressed and a block-compressed format, so the pages never got written | `exec_copy_reinterpret`: a T2T copy whose two formats differ in block size (bytes per block equal) goes through the device staging buffer (texture->buffer->texture, extents in source texels on the way out and dest texels, scaled by the block size and clamped to the dest mip, on the way in); `exec_copy_aspect` now shares the helper (`exec_copy_staged`) | `madeira_d3d12.c` `exec_copy_staged`, `exec_copy_reinterpret`, T2T branch of `exec_copy` |
| 10 | `MTL_SHADER_VALIDATION=1` crashed: `NSGenericException ... mutated while being enumerated` in `-[MTLToolsResidencySet commit]` | creation threads add to the residency set while the queue thread commits it; MTLResidencySet is not thread-safe | add/remove/commit under one SRW lock (`mad_resset_commit`) | `mad_resident`, `mad_unresident`, both commit sites |

Also added, all env/cfg-gated and upstreamable:

- `MADEIRA_D3D12_TRACE_CAPS=1`: every `CheckFeatureSupport` (feature, size, result words) and device `QueryInterface`.
- `MADEIRA_D3D12_TRACE_COPIES=1`: buffer→texture uploads into BC7_UNORM / array / ≥2048 / single-mip BC1 ≥256 textures (`[copy-trace] b2t`), and every texture→texture copy whose formats differ (`[copy-trace] t2t`, first 400; how #11 was found).
- `MADEIRA_IR_DUMP_LIBS=1`: every converted metallib to `$MADEIRA_DOCS_DIR/madeira-libs/` (how #7 was found: `strings` on them).
- `madeira-capture.txt` in `MADEIRA_DOCS_DIR` (unix side, `_madeira_ctl` op 0): requests a frame capture like the iOS UI does.
- `madeira.cfg capture-tess = 1`: the draw capture (`capture-ps` machinery, ml1106) also takes DXIL tessellation draws with a pixel shader; `capture-rt-w = N`: draws whose first colour target is N wide.
- For converter (DXIL) pipelines the draw capture now prints the whole root layout (`[capture-draw] root pN ...`), the descriptors each table spans with their textures (`[capture-draw] pN[k] view ...`), dumps root CBVs (`cb<N>` raw files), mip 0 of each texture and every slice of ≤16-layer arrays (`s<slice><idx>` files). Before this it only handled DXBC (`ps_air`) pipelines.
- `MADEIRA_D3D12_CS_DUMP=1` also writes every tessellation pipeline's four stages to `C:\madeira-cs\tess_<pso>_{vs,hs,ds,ps}.dxil`; the `[capture-draw] ===== draw` header prints `pso=<ptr>` and every `DXIL tessellation:` reflection line prints its `pso=` too (same run only).
- `madeira.cfg capture-heap-a = N`, `capture-heap-b = M` (re-read at every capture, so they can be set after a first capture has printed the indices): dump heap entries N..N+7, M..M+7; a table with a >16-descriptor range also gets a `[capture-heap] p<N> idx:WxH/layers/dxgi ...` listing of every non-placeholder texture in its first 16384 entries. Root CBV captures are 16 KB.
- `madeira.cfg dtess-max-factor = N` (clamp the hull's max factor), `dtess-vertex-size = N` (override the reflected VS output size for ALL tess pipelines; the terrain's is already 80, so leave unset), `dtess-matprobe = 1` (see "Where it stands now").
- Tools: `phase2/tools/wincap.swift` (window ids for screencapture) and `phase2/tools/classify.py` (page-table record classifier, usage `python3 -I classify.py <run log> <cb raw file>`) are kept in the repo. Scratchpad-only tools (recreate if needed): `psv0.py` (DXBC chunk walker; ISG1/OSG1/PSG1 records are 32 B, PSV0 bind records 24 B), `splice_rts0.py` (serialise a v1.1 root signature as an RTS0 chunk so `metal-shaderconverter` accepts shaders with unbounded arrays; it needs b2 and the space-1000 samplers covered), `lib2ll.sh` (metallib -> textual AIR: slice the bitcode behind the 0x0B17C0DE wrapper, `xcrun metal-opt -S`), `wincap.swift` (lists windows; `screencapture -x -l <id>` grabs the game window even when another app is in front; plain `screencapture -x` returns black when the desktop is in use).
- `build/tools/capture-to-png.py` converts attachments; BC7/BC6 texture dumps decode with the `texture2ddecoder` pip package (venv in the scratchpad was used; recreate: `python3 -m venv v && v/bin/pip install texture2ddecoder pillow numpy`).

`madeira.cfg` keys tried and NOT needed (leave the file with only what you need):
`d3d12-typed-uav-load = 1`, (`d3d12-tiled-resources = 1` is listed as a retest candidate below),
`d3d12-tile-based = 0` (harmless, desktop-like ARCHITECTURE answer, currently set).

## Session 1 investigation (resolved; kept short)

Facts that still hold: the terrain colour pass is a 19/20-param root signature (PS b0,b1[,b2],
s0, t0..t9 as 1-descriptor tables, one 229376-descriptor SRV table at t10 = the whole
shader-visible heap); the PS declares `Texture2D t10..unbounded` (SM 6.0, PSV0) and fetches
`rec = materialCB[INDEX*2..+1]` (32-B records: float4 scale/offset + uint4 of three heap
indices), `tex = t10[rec.x]`; `INDEX` is a flat uint pixel input produced by the hull patch-constant
function and routed through the domain (mesh) stage; heap content, residency, varying names,
descriptor stride and the generated AIR were all verified correct. Heap entry 0 is a 1x1 BLACK
placeholder, so any out-of-range INDEX (bounds-checked to 0) lands on it. The cause was #9. The
"correct geometry, black surface" picture of session 1 (`menu_terrain_grid.png`) was the
converter's degenerate output with zeroed tables, not real tessellation.

## Where it stands now (session 3)

Session 2's handoff question is answered: the 64 KB capture of the colour draw's root CBV b1
(`phase2/capture/f1291_e50751_cb1_65536x1_*.raw`, classifier in the scratchpad `classify.py`:
parse `[capture-heap] p13 idx:WxH/layers/dxgi` into a set, check the three uint indices of each
32-B record) showed 2048 records, ALL pointing at real heap textures, only 14 distinct texture
triples, 256 records per triple, each triple a 512x512 (or 256x256) BC1_UNORM_SRGB + two
BC1_UNORM, with a float4 of (uv scale, uv scale, world offset x, y). So INDEX and the table
were fine; the texture CONTENT was black. `MADEIRA_D3D12_TRACE_COPIES=1` with the new `t2t`
trace then showed ~400 copies `Texture 512x512 fmt71 <- RenderTarget 832x512 fmt17 (R32G32_UINT)
sub N: 128x128 from x,y`, i.e. a GPU BC1 compressor plus reinterpreting copies, per mip. Fix #11.

Verified after the fix: both menu vistas fully textured, `0 skipped` draws, no `sizes differ`
line, 60 presents/s unchanged. `madeira.cfg` is back to `d3d12-tile-based = 0` +
`capture-tess = 1` only; `dtess-matprobe` is no longer needed (leave the code, it is cfg-gated).

Map loaded and played (session 3, 19:30; the user clicked, Claude watched the log). Nothing
wrong found. Next milestone: PERFORMANCE. The menu runs at 60 presents/s, the map at a very
steady 22-23 (measure: `grep "Present #" log | tail`, the line is printed every 16 presents, fps =
delta presents / delta t). Starting points: the per-list stats (`list executed: N commands, M
draws`, ~500-draw lists, ~8800 draws per frame), `perf-log` in madeira.cfg, `pso-parallel`,
`async-submit`, `fence-chain` (the cfg keys the runtime reads are listed in PHASE1_BUILD.md), and
Instruments / Metal System Trace on the wine64 process to see whether the GPU or the CPU replay
thread is the limit. The steadiness of 23 suggests a CPU-side cap (command recording or replay),
not GPU load.

## Other open items

- NV12 (format 103) has no Metal mapping; the engine only asks for format support at start-up, the tutorial clip in the camera-controls popup plays fine, so no in-game video needed it so far.
- The 832x512 12-mip transient of #6 is explained by #11: it is the GPU texture compressor's output, sized for the BC1 chain of the biggest page (the 1024x1024 texture has 11 levels... the engine asks for 12 anyway; the clamp works, the copies only use levels 0-4).
- The indirect-draw scratch ring is 1024 slots with no fence; fine for this game, note it upstream.
- `[iOS DXMT] Present` and the census lines are chatty.
- `docs/MACOS_X86_64.md` in the clone has a short "Running a game" section; update it with #7/#8
  when upstreaming.

## Files

| What | Where |
| ---- | ----- |
| launch script, cfg, trigger file, logs, captures | `phase2/run_game.sh`, `phase2/madeira.cfg`, `phase2/madeira-capture.txt`, `phase2/logs/`, `phase2/capture/` |
| screenshots | `phase2/intro_screenshot.png` (first render), `phase2/menu_terrain_grid.png` (session 1 state), `phase2/bc_off.png`, `phase2/tess_tables_fix.png` (first textured terrain), `phase2/win_vsize80.png`, `phase2/win_nooverride.png` (current state), `phase2/win_matprobe.png` (probe), `phase2/win_cb64.png` (session 3 before #11), `phase2/win_staged_copy.png` + `phase2/win_staged_copy2.png` (terrain complete), `phase2/ingame1.png` + `phase2/ingame2.png` (map loaded, playing), `phase2/terrain_ps_inputs.png`, `phase2/shadow_filter_2048.png` |
| patches of every uncommitted change (session 3 state; regenerate after further changes, see `reproduce2.md` B2) | `phase2/patches/madeira.patch`, `phase2/patches/dxmt.patch` |
| Madeira changes | `madeira-d3d12/src/pe/madeira_d3d12.c`, `madeira-d3d12/src/pe/indirect_mesh.metal` (new), `build/madeira-d3d12/gen-tess-tables.py` (new), `build/madeira-d3d12/build-pe.sh`, `build/madeira-d3d12/build-macos-x86_64.sh`, `madeira-d3d12/src/unix/madeira_ir_unix.mm`, `docs/MACOS_X86_64.md`; dxmt submodule: `src/winemetal/unix/winemetal_unix.c` (+ Phase 1 files) |

## Session 4 (2026-10-12 evening): performance

Measurement method (all in the runtime's own `[perf]` block, every 5 s, no Instruments needed):

- `ml1108`: fps, `gpu_busy` (union of command-buffer GPU intervals), per-frame GPU ms.
- `ml1119`: caller-thread ms per frame in ExecuteCommandLists (the replay runs on the caller
  unless `async-submit = 1`) and in Present.
- NEW `ml1160` (this session): draw-kind census per frame: plain draws (+ instances), GS-emulation
  mesh draws (+ indirect, object threadgroups), DXIL tessellation draws (+ indirect, object
  threadgroups), DXBC tessellation draws, dispatches.
- NEW `ml1161`: `madeira.cfg diag-skip = <mask>` is RE-READ every 5 s while the game runs: 1 skips
  plain draws, 2 GS-mesh draws, 4 DXIL tessellation draws, 8 dispatches. Attribution experiment
  (the picture breaks accordingly); set it back to 0 afterwards.
- `madeira.cfg encoder-labels = 1` + `xcrun xctrace record --template 'Metal System Trace' --attach
  <pid>` works through Wine, but two thirds of the GPU intervals carry no process/command buffer
  (cmdbuffer 0, "Frame 0"; at the game's frame cadence, likely the object/mesh kicks) so the
  per-encoder attribution was abandoned. Parser kept in the scratchpad (`gpuagg.py`: export the
  `metal-gpu-intervals`, `metal-application-encoders-list`, `metal-gpu-submission-to-command-buffer-id`
  tables with `xctrace export --xpath`, resolve the `ref=` ids, join submission id -> encoder id ->
  label; ids must be compared on the raw text, not `fmt`).

Reference scene: the autosave loaded with "Continue", camera untouched. 2560x1347, M2 Pro.

| Configuration | fps | GPU ms/frame | notes |
| --- | --- | --- | --- |
| baseline (session 3 build) | 26.4 | 37.6 | GPU 99-100% busy; caller thread ECL 11 ms + Present 16 ms |
| `dtess-max-factor = 8` | 32.5 | 30.5 | menu terrain looks identical; in-game not yet compared closely |
| + `diag-skip = 4` (no tessellation draws) | 50 | 18.2 | tessellation = ~12 ms at factor 8 (~19 ms at 64) |
| + `diag-skip = 1` (no plain draws) | 53 | 18.7 | plain draws = ~12 ms |
| + `diag-skip = 2` (no GS-mesh draws) | 36.6 | 27.1 | GS-mesh (grass etc.) = ~3.5 ms |
| + `diag-skip = 15` (nothing drawn) | 60 | 1.5 | passes, clears, load/store, copies cost nothing |

Draw census of that scene per frame: ~10,600 plain draws, EVERY one single-instance (the engine
does not instance); ~155 GS-mesh draws (~620 object TGs); ~358 DXIL tessellation draws with
~13,480 object threadgroups = ~430k single-point patches per frame (terrain tiles of ~1024
patches, drawn again for the shadow cascades), max factor 64 in the hull.

Conclusions so far: the ~1 GB/frame attachment load/store from the ml1137 census is NOT a cost
(1.5 ms with nothing drawn). The GPU time is real shading work: tessellation emulation scales
with the factor; the plain draws are ~1.1 us of GPU each (shadow cascades at 2048x2048, main
pass, a 1280x673 pass). The main-menu "stag statue" vista (dense grass) is a click-free ~45 ms
GPU benchmark; the lake vista is 2-4 ms. In that menu vista the CPU is the limit instead: the
replay on the caller thread (`ExecuteCommandLists` 17 ms/frame) with the GPU at 48%.

Tried and rejected (restart with both, user then played, so not a controlled A/B, but the
counters are unambiguous): `fence-chain = 6` overlaps only 1-2 of ~55 encoders per frame
(ml1134: "53.9 synced"), because the engine issues a ResourceBarrier between almost every pair of
passes; `async-submit = 1` zeroes the caller's ExecuteCommandLists/Present time but the game
thread then blocks in fence waits for the same duration (ml1109), frame time == GPU time either
way. Controlled sample after the user reloaded the save in that run (same camera, same draw census):
26.0 fps / 38.4 ms GPU versus 32.5 / 30.5 with factor 8 alone, i.e. fence-chain 6 COSTS ~8 ms: it
runs 88 encoders per frame instead of ~60 (ml1116: 117 fence waits), 87 of them synced anyway.
Both back to default. `madeira.cfg` now carries `dtess-max-factor = 8` (the only win so far,
~20% GPU) and `diag-skip = 0`.

Next steps, in order of expected value:
1. Confirm visually (user) that terrain at factor 8 is acceptable in-game; try 4 for the slope.
2. Per-draw cost of the 10.6k plain draws (12 ms GPU, 11 ms CPU replay): elide redundant per-draw
   state (same PSO/viewport/scissor/vertex buffers as the previous draw of the encoder) and
   measure; the argument tables (`mad_air_build_tables`) are rebuilt per draw too.
3. The GS-mesh path (grass, 3.5 ms) is the smallest item.
4. In-game resolution is a game setting; the fragment share of the plain draws scales with it.

Build/install of this session's d3d12.dll (ml1160 census, ml1161 diag-skip): as in "How to run".
Tools added: `phase2/tools/click.swift` (CGEvent clicks/keys; unused, the user clicks), scratchpad
`fps.sh` (ml1108 summary), `gputrace.sh` + `gpuagg.py` (xctrace capture + aggregation).

Later in session 4 (the autosave had moved, so a new reference view, `phase2/ref_session4.png`,
20.9 fps / 47.7 ms GPU, ExecuteCommandLists 12.0 ms; tessellation ~30 ms of it at factor 8):

- NEW `ml1162` state elision (`madeira.cfg state-elide = 0` disables): a draw repeats only the
  render state that changed since the previous draw of its encoder (PSO, viewport, scissor, the
  16 vertex-buffer binds of the MSC path, depth-stencil state + stencil ref, blend factor,
  rasterizer state). `[perf] ml1162 render commands per frame: N encoded, M elided`. In-game 41%
  of the render commands go away; ExecuteCommandLists 12.0 -> ~9 ms per frame at a similar view.
  Implementation: `e->st` in `struct mad_exec` holds the state last encoded on `e->renc`; the
  draw chain now starts at `head` (first appended node) instead of always at `c_pso`; a draw that
  returns between building the chain and encoding it leaves `st_pending` set, which invalidates
  the cache at the next draw.
- NEW `diag-skip` bits 16 (tessellation draws into depth-only passes) and 32 (tessellation draws
  with a colour target). At one still view (33.2 ms GPU): bit 16 -> 24.0 ms, bit 32 -> 23.1 ms.
  The census showed the shadow pass is ONE tessellation draw of ~231k patches (7232 object TGs)
  per frame, the colour pass ~116 draws / ~50k patches. So the depth-only terrain costs ~9 ms and
  the colour terrain (incl. its pixel shading) ~10 ms.
- NEW `madeira.cfg dtess-depth-max-factor = N` (`ml1163`): max-factor clamp applied only to
  tessellation pipelines created with NumRenderTargets == 0 (the shadow-map PSOs). Set to 2.
  Result at the SAME still view (identical census, 6.3k plain / 117 tess draws / 8792 TGs):
  33.2 ms -> 27.0 ms GPU, 30.0 -> 36.9 fps; `phase2/depth_factor2.png` vs the same view before
  (`scratch skip16`): tree and hut shadows intact, no visible change. Where this view started the
  session (20.9 fps / 47.7 ms with the session-3 build at factor 64) it is now ~37 fps.

Session 4 end state of `madeira.cfg`: `dtess-max-factor = 8`, `dtess-depth-max-factor = 2`,
`diag-skip = 0`, `d3d12-tile-based = 0`, `capture-tess = 1`. State elision is on by default.

Remaining levers (not done): `dtess-max-factor = 4` for the colour pass (user to judge the
terrain), `dtess-depth-max-factor = 1`; the 6-10k single-instance plain draws (~12 ms GPU, now
~6-9 ms CPU replay); `mad_air_build_tables` still rebuilds both argument tables per draw (next CPU
item); the GS-mesh grass path (~3.5 ms).
Factor 4 (colour) + 1 (depth), same view as the 36.3 fps / 27.4 ms reading before it: 37.4 fps /
26.5 ms, i.e. ~1 ms. The terrain's remaining colour cost is its pixel shading, not the factor.
Cfg set back to 8 / 2 for the next launch (the running game still has 4 / 1).

Argument-table caching: NOT needed. The 10k plain draws use the DXIL (MSC) path, whose per-draw
table is only the 1088-byte root-layout ring slot (`exec_arg_slot_for`); `mad_air_build_tables`
serves the DXBC and tessellation paths. NEW `[perf] ml1164 exec_draw caller ms per frame` (four
rdtsc phases; Rosetta reports a 1 GHz tsc, calibrated against wall each period) showed where the
replay time goes: menu vista with 22k draws, ExecuteCommandLists 15 ms = encode (the per-draw
winemetal `encodeCommands` bridge call and its Metal calls) 11.3 ms, root slot + chain build 1.2,
begin_render 0.9, use loops 0.1. In-game ~0.5 us per draw in the bridge, ~0.1-0.3 us chain build.
Cutting it further needs batching several draws per bridge call (chain nodes in an arena, flushed
at exec_end / before any other encodeCommands on the encoder) and offset-only binds
(`WMTRenderCommandSet*BufferOffset`) for the ring-slot buffers (indices 2, 4, 5 are the same chunk
for ~900 consecutive draws). Not done: at every heavy view the caller thread finishes its ~9 ms and
then waits for the GPU in Present, so CPU work is no longer on the critical path.

GPU floor reached for cfg-level work. The remaining GPU frame (~27 ms at the session-4 reference
view) is real shading: plain draws ~12 ms (Instruments: fragment ~10 ms/frame = 2048x2048 shadow
cascades 3.4 + main pass 4 + a 1280x673 pass 2.7, vertex 3.5), terrain colour pass ~10 ms (pixel
shading, not factor-bound: factor 8 -> 4 saved ~1 ms), grass GS-mesh ~3.5 ms. The in-game graphics
settings (shadow quality/resolution, resolution scale) are now the cheapest lever and are the
user's call; on the layer side the next candidates are the bridge batching above (CPU only) and
checking the converter's pixel-shader output for avoidable cost (GPU).

Visual check by the user (2026-10-12 evening): terrain at `dtess-max-factor = 4` with
`dtess-depth-max-factor = 1` shows no difference to their eye; cfg keeps 4 / 1.

In-game shadow quality (user changed it live, same view, ~9.1k plain / 231 tess draws):
high 37.5 fps / 26.6 ms GPU, medium 41.0 / 24.3, low 42.4 / 23.5. Medium is the sweet spot; the
cascades still draw every object at every level. Render resolution / resolution scale is the
remaining game-side lever for the ~20 ms of pixel shading.
The game has no resolution-scale option (user checked); only the display resolution itself
could lower the pixel count. Session 4 closed here: shadows on low, cfg 4 / 1, ~42 fps at the
settlement view. The user considers this state workable.
