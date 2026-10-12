#!/bin/bash
# gputrace.sh <seconds> : record Metal System Trace of the game, export GPU encoder intervals, aggregate by label
set -u
S=$(dirname "$0"); secs=${1:-5}
PID=$(pgrep -f "Pioneers of Pagonia.exe" | head -1); [ -z "$PID" ] && { echo "no game pid"; exit 1; }
rm -rf "$S/game.trace"
xcrun xctrace record --template 'Metal System Trace' --attach "$PID" --time-limit "${secs}s" --output "$S/game.trace" >"$S/xctrace.log" 2>&1 || { tail -5 "$S/xctrace.log"; exit 1; }
xcrun xctrace export --input "$S/game.trace" --toc > "$S/toc.xml" 2>&1
grep -o 'schema="[^"]*"' "$S/toc.xml" | sort | uniq -c
