#!/bin/bash
# Run Madeira's D3D12 test executables inside the Madeira wrapper copy.
# Usage: ./run_tests.sh [m2|vfetch|cube|all]   (default: all)
#   WMT_TRACE_RENDER=1  prints every render pass / viewport / PSO / draw (winemetal.so)
#   MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=nslog  Metal API validation
set -u
A="$HOME/Applications/Steambuild-Madeira.app"
W="$A/Contents/SharedSupport/wine"
export WINEPREFIX="$A/Contents/SharedSupport/prefix"
export WINEDEBUG="${WINEDEBUG:--all}"
# wineserver links @rpath/libinotify.0.dylib etc. from Contents/Frameworks; the
# Wineskin launcher sets this, a direct wine64 call must too.
export DYLD_FALLBACK_LIBRARY_PATH="$A/Contents/Frameworks:/usr/lib"
cd "$WINEPREFIX/drive_c/madeira-tests" || exit 1
what="${1:-all}"
run() { echo "=== $1"; timeout "${2:-180}" "$W/bin/wine64" "C:\\madeira-tests\\$1" 2>&1; }
case "$what" in
  m2)     run d3d12-m2-x64.exe | grep -E "FAIL|checks" ;;
  vfetch) run d3d12-vfetch-x64.exe | grep -E "FAIL|checks" ;;
  cube)   run d3d12-cube-x64.exe 30 | grep -E "^cube|presenter|COMMAND BUFFER" ;;   # a window with a tumbling textured cube for 30 s
  all)    run d3d12-m2-x64.exe | grep -E "FAIL|checks"; run d3d12-vfetch-x64.exe | grep -E "FAIL|checks"; run d3d12-cube-x64.exe 30 | grep -E "^cube|presenter|COMMAND BUFFER" ;;
  *) echo "usage: $0 [m2|vfetch|cube|all]"; exit 2 ;;
esac
