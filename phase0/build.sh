#!/bin/zsh
# Build the Phase 0 harnesses against the installed Metal Shader Converter.
set -e
cd "${0:A:h}"
clang++ -std=c++17 -fobjc-arc -framework Metal -framework Foundation load_metallib.mm -o load_metallib
clang++ -std=c++17 -fobjc-arc -I/usr/local/include -L/usr/local/lib -lmetalirconverter -Wl,-rpath,/usr/local/lib \
    -framework Metal -framework Foundation tess_pipeline.mm -o tess_pipeline
echo built
