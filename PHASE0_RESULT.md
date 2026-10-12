# Phase 0 result: Pagonia's hull shaders through the Metal Shader Converter standalone

Date: 2026-10-12. Machine: Apple M2 Pro, macOS 27.0.1 (26A434), Xcode 27.0.
Converter: Metal Shader Converter 4.0 beta 2, `metal-irconverter version: 4.0.1`, installed at
`/usr/local/{bin,lib,include}` (pkg SHA-256 `1acc33c8…5734`, from the GPTK 4.0 beta 2 DMG).

## Verdict: GO. The converter is not the blocker; D3DMetal's driving of it is.

Every hull shader in the game converts, loads, and links into a complete tessellation-emulation mesh
pipeline (stage-in + VS object stage, hull + tessellator, domain + passthrough mesh stage, pixel
stage) on this machine. That holds for:

| Variant                                                               | Pipelines built | Failures                        |
| --------------------------------------------------------------------- | --------------- | ------------------------------- |
| installed universal converter, Metal 3 API (`newRenderPipelineStateWithMeshDescriptor`) | 62 / 66 | 4, all one PS, see below |
| installed converter, Metal 4 API (`MTL4Compiler`), what `D3DM_MTL4=1` uses | 62 / 66 | same 4 |
| **D3DMetal's own embedded converter** (`D3DMetal.framework/Resources/libmetalirconverter.dylib`, x86_64, harness built for x86_64 under Rosetta), Metal 3 | 62 / 66 | same 4 |
| D3DMetal's embedded converter, Metal 4 API                             | 62 / 66         | same 4                          |
| depth-only pipelines (no pixel shader) for the one DS that only outputs SV_Position, all four variants | 2 / 2 | none |

The four failures are the same pixel shader (`0xde16ebe`) in every run: `Unbounded arrays require
specifying a root signature`. That is a bindless pixel shader needing the engine's root signature,
which the harness does not have (it compiles with the converter's linear resource layout). It is not a
hull or domain problem. The pairing with that PS was a guess anyway; the DS in question also builds
with another PS.

So the `Failed to materializeAll` error D3DMetal logs for `irconverter_hull_shader` is not a property
of the shaders or of the converter library. It comes from how D3DMetal assembles the pipeline
(options, root-signature-derived layout, function constants, or its validation step). Madeira drives
the same converter with different code and may therefore succeed. Phase 1 is justified.

Caveats worth knowing before Phase 2:

- The harness used no root signature. The game's real root signature changes the argument-buffer
  layout the converter emits but not the tessellation emulation code; still, the first real test
  with the engine's root signature is Phase 2.
- Three domain shaders (`0x12becd88`, `0xe03a22e`, `0xe03cd36`) emit
  `[metal-shaderconverter] Warning: Unsupported: culldistance`. They still build. If terrain has
  clipping artifacts later, this is the first suspect.
- The CLI `metal-shaderconverter` segfaults (exit 139) when given `--enable-gs-ts-emulation`, for
  any input, so the C API was used for everything emulation-related.
- An intentionally wrong pairing (depth-only DS `0x12a606c0` with a colour PS) crashes the Metal
  compiler service (`XPC_ERROR_CONNECTION_INTERRUPTED`), reproducibly. Irrelevant to the game, but
  a reminder that a stage mismatch can look like a compiler failure.

## Shader inventory

All shaders are embedded in `Pioneers of Pagonia.exe` (357 MB). The five `pak/*` files (6.0 GB)
contain no DXBC containers. Carved with `phase0/carve_dxbc.py`:

| Type               | Count  |
| ------------------ | ------ |
| pixel (ps6_0)      | 14918  |
| vertex (vs6_0)     | 114    |
| compute (cs6_0)    | 114    |
| geometry (gs6_0)   | 52     |
| domain (ds6_0)     | 10     |
| hull (hs6_0)       | 9      |
| total              | 15217  |

All are DXIL shader model 6.0, chunks `SFI0, ISG1, OSG1, [PSG1], PSV0, STAT, HASH, DXIL`. No shader
embeds a root signature (`RTS0`); the engine passes it at PSO creation. Inventory with EXE offsets:
`phase0/shaders/inventory.tsv` (file names are `<offset>_<type>.dxbc`).

### Hull shaders

All nine: quad domain, integer partitioning, triangle CCW output, 1 input control point.

| HS offset    | Inputs (from VS)                 | Out CP | Patch const bytes | Max tess | Notes                                     |
| ------------ | -------------------------------- | ------ | ----------------- | -------- | ----------------------------------------- |
| `0x12aa2180` | DATA, STARTLEFT…ENDRIGHT, RANGE  | 1 (0 B) | 144              | 64       | spline/road patches (`SubDToBezierConstantsHS`) |
| `0x12c42160` | HEIGHTS0-3, GRIDPOS              | 4      | 128               | 10       | terrain, GROUNDHEIGHT + FLUIDHEIGHT       |
| `0x12c4a248` | HEIGHTS0-3, GRIDPOS              | 4      | 32                | 10       | terrain                                   |
| `0x12c4dcf8` | TILEID                           | 4      | 32                | 10       | terrain, tile-indexed                     |
| `0x12c596d0` | TILEID                           | 4      | 40                | 10       | terrain, SCANRANGE                        |
| `0x12c67d48` | HEIGHTS0-3, GRIDPOS              | 4      | 40                | 10       | terrain, INDEX                            |
| `0x12c79738` | TILEID, INDEX                    | 4      | 40                | 10       | terrain, tile-indexed                     |
| `0xe03fe56`  | HEIGHTS0-3, GRIDPOS              | 4      | 64                | 10       | terrain, GROUNDHEIGHT + FLUIDHEIGHT       |
| `0xe042536`  | HEIGHTS0-3, GRIDPOS              | 4      | 64                | 10       | terrain, GROUNDHEIGHT + FLUIDHEIGHT       |

### Domain shaders

| DS offset    | In CP | Patch const | Mesh prims/tg | Pairs with HS                     |
| ------------ | ----- | ----------- | ------------- | --------------------------------- |
| `0x12a4e918` | 1     | 144         | 256           | `0x12aa2180`                      |
| `0x12becd88` | 4     | 128         | 64            | `0x12c42160`                      |
| `0x12a5a530` | 4     | 32          | 256           | `0x12c4a248`, `0x12c4dcf8`        |
| `0x12a606c0` | 4     | 32          | 256           | same; outputs only SV_Position (depth-only) |
| `0x12c5f138` | 4     | 32          | 256           | `0x12c4a248`, `0x12c4dcf8`        |
| `0x12aa4c98` | 4     | 40          | 224           | `0x12c596d0`                      |
| `0x12c47fb8` | 4     | 40          | 224           | `0x12c67d48`, `0x12c79738`        |
| `0x12c57868` | 4     | 40          | 256           | `0x12c67d48`, `0x12c79738`        |
| `0xe03a22e`  | 4     | 64          | 96            | `0xe03fe56`, `0xe042536`          |
| `0xe03cd36`  | 4     | 64          | 96            | `0xe03fe56`, `0xe042536`          |

Vertex shaders feeding the hull stages: `0x12a510b8`, `0x12c5ddc0`, `0x12c7b5f0` (HEIGHTS/GRIDPOS,
input is only SV_VertexID), `0x12c5d340` (TILEID), `0x12aaa7e0` (TILEID+INDEX), `0x12a52490`
(spline). Pairing was done by matching signatures (`phase0/pair_shaders.py`), not by observing the
engine, so some VS/DS/PS combinations in `pairs.tsv` may never occur in the game. Every HS and DS
appears in at least one combination that builds.

## Per-step results

1. **CLI conversion, no emulation flag** (`phase0/convert_all.sh`): 71/71 hull, domain and geometry
   shaders convert. Hull output already contains `irconverter_hull_shader` and
   `irconverter_tessellator` as visible functions with function constants
   `vertex_shader_output_size_fc` (int) and `max_tessellation_factor_fc` (float).
2. **Library load + function specialisation** (`phase0/load_metallib.mm`): 110/110 functions in those
   71 metallibs materialise via `newFunctionWithName:constantValues:` on the M2 Pro.
3. **Full pipeline** (`phase0/tess_pipeline.mm`, C API, `IRCompilerEnableGeometryAndTessellationEmulation`,
   separate stage-in function synthesised from the VS input signature, pipeline assembled exactly like
   `IRRuntimeNewGeometryTessellationEmulationPipeline` in Apple's runtime header, optionally through
   `MTL4Compiler`): results in the table at the top. Logs: `results.log` (Metal 3),
   `results_mtl4.log`, `results_d3dm_converter.log`, `results_d3dm_converter_mtl4.log`.

## Reproduce

```
cd phase0
./build.sh                                   # load_metallib, tess_pipeline (arm64)
python3 -I carve_dxbc.py shaders "<game dir>/Pioneers of Pagonia.exe"
./convert_all.sh shaders out                 # CLI pass, writes out/*.metallib + reflection
./load_metallib out/*_plain.metallib         # step 2
python3 -I pair_shaders.py shaders           # writes pairs.tsv
./run_pairs.sh shaders                       # step 3, Metal 3
EXTRA=--mtl4 ./run_pairs.sh shaders          # step 3, Metal 4 compiler
# D3DMetal's own converter (x86_64 harness; dylib copied from the GPTK DMG to d3dmetal_lib/):
clang++ -arch x86_64 -std=c++17 -fobjc-arc -I/usr/local/include -L d3dmetal_lib -lmetalirconverter \
  -Wl,-rpath,"$PWD/d3dmetal_lib" -framework Metal -framework Foundation tess_pipeline.mm -o tess_pipeline_x86_d3dm
BIN=./tess_pipeline_x86_d3dm ./run_pairs.sh shaders
```

Single pipeline, e.g. the main terrain one:

```
./tess_pipeline "shaders/Pioneers of Pagonia.exe_0x12a510b8_vs6_0.dxbc" \
  "shaders/Pioneers of Pagonia.exe_0x12c42160_hs6_0.dxbc" \
  "shaders/Pioneers of Pagonia.exe_0x12becd88_ds6_0.dxbc" \
  "shaders/Pioneers of Pagonia.exe_0xde0d962_ps6_0.dxbc" [--mtl4] [--dump DIR]
```

`phase0/shaders/` (240 MB of carved game shaders) and `phase0/d3dmetal_lib/` (Apple's dylib) are
derived from licensed binaries; do not publish them.

## What this means for Phase 1

Nothing in the converter blocks Madeira's path. Phase 1 (build Madeira's D3D12 layer for x86_64 macOS
Wine) can start. Carry forward: the root-signature caveat, the `culldistance` warning, and the fact
that all terrain hull shaders use max tessellation factor 10 with 4 output control points, which
Madeira's `WMTGeometryEmulationInfo.max_tessellation_factor` must carry.
