# Phase 1 result: Madeira's D3D12 layer built for x86_64 macOS Wine, test gate passed

Date: 2026-10-12. Machine: Apple M2 Pro, macOS 27.0.1, Xcode 27.0 (plus the Metal Toolchain
component, see below). Plan: `MADEIRA_PORT_PLAN.md` section "Phase 1".

## Verdict: gate passed, proceed to Phase 2

| Test (x86_64 EXE, run inside the wrapper copy's Wine 10)  | Result                   |
| --------------------------------------------------------- | ------------------------ |
| `d3d12-m2-x64.exe` (ABI, sync, copy, draw, depth, texture) | **90 checks, 0 failures** |
| `d3d12-vfetch-x64.exe` (vertex-fetch differential)         | **31 checks, 0 failures** |
| `d3d12-cube-x64.exe` (on-screen textured cube)             | **visible**, 787 frames in 30 s, no command-buffer errors; user-confirmed, see `phase1/cube_screenshot.png` |

The README's counts (41 ABI, 54 copy/readback) are from an older test version; the current test is
one 90-check executable.

Everything runs through the real path: `d3d12.dll` (x86_64 PE) -> `winemetal.dll` (Wine builtin
PE) -> unix call -> `winemetal.so` (x86_64 Mach-O, 52 MB, airconv + LLVM 15 + the madeira-d3d12
converter service linked in) -> `libmetalirconverter.dylib` (Apple's universal converter) -> Metal.
The runtime logged `conversion target: macOS, family 5001 (Metal3), min 15.0`, converted the test
DXIL at run time, and built pipelines. Command buffers are checked for `MTLCommandBufferStatusError`
after every retire; none occurred.

## Where things are

| Item                        | Path                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------ |
| Madeira clone (modified)    | `~/Documents/Programming/private/madeira-src/Madeira` (shallow, commit `HEAD` of 2026-10-06; submodules `dxmt` db546ee, `wine` 257f271; FEX and madeira-dock not checked out, not needed) |
| Toolchains                  | `~/Documents/Programming/private/madeira-src/toolchain/` (symlinked as `Madeira/toolchains/*` and `Madeira/dxmt/toolchains -> ../toolchains`) |
| Build products              | `Madeira/build/madeira-d3d12/out-macos/` (d3d12.dll, madeira_d3d12.dll, d3d12core.dll, winemetal.dll, winemetal.so, libmetalirconverter.dylib, three test EXEs) |
| dxmt meson build dir        | `Madeira/dxmt/build-x86_64/`                                                                           |
| Wrapper copy (test target)  | `~/Applications/Steambuild-Madeira.app` (APFS clone of the working wrapper; the working wrapper is untouched) |
| Test runner                 | `phase1/run_tests.sh [m2|vfetch|cube|all]`                                                             |
| Logs of this session        | scratchpad only; rerun the runner to reproduce                                                         |

## Toolchain versions

| Component                      | Version / source                                                                                         |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- |
| llvm-mingw                     | `llvm-mingw-20260421-ucrt-macos-universal.tar.xz`, SHA-256 `bd85a397...3b7f` (matches Madeira's pin), clang 22.1.4 |
| LLVM for airconv               | llvm-project tag `llvmorg-15.0.7`, built x86_64 with the flags from dxmt's `configure.sh` (targets "", assertions on, zstd off, tools off), installed to `toolchain/llvm-darwin` (76 static libs) |
| Wine SDK (import libs, winebuild, ntdll.so/winemac.so to link against) | 3Shain's `wine.tar.gz` v8.16-3shain (what upstream DXMT CI uses), winebuild 8.17, SHA-256 `289c7f19...de4f10` |
| Metal Shader Converter         | 4.0 beta 2 pkg from the GPTK 4.0 beta 2 DMG, SHA verified by `deps.sh`; the macOS universal dylib from the package is what ships next to winemetal.so |
| Metal compiler                 | Xcode 27 does not include it; `xcodebuild -downloadComponent MetalToolchain` (metal 32023.921) was needed for dxmt's embedded `.metal` shaders |
| meson / ninja / cmake          | 1.12.1 / 1.13.2 / Homebrew current                                                                        |
| Target Wine                    | wrapper's `wine-10.0 (Sikarugir)`, x86_64, D3DMetal v2.1 overlay (GPTK 4 beta 2 files)                    |

## Exact commands (reproduce from scratch)

```bash
# 1. clone (shallow) and fix the submodule checkouts the shallow clone leaves empty
mkdir -p ~/Documents/Programming/private/madeira-src && cd ~/Documents/Programming/private/madeira-src
git clone --depth 1 --recursive --shallow-submodules https://github.com/willfaust/Madeira Madeira
cd Madeira && git submodule update --force --checkout dxmt wine

# 2. toolchains (all outside the repo, symlinked in)
cd ../ && mkdir toolchain && cd toolchain
curl -sL -o llvm-mingw.tar.xz https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/llvm-mingw-20260421-ucrt-macos-universal.tar.xz
tar xf llvm-mingw.tar.xz && xattr -dr com.apple.quarantine llvm-mingw-20260421-ucrt-macos-universal
mkdir wine-3shain && curl -sL https://github.com/3Shain/wine/releases/download/v8.16-3shain/wine.tar.gz | tar xz -C wine-3shain
git clone --depth 1 --branch llvmorg-15.0.7 https://github.com/llvm/llvm-project.git llvm-project
cmake -B llvm-darwin-build -S llvm-project/llvm -DCMAKE_INSTALL_PREFIX="$PWD/llvm-darwin" \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 -DLLVM_HOST_TRIPLE=x86_64-apple-darwin -DLLVM_ENABLE_ASSERTIONS=On \
  -DLLVM_ENABLE_ZSTD=Off -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="" -DLLVM_BUILD_TOOLS=Off \
  -DLLVM_INCLUDE_TESTS=Off -DLLVM_INCLUDE_BENCHMARKS=Off -DLLVM_INCLUDE_EXAMPLES=Off -G Ninja
ninja -C llvm-darwin-build && ninja -C llvm-darwin-build install      # ~8 min on the M2 Pro
cd ../Madeira && mkdir -p toolchains && ln -sfn ../toolchain/llvm-mingw-20260421-ucrt-macos-universal toolchains/ \
  && ln -sfn ../toolchain/llvm-darwin toolchains/llvm-darwin && ln -sfn ../toolchain/wine-3shain toolchains/wine \
  && ln -sfn ../toolchains dxmt/toolchains
brew install meson ninja cmake
xcodebuild -downloadComponent MetalToolchain

# 3. converter package (deps.sh verifies the SHA and expands it)
hdiutil attach -nobrowse -readonly ~/Downloads/Game_Porting_Toolkit_4.0_beta_2.dmg
mkdir -p research/GPTK && cp "/Volumes/Game Porting Toolkit/Metal Shader Converter 4.0 beta 2.pkg" research/GPTK/
hdiutil detach "/Volumes/Game Porting Toolkit"

# 4. build everything (meson setup on first run, then winemetal.dll/.so, then the PE side)
bash build/madeira-d3d12/build-macos-x86_64.sh          # -> build/madeira-d3d12/out-macos/

# 5. install into a COPY of the wrapper (APFS clone, costs no disk)
cp -Rpc ~/Applications/"Steambuild 32 64bit Metal.app" ~/Applications/Steambuild-Madeira.app
A=~/Applications/Steambuild-Madeira.app; W="$A/Contents/SharedSupport/wine"; O=build/madeira-d3d12/out-macos
mv "$W/lib/wine/x86_64-windows/winemetal.dll" "$W/lib/wine/x86_64-windows/winemetal.dll.sikarugir"   # 36 KB stub exporting only WineMetalEntry
cp $O/winemetal.dll "$W/lib/wine/x86_64-windows/"
cp $O/winemetal.so $O/libmetalirconverter.dylib "$W/lib/wine/x86_64-unix/"
mkdir -p "$A/Contents/SharedSupport/prefix/drive_c/madeira-tests" && cp $O/*.exe $O/*.dll "$A/Contents/SharedSupport/prefix/drive_c/madeira-tests/"

# 6. gate
~/Documents/Programming/private/PoP/phase1/run_tests.sh all
```

Running `wine64` directly needs `WINEPREFIX` and `DYLD_FALLBACK_LIBRARY_PATH=$A/Contents/Frameworks:/usr/lib`
(wineserver links `@rpath/libinotify.0.dylib` from there; the Wineskin launcher sets it). The
runner script does this.

## Source changes in the clone (all uncommitted, 10 files; intended to be upstreamable)

dxmt submodule (`willfaust/dxmt`, branch `ios-port`):

- `build-x86_64-win.txt` (new): cross file for `x86_64-w64-mingw32-clang` from the pinned llvm-mingw.
- `meson.options`: `madeira_d3d12_path`, `madeira_msc_include`, `madeira_converter_id`.
- `src/winemetal/unix/meson.build`: when `madeira_d3d12_path` is set, builds `madeira_ir_unix.mm`
  (Objective-C++ ARC), `madeira_sm5_ia.cpp` and `madeira_ags.cpp` into two static libraries linked
  whole into `winemetal.so`; adds `include_directories('..')` (the fork's `wmt_remote_pack.h`
  includes `winemetal.h`); adds `-arch x86_64` to the .so link because linking an Objective-C++
  archive makes meson use the ObjC++ driver, which upstream's meson.build gives no arch flag; adds
  `wmt_macos_stubs.c` to the sources.
- `src/winemetal/unix/wmt_macos_stubs.c` (new): no-op definitions of the 17 `ios_*` hooks that
  the iOS app and its ntdll provide (frame stats, exception counters, cross-process probe).
- `src/winemetal/unix/winemetal_unix.c`: `os_proc_available_memory()` is iOS-only, replaced by a
  macro returning 0 ("limit unknown") under `!TARGET_OS_IOS`; plus an env-gated render trace
  (`WMT_TRACE_RENDER=1`: render passes, viewports, scissors, rasterizer state, DSSO, PSO
  descriptors, draws) that was decisive for the write-mask finding below.
- `src/airconv/shaders/air_tessellation.metal`: the `__metal_atomic_fetch_add_explicit` intrinsic
  changed arity in the Xcode 27 Metal toolchain; replaced by the public `atomic_fetch_add_explicit`
  exactly as upstream 3Shain/dxmt already has it.

Madeira:

- `build/madeira-d3d12/build-pe.sh`: `MADEIRA_PE_ARCH` (default `arm64ec`, so iOS is unchanged)
  selects the DLL compiler and `WINEMETAL_LIB` the import-library directory.
- `build/madeira-d3d12/build-macos-x86_64.sh` (new): orchestration, see above.
- `madeira-d3d12/src/unix/madeira_ir_unix.mm`: on `!TARGET_OS_IOS`, look for
  `libmetalirconverter.dylib` next to winemetal.so (via `dladdr` on its own image) before the app
  bundle path.
- `madeira-d3d12/tests/windows/m2_abi.c`, `cube_window.c`: see "Test fixes" below.
- `docs/MACOS_X86_64.md` (new): the same information from Madeira's point of view.

## What went wrong on the way (so Phase 2 does not repeat it)

1. **Shallow submodule clone left `dxmt/` empty and `wine/` on the wrong commit.** Fixed with
   `git submodule update --force --checkout dxmt wine`.
2. **The dxmt cross files resolve toolchains under `dxmt/toolchains`**, hence the extra symlink.
3. **Metal toolchain missing** (Xcode 27 ships without it). One `xcodebuild -downloadComponent`.
4. **First winemetal.so came out arm64 with no symbols** (ObjC++ link driver without `-arch`).
5. **First test run: 90 checks, 7 failures, every draw invisible, clears visible, no Metal
   validation errors, no GPU errors.** The render trace showed `color0 writeMask=0` on every
   pipeline. Cause: the tests zero their `D3D12_GRAPHICS_PIPELINE_STATE_DESC` and never set
   `RenderTargetWriteMask`; the runtime maps the blend state faithfully (`mad_write_mask`), and a
   zero mask writes nothing in real D3D12 too. `vfetch_test.c` sets the mask and passed from the
   start. The runtime is right; the test predates the strict mapping. Same story for the cube's
   depth test (zeroed `DepthStencilState` = no depth test), the SRV `Shader4ComponentMapping` (0
   means "component 0 in every channel", giving (200,200,200) for a (200,100,50) texel), the
   textured render target created without `ALLOW_RENDER_TARGET` (Metal validation refused the
   pass), and a check that read `GetCompletedValue` right after `Queue::Signal` (signals are
   asynchronous since the runtime's ml1061 change).

### Test fixes (all in the tests, none in the runtime)

| File              | Change                                                                                       |
| ----------------- | -------------------------------------------------------------------------------------------- |
| `m2_abi.c`        | `RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL` on `pd`, `cpd`, `tpd`; `cpd` depth enable/write/`LESS`; `svd.Shader4ComponentMapping = DEFAULT`; textured RT gets `ALLOW_RENDER_TARGET`; the 4-cycle check waits with `SetEventOnCompletion(n, NULL)` before reading the value |
| `cube_window.c`   | write mask, depth state, SRV mapping                                                         |

Before these: 90/7. After: 90/0 and 31/0.

## Things to carry into Phase 2

- **The Wineskin launcher forces D3DMetal**: with `D3DMETAL=1` in `Info.plist` it exports
  `WINEDLLOVERRIDES="*dxgi,*d3d10core,*d3d11,*d3d12=b"`, which beats any registry override. For the
  game launch through Steam in the copy, set `D3DMETAL` to 0 in the copy's `Info.plist` (and
  `D3DMETAL_FORCE`), or launch with the env overridden, then put Madeira's `d3d12.dll` and
  `d3d12core.dll` in the game folder with `d3d12,d3d12core=n` for the game EXE. Apple's
  `dxgi.dll` stays for now; Madeira's dxgi (from the dxmt fork) was not built in Phase 1.
- `winemetal.dll` is now a Wine builtin in `x86_64-windows` of the copy and `winemetal.so` plus the
  converter in `x86_64-unix`; nothing in the game folder is needed for those.
- `winemetal.so` links `@rpath/ntdll.so` and `@rpath/winemac.so` from the 8.16 SDK; at run time
  dyld resolves them to the already-loaded Wine 10 images via `@loader_path`. Works, verified by
  the tests, but a Wine update that renames those would need a relink.
- `madeira.cfg` is read from `$HOME/Documents/madeira.cfg` (`madeira_cfg.h`), where `$HOME` is
  the Wine process's HOME. Keys the runtime reads: `async-present-ahead, async-submit,
  barrier-render, capture-*, d3d12-core-dll, d3d12-msaa8, d3d12-reserved-max-mb, d3d12-tile-based,
  d3d12-tiled-resources, d3d12-typed-uav-load, dxil-tess, encoder-labels, f6-compute-open,
  fence-chain, heap-backing, occlusion-visible, perf-log, pso-lazy, pso-parallel, pso-share-libs,
  upload-swap, use-dedup`.
- Diagnostics that proved useful: `WMT_TRACE_RENDER=1` (my trace), `MTL_DEBUG_LAYER=1
  MTL_DEBUG_LAYER_ERROR_MODE=nslog MTL_SHADER_VALIDATION=1` (Metal validation prints to stderr; the
  category header, for example `RenderPass Descriptor Validation`, is on its own line and the
  message on the next), `WINEDEBUG=+loaddll`.
- Feature level: the runtime refuses 12_1 and "claims 12_0 as the ceiling". Pagonia wants Resource
  Binding Tier 3 and SM 6.x via `CheckFeatureSupport`; check what Madeira answers.
- Disk: 21 GB free. `toolchain/llvm-project` (1.6 GB) and `toolchain/llvm-darwin-build` (518 MB)
  can be deleted; `toolchain/llvm-darwin` is the installed result the build needs.
