#!/bin/bash
# Launch Pioneers of Pagonia through Steam inside the Madeira wrapper copy, bypassing the
# Wineskin launcher so the environment is explicit and stderr lands in a file.
# Usage: run_game.sh [steam|game|kill]   (default: game = Steam.exe -applaunch 2155180)
#   Env passthrough: WINEDEBUG (default -all), WMT_TRACE_RENDER, MTL_DEBUG_LAYER, ...
# Madeira's d3d12.dll, d3d12core.dll and DXMT's dxgi.dll sit in the game folder and are
# selected with native-first overrides; Steam's own processes fall back to the builtins.
set -u
A="$HOME/Applications/Steambuild-Madeira.app"
W="$A/Contents/SharedSupport/wine"
export WINEPREFIX="$A/Contents/SharedSupport/prefix"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-dxgi,d3d12,d3d12core=n,b}"
export WINEESYNC=1 WINEMSYNC=1
export MADEIRA_DOCS_DIR="${MADEIRA_DOCS_DIR:-$(cd "$(dirname "$0")" && pwd)}"   # madeira.cfg lives next to this script
export DYLD_FALLBACK_LIBRARY_PATH="$A/Contents/Frameworks:/usr/lib"
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/run-$(date +%Y%m%d-%H%M%S).log"
STEAM='C:\Program Files (x86)\Steam\Steam.exe'
case "${1:-game}" in
  steam) echo "log: $LOG"; "$W/bin/wine64" "$STEAM" -silent >"$LOG" 2>&1 ;;
  game)  echo "log: $LOG"; "$W/bin/wine64" "$STEAM" -silent -applaunch 2155180 >"$LOG" 2>&1 ;;
  kill)  "$W/bin/wineserver" -k ;;
  *) echo "usage: $0 [steam|game|kill]"; exit 2 ;;
esac
