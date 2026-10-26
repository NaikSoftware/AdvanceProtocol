#!/bin/bash
# Тягне CC0-матеріали ambientCG (1K JPG) у art-refs/buildings_tex/<імʼя>/; кеш не комітиться.
set -e
OUT="$(dirname "$0")/../../../art-refs/buildings_tex"
mkdir -p "$OUT"
# без цього Godot імпортує .blend із ambientCG і --import мовчки падає
touch "$OUT/.gdignore"
for m in Concrete034 Concrete046 Plaster001 CorrugatedSteel005 CorrugatedSteel007A Bricks105 MetalPlates013 Asphalt031 Concrete019 PaintedMetal012 Rust004 Planks021 Bark012; do
  [ -d "$OUT/$m" ] && continue
  mkdir -p "$OUT/$m"
  curl -sL -o "$OUT/$m.zip" "https://ambientcg.com/get?file=${m}_1K-JPG.zip"
  python3 -I -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$OUT/$m.zip" "$OUT/$m"
  rm "$OUT/$m.zip"
done

# завал: ambientCG Ground111 (2K) і Poly Haven broken_brick_wall (2K, CC0)
if [ ! -d "$OUT/Ground111" ]; then
  mkdir -p "$OUT/Ground111"
  curl -sL -o "$OUT/Ground111.zip" "https://ambientcg.com/get?file=Ground111_2K-JPG.zip"
  python3 -I -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$OUT/Ground111.zip" "$OUT/Ground111"
  rm "$OUT/Ground111.zip"
fi
if [ ! -f "$OUT/broken_brick_wall/diff.jpg" ]; then
  mkdir -p "$OUT/broken_brick_wall"
  U=$(curl -s https://api.polyhaven.com/files/broken_brick_wall | python3 -I -c "import json,sys;print(json.load(sys.stdin)['Diffuse']['2k']['jpg']['url'])")
  curl -sL -o "$OUT/broken_brick_wall/diff.jpg" "$U"
fi
# шорсткість цегли з того самого скану: make_material бере її в ORM (без неї цегла рівно матова)
if [ ! -f "$OUT/broken_brick_wall/rough.jpg" ]; then
  U=$(curl -s https://api.polyhaven.com/files/broken_brick_wall | python3 -I -c "import json,sys;print(json.load(sys.stdin)['Rough']['2k']['jpg']['url'])")
  curl -sL -o "$OUT/broken_brick_wall/rough.jpg" "$U"
fi
