#!/usr/bin/env bash
# Збирає бібліотеку лісу з нуля: джерела крон → атласи → GLB і атласи в assets/props/forest/.
#
# Запуск: tools/blender/forest/build_all.sh <тека_джерел> [atlas]
#   <тека_джерел> — поза репозиторієм: .blend з Poly Haven (ph/), рендери пучків і будова
#                   дерев (crowns/), атласи (atlas/), журнали кроків (log/);
#   atlas         — лише атласи й GLB з уже готових джерел (без рендерів, ~5 хв замість ~1 год).
# Blender — змінна BLENDER (типово blender), завжди -b. Усі числа вузлів — у specs/.
#
# Порядок:
#   1. fetch_polyhaven.py — pine_tree_01, fir_tree_01 (CC0);
#   2. src_conifer.py на кожне хвойне дерево, src_pine_tufts.py — спрайти хвої;
#   3. src_leaf_sprites.py на кожен набір × сезон (+ пожовклі берези й дуби);
#   4. src_broadleaf.py — будова листяних, кущів, узлісся, колод, підстилки (без Blender);
#   5. specs/make_broadleaf_specs.py, далі make_atlas.py і build_library.py на кожен spec;
#   6. build_ground.py — земля просіки.
set -euo pipefail
F="$(cd "$(dirname "$0")" && pwd)"
A="$(cd "$F/../../.." && pwd)/assets/props/forest"
S="${1:?потрібна тека джерел поза репозиторієм}"
B="${BLENDER:-blender}"
mkdir -p "$S/crowns" "$S/atlas" "$S/log"

# Крок у Blender: журнал у log/<ім'я>.txt; помилка скрипта — ненульовий код і зупинка.
blend() {
	local name="$1"; shift
	echo "== $name"
	"$B" -b --factory-startup --python-exit-code 1 -P "$@" > "$S/log/$name.txt" 2>&1 || {
		tail -n 30 "$S/log/$name.txt"; exit 1; }
}

if [ "${2:-}" != atlas ]; then
	python3 -I "$F/fetch_polyhaven.py" "$S/ph" > "$S/log/fetch.txt"
	P="$S/ph/pine_tree_01/pine_tree_01_1k.blend"
	R="$S/ph/fir_tree_01/fir_tree_01_1k.blend"
	C="$S/crowns"
	# <об'єкт> <тег> воксель карток частка_без_крони спрайтів [skirt]
	blend pine_a "$F/src_conifer.py" -- "$P" pine_tree_01_a_LOD1 "$C" pine_a 1.0 70 0.5 8
	blend pine_b "$F/src_conifer.py" -- "$P" pine_tree_01_b_LOD1 "$C" pine_b 1.0 68 0.35 8
	blend pine_c "$F/src_conifer.py" -- "$P" pine_tree_01_c_LOD1 "$C" pine_c 1.0 70 0.45 8
	blend spruce_a "$F/src_conifer.py" -- "$R" fir_tree_01_a_LOD1 "$C" spruce_a 1.0 70 0.0 8
	blend spruce_b "$F/src_conifer.py" -- "$R" fir_tree_01_b_LOD1 "$C" spruce_b 1.0 30 0.0 8 skirt
	# Ялинові пучки — теж із соснових гілочок (у fir_tree_01 гілочки без хвої).
	blend pine_tufts "$F/src_pine_tufts.py" -- "$P" "$C" 10 pine
	blend spruce_tufts "$F/src_pine_tufts.py" -- "$P" "$C" 10 spruce
	for k in birch broad oak shrub; do
		for s in late summer early; do
			blend "leaf_${k}_$s" "$F/src_leaf_sprites.py" -- "$C" "$k" "$s" 8
		done
	done
	for k in birch oak; do
		blend "leaf_${k}_turned" "$F/src_leaf_sprites.py" -- "$C" "$k" turned 8
	done
	python3 -I "$F/src_broadleaf.py" "$C" > "$S/log/broadleaf.txt"
fi

python3 -I "$F/specs/make_broadleaf_specs.py"
for spec in conifer broadleaf_late broadleaf_summer broadleaf_early; do
	python3 -I "$F/make_atlas.py" "$F/specs/$spec.json" "$S/crowns" "$S/atlas" > "$S/log/atlas_$spec.txt"
	blend "glb_$spec" "$F/build_library.py" -- "$F/specs/$spec.json" "$S/crowns" "$S/atlas" "$A/forest_$spec.glb"
	grep -E "^NODE" "$S/log/glb_$spec.txt" | tr '\n' ' '; echo
done
blend ground "$F/build_ground.py" -- "$A/forest_ground.glb"
echo "готово: $A"
