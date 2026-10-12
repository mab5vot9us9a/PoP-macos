#!/bin/zsh
# Run tess_pipeline over every row of pairs.tsv. Usage: ./run_pairs.sh SHADER_DIR > results.log
cd "${0:A:h}"
S=$1
while IFS=$'\t' read -r vs hs ds ps; do
  [[ $ps == NONE ]] && { echo "SKIP no PS for $hs/$ds"; continue; }
  r=$(${BIN:-./tess_pipeline} "$S/$vs" "$S/$hs" "$S/$ds" "$S/$ps" ${EXTRA:-} 2>&1)
  v=${vs#Pioneers of Pagonia.exe_}; h=${hs#Pioneers of Pagonia.exe_}; d=${ds#Pioneers of Pagonia.exe_}; p=${ps#Pioneers of Pagonia.exe_}
  if echo "$r" | grep -q "PIPELINE OK"; then
    echo "OK   vs=${v%.dxbc} hs=${h%.dxbc} ds=${d%.dxbc} ps=${p%.dxbc}"
  else
    echo "FAIL vs=${v%.dxbc} hs=${h%.dxbc} ds=${d%.dxbc} ps=${p%.dxbc}"
    echo "$r" | grep -E "FAIL|PIPELINE" | sed 's/^/     /'
  fi
done < pairs.tsv
