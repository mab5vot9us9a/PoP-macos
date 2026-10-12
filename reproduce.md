# Reproduce: Pioneers of Pagonia on Apple Silicon (as of 2026-10-12)

Result of these steps: the game starts, reaches the main menu and loads maps. Terrain and grass are
not rendered (Apple D3DMetal fails to compile the game's tessellation hull shaders). Audio was silent
on first test, cause not yet confirmed. This is the same state the Steam thread reached, minus the
binary patching, which a new engine flag made unnecessary.

Based on the Steam thread "Mac Version", page 5, posts by SoaD_1337, jabba and developer Ralf:
https://steamcommunity.com/app/2155180/discussions/0/3758852882969018374/?ctp=5

## Requirements

- Apple Silicon Mac on macOS 26 or newer (the Metal 4 backend needs it). Tested here on macOS 27.
- A Steam account owning Pioneers of Pagonia.
- A free Apple developer account for the GPTK download.
- About 20 GB free disk space (wrapper plus game).

## Downloads

| What                                                        | Where                                                   | Notes                                                                                                                                                                                  |
| ----------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Porting Kit 7.0.2, Apple Silicon build                      | https://paulthetall.itch.io/porting-kit                 | File `Porting.Kit-7.0.2-Apple Silicon.dmg`. Take the Apple Silicon one, not Intel.                                                                                                     |
| Game Porting Toolkit 4.0 beta 2, evaluation environment DMG | https://developer.apple.com/games/game-porting-toolkit/ | "Download Game Porting Toolkit 4", then the "Evaluation environment for Windows games" DMG. Sign in with the developer account. File used here: `Game_Porting_Toolkit_4.0_beta_2.dmg`. |
| Steam Windows client                                        | installed by Porting Kit                                | nothing to download by hand                                                                                                                                                            |

## Step 1: install Steam and the game through Porting Kit

1. Open the Porting Kit DMG and drag Porting Kit into Applications.
2. In Porting Kit, open the Library, choose Sources, then Steam.
3. In the first row (Steam logo), pick the **Steambuild Metal** preset. Not DXVK: the later steps
   depend on D3DMetal being the D3D12 layer.
4. Wait for the install. The wrapper ends up at:
   ```
   ~/Applications/Steambuild 32 64bit Metal.app
   ```
5. Launch the wrapper, sign in to Steam, install Pioneers of Pagonia. The game lands at:
   ```
   ~/Applications/Steambuild 32 64bit Metal.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Pioneers of Pagonia/
   ```
6. Launch the game once. Expected failure: **"No Compatible Graphics Hardware Was Found"**. That is the
   stock GPTK 3 D3DMetal reporting Resource Binding Tier 2 and Shader Model 6.0, which the engine
   rejects. It confirms you are at the thread's starting point.

## Step 2: overlay GPTK 4 D3DMetal into the wrapper

Mount the GPTK DMG, then merge (never replace) the two library folders. `ditto` merges directory
contents; a plain `mv` of `wine/` would delete `ntdll.so` and break Wine.

```bash
cd ~/Applications/"Steambuild 32 64bit Metal.app"/Contents/SharedSupport/wine/lib
ls                                   # expect: external  wine
find . -name 'ntdll.so'              # note that it exists
ls /Volumes/*/redist/lib             # expect: external  wine (from the DMG)

mv external external.old
ditto /Volumes/*/redist/lib/external external
ditto /Volumes/*/redist/lib/wine wine

find . -name 'ntdll.so'              # must still be found
```

Enable the Metal 4 backend. This is per login session; re-run after a reboot:

```bash
launchctl setenv D3DM_MTL4 1
```

Quit the wrapper completely, relaunch it, start the game. Expected failure now: a popup saying
**"DirectX 12 Agility SDK could not be loaded / update to Windows 10 1909"**. That means the GPU
check passed and the overlay worked.

## Step 3: skip the Agility SDK check with engine flags

The thread worked around the 1909 popup with a registry edit, a version resource patch of Apple's
`dxgi.dll` and `d3d12.dll`, DLL overrides, and a static import appended to the game's `dxil.dll`.
None of that is needed any more. Developer Ralf announced a bypass flag in post 70, and scanning
the 1.5.2 game executable for UTF-16 strings shows it shipped:

```
-NoDX12DeviceFactory      (Ralf, post 62: use the old device creation path, avoids D3D12GetInterface)
-NoDX12SDKVersionCheck    (Ralf, post 70: skip the Agility SDK / D3D12Core presence check)
```

In the Steam client inside the wrapper: right-click the game, Properties, General, Launch Options:

```
-NoDX12DeviceFactory -NoDX12SDKVersionCheck
```

Launch. Expected result: main menu, maps load, no ground or grass.

Checked and not needed on this machine: the prefix already has `CurrentBuild` 19043 in
`system.reg`, above the 18363 minimum the engine checks, so the registry step from the thread was
skipped. No DLL overrides for `d3d12`, `dxgi` or `d3d12core` were added.

## What is still broken

- **Terrain and grass missing.** D3DMetal's shader converter fails on the terrain hull shaders:
  `Compilation of function 'irconverter_hull_shader' failed ... "Failed to materializeAll."` and the
  pipelines become no-ops. No engine fallback exists (Ralf, post 70). Apple Feedback IDs from the
  thread: FB23835909, FB24521881. Next steps are in `MADEIRA_PORT_PLAN.md`.

## Things that undo the setup

- Rebooting clears `D3DM_MTL4`. Re-run the `launchctl setenv` line.
- Reinstalling or updating the Porting Kit Steam preset replaces the wrapper and the GPTK overlay.
- Game updates do not affect anything here, since no game files were modified.

## Useful paths

| Item                               | Path                                                                               |
| ---------------------------------- | ---------------------------------------------------------------------------------- |
| Wrapper Wine libs (overlay target) | `~/Applications/Steambuild 32 64bit Metal.app/Contents/SharedSupport/wine/lib`     |
| Wine prefix                        | `~/Applications/Steambuild 32 64bit Metal.app/Contents/SharedSupport/prefix`       |
| Game settings                      | `.../prefix/drive_c/users/Wineskin/AppData/Local/Pioneers of Pagonia/settings.ini` |
| Saves                              | `.../prefix/drive_c/users/Wineskin/Saved Games/Pioneers of Pagonia`                |
| Bundled Agility runtime            | `.../common/Pioneers of Pagonia/D3D12/D3D12Core.dll`                               |

Other engine flags seen in the executable, untested: `-NoAftermath`, `-NoDAQShadows`,
`-NoProtonInformation`, `-NoGOGLogin`.
