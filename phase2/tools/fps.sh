#!/bin/bash
# fps.sh <log> [N]: last N ml1108 perf lines as "fps gpu_ms" plus their mean
L=$1; N=${2:-6}
grep "ml1108" "$L" | tail -$N | sed -E 's/.*presents=([0-9]+) \(([0-9.]+) fps\).*gpu_busy=([0-9]+)ms \(([0-9]+)% of wall.*per-frame: gpu ([0-9.]+)ms.*/fps=\2 gpu_busy=\4% gpu_per_frame=\5ms/' 
grep "ml1108" "$L" | tail -$N | sed -E 's/.*\(([0-9.]+) fps\).*/\1/' | awk '{s+=$1; n++} END{if(n) printf "mean fps %.1f over %d samples\n", s/n, n}'
