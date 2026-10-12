# Reproduce 2: Pioneers of Pagonia with full terrain on Apple Silicon (state of 2026-10-12, evening)

Result of these steps: the game starts through Steam inside a Porting Kit wrapper, but its
D3D12 calls go to **Madeira's open-source D3D12-on-Metal layer** instead of Apple's D3DMetal.
Intro cinematic, main menu and the menu's 3D scene render at ~60 frames/s **with the terrain
complete** (grass, sand, water, rock, paths), which D3DMetal cannot do (it fails on the terrain's
tessellation shaders, see `reproduce.md`). **A map loads and plays**: terrain, units, buildings,
roads, UI, the tutorial video; nothing flickers; the log shows no skipped or unimplemented work.
In-game frame rate is ~23 frames/s at 2560x1347 (the open item). Reference pictures:
`phase2/win_staged_copy.png`, `phase2/win_staged_copy2.png` (menu), `phase2/ingame1.png`,
`phase2/ingame2.png` (map).

This file is self-contained. The documents it grew out of hold the details and the history:

| Document                | What it holds                                                                       |
| ----------------------- | ----------------------------------------------------------------------------------- |
| `reproduce.md`          | the base setup with Apple's D3DMetal (Porting Kit, GPTK 4 overlay, engine flags)    |
| `MADEIRA_PORT_PLAN.md`  | why Madeira, the phase plan and gates                                               |
| `PHASE1_BUILD.md`       | the toolchain and build of Madeira for x86_64 macOS Wine, with every pitfall        |
| `PHASE2_LOG.md`         | the 11 runtime fixes that make the game render, diagnostics, next steps             |

## What you end up with

```
Steam.exe -> Pagonia.exe (x86_64 PE, Wine 10 from Porting Kit)
   dxgi.dll        DXMT's dxgi (swapchain bridge)              } in the game folder,
   d3d12.dll       Madeira's D3D12 runtime (PE, our build)      } native-first overrides
   d3d12core.dll   Madeira's stub                               }
      -> winemetal.dll   (Wine builtin PE, replaces the wrapper's 36 KB stub)
      -> winemetal.so    (x86_64 Mach-O: airconv + LLVM 15 + Madeira's converter service)
      -> libmetalirconverter.dylib (Apple's Metal Shader Converter 4.0 beta 2)
      -> Metal
```

Apple's D3DMetal stays installed in the wrapper and is still used by Steam's own processes.

## Requirements

- Apple Silicon Mac, macOS 26 or newer (done here on an M2 Pro, macOS 27.0.1).
- Xcode 27 plus the Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`).
- Homebrew with `meson`, `ninja`, `cmake`, `python3`.
- A Steam account owning Pioneers of Pagonia (game version 1.5.2 was used).
- A free Apple developer account, for the Game Porting Toolkit 4.0 beta 2 DMG.
- About 25 GB free: 20 GB wrapper plus game, 3 GB toolchains and build, the rest for logs/captures.
- Time: roughly 1 hour of downloads and builds (the LLVM 15 build alone is ~8 min on an M2 Pro).

## Part A: the base wrapper (same as `reproduce.md`)

Follow `reproduce.md` steps 1 to 3 exactly. In short:

1. Porting Kit 7.0.2 (Apple Silicon build), Library > Sources > Steam, preset **Steambuild Metal**.
   The wrapper lands at `~/Applications/Steambuild 32 64bit Metal.app`. Sign in, install the game.
2. Overlay GPTK 4.0 beta 2's `redist/lib/external` and `redist/lib/wine` into the wrapper's
   `Contents/SharedSupport/wine/lib` with `ditto` (merge, never replace). `launchctl setenv D3DM_MTL4 1`.
3. Steam launch options for the game: `-NoDX12DeviceFactory -NoDX12SDKVersionCheck`.

Gate: the game reaches the main menu through D3DMetal, with black terrain. Keep this wrapper as
is; everything below happens in a copy of it.

## Part B: build Madeira for x86_64 macOS Wine

The pinned versions matter; they are the ones the build scripts expect.

### B1. Source

```bash
mkdir -p ~/Documents/Programming/private/madeira-src && cd ~/Documents/Programming/private/madeira-src
git clone --depth 1 --recursive --shallow-submodules https://github.com/willfaust/Madeira Madeira
cd Madeira && git submodule update --force --checkout dxmt wine   # the shallow clone leaves dxmt/ empty
git log -1 --format=%H            # built here from 48f976429c189f8396e23d251d8a82f43c705922 (2026-10-07)
(cd dxmt && git log -1 --format=%H)   # db546ee466ad50ec6463edb5fa183de11db43761 (willfaust/dxmt, ios-port)
```

If upstream has moved, check out those two commits first; the patches below were made against them.

### B2. Apply this project's changes

All changes are uncommitted in the working clone and exported as two patches in
`phase2/patches/`. They add the x86_64 macOS build, the macOS stubs, and the eleven runtime fixes
(tessellator tables, staged BC1 copies, indirect mesh draws, geometry-shader pipelines, video
budget, mip clamp, residency, and so on; the table in `PHASE2_LOG.md` lists each one).

```bash
P=~/Documents/Programming/private/PoP/phase2/patches
cd ~/Documents/Programming/private/madeira-src/Madeira
git apply --check $P/madeira.patch && git apply $P/madeira.patch
cd dxmt && git apply --check $P/dxmt.patch && git apply $P/dxmt.patch && cd ..
git status --short        # 5 modified + 4 new files in Madeira, 4 modified + 2 new in dxmt
```

### B3. Toolchains (outside the repo, symlinked in)

```bash
cd ~/Documents/Programming/private/madeira-src && mkdir -p toolchain && cd toolchain
curl -sL -o llvm-mingw.tar.xz https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/llvm-mingw-20260421-ucrt-macos-universal.tar.xz
tar xf llvm-mingw.tar.xz && xattr -dr com.apple.quarantine llvm-mingw-20260421-ucrt-macos-universal
mkdir wine-3shain && curl -sL https://github.com/3Shain/wine/releases/download/v8.16-3shain/wine.tar.gz | tar xz -C wine-3shain
git clone --depth 1 --branch llvmorg-15.0.7 https://github.com/llvm/llvm-project.git llvm-project
cmake -B llvm-darwin-build -S llvm-project/llvm -DCMAKE_INSTALL_PREFIX="$PWD/llvm-darwin" \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 -DLLVM_HOST_TRIPLE=x86_64-apple-darwin -DLLVM_ENABLE_ASSERTIONS=On \
  -DLLVM_ENABLE_ZSTD=Off -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="" -DLLVM_BUILD_TOOLS=Off \
  -DLLVM_INCLUDE_TESTS=Off -DLLVM_INCLUDE_BENCHMARKS=Off -DLLVM_INCLUDE_EXAMPLES=Off -G Ninja
ninja -C llvm-darwin-build && ninja -C llvm-darwin-build install
cd ../Madeira && mkdir -p toolchains \
  && ln -sfn ../toolchain/llvm-mingw-20260421-ucrt-macos-universal toolchains/ \
  && ln -sfn ../toolchain/llvm-darwin toolchains/llvm-darwin \
  && ln -sfn ../toolchain/wine-3shain toolchains/wine \
  && ln -sfn ../toolchains dxmt/toolchains
brew install meson ninja cmake
xcodebuild -downloadComponent MetalToolchain
```

Why these: llvm-mingw is Madeira's pinned PE compiler; the 3Shain Wine 8.16 SDK gives the import
libraries and `winebuild` that upstream DXMT CI uses; LLVM 15 is what airconv links against; the
Metal toolchain compiles dxmt's embedded `.metal` shaders and Madeira's `indirect_mesh.metal`.

### B4. Metal Shader Converter package

```bash
hdiutil attach -nobrowse -readonly ~/Downloads/Game_Porting_Toolkit_4.0_beta_2.dmg
mkdir -p research/GPTK && cp "/Volumes/Game Porting Toolkit/Metal Shader Converter 4.0 beta 2.pkg" research/GPTK/
hdiutil detach "/Volumes/Game Porting Toolkit"
```

The build's `deps.sh` verifies the package's SHA and expands it. Its runtime header is also the
source of the tessellator tables (`gen-tess-tables.py`), which fix #9 needs.

### B5. Build

```bash
cd ~/Documents/Programming/private/madeira-src/Madeira
bash build/madeira-d3d12/build-macos-x86_64.sh      # meson setup on the first run, then everything
ls build/madeira-d3d12/out-macos/
# d3d12.dll d3d12core.dll dxgi.dll winemetal.dll winemetal.so libmetalirconverter.dylib + 3 test EXEs
```

Expect warnings about unused functions, no errors. `winemetal.so` must be x86_64 and ~52 MB
(`file` and `ls -l`); an arm64 or tiny one means the dxmt patch did not apply.

## Part C: install into a copy of the wrapper

Never modify the Part A wrapper: it is the fallback and its Steam login is shared with the copy.

```bash
cp -Rpc ~/Applications/"Steambuild 32 64bit Metal.app" ~/Applications/Steambuild-Madeira.app   # APFS clone, no disk cost
A=~/Applications/Steambuild-Madeira.app; W="$A/Contents/SharedSupport/wine"
O=~/Documents/Programming/private/madeira-src/Madeira/build/madeira-d3d12/out-macos
G="$A/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Pioneers of Pagonia"

# 1. winemetal: the Wine builtin stub is replaced, the unix side and the converter go next to ntdll.so
mv "$W/lib/wine/x86_64-windows/winemetal.dll" "$W/lib/wine/x86_64-windows/winemetal.dll.sikarugir"
cp "$O/winemetal.dll" "$W/lib/wine/x86_64-windows/"
cp "$O/winemetal.so" "$O/libmetalirconverter.dylib" "$W/lib/wine/x86_64-unix/"

# 2. the D3D12 layer, in the game folder (selected by DLL overrides at launch, game files untouched)
cp "$O/d3d12.dll" "$O/d3d12core.dll" "$O/dxgi.dll" "$G/"

# 3. stop the Wineskin launcher from forcing D3DMetal (it would export *dxgi,*d3d12=b)
plutil -replace D3DMETAL -integer 0 "$A/Contents/Info.plist"
plutil -replace D3DMETAL_FORCE -integer 0 "$A/Contents/Info.plist"

# 4. optional gate: Madeira's own tests inside the copy (90 + 31 checks, a textured cube window)
mkdir -p "$A/Contents/SharedSupport/prefix/drive_c/madeira-tests" && cp "$O"/*.exe "$O"/*.dll "$A/Contents/SharedSupport/prefix/drive_c/madeira-tests/"
~/Documents/Programming/private/PoP/phase1/run_tests.sh all
```

## Part D: run the game

The launch script `phase2/run_game.sh` starts `wine64` directly with the copy's prefix, the DLL
overrides, `MADEIRA_DOCS_DIR` pointing at `phase2/` (where `madeira.cfg`, captures and the
shader cache live) and stderr of every Wine process in `phase2/logs/run-<timestamp>.log`.

```bash
cd ~/Documents/Programming/private/PoP/phase2
cat madeira.cfg        # d3d12-tile-based = 0 and capture-tess = 1 are all it needs
WINEDLLOVERRIDES="dxgi,d3d12,d3d12core=n,b;GfnRuntimeSdk=d" ./run_game.sh game
# ... Steam ~30 s, game ~40 s to the menu. Stop everything with:
./run_game.sh kill
```

Before launching: quit any other Steam client of the same account (the Part A wrapper's Steam
logs this one out). The `GfnRuntimeSdk=d` override is required: the GeForce NOW SDK crashes on
unload with Madeira's timing.

### Expected result

- Log: `conversion target: macOS`, pipelines built, `ml1042 ... (0 skipped)` lines every few
  seconds, `[iOS DXMT] Present #N` at ~60/s, no `COMMAND BUFFER` error, no `not implemented`.
- Window: intro cinematic, then the main menu with a fully textured 3D vista behind it. The menu
  cycles through several vistas; all of them must show ground textures everywhere.
- Screenshot while the desktop is in use: `screencapture -x` returns black. Capture the window by
  id instead: `swiftc -O phase2/tools/wincap.swift -o wincap`, then `screencapture -x -l $(./wincap | awk '/^TARGET/{print $2}') shot.png`.

## Part E: iterating on the runtime

```bash
M=~/Documents/Programming/private/madeira-src/Madeira; A=~/Applications/Steambuild-Madeira.app
G="$A/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Pioneers of Pagonia"
# PE side only (d3d12.dll), ~1 min:
cd $M && MADEIRA_PE_ARCH=x86_64 bash build/madeira-d3d12/build-pe.sh && cp build/madeira-d3d12/out-pe/d3d12.dll "$G/"
# unix side (winemetal.so); the file is mapped while the game runs, so copy via a temp name:
cd $M/dxmt/build-x86_64 && ninja src/winemetal/unix/winemetal.so \
  && cp src/winemetal/unix/winemetal.so "$A/Contents/SharedSupport/wine/lib/wine/x86_64-unix/winemetal.so.new" \
  && mv "$A/Contents/SharedSupport/wine/lib/wine/x86_64-unix/winemetal.so.new" "$A/Contents/SharedSupport/wine/lib/wine/x86_64-unix/winemetal.so"
```

Delete `phase2/shadercache/` after changing shader conversion code, or cached conversions are
served. Diagnostics (frame capture via `echo 1 > phase2/madeira-capture.txt`, copy traces,
Metal shader validation, capture of DXIL tessellation draws) are listed in `PHASE2_LOG.md`.

## Things that go wrong

| Symptom                                                        | Cause and fix                                                                                           |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| "No Compatible Graphics Hardware", every box unchecked          | the engine's video-memory probe; fixed in the dxmt patch (macOS budget from Metal). Patch not applied?  |
| Game still uses D3DMetal (log has no `[madeira-d3d12]` lines)  | `D3DMETAL` still 1 in the copy's Info.plist, or the overrides missing, or the DLLs not in the game folder |
| Execute-access page fault in `GfnRuntimeSdk.dll` after the splash | `GfnRuntimeSdk=d` missing from `WINEDLLOVERRIDES`                                                    |
| Terrain black, everything else fine                            | an old `d3d12.dll`: fixes #9 and #11 are in the Madeira patch; rebuild the PE side and copy it          |
| Steam in the copy logged out                                   | another Steam client of the account is running; quit it                                                 |
| `D3DM_MTL4` effects gone after a reboot                        | only relevant for the D3DMetal wrapper; Madeira does not use it                                         |
| `wineserver` fails to start when run by hand                   | needs `DYLD_FALLBACK_LIBRARY_PATH=$A/Contents/Frameworks:/usr/lib` (the script sets it)                 |

## What is not done

- Performance in a map: ~23 frames/s, very steady, against 60 in the menu. Likely a CPU-side
  limit in command recording or replay; see `PHASE2_LOG.md` "Where it stands now" for starting points.
- Only the tutorial's first minutes have been played; longer sessions, saving/loading, and the
  other maps are untested.
- All Madeira changes are uncommitted and only in the patches; they are written to be upstreamable
  (`docs/MACOS_X86_64.md` in the patch describes them from Madeira's side).
