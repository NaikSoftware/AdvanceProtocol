#!/bin/bash
# Тягне CC0-матеріали ambientCG (1K JPG) у art-refs/buildings_tex/<імʼя>/; кеш не комітиться.
set -e
OUT="$(dirname "$0")/../../../art-refs/buildings_tex"
mkdir -p "$OUT"
# без цього Godot імпортує .blend із ambientCG і --import мовчки падає
touch "$OUT/.gdignore"
for m in Concrete034 Concrete046 Plaster001 CorrugatedSteel005 CorrugatedSteel007A Bricks105 MetalPlates013 Asphalt031 Concrete019 PaintedMetal012 Rust004; do
  [ -d "$OUT/$m" ] && continue
  mkdir -p "$OUT/$m"
  curl -sL -o "$OUT/$m.zip" "https://ambientcg.com/get?file=${m}_1K-JPG.zip"
  python3 -I -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$OUT/$m.zip" "$OUT/$m"
  rm "$OUT/$m.zip"
done
