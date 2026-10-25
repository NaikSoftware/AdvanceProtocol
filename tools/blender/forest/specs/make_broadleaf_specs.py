"""Пише specs/broadleaf_{late,summer,early}.json: набір вузлів один, різняться спрайти й тон.

Запуск: python3 -I make_broadleaf_specs.py
Тон — середні L*, C* і тон h непрозорих текселів пучка (CIELAB), під настрій карт:
- пізня осінь — голе гілля: L* 30, C* 4, листя ≤ 10 % (буре листя тримає лише дуб);
  крону тримає гілля-геометрія (`*_bare`), пучків лишається половина, у поодиноких — 8–20 %;
- літо — листя L* 28–38 на сонці, C* до ~25, перепади яскравості стиснуті до 0,45;
- рання осінь — половина берез і дубів пожовкла (береза жовта L* 55–65, C* 35–45,
  h 80–90; дуб світло-бурий L* 38–48, C* 25–35, h 60–75), решта жовто-зелена.
Береза в листі ріденька (половина пучків): у неї ажурна звисла крона, а не куля.
Пожовклі крони ранньої осені розфарбовує дошка цілими деревами (колір екземпляра), а не
окремими пучками: інакше осінь читалась конфеті. Набори *_turned лишаються в атласі.
Дерева зменшено (`scale`): сосна 12–14 м, листяні 10–12 м, береза 9–11 м — заради читання
з камери гри; кущі, узлісся й повалені стовбури — у справжньому розмірі.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GREEN = {
    "summer": {"L": 36, "C": 14, "h": 125, "contrast_l": 0.45},
    "early": {"L": 38, "C": 16, "h": 110, "contrast_l": 0.5},
    "late": {"L": 30, "C": 4, "h": 70, "contrast_l": 0.9},
}
TURNED = {"birch": {"L": 60, "C": 40, "h": 85, "contrast_l": 0.8},
          "oak": {"L": 43, "C": 30, "h": 68, "contrast_l": 0.8}}
LITTER = {"L": 28, "C": 6, "h": 70, "contrast_l": 0.9}
CUTOFF = {"summer": 0.45, "early": 0.45, "late": 0.45}
KEEP = {"summer": 1.0, "early": 1.0, "late": 0.55}
BARK = {"birch": {"target_y": 0.16, "sat": 0.5}, "oak": {"target_y": 0.06}, "lime": {"target_y": 0.07}}

# вузол, джерело будови, набір спрайтів, кора, додатково
ITEMS = [
    ("Birch_A", "birch_a", "birch", "birch", {"late_src": "birch_a_bare", "leafy_keep": 0.7, "scale": 0.56, "card_scale": 1.4}),
    ("Birch_B", "birch_b", "birch", "birch", {"late_src": "birch_b_bare", "leafy_keep": 0.7, "scale": 0.63, "card_scale": 1.4}),
    ("Oak_A", "oak_a", "oak", "oak", {"late_src": "oak_a_bare", "leafy_keep": 0.85, "scale": 0.58, "card_scale": 1.6}),
    ("Oak_B", "oak_b", "oak", "oak", {"late_src": "oak_b_bare", "leafy_keep": 0.85, "scale": 0.6, "card_scale": 1.6}),
    ("Shrub_Hazel", "shrub_hazel", "shrub", "lime", {"trunk": False, "strip": True}),
    ("Shrub_Thorn", "shrub_thorn", "shrub", "oak", {"trunk": False, "strip": True}),
    ("Hedge_Shrub", "hedge_shrub", "shrub", "lime", {"trunk": False, "strip": True}),
    ("Log_A", "log_a", None, "oak", {"trunk": False, "strip": True}),
    ("Log_B", "log_b", None, "oak", {"trunk": False, "strip": True}),
    ("Litter_A", "litter_a", None, "oak", {"trunk": False, "flat_sprites": "litter"}),
    ("Hero_Oak", "hero_oak", "oak", "oak", {"trunk_sides": 6, "late_keep": 0.2, "scale": 0.63, "card_scale": 1.3}),
    ("Hero_Lime", "hero_lime", "broad", "lime", {"trunk_sides": 6, "late_keep": 0.18, "scale": 0.6, "card_scale": 1.3}),
    ("Hero_Birch", "hero_birch", "birch", "birch", {"trunk_sides": 6, "late_keep": 0.2, "scale": 0.62, "card_scale": 1.3}),
    ("Hero_Poplar", "hero_poplar", "broad", "lime", {"trunk_sides": 6, "late_keep": 0.08, "scale": 0.56, "card_scale": 1.3}),
]

for season in ("late", "summer", "early"):
    sets = {k: [{"src": "%s_%s" % (k, season), "grade": {"lab": GREEN[season]}}]
            for k in ("birch", "broad", "oak", "shrub")}
    sets["litter"] = [{"src": "broad_late", "max": 4, "grade": {"lab": LITTER}}]
    if season == "early":
        for k, g in TURNED.items():
            sets["%s_turned" % k] = [{"src": "%s_turned" % k, "grade": {"lab": g}}]
    items = []
    for node, src, spr, bark, extra in ITEMS:
        extra = dict(extra)
        early_set = extra.pop("early_set", None)
        late_keep = extra.pop("late_keep", None)
        late_src = extra.pop("late_src", None)
        leafy_keep = extra.pop("leafy_keep", None)
        it = {"node": node, "src": late_src if (season == "late" and late_src) else src, "trunk_grade": BARK[bark]}
        if spr:
            it["sprites"] = early_set if (season == "early" and early_set) else spr
        if season == "late" and late_keep:
            it["card_keep"] = late_keep
        if season != "late" and leafy_keep:
            it["card_keep"] = leafy_keep
        if node.startswith(("Hedge", "Shrub", "Log", "Litter")):
            it["card_keep"] = 1.0
        it.update(extra)
        items.append(it)
    # Клітинка 256 px (≈0,9 см на тексель для пучка 2,4 м): на 128 px ближні крони на
    # мінімальному зумі були розмиті.
    spec = {"atlas": "forest_broadleaf_%s" % season, "size": 2048, "cell": 256, "alpha_cutoff": CUTOFF[season],
            "card_keep": KEEP[season], "sprite_sets": sets, "items": items}
    with open(os.path.join(HERE, "broadleaf_%s.json" % season), "w") as f:
        json.dump(spec, f, indent=1)
    print("spec", season, len(items))
