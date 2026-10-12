#!/bin/zsh
# Convert all hull/domain/geometry DXIL shaders with metal-shaderconverter.
# Usage: ./convert_all.sh SHADER_DIR OUT_DIR
set -u
SRC=$1; OUT=$2; mkdir -p "$OUT"
HERE=${0:A:h}
for f in "$SRC"/*_{hs,ds,gs}6_0.dxbc; do
  b=$(basename "$f" .dxbc); b=${b#Pioneers of Pagonia.exe_}
  for mode in plain emu; do
    extra=()
    [[ $mode == emu ]] && extra=(--enable-gs-ts-emulation --vertex-input-layout-file="$HERE/dummy_layout.json")
    if metal-shaderconverter "$f" -o "$OUT/${b}_$mode.metallib" --minimum-gpu-family Metal3 \
         --output-reflection-file "$OUT/${b}_$mode.refl.json" "${extra[@]}" > "$OUT/${b}_$mode.log" 2>&1; then
      echo "OK   $mode $b"
    else
      echo "FAIL $mode $b: $(head -c 300 "$OUT/${b}_$mode.log")"
    fi
  done
done
