#!/bin/bash
# Копіює GLB у assets/props, імпортує й знімає превʼю камерою гри (потрібне вікно).
# Використання: [FLAGS="--rl --back"] shoot.sh <name> ...
# Видаляємо лише витягнуті з GLB текстури знімуваних активів: Godot не перезаписує вже витягнуту карту нормалей, тож стара лишалась би
# в кадрі. .import чужих активів не чіпаємо: вони тримають стабільні uid (видалення зсувало uid у чужих сценах).
set -o pipefail
cd "$(dirname "$0")/../../.."
G="${GODOT:-godot}"
for n in "$@"; do
  cmp -s "art-refs/buildings_out/$n.glb" "assets/props/$n.glb" || cp "art-refs/buildings_out/$n.glb" assets/props/
  rm -f "assets/props/${n}.glb.import" "assets/props/${n}_${n}_atlas.jpg" "assets/props/${n}_${n}_atlas.jpg.import" "assets/props/${n}_${n}_normal.png" "assets/props/${n}_${n}_normal.png.import" \
        "assets/props/${n}_${n}_normal.jpg" "assets/props/${n}_${n}_normal.jpg.import"
done
timeout 120 "$G" --headless --import --path . >/dev/null 2>&1
git checkout project.godot
timeout 170 "$G" --path . res://tools/prop_preview.tscn -- "$PWD/art-refs/buildings" ${FLAGS:---graze --back --tank --side} "$@" 2>&1 | grep -E "PROP|ERROR"
