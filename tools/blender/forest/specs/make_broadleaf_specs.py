"""Пише specs/broadleaf_{late,summer,early}.json: набір вузлів один, різняться спрайти й тон.

Запуск: python3 -I make_broadleaf_specs.py
Тон за сезоном — під настрій сцени (docs/art/props-research.md, «Forest»): літо — на 40 %
менші перепади яскравості листя, рання осінь — жовто-зелене з 10–20 % жовтогарячого
й насиченістю до ~25 (C* у Lab), пізня — голі гілки з поодиноким бурим листям.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LEAF = {
    "summer": {"sat": 0.75, "contrast": 0.6, "target_y": 0.055},
    "early": {"sat": 0.62, "contrast": 0.7, "target_y": 0.08},
    "late": {"tint": [1.05, 1.0, 0.86], "sat": 0.45, "contrast": 0.8, "target_y": 0.06},
}
CUTOFF = {"summer": 0.45, "early": 0.45, "late": 0.45}
# Частка пучків, що лишається: голе дерево має пропускати 45–60 % погляду згори.
KEEP = {"summer": 1.0, "early": 1.0, "late": 0.55}
BARK = {"birch": {"target_y": 0.30, "sat": 0.5}, "oak": {"target_y": 0.06}, "lime": {"target_y": 0.07}}

ITEMS = [
    ("Birch_A", "birch_a", "birch", "birch", {}),
    ("Birch_B", "birch_b", "birch", "birch", {}),
    ("Oak_A", "oak_a", "oak", "oak", {"card_scale": 1.2}),
    ("Oak_B", "oak_b", "oak", "oak", {"card_scale": 1.2}),
    ("Shrub_Hazel", "shrub_hazel", "shrub", "lime", {"trunk": False, "strip": True}),
    ("Shrub_Thorn", "shrub_thorn", "shrub", "oak", {"trunk": False, "strip": True}),
    ("Log_A", "log_a", None, "oak", {"trunk": False, "strip": True}),
    ("Log_B", "log_b", None, "oak", {"trunk": False, "strip": True}),
    # Крона поодинокого дерева 12–16 м: пучок у 1,6 раза більший (3,8 м, ~3 см на тексель),
    # інакше 85 карток не закривають купол і він розсипається на окремі плями.
    ("Hero_Oak", "hero_oak", "oak", "oak", {"trunk_sides": 6, "card_scale": 1.6}),
    ("Hero_Lime", "hero_lime", "broad", "lime", {"trunk_sides": 6, "card_scale": 1.5}),
    ("Hero_Birch", "hero_birch", "birch", "birch", {"trunk_sides": 6, "card_scale": 1.25}),
    ("Hero_Poplar", "hero_poplar", "broad", "lime", {"trunk_sides": 6, "card_scale": 1.3}),
]

for season in ("late", "summer", "early"):
    g = dict(LEAF[season])
    sets = {k: [{"src": "%s_%s" % (k, season), "grade": g}]
            for k in ("birch", "broad", "oak", "shrub")}
    items = []
    for node, src, spr, bark, extra in ITEMS:
        it = {"node": node, "src": src, "trunk_grade": BARK[bark]}
        if spr:
            it["sprites"] = spr
        it.update(extra)
        items.append(it)
    spec = {"atlas": "forest_broadleaf_%s" % season, "size": 1024, "alpha_cutoff": CUTOFF[season],
            "card_keep": KEEP[season], "sprite_sets": sets, "items": items}
    with open(os.path.join(HERE, "broadleaf_%s.json" % season), "w") as f:
        json.dump(spec, f, indent=1)
    print("spec", season, len(items))
