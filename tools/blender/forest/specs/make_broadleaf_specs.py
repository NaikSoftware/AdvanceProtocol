"""Пише specs/broadleaf_{late,summer,early}.json: набір вузлів один, різняться спрайти й тон.

Запуск: python3 -I make_broadleaf_specs.py
Тон — середні L*, C* і тон h непрозорих текселів пучка (CIELAB), під настрій карт:
- пізня осінь — голі гілки: L* 20–32, C* < 10, листя ≤ 10 %;
- літо — листя L* 28–38 на сонці, C* до ~25;
- рання осінь — половина берез і дубів пожовкла (береза жовта L* 55–65, C* 35–45,
  h 80–90; дуб світло-бурий L* 38–48, C* 25–35, h 60–75), решта жовто-зелена.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GREEN = {
    "summer": {"L": 42, "C": 22, "h": 118, "contrast_l": 0.75},
    "early": {"L": 40, "C": 20, "h": 106, "contrast_l": 0.8},
    "late": {"L": 26, "C": 6, "h": 70, "contrast_l": 0.9},
}
TURNED = {"birch": {"L": 60, "C": 40, "h": 85, "contrast_l": 0.8},
          "oak": {"L": 43, "C": 30, "h": 68, "contrast_l": 0.8}}
CUTOFF = {"summer": 0.45, "early": 0.45, "late": 0.45}
# Частка пучків, що лишається: голе дерево пропускає 45–60 % погляду згори.
KEEP = {"summer": 1.0, "early": 1.0, "late": 0.5}
BARK = {"birch": {"target_y": 0.30, "sat": 0.5}, "oak": {"target_y": 0.06}, "lime": {"target_y": 0.07}}

# вузол, джерело будови, набір спрайтів, кора, додатково
ITEMS = [
    ("Birch_A", "birch_a", "birch", "birch", {"early_set": "birch_turned"}),
    ("Birch_B", "birch_b", "birch", "birch", {}),
    ("Oak_A", "oak_a", "oak", "oak", {"card_scale": 1.2, "early_set": "oak_turned"}),
    ("Oak_B", "oak_b", "oak", "oak", {"card_scale": 1.2}),
    ("Shrub_Hazel", "shrub_hazel", "shrub", "lime", {"trunk": False, "strip": True}),
    ("Shrub_Thorn", "shrub_thorn", "shrub", "oak", {"trunk": False, "strip": True}),
    ("Log_A", "log_a", None, "oak", {"trunk": False, "strip": True}),
    ("Log_B", "log_b", None, "oak", {"trunk": False, "strip": True}),
    ("Hero_Oak", "hero_oak", "oak", "oak", {"trunk_sides": 6, "early_set": "oak_turned", "late_keep": 0.18}),
    ("Hero_Lime", "hero_lime", "broad", "lime", {"trunk_sides": 6, "late_keep": 0.16}),
    ("Hero_Birch", "hero_birch", "birch", "birch", {"trunk_sides": 6, "early_set": "birch_turned", "late_keep": 0.1}),
    ("Hero_Poplar", "hero_poplar", "broad", "lime", {"trunk_sides": 6, "late_keep": 0.08}),
]

for season in ("late", "summer", "early"):
    sets = {k: [{"src": "%s_%s" % (k, season), "grade": {"lab": GREEN[season]}}]
            for k in ("birch", "broad", "oak", "shrub")}
    if season == "early":
        for k, g in TURNED.items():
            sets["%s_turned" % k] = [{"src": "%s_turned" % k, "grade": {"lab": g}}]
    items = []
    for node, src, spr, bark, extra in ITEMS:
        it = {"node": node, "src": src, "trunk_grade": BARK[bark]}
        extra = dict(extra)
        early_set = extra.pop("early_set", None)
        late_keep = extra.pop("late_keep", None)
        if spr:
            it["sprites"] = early_set if (season == "early" and early_set) else spr
        if season == "late" and late_keep:
            it["card_keep"] = late_keep
        it.update(extra)
        items.append(it)
    spec = {"atlas": "forest_broadleaf_%s" % season, "size": 1024, "alpha_cutoff": CUTOFF[season],
            "card_keep": KEEP[season], "sprite_sets": sets, "items": items}
    with open(os.path.join(HERE, "broadleaf_%s.json" % season), "w") as f:
        json.dump(spec, f, indent=1)
    print("spec", season, len(items))
