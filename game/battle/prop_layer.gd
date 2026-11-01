class_name PropLayer
extends Node3D
## Пропси поля бою: будівлі, руїни, мости, огорожі, тюки, опори з дротами, причепи, блоки,
## каміння. Лише вигляд — жодне правило їх не читає (docs/art-direction.md «Props»): будівля
## стоїть тільки на клітинках BUILDING і вміщається в їхню групу цілими тайлами, дрібні пропси —
## біля країв прохідних клітинок, ніколи в центрі, де стоїть юніт; техніка, що в'їхала, їх
## розчавлює. Розстановка — чиста функція дошки: той самий світ → ті самі перетворення, усе з
## cell_hash, ніколи Rules.roll чи глобальна випадковість, бо обидва гравці мусять бачити одне.
## Одна MultiMesh на модель — один вузол і по draw call на поверхню (§8).

enum Kind { STRUCTURE, RUIN, BRIDGE, FIELD_FENCE, GARDEN_FENCE, HAY, POLE, TRAILER, BLOCK, BOULDER, YARD }
## Як виглядає розчавлене: LAY — повалене набік, SQUASH — сплющене, SINK — втиснуте в землю.
enum Crush { NONE, LAY, SQUASH, SINK }

const MODEL_DIR: String = "res://assets/props/"
## Модель -> {kind, weight, …}. Слід будівлі в тайлах — з метаданих GLB (`footprint_tiles`), тож
## нова модель того самого виду стає в слот за самим ім'ям. Модель без файлу пропускається.
## max — скільки разів на карту (орієнтир, що має лишатись одним), ring — лише в кільці, gap —
## власний проміжок до сусідньої будівлі, якщо більший за STRUCTURE_GAP, tower —
## вежа (одна на карту, у власному дворі), storeys — двоповерховий (у селі їх не більше половини),
## damaged — пошкоджена модель (її димар не димить), scale — рівномірний множник розміру (брила завелика для польового каменя, хата на клітинку
## заширока, щоб між сусідніми з камери гри було видно землю),
## map/order/deck_top — міст своєї переправи (DECK_TOP з tools/blender/bridges/build_bridges.py).
const MODELS: Dictionary = {
	&"house_h1": {"kind": Kind.STRUCTURE, "weight": 4},
	&"house_h1_hit": {"kind": Kind.STRUCTURE, "damaged": true, "weight": 1},
	&"house_h2": {"kind": Kind.STRUCTURE, "weight": 3},
	&"house_h3": {"kind": Kind.STRUCTURE, "weight": 2, "storeys": 2},
	&"house_h4": {"kind": Kind.STRUCTURE, "weight": 4},
	&"house_h5": {"kind": Kind.STRUCTURE, "weight": 6, "scale": HOUSE_SCALE},
	&"house_h6": {"kind": Kind.STRUCTURE, "weight": 2, "storeys": 2, "scale": HOUSE_SCALE},
	&"house_h7": {"kind": Kind.STRUCTURE, "weight": 4, "scale": HOUSE_SCALE},
	&"house_h8": {"kind": Kind.STRUCTURE, "weight": 3, "scale": HOUSE_SCALE},
	&"f8_shed": {"kind": Kind.STRUCTURE, "weight": 2},
	&"f8_shed_brick": {"kind": Kind.STRUCTURE, "weight": 2, "yard_only": true},
	&"f8_shed_lean": {"kind": Kind.STRUCTURE, "weight": 2, "yard_only": true},
	&"h5_panel_block": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"h5_panel_block_damaged": {"kind": Kind.STRUCTURE, "damaged": true, "weight": 2, "max": 1},
	&"f1_farm_barn": {"kind": Kind.STRUCTURE, "weight": 1},
	&"f2_livestock_barn": {"kind": Kind.STRUCTURE, "weight": 2, "ring": true},
	&"f3_hangar": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f3_hangar_damaged": {"kind": Kind.STRUCTURE, "damaged": true, "weight": 2, "max": 1},
	&"f4_grain_bins": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f5_silo_battery": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f6_fuel_station": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f7_water_tower": {"kind": Kind.STRUCTURE, "weight": 1, "gap": 0.5, "tower": true},
	&"f7b_brick_tower": {"kind": Kind.STRUCTURE, "weight": 1, "gap": 0.5, "tower": true},
	&"ruin_h1": {"kind": Kind.RUIN, "weight": 1},
	&"ruin_h3": {"kind": Kind.RUIN, "weight": 1},
	&"bridge_river_west": {"kind": Kind.BRIDGE, "map": &"river", "order": 0, "deck_top": 0.30},
	&"bridge_river_centre": {"kind": Kind.BRIDGE, "map": &"river", "order": 1, "deck_top": 0.30},
	&"bridge_river_east": {"kind": Kind.BRIDGE, "map": &"river", "order": 2, "deck_top": 0.21},
	&"infra_fence_picket": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY},
	# Паркани дворів: п'ять видів однієї моделі (infra_fence_yard) і одного атласу — один вузол «batch» на всі двори.
	# Ім'я — «модель_вид»; номер виду (fence_kind_of) і верх кожного беруться з extras самої моделі
	# (tools/blender/infra/yard_fences.py), і номер іде в INSTANCE_CUSTOM (prop_thin лишає з картки лише його смугу).
	# gate — форма воріт цього паркану.
	&"infra_fence_yard_picket": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY, "glb": &"infra_fence_yard",
			"batch": &"infra_fence_yard", "gate": &"wood"},
	&"infra_fence_yard_sheet": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY, "glb": &"infra_fence_yard",
			"batch": &"infra_fence_yard", "gate": &"sheet"},
	&"infra_fence_yard_chainlink": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY, "glb": &"infra_fence_yard",
			"batch": &"infra_fence_yard", "gate": &"lattice"},
	&"infra_fence_yard_brickbars": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY, "glb": &"infra_fence_yard",
			"batch": &"infra_fence_yard", "gate": &"metal"},
	&"infra_fence_yard_slat": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY, "glb": &"infra_fence_yard",
			"batch": &"infra_fence_yard", "gate": &"slat"},
	# Паркани ферм і полів (FIELD_FENCE): профлист і єврозабір; двори обгороджує infra_fence_yard.
	&"infra_fence_sheet_green": {"kind": Kind.FIELD_FENCE, "crush": Crush.LAY, "height": 0.7},
	&"infra_fence_sheet_brown": {"kind": Kind.FIELD_FENCE, "crush": Crush.LAY, "height": 0.7},
	&"infra_fence_euro": {"kind": Kind.FIELD_FENCE, "crush": Crush.LAY},
	&"infra_hay_round": {"kind": Kind.HAY, "crush": Crush.SQUASH},
	&"infra_hay_wrapped": {"kind": Kind.HAY, "crush": Crush.SQUASH},
	&"infra_pole_concrete_10kv": {"kind": Kind.POLE, "line": &"10kv", "crush": Crush.LAY},
	&"infra_pole_concrete_04kv": {"kind": Kind.POLE, "line": &"04kv", "crush": Crush.LAY},
	&"infra_pole_wood": {"kind": Kind.POLE, "line": &"04kv", "crush": Crush.LAY},
	&"infra_trailer_green": {"kind": Kind.TRAILER, "crush": Crush.SQUASH},
	&"infra_trailer_rust": {"kind": Kind.TRAILER, "crush": Crush.SQUASH},
	&"infra_trailer_flatbed": {"kind": Kind.TRAILER, "crush": Crush.SQUASH},
	&"infra_trailer_tank": {"kind": Kind.TRAILER, "crush": Crush.SQUASH},
	&"infra_jersey_block": {"kind": Kind.BLOCK, "crush": Crush.LAY},
	&"rock_moss_01": {"kind": Kind.BOULDER, "crush": Crush.SINK, "scale": 0.55},
	&"rock_moss_02": {"kind": Kind.BOULDER, "crush": Crush.SINK, "scale": 0.6},
	&"rock_moss_03": {"kind": Kind.BOULDER, "crush": Crush.SINK},
	&"rock_moss_04": {"kind": Kind.BOULDER, "crush": Crush.SINK},
	&"boulder_01": {"kind": Kind.BOULDER, "crush": Crush.SINK},
	&"dead_tree_trunk_02": {"kind": Kind.YARD, "crush": Crush.SINK},
	# Колода для рубання дров біля хати.
	&"tree_stump_01": {"kind": Kind.YARD, "crush": Crush.SINK, "scale": 0.5},
}
## Руїни з глухим фронтоном збоку: ставляться пошкодженим фасадом (−Z) до камери (+x чи +z).
const CAMERA_FRONT: Array[StringName] = [&"ruin_half_house2"]
## Орієнтир кільця: кільце — декорація без правил, тож карта може мати в ньому свою велику руїну. Модель ставиться в кільці
## найближче до near (клітинка дошки), поворотом rot (2 — фасад із язиком завалу до камери), лише на вільному полі.
const RING_LANDMARKS: Dictionary = {}
## Руїни, яких у таблиці ще нема, стають у слот за префіксом імені: напівзруйнована будівля —
## звичайна, повна руїна — рідкісна. Перший збіг виграє.
## Моделі, що лежать на диску, але не ставляться: їх не бере ні таблиця, ні префікс.
## Панельні блоки — міська забудова, на сільських картах їм не місце; ресурси лишені для майбутньої карти міста.
const RETIRED: Array[StringName] = [&"h5_panel_block", &"h5_panel_block_damaged"]
const PREFIX_RULES: Array[Dictionary] = [
	{"prefix": "ruin_half_", "kind": Kind.RUIN, "weight": 6},
	{"prefix": "ruin_", "kind": Kind.RUIN, "weight": 1},
]
## Половина квадрата в центрі клітинки, куди не заходить жоден дрібний пропс: там стоїть юніт.
const KEEP_OUT: float = 0.2
## Слід юніта в центрі клітинки (півсторона квадрата, клітинки): дрібний пропс — тюк, причеп, колода
## — його не перетинає, а стовп стоїть ще на UNIT_POLE_CLEAR далі.
const UNIT_HALF: float = 0.3
const UNIT_POLE_CLEAR: float = 0.15
## Частка викинутих пікселів даху над юнітом (≈ 30 % непрозорості, docs/art/props-research.md).
## Будівля над юнітом — напівпрозора (альфа FADE_ALPHA), перехід за FADE_TIME секунд.
const FADE_ALPHA: float = 0.35
## Пріоритет прозорого проходу глибини розчиненої будівлі: вищий за вогонь, дим і дощ (1), нижчий за
## позначки над юнітом (UnitView.OVERLAY_PRIORITY).
const FADE_DEPTH_PRIORITY: int = 5
const FADE_TIME: float = 0.2
## Розчиняється лише будівля, вища за це (клітинки, ~4 м): нижча юніта не закриває.
const FADE_MIN_H: float = 0.5
## Сусіди, що розчиняються разом із клітинкою юніта: камера стоїть на +x, +z від фокуса (yaw 45°),
## тож саме ці клітинки лежать між юнітом і камерою.
const REVEAL_OFFSETS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
## Найдовший проліт ліній, клітинки: 10 кВ — 72 м, 0.4 кВ — 40 м (у селі 30–40 м).
const SPAN: Dictionary = {&"10kv": 9.0, &"04kv": 5.0}
## Провис дроту посередині прольоту — частка прольоту (~2.5 %): ланцюгова лінія при такому провисі
## не відрізняється від параболи.
const WIRE_SAG_RATIO: float = 0.012
const WIRE_SEGMENTS: int = 8
## Відвід до хати — від найближчої опори її вулиці до стіни з боку вулиці: не довший за це (16 м: довший проліт
## тягнеться над полем чи навскіс через вулицю) і не коротший за DROP_MIN (клітинки); кріпиться на висоті
## DROP_ATTACH_H (2.9 м) під звісом.
const DROP_DIRECT: float = 2.0
const DROP_MIN: float = 0.05
const DROP_ATTACH_H: float = 0.36
## Відвід тримається від чужих хат щонайменше на стільки.
const DROP_GAP: float = 0.1
## Відвід через вулицю — лише прямо впоперек: косинус кута до нормалі вулиці не менший (25°), проліт не довший
## (14 м, клітинки).
const DROP_CROSS_COS: float = 0.906
const DROP_CROSS: float = 1.75
## Проліт 0.4 кВ через вулицю (опора до опори впоперек) не довший за стільки (клітинки, 40 м).
const SPAN_CROSS: float = 5.0
## Відвід може читатися над власною хатою лише на стільки біля кріплення (клітинки, ~0.3 м).
const DROP_END_FREE: float = 0.04
## Над асфальтом дріт не довший за стільки ширин дороги: прямо впоперек — одна ширина, на 25° — 1.1.
const ROAD_SPAN_K: float = 1.2
## Дріт, що не перетинає вісь дороги, висить над асфальтом не довше за стільки (клітинки).
const ROAD_CLIP: float = 0.3
## Нахил камери, під яким дріт перевіряється на «над будівлею» — нахил рига на зумі WIRE_SEEN_ZOOM. Що нижча камера,
## то далі дріт зсунутий на екрані й то більше прольотів уздовж дворів відпадає. Це найнижчий нахил, за якого кожне
## поселення лишається з лінією й ТП, а відводи має 40–70 % хат на Річці й Перехресті (перебір нахилів 38–46.5°: нижче
## за ~44° головне село Перехрестя гасне). Під нижчою камерою (зум 6–10) окремий проліт може читатися біля фасаду.
const WIRE_SEEN_ZOOM: float = 11.0
const WIRE_SEEN_PITCH_DEG: float = IsoCameraRig.PITCH_NEAR_DEG + (IsoCameraRig.PITCH_FAR_DEG - IsoCameraRig.PITCH_NEAR_DEG) \
		* (WIRE_SEEN_ZOOM - IsoCameraRig.MIN_ZOOM) / (IsoCameraRig.MAX_ZOOM - IsoCameraRig.MIN_ZOOM)
## Нахил, під яким дріт перевіряється біля стовпчика димаря: найнижчий нахил рига — відвід не «закінчується» на димарі
## на жодному зумі, а густоти це не коштує.
const CHIMNEY_SEEN_PITCH_DEG: float = IsoCameraRig.PITCH_NEAR_DEG
## Дим руїни: вага висоти (клітинки на клітинку) проти відстані до центру, відступ від уцілілого димаря й підйом над уламком, клітинки.
const RUIN_SMOKE_HEIGHT_W: float = 3.0
const RUIN_SMOKE_CHIMNEY_GAP: float = 0.5
const RUIN_SMOKE_LIFT: float = 0.03
## Кінець відводу не ближче за стільки (клітинки, ~2 м) до димаря в плані: інакше відвід читається таким, що
## закінчується на димарі.
const DROP_CHIMNEY_CLEAR: float = 0.25
## Стіна, до лінії якої димар ближчий за стільки (клітинки, ~2.8 м), — не стіна для відводу.
const DROP_CHIMNEY_WALL: float = 0.35
## Дріт на екрані не ближче за стільки (клітинки, ~1.2 м) до стовпчика димаря.
const WIRE_CHIMNEY_CLEAR: float = 0.15
## Стовп ЛЕП — поза обрисом паркану двору й не ближче за стільки до лінії паркану (клітинки, 1.6 м).
const POLE_FENCE_CLEAR: float = 0.2
## Стовп ЛЕП не ближче за стільки до самих секцій паркану — двору чи поля (клітинки, 2.4 м): стовп на розі паркану
## читається стовпом у дворі.
const POLE_FENCE_SEG_CLEAR: float = 0.3
## Стовп ЛЕП не ближче за стільки до прорізу воріт садиби (клітинки, 1.6 м).
const POLE_GATE_CLEAR: float = 0.2
## Стовп ЛЕП не ближче за стільки до тюка сіна (клітинки).
const POLE_HAY_CLEAR: float = 0.5
## Відвід, що йде від опори майже прямо до камери чи від неї (косинус кута з напрямом погляду), на екрані — вертикальна
## риска над сусіднім дахом.
const DROP_VIEW_COS: float = 0.97
## Точка дроту глибше за стільки в клітинку чужого двору (клітинки) — дріт іде крізь двір.
const YARD_EPS: float = 0.05
## Стовп стоїть на межі клітинок біля вулиці, тож до обрису будівлі (двір починається за 0.1 від межі) — не ближче за
## стільки; від паркану чи дрібної речі — щоб не стояти в самому паркані (клітинки).
const POLE_BUILDING_CLEAR: float = 0.1
## Від цілої хати стовп стоїть не ближче (смуга вулиці, не двір), і проліт не заходить ближче.
const POLE_HOME_CLEAR: float = 0.3
## Стовп у клітинці двору стоїть не далі за стільки (клітинки) від межі двору з боку вулиці.
const YARD_EDGE: float = 0.15
const POLE_PROP_CLEAR: float = 0.0
## Стовп від води й болота (WATER_CLEAR плюс півширини основи) і від мосту.
const POLE_WET_CLEAR: float = 0.55
const POLE_BRIDGE_CLEAR: float = 0.3
const POLE_GARDEN_CLEAR: float = 0.0
## Стовп, шафа ТП і анкер відтяжки — не ближче за стільки метрів до краю асфальту за полем d дороги
## (RoadCourse.d_at), яке малює шейдер землі; 1.6 м = 0.2 клітинки.
const POLE_ROAD_CLEAR_M: float = 2.4
## Стовп лінії стоїть у своїй точці з цією точністю (клітинки).
const POLE_SNAP: float = 0.05
## Відтяжка кутової чи кінцевої опори лягає на землю на стільки клітинок від неї.
const GUY_REACH: float = 0.3
## Опора з прольотами, чия векторна сума коротша за це, — пряма (чи тавр): відтяжки не має.
const GUY_PULL_MIN: float = 0.6
## Дріт — сіро-оливковий напівпрозорий, ближчий до тону землі: майже чорна лінія тягла око з кожної хати. На зумі 8
## він ще читається лінією.
const WIRE_COLOR: Color = Color(0.15, 0.145, 0.13, 0.72)
## На мокрій карті земля темна, і темний дріт на ній зникав — стовпи читались окремими палицями. Мокрий дріт
## світліший (відблиск неба), на ~0.2 яскравіший за сухий: тихий, але лінією.
const WIRE_COLOR_WET: Color = Color(0.36, 0.355, 0.34, 0.72)
## Найнижчий дріт прольоту 0.4 кВ над ґрунтом чи водою, метри (з невеликим запасом над 6 м норми).
const WIRE_CLEAR_M: float = 6.2
## Множник прозорості кожного з трьох голих дротів 10 кВ.
const WIRE_10KV_ALPHA: float = 0.55
## Пріоритет прозорого проходу дротів: після води (0), як вогонь і дощ.
const WIRE_RENDER_PRIORITY: int = 1
## Імовірності з хешу на клітинку, у шістнадцятих: огорожа вздовж дороги йде відрізками по три
## клітинки, тюки — на кожній ~восьмій луці.
const FIELD_FENCE_RUN: int = 3
const FIELD_FENCE_CHANCE: int = 6
const HAY_CHANCE: int = 2
## Найменший проміжок між межами будівель (разом зі звісом даху), клітинки: 1 м. Чи читаються два
## будинки окремо, вирішує правило екрана (SCREEN_DEPTH_SEP); цей проміжок лише не дає стінам
## зійтися впритул згори.
const STRUCTURE_GAP: float = 0.125
## Підлога руїни — частка обрису руїни (зі звісом): так вона лишається в межах стін.
const RUBBLE_FLOOR: float = 0.9
## Уламки руїни: цегла, тиньк, обгоріле дерево (sRGB; вершинний колір множить альбедо).
const DEBRIS_COLORS: Array[Color] = [Color(0.36, 0.2, 0.15), Color(0.42, 0.4, 0.37), Color(0.12, 0.1, 0.08)]
## Найменший проміжок між обрисами будівель дошки (зі звісом даху): ~2 м землі між силуетами.
const BUILDING_GAP: float = 0.25
## Найдальше, на скільки будівля дошки відсувається від центру своєї клітинки заради BUILDING_GAP.
const BUILDING_SHIFT: float = 0.3
## Повітки двору стоять на клітинці BUILDING без будинку зменшеними (YARD_SHED_SCALE: ассет на 0.96
## клітинки не влазить із відступом до огорожі); сусідні двори беруть різні (як хати — HOUSE_FORMS).
const YARD_SHEDS: Array[StringName] = [&"f8_shed", &"f8_shed_brick", &"f8_shed_lean"]
## Форми паркану садиби: «модель|множник висоти». Види відрізняються формою (штахет 1.3 м, суцільний профлист 1.8 м,
## сітка на трубах 1.5 м, цегляний цоколь із прутами 1.6 м, горизонтальні дошки 1.45 м), а не фарбою, яку prop_thin
## знебарвлює; множник висоти в кожного свій, тож сусіди різняться й висотою. Усі види — один вузол малювання.
const FENCE_FORMS: Array[StringName] = [&"infra_fence_yard_picket|1.0", &"infra_fence_yard_sheet|0.95",
		&"infra_fence_yard_chainlink|1.05", &"infra_fence_yard_brickbars|0.9", &"infra_fence_yard_slat|1.1"]
## Крок стовпів паркану двору, м: один повтор атласу вздовж секції (TILE_M у tools/blender/infra/yard_fences.py).
const YARD_FENCE_TILE_M: float = 2.5
## Форми воріт садиби: суцільні металеві, з профнастилу, дерев'яні, ґратчасті, з горизонтальних дощок. Ворота беруть
## форму свого паркану (spec «gate»).
const GATE_KINDS: Array[StringName] = [&"metal", &"sheet", &"wood", &"lattice", &"slat"]
## Секція паркану не відходить від ґрунту посередині більш ніж на 5 см; найкоротша секція (клітинки).
const FENCE_SAG: float = 0.05 * 0.125
const FENCE_MIN: float = 0.1
## Хата на клітинку (ассет на 0.94 клітинки, ~7.5 м) — рівномірно до ~6.4 м: така сільська хата
## звична, а між двома сусідніми з камери гри лишається смуга землі.
const HOUSE_SCALE: float = 1.0
## Форми хат садиб на одну клітинку і найменша відстань (клітинок) між двома хатами однієї форми.
const HOUSE_FORMS: Array[StringName] = [&"house_h5", &"house_h7", &"house_h8", &"house_h6"]
const HOUSE_APART: int = 4
## Руїна -> ціла хата з тим самим силуетом; ближче RUIN_TWIN_NEAR клітинок вони не стоять (ця відстань лишає ще вибір форми хати).
const RUIN_TWIN_NEAR: int = 1
## Однакові руїни ближче за стільки клітинок (Чебишов) не стоять.
const RUIN_APART: int = 4
## Заміна руїни воліє модель, якої нема й у цьому радіусі.
const RUIN_FAR: int = 8
## Руїна міняється лише на таку, чий слід відрізняється не більш ніж на цю частку площі: інакше зсувається паркан і ворота садиби.
const RUIN_SWAP_AREA: float = 0.12
const RUIN_TWIN: Dictionary = {&"ruin_half_house2": &"house_h6", &"ruin_half_house1": &"house_h5"}
## Стовп, будівля й паркан тримаються від води й болота щонайменше на стільки клітинок.
const WATER_CLEAR: float = 0.4
const YARD_SHED_SCALE: float = 0.7
## Велика будівля (слід понад клітинку) зі звісом тримається на стільки всередині своєї групи
## BUILDING (клітинки, ~2 м). Будинок на одну клітинку стоїть у ній по центру й тримає лише
## YARD_CLEAR_SMALL до межі: з повним відступом жоден не влазить, а з цим до огорожі на YARD_OUT
## лишається ≥ 0.3 клітинки й разом із її товщиною.
const YARD_CLEAR: float = 0.25
const YARD_CLEAR_SMALL: float = 0.03
## Отвір воріт у огорожі двору разом із хвірткою, клітинки (~4.6 м): решта ребра обгороджена, двір не
## відкритий на вулицю.
const GATE: float = 0.58
## Ворота садиби — стовп, полотно завширшки GATE_LEAF (3.2 м), стовп, хвіртка (~1 м) і стовп: у GATE між
## центрами крайніх стовпів. Висота полотна 1.84 м.
const GATE_LEAF: float = 0.4
const GATE_H: float = 0.23
## Найкоротша секція огорожі, клітинки (4 м): коротший обрубок читається уламком, не огорожею.
const MIN_FENCE: float = 0.5
## Паркан за стовпом воріт до стіни чи розриву — не коротший за стільки (3.6 м): коротше — уламок біля воріт, і двір читається
## двома панелями, що нічого не обгороджують. Менший за MIN_FENCE, бо тісний двір (хата, сарай і руїна по периметру)
## інакше не вміщує навіть стулку з упором у кут.
const GATE_FLANK: float = 0.45
## Город не ближче стільки до розриву в паркані (_clip_garden).
const OPEN_SIDE_CLEAR: float = 0.5
## Найкоротший шматок кільця біля воріт: стовп і прольот (~1.2 м).
const GATE_POST: float = 0.15
## Ворота дивляться на дорогу, коли промінь від них назовні впирається в покриття не далі, ніж за стільки клітинок.
const GATE_SIGHT: float = 2.0
## Отвір воріт далі стільки (клітинки, ~2.8 м) від будь-якої будівлі чи сараю: ворота не лізуть на фасад. Двір, де такого
## місця нема, бере менший запас (_GATE_CLEARS): двір без воріт не лишається.
const GATE_CLEAR: float = 0.35
## Паркан не йде вздовж стіни ближче за стільки (клітинки, ~2 м): стіна сама межа двору.
const FENCE_WALL: float = 0.25
const GATE_CLEARS: Array[float] = [GATE_CLEAR, 0.25]
## Отвір воріт уздовж стіни (паралельно їй) не ближче стільки (клітинки, ~3.2 м), хоч би який запас узяв двір: ближче
## ворота виходять з-під звису даху чи затуляють перший поверх фасаду.
const GATE_ALONG: float = 0.4
## Верх полотна воріт на екрані не ближче стільки (клітинки площини фокуса, ~15 px на зумі 8) до силуету ближчої
## будівлі з димарем: інакше ворота визирають з-за даху й читаються частиною хати.
const GATE_SCREEN_GAP: float = 0.13
## Паркан двору не ближче стільки (клітинки, ~0.5 м) до краю намальованого асфальту: між панеллю й покриттям лишається узбіччя.
const FENCE_ROAD_INSET: float = 0.06
## Прямий хід паркану, коротший за це (клітинки, ~2 м), стоїть лише як сполучник воріт чи довгого ходу (_drop_short_runs).
const SHORT_RUN: float = 0.25
## Кут камери для правила екрана (IsoCameraRig: 38–55°, бій здебільшого близько) і найменша глибина
## між будівлями, що на екрані накладаються: ближча будівля не сміє ховати дальшу, бо тоді дві
## читаються однією, хоч згори між ними й 2 м.
# shortcut: один кут для правила екрана, хоча риг ходить 38–55°; на 55° силуети коротші, тож 40°
# суворіше — рахувати на кожному зумі, якщо на дальньому знову злипнуться будинки.
const SCREEN_PITCH_DEG: float = 40.0
const SCREEN_DEPTH_SEP: float = 1.2
## Земля між силуетами на екрані, клітинки (~1.2 м): силуети, що торкаються кутами, читаються одним.
const SCREEN_GROUND: float = 0.15
## Те саме між хатою й руїною (~0.4 м): руїна низька й напівзавалена, силует не злипається.
const SCREEN_GROUND_RUIN: float = 0.05
## Огорожа двору стоїть за межею групи BUILDING на ~2.2 м: будинок на одну клітинку займає її
## майже всю, і до огорожі однаково лишається ≥ 0.3 клітинки; секція ще далеко від центру сусідньої
## клітинки, де стоїть юніт.
## 0.285: лице секції (півтовщини 0.0125) лишається за 0.2 від центру сусідньої клітинки.
const YARD_OUT: float = 0.285
## Город займає таку частку двору садиби (30–50 %): решта — трава, хата, сарай.
const GARDEN_SHARE: float = 0.4
## Тюк — на такій відстані за краєм ріллі (центр), не далі 0.3: біля поля, не в ньому.
const HAY_OUT: float = 0.15
## Найдалі від краю поля, де ще стоїть тюк, клітинки.
const HAY_EDGE: float = 0.3
## Найдальше від точки макету, куди тюк перескакує на край поля.
const HAY_SNAP: float = 2.0
## КТП-шафа на землі біля опори (~1.6 × 2.4 × 1.1 м) і її колір (оцинкована сталь, сіро-зелена,
## value ≤ 0.3).
const TRANSFORMER_SIZE: Vector3 = Vector3(0.2, 0.3, 0.14)
## Центр шафи — за стільки клітинок від стовпа: між стовпом і гранню шафи лишається 0.6–1 м.
## Радіус стовпа (клітинки) і щілина між його поверхнею й гранню шафи, метри.
const POLE_RADIUS: float = 0.02
const CABINET_GAP_M: float = 0.4
const TRANSFORMER_COLOR: Color = Color(0.25, 0.28, 0.26)
## Поселення — опори в межах стількох клітинок: одна підстанція на поселення.
const SETTLEMENT_R: float = 6.0
## Стовп воріт (~0.25 м в перерізі), на ~0.4 м вищий за полотно.
const GATE_POST_SIZE: Vector3 = Vector3(0.03, 0.245, 0.03)
## Стовп дерев'яних воріт — темна бура кора, не світліша за стовпи паркану поруч.
const GATE_POST_COLOR: Color = Color(0.2, 0.15, 0.1)
## Тони полотна воріт (sRGB; вершинний колір множить альбедо коробки): сталь, фарбований профнастил
## (бурий чи зелений), дошки, оцинкована ґратка.
const GATE_STEEL: Array[Color] = [Color(0.22, 0.28, 0.34), Color(0.28, 0.31, 0.27)]
const GATE_SHEET: Array[Color] = [Color(0.36, 0.2, 0.13), Color(0.2, 0.32, 0.22)]
## Дошки воріт — тон свого паркану (середнє по атласу), на ~15 % темніше: полотно вертикальними гранями коробки
## освітлене так само, як картка паркану, тож альбедо більше за паркан давало б світле дерево на кадрі. Штахетник
## і горизонтальні дошки мають різну кору — по тону на кожен (test_yard_fence_tone).
const GATE_WOOD: Color = Color(0.15, 0.115, 0.08)
const GATE_SLAT: Color = Color(0.27, 0.19, 0.11)
## Частка, на яку фарба воріт зсувається до сірого (_gate_box_at).
const GATE_DESAT: float = 0.3
## Ворота рабиці — оцинковка, як сітка й труби паркану (chainlink у tools/blender/infra/yard_fences.py), тон у тон
## з нею: і чорна, і біла ґратка — найконтрастніша річ двору й перебиває сам двір.
const GATE_IRON: Color = Color(0.3, 0.31, 0.3)
## Півширина стежки двору для відступу дрібних речей від неї (самі стежки — Footpaths).
const PATH_WIDTH: float = 0.1
## Відступи сторони кільця паркану від межі двору, від бажаного (назовні) до найглибшого всередину;
## глибше −0.25 паркан зайшов би в квадрат юніта в центрі клітинки (KEEP_OUT).
const RING_OFFSETS: Array[float] = [YARD_OUT, 0.15, 0.0, -0.12, -0.25]
## Кам'яні брили й бетонні блоки темніші за ассет: світлі, вони читались плямами фарби.
const STONE_TINT: float = 0.85
## Опори ЛЕП: альбедо ассета ~0.56 (світлий бетон), і на сонці тонкий стовп світився білим поверх
## трави. Вивітрене дерево й брудний бетон — не світліші за ґрунт поруч.
const POLE_TINT: float = 0.45
## Пляма дотику під брилою чи блоком: у скільки разів ширша за сам пропс і наскільки темна.
const CONTACT_SPREAD: float = 1.25
const CONTACT_ALPHA: float = 0.6
const _FADE_SHADER: Shader = preload("res://game/battle/shaders/prop_fade.gdshader")
const _THIN_SHADER: Shader = preload("res://game/battle/shaders/prop_thin.gdshader")
## Огорожа без прозорих щілин — той самий шейдер без discard: рання перевірка глибини лишається.
static var _thin_solid_shader: Shader
const _CONTACT_SHADER: Shader = preload("res://game/battle/shaders/prop_contact.gdshader")
const _GARDEN_SHADER: Shader = preload("res://game/battle/shaders/prop_garden.gdshader")
const _GRIME_SHADER: Shader = preload("res://game/battle/shaders/prop_grime.gdshader")
const _RUBBLE_SHADER: Shader = preload("res://game/battle/shaders/prop_rubble.gdshader")
## Пояс бруду довкола хати, клітинки (~0.5 м).
const GRIME_M: float = 0.0625
## Запас від краю дорожнього покриття для парканів і дрібних пропсів, клітинки (~0.4 м).
const ROAD_PAD: float = 0.05
## Сарай, причіп чи техніка — лише при хаті: хата в межах стількох клітинок (Чебишов).
const HOUSE_NEAR: int = 2
## Той самий шейдер будівлі без розчинення: discard у шейдері вимикає ранню перевірку глибини на
## мобільних GPU, тож будівлі моделі, над якою зараз ніхто не стоїть, малюються без нього.
static var _alpha_shader_cache: Shader
static var _depth_shader_cache: Shader

## Модель -> {mesh, local, footprint, aabb, wires, tris}; спільний на процес, бо GLB кешуються.
static var _models: Dictionary = {}
## Тюк на мокрій карті: у дощ солома темна й сірувата, не жовто-зелена пляма на траві.
const HAY_WET: Color = Color(0.62, 0.6, 0.5)
## Модель -> ShaderMaterial розчинення (лише будівлі й руїни).
static var _fade_materials: Dictionary = {}
## Вид -> моделі на диску: перелік теки й сортування не повторюються на кожну групу будівель.
static var _by_kind: Dictionary = {}
## Модель -> мокра копія сітки (мости під дощем).
static var _wet_meshes: Dictionary = {}
const WET_DARK: float = 0.75
const WET_ROUGHNESS: float = 0.55
const BRIDGE_ROUGH: float = 0.85
## Тюки: загорнутий у плівку мав шорсткість 0.35 і блищав, як метал.
const HAY_ROUGH: float = 0.8
## Спекуляр будівель: мінеральні поверхні (тиньк, цегла, шифер) ≤ 0.3, якщо GLB не каже менше.
const MINERAL_SPECULAR: float = 0.3
## Модель -> {solid, fade} ShaderMaterial будівлі для поточного вузла.
var _node_materials: Dictionary = {}
var _contacts: MultiMeshInstance3D
var _apply_queued: bool = false

## Кожен екземпляр: {model, transform, cells (клітинки дошки під ним), crush, broken_of}.
var _instances: Array[Dictionary] = []
## Вузол (модель або «модель@ring») -> модель.
var _node_model: Dictionary = {}
## Вузол -> MultiMeshInstance3D і індекси екземплярів у ньому.
var _nodes: Dictionary = {}
var _slots: Dictionary = {}
## Городи садиб з макету: {rect, dir — від хати, green — частка зеленого}.
var _garden_plots: Array[Dictionary] = []
## Перетворення плиток грядок (одинична площина): без рендера MultiMesh їх не повертає.
var _garden_xforms: Array[Transform3D] = []
## Протоптані стежки (Footpaths) і витоптані плями Vector3(x, y, радіус) у координатах дошки:
## BoardView запікає їх у маску землі.
var footpaths: Array = []
var trodden: PackedVector3Array = PackedVector3Array()
## Видимі краї полів ріллі в координатах дошки (GroundSurface.field_edges): тюки — біля них.
var field_edges: Array[Rect2] = []
## Клітинки старту юнітів (обох гравців): дрібні пропси туди не стають — техніка на старті їх
## розчавила б, і лінія чи тюк з'являлися б уже поваленими.
var spawn_cells: Dictionary = {}
## Розстановка останньої побудови: для перевірки дорожнього покриття (тести, інструменти).
var _placer: RefCounted
## Городні грядки: клітинка BUILDING без будинку й без повітки — город (лише вигляд).
var _gardens: Array[Vector2i] = []
var _garden_node: MultiMeshInstance3D
## Наскільки грядки зелені (BattleLook.season): літо — зелень, рання осінь — жовта, пізня — гола рілля.
var garden_green: float = 0.2
## Відводи до хат: [індекс опори, точка на стіні хати].
var _drops: Array = []
## Центри цілих хат без відводу: мережа їх не живить (PowerGrid.fed) чи опора не дістає (drop_ok); тест їх називає.
var _unfed: Array[Vector2] = []
## Центри хат, до яких опора дістала б, а відводу навмисно нема (PowerGrid.skipped): тест їх називає.
var _skipped: Array[Vector2] = []
## Опори 10 кВ із щогловою трансформаторною підстанцією (індекси екземплярів): від неї 0.4 кВ до хат.
var _transformers: Dictionary = {}
## Однакові коробки — стовпи воріт і уламки руїн — одним MultiMesh (§8: виклик малювання на
## кожну групу коштував би вдвічі більше). Збираються під час побудови й далі не міняються.
var _small_base: Array[Transform3D] = []
## Вузол «batch» -> вид, записаний у INSTANCE_CUSTOM кожного слота (_write_nodes).
var _custom_written: Dictionary = {}
var _small_colors: Array[Color] = []
var _transformer_node: MultiMeshInstance3D = null
## Ворота садиб: {a, mid, b — центри стовпів (полотно a→mid, хвіртка mid→b), kind, out — нормаль до дороги,
## height, seed}; з них збираються дрібні коробки.
var _gates: Array[Dictionary] = []
## Опори з дротами: [індекс екземпляра опори A, індекс B] — проліт.
var _spans: Array = []
var _wires: MeshInstance3D
var _reveal: Dictionary = {}
## Клітинки юнітів останнього set_reveal_cells: будівля розчиняється, лише коли на екрані закриває юніта.
var _reveal_units: Array[Vector2i] = []
## Вузол → MultiMesh напівпрозорих екземплярів тієї ж моделі.
var _fade_nodes: Dictionary = {}
## Екземпляр → рівень розчинення 0..1 (0 — суцільний) і куди він іде.
var _fade_level: Dictionary = {}
var _fade_target: Dictionary = {}
var _crushed: Dictionary = {}
var _board_size: Vector2i = Vector2i.ZERO
## Клітинки дошки з лісом: тут стоятимуть дерева, коли їхній вигляд буде готовий.
var forest_cells: Array[Vector2i] = []
## Пропси (крім мостів) кидають тінь сонця. Без неї на сонячній карті дім, тюк чи опора висять
## над землею; ставити до build().
var structure_shadows: bool = false
## Мокра карта (BattleLook.wetness): мости темніші й з полиском. Імпортований матеріал мосту
## погоди не читає, тож мокра копія сітки; ставити до build().
var wet: bool = false


## Хати, у моделі яких двері й сходинка на тильній стіні (+Z), а не на фасаді (−Z): їх ставимо
## задом наперед, щоб двері дивились до воріт і дороги. Інакше стежка й пляма біля дверей лягали
## під глуху стіну, а до справжніх дверей від хвіртки не було проходу.
const HOUSE_BACK_DOOR: Array[StringName] = [&"house_h5"]


## Детермінований хеш клітинки; уся мінливість розстановки береться з нього.
static func cell_hash(cell: Vector2i, salt: int) -> int:
	return hash(Vector3i(cell.x, cell.y, salt))


## Вид моделі за таблицею чи префіксом; {} — модель не пропс цього шару.
static func spec_of(model: StringName) -> Dictionary:
	if MODELS.has(model):
		return MODELS[model]
	# Шматок мосту на одну клітинку («модель#k») і зруйнований двійник — той самий слот, що й цілий.
	var base := StringName(String(model).get_slice("#", 0).trim_suffix("_broken"))
	if base != model and MODELS.has(base):
		return MODELS[base]
	for rule in PREFIX_RULES:
		if String(model).begins_with(rule["prefix"]):
			return rule
	return {}


## Усі моделі виду, що є на диску: з таблиці й ті, що стали в слот за префіксом.
static func models_of(kind: int) -> Array[StringName]:
	if _by_kind.has(kind):
		return (_by_kind[kind] as Array[StringName]).duplicate()
	var out: Array[StringName] = []
	var names: Array[StringName] = []
	for m: StringName in MODELS:
		names.append(m)
	# Перелік через ResourceLoader: в експортованій збірці в теці лежать лише .import і .remap.
	for f in ResourceLoader.list_directory(MODEL_DIR):
		if f.ends_with(".glb") and not f.ends_with("_broken.glb") and not MODELS.has(StringName(f.get_basename())):
			names.append(StringName(f.get_basename()))
	# За рядком, не StringName.sort(): той порівнює вказівники й міняє порядок між запусками, а з ним
	# і кожен вибір моделі — розстановка мусить бути тією самою щоразу.
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for m in names:
		var s: Dictionary = spec_of(m)
		if not s.is_empty() and int(s["kind"]) == kind and not RETIRED.has(m) and model(m) != null:
			out.append(m)
	_by_kind[kind] = out
	return out.duplicate()


## Сітка, локальне перетворення сітки, слід і межі моделі; null — файлу нема.
static func model(name: StringName) -> Variant:
	if _models.has(name):
		return _models[name]
	if String(name).contains("#"):
		_models[name] = _segment(name)
		return _models[name]
	# Вид паркану двору ділить модель і сітку з рештою видів: один ресурс на всі, бо вони — один вузол малювання.
	var glb := StringName(spec_of(name).get("glb", name))
	if glb != name:
		for other: StringName in _models:
			if StringName(spec_of(other).get("glb", other)) == glb and other != glb and _models[other] != null:
				_models[name] = _models[other]
				return _models[name]
	var path: String = MODEL_DIR + String(glb) + ".glb"
	if not ResourceLoader.exists(path):
		_models[name] = null
		return null
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		push_warning("PropLayer: %s має %d сіток, беру першу" % [name, meshes.size()])
	var mi: MeshInstance3D = meshes[0]
	var local: Transform3D = _to_root(mi, root)
	var footprint := Vector2i.ZERO
	var fence_kinds: Array = []
	var fence_tops: Array = []
	for n in [root] + root.find_children("*", "", true, false):
		var ex: Variant = n.get_meta("extras") if n.has_meta("extras") else null
		if ex is Dictionary and (ex as Dictionary).has("footprint_tiles"):
			var f: Array = ex["footprint_tiles"]
			footprint = Vector2i(roundi(f[0]), roundi(f[1]))
		if ex is Dictionary and (ex as Dictionary).has("fence_kinds"):
			fence_kinds = ex["fence_kinds"]
			fence_tops = ex["fence_tops"]
	var wires: Array[Vector3] = []
	var named: Array[Node] = root.find_children("wire_*", "", true, false)
	named.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for w in named:
		wires.append(_to_root(w as Node3D, root).origin)
	# Маркер chimney_top (порожній вузол над шапкою димаря): туди чіпляється дим.
	var chimneys: Array[Vector3] = []
	for n in root.find_children("chimney_top*", "", true, false):
		chimneys.append(_to_root(n as Node3D, root).origin)
	var tris: int = 0
	for s in mi.mesh.get_surface_count():
		tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var info: Dictionary = {"mesh": _tuned_mesh(name, mi.mesh, fence_tops), "local": local, "footprint": footprint,
			"aabb": local * mi.mesh.get_aabb(), "wires": wires, "tris": tris, "chimneys": chimneys,
			"fence_kinds": fence_kinds, "fence_tops": fence_tops}
	root.free()
	_models[name] = info
	return info


## Номер виду паркану двору «модель_вид» у fence_kinds його моделі (порядок задає GLB); −1 — не вид паркану.
static func fence_kind_of(name: StringName) -> int:
	var glb := StringName(spec_of(name).get("glb", name))
	var info: Variant = model(name)
	if glb == name or info == null:
		return -1
	return ((info as Dictionary)["fence_kinds"] as Array).find(String(name).trim_prefix(String(glb) + "_"))


## Копія сітки, що множить альбедо кожної поверхні на tint.
static func _dimmed(mesh: Mesh, tint: Color) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i) as BaseMaterial3D
		if src != null:
			var dark: BaseMaterial3D = src.duplicate()
			dark.albedo_color = src.albedo_color * tint
			copy.surface_set_material(i, dark)
	return copy


## Копія сітки з власними матеріалами для огорож (двобічне світло) і каміння (темніше). Сам GLB
## не чіпаємо: load() ділить його сітку з усіма, хто його вантажить.
static func _tuned_mesh(name: StringName, mesh: Mesh, fence_tops: Array = []) -> Mesh:
	var kind: int = int(spec_of(name).get("kind", -1))
	if kind not in [Kind.FIELD_FENCE, Kind.GARDEN_FENCE, Kind.BOULDER, Kind.BLOCK, Kind.POLE, Kind.HAY]:
		return mesh
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		if kind == Kind.HAY:
			var matte: BaseMaterial3D = src.duplicate()
			matte.roughness = maxf(src.roughness, HAY_ROUGH)
			matte.metallic = 0.0
			copy.surface_set_material(i, matte)
			continue
		if kind == Kind.BOULDER or kind == Kind.BLOCK or kind == Kind.POLE:
			var tint: float = POLE_TINT if kind == Kind.POLE else STONE_TINT
			var dark: BaseMaterial3D = src.duplicate()
			dark.albedo_color = src.albedo_color * Color(tint, tint, tint, 1.0)
			dark.roughness = maxf(src.roughness, 0.95 if kind == Kind.POLE else src.roughness)
			copy.surface_set_material(i, dark)
			continue
		var thin := ShaderMaterial.new()
		var cut: bool = src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		thin.shader = _THIN_SHADER if cut else _thin_solid()
		thin.set_shader_parameter("albedo_tex", src.albedo_texture)
		thin.set_shader_parameter("albedo_color", src.albedo_color)
		thin.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
		thin.set_shader_parameter("alpha_cut", src.alpha_scissor_threshold if cut else 0.0)
		thin.set_shader_parameter("roughness", src.roughness)
		thin.set_shader_parameter("metallic", src.metallic)
		# Верх секції темніший: світлі шапки стовпчиків читались білим пунктиром уздовж огорожі.
		thin.set_shader_parameter("top_local", mesh.get_aabb().end.y)
		if spec_of(name).has("batch"):
			# Картка з усіма видами: шейдер лишає смугу виду екземпляра й тягне текстуру кроком стовпів від початку
			# секції, а не розтягує її з масштабом секції.
			thin.set_shader_parameter("kinds", fence_tops.size())
			thin.set_shader_parameter("tile_m", YARD_FENCE_TILE_M)
			thin.set_shader_parameter("kind_top", PackedFloat32Array(fence_tops))
		copy.surface_set_material(i, thin)
	return copy


## Шматок моделі мосту на одну клітинку переправи: «модель#k» — k-та клітинка вздовж локальної Z
## (від −L/2). Підрив буває на одній клітинці (EngineerCommand), тож кожна клітинка показує власний
## стан: цілий настил чи руїну. Трикутники обрізано точно по межі клітинки, з інтерполяцією всіх
## атрибутів, тож довгий настил не зникає й не вилазить у сусідню клітинку.
static func _segment(name: StringName) -> Variant:
	var base := StringName(String(name).get_slice("#", 0))
	var k: int = int(String(name).get_slice("#", 1))
	var whole: Variant = model(base)
	if whole == null:
		return null
	var info: Dictionary = whole
	# Довжина переправи — за цілою моделлю: уламки зруйнованої можуть бути коротші.
	var intact := StringName(String(base).trim_suffix("_broken"))
	var length: int = roundi(((model(intact) if model(intact) != null else info)["aabb"] as AABB).size.z)
	var z0: float = -length * 0.5 + k
	var mesh: ArrayMesh = _clip_z(info["mesh"], info["local"], z0, z0 + 1.0)
	var tris: int = 0
	for s in mesh.get_surface_count():
		tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var wires: Array[Vector3] = []
	return {"mesh": mesh, "local": Transform3D.IDENTITY, "footprint": Vector2i.ZERO,
			"aabb": mesh.get_aabb() if mesh.get_surface_count() > 0 else AABB(), "wires": wires, "tris": tris}


## Поверхні сітки (у просторі кореня моделі), обрізані площинами z = z0 і z = z1.
static func _clip_z(src: Mesh, local: Transform3D, z0: float, z1: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var a: Array = src.surface_get_arrays(s)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tan: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(pos.size())
			for i in pos.size():
				idx[i] = i
		var verts: Array = []
		for i in pos.size():
			# Вершина як масив атрибутів: позиція, нормаль, дотична, колір, uv, uv2.
			verts.append([local * pos[i],
					(local.basis * nrm[i]).normalized() if not nrm.is_empty() else Vector3.UP,
					Vector4(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2], tan[i * 4 + 3]) if not tan.is_empty() else Vector4(1, 0, 0, 1),
					col[i] if not col.is_empty() else Color.WHITE,
					uv[i] if not uv.is_empty() else Vector2.ZERO,
					uv2[i] if not uv2.is_empty() else Vector2.ZERO])
		var o_pos := PackedVector3Array()
		var o_nrm := PackedVector3Array()
		var o_tan := PackedFloat32Array()
		var o_col := PackedColorArray()
		var o_uv := PackedVector2Array()
		var o_uv2 := PackedVector2Array()
		for t in range(0, idx.size(), 3):
			var poly: Array = [verts[idx[t]], verts[idx[t + 1]], verts[idx[t + 2]]]
			poly = _clip_poly(poly, z0, 1.0)
			poly = _clip_poly(poly, z1, -1.0)
			for j in range(1, poly.size() - 1):
				for v: Array in [poly[0], poly[j], poly[j + 1]]:
					o_pos.append(v[0])
					o_nrm.append(v[1])
					var tv: Vector4 = v[2]
					o_tan.append_array([tv.x, tv.y, tv.z, tv.w])
					o_col.append(v[3])
					o_uv.append(v[4])
					o_uv2.append(v[5])
		if o_pos.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = o_pos
		arrays[Mesh.ARRAY_NORMAL] = o_nrm
		if not tan.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = o_tan
		if not col.is_empty():
			arrays[Mesh.ARRAY_COLOR] = o_col
		if not uv.is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = o_uv
		if not uv2.is_empty():
			arrays[Mesh.ARRAY_TEX_UV2] = o_uv2
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	return out


## Сазерленд — Ходжмен однією площиною: лишає частину многокутника, де side·(z − plane) ≥ 0.
static func _clip_poly(poly: Array, plane: float, side: float) -> Array:
	var out: Array = []
	for i in poly.size():
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % poly.size()]
		var da: float = side * ((a[0] as Vector3).z - plane)
		var db: float = side * ((b[0] as Vector3).z - plane)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			var t: float = da / (da - db)
			out.append([(a[0] as Vector3).lerp(b[0], t), (a[1] as Vector3).lerp(b[1], t).normalized(),
					(a[2] as Vector4).lerp(b[2], t), (a[3] as Color).lerp(b[3], t),
					(a[4] as Vector2).lerp(b[4], t), (a[5] as Vector2).lerp(b[5], t)])
	return out


static func _to_root(n: Node3D, root: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p != root:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## world — дошка разом із кільцем (Surroundings.world_board), ring — його ширина, тож клітинка
## дошки c лежить у світі на c + ring. map_key — ім'я файлу карти (мости своєї карти, сіль
## хешу), half_dir — напрям від центру дошки до баз гравця 0: половини мають власний набір.
func build(world: Board, ring: int, board_size: Vector2i, height: TerrainHeight,
		map_key: StringName = &"", half_dir: Vector2 = Vector2.ZERO, fields: Array[Rect2] = [],
		spawns: Array[Vector2i] = []) -> void:
	field_edges = fields
	spawn_cells.clear()
	for c in spawns:
		spawn_cells[c] = true
	for child in get_children():
		child.free()
	_instances.clear()
	_nodes.clear()
	_fade_nodes.clear()
	_fade_level.clear()
	_fade_target.clear()
	_slots.clear()
	_custom_written.clear()
	_node_model.clear()
	_spans.clear()
	_drops.clear()
	_skipped = []
	_transformers.clear()
	_transformer_node = null
	_small_base.clear()
	_small_colors.clear()
	_gates.clear()
	_wires = null
	_contacts = null
	_garden_node = null
	_gardens.clear()
	_garden_plots.clear()
	_garden_xforms.clear()
	footpaths = []
	trodden = PackedVector3Array()
	_placer = null
	_node_materials.clear()
	forest_cells.clear()
	_board_size = board_size
	if world.width <= 0 or world.height <= 0:
		return
	var p := _Placer.new(self, world, ring, board_size, height, map_key, half_dir)
	# Будівлі стоять на рівних майданчиках, урізаних у рельєф (TerrainHeight.add_pad); решта пропсів
	# ставиться вже на вирівняний ґрунт.
	if height != null:
		height.clear_pads()
	p.place_all()
	if height != null:
		height.finish_pads()
	_assign_roofs()
	_spans = p.spans
	_gardens = p.gardens
	_garden_plots = p.garden_plots
	footpaths = p.walks
	trodden = p.patches
	_placer = p
	for y in board_size.y:
		for x in board_size.x:
			if world.kind_at(Vector2i(x + ring, y + ring)) == Terrain.Kind.FOREST:
				forest_cells.append(Vector2i(x, y))
	_build_nodes(ring > 0)
	_apply()


## Клітинки юнітів, які зараз показано: їхні будівлі й будівлі між ними та камерою розчиняються.
## Новий набір замінює попередній. instant — без переходу й одразу, не в кінці кадру: на гейті
## передачі (§3.5) дах, прозорий для попереднього гравця, не має й кадру доповертатись до
## непрозорості — це показало б, де стоять його юніти.
func set_reveal_cells(cells: Array[Vector2i], instant: bool = false) -> void:
	_reveal.clear()
	_reveal_units = cells.duplicate()
	for c in cells:
		for o in REVEAL_OFFSETS:
			_reveal[c + o] = true
	if not instant:
		_queue_apply()
		return
	_apply()
	for i in _fade_target:
		_fade_level[i] = _fade_target[i]
	_write_nodes()
	set_process(false)


## Клітинки, де розчавлено дрібні пропси, — уже обрізані розвіданим глядача (§3.5): шар не
## знає ні про гравців, ні про туман і малює рівно те, що дали.
func set_crushed(cells: Array[Vector2i]) -> void:
	_crushed.clear()
	for c in cells:
		_crushed[c] = true
	_queue_apply()


## Світові точки верху димарів хат дошки (вузол chimney_top моделі) — для диму з димарів.
func chimney_tops() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for inst in _instances:
		var spec: Dictionary = spec_of(inst["model"])
		# у пошкодженої хати димар не димить: це руїна з проламом, а не житло
		if int(spec["kind"]) != Kind.STRUCTURE or inst.get("yard", false) or bool(spec.get("damaged", false)):
			continue
		if not _on_board((inst["cells"] as Array)[0]):
			continue
		var t: Transform3D = _final_transform(inst) * (model(inst["model"]) as Dictionary)["local"]
		for p: Vector3 in (model(inst["model"]) as Dictionary).get("chimneys", []):
			out.append(t * p)
	return out


## Центри руїн дошки на землі (середина обрису, висота підошви) — для тління руїн.
func ruin_centres() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.RUIN or not _on_board((inst["cells"] as Array)[0]):
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		out.append(Vector3(box.get_center().x, box.position.y, box.get_center().z))
	return out


## Звідки тліє руїна: з уламків усередині обрису — низька частина верху сітки, ближча до центру, не
## біля уцілілого димаря (дим біля цілого димаря читався б як дим із димаря) і не над порожнім повітрям.
func ruin_smoke_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) == Kind.RUIN and _on_board((inst["cells"] as Array)[0]):
			out.append(_ruin_smoke_point(inst))
	return out


## Точка диму лише тієї руїни, центр якої (`ruin_centres`) збігається з `centre`: важка вибірка по сітці
## йде тільки для руїн, що справді димлять.
func ruin_smoke_point_at(centre: Vector3) -> Vector3:
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.RUIN or not _on_board((inst["cells"] as Array)[0]):
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		if Vector3(box.get_center().x, box.position.y, box.get_center().z).is_equal_approx(centre):
			return _ruin_smoke_point(inst)
	return centre


func _ruin_smoke_point(inst: Dictionary) -> Vector3:
	var info: Dictionary = model(inst["model"])
	var t: Transform3D = _final_transform(inst) * (info["local"] as Transform3D)
	var box: AABB = (inst["transform"] as Transform3D) * (info["aabb"] as AABB)
	var chims: Array[Vector2] = []
	for ch: Vector3 in info.get("chimneys", []):
		chims.append(Vector2((t * ch).x, (t * ch).z))
	var top: Dictionary = top_surface_grid(info["mesh"] as Mesh, t, box)
	var step: float = top["step"]
	var h: PackedFloat32Array = top["h"]
	var centre := Vector2(box.get_center().x, box.get_center().z)
	var best := Vector3.INF
	var best_score: float = INF
	var tm: TriangleMesh = triangles_of(inst["model"])
	var inv: Transform3D = t.affine_inverse()
	var down: Vector3 = (inv.basis * Vector3.DOWN).normalized()
	for iz in int(top["nz"]):
		for ix in int(top["nx"]):
			var y: float = h[iz * int(top["nx"]) + ix]
			if is_inf(y):
				continue
			var xz := Vector2(box.position.x + (ix + 0.5) * step, box.position.z + (iz + 0.5) * step)
			if chims.any(func(c: Vector2) -> bool: return c.distance_to(xz) < RUIN_SMOKE_CHIMNEY_GAP):
				continue
			# Висота важить більше за відстань до центру: огризок стіни не виграє в справжнього завалу.
			var score: float = xz.distance_to(centre) + RUIN_SMOKE_HEIGHT_W * (y - box.position.y)
			if score < best_score:
				# Сітка наближена: біля ребра трикутників вона може схибити, тож точну висоту дає промінь, а
				# осередок, де вони розходяться, відкидаємо.
				var hit: Dictionary = tm.intersect_ray(inv * Vector3(xz.x, y + 50.0, xz.y), down)
				if hit.is_empty():
					continue
				var hy: float = (t * (hit["position"] as Vector3)).y
				if absf(hy - y) > 0.03:
					continue
				best_score = score
				best = Vector3(xz.x, hy + RUIN_SMOKE_LIFT, xz.y)
	if best == Vector3.INF:
		best = Vector3(centre.x, box.position.y + RUIN_SMOKE_LIFT, centre.y)
	return best


## Верх сітки в світі: найвища точка трикутників над кожною клітинкою решітки кроку 0,1 у межах box
## (inf — над порожнім). Для диму руїни й для тесту, що дим не висить у повітрі.
static func top_surface_grid(mesh: Mesh, xf: Transform3D, box: AABB) -> Dictionary:
	var step: float = 0.1
	var nx: int = maxi(1, ceili(box.size.x / step))
	var nz: int = maxi(1, ceili(box.size.z / step))
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	h.fill(-INF)
	for sidx in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(sidx)
		var vs: PackedVector3Array = xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for k in range(0, idx.size() - 2, 3):
			var a: Vector3 = vs[idx[k]]
			var b: Vector3 = vs[idx[k + 1]]
			var c: Vector3 = vs[idx[k + 2]]
			var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			# Лицьова грань Godot — за годинниковою стрілкою; грані, що дивляться вниз чи вбік, верху не дають.
			if den > -1e-9:
				continue
			var ix0: int = maxi(0, floori((minf(a.x, minf(b.x, c.x)) - box.position.x) / step))
			var ix1: int = mini(nx - 1, floori((maxf(a.x, maxf(b.x, c.x)) - box.position.x) / step))
			var iz0: int = maxi(0, floori((minf(a.z, minf(b.z, c.z)) - box.position.z) / step))
			var iz1: int = mini(nz - 1, floori((maxf(a.z, maxf(b.z, c.z)) - box.position.z) / step))
			for iz in range(iz0, iz1 + 1):
				for ix in range(ix0, ix1 + 1):
					var px: float = box.position.x + (ix + 0.5) * step
					var pz: float = box.position.z + (iz + 0.5) * step
					var l1: float = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
					var l2: float = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
					var l3: float = 1.0 - l1 - l2
					if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
						continue
					h[iz * nx + ix] = maxf(h[iz * nx + ix], l1 * a.y + l2 * b.y + l3 * c.y)
	for i in h.size():
		if h[i] == -INF:
			h[i] = INF
	return {"h": h, "nx": nx, "nz": nz, "step": step}


## Точка на покритті дороги (осі й ширина RoadCourse) з запасом pad, клітинки.
func on_road(p: Vector2, pad: float = 0.0) -> bool:
	return _placer != null and _placer.on_road(p, pad)


## Для тестів: екземпляри, що стоять на клітинці дошки.
func instances_on(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _gardens.has(cell):
		out.append({"model": &"garden", "transform": Transform3D(Basis(), Vector3(cell.x, 0.0, cell.y)),
				"faded": false, "crushed": false, "yard": true})
	for inst in _instances:
		if (inst["cells"] as Array).has(cell):
			out.append({"model": inst["model"], "transform": _final_transform(inst),
					"faded": _is_faded(inst), "crushed": _is_crushed(inst), "yard": inst.get("yard", false)})
	return out


func garden_beds() -> Array[Transform3D]:
	return _garden_xforms


func all_instances() -> Array[Dictionary]:
	return _instances


func triangle_count() -> int:
	var t: int = 0
	for inst in _instances:
		t += int((model(inst["model"]) as Dictionary)["tris"])
	return t


## Ворота дворів: {a, mid, b, kind, out, height, …} — стовпи a, mid, b і висота полотна.
func gates() -> Array[Dictionary]:
	return _gates


## Дроти ЛЕП на площині XZ: прольоти між опорами й відводи до хат, [a, b] (Vector2) — щоб рослинність
## не росла під ними.
func wire_lines() -> Array:
	var out: Array = span_lines()
	for dr: Array in _drops:
		var a: Vector3 = (_instances[dr[0]]["transform"] as Transform3D).origin
		var at: Variant = dr[1]
		out.append([Vector2(a.x, a.z), Vector2(at.x, at.z) if at is Vector3 else at])
	return out


## Лише прольоти між опорами, [a, b] (Vector2), без відводів: просіка в лісі йде за лінією, а не до хат.
func span_lines() -> Array:
	var out: Array = []
	for s: Array in _spans:
		var a: Vector3 = (_instances[s[0]]["transform"] as Transform3D).origin
		var b: Vector3 = (_instances[s[1]]["transform"] as Transform3D).origin
		out.append([Vector2(a.x, a.z), Vector2(b.x, b.z)])
	return out


func wire_spans() -> int:
	var n: int = 0
	for s: Array in _spans:
		if not _is_crushed(_instances[s[0]]) and not _is_crushed(_instances[s[1]]):
			n += 1
	return n


## Набір під юнітами й розчавлене приходять разом після кожного пакета подій: вузли оновлюються
## один раз наприкінці кадру, а не на кожен виклик. Стан (instances_on) правдивий одразу.
func _queue_apply() -> void:
	if _apply_queued:
		return
	_apply_queued = true
	_flush.call_deferred()


func _flush() -> void:
	if _apply_queued:
		_apply()


## yard — двірське вбрання клітинки без будинку (зменшена повітка, дрова, тюки): правила
## відстані між будинками його не стосуються.
func _add(model_name: StringName, xform: Transform3D, cells: Array[Vector2i], yard: bool = false) -> int:
	_instances.append({"model": model_name, "transform": xform, "cells": cells,
			"crush": int(spec_of(model_name).get("crush", Crush.NONE)), "yard": yard})
	return _instances.size() - 1


## Будівлі кільця — окремий вузол на модель, без тіні: MultiMesh відсікається камерою й тінню
## цілим, тож спільний із дошкою вузол малював би кільце (і його тінь) навіть на близькому зумі.
func _build_nodes(haze: bool) -> void:
	var by_node: Dictionary = {}
	for i in _instances.size():
		var m: StringName = _instances[i]["model"]
		# Види паркану двору — один вузол «batch»: вид екземпляра йде в INSTANCE_CUSTOM (_write_nodes).
		var key: StringName = StringName(spec_of(m).get("batch", m))
		var k: int = int(spec_of(m)["kind"])
		if (k == Kind.STRUCTURE or k == Kind.RUIN) and not _on_board((_instances[i]["cells"] as Array)[0]):
			key = StringName(String(m) + "@ring")
		if not by_node.has(key):
			by_node[key] = []
			_node_model[key] = m
		(by_node[key] as Array).append(i)
	var names: Array = by_node.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for key: StringName in names:
		var m: StringName = _node_model[key]
		var ring: bool = String(key).ends_with("@ring")
		var info: Dictionary = model(m)
		var kind: int = int(spec_of(m)["kind"])
		var fades: bool = kind == Kind.STRUCTURE or kind == Kind.RUIN
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = fades or spec_of(m).has("batch")
		mm.mesh = _bridge_mesh(m, info["mesh"], wet) if kind == Kind.BRIDGE else info["mesh"]
		if kind == Kind.HAY and wet:
			mm.mesh = _dimmed(info["mesh"], HAY_WET)
		mm.instance_count = (by_node[key] as Array).size()
		var mmi := MultiMeshInstance3D.new()
		# Godot міняє «@» в імені вузла на «_», тож вузол кільця — «модель_ring».
		mmi.name = String(key).replace("@ring", "_ring")
		mmi.multimesh = mm
		# §8: тіні — юнітам; пропсам — лише будинкам дошки, де без тіні на сонці дім висить над
		# землею. Руїни (низькі й важкі, до 4 тис. трикутників) лягають плямою дотику, як каміння;
		# огорожі, опори й дрібнота без тіні: їхній прохід тіней коштував десятки тисяч трикутників
		# на кадр, а тонка тінь на м'якому сонці майже не видна.
		var casts: bool = structure_shadows and not ring and kind == Kind.STRUCTURE
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if fades:
			_node_materials[key] = {"fade": _fade_material(m, info, haze, false), "solid": _fade_material(m, info, haze, true)}
			mmi.material_override = _node_materials[key]["solid"]
			# Напівпрозорі екземпляри — в окремому вузлі з альфа-матеріалом: прозорий прохід лише для
			# них, решта лишається непрозорою. Схований, доки нема що розчиняти.
			var fmm := MultiMesh.new()
			fmm.transform_format = MultiMesh.TRANSFORM_3D
			fmm.use_custom_data = true
			fmm.mesh = mm.mesh
			fmm.instance_count = mm.instance_count
			var fmi := MultiMeshInstance3D.new()
			fmi.name = String(mmi.name) + "_fade"
			fmi.multimesh = fmm
			fmi.cast_shadow = mmi.cast_shadow
			fmi.material_override = _node_materials[key]["fade"]
			fmi.visible = false
			add_child(fmi)
			_fade_nodes[key] = fmi
		add_child(mmi)
		_nodes[key] = mmi
		_slots[key] = by_node[key]
	if not _spans.is_empty() or not _drops.is_empty():
		_wires = MeshInstance3D.new()
		_wires.name = "Wires"
		_wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = WIRE_COLOR_WET if wet else WIRE_COLOR
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Дріт — лінія в один піксель, що не гасне з відстанню: на дальньому зумі над світлою водою згасання
		# прибрало б його зовсім. Малюється після води (вода — прозорий прохід з пріоритетом 0), щоб порядок
		# не залежав від ракурсу.
		mat.render_priority = WIRE_RENDER_PRIORITY
		_wires.material_override = mat
		add_child(_wires)
	_build_contacts()
	_build_gardens()
	_build_grime()
	_build_rubble_floors()
	_build_small_boxes()


## Городи: сусідні клітинки городу зливаються в одну ділянку (жадібні прямокутники, тож Г-подібна
## група не ляже на хату), трохи повернуту й з відступом від меж — один город на двір, а не плитка
## на кожну клітинку. Ряди — шейдер, крок у метрах однаковий для будь-якого розміру ділянки.
func _build_gardens() -> void:
	_build_gates()
	if not _garden_plots.is_empty():
		_build_garden_plots()
		return
	if _gardens.is_empty():
		return
	var plots: Array[Rect2i] = _garden_rects()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _GARDEN_SHADER
	mat.set_shader_parameter("green", garden_green)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = plots.size()
	for i in plots.size():
		var r: Rect2i = plots[i]
		var hv: int = absi(cell_hash(r.position, 144))
		# Ряди вздовж довшого боку; ділянка трохи повернута й менша за свої клітинки.
		var long_x: bool = r.size.x >= r.size.y
		var yaw: float = (0.0 if long_x else PI * 0.5) + (float(hv % 41) / 40.0 - 0.5) * 0.2
		var len_a: float = float(maxi(r.size.x, r.size.y)) - 0.28 - float(hv / 64 % 10) / 100.0
		var len_b: float = float(mini(r.size.x, r.size.y)) - 0.3 - float(hv / 1024 % 10) / 100.0
		var centre := Vector2(r.position) + Vector2(r.size - Vector2i.ONE) * 0.5
		var hx: float = TerrainHeight.ground_y(centre.x + 0.3, centre.y) - TerrainHeight.ground_y(centre.x - 0.3, centre.y)
		var hz: float = TerrainHeight.ground_y(centre.x, centre.y + 0.3) - TerrainHeight.ground_y(centre.x, centre.y - 0.3)
		var up := Vector3(-hx / 0.6, 1.0, -hz / 0.6).normalized()
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw)).slide(up).normalized()
		_garden_xforms.append(Transform3D(Basis(right * len_a, up, right.cross(up) * len_b),
				Vector3(centre.x, TerrainHeight.ground_y(centre.x, centre.y) + 0.006, centre.y)))
		mm.set_instance_transform(i, _garden_xforms[i])
		# r — скільки рядів на ділянці (ряд ~0.9 м), g — зсув візерунка краю.
		mm.set_instance_custom_data(i, Color(len_a * 8.0 / 0.9, float(hv % 97) / 97.0, 0.0, 0.0))
	_garden_node = MultiMeshInstance3D.new()
	_garden_node.name = "GardenBeds"
	_garden_node.multimesh = mm
	_garden_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_garden_node)


## Город садиби — частина двору за хатою (GARDEN_SHARE двору), м'який рваний край у траву.
func _build_garden_plots() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _GARDEN_SHADER
	mat.set_shader_parameter("green", garden_green)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = _garden_plots.size()
	for i in _garden_plots.size():
		var gp: Dictionary = _garden_plots[i]
		var rect: Rect2 = gp["rect"]
		var away: Vector2 = gp["dir"]
		var centre: Vector2 = rect.get_center()
		var hv: int = absi(cell_hash(Vector2i(centre.floor()), 144))
		# Ряди впоперек напряму від хати (UV.x уздовж away), трохи повернуто.
		var along_x: bool = absf(away.x) >= absf(away.y)
		var along: float = rect.size.x if along_x else rect.size.y
		var across: float = rect.size.y if along_x else rect.size.x
		var yaw: float = (0.0 if along_x else PI * 0.5) + (float(hv / 16 % 21) / 20.0 - 0.5) * 0.06
		var hx: float = TerrainHeight.ground_y(centre.x + 0.3, centre.y) - TerrainHeight.ground_y(centre.x - 0.3, centre.y)
		var hz: float = TerrainHeight.ground_y(centre.x, centre.y + 0.3) - TerrainHeight.ground_y(centre.x, centre.y - 0.3)
		var up := Vector3(-hx / 0.6, 1.0, -hz / 0.6).normalized()
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw)).slide(up).normalized()
		_garden_xforms.append(Transform3D(Basis(right * along, up, right.cross(up) * across),
				Vector3(centre.x, TerrainHeight.ground_y(centre.x, centre.y) + 0.004, centre.y)))
		mm.set_instance_transform(i, _garden_xforms[i])
		# r — рядів (крок ~0.7 м, клітинка 8 м), g — зерно краю, b — частка зеленого.
		mm.set_instance_custom_data(i, Color(along * 8.0 / 0.7, float(hv % 97) / 97.0, float(gp["green"]), 0.0))
	_garden_node = MultiMeshInstance3D.new()
	_garden_node.name = "GardenBeds"
	_garden_node.multimesh = mm
	_garden_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_garden_node)


## Ворота садиби з _gates: стовпи, полотно (дві стулки) і хвіртка збираються з дрібних коробок у спільному
## вузлі SmallBoxes — нового виклику малювання вони не додають. Вигляд полотна — за kind.
func _build_gates() -> void:
	for g: Dictionary in _gates:
		var a: Vector2 = g["a"]
		var mid: Vector2 = g["mid"]
		var b: Vector2 = g["b"]
		var u: Vector2 = (b - a).normalized()
		var kind_id: StringName = g["kind"]
		var sd: int = int(g["seed"])
		var tone: int = sd % 2
		var post_color: Color = GATE_POST_COLOR
		match kind_id:
			&"metal":
				post_color = Color(0.17, 0.18, 0.19)
			&"sheet":
				post_color = (GATE_SHEET[tone] as Color) * 0.6
			&"lattice":
				post_color = GATE_IRON
		for p: Vector2 in [a, b]:
			_gate_box(p, u, Vector2.ZERO, GATE_POST_SIZE, GATE_POST_SIZE.y * 0.5 - 0.01, post_color)
		# Стовп між полотном і хвірткою товщий, вищий і темніший: на зумі 8 видно, де закінчується полотно.
		_gate_box(mid, u, Vector2.ZERO, Vector3(GATE_POST_SIZE.x * 1.5, GATE_POST_SIZE.y + 0.03, GATE_POST_SIZE.z * 1.5),
				(GATE_POST_SIZE.y + 0.03) * 0.5 - 0.01, post_color * 0.6)
		# Полотно стоїть між гранями стовпів; на схилі — від нижчого кінця, щоб не висіло.
		var half_post: float = GATE_POST_SIZE.x * 0.5
		var spans: Array = [[a + u * half_post, mid - u * half_post * 1.5, true], [mid + u * half_post * 1.5, b - u * half_post, false]]
		for sp: Array in spans:
			var p0: Vector2 = sp[0]
			var p1: Vector2 = sp[1]
			var base: float = minf(TerrainHeight.ground_y(p0.x, p0.y), TerrainHeight.ground_y(p1.x, p1.y)) + 0.012
			var halves: Array = [[p0, p0.lerp(p1, 0.5) - u * 0.002], [p0.lerp(p1, 0.5) + u * 0.002, p1]] if sp[2] else [[p0, p1]]
			for lf: Array in halves:
				_gate_leaf(lf[0], lf[1], u, g["out"], base, float(g["height"]) - 0.012, kind_id, tone, sd)


## Одна стулка від p0 до p1 (вздовж u), нижній край на висоті base, висота h; out — бік до дороги.
func _gate_leaf(p0: Vector2, p1: Vector2, u: Vector2, out: Vector2, base: float, h: float, kind_id: StringName, tone: int, sd: int) -> void:
	var span: float = p0.distance_to(p1)
	var mid: Vector2 = (p0 + p1) * 0.5
	match kind_id:
		&"metal":
			var c: Color = GATE_STEEL[tone]
			_gate_box_at(mid, u, Vector2.ZERO, Vector3(span, h - 0.02, 0.01), base + 0.01 + (h - 0.02) * 0.5, c)
			for y: float in [0.0, h - 0.014]:
				_gate_box_at(mid, u, out * 0.003, Vector3(span, 0.014, 0.014), base + y + 0.007, c * 0.7)
		&"sheet":
			var c: Color = GATE_SHEET[tone]
			_gate_box_at(mid, u, Vector2.ZERO, Vector3(span, h, 0.008), base + h * 0.5, c * 0.85)
			var n: int = maxi(1, roundi(span / 0.045))
			for k in n:
				var t: float = (float(k) + 0.5) / float(n) - 0.5
				_gate_box_at(mid + u * (t * span), u, out * 0.005, Vector3(0.012, h - 0.01, 0.006), base + h * 0.5, c * (1.15 if k % 2 == 0 else 0.95))
		&"slat":
			# Горизонтальні дошки з просвітом між двома стійками, як паркан із дощок.
			var rows: int = maxi(3, floori(h / 0.022))
			for k in rows:
				var y: float = (float(k) + 0.5) / float(rows) * h
				var vary: int = absi(hash(Vector2i(sd, k))) % 5
				_gate_box_at(mid, u, Vector2.ZERO, Vector3(span, h / float(rows) * 0.72, 0.01), base + y, GATE_SLAT * (0.8 + 0.06 * float(vary)))
			for t: float in [-0.5, 0.5]:
				_gate_box_at(mid + u * (t * (span - 0.012)), u, -out * 0.008, Vector3(0.012, h, 0.012), base + h * 0.5, GATE_SLAT * 0.55)
		&"wood":
			var n: int = maxi(1, floori(span / 0.05))
			var w: float = span / float(n)
			for k in n:
				var t: float = (float(k) + 0.5) / float(n) - 0.5
				var vary: int = absi(hash(Vector2i(sd, k))) % 5
				var ph: float = h - 0.012 * float(vary % 3)
				_gate_box_at(mid + u * (t * span), u, Vector2.ZERO, Vector3(w - 0.003, ph, 0.01), base + ph * 0.5, GATE_WOOD * (0.85 + 0.08 * float(vary)))
			for y: float in [0.22, 0.74]:
				_gate_box_at(mid, u, -out * 0.008, Vector3(span, 0.016, 0.008), base + h * y, GATE_WOOD * 0.6)
		_:
			for y: float in [0.0, h * 0.5, h - 0.01]:
				_gate_box_at(mid, u, Vector2.ZERO, Vector3(span, 0.01, 0.01), base + y + 0.005, GATE_IRON)
			var n: int = maxi(2, roundi(span / 0.045))
			for k in n + 1:
				var t: float = float(k) / float(n) - 0.5
				_gate_box_at(mid + u * (t * span), u, Vector2.ZERO, Vector3(0.006, h, 0.006), base + h * 0.5, GATE_IRON)


## Коробка size із центром над точкою p, зсунута впоперек на off, висота центру над ґрунтом dy.
func _gate_box(p: Vector2, u: Vector2, off: Vector2, size: Vector3, dy: float, color: Color) -> void:
	_gate_box_at(p, u, off, size, TerrainHeight.ground_y(p.x, p.y) + dy, color)


## Те саме, висота центру y задана у світі: ґрунт під стулкою береться один раз на всю стулку.
func _gate_box_at(p: Vector2, u: Vector2, off: Vector2, size: Vector3, y: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, atan2(-u.y, u.x)).scaled_local(size)
	# Фарба воріт приглушена на GATE_DESAT до сірого тієї ж яскравості: вивітрена, а не іграшкова.
	var grey: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	_add_small(Transform3D(basis, Vector3(p.x + off.x, y, p.y + off.y)), color.lerp(Color(grey, grey, grey, color.a), GATE_DESAT))


func _add_small(xf: Transform3D, color: Color) -> void:
	_small_base.append(xf)
	_small_colors.append(color)


## Один вузол на всі дрібні коробки, коли їх уже зібрано.
func _build_small_boxes() -> void:
	if _small_base.is_empty():
		return
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = _small_base.size()
	for i in _small_base.size():
		mm.set_instance_transform(i, _small_base[i])
		mm.set_instance_color(i, _small_colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = "SmallBoxes"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Жадібне покриття клітинок городу прямокутниками: рядок за рядком, вшир, потім углиб.
func _garden_rects() -> Array[Rect2i]:
	var left: Dictionary = {}
	for c in _gardens:
		left[c] = true
	var cells: Array = left.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array[Rect2i] = []
	for c: Vector2i in cells:
		if not left.has(c):
			continue
		var w: int = 1
		while left.has(c + Vector2i(w, 0)):
			w += 1
		var hgt: int = 1
		while true:
			var full := true
			for x in w:
				full = full and left.has(c + Vector2i(x, hgt))
			if not full:
				break
			hgt += 1
		for y in hgt:
			for x in w:
				left.erase(c + Vector2i(x, y))
		out.append(Rect2i(c, Vector2i(w, hgt)))
	return out


## Підлога руїн дошки: плита уламків на обрисі руїни (трохи ширша за нього), щоб крізь пролом не
## було видно трави. Одна MultiMesh, два трикутники на руїну.
func _build_rubble_floors() -> void:
	var xforms: Array[Transform3D] = []
	var debris: Array[Transform3D] = []
	var debris_col: Array[Color] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.RUIN or not _on_board((inst["cells"] as Array)[0]):
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var c := Vector2(box.get_center().x, box.get_center().z)
		# Підлога — у межах стін (обрис руїни зі звісом, звужений): за стіни вона не вилазить.
		var floor_size := Vector2(box.size.x, box.size.z) * RUBBLE_FLOOR
		xforms.append(Transform3D(Basis.from_scale(Vector3(floor_size.x, 1.0, floor_size.y)),
				Vector3(c.x, TerrainHeight.ground_y(c.x, c.y) + 0.004, c.y)))
		# 3–6 уламків — шматки стіни, тиньку й обгорілі балки: підлозі потрібна висота, не лише фарба.
		var cell: Vector2i = (inst["cells"] as Array)[0]
		var hv: int = absi(cell_hash(cell, 170))
		for k in 3 + hv % 4:
			var r: int = absi(cell_hash(cell, 171 + k))
			var at := c + Vector2(float(r % 61) / 60.0 - 0.5, float(r / 61 % 61) / 60.0 - 0.5) * floor_size * 0.8
			var beam: bool = r % 5 == 0
			var size := Vector3(0.28, 0.025, 0.035) if beam else Vector3(0.06 + float(r % 7) * 0.012, 0.03 + float(r % 5) * 0.008, 0.05 + float(r % 3) * 0.015)
			var b := Basis(Vector3.UP, float(r % 628) / 100.0) * Basis(Vector3.RIGHT, (float(r / 7 % 9) - 4.0) * 0.06)
			debris.append(Transform3D(b.scaled_local(size), Vector3(at.x, TerrainHeight.ground_y(at.x, at.y) + size.y * 0.3, at.y)))
			debris_col.append(DEBRIS_COLORS[2] if beam else DEBRIS_COLORS[r % 2])
	for i in debris.size():
		_add_small(debris[i], debris_col[i])
	if xforms.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _RUBBLE_SHADER
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = "RubbleFloors"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Пояс бруду довкола хат дошки: квадрат на сліді хати, ширший на GRIME_M з кожного боку; шейдер
## темнить смугу вздовж стін. Одна MultiMesh, два трикутники на хату.
func _build_grime() -> void:
	var xforms: Array[Transform3D] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.STRUCTURE or inst.get("yard", false):
			continue
		if not _on_board((inst["cells"] as Array)[0]):
			continue
		var t: Transform3D = inst["transform"]
		var box: AABB = t * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var size := Vector2(box.size.x, box.size.z) + Vector2.ONE * GRIME_M * 2.0
		var c := Vector2(box.get_center().x, box.get_center().z)
		xforms.append(Transform3D(Basis.from_scale(Vector3(size.x, 1.0, size.y)),
				Vector3(c.x, TerrainHeight.ground_y(c.x, c.y) + 0.005, c.y)))
	if xforms.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _GRIME_SHADER
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = "HouseGrime"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Пляма дотику під брилами й блоками: один квадрат на кожен, лягає за схилом, одна MultiMesh. Без
## неї світлий камінь на траві читається наклеєним, а справжня тінь по всіх брилах — задорога.
func _build_contacts() -> void:
	var xforms: Array[Transform3D] = []
	var heights: Array[float] = []
	for inst in _instances:
		var k: int = int(spec_of(inst["model"])["kind"])
		if k != Kind.BOULDER and k != Kind.BLOCK and k != Kind.RUIN:
			continue
		var t: Transform3D = inst["transform"]
		var box: AABB = t * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var size := Vector2(box.size.x, box.size.z) * CONTACT_SPREAD
		var c := Vector2(box.get_center().x, box.get_center().z)
		var hx: float = TerrainHeight.ground_y(c.x + 0.05, c.y) - TerrainHeight.ground_y(c.x - 0.05, c.y)
		var hz: float = TerrainHeight.ground_y(c.x, c.y + 0.05) - TerrainHeight.ground_y(c.x, c.y - 0.05)
		var up := Vector3(-hx / 0.1, 1.0, -hz / 0.1).normalized()
		var right: Vector3 = Vector3.RIGHT.slide(up).normalized()
		var back: Vector3 = right.cross(up)
		# Права трійка (z = x × y): дзеркальна перевернула б обхід трикутників, і cull_back викинув би
		# пляму зовсім.
		xforms.append(Transform3D(Basis(right * size.x, up, back * size.y),
				Vector3(c.x, TerrainHeight.ground_y(c.x, c.y) + 0.004, c.y)))
		heights.append(box.size.y)
	if xforms.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _CONTACT_SHADER
	mat.set_shader_parameter("strength", CONTACT_ALPHA)
	mat.set_shader_parameter("cast", 1.0 if structure_shadows else 0.0)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(heights[i], 0.0, 0.0, 0.0))
	_contacts = MultiMeshInstance3D.new()
	_contacts.name = "ContactShadows"
	_contacts.multimesh = mm
	_contacts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contacts)


## Імпортований матеріал не чіпаємо: GLB кешується й ділиться між усіма, хто його вантажить.
## Розчинення й імла — у власному ShaderMaterial поверх сітки (material_override).
func _fade_material(m: StringName, info: Dictionary, haze: bool, solid: bool) -> ShaderMaterial:
	# Розмір дошки — у ключі: імла кільця залежить від нього, а кеш живе весь процес.
	var key: String = "%s:%s:%s:%s" % [m, haze, _board_size, solid]
	if _fade_materials.has(key):
		return _fade_materials[key]
	var src := (info["mesh"] as Mesh).surface_get_material(0) as BaseMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = _FADE_SHADER if solid else _alpha_shader()
	if src != null:
		# Усе, що є в матеріалі GLB: карта шорсткості з її каналом, метал, AO, сила нормалей і
		# спекуляр; інакше атлас із фактурою в бою читається рівним пластиком.
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("normal_scale", src.normal_scale if src.normal_enabled else 1.0)
		mat.set_shader_parameter("albedo_color", src.albedo_color)
		mat.set_shader_parameter("roughness", src.roughness)
		mat.set_shader_parameter("metallic", src.metallic)
		mat.set_shader_parameter("specular", minf(src.metallic_specular, MINERAL_SPECULAR))
		mat.set_shader_parameter("use_roughness_tex", src.roughness_texture != null)
		if src.roughness_texture != null:
			mat.set_shader_parameter("roughness_tex", src.roughness_texture)
			mat.set_shader_parameter("roughness_channel", _channel(src.roughness_texture_channel))
		mat.set_shader_parameter("use_metallic_tex", src.metallic_texture != null)
		if src.metallic_texture != null:
			mat.set_shader_parameter("metallic_tex", src.metallic_texture)
			mat.set_shader_parameter("metallic_channel", _channel(src.metallic_texture_channel))
		var ao: bool = src.ao_enabled and src.ao_texture != null
		mat.set_shader_parameter("use_ao_tex", ao)
		if ao:
			mat.set_shader_parameter("ao_tex", src.ao_texture)
			mat.set_shader_parameter("ao_channel", _channel(src.ao_texture_channel))
			mat.set_shader_parameter("ao_light_affect", src.ao_light_affect)
	if haze:
		Surroundings.apply(mat, _board_size)
	if not solid:
		# Розчинення у два проходи: спершу глибина (раніше за інші прозорі), тоді колір поверх неї.
		# Прохід глибини — після інших прозорих (ефекти, дим, дощ, дроти, контури зон), тож те, що
		# за дахом, уже намальоване й не губиться за невидимою глибиною; колір даху — поверх нього.
		var depth: ShaderMaterial = mat.duplicate()
		depth.shader = _depth_shader()
		depth.render_priority = FADE_DEPTH_PRIORITY
		mat.render_priority = FADE_DEPTH_PRIORITY + 1
		depth.next_pass = mat
		mat = depth
	_fade_materials[key] = mat
	return mat


## Копія сітки мосту під погоду карти. Ассет має «мокрі» поверхні з шорсткістю 0.15 і сталь 0.5 —
## у кадрі міст блищав, як скло. Шорсткість тепер не нижча за BRIDGE_ROUGH (суха карта) чи
## WET_ROUGHNESS (мокра; там ще й темніше).
static func _bridge_mesh(m: StringName, mesh: Mesh, wet_look: bool) -> Mesh:
	var key: String = "%s:%s" % [m, wet_look]
	if _wet_meshes.has(key):
		return _wet_meshes[key]
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var w: BaseMaterial3D = src.duplicate()
		var dark: float = WET_DARK if wet_look else 1.0
		w.albedo_color = src.albedo_color * Color(dark, dark, dark, 1.0)
		w.roughness = maxf(src.roughness, WET_ROUGHNESS if wet_look else BRIDGE_ROUGH)
		w.metallic = minf(src.metallic, 0.1)
		copy.surface_set_material(i, w)
	_wet_meshes[key] = copy
	return copy


static func _thin_solid() -> Shader:
	if _thin_solid_shader == null:
		_thin_solid_shader = Shader.new()
		var code: String = _THIN_SHADER.code
		var cut: String = "\tif (alpha_cut > 0.0 && tex.a < cut) {\n\t\tdiscard;\n\t}\n"
		assert(code.contains(cut), "PropLayer: відсікання в prop_thin.gdshader змінилось")
		_thin_solid_shader.code = code.replace(cut, "")
	return _thin_solid_shader


## Канал текстури StandardMaterial3D (TEXTURE_CHANNEL_*) як вектор для dot у шейдері.
static func _channel(ch: int) -> Vector4:
	return [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.299, 0.587, 0.114, 0)][ch]


## Варіант prop_fade з FADE_ALPHA: колір з альфою, без запису глибини (другий прохід розчинення).
static func _alpha_shader() -> Shader:
	if _alpha_shader_cache == null:
		_alpha_shader_cache = _variant("FADE_ALPHA")
	return _alpha_shader_cache


## Варіант prop_fade з FADE_DEPTH: лише глибина (перший прохід розчинення).
static func _depth_shader() -> Shader:
	if _depth_shader_cache == null:
		_depth_shader_cache = _variant("FADE_DEPTH")
	return _depth_shader_cache


static func _variant(define: String) -> Shader:
	var sh := Shader.new()
	var code: String = _FADE_SHADER.code
	assert(code.contains("shader_type spatial;"), "PropLayer: prop_fade.gdshader без shader_type")
	sh.code = code.replace("shader_type spatial;", "shader_type spatial;\n#define " + define)
	return sh


## Дахи хат — п'ять сільських кольорів (sRGB): графітовий шифер, темна вишня, справжня темна зелень,
## оцинковка, темно-коричневий. Шейдер не множить текстуру, а підставляє цей колір, зберігши її
## рельєф (множник по кольоровому даху давав брудні оливкові й вохристі тони), і кожен колір темніший
## за стіну щонайменше в 1/0.6 раза.
const ROOF_PALETTE: Array[Color] = [Color(0.2, 0.21, 0.23), Color(0.26, 0.09, 0.095), Color(0.12, 0.27, 0.16),
		Color(0.314, 0.329, 0.345), Color(0.24, 0.17, 0.12)]
## Найдалі від стіни по яскравості: дах хати не світліший за стільки її стіни (гамма-яскравість sRGB).
const ROOF_WALL_MAX: float = 0.6
## Найтемніший відтінок стіни в шейдері (WALL_TINTS у prop_fade.gdshader): із ним дах теж має вкластись у ROOF_WALL_MAX.
const WALL_TINT_MIN: float = 0.93
static var _wall_luma: Dictionary = {}


## Яскравість стіни моделі (sRGB, медіана за площею вертикальних граней по атласу); 1 — немає текстури, тож без обмеження.
static func wall_luma(m: StringName) -> float:
	if _wall_luma.has(m):
		return _wall_luma[m]
	var out: float = 1.0
	var info: Variant = model(m)
	var mesh: Mesh = (info as Dictionary)["mesh"] if info != null else null
	var mat: BaseMaterial3D = mesh.surface_get_material(0) as BaseMaterial3D if mesh != null else null
	if mat != null and mat.albedo_texture != null:
		var img: Image = mat.albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		var arr: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var samples: Array = []
		for t in idx.size() / 3:
			var a: int = idx[t * 3]
			var b: int = idx[t * 3 + 1]
			var c: int = idx[t * 3 + 2]
			var n: Vector3 = (v[b] - v[a]).cross(v[c] - v[a])
			if n.length() < 1e-9 or absf(n.normalized().y) > 0.3:
				continue
			var q: Vector2 = (uv[a] + uv[b] + uv[c]) / 3.0
			var px: Color = img.get_pixel(clampi(int(q.x * img.get_width()), 0, img.get_width() - 1),
					clampi(int(q.y * img.get_height()), 0, img.get_height() - 1))
			samples.append([px.r * 0.2126 + px.g * 0.7152 + px.b * 0.0722, n.length()])
		samples.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var total: float = 0.0
		for sm: Array in samples:
			total += sm[1]
		var acc: float = 0.0
		for sm: Array in samples:
			acc += sm[1]
			if acc >= total * 0.5:
				out = sm[0]
				break
	_wall_luma[m] = out
	return out
## Дві хати ближче за стільки клітинок мають різні дахи, поки є вільний колір.
const ROOF_APART: int = HOUSE_APART


static func _has_roof_colour(inst: Dictionary) -> bool:
	return String(inst["model"]).begins_with("house_") and not inst.get("yard", false)


## Номер кольору даху хати з ROOF_PALETTE; −1 — дах не перефарбовується (руїна, сарай, ферма).
static func roof_of(inst: Dictionary) -> int:
	return int(inst.get("roof", -1))


## Жадібно по порядку розстановки: з кольору за хешем клітинки — перший, якого нема в хатах ближче ROOF_APART;
## коли вільного нема — той, чий найближчий двійник найдалі.
func _assign_roofs() -> void:
	var done: Array = []
	for inst: Dictionary in _instances:
		if not _has_roof_colour(inst):
			continue
		var c: Vector2i = (inst["cells"] as Array)[0]
		var start: int = absi(cell_hash(c, 9137)) % ROOF_PALETTE.size()
		var best: int = start
		var best_gap: int = -1
		var wall: float = wall_luma(inst["model"]) * WALL_TINT_MIN
		for k in ROOF_PALETTE.size():
			var idx: int = (start + k) % ROOF_PALETTE.size()
			if ROOF_PALETTE[idx].get_luminance() > wall * ROOF_WALL_MAX:
				continue
			var gap: int = 1 << 20
			for d: Array in done:
				if d[1] == idx:
					var o: Vector2i = (d[0] as Vector2i) - c
					gap = mini(gap, maxi(absi(o.x), absi(o.y)))
			if gap > ROOF_APART:
				best = idx
				break
			if gap > best_gap:
				best_gap = gap
				best = idx
		inst["roof"] = best
		done.append([c, best])


## Колір даху для шейдера (лінійний); нулі — дах лишається з текстури моделі.
func _roof_tint(inst: Dictionary) -> Color:
	var idx: int = roof_of(inst)
	return Color(0, 0, 0) if idx < 0 else ROOF_PALETTE[idx].srgb_to_linear()


func _on_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _board_size.x and c.y < _board_size.y


func _is_faded(inst: Dictionary) -> bool:
	var kind: int = int(spec_of(inst["model"])["kind"])
	if kind != Kind.STRUCTURE and kind != Kind.RUIN:
		return false
	# Низьке (купа уламків, сарай по пояс юніту) юніта не ховає: розчиняти нема чого.
	var h: float = ((model(inst["model"]) as Dictionary)["aabb"] as AABB).size.y * (inst["transform"] as Transform3D).basis.y.length()
	if h < FADE_MIN_H:
		return false
	if not (inst["cells"] as Array).any(func(c: Vector2i) -> bool: return _reveal.has(c)):
		return false
	# Лише коли будівля на екрані перекриває юніта (сусід збоку його не ховає) і стоїть ближче до
	# камери: ближній край будівлі вглиб — перед юнітом. Будівля за юнітом нічого не закриває.
	var box: AABB = (inst["transform"] as Transform3D) * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
	var proj: Array = _Placer._screen_of(Rect2(box.position.x, box.position.z, box.size.x, box.size.z), box.size.y)
	var scr: Rect2 = proj[0]
	var near_depth: float = (proj[1] as Vector2).x
	for u in _reveal_units:
		var us: Array = _Placer._screen_of(Rect2(Vector2(u) - Vector2(0.2, 0.2), Vector2(0.4, 0.4)), 0.25)
		if near_depth < (us[1] as Vector2).x and scr.intersects(us[0]):
			return true
	return false


func _is_crushed(inst: Dictionary) -> bool:
	return int(inst["crush"]) != Crush.NONE and _crushed.has((inst["cells"] as Array)[0])


## Розчавлене лишається на місці як шрам: повалене, сплющене чи втиснуте.
func _final_transform(inst: Dictionary) -> Transform3D:
	var t: Transform3D = inst["transform"]
	if not _is_crushed(inst):
		return t
	var h: int = cell_hash((inst["cells"] as Array)[0], int(t.origin.x * 1000.0))
	match int(inst["crush"]):
		Crush.LAY:
			# Набік довкола поздовжньої осі (локальна X): огорожа, опора, блок лягають на землю.
			var side: float = 1.0 if h & 1 else -1.0
			return t * Transform3D(Basis(Vector3.RIGHT, side * deg_to_rad(84.0)), Vector3.ZERO)
		Crush.SQUASH:
			return t * Transform3D(Basis.from_scale(Vector3(1.1, 0.35, 1.05)), Vector3.ZERO)
		Crush.SINK:
			var info: Dictionary = model(inst["model"])
			return t.translated(Vector3(0.0, -(info["aabb"] as AABB).size.y * 0.6 * t.basis.get_scale().y, 0.0))
	return t


func _apply() -> void:
	_apply_queued = false
	var moving := false
	for key: StringName in _fade_nodes:
		for i in _slots[key]:
			_fade_target[i] = 1.0 if _is_faded(_instances[i]) else 0.0
			moving = moving or not is_equal_approx(float(_fade_level.get(i, 0.0)), _fade_target[i])
	_write_nodes()
	set_process(moving)
	_rebuild_wires()
	_rebuild_transformers()


## Розчинення плавне: рівень іде до цілі за FADE_TIME (кадр показу, не правила).
func _process(delta: float) -> void:
	var moving := false
	for i in _fade_target:
		var lv: float = move_toward(float(_fade_level.get(i, 0.0)), _fade_target[i], delta / FADE_TIME)
		_fade_level[i] = lv
		moving = moving or not is_equal_approx(lv, _fade_target[i])
	_write_nodes()
	set_process(moving)


## Екземпляри у вузлах: розчинюваний (рівень > 0) — у вузлі «_fade» з альфою 1 − рівень·(1 − FADE_ALPHA),
## у суцільному прихований нульовим масштабом; решта — навпаки.
func _write_nodes() -> void:
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for key: StringName in _nodes:
		var m: StringName = _node_model[key]
		var mm: MultiMesh = (_nodes[key] as MultiMeshInstance3D).multimesh
		var fmi: MultiMeshInstance3D = _fade_nodes.get(key)
		var slots: Array = _slots[key]
		var local: Transform3D = (model(m) as Dictionary)["local"]
		var any_faded := false
		for k in slots.size():
			var inst: Dictionary = _instances[slots[k]]
			var t: Transform3D = _final_transform(inst) * local
			if fmi == null:
				mm.set_instance_transform(k, t)
				if mm.use_custom_data:
					var kind_id: int = fence_kind_of(inst["model"])
					mm.set_instance_custom_data(k, Color(float(kind_id), 0.0, 0.0, 0.0))
					# Дзеркало для тестів: без рендера (headless) MultiMesh записаного не віддає.
					if not _custom_written.has(key):
						_custom_written[key] = []
						(_custom_written[key] as Array).resize(slots.size())
					(_custom_written[key] as Array)[k] = kind_id
				continue
			var lv: float = float(_fade_level.get(slots[k], 0.0))
			var tint: Color = _roof_tint(inst)
			var faded: bool = lv > 0.0
			any_faded = any_faded or faded
			mm.set_instance_transform(k, hidden if faded else t)
			mm.set_instance_custom_data(k, Color(tint.r, tint.g, tint.b, 0.0))
			fmi.multimesh.set_instance_transform(k, t if faded else hidden)
			fmi.multimesh.set_instance_custom_data(k, Color(tint.r, tint.g, tint.b, lv * (1.0 - FADE_ALPHA)))
		if fmi != null:
			fmi.visible = any_faded


## Дроти — лінії в пікселях екрана, не геометрія: 1–3 см дроту менші за піксель (props-research).
## Проліт до поваленої опори не малюється.
func _rebuild_wires() -> void:
	if _wires == null:
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for s: Array in _spans:
		var a: Dictionary = _instances[s[0]]
		var b: Dictionary = _instances[s[1]]
		if _is_crushed(a) or _is_crushed(b):
			continue
		# Три голі дроти 10 кВ поруч читались найтемнішою лінією кадру: кожен прозоріший, щоб трійка важила як кабель СІП.
		var col := Color(1.0, 1.0, 1.0, WIRE_10KV_ALPHA if _is_10kv_inst(a) and _is_10kv_inst(b) else 1.0)
		for pr: Array in span_wire_pairs(a, b):
			_append_wire(verts, cols, pr[0], pr[1], col)
	# Відвід до хати: два дроти від траверси стовпа до стіни під звісом даху, з невеликим провисом.
	for dr: Array in _drops:
		var pole: Dictionary = _instances[dr[0]]
		if _is_crushed(pole):
			continue
		for pr: Array in drop_wire_pairs(pole, dr[1]):
			_append_wire(verts, cols, pr[0], pr[1], Color.WHITE)
	for g: Array in _guy_lines():
		_append_wire(verts, cols, g[1], g[2], Color.WHITE)
	if verts.is_empty():
		_wires.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_wires.mesh = mesh


## Відтяжки: кутова й кінцева опора тягнеться від ~85 % висоти до землі в бік, протилежний прольотам
## (дріт, що тягне опору, вона мусить утримати). Пряма опора відтяжки не має. Анкер стоїть на ґрунті
## (висота TerrainHeight), не ближче POLE_ROAD_CLEAR_M до асфальту й не в сліду юніта: бік і виліт
## добираються. Елемент: [індекс опори, верх відтяжки, анкер].
func _guy_lines() -> Array:
	var pull: Dictionary = {}
	var degree: Dictionary = {}
	for s: Array in _spans:
		for e in 2:
			var a: Dictionary = _instances[s[e]]
			var b: Dictionary = _instances[s[1 - e]]
			if _is_crushed(a) or _is_crushed(b):
				continue
			var d: Vector3 = (b["transform"] as Transform3D).origin - (a["transform"] as Transform3D).origin
			pull[s[e]] = pull.get(s[e], Vector3.ZERO) + Vector3(d.x, 0.0, d.z).normalized()
			degree[s[e]] = int(degree.get(s[e], 0)) + 1
	var out: Array = []
	for i: int in pull:
		# Пряма (сума ≈ 0) чи розгалуження під прямими кутами (сума мала) відтяжки не мають.
		if int(degree[i]) >= 2 and (pull[i] as Vector3).length() < GUY_PULL_MIN:
			continue
		var t: Transform3D = _instances[i]["transform"]
		var h: float = ((model(_instances[i]["model"]) as Dictionary)["aabb"] as AABB).size.y
		var away := Vector2(-(pull[i] as Vector3).x, -(pull[i] as Vector3).z).normalized()
		var anchor: Vector3 = _guy_anchor(Vector2(t.origin.x, t.origin.z), away)
		if anchor.is_finite():
			out.append([i, t.origin + Vector3(0.0, h * 0.85, 0.0), anchor])
	return out


## Анкер відтяжки: у бік away від основи, на ґрунті; бік і виліт добираються, поки місце не стане
## придатним. Vector3.INF — місця нема.
func _guy_anchor(base: Vector2, away: Vector2) -> Vector3:
	for reach: float in [GUY_REACH, 0.2, 0.12, 0.08]:
		for rot: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 2.6, -2.6, PI]:
			var q: Vector2 = base + away.rotated(rot) * reach
			if _placer != null and _placer.anchor_ok(q):
				return Vector3(q.x, _placer.ground(q.x, q.y), q.y)
	return Vector3.INF


## Основа не ближче POLE_ROAD_CLEAR_M до асфальту за полем дороги (RoadCourse.d_at), у метрах.
func road_edge_m(p: Vector2) -> float:
	return _placer.road_edge_m(p) if _placer != null else 1e9


static func _append_wire(verts: PackedVector3Array, cols: PackedColorArray, pa: Vector3, pb: Vector3, col: Color) -> void:
	var pts: PackedVector3Array = wire_points(pa, pb, WIRE_SEGMENTS)
	for j in WIRE_SEGMENTS:
		verts.append(pts[j])
		verts.append(pts[j + 1])
		cols.append(col)
		cols.append(col)


## Точки дроту від pa до pb з провисом посередині: n відрізків, n + 1 точка.
static func wire_points(pa: Vector3, pb: Vector3, n: int) -> PackedVector3Array:
	var sag: float = WIRE_SAG_RATIO * Vector2(pb.x - pa.x, pb.z - pa.z).length()
	var out := PackedVector3Array()
	for j in n + 1:
		var t: float = float(j) / n
		out.append(pa.lerp(pb, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0))
	return out


## Ізолятори опори у світі.
static func _insulators(inst: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for w: Vector3 in (model(inst["model"]) as Dictionary)["wires"]:
		out.append((inst["transform"] as Transform3D) * w)
	return out


## Три фази з чотирьох ізоляторів 0.4 кВ (дві пари: верхня й нижня): верхні два й середина нижніх.
## Нуль на перехідному прольоті не тягнеться.
static func _phases(ws: Array[Vector3], n: int) -> Array[Vector3]:
	if ws.size() == n:
		return ws
	var sorted: Array[Vector3] = ws.duplicate()
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	if ws.size() == 4 and n == 3:
		return [sorted[0], sorted[1], (sorted[2] + sorted[3]) * 0.5]
	return sorted.slice(0, n)


## Середина траверси опори: куди чіпляється одножильний кабель 0.4 кВ.
static func _attach_point(inst: Dictionary) -> Vector3:
	var ws: Array[Vector3] = _insulators(inst)
	var sum := Vector3.ZERO
	for w in ws:
		sum += w
	return sum / maxf(float(ws.size()), 1.0)


static func _is_10kv_inst(inst: Dictionary) -> bool:
	return spec_of(inst["model"]).get("line", &"") == &"10kv"


## Пари кінців дротів прольоту між опорами a і b. Між двома опорами 10 кВ — три голі дроти, фаза до фази (з
## перестановок, де дроти не перехрещуються у плані, а потім найкоротша); решта — один скручений кабель СІП від
## траверси до траверси.
static func span_wire_pairs(a: Dictionary, b: Dictionary) -> Array:
	if not (_is_10kv_inst(a) and _is_10kv_inst(b)):
		return [[_attach_point(a), _attach_point(b)]]
	var wa: Array[Vector3] = _insulators(a)
	var wb: Array[Vector3] = _insulators(b)
	var n: int = mini(wa.size(), wb.size())
	if n == 0:
		return []
	wa = _phases(wa, n)
	wb = _phases(wb, n)
	var best: Array = []
	var best_cost: float = INF
	for perm: Array in _permutations(n):
		var cost: float = 0.0
		for i in n:
			for j in range(i + 1, n):
				if Geometry2D.segment_intersects_segment(Vector2(wa[i].x, wa[i].z), Vector2(wb[perm[i]].x, wb[perm[i]].z),
						Vector2(wa[j].x, wa[j].z), Vector2(wb[perm[j]].x, wb[perm[j]].z)) != null:
					cost += 1000.0
			cost += wa[i].distance_to(wb[perm[i]]) + absf(wa[i].y - wb[perm[i]].y) * 4.0
		if cost < best_cost - 1e-9:
			best_cost = cost
			best = []
			for i in n:
				best.append([wa[i], wb[perm[i]]])
	return best


static func _permutations(n: int) -> Array:
	if n <= 1:
		return [[0]] if n == 1 else [[]]
	var out: Array = []
	for rest: Array in _permutations(n - 1):
		for pos in n:
			var q: Array = rest.duplicate()
			q.insert(pos, n - 1)
			out.append(q)
	return out


## Відвід — один кабель СІП від траверси опори до кріплення на стіні.
static func drop_wire_pairs(pole: Dictionary, target: Vector3) -> Array:
	return [[_attach_point(pole), target]]


## Житлова будівля: ціла хата (house_*). Пошкоджена хата (ruin_half_house*), сарай і решта руїн — не житлові:
## відводу до них нема.
static func is_home(inst: Dictionary) -> bool:
	if inst.get("yard", false):
		return false
	return int(spec_of(inst["model"])["kind"]) == Kind.STRUCTURE and String(inst["model"]).begins_with("house")


## Найближча до from точка обрису будівлі rect (куди чіпляється відвід з боку from); INF, коли from — усередині.
static func drop_attach(rect: Rect2, from: Vector2) -> Vector2:
	if rect.has_point(from):
		return Vector2.INF
	return Vector2(clampf(from.x, rect.position.x, rect.end.x), clampf(from.y, rect.position.y, rect.end.y))


## Зовнішні нормалі сторін обрису rect, на яких (найближче до яких) лежить точка a: на розі — дві.
static func wall_normals(rect: Rect2, a: Vector2) -> Array[Vector2]:
	var d: Array[float] = [absf(a.x - rect.position.x), absf(a.x - rect.end.x), absf(a.y - rect.position.y), absf(a.y - rect.end.y)]
	var all: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	var out: Array[Vector2] = []
	for k in 4:
		if d[k] <= d.min() + 1e-3:
			out.append(all[k])
	return out


static var _tri_cache: Dictionary = {}


## Трикутники меша моделі (для перевірки, що дріт не проходить крізь дах).
static func triangles_of(name: StringName) -> TriangleMesh:
	if not _tri_cache.has(name):
		_tri_cache[name] = ((model(name) as Dictionary)["mesh"] as Mesh).generate_triangle_mesh()
	return _tri_cache[name]


## Центр шафи ТП біля опори в точці pos (along — вздовж лінії, side — упоперек): на землі, щілина між стовпом і
## гранню 0.6–1 м; уся площа не ближче POLE_ROAD_CLEAR_M до асфальту, не в будівлях і не в сліду юніта. INF — місця
## нема. Без розстановки (placer == null) беться перший кандидат.
static func cabinet_centre(pos: Vector2, along: Vector2, side: Vector2, placer: Variant) -> Vector2:
	var hx: Vector2 = side * TRANSFORMER_SIZE.x * 0.5
	var hz: Vector2 = along * TRANSFORMER_SIZE.z * 0.5
	var first := Vector2.INF
	# Корпус упритул до зазору CABINET_GAP_M від стовпа, далі кроками, якщо місце зайняте.
	var along_off: float = POLE_RADIUS + CABINET_GAP_M / 8.0 + TRANSFORMER_SIZE.z * 0.5
	var side_off: float = POLE_RADIUS + CABINET_GAP_M / 8.0 + TRANSFORMER_SIZE.x * 0.5
	for dir: Array in [[along, along_off], [-along, along_off], [side, side_off], [-side, side_off],
			[along, along_off + 0.03], [-along, along_off + 0.03], [side, side_off + 0.03], [-side, side_off + 0.03],
			[along, along_off + 0.06], [-along, along_off + 0.06], [side, side_off + 0.06], [-side, side_off + 0.06]]:
		var c: Vector2 = pos + (dir[0] as Vector2) * float(dir[1])
		first = c if not first.is_finite() else first
		if placer == null:
			return first
		if placer.cabinet_ok([c + hx + hz, c + hx - hz, c - hx + hz, c - hx - hz, c] as Array[Vector2]):
			return c
	return Vector2.INF


func _cabinet_at(pole: Dictionary) -> Vector3:
	var t: Transform3D = pole["transform"]
	var along := Vector2(t.basis.z.x, t.basis.z.z).normalized()
	var side := Vector2(t.basis.x.x, t.basis.x.z).normalized()
	var o := Vector2(t.origin.x, t.origin.z)
	var c: Vector2 = PropLayer.cabinet_centre(o, along, side, _placer)
	if not c.is_finite():
		c = o + along * (POLE_RADIUS + CABINET_GAP_M / 8.0 + TRANSFORMER_SIZE.z * 0.5)
	return Vector3(c.x, t.origin.y + TRANSFORMER_SIZE.y * 0.5, c.y)


## Центри шаф підстанцій, що зараз показано (на поваленій опорі шафи нема).
func transformers_shown() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i: int in _transformers:
		var pole: Dictionary = _instances[i]
		if not _is_crushed(pole):
			out.append(_cabinet_at(pole))
	return out


## Комплектна трансформаторна підстанція (КТП) — сталева шафа ~1.6 × 2.4 × 1.1 м на землі біля опори
## 10 кВ. Повалена опора — без шафи.
func _rebuild_transformers() -> void:
	if _transformers.is_empty():
		return
	if _transformer_node == null:
		# Власний матеріал: сталева шафа (шорсткість 0.75, метал 0.3) — інший за дерев'яні стовпи й уламки.
		var box := BoxMesh.new()
		box.size = TRANSFORMER_SIZE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = TRANSFORMER_COLOR
		mat.roughness = 0.75
		mat.metallic = 0.3
		box.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = _transformers.size()
		_transformer_node = MultiMeshInstance3D.new()
		_transformer_node.name = "Transformers"
		_transformer_node.multimesh = mm
		_transformer_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_transformer_node)
	var mm: MultiMesh = _transformer_node.multimesh
	var k: int = 0
	for i: int in _transformers:
		var pole: Dictionary = _instances[i]
		var at: Vector3 = _cabinet_at(pole)
		var basis: Basis = (pole["transform"] as Transform3D).basis.orthonormalized()
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), at) if _is_crushed(pole)
				else Transform3D(basis, at))
		k += 1


## Розстановка однієї побудови: окремий об'єкт, щоб стан обходу (зайняте, лічильники) не жив
## у шарі між побудовами.
class _Placer:
	var layer: PropLayer
	var world: Board
	var ring: int
	var size: Vector2i
	var height: TerrainHeight
	var map_key: StringName
	var half_dir: Vector2
	var salt: int
	var used: Dictionary = {}
	var spans: Array = []
	## Межі вже поставлених будівель у XZ разом зі звісом даху, власний проміжок кожної і її проєкція
	## на екран: [Rect2, gap, Rect2 екрана, Vector2 глибини]. Нова будівля тримається від них на
	## більший із двох проміжків і не накладається на екрані ближче за SCREEN_DEPTH_SEP углиб.
	var placed: Array = []
	## Клітинка -> модель будівлі на ній: однакові моделі поруч не стають.
	var model_at: Dictionary = {}
	## Хати, уже поставлені (садиби й процедурні села кільця): [клітинка, модель] — щоб сусіди не повторювали форму.
	var farm_houses: Array = []
	## [клітинка, модель] поставлених руїн: сусідні руїни не повторюють вигляд.
	var farm_ruins: Array = []
	var tower_placed := false
	## Скільки поставлено будинків: [одноповерхових, двоповерхових].
	var storeys: Array[int] = [0, 0]
	## Макет сіл карти (VillageLayout); порожній — розстановка процедурою, як для тестових дощок.
	var layout: Dictionary = {}
	## [індекс екземпляра, номер майданчика] будівель на майданчиках.
	var padded: Array = []
	## Клітинки дошки, на яких уже стоїть дрібний пропс (одна річ на ребро).
	var edges: Dictionary = {}
	var gardens: Array[Vector2i] = []
	## Городи садиб: {rect, dir — від хати, green — частка зеленого, home}.
	var garden_plots: Array[Dictionary] = []
	## Стежки (Footpaths) і витоптані плями; домішок до воріт і сараїв збирає _homesteads.
	var walks: Array = []
	var patches: PackedVector3Array = PackedVector3Array()
	## Садиба -> [двері, нормаль фасаду, обрис хати].
	var doors: Dictionary = {}
	## Садиба -> модель хати.
	var house_models: Dictionary = {}
	## Садиба -> обрис сараю.
	var shed_of: Dictionary = {}
	## Садиба -> [середина хвіртки (там іде стежка), нормаль сторони воріт назовні].
	var gates: Dictionary = {}
	## Садиби, де жоден вільний відрізок огорожі не дивиться на дорогу ближче GATE_SIGHT: ворота там — на найближчому до хати.
	var gate_blind: Dictionary = {}
	## Садиба -> запас від будівель, з яким удалось поставити ворота (GATE_CLEARS).
	var gate_clear: Dictionary = {}
	## Садиба, чиє кільце будується зараз, і власники клітинок дворів: чужий двір паркан не перетинає.
	var _ring_i: int = -1
	var _owner_of: Dictionary = {}
	## Множник висоти секцій кільця, що будується (форма паркану).
	var _ring_hmul: float = 1.0
	## Обриси стін (з будівель і сараїв) для кільця, що будується, і його відрізки до постановки.
	var _wall_rects: Array[Rect2] = []
	## Висота кожного обрису з _wall_rects (клітинки) і шапки його димарів (x, z, висота): силует будівлі на екрані
	## для воріт (_gate_at).
	var _wall_tops: Array[float] = []
	var _wall_chims: Array = []
	const SCREEN_OFF: int = 0
	const SCREEN_STRICT: int = 1
	const SCREEN_WIDEST: int = 2
	var _pieces: Array = []
	var _collecting: bool = false
	## Відрізки парканів двору для _fence_segments: рахуються заново, лише коли додались екземпляри.
	var _fence_cache: Array = []
	var _fence_cache_n: int = -1
	## Відрізки воріт [від стовпа до стовпа]: для тих, хто ставить щось поруч (стовпи ЛЕП).
	var gate_segments: Array = []
	## Садиба -> {fence, shed, trailer, gate}: яку форму вона взяла (чого нема — того на дворі нема).
	var forms: Dictionary = {}
	## Вид форми -> [[хата садиби, форма], …]: за ним сусіди не повторюють форм (_pick_apart).
	var _taken: Dictionary = {}
	## Обриси дрібних речей дворів: наступна не стає на попередню.
	var placed_small: Array[Rect2] = []
	## Обриси для стовпів і дротів ЛЕП: будівлі й руїни, мости, решта пропсів (_index_obstacles).
	var _bld_rects: Array[Rect2] = []
	## Висота кожної будівлі з _bld_rects (верх обрису над підошвою, клітинки): нижча будівля ховає менше дроту за собою.
	var _bld_heights: Array[float] = []
	var _bridge_rects: Array[Rect2] = []
	var _home_rects: Array[Rect2] = []
	var _prop_rects: Array[Rect2] = []
	var _garden_rects: Array[Rect2] = []
	var _hay_rects: Array[Rect2] = []
	## Шапки димарів будівель: x, z у плані, y — висота над ґрунтом під будівлею (клітинки).
	var _chimneys: Array[Vector3] = []
	## Клітинка дошки -> відрізки осі дороги поруч [a, b, півширина в клітинках]: покриття дороги
	## — власна геометрія (RoadCourse), не вид клітинки, тож паркан на «полі» міг лягти на асфальт.
	var road_index: Dictionary = {}
	var road_indexed := false
	## Клітинки дошки з огорожею двору: польова огорожа й причепи їх оминають.
	var yard_cells: Dictionary = {}
	## Клітинка двору садиби з макету -> індекс садиби: відвід не йде чужим двором (drop_ok).
	var yard_owner: Dictionary = {}
	## Обриси дворів садиб так, як стоїть паркан (сторони з відступом _fence_ring): стовп ЛЕП туди не ставиться.
	var yard_polys: Array[PackedVector2Array] = []
	## Клітинки дошки під будівлями -> напрям фасаду (−Z моделі) на дошці: двір без будівлі не
	## обгороджується (порожня огорожа серед поля читається уламком), а хвіртка стає перед дверима.
	var built: Dictionary = {}
	var _walk_idx: Dictionary = {}
	var _walk_idx_n: int = -1

	func _init(p_layer: PropLayer, p_world: Board, p_ring: int, p_size: Vector2i,
			p_height: TerrainHeight, p_map: StringName, p_half: Vector2) -> void:
		layer = p_layer
		world = p_world
		ring = p_ring
		size = p_size
		height = p_height
		map_key = p_map
		half_dir = p_half
		salt = String(p_map).hash()
		layout = VillageLayout.for_map(p_map)

	func place_all() -> void:
		if not layout.is_empty():
			_structures()
			_ring_landmark()
			_homesteads()
			settle()
			_footpaths()
			_bridges()
			_layout_hay()
			_blocks()
			_boulders()
			_layout_poles()
			return
		_structures()
		_ring_landmark()
		_dress_yards()
		settle()
		_bridges()
		_yard_fences()
		_field_fences()
		_hay()
		_trailers()
		_blocks()
		_boulders()
		_poles()

	## Орієнтир кільця карти (RING_LANDMARKS): найближче до near вільне поле, що цілком лежить за краєм дошки.
	func _ring_landmark() -> void:
		var spec: Dictionary = PropLayer.RING_LANDMARKS.get(map_key, {})
		if spec.is_empty() or ring <= 0:
			return
		var m: StringName = spec["model"]
		var fp: Vector2i = (PropLayer.model(m) as Dictionary)["footprint"]
		if fp == Vector2i.ZERO:
			return
		var rot: int = int(spec["rot"])
		var s: Vector2i = fp if rot % 2 == 0 else Vector2i(fp.y, fp.x)
		var near: Vector2 = Vector2(spec["near"]) + Vector2(s) * 0.5
		var best := Vector2i.ZERO
		var best_d: float = INF
		var free: Dictionary = {}
		for oy in range(-ring, size.y + ring - s.y + 1):
			for ox in range(-ring, size.x + ring - s.x + 1):
				var o := Vector2i(ox, oy)
				var d: float = (Vector2(o) + Vector2(s) * 0.5 - near).length_squared()
				if d >= best_d:
					continue
				var ok := true
				for dy in s.y:
					for dx in s.x:
						var c: Vector2i = o + Vector2i(dx, dy)
						if on_board(c) or model_at.has(c) or not [Terrain.Kind.FIELD, Terrain.Kind.HILL].has(kind(c)):
							ok = false
				# Ліс і ЛЕП кільця: ні крона, ні опора, ні траса дроту не заходять на орієнтир (крона виступає за клітинку — запас 1 клітинка).
				for dy in range(-1, s.y + 1):
					for dx in range(-1, s.x + 1):
						if kind(o + Vector2i(dx, dy)) == Terrain.Kind.FOREST:
							ok = false
				if ok and _on_route(_rect_of(m, o, rot, s).grow(0.6)):
					ok = false
				if ok and _clear_of_placed(m, o, rot, s):
					best = o
					best_d = d
		if best_d == INF:
			return
		for dy in s.y:
			for dx in s.x:
				free[best + Vector2i(dx, dy)] = true
		_put_structure(m, best, rot, s, free)

	## Клітинка світу -> клітинка дошки.
	func board_cell(w: Vector2i) -> Vector2i:
		return w - Vector2i(ring, ring)

	func on_board(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

	func kind(c: Vector2i) -> int:
		var w: Vector2i = c + Vector2i(ring, ring)
		return world.kind_at(w) if world.in_bounds(w) else -1

	## Половина дошки: 0 — бік гравця 0. Без напряму — ліва/права.
	func half(c: Vector2i) -> int:
		var mid := Vector2(size) * 0.5 - Vector2(0.5, 0.5)
		var d: Vector2 = half_dir if half_dir != Vector2.ZERO else Vector2(-1.0, 0.0)
		return 0 if (Vector2(c) - mid).dot(d) > 0.0 else 1

	func h(c: Vector2i, k: int) -> int:
		return absi(PropLayer.cell_hash(c, salt + k * 7919))

	## Модель виду для половини: кожна половина бере свою, тож пейзаж не віддзеркалений.
	func pick_for_half(kind_id: int, half_id: int, filter: Callable = Callable()) -> StringName:
		var ms: Array[StringName] = PropLayer.models_of(kind_id)
		if filter.is_valid():
			ms = ms.filter(filter)
		if ms.is_empty():
			return &""
		var start: int = absi(hash(Vector2i(salt, kind_id))) % ms.size()
		return ms[(start + half_id) % ms.size()]

	func ground(x: float, z: float) -> float:
		return height.at(x, z) if height != null else 0.0

	## Рівний майданчик під слідом будівлі (TerrainHeight.add_pad); -1 — рельєфу нема.
	func pad(r: Rect2) -> int:
		return height.add_pad(r) if height != null else -1

	## Екземпляр idx стане підошвою на майданчик id наприкінці розстановки: висота тераси ще може
	## змінитися, коли поруч стане інша будівля.
	func seat(idx: int, id: int) -> void:
		if id >= 0:
			padded.append([idx, id])

	## Підошви всіх будівель — на висоти їхніх терас.
	func settle() -> void:
		for e: Array in padded:
			var t: Transform3D = layer._instances[e[0]]["transform"]
			t.origin.y = height.pad_level(e[1])
			layer._instances[e[0]]["transform"] = t

	## Точка на покритті дороги (з запасом pad), за осями RoadCourse і їхньою шириною.
	func on_road(p: Vector2, pad: float) -> bool:
		if not road_indexed:
			_index_roads()
		var c := Vector2i(roundi(p.x), roundi(p.y))
		for seg: Array in road_index.get(c, []):
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var ab: Vector2 = b - a
			var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if p.distance_to(a + ab * t) < float(seg[2]) + pad:
				return true
		return false

	func _index_roads() -> void:
		road_indexed = true
		if height == null or height.roads == null:
			return
		var roads: RoadCourse = height.roads
		for li in roads.lines.size():
			var pts: PackedVector2Array = roads.lines[li]
			for k in range(1, pts.size()):
				var a: Vector2 = pts[k - 1] - Vector2(ring, ring)
				var b: Vector2 = pts[k] - Vector2(ring, ring)
				var half: float = float(roads.halfs[li][k]) / 8.0
				var lo := Vector2i(floori(minf(a.x, b.x) - half - 0.5), floori(minf(a.y, b.y) - half - 0.5))
				var hi := Vector2i(ceili(maxf(a.x, b.x) + half + 0.5), ceili(maxf(a.y, b.y) + half + 0.5))
				for y in range(lo.y, hi.y + 1):
					for x in range(lo.x, hi.x + 1):
						var key := Vector2i(x, y)
						if not road_index.has(key):
							road_index[key] = []
						(road_index[key] as Array).append([a, b, half])

	## Межа пропса в XZ (кути й середина) лежить на покритті дороги.
	func _box_on_road(m: StringName, xform: Transform3D) -> bool:
		var box: AABB = xform * ((PropLayer.model(m) as Dictionary)["aabb"] as AABB)
		for v: Vector2 in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
				Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z),
				Vector2(box.get_center().x, box.get_center().z)]:
			if on_road(v, ROAD_PAD):
				return true
		return false

	## Точка ближче за clear до клітинки води чи болота.
	func near_wet(p: Vector2, clear: float) -> bool:
		var c := Vector2i(roundi(p.x), roundi(p.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				var kd: int = kind(n)
				if kd != Terrain.Kind.WATER and kd != Terrain.Kind.MARSH:
					continue
				var nearest := Vector2(clampf(p.x, n.x - 0.5, n.x + 0.5), clampf(p.y, n.y - 0.5, n.y + 0.5))
				if p.distance_to(nearest) < clear:
					return true
		return false

	## Хата (будинок, не вежа й не двірське вбрання) в межах HOUSE_NEAR клітинок.
	func house_near(c: Vector2i) -> bool:
		for dy in range(-HOUSE_NEAR, HOUSE_NEAR + 1):
			for dx in range(-HOUSE_NEAR, HOUSE_NEAR + 1):
				var n: StringName = model_at.get(c + Vector2i(dx, dy), &"")
				if n == &"":
					continue
				var s: Dictionary = PropLayer.spec_of(n)
				if int(s["kind"]) == Kind.STRUCTURE and not bool(s.get("tower", false)):
					return true
		return false

	const N_FACE := Vector2i(0, -1)
	const W_FACE := Vector2i(-1, 0)
	const S_FACE := Vector2i(0, 1)
	const E_FACE := Vector2i(1, 0)

	## Межі екземпляра в XZ відносно центру клітинки не заходять у квадрат юніта.
	## Обрис r не заходить у слід юніта (UNIT_HALF + margin) на жодній клітинці, де юніт може стояти.
	func clear_of_units(r: Rect2, margin: float = 0.0) -> bool:
		var cc := Vector2i(roundi(r.get_center().x), roundi(r.get_center().y))
		var half: float = PropLayer.UNIT_HALF + margin
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = cc + Vector2i(dx, dy)
				if not on_board(c) or kind(c) == Terrain.Kind.WATER:
					continue
				var hc: float = 0.5 if layer.spawn_cells.has(c) else half
				if r.intersects(Rect2(Vector2(c) - Vector2(hc, hc), Vector2(hc, hc) * 2.0)):
					return false
		return true

	func clear_of_centre(m: StringName, xform: Transform3D, c: Vector2i) -> bool:
		var box: AABB = xform * ((PropLayer.model(m) as Dictionary)["aabb"] as AABB)
		var lo := Vector2(box.position.x - c.x, box.position.z - c.y)
		var hi := Vector2(box.end.x - c.x, box.end.z - c.y)
		return lo.x >= PropLayer.KEEP_OUT or hi.x <= -PropLayer.KEEP_OUT \
				or lo.y >= PropLayer.KEEP_OUT or hi.y <= -PropLayer.KEEP_OUT

	## tilt — довгий пропс (огорожа) лягає за схилом уздовж своєї довжини (локальна X), а не стоїть
	## рівно, одним кінцем у повітрі.
	## length — масштаб уздовж локальної X: огорожа двору подовжується на кутах до сусідньої.
	func put_small(m: StringName, c: Vector2i, local: Vector2, yaw: float, scale: float = 1.0, tilt: bool = false,
			length: float = 1.0, height: float = 1.0) -> bool:
		if m == &"":
			return false
		var x: float = c.x + local.x
		var z: float = c.y + local.y
		var basis := Basis(Vector3.UP, yaw)
		var y: float = ground(x, z)
		if tilt:
			var half_len: float = ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.x * 0.5 * length
			var along: Vector3 = basis.x * half_len
			var y0: float = ground(x - along.x, z - along.z)
			var y1: float = ground(x + along.x, z + along.z)
			basis = Basis(basis.z, atan2(y1 - y0, 2.0 * half_len)) * basis
			# Секція обертається довкола середини: та стоїть на середній висоті кінців, тож обидва
			# кінці на землі, а не один у ній.
			y = (y0 + y1) * 0.5
		var xform := Transform3D(basis * Basis.from_scale(Vector3(length, height, 1.0) * scale), Vector3(x, y, z))
		if not clear_of_centre(m, xform, c) or _box_on_road(m, xform):
			return false
		var cells: Array[Vector2i] = [c]
		layer._add(m, xform, cells)
		return true

	# --- будівлі ---------------------------------------------------------------------------

	## Кожна зв'язна група BUILDING (і дошки, і кільця) заповнюється цілими слідами: спершу більші,
	## вага моделі й хеш вирішують, яку саме; повернута фасадом (−Z) до дороги, якщо та поруч.
	## Клітинка, куди не влізло нічого, лишається двором. RUBBLE — та сама логіка з руїнами.
	func _structures() -> void:
		# Руїни першими: клітинка RUBBLE мусить читатися руїною, а будинок поруч поступиться їй.
		for target: int in [Terrain.Kind.RUBBLE, Terrain.Kind.BUILDING]:
			var kind_id: int = Kind.STRUCTURE if target == Terrain.Kind.BUILDING else Kind.RUIN
			var seen: Dictionary = {}
			var groups: Array = []
			for wy in world.height:
				for wx in world.width:
					var w := Vector2i(wx, wy)
					if seen.has(w) or world.kind_at(w) != target:
						continue
					var group: Array[Vector2i] = []
					var queue: Array[Vector2i] = [w]
					seen[w] = true
					while not queue.is_empty():
						var q: Vector2i = queue.pop_back()
						group.append(board_cell(q))
						for d in Board.DIRS_4:
							var n: Vector2i = q + d
							if world.in_bounds(n) and not seen.has(n) and world.kind_at(n) == target:
								seen[n] = true
								queue.append(n)
					group.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
					groups.append(group)
			# Спершу групи дошки: єдина на карту вежа — орієнтир села, а не пейзажу за краєм.
			var board_first: Array = groups.filter(func(g: Array) -> bool: return g.any(func(c: Vector2i) -> bool: return on_board(c)))
			# Села дошки — з макету карти; процедура лишається для кільця.
			if not layout.is_empty() and target == Terrain.Kind.BUILDING:
				groups = groups.filter(func(g: Array) -> bool: return not board_first.has(g))
				board_first = []
			for g: Array[Vector2i] in board_first + groups.filter(func(g: Array) -> bool: return not board_first.has(g)):
				_fill_group(g, kind_id)

	func _fill_group(group: Array[Vector2i], kind_id: int) -> void:
		var free: Dictionary = {}
		for c in group:
			free[c] = true
		var in_ring: bool = not group.any(func(c: Vector2i) -> bool: return on_board(c))
		var has_tower := false
		var models: Array[StringName] = PropLayer.models_of(kind_id)
		var step: int = 0
		while true:
			var options: Array = []
			var total: int = 0
			for m in models:
				var s: Dictionary = PropLayer.spec_of(m)
				if bool(s.get("ring", false)) and not in_ring or bool(s.get("yard_only", false)):
					continue
				if s.has("max") and int(used.get(m, 0)) >= int(s["max"]):
					continue
				if bool(s.get("tower", false)) and (has_tower or tower_placed):
					continue
				# Двоповерхових не більше, ніж одноповерхових: село — це передусім хати.
				if int(s.get("storeys", 1)) >= 2 and storeys[1] >= storeys[0]:
					continue
				var fp: Vector2i = (PropLayer.model(m) as Dictionary)["footprint"]
				if fp == Vector2i.ZERO:
					continue
				for c in group:
					if not free.has(c):
						continue
					for rot in 4:
						# Фасад до камери: −Z після повороту дивиться на +z (rot 2) чи +x (rot 3).
						if PropLayer.CAMERA_FRONT.has(m) and rot < 2:
							continue
						var size_r: Vector2i = fp if rot % 2 == 0 else Vector2i(fp.y, fp.x)
						# Руїна стоїть на кожній клітинці RUBBLE (вона й є вид клітинки), тож правила відстані
						# її не відсувають; будинки ж тримаються від руїн, як від будь-якої будівлі.
						var ruin: bool = kind_id == Kind.RUIN
						if _fits(free, c, size_r) and _inside_yard(m, c, rot, size_r) \
								and (ruin or (_clear_of_placed(m, c, rot, size_r) and _no_twin(m, c, size_r) \
								and _tower_apart(m, c, size_r))):
							var weight: int = int(s.get("weight", 1)) * size_r.x * size_r.y
							options.append([m, c, rot, size_r, weight, _faces_road(c, size_r, rot)])
			if options.is_empty():
				return
			# Фасадом до дороги, щойно таке місце є: хата не стоїть до вулиці глухим боком.
			if options.any(func(o: Array) -> bool: return o[5]):
				options = options.filter(func(o: Array) -> bool: return o[5])
			# Хата не повторює форму сусідньої (ближче HOUSE_APART), якщо є з чого вибрати.
			var varied: Array = options.filter(func(o: Array) -> bool: return not (String(o[0]).begins_with("house_") and _house_near(o[0], o[1])))
			if not varied.is_empty():
				options = varied
			for o: Array in options:
				total += int(o[4])
			var roll: int = h(group[0], 100 + step) % total
			step += 1
			for o: Array in options:
				roll -= int(o[4])
				if roll < 0:
					if kind_id == Kind.RUIN:
						o = _ruin_swap(o, options)
					_put_structure(o[0], o[1], o[2], o[3], free)
					if String(o[0]).begins_with("house_"):
						farm_houses.append([o[1], o[0]])
					if kind_id == Kind.RUIN:
						farm_ruins.append([o[1], o[0]])
					has_tower = has_tower or bool(PropLayer.spec_of(o[0]).get("tower", false))
					tower_placed = tower_placed or has_tower
					break

	func _rect_of(m: StringName, origin: Vector2i, rot: int, s: Vector2i) -> Rect2:
		var centre := Vector2(origin) + Vector2(s - Vector2i.ONE) * 0.5
		var box: AABB = Transform3D(_basis_of(m, rot), Vector3(centre.x, 0.0, centre.y)) \
				* ((PropLayer.model(m) as Dictionary)["aabb"] as AABB)
		return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)

	func _gap_of(m: StringName) -> float:
		return maxf(STRUCTURE_GAP, float(PropLayer.spec_of(m).get("gap", 0.0)))

	func _clear_of_placed(m: StringName, origin: Vector2i, rot: int, s: Vector2i) -> bool:
		var r: Rect2 = _rect_of(m, origin, rot, s)
		var scr: Array = _screen_of(r, _height_of(m))
		for p: Array in placed:
			if r.grow(maxf(_gap_of(m), float(p[1]))).intersects(p[0]):
				return false
			var margin: float = SCREEN_GROUND_RUIN if p[4] else SCREEN_GROUND
			if (scr[0] as Rect2).grow(margin).intersects(p[2]) and _depth_gap(scr[1], p[3]) < SCREEN_DEPTH_SEP:
				return false
		return true

	func _height_of(m: StringName) -> float:
		return ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.y * _scale_of(m)

	func _scale_of(m: StringName) -> float:
		return float(PropLayer.spec_of(m).get("scale", 1.0))

	func _basis_of(m: StringName, rot: int) -> Basis:
		return Basis(Vector3.UP, rot * PI * 0.5).scaled(Vector3.ONE * _scale_of(m))

	## Проєкція межі будівлі (разом із висотою даху) на екран камери гри: [Rect2 екрана, Vector2
	## глибини вздовж погляду]. Камера стоїть на +x, +z від фокуса й дивиться на −x, −z.
	static func _screen_of(r: Rect2, h: float) -> Array:
		var right := Vector2(1.0, -1.0).normalized()
		var fwd := Vector2(-1.0, -1.0).normalized()
		var pitch: float = deg_to_rad(SCREEN_PITCH_DEG)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var d := Vector2(INF, -INF)
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var depth: float = c.dot(fwd)
			d = Vector2(minf(d.x, depth), maxf(d.y, depth))
			for y: float in [0.0, h]:
				var p := Vector2(c.dot(right), depth * sin(pitch) + y * cos(pitch))
				lo = lo.min(p)
				hi = hi.max(p)
		return [Rect2(lo, hi - lo), d]

	## Напрям погляду камери в плані (IsoCameraRig.YAW_DEGREES): від камери вглиб, як у _seen_clear.
	static func _cam_fwd() -> Vector2:
		return -Vector2(sin(deg_to_rad(IsoCameraRig.YAW_DEGREES)), cos(deg_to_rad(IsoCameraRig.YAW_DEGREES)))

	## Точка плану (x, z) на висоті y — на екрані камери під найнижчим нахилом рига (там силуети найвищі), у клітинках
	## площини фокуса.
	static func _screen_pt(c: Vector2, y: float) -> Vector2:
		var pitch: float = deg_to_rad(IsoCameraRig.PITCH_NEAR_DEG)
		var fwd: Vector2 = _cam_fwd()
		return Vector2(c.dot(Vector2(-fwd.y, fwd.x)), c.dot(fwd) * sin(pitch) + y * cos(pitch))

	## Відстань на екрані (клітинки площини фокуса) від верху q (висота h) до найближчого силуету з hulls; 0 — усередині.
	## Байдуже, перед будівлею точка чи за нею: за — ворота визирають з-за даху, перед — затуляють перший поверх.
	static func _hull_gap(q: Vector2, h: float, hulls: Array) -> float:
		var s: Vector2 = _screen_pt(q, h)
		var gap: float = INF
		for hull: PackedVector2Array in hulls:
			if Geometry2D.is_point_in_polygon(s, hull):
				return 0.0
			for k in hull.size() - 1:
				gap = minf(gap, Geometry2D.get_closest_point_to_segment(s, hull[k], hull[k + 1]).distance_to(s))
		return gap

	static func _depth_gap(a: Vector2, b: Vector2) -> float:
		return maxf(0.0, maxf(b.x - a.y, a.x - b.y))

	## Та сама модель не стоїть у сусідній клітинці (і по діагоналі): ряд однакових хат — штамп.
	func _no_twin(m: StringName, origin: Vector2i, s: Vector2i) -> bool:
		for dy in range(-1, s.y + 1):
			for dx in range(-1, s.x + 1):
				if model_at.get(origin + Vector2i(dx, dy), &"") == m:
					return false
		return true

	## Вежа — у власному дворі: жодна будівля не стоїть поруч із нею (і по діагоналі).
	func _tower_apart(m: StringName, origin: Vector2i, s: Vector2i) -> bool:
		var tower: bool = bool(PropLayer.spec_of(m).get("tower", false))
		for dy in range(-1, s.y + 1):
			for dx in range(-1, s.x + 1):
				var n: Vector2i = origin + Vector2i(dx, dy)
				if not model_at.has(n):
					continue
				if tower or bool(PropLayer.spec_of(model_at[n]).get("tower", false)):
					return false
		return true

	## Межа моделі зі звісом даху лежить у власному сліді з відступом з усіх боків: огорожа двору йде
	## довкола ділянки під будівлями, тож може пройти й між будинком і порожньою клітинкою групи.
	## Велика будівля — YARD_CLEAR, на одну клітинку — YARD_CLEAR_SMALL (до огорожі однаково ≥ 0.3
	## клітинки), руїна (її не обгороджують) — лише не за межею клітинки.
	func _inside_yard(m: StringName, origin: Vector2i, rot: int, s: Vector2i) -> bool:
		var r: Rect2 = _rect_of(m, origin, rot, s)
		var f := Rect2(Vector2(origin) - Vector2(0.5, 0.5), Vector2(s))
		var ruin: bool = int(PropLayer.spec_of(m)["kind"]) == Kind.RUIN
		var margin: float = 0.0 if ruin else (YARD_CLEAR_SMALL if s == Vector2i.ONE else YARD_CLEAR)
		return f.grow(-margin + 1e-4).encloses(r)

	func _fits(free: Dictionary, origin: Vector2i, s: Vector2i) -> bool:
		for dy in s.y:
			for dx in s.x:
				if not free.has(origin + Vector2i(dx, dy)):
					return false
		return true

	## Фасад (−Z моделі) після повороту rot·90° дивиться на дорогу одразу за слідом.
	func _faces_road(origin: Vector2i, s: Vector2i, rot: int) -> bool:
		var front: Vector2i = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)][rot]
		for dy in s.y:
			for dx in s.x:
				var n: Vector2i = origin + Vector2i(dx, dy) + front
				if kind(n) == Terrain.Kind.ROAD:
					return true
		return false

	func _put_structure(m: StringName, origin: Vector2i, rot: int, s: Vector2i, free: Dictionary) -> void:
		var cells: Array[Vector2i] = []
		# Будівля дошки відсувається в межах своєї клітинки від уже поставлених на BUILDING_GAP.
		var shift: Vector2 = _best_shift(_rect_of(m, origin, rot, s), BUILDING_SHIFT) if on_board(origin) else Vector2.ZERO
		for dy in s.y:
			for dx in s.x:
				var c: Vector2i = origin + Vector2i(dx, dy)
				free.erase(c)
				cells.append(c)
				built[c] = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)][rot]
		var r_box: Rect2 = _rect_of(m, origin, rot, s)
		r_box.position += shift
		var pid: int = pad(r_box)
		used[m] = int(used.get(m, 0)) + 1
		var sp: Dictionary = PropLayer.spec_of(m)
		if int(sp["kind"]) == Kind.STRUCTURE and not bool(sp.get("tower", false)):
			storeys[1 if int(sp.get("storeys", 1)) >= 2 else 0] += 1
		var r: Rect2 = r_box
		var scr: Array = _screen_of(r, _height_of(m))
		placed.append([r, _gap_of(m), scr[0], scr[1], int(PropLayer.spec_of(m)["kind"]) == Kind.RUIN])
		for c in cells:
			model_at[c] = m
		var centre := Vector2(origin) + Vector2(s - Vector2i.ONE) * 0.5 + shift
		seat(layer._add(m, Transform3D(_basis_of(m, rot), Vector3(centre.x, 0.0, centre.y)), _board_only(cells)), pid)

	## Найменший зсув обрису r (кроком 0.05, не далі limit), за якого він на BUILDING_GAP від усіх уже
	## поставлених будівель; якщо такого нема — зсув із найбільшим проміжком.
	func _best_shift(r: Rect2, limit: float) -> Vector2:
		var cands: Array[Vector2] = []
		var n: int = roundi(limit / 0.05)
		for dy in range(-n, n + 1):
			for dx in range(-n, n + 1):
				cands.append(Vector2(dx, dy) * 0.05)
		cands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())
		var best := Vector2.ZERO
		var best_gap: float = -INF
		for v in cands:
			var q := Rect2(r.position + v, r.size)
			var g: float = INF
			for p: Array in placed:
				var o: Rect2 = p[0]
				g = minf(g, maxf(maxf(o.position.x - q.end.x, q.position.x - o.end.x), maxf(o.position.y - q.end.y, q.position.y - o.end.y)))
			if g >= BUILDING_GAP:
				return v
			if g > best_gap + 1e-4:
				best_gap = g
				best = v
		return best

	## Чи заходить траса 10 кВ макета (вісь дороги, уздовж якої PowerGrid ставить стовпи) у прямокутник.
	func _on_route(r: Rect2) -> bool:
		for route: Dictionary in layout.get("routes", []):
			var pts: Array = route["axis"]
			for k in range(1, pts.size()):
				if _seg_hits_rect(pts[k - 1], pts[k], r):
					return true
		return false

	static func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
		if r.has_point(a) or r.has_point(b):
			return true
		var c: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in 4:
			if Geometry2D.segment_intersects_segment(a, b, c[k], c[(k + 1) % 4]) != null:
				return true
		return false

	func _board_only(cells: Array[Vector2i]) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in cells:
			if on_board(c):
				out.append(c)
		# Будівля кільця не стоїть на жодній клітинці дошки, але має ключ для пошуку.
		return out if not out.is_empty() else cells

	# --- двори ------------------------------------------------------------------------------

	## Кожна клітинка BUILDING дошки читається забудованою (§8: вид клітинки видно). Хата — головне;
	## де вона не стала, там двір хати: одна повітка й один причіп на двір як доповнення, решта —
	## город із грядками й тюком. Клітинки двору обгороджуються разом із хатою одним контуром.
	func _dress_yards() -> void:
		var shed_in: Dictionary = {}
		var trailer_in: Dictionary = {}
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if kind(c) != Terrain.Kind.BUILDING or built.has(c):
					continue
				built[c] = Vector2i.ZERO
				var yard: Vector2i = _yard_key(c)
				var yaw: float = float(h(c, 140) % 4) * PI * 0.5
				# Поруч із вежею повітки нема: вежа стоїть у власному дворі.
				var by_tower := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n: StringName = model_at.get(c + Vector2i(dx, dy), &"")
						by_tower = by_tower or bool(PropLayer.spec_of(n).get("tower", false))
				var roll: int = h(c, 141) % 3 if house_near(c) else 2
				if roll == 0 and not by_tower and not shed_in.has(yard):
					shed_in[yard] = true
					var shed_m: StringName = _pick_apart(YARD_SHEDS, c, &"shed", h(yard, 143) % YARD_SHEDS.size())
					if not _taken.has(&"shed"):
						_taken[&"shed"] = []
					(_taken[&"shed"] as Array).append([c, shed_m])
					var cells: Array[Vector2i] = [c]
					var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * YARD_SHED_SCALE), Vector3(c.x, 0.0, c.y))
					var box: AABB = xf * ((PropLayer.model(shed_m) as Dictionary)["aabb"] as AABB)
					seat(layer._add(shed_m, xf, cells, true), pad(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)))
				elif roll == 1 and not trailer_in.has(yard):
					trailer_in[yard] = true
					_yard_item(_trailer_apart(c), c, Vector2(0.0, 0.1), yaw)
				elif _house_beside(c) and h(c, 145) % 3 != 0:
					# Город — при самій хаті, і не на кожній вільній клітинці.
					gardens.append(c)

	## Причіп поблизу клітинки c: вид, якого нема в причепів ближче HOUSE_APART клітинок (_pick_apart); &"" — моделей нема.
	func _trailer_apart(c: Vector2i) -> StringName:
		var forms_of: Array[StringName] = PropLayer.models_of(Kind.TRAILER)
		if forms_of.is_empty():
			return &""
		var m: StringName = _pick_apart(forms_of, c, &"trailer", half(c))
		if not _taken.has(&"trailer"):
			_taken[&"trailer"] = []
		(_taken[&"trailer"] as Array).append([c, m])
		return m

	## Хата на сусідній клітинці (і по діагоналі).
	func _house_beside(c: Vector2i) -> bool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: StringName = model_at.get(c + Vector2i(dx, dy), &"")
				if n == &"":
					continue
				var sp: Dictionary = PropLayer.spec_of(n)
				if int(sp["kind"]) == Kind.STRUCTURE and not bool(sp.get("tower", false)):
					return true
		return false

	## Двір — зв'язна група BUILDING дошки; ключ — її найменша клітинка.
	func _yard_key(c: Vector2i) -> Vector2i:
		var best: Vector2i = c
		var seen: Dictionary = {c: true}
		var queue: Array[Vector2i] = [c]
		while not queue.is_empty():
			var q: Vector2i = queue.pop_back()
			if q.y < best.y or (q.y == best.y and q.x < best.x):
				best = q
			for d in Board.DIRS_4:
				var n: Vector2i = q + d
				if not seen.has(n) and on_board(n) and kind(n) == Terrain.Kind.BUILDING:
					seen[n] = true
					queue.append(n)
		return best

	func _yard_item(m: StringName, c: Vector2i, local: Vector2, yaw: float) -> void:
		if m == &"" or PropLayer.model(m) == null:
			return
		var x: float = c.x + local.x
		var z: float = c.y + local.y
		var cells: Array[Vector2i] = [c]
		layer._add(m, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, ground(x, z), z)), cells, true)

	# --- села за макетом карти -----------------------------------------------------------------

	## Садиби з VillageLayout: хата на своїй клітинці фасадом до дороги, город за нею (30–50 % двору,
	## частина зелена, частина гола), сарай, решта двору — трава. Клітинки між садибами (orchards) —
	## трав'яні двори й лук із поодиноким дров'яником, без городів.
	func _homesteads() -> void:
		var homes: Array = layout.get("homes", [])
		var owner_of: Dictionary = {}
		for i in homes.size():
			for c: Vector2i in homes[i]["cells"]:
				owner_of[c] = i
		yard_owner = owner_of
		var sheds: Array[Rect2] = []
		var house_rects: Dictionary = {}
		for i in homes.size():
			var home: Dictionary = homes[i]
			var hc: Vector2i = home["house"]
			var rot: int = [N_FACE, W_FACE, S_FACE, E_FACE].find(home["face"])
			house_models[i] = _house_model(hc, i)
			var house_rot: int = (rot + 2) % 4 if PropLayer.HOUSE_BACK_DOOR.has(house_models[i]) else rot
			_put_structure(house_models[i], hc, house_rot, Vector2i.ONE, {})
			house_rects[i] = placed.back()[0]
			var gcells: Array = home.get("garden", [])
			if not gcells.is_empty():
				# Город — одна ділянка по клітинках городу, площею ~40 % двору (не більше 80 % тих клітинок),
				# зсунута від хати вглиб.
				var lo := Vector2(gcells[0])
				var hi := Vector2(gcells[0])
				for g: Vector2i in gcells:
					lo = lo.min(Vector2(g))
					hi = hi.max(Vector2(g))
					gardens.append(g)
				var box := Rect2(lo - Vector2(0.5, 0.5), hi - lo + Vector2.ONE)
				var f: float = sqrt(minf(GARDEN_SHARE * float((home["cells"] as Array).size()), 0.8 * box.get_area()) / box.get_area())
				var away: Vector2 = (box.get_center() - Vector2(hc)).normalized()
				var size: Vector2 = box.size * f
				var centre: Vector2 = box.get_center() + away * (box.size - size) * 0.25
				# Частка зеленого: картопля чи капуста на частині городу, решта — голий ґрунт.
				garden_plots.append({"rect": Rect2(centre - size * 0.5, size), "dir": away,
						"green": [0.0, 0.4, 0.65][h(hc, 151) % 3], "home": i})
				# Город — рівна ділянка, як і майданчик хати: плоска плитка грядок на перегині рельєфу
				# (спад майданчика) різалася б ґрунтом на клапті. Запас покриває поворот плитки (≤ 3°).
				pad(Rect2(centre - size * 0.5, size).grow(0.03))
			for c: Vector2i in home["cells"]:
				if not built.has(c):
					built[c] = Vector2i.ZERO
			var shed_models: Array[StringName] = PropLayer.YARD_SHEDS.filter(func(m: StringName) -> bool: return PropLayer.model(m) != null)
			if home.has("shed") and not shed_models.is_empty():
				var shed_m: StringName = _pick_apart(shed_models, hc, &"shed", h(hc, 171) % shed_models.size())
				var sc: Vector2i = home["shed"]
				var cells: Array[Vector2i] = [sc]
				var xf := Transform3D(Basis(Vector3.UP, rot * PI * 0.5).scaled(Vector3.ONE * YARD_SHED_SCALE), Vector3(sc.x, 0.0, sc.y))
				var box: AABB = xf * ((PropLayer.model(shed_m) as Dictionary)["aabb"] as AABB)
				var shift: Vector2 = _best_shift(Rect2(box.position.x, box.position.z, box.size.x, box.size.z), BUILDING_SHIFT + 0.1)
				var sr := Rect2(box.position.x + shift.x, box.position.z + shift.y, box.size.x, box.size.z)
				# Біля води сарай не ставимо.
				if near_wet(sr.get_center(), WATER_CLEAR) or near_wet(sr.position, WATER_CLEAR) or near_wet(sr.end, WATER_CLEAR):
					continue
				# Сарай, якому між хатою й руїною нема місця, не ставимо: впритул вони читаються одним.
				if placed.any(func(p: Array) -> bool: return sr.grow(BUILDING_GAP - 1e-3).intersects(p[0])):
					continue
				xf.origin += Vector3(shift.x, 0.0, shift.y)
				seat(layer._add(shed_m, xf, cells, true), pad(sr))
				_note_form(i, hc, &"shed", shed_m)
				sheds.append(sr)
				shed_of[i] = sr
				var scr: Array = _screen_of(sr, _height_of(shed_m) * YARD_SHED_SCALE)
				placed.append([sr, STRUCTURE_GAP, scr[0], scr[1], false])
		# Лук між садибами — трава; поодинокі колоди читались мотлохом, тож дров нема, доки нема моделі
		# складених дров.
		for c: Vector2i in layout.get("orchards", []):
			built[c] = Vector2i.ZERO
		var rings: Dictionary = {}
		for i in homes.size():
			rings[i] = _fence_ring(i, homes[i], owner_of, sheds)
			yard_polys.append(_ring_polygon(rings[i]))
		# Город — усередині кільця й осторонь будівель: не під руїною, не за парканом.
		for gp: Dictionary in garden_plots:
			gp["rect"] = _clip_garden(gp["rect"], rings.get(gp["home"], []))
		garden_plots = garden_plots.filter(func(gp: Dictionary) -> bool:
			return (gp["rect"] as Rect2).size.x >= 0.3 and (gp["rect"] as Rect2).size.y >= 0.3)
		for i in homes.size():
			var hr: Rect2 = house_rects[i]
			var face := Vector2(homes[i]["face"])
			# Двері — посередині фасаду, на краю обрису хати.
			var door: Vector2 = hr.get_center() + face * (absf(face.x) * hr.size.x + absf(face.y) * hr.size.y) * 0.5
			var path: Array = []
			if gates.has(i):
				var gate: Vector2 = gates[i][0]
				if gate.distance_to(door) >= 0.05:
					path = [gate, door, PATH_WIDTH]
			doors[i] = [door, face, hr]
			_dress_home(i, homes[i], path)

	## Протоптані стежки (Footpaths): від дверей кожної хати макету через ворота до узбіччя, витоптані
	## плями біля воріт і сараїв та 1–2 стежки від дороги до берега. Лише вигляд: маску зносу читає земля.
	func _footpaths() -> void:
		var homes: Array = layout.get("homes", [])
		for i in homes.size():
			if not doors.has(i):
				continue
			var door: Vector2 = doors[i][0]
			var face: Vector2 = doors[i][1]
			var house: Rect2 = doors[i][2]
			var gate: Vector2 = door + face * 0.5
			var out: Vector2 = face
			if gates.has(i):
				gate = gates[i][0]
				out = gates[i][1]
			var sd: int = h(homes[i]["house"], 190)
			var porch: Vector2 = door + face * 0.14
			# Огорожа впритул до фасаду (смуга вужча за ґанок) — ґанок і стежка лишаються в смузі, не за парканом.
			var front: float = _fence_ray(door, face, 0.14)
			var tight: bool = front < 0.14
			if tight:
				porch = door + face * maxf(0.02, front - 0.04)
			var inside: Vector2 = gate - out * 0.12
			var outside: Vector2 = gate + out * 0.15
			var road: Vector2 = _verge_point(outside)
			# Двері можуть дивитися від воріт (Хребет): тоді стежка обходить хату, а не різає її.
			var ctrl := PackedVector2Array([door, porch])
			var route: PackedVector2Array = _yard_route(porch, inside)
			var via_gate: bool = not route.is_empty()
			if via_gate:
				ctrl.append_array(route)
				ctrl.append_array([gate, outside])
			else:
				# Двері по той бік паркану (вони стоять на вулиці): стежка йде від дверей на узбіччя, повз ворота.
				outside = porch
				road = _verge_point(porch)
			if road != Vector2.INF and road.distance_to(outside) > 0.02:
				# Узбіччя може бути за сусідньою будівлею чи парканом: теж обхід, а не пряма.
				# Дорога по той бік паркану (ворота дивляться від неї): стежка кінчається біля воріт, не крізь двір.
				ctrl.append_array(_yard_route(outside, road, 1.8, false))
			var pts := PackedVector2Array([ctrl[0]])
			for k in range(1, ctrl.size()):
				if ctrl[k].distance_to(ctrl[k - 1]) > 1e-3:
					pts.append_array(Footpaths.meander(ctrl[k - 1], ctrl[k], 0.01, 1.0, sd + k).slice(1))
			pts = Footpaths.resample(Footpaths.smooth(pts, 2))
			if _path_hits_fence(pts) or _path_in_building(pts):
				pts = Footpaths.resample(ctrl)
				# Ламана з маршрутів сітки перевірена по прямій видимості; якщо й вона перетинає — стежки двору нема.
				if _path_hits_fence(pts) or _path_in_building(pts):
					continue
			# Безперервна смуга від дверей через хвіртку до узбіччя: ~0.7 м, біля дверей і хвіртки вдвічі ширша.
			var hw := PackedFloat32Array()
			hw.resize(pts.size())
			for k in pts.size():
				var f: float = 1.0
				for pin: Vector2 in [door, gate]:
					f += 1.0 * exp(-pts[k].distance_to(pin) * pts[k].distance_to(pin) / 0.03)
				hw[k] = Footpaths.HALF * f
			walks.append({"kind": &"yard", "home": i, "door": door, "pts": pts, "seed": sd, "solid": 0.8,
					"fade_end": minf(0.08, 0.2 * Footpaths.length(pts)), "half": hw})
			_yard_floor(i, homes[i], inside, porch, door, sd)
			# Пляма біля хвіртки: назовні, коли там є узбіччя; хвіртка майже на узбіччі — менша впритул до
			# неї; хвіртка на самому краю дороги — у дворі перед нею. Без плями вхід у двір не читався.
			# На полотно дороги вона однаково не лягає — маску ріже dry.
			for cand: Array in [[0.22, 0.28, 0.3], [0.06, 0.2, 0.12], [-0.12, 0.18, 0.0]]:
				var gp: Vector2 = gate + out * float(cand[0])
				if not on_road(gp, float(cand[2])) and _on_board(gp):
					patches.append(Vector3(gp.x, gp.y, float(cand[1])))
					break
			var pp: Vector2 = porch + face * (0.06 if not tight else 0.0)
			if _on_board(pp):
				patches.append(Vector3(pp.x, pp.y, 0.2))
			if shed_of.has(i):
				var sr: Rect2 = shed_of[i]
				var dir: Vector2 = (door - sr.get_center()).normalized()
				var reach: float = minf(sr.size.x * 0.5 / maxf(absf(dir.x), 1e-3), sr.size.y * 0.5 / maxf(absf(dir.y), 1e-3))
				var at: Vector2 = sr.get_center() + dir * (reach + 0.14)
				if not on_road(at, 0.3) and _on_board(at):
					patches.append(Vector3(at.x, at.y, 0.2))
		_water_walks()

	## Збите подвір'я: пляма на трикутник «хвіртка — двері — сарай чи город» (~20–40 м²) і проходи 1–1.5 м від
	## хвіртки та від дверей до сараю, з рваним краєм й острівцями трави. Видно й коли хата частково закриває двері.
	func _yard_floor(i: int, home: Dictionary, inside: Vector2, porch: Vector2, door: Vector2, sd: int) -> void:
		var tgt := Vector2.INF
		if shed_of.has(i):
			var sr: Rect2 = shed_of[i]
			var dir: Vector2 = (door - sr.get_center()).normalized()
			tgt = sr.get_center() + dir * (maxf(sr.size.x, sr.size.y) * 0.5 + 0.12)
		else:
			for gp: Dictionary in garden_plots:
				if int(gp["home"]) == i:
					var gr: Rect2 = gp["rect"]
					tgt = gr.get_center() + (door - gr.get_center()).normalized() * (maxf(gr.size.x, gr.size.y) * 0.5 + 0.1)
					break
		if tgt == Vector2.INF:
			var sum := Vector2.ZERO
			for c: Vector2i in home["cells"]:
				sum += Vector2(c)
			tgt = porch.lerp(sum / float(home["cells"].size()), 0.6)
		for a: Vector2 in [inside, porch + (porch - door).normalized() * 0.06, tgt]:
			walks.append({"kind": &"yard_floor", "home": i, "door": a, "pts": PackedVector2Array([a, a + Vector2(0.03, 0.0)]),
					"seed": sd + 3, "solid": 0.85, "flat": 3.0, "half": PackedFloat32Array([0.26, 0.26])})
		for pair: Array in [[inside, tgt], [porch, tgt]]:
			var pts: PackedVector2Array = Footpaths.resample(Footpaths.smooth(Footpaths.meander(pair[0], pair[1], 0.04, 0.8, sd + 5), 4))
			# Стежка до сараю не лізе крізь паркан двору (сарай по той бік вигину кільця): такої стежки нема.
			if _path_hits_fence(pts) or _path_in_building(pts):
				continue
			var hw := PackedFloat32Array()
			hw.resize(pts.size())
			hw.fill(0.1)
			walks.append({"kind": &"yard_floor", "home": i, "door": pair[0], "pts": pts, "seed": sd + 7, "solid": 0.9, "flat": 3.0, "half": hw})

	## Найкоротша ламана від a до b (без a, з b) між будівлями й парканами двору: хвиля по сітці 0.05 і вирівнювання
	## по прямій видимості. Ворота не навпроти дверей, тож пряма лінія від дверей до хвіртки різала б хату чи паркан.
	## Порожня — шляху нема (тоді _route обходить лише хату).
	const LOS_CELLS: int = 60

	func _yard_route(a: Vector2, b: Vector2, margin: float = 0.7, free_goal: bool = true) -> PackedVector2Array:
		var step: float = 0.05
		var lo: Vector2 = a.min(b) - Vector2(margin, margin)
		var nx: int = ceili((a.max(b).x + margin - lo.x) / step) + 1
		var ny: int = ceili((a.max(b).y + margin - lo.y) / step) + 1
		var blocked := PackedByteArray()
		blocked.resize(nx * ny)
		# Сітка — лише довкола a–b: решта будівель і парканів карти її не торкається.
		var grid := Rect2(lo, Vector2(nx, ny) * step).grow(step * 2.0)
		for pl: Array in placed:
			var r: Rect2 = (pl[0] as Rect2).grow(0.03)
			if not r.intersects(grid):
				continue
			for gy in range(maxi(0, floori((r.position.y - lo.y) / step)), mini(ny, ceili((r.end.y - lo.y) / step) + 1)):
				for gx in range(maxi(0, floori((r.position.x - lo.x) / step)), mini(nx, ceili((r.end.x - lo.x) / step) + 1)):
					if r.has_point(lo + Vector2(gx, gy) * step):
						blocked[gy * nx + gx] = 1
		for sg: Array in _fence_segments():
			if not Rect2(sg[0], Vector2.ZERO).expand(sg[1]).intersects(grid, true):
				continue
			var n: int = maxi(1, ceili((sg[0] as Vector2).distance_to(sg[1]) / (step * 0.5)))
			for k in n + 1:
				var q: Vector2 = (sg[0] as Vector2).lerp(sg[1], float(k) / float(n)) - lo
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var gx: int = roundi(q.x / step) + ox
						var gy: int = roundi(q.y / step) + oy
						if gx >= 0 and gy >= 0 and gx < nx and gy < ny:
							blocked[gy * nx + gx] = 1
		# Початок і кінець стоять упритул до стіни чи паркану: довкола них вільно.
		for e: Vector2 in [a, b]:
			var rad: int = 2 if (free_goal or e == a) else 1
			for oy in range(-rad, rad + 1):
				for ox in range(-rad, rad + 1):
					var gx: int = roundi((e.x - lo.x) / step) + ox
					var gy: int = roundi((e.y - lo.y) / step) + oy
					if gx >= 0 and gy >= 0 and gx < nx and gy < ny and Vector2(ox, oy).length() <= float(rad):
						blocked[gy * nx + gx] = 0
		var from := Vector2i(roundi((a.x - lo.x) / step), roundi((a.y - lo.y) / step))
		var goal := Vector2i(roundi((b.x - lo.x) / step), roundi((b.y - lo.y) / step))
		# Найкоротша ламана по вільних клітинках (вісім сусідів, діагональ — √2): пошук іде в рушії, не в GDScript.
		var astar := AStarGrid2D.new()
		astar.region = Rect2i(0, 0, nx, ny)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
		astar.update()
		for idx in blocked.size():
			if blocked[idx] == 1:
				astar.set_point_solid(Vector2i(idx % nx, idx / nx))
		var ids: Array[Vector2i] = astar.get_id_path(from, goal)
		if ids.is_empty():
			return PackedVector2Array()
		var cells: Array[Vector2] = []
		for id: Vector2i in ids:
			cells.append(lo + Vector2(id) * step)
		# Вирівнювання: з кожної точки — до найдальшої, яку видно напряму по вільних клітинках.
		var out := PackedVector2Array()
		var i: int = 0
		while i < cells.size() - 1:
			# Пряма видимість — не далі LOS_CELLS кроків уперед: інакше вирівнювання квадратичне в довжині стежки.
			var j: int = mini(cells.size() - 1, i + LOS_CELLS)
			while j > i + 1:
				var seen := true
				var span: float = cells[i].distance_to(cells[j])
				var n_s: int = ceili(span / (step * 0.5))
				for k in range(1, n_s):
					var q: Vector2 = cells[i].lerp(cells[j], float(k) / float(n_s)) - lo
					if blocked[roundi(q.y / step) * nx + roundi(q.x / step)] == 1:
						seen = false
						break
				if seen:
					break
				j -= 1
			out.append(cells[j])
			i = j
		if out.is_empty():
			out.append(b)
		out[out.size() - 1] = b
		return out

	## Чи ламана заходить у будівлю (крім двох перших точок біля дверей).
	func _path_in_building(pts: PackedVector2Array) -> bool:
		var box: Rect2 = _pts_box(pts)
		for pl: Array in placed:
			var r: Rect2 = (pl[0] as Rect2).grow(-0.005)
			if not r.intersects(box, true):
				continue
			for k in range(2, pts.size()):
				if r.has_point(pts[k]):
					return true
		return false

	## Прямі ходи парканів: відрізки, що стикуються кінцями й лежать на одній прямій, — один хід. Кожен —
	## {segs: [[a, b], …], len, ends: кінці, не спільні з іншим відрізком ходу}.
	static func _collinear_runs(segs: Array) -> Array:
		var parent: Array[int] = []
		for k in segs.size():
			parent.append(k)
		var root := func(k: int) -> int:
			while parent[k] != k:
				k = parent[k]
			return k
		for k in segs.size():
			var dk: Vector2 = ((segs[k][1] as Vector2) - (segs[k][0] as Vector2)).normalized()
			for m in range(k + 1, segs.size()):
				var dm: Vector2 = ((segs[m][1] as Vector2) - (segs[m][0] as Vector2)).normalized()
				if absf(dk.cross(dm)) > 0.05:
					continue
				for ea: Vector2 in segs[k]:
					for eb: Vector2 in segs[m]:
						if ea.distance_to(eb) < 0.03:
							parent[root.call(k)] = root.call(m)
		var by_root: Dictionary = {}
		for k in segs.size():
			var r: int = root.call(k)
			if not by_root.has(r):
				by_root[r] = {"segs": [], "len": 0.0, "ends": []}
			by_root[r]["segs"].append(segs[k])
			by_root[r]["len"] = float(by_root[r]["len"]) + (segs[k][0] as Vector2).distance_to(segs[k][1])
		for run: Dictionary in by_root.values():
			for sg: Array in run["segs"]:
				for e: Vector2 in sg:
					var shared := false
					for o: Array in run["segs"]:
						if o != sg and ((o[0] as Vector2).distance_to(e) < 0.03 or (o[1] as Vector2).distance_to(e) < 0.03):
							shared = true
					if not shared:
						run["ends"].append(e)
		return by_root.values()

	static func _pts_box(pts: PackedVector2Array) -> Rect2:
		var box := Rect2(pts[0] if not pts.is_empty() else Vector2.ZERO, Vector2.ZERO)
		for q: Vector2 in pts:
			box = box.expand(q)
		return box

	## Секції парканів двору як відрізки по осі моделі.
	func _fence_segments() -> Array:
		var n_inst: int = layer._instances.size()
		if _fence_cache_n == n_inst:
			return _fence_cache
		# Екземпляри лише додаються: дочитуємо нові, а з нуля — тільки коли список скоротився.
		if _fence_cache_n < 0 or _fence_cache_n > n_inst:
			_fence_cache = []
			_fence_cache_n = 0
		var out: Array = _fence_cache
		for idx in range(_fence_cache_n, n_inst):
			var inst: Dictionary = layer._instances[idx]
			if int(PropLayer.spec_of(inst["model"]).get("kind", -1)) != Kind.GARDEN_FENCE:
				continue
			var xf: Transform3D = inst["transform"]
			var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
			var a3: Vector3 = xf * Vector3(box.position.x, 0.0, 0.0)
			var b3: Vector3 = xf * Vector3(box.end.x, 0.0, 0.0)
			out.append([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z)])
		_fence_cache_n = n_inst
		return out

	## Чи ламана перетинає якусь секцію паркану двору (кінці секції — по осі моделі).
	func _path_hits_fence(pts: PackedVector2Array) -> bool:
		var box: Rect2 = _pts_box(pts)
		for sg: Array in _fence_segments():
			if not Rect2(sg[0], Vector2.ZERO).expand(sg[1]).intersects(box, true):
				continue
			for k in range(1, pts.size()):
				if Geometry2D.segment_intersects_segment(pts[k - 1], pts[k], sg[0], sg[1]) != null:
					return true
		return false

	## Відстань від from уздовж dir до першої секції паркану не далі за reach; INF — нема.
	func _fence_ray(from: Vector2, dir: Vector2, reach: float) -> float:
		var best: float = INF
		for sg: Array in _fence_segments():
			var hit: Variant = Geometry2D.segment_intersects_segment(from, from + dir * reach, sg[0], sg[1])
			if hit != null:
				best = minf(best, from.distance_to(hit as Vector2))
		return best

	func _on_board(q: Vector2) -> bool:
		return q.x >= -0.3 and q.y >= -0.3 and q.x <= size.x - 0.7 and q.y <= size.y - 0.7

	## Найкоротший обхід прямокутника box (відступ 0.12): прямо, через один кут чи через два сусідні.
	func _route(a: Vector2, b: Vector2, box: Rect2, margin: float = 0.12) -> PackedVector2Array:
		var r: Rect2 = box.grow(margin)
		if not _cuts(a, b, r):
			return PackedVector2Array()
		var cs: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var best := PackedVector2Array()
		var best_len: float = INF
		var tries: Array = []
		for i in 4:
			tries.append([cs[i]])
			tries.append([cs[i], cs[(i + 1) % 4]])
			tries.append([cs[i], cs[(i + 3) % 4]])
		for t: Array in tries:
			var chain: Array[Vector2] = [a]
			chain.append_array(t)
			chain.append(b)
			var total: float = 0.0
			var ok := true
			for k in range(1, chain.size()):
				total += chain[k].distance_to(chain[k - 1])
				ok = ok and not _cuts(chain[k - 1], chain[k], r)
			if ok and total < best_len:
				best_len = total
				best = PackedVector2Array(t)
		return best

	func _cuts(a: Vector2, b: Vector2, r: Rect2) -> bool:
		var inner: Rect2 = r.grow(-0.02)
		for k in range(1, 20):
			if inner.has_point(a.lerp(b, k / 20.0)):
				return true
		return false

	## Точка на узбіччі: 0.1 клітинки поза краєм полотна, найближча до from. Стежка тут гасне, на полотно
	## не заходить: якщо from уже на полотні, її виштовхує за край. INF — доріг нема.
	func _verge_point(from: Vector2) -> Vector2:
		if not road_indexed:
			_index_roads()
		var best := Vector2.INF
		var best_d: float = INF
		var best_half: float = 0.0
		var best_n := Vector2.ZERO
		for segs: Array in road_index.values():
			for seg: Array in segs:
				var a: Vector2 = seg[0]
				var ab: Vector2 = (seg[1] as Vector2) - a
				var c: Vector2 = a + ab * clampf((from - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d: float = from.distance_to(c)
				if d < best_d - 1e-6:
					best_d = d
					best = c
					best_half = float(seg[2])
					best_n = Vector2(-ab.y, ab.x).normalized()
		if best == Vector2.INF:
			return best
		var want: float = best_half + 0.1
		var away: Vector2 = (from - best).normalized() if best_d > 1e-4 else best_n
		return best + away * want

	func _dry(q: Vector2) -> bool:
		if height != null:
			return height.at(q.x, q.y) >= TerrainHeight.WATER_LEVEL
		return kind(Vector2i(roundi(q.x), roundi(q.y))) != Terrain.Kind.WATER

	## Берег: від центру клітинки суші в бік води, поки ґрунт сухий (вода тримається ≥ 0.3 від центру);
	## INF — за 3 клітинки води не знайшлось.
	func _shore(c: Vector2i, d: Vector2i) -> Vector2:
		var last := Vector2(c)
		for k in 80:
			var q: Vector2 = Vector2(c) + Vector2(d) * (0.04 * k)
			if not _dry(q):
				return last
			last = q
		return Vector2.INF

	## Клітинка води тут дозволена: контур берега не лежить на сітці, суха земля може належати їй.
	func _walkable(q: Vector2) -> bool:
		var c := Vector2i(roundi(q.x), roundi(q.y))
		if not _on_board(q) or not _dry(q) or built.has(c) or yard_cells.has(c) \
				or [Terrain.Kind.BUILDING, Terrain.Kind.RUBBLE, Terrain.Kind.FOREST, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED].has(kind(c)):
			return false
		for r: Rect2 in _walk_blockers(c):
			if r.has_point(q):
				return false
		return true

	## Обриси, що не пускають стежку (будівлі й речі з запасом 0.2, межі полів і городи — 0.1), за клітинкою, де
	## вони можуть торкнутися точки: _walkable питають для тисяч клітинок сітки, і кожна перебирає лише обриси своєї клітинки.
	func _walk_blockers(c: Vector2i) -> Array:
		var n: int = placed.size() + layer.field_edges.size() + garden_plots.size()
		if n != _walk_idx_n:
			_walk_idx.clear()
			_walk_idx_n = n
			var rects: Array[Rect2] = []
			for p: Array in placed:
				rects.append((p[0] as Rect2).grow(0.2))
			for r: Rect2 in layer.field_edges:
				rects.append(r.grow(0.1))
			for gp: Dictionary in garden_plots:
				rects.append((gp["rect"] as Rect2).grow(0.1))
			for r: Rect2 in rects:
				for cy in range(floori(r.position.y + 0.5) - 1, ceili(r.end.y + 0.5) + 1):
					for cx in range(floori(r.position.x + 0.5) - 1, ceili(r.end.x + 0.5) + 1):
						var key := Vector2i(cx, cy)
						if not _walk_idx.has(key):
							_walk_idx[key] = []
						(_walk_idx[key] as Array).append(r)
		return _walk_idx.get(c, [])

	const _GRID: float = 0.25

	## Секції парканів (відрізки в координатах дошки) за клітинками 1×1: справжня відстань до них, а не до
	## найближчого вузла сітки пошуку.
	var _fence_segs: Dictionary = {}
	## Біля початку маршруту (хвіртка — прохід між секціями) запас від парканів не вимагаємо.
	var _free_from: Vector2 = Vector2(-99, -99)
	var _walk_cache: Dictionary = {}
	const FENCE_MARGIN: float = 0.2

	func _index_fences() -> void:
		_fence_segs.clear()
		for inst: Dictionary in layer._instances:
			var k: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
			if k != Kind.GARDEN_FENCE and k != Kind.FIELD_FENCE:
				continue
			var xf: Transform3D = inst["transform"]
			var aabb: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
			var a3: Vector3 = xf * Vector3(aabb.position.x, 0, 0)
			var b3: Vector3 = xf * Vector3(aabb.end.x, 0, 0)
			var seg: Array = [Vector2(a3.x, a3.z), Vector2(b3.x, b3.z)]
			var lo := Vector2i(floori(minf(seg[0].x, seg[1].x) - 0.5), floori(minf(seg[0].y, seg[1].y) - 0.5))
			var hi := Vector2i(ceili(maxf(seg[0].x, seg[1].x) + 0.5), ceili(maxf(seg[0].y, seg[1].y) + 0.5))
			for cy in range(lo.y, hi.y + 1):
				for cx in range(lo.x, hi.x + 1):
					var key := Vector2i(cx, cy)
					if not _fence_segs.has(key):
						_fence_segs[key] = []
					(_fence_segs[key] as Array).append(seg)

	## Найменша відстань від q до секцій парканів поруч (INF — нема).
	func fence_dist(q: Vector2) -> float:
		var best: float = INF
		var c := Vector2i(floori(q.x + 0.5), floori(q.y + 0.5))
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				for seg: Array in _fence_segs.get(c + Vector2i(ox, oy), []):
					var a: Vector2 = seg[0]
					var ab: Vector2 = (seg[1] as Vector2) - a
					best = minf(best, q.distance_to(a + ab * clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)))
		return best

	func _cell_ok(q: Vector2, shore: Vector2) -> bool:
		if q.distance_to(_free_from) > 0.7 and fence_dist(q) < FENCE_MARGIN:
			return false
		if not _walkable(q):
			return false
		if q.distance_to(shore) > 0.8:
			for o: Vector2 in [Vector2(0.12, 0), Vector2(-0.12, 0), Vector2(0, 0.12), Vector2(0, -0.12)]:
				if not _dry(q + o):
					return false
		return true

	func _line_clear(a: Vector2, b: Vector2, shore: Vector2) -> bool:
		for k in range(1, ceili(a.distance_to(b) / 0.1)):
			if not _cell_ok(a.lerp(b, k * 0.1 / a.distance_to(b)), shore):
				return false
		return true

	## Крутизна ґрунту в точці (перепад висоти на клітинку).
	func _slope(q: Vector2) -> float:
		if height == null:
			return 0.0
		return maxf(absf(height.at(q.x + 0.15, q.y) - height.at(q.x - 0.15, q.y)), absf(height.at(q.x, q.y + 0.15) - height.at(q.x, q.y - 0.15))) / 0.3

	## Шлях людини від from до берега: найкоротший зручний, з обходами рельєфу, мокрих місць, ріллі, грядок,
	## парканів і будівель (A* по сітці 0.25 клітинки), без шуму: вигини дають лише перешкоди.
	## Відстань до паркану, прохідність, суха ґрунтова окіл і вага клітинки сітки стежок (кеш на розставлення).
	func _walk_cell(id: Vector2i, q: Vector2) -> Array:
		if _walk_cache.has(id):
			return _walk_cache[id]
		var dry4 := true
		for o: Vector2 in [Vector2(0.12, 0), Vector2(-0.12, 0), Vector2(0, 0.12), Vector2(0, -0.12)]:
			dry4 = dry4 and _dry(q + o)
		var w: float = 1.0 + 12.0 * _slope(q)
		if kind(Vector2i(roundi(q.x), roundi(q.y))) == Terrain.Kind.MARSH:
			w += 3.0
		# Дорогу перетинають, але лише коли треба: перехід через неї дорожчий.
		if on_road(q, 0.0):
			w += 4.0
		var info: Array = [fence_dist(q), _walkable(q), dry4, w]
		_walk_cache[id] = info
		return info

	func _walk_route(from: Vector2, shore: Vector2) -> PackedVector2Array:
		var gw: int = ceili((size.x + 0.8) / _GRID)
		var gh: int = ceili((size.y + 0.8) / _GRID)
		var astar := AStarGrid2D.new()
		astar.region = Rect2i(0, 0, gw, gh)
		astar.cell_size = Vector2(_GRID, _GRID)
		astar.offset = Vector2(-0.4, -0.4)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
		astar.update()
		_free_from = from
		var near: float = from.distance_to(shore) + 3.0
		for gy in gh:
			for gx in gw:
				var q: Vector2 = Vector2(-0.4, -0.4) + Vector2(gx, gy) * _GRID
				# Лише навколо відрізка від початку до берега: далі пошук не ходить, а клітинки дорогі.
				if q.distance_to(from) > near or q.distance_to(shore) > near:
					astar.set_point_solid(Vector2i(gx, gy), true)
					continue
				# Властивості клітинки не залежать від початку й берега — рахуються раз на все розставлення.
				var info: Array = _walk_cell(Vector2i(gx, gy), q)
				if (q.distance_to(from) > 0.7 and float(info[0]) < FENCE_MARGIN) or not bool(info[1]) \
						or (q.distance_to(shore) > 0.8 and not bool(info[2])):
					astar.set_point_solid(Vector2i(gx, gy), true)
					continue
				var w: float = float(info[3])
				astar.set_point_weight_scale(Vector2i(gx, gy), w)
		var a := Vector2i(roundi((from.x + 0.4) / _GRID), roundi((from.y + 0.4) / _GRID))
		var b := Vector2i(roundi((shore.x + 0.4) / _GRID), roundi((shore.y + 0.4) / _GRID))
		for id: Vector2i in [a, b]:
			if astar.is_in_boundsv(id):
				astar.set_point_solid(id, false)
		if not astar.is_in_boundsv(a) or not astar.is_in_boundsv(b):
			return PackedVector2Array()
		var raw: PackedVector2Array = astar.get_point_path(a, b)
		if raw.size() < 2:
			return PackedVector2Array()
		# Кінці — точно початок і берег; решту спрямлено (найдовші відрізки лінії огляду) й згладжено.
		var ctrl := PackedVector2Array([from])
		var cur: int = 0
		var pts_in := PackedVector2Array([from])
		pts_in.append_array(raw.slice(1, raw.size() - 1))
		pts_in.append(shore)
		while cur < pts_in.size() - 1:
			var nxt: int = pts_in.size() - 1
			while nxt > cur + 1 and not _line_clear(pts_in[cur], pts_in[nxt], shore):
				nxt -= 1
			ctrl.append(pts_in[nxt])
			cur = nxt
		# Одна гладка крива: злами замінено дугами радіусом до клітинки (менші, якщо перешкода не пускає).
		for radius: float in [1.0, 0.7, 0.4, 0.0]:
			var pts: PackedVector2Array = Footpaths.resample(Footpaths.fillet(ctrl, radius))
			var ok := true
			for k in range(1, pts.size()):
				ok = ok and _cell_ok(pts[k], shore)
			if ok:
				return pts
		return PackedVector2Array()

	## До води — 1–2 стежки на карту, кожна з причиною: від хвіртки двору, найближчого до води, або від
	## дороги до пологого спуску на березі, де витоптано майданчик. Лише вигляд.
	func _water_walks() -> void:
		_index_fences()
		var landings: Array = []
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if not [Terrain.Kind.FIELD, Terrain.Kind.HILL].has(kind(c)):
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if kind(c + d) == Terrain.Kind.WATER:
						var shore: Vector2 = _shore(c, d)
						if shore != Vector2.INF and _on_board(shore):
							landings.append([shore, _slope(shore)])
		var starts: Array = []
		for i: int in gates:
			var g: Vector2 = gates[i][0] + (gates[i][1] as Vector2) * 0.15
			# Ворота в щілині між сусідніми парканами (не ширшій за двічі FENCE_MARGIN) — глухий кут для стежки:
			# повна сітка A* там нічого не знайде, а коштує десятки мілісекунд.
			var beyond: Vector2 = g + (gates[i][1] as Vector2) * 0.7
			if _walkable(beyond) and fence_dist(beyond) >= FENCE_MARGIN and not gate_blind.has(i):
				starts.append(g)
		var chosen: Array[Vector2] = []
		var used_starts: Array[Vector2] = []
		# Спершу від хвірток: хвіртка → берег з найменшою ціною (відстань і крутизна спуску).
		var pairs: Array = []
		for st: Vector2 in starts:
			for l: Array in landings:
				var dd: float = st.distance_to(l[0])
				if dd >= 2.2 and dd <= 9.0:
					pairs.append([dd + 8.0 * float(l[1]), st, l[0]])
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for pr: Array in pairs:
			if chosen.size() >= 2 or pairs.find(pr) > 60:
				break
			# Дві стежки від хвірток — з різних дворів до берегів не ближче 6 клітинок один від одного.
			if used_starts.has(pr[1]) or chosen.any(func(c: Vector2) -> bool: return c.distance_to(pr[2]) < 6.0):
				continue
			if _add_water_walk(pr[1], pr[2], chosen, 0):
				chosen.append(pr[2])
				used_starts.append(pr[1])
		# Друга — від дороги до іншого спуску, далеко від першого.
		if not road_indexed:
			_index_roads()
		var cand2: Array = []
		for l: Array in landings:
			var shore: Vector2 = l[0]
			if chosen.any(func(c: Vector2) -> bool: return c.distance_to(shore) < 6.0):
				continue
			var v: Vector2 = _verge_point(shore)
			if v == Vector2.INF:
				continue
			var dd: float = v.distance_to(shore)
			if dd >= 3.0 and dd <= 10.0:
				cand2.append([dd + 8.0 * float(l[1]), v, shore])
		cand2.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var tried := 0
		for pr: Array in cand2:
			if chosen.size() >= 2 or tried >= 12:
				break
			tried += 1
			if _add_water_walk(pr[1], pr[2], chosen, 1):
				chosen.append(pr[2])
		# Без хвірток поблизу (чи як перша не склалась) — і першу беремо від дороги.
		if chosen.is_empty():
			for pr: Array in cand2:
				if tried >= 24:
					break
				tried += 1
				if _add_water_walk(pr[1], pr[2], chosen, 1):
					chosen.append(pr[2])
					break

	func _add_water_walk(from: Vector2, shore: Vector2, chosen: Array[Vector2], serial: int) -> bool:
		var pts: PackedVector2Array = _walk_route(from, shore)
		if pts.size() < 8:
			return false
		# Спуск закінчується майданчиком діаметром ~2 м за 0.1 клітинки від води.
		var dir: Vector2 = (pts[pts.size() - 1] - pts[pts.size() - 4]).normalized()
		var centre: Vector2 = shore - dir * 0.1
		while pts.size() > 8 and pts[pts.size() - 1].distance_to(centre) < 0.12:
			pts.remove_at(pts.size() - 1)
		pts.append(centre)
		pts = Footpaths.resample(pts)
		var sd: int = h(Vector2i(roundi(shore.x), roundi(shore.y)), 210 + serial)
		walks.append({"kind": &"water", "home": -1, "door": from, "pts": pts, "seed": sd, "fade_start": 0.15,
				"half": Footpaths.widths(pts, Footpaths.HALF, [])})
		walks.append({"kind": &"landing", "home": -1, "door": centre, "pts": PackedVector2Array([centre, centre + dir * 0.03]),
				"seed": sd + 1, "solid": 0.9, "half": PackedFloat32Array([0.15, 0.15])})
		return true

	## 1–2 дрібні речі на двір із наявних моделей: колода для дров біля хати, на кожному другому дворі
	## ще й причеп. Річ стоїть на клітинках двору, на 0.12 від їхньої межі (паркану), осторонь будівель,
	## городу й стежки; не влізла — нема.
	func _dress_home(i: int, home: Dictionary, path: Array) -> void:
		var lot: Array = home["cells"]
		var items: Array[StringName] = [&"tree_stump_01"]
		var trailers: Array[StringName] = PropLayer.models_of(Kind.TRAILER)
		if h(home["house"], 160) % 2 == 0 and not trailers.is_empty():
			items.append(_pick_apart(trailers, home["house"], &"trailer", h(home["house"], 161) % trailers.size()))
		var gr: Array[Rect2] = []
		for gp: Dictionary in garden_plots:
			if int(gp["home"]) == i:
				gr.append(gp["rect"])
		for m in items:
			if PropLayer.model(m) == null:
				continue
			var aabb: AABB = (PropLayer.model(m) as Dictionary)["aabb"]
			var sc: float = float(PropLayer.spec_of(m).get("scale", 1.0))
			var spots: Array[Vector2] = []
			for c: Vector2i in lot:
				for oy in range(-3, 4):
					for ox in range(-3, 4):
						spots.append(Vector2(c) + Vector2(ox, oy) * 0.1)
			var start: int = h(home["house"], 162 + items.find(m)) % spots.size()
			for k in spots.size():
				var q: Vector2 = spots[(start + k) % spots.size()]
				var yaw: float = float(h(Vector2i(q * 10.0), 163) % 628) / 100.0
				var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(q.x, ground(q.x, q.y), q.y))
				var box: AABB = xf * aabb
				var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
				if _yard_spot_ok(r, lot, path, gr):
					var cells: Array[Vector2i] = [Vector2i(roundi(q.x), roundi(q.y))]
					layer._add(m, xf, cells, true)
					placed_small.append(r)
					if int(PropLayer.spec_of(m)["kind"]) == Kind.TRAILER:
						_note_form(i, home["house"], &"trailer", m)
					break

	func _yard_spot_ok(r: Rect2, lot: Array, path: Array, gardens_of: Array[Rect2]) -> bool:
		if not clear_of_units(r) or near_wet(r.get_center(), WATER_CLEAR):
			return false
		for v: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			for o: Vector2 in [Vector2(0.12, 0), Vector2(-0.12, 0), Vector2(0, 0.12), Vector2(0, -0.12)]:
				if not lot.has(Vector2i(roundi(v.x + o.x), roundi(v.y + o.y))):
					return false
		for p: Array in placed:
			if (p[0] as Rect2).grow(0.1).intersects(r):
				return false
		for g in gardens_of + placed_small:
			if g.grow(0.05).intersects(r):
				return false
		if not path.is_empty():
			var a: Vector2 = path[0]
			var b: Vector2 = path[1]
			var cpt: Vector2 = Geometry2D.get_closest_point_to_segment(r.get_center(), a, b)
			if r.grow(PATH_WIDTH * 0.6).has_point(cpt):
				return false
		return true

	## Город r, обрізаний до внутрішнього боку сторін кільця (−0.1) і на 0.1 від будівель: з чотирьох
	## можливих зрізів від будівлі лишаємо той, що зберігає найбільшу площу.
	func _clip_garden(r: Rect2, sides: Array) -> Rect2:
		for sd: Dictionary in sides:
			var d: Vector2i = sd["d"]
			var b: float = float(sd["line"]) + float(d.x + d.y) * float(sd["o"])
			var margin: float = PropLayer.OPEN_SIDE_CLEAR if sd.get("open", false) else 0.1
			var lo: float = INF
			var hi: float = -INF
			for e: Array in sd["edges"]:
				var g: Vector2i = e[0]
				var along: float = float(g.y) if d.x != 0 else float(g.x)
				lo = minf(lo, along - 0.5)
				hi = maxf(hi, along + 0.5)
			var ax: int = 0 if d.x != 0 else 1
			var cross: int = 1 - ax
			if r.end[cross] <= lo or r.position[cross] >= hi:
				continue
			var end: Vector2 = r.end
			if d.x + d.y > 0:
				end[ax] = minf(end[ax], b - margin)
				r.end = end
			else:
				var pos: Vector2 = r.position
				var shift: float = maxf(pos[ax], b + margin) - pos[ax]
				pos[ax] += shift
				r.position = pos
				var sz: Vector2 = r.size
				sz[ax] -= shift
				r.size = sz
		for p: Array in placed:
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				return Rect2()
			var o: Rect2 = (p[0] as Rect2).grow(0.1)
			if not o.intersects(r):
				continue
			var cuts: Array[Rect2] = [
				Rect2(r.position, Vector2(o.position.x - r.position.x, r.size.y)),
				Rect2(Vector2(o.end.x, r.position.y), Vector2(r.end.x - o.end.x, r.size.y)),
				Rect2(r.position, Vector2(r.size.x, o.position.y - r.position.y)),
				Rect2(Vector2(r.position.x, o.end.y), Vector2(r.size.x, r.end.y - o.end.y))]
			var best := Rect2()
			for c in cuts:
				if c.size.x > 0.0 and c.size.y > 0.0 and c.get_area() > best.get_area():
					best = c
			r = best
		return r

	## Хата садиби: одна з чотирьох форм на клітинку — щипцева (h5), чотирисхила (h7), дерев'яна з ґанком (h8)
	## і двоповерхова (h6); почату форму дає хеш клітинки. Садиба не повторює форму жодної хати ближче
	## HOUSE_APART клітинок, поки є вільна форма; коли поруч уже всі чотири, повтор дозволено. Три форми
	## на село тримає розклад нинішніх карт, а не алгоритм: ланцюжок A–B–C з A і C далі HOUSE_APART
	## може вийти з двома формами.
	func _house_model(hc: Vector2i, i: int) -> StringName:
		var start: int = h(hc, 150) % HOUSE_FORMS.size()
		var pick: StringName = &""
		for pass_ in 3:
			for k in HOUSE_FORMS.size():
				var m: StringName = HOUSE_FORMS[(start + k) % HOUSE_FORMS.size()]
				if PropLayer.model(m) == null or not _no_twin(m, hc, Vector2i.ONE):
					continue
				if (pass_ == 0 and _ruin_twin_near(m, hc)) or (pass_ < 2 and _house_near(m, hc)):
					continue
				pick = m
				break
			if pick != &"":
				break
		if pick == &"":
			pick = &"house_h5"
		farm_houses.append([hc, pick])
		return pick

	## Форма з forms для садиби з хатою hc: починаючи з номера start, перша, що не стоїть у садибі ближче
	## HOUSE_APART клітинок (Чебишов); коли поруч є вже всі — та, чия найближча така сама найдалі.
	func _pick_apart(forms_of: Array[StringName], hc: Vector2i, key: StringName, start: int) -> StringName:
		var best: StringName = &""
		var best_gap: int = -1
		for k in forms_of.size():
			var m: StringName = forms_of[(start + k) % forms_of.size()]
			var gap: int = 1 << 20
			for t: Array in _taken.get(key, []):
				if t[1] == m:
					var d: Vector2i = (t[0] as Vector2i) - hc
					gap = mini(gap, maxi(absi(d.x), absi(d.y)))
			if gap > HOUSE_APART:
				return m
			if gap > best_gap:
				best_gap = gap
				best = m
		return best

	## Садиба i справді взяла форму m виду key: далі її бачать сусіди.
	func _note_form(i: int, hc: Vector2i, key: StringName, m: StringName) -> void:
		if not forms.has(i):
			forms[i] = {}
		(forms[i] as Dictionary)[key] = m
		if not _taken.has(key):
			_taken[key] = []
		(_taken[key] as Array).append([hc, m])

	## Та сама руїна ближче RUIN_APART клітинок: однакові руїни поруч читаються копіями.
	func _ruin_near(m: StringName, c: Vector2i, reach: int = RUIN_APART) -> bool:
		for fr: Array in farm_ruins:
			var d: Vector2i = (fr[0] as Vector2i) - c
			if fr[1] == m and maxi(absi(d.x), absi(d.y)) <= reach:
				return true
		return false

	## Руїна з повним слідом (ruin_half_*) або далі клітинки від садиб макета: низька не замикає двір, і город лишається біля розриву паркану.
	func _closes_yard(m: StringName, c: Vector2i) -> bool:
		if String(m).begins_with("ruin_half_"):
			return true
		for home: Dictionary in layout.get("homes", []):
			for hc: Vector2i in home["cells"]:
				if maxi(absi(hc.x - c.x), absi(hc.y - c.y)) <= 1:
					return false
		return true

	## Руїна на тій самій клітинці й з тим самим поворотом, що й вибрана, але не повторює сусідню й не двійник хати макета;
	## з таких — найближча за площею обрису до вибраної, щоб розкладка садиб (паркан, ворота, город) лишалась на місці.
	## Нема на що міняти — лишається вибрана.
	func _ruin_swap(pick: Array, options: Array) -> Array:
		if not _ruin_near(pick[0], pick[1]):
			return pick
		var area := func(m: StringName) -> float:
			var sz: Vector3 = ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size
			return sz.x * sz.z
		var want: float = area.call(pick[0])
		var best: Array = pick
		# Спершу такі, що не повторюють руїну й далі (RUIN_FAR), потім хоч не ближче RUIN_APART.
		for reach: int in [RUIN_FAR, RUIN_APART]:
			var best_d: float = INF
			for o: Array in options:
				if o[1] != pick[1] or o[2] != pick[2] or _ruin_near(o[0], o[1], reach) or not _closes_yard(o[0], o[1]):
					continue
				var d: float = absf(float(area.call(o[0])) - want)
				if d < best_d and d <= want * RUIN_SWAP_AREA:
					best_d = d
					best = o
			if best_d < INF:
				return best
		return best

	## Руїна цієї ж хати поруч (RUIN_TWIN): ціла хата й її розбитий двійник на сусідніх ділянках — той самий силует двічі.
	func _ruin_twin_near(house: StringName, hc: Vector2i) -> bool:
		for fr: Array in farm_ruins:
			var d: Vector2i = (fr[0] as Vector2i) - hc
			if PropLayer.RUIN_TWIN.get(fr[1], &"") == house and maxi(absi(d.x), absi(d.y)) <= RUIN_TWIN_NEAR:
				return true
		return false

	func _house_near(m: StringName, hc: Vector2i) -> bool:
		for fh: Array in farm_houses:
			var d: Vector2i = (fh[0] as Vector2i) - hc
			if fh[1] == m and maxi(absi(d.x), absi(d.y)) <= HOUSE_APART:
				return true
		return false

	## Паркан садиби — одне замкнене кільце по межі двору з одними воротами GATE до дороги. Межа двору
	## обходиться як многокутник; кожна сторона стає на YARD_OUT назовні, а якщо там дорога, вода чи
	## будівля ближче 0.3 клітинки — зсувається всередину двору, але не зникає. Кути — перетини
	## сусідніх сторін, тож завжди зімкнуті; будівлю на межі паркан обходить до самої стіни. Межу з
	## сусідньою садибою ставить одна з них, рівно по межі. Повертає сторони з їхніми відступами.
	func _fence_ring(i: int, home: Dictionary, owner_of: Dictionary, sheds: Array[Rect2]) -> Array:
		var lot: Dictionary = {}
		for c: Vector2i in home["cells"]:
			lot[c] = true
		var hc: Vector2i = home["house"]
		_ring_i = i
		_owner_of = owner_of
		# Стіни — обриси моделей зі звісом даху, ті самі, що бачить глядач (а не поля розстановки в placed).
		_wall_rects.clear()
		_wall_tops.clear()
		_wall_chims.clear()
		for inst: Dictionary in layer._instances:
			var kd: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
			if kd == Kind.STRUCTURE or kd == Kind.RUIN:
				var bx: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
				_wall_rects.append(Rect2(bx.position.x, bx.position.z, bx.size.x, bx.size.z))
				_wall_tops.append(bx.size.y)
				var chims: Array[Vector3] = []
				var xf: Transform3D = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary).get("local", Transform3D()) as Transform3D)
				for ch: Vector3 in (PropLayer.model(inst["model"]) as Dictionary).get("chimneys", []):
					var w: Vector3 = xf * ch
					chims.append(Vector3(w.x, w.z, w.y - bx.position.y))
				_wall_chims.append(chims)
		_pieces.clear()
		_collecting = true
		var palette: Array[StringName] = PropLayer.FENCE_FORMS.filter(func(f: StringName) -> bool:
			return PropLayer.model(StringName(String(f).get_slice("|", 0))) != null)
		if palette.is_empty():
			return []
		var base: int = absi(hash(Vector2i(salt, Kind.GARDEN_FENCE))) + half(hc)
		var form: StringName = _pick_apart(palette, hc, &"fence", (base + h(hc, 121)) % palette.size())
		var m := StringName(String(form).get_slice("|", 0))
		_ring_hmul = float(String(form).get_slice("|", 1))
		var sides: Array[Dictionary] = _lot_sides(lot, owner_of)
		if sides.is_empty():
			_collecting = false
			return []
		# Ворота: на стороні, що містить ребро фасаду хати; інакше — на стороні до дороги.
		var gate_side: int = -1
		for k in sides.size():
			for e: Array in sides[k]["edges"]:
				if e[0] == hc and e[1] == home["face"] and int(sides[k]["nb"]) < 0:
					gate_side = k
		# Ворота дивляться на дорогу: фасад, що дивиться повз неї (дорога збоку чи за рогом), поступається
		# стороні, яка до дороги ближча.
		if gate_side >= 0 and _road_ahead(sides[gate_side]) > GATE_SIGHT:
			var best_gap: float = GATE_SIGHT
			for k in sides.size():
				var gap: float = _road_ahead(sides[k]) if int(sides[k]["nb"]) < 0 else INF
				if gap < best_gap:
					best_gap = gap
					gate_side = k
		if gate_side < 0:
			for k in sides.size():
				if int(sides[k]["nb"]) < 0 and kind((sides[k]["edges"][0] as Array)[0] + sides[k]["d"]) == Terrain.Kind.ROAD:
					gate_side = k
					break
		# Відступ кожної сторони: найдальший назовні, де сторона найменше перекрита дорогою, водою чи
		# будівлями; що лишилось перекритим — _fence_run обходить. Межа з сусідом — рівно по межі.
		for k in sides.size():
			var sd: Dictionary = sides[k]
			sd["o"] = 0.0
			sd["oi"] = RING_OFFSETS.size()
			if int(sd["nb"]) >= 0:
				continue
			var best: float = INF
			for oi in RING_OFFSETS.size():
				var blocked: float = _ring_side_blocked(sd, RING_OFFSETS[oi], sheds)
				if blocked < best - 1e-3:
					best = blocked
					sd["o"] = RING_OFFSETS[oi]
					sd["oi"] = oi
				if blocked == 0.0:
					break
		var n: int = sides.size()
		# Дорога чи вода на справжньому відрізку від кута до кута (кут бере відступ сусіда, тож сторона
		# виходить за свої клітинки): сторону, на якій перешкода, — або сусіда, якщо перешкода біля його
		# кута, — на крок углиб, доки кільце не стане вільним.
		for guard in 4 * n:
			var moved := false
			for k in n:
				var sd: Dictionary = sides[k]
				var p0: Vector2 = _ring_corner(sides[(k - 1 + n) % n], sd)
				var p1: Vector2 = _ring_corner(sd, sides[(k + 1) % n])
				var total: float = p0.distance_to(p1)
				var steps: int = maxi(1, ceili(total / 0.05))
				for j in steps + 1:
					var q: Vector2 = p0.lerp(p1, float(j) / float(steps))
					if not _fence_hard(q):
						continue
					var d0: float = q.distance_to(p0)
					var who: int = k
					if d0 < 0.45:
						who = (k - 1 + n) % n
					elif total - d0 < 0.45:
						who = (k + 1) % n
					if not _ring_deeper(sides[who]) and who != k:
						who = k if _ring_deeper(sides[k]) else -1
					if who >= 0 and _ring_deeper(sides[who]):
						sides[who]["oi"] = int(sides[who]["oi"]) + 1
						sides[who]["o"] = RING_OFFSETS[int(sides[who]["oi"])]
						moved = true
					break
			if not moved:
				break
		var starts: Array[Vector2] = []
		var ends: Array[Vector2] = []
		for k in n:
			starts.append(_ring_corner(sides[(k - 1 + n) % n], sides[k]))
			ends.append(_ring_corner(sides[k], sides[(k + 1) % n]))
		# Кут, що й на найглибшому відступі лишився біля води (зона довкола мокрої клітинки — квадрат),
		# обходимо сходинкою всередину: від кута назад по обох сторонах до першої вільної точки і через
		# внутрішній кут між ними.
		for k in n:
			var k1: int = (k + 1) % n
			if int(sides[k]["nb"]) >= 0 or int(sides[k1]["nb"]) >= 0 or not _fence_hard(ends[k]):
				continue
			var c: Vector2 = ends[k]
			var a: Vector2 = _first_free(c, starts[k])
			var b: Vector2 = _first_free(c, ends[k1])
			var notch: Vector2 = a + b - c
			if a == c or b == c or _fence_hard(notch):
				continue
			ends[k] = a
			starts[k1] = b
			_fence_run(m, a, notch, lot, sheds)
			_fence_run(m, notch, b, lot, sheds)
		# Вільні ділянки кожної сторони, яку ставить ця садиба.
		var runs: Array = []
		for k in n:
			var sd: Dictionary = sides[k]
			if int(sd["nb"]) >= 0 and int(sd["nb"]) < i:
				continue
			for sp: Array in _free_spans(starts[k], ends[k], sheds):
				runs.append([sp[0], sp[1], k])
		# Ворота — на вільній ділянці (не там, де фасад хати сам стоїть на межі), найближче навпроти хати:
		# спершу на боці фасаду, інакше на будь-якій зовнішній стороні. З обох боків — щонайменше
		# GATE_POST паркану, бо ворота впритул до кута чи стіни лишили б один стовп без пари.
		var gate_run: int = -1
		var gate_at: float = 0.0
		var best_score := Vector3(INF, INF, INF)
		var gate_tier := Vector2i.ZERO
		# Порядок переваг: суворий прохід — уздовж стіни отвір не ближче GATE_ALONG (x) і на екрані ворота далі
		# GATE_SCREEN_GAP від силуетів будівель (y), бо інакше читаються прибудовою до хати; далі паркан обабіч
		# завдовжки MIN_FENCE (коротший лишає стовп без пари, і сторона читається уламком); далі запас від стін за
		# GATE_CLEARS. Двір, де суворого місця нема, бере місце, найдальше на екрані від силуетів, а коли нема й такого
		# уздовж стін — і ближче до стіни: двір без воріт гірший.
		for flank: float in [GATE_FLANK, GATE_POST]:
			for tier: Vector2i in [Vector2i(1, SCREEN_STRICT), Vector2i(1, SCREEN_WIDEST), Vector2i(0, SCREEN_WIDEST)]:
				for clear: float in GATE_CLEARS:
					if gate_run >= 0:
						break
					for j in runs.size():
						var k: int = runs[j][2]
						if int(sides[k]["nb"]) >= 0:
							continue
						var a: Vector2 = runs[j][0]
						var b: Vector2 = runs[j][1]
						var total: float = a.distance_to(b)
						# На кінці, де кільце повертає за кут, паркан за стовпом триває далі боковою стороною, тож
						# ворота можуть стати майже до кута (на GATE_POST); біля стіни чи розриву за стовпом потрібен повний flank.
						var flank_a: float = minf(flank, GATE_POST) if _ring_continues(runs, j, a) else flank
						var flank_b: float = minf(flank, GATE_POST) if _ring_continues(runs, j, b) else flank
						if total < GATE + flank_a + flank_b:
							continue
						var dir: Vector2 = (b - a) / total
						var found: Vector2 = _gate_at(a, b, sheds, (Vector2(hc) - a).dot(dir), clear, flank_a, GATE_ALONG * tier.x, tier.y, flank_b)
						var at: float = found.x
						if at < 0.0:
							continue
						# Спершу отвір, що дивиться на дорогу (з запасом на зсув хвіртки), потім на боці фасаду, потім найближчий до хати.
						var facing: bool = road_ahead_of(a + dir * at, Vector2(sides[k]["d"] as Vector2i)) <= GATE_SIGHT - 0.3
						var pref: float = (0.0 if k == gate_side else 1.0) if tier.y == SCREEN_STRICT else -found.y
						var score := Vector3(0.0 if facing else 1.0, pref, (a + dir * at).distance_to(Vector2(hc)))
						if score.x < best_score.x or (score.x == best_score.x and (score.y < best_score.y or (score.y == best_score.y and score.z < best_score.z))):
							best_score = score
							gate_run = j
							gate_at = at
					# Менший запас — лише коли з більшим воріт нема ніде: легше ворота біля стіни, ніж двір без воріт.
					if gate_run >= 0:
						gate_clear[i] = clear
						gate_tier = tier
						break
		# Двір, де жоден вільний відрізок не дивиться на дорогу, — явно «сліпий»: ворота на найближчому відрізку.
		if gate_run >= 0 and best_score.x > 0.0:
			gate_blind[i] = true
		for j in runs.size():
			var a: Vector2 = runs[j][0]
			var b: Vector2 = runs[j][1]
			if j == gate_run:
				var dir: Vector2 = (b - a).normalized()
				var proj: float = (Vector2(hc) - a).dot(dir)
				var at: float = gate_at
				var p0: Vector2 = a + dir * (at - GATE * 0.5)
				var p1: Vector2 = a + dir * (at + GATE * 0.5)
				_fence_straight(m, a, p0, lot)
				_fence_straight(m, p1, b, lot)
				var out: Vector2 = Vector2(sides[int(runs[j][2])]["d"])
				# Хвіртка — з того краю отвору, що ближче до хати: стежка від дверей не обходить полотно.
				var wicket_far: bool = proj > at or (proj == at and h(hc, 170) % 2 == 0)
				var from: Vector2 = p0 if wicket_far else p1
				var to: Vector2 = p1 if wicket_far else p0
				var leaf_mid: Vector2 = from + (to - from).normalized() * (GATE_LEAF + GATE_POST_SIZE.x)
				# Ворота — того самого роду, що й паркан двору; модель без своєї форми воріт бере вільну від сусідів.
				var kind_id: StringName = StringName(PropLayer.spec_of(m).get("gate",
						_pick_apart(PropLayer.GATE_KINDS, hc, &"gate", h(hc, 172) % PropLayer.GATE_KINDS.size())))
				_note_form(i, hc, &"gate", kind_id)
				gates[i] = [(leaf_mid + to) * 0.5, out]
				gate_segments.append([from, to])
				layer._gates.append({"a": from, "mid": leaf_mid, "b": to, "kind": kind_id, "out": out,
						"height": GATE_H, "seed": h(hc, 173), "clear": float(gate_clear.get(i, 0.0)),
						"along": gate_tier.x > 0, "screen": gate_tier.y == SCREEN_STRICT})
			else:
				_fence_straight(m, a, b, lot)
		# Сторона з розривом (ні секція чи ворота, ні стіна її не замикають) — _clip_garden тримає город подалі від неї.
		for k in n:
			if int(sides[k]["nb"]) >= 0:
				continue
			var open_len: float = 0.0
			var side_len: float = (starts[k] as Vector2).distance_to(ends[k] as Vector2)
			for step in ceili(side_len / 0.05) + 1:
				var q: Vector2 = (starts[k] as Vector2).lerp(ends[k] as Vector2, minf(1.0, float(step) * 0.05 / maxf(side_len, 1e-6)))
				var shut := false
				for r: Array in runs:
					shut = shut or (r[2] == k and Geometry2D.get_closest_point_to_segment(q, r[0], r[1]).distance_to(q) < 0.06)
				if gate_run >= 0 and gates.has(i):
					var gs: Array = gate_segments.back()
					shut = shut or Geometry2D.get_closest_point_to_segment(q, gs[0], gs[1]).distance_to(q) < 0.06
				for r: Rect2 in _wall_rects:
					shut = shut or r.grow(0.15).has_point(q)
				for r: Rect2 in sheds:
					shut = shut or r.grow(0.15).has_point(q)
				if not shut:
					open_len += 0.05
			sides[k]["open"] = open_len > 0.1
		_collecting = false
		var posts: Array[Vector2] = []
		for g: Dictionary in layer._gates.slice(layer._gates.size() - (1 if gates.has(i) else 0)):
			posts.append_array([g["a"], g["mid"], g["b"]])
		for pc: Array in _finish_pieces(_pieces, posts):
			_fence_straight(m, pc[0], pc[1], lot)
		_note_form(i, hc, &"fence", form)
		return sides

	## Кінець e вільної ділянки j — кут кільця, де вона переходить в іншу ділянку (кінці збігаються).
	func _ring_continues(runs: Array, j: int, e: Vector2) -> bool:
		for o in runs.size():
			if o != j and (runs[o][0] as Vector2).distance_to(e) < 0.03 or o != j and (runs[o][1] as Vector2).distance_to(e) < 0.03:
				return true
		return false

	## Центр отвору воріт на відрізку a→b (відстань від a), найближчий до want, де увесь отвір (з півтовщиною
	## стовпів) далі clear від будівель, далі clear + 0.1 від сараїв (ворота проти комори читались дверима гаража)
	## і далі WATER_CLEAR від води; -1 — такого місця нема. Уздовж стіни отвір далі side від неї. screen: SCREEN_STRICT —
	## верх полотна на екрані далі GATE_SCREEN_GAP від силуетів будівель (_hull_gap); SCREEN_WIDEST — місце, найдальше
	## від них, хоч і ближче. flank — запас паркану від початку відрізка, flank_b — від кінця (−1: той самий). Повертає (центр отвору, відстань на екрані до силуетів; INF — силуетів поруч нема).
	func _gate_at(a: Vector2, b: Vector2, sheds: Array[Rect2], want: float, clear: float, flank: float, side: float = 0.0,
			screen: int = SCREEN_OFF, flank_b: float = -1.0) -> Vector2:
		var total: float = a.distance_to(b)
		var dir: Vector2 = (b - a) / total
		var lo: float = flank + GATE * 0.5
		var hi: float = (flank if flank_b < 0.0 else flank_b) + GATE * 0.5
		var half: float = GATE * 0.5 + GATE_POST_SIZE.x
		# Обриси, що взагалі можуть зачепити відрізок (з запасом): решта вибірок їх не перебирає.
		var near: Array[Rect2] = []
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(clear + 0.1 + 0.02)
		var walls: Array[Rect2] = []
		# Силуети будівель на екрані — лише коли правило екрана діє.
		var hulls: Array = []
		for w in _wall_rects.size():
			var r: Rect2 = _wall_rects[w]
			if r.intersects(box):
				near.append(r.grow(clear))
			if r.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(side + 0.1)):
				walls.append(r)
			if screen != SCREEN_OFF and r.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(_wall_tops[w] * 2.0 + 0.5)):
				var pts := PackedVector2Array()
				for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
					for y: float in [0.0, _wall_tops[w]]:
						pts.append(_screen_pt(c, y))
				for ch: Vector3 in _wall_chims[w]:
					pts.append(_screen_pt(Vector2(ch.x, ch.y), ch.z))
				hulls.append(Geometry2D.convex_hull(pts))
		var ax: int = 0 if absf(dir.x) > absf(dir.y) else 1
		for r: Rect2 in sheds:
			if r.intersects(box):
				near.append(r.grow(clear + 0.1))
		var best: float = -1.0
		var best_gap: float = INF
		# Без силуетів поруч відстань на екрані скрізь INF: вибір — найближче до want, як без правила екрана.
		var widest: bool = screen == SCREEN_WIDEST and not hulls.is_empty()
		if widest:
			best_gap = -1.0
		var t: float = lo
		while t <= total - hi + 1e-6:
			if not widest and best >= 0.0 and absf(t - want) >= absf(best - want):
				t += 0.04
				continue
			var ok := true
			for u: float in [-half, -half * 0.5, 0.0, half * 0.5, half]:
				var q: Vector2 = a + dir * (t + u)
				for r: Rect2 in near:
					if r.has_point(q):
						ok = false
						break
				if not ok:
					break
			if ok:
				var p0: Vector2 = a + dir * (t - half)
				var p1: Vector2 = a + dir * (t + half)
				for r: Rect2 in walls:
					if minf(p0[ax], p1[ax]) < r.end[ax] and maxf(p0[ax], p1[ax]) > r.position[ax] \
							and maxf(r.position[1 - ax] - p0[1 - ax], p0[1 - ax] - r.end[1 - ax]) < side:
						ok = false
						break
			var gap: float = INF
			if ok and not hulls.is_empty():
				for u in 11:
					gap = minf(gap, _hull_gap(a + dir * (t - GATE * 0.5 + GATE * u / 10.0), GATE_H, hulls))
				ok = screen == SCREEN_WIDEST or gap >= GATE_SCREEN_GAP
			if ok:
				for u: float in [-half, 0.0, half]:
					if near_wet(a + dir * (t + u), WATER_CLEAR):
						ok = false
						break
			# SCREEN_WIDEST: найдальше на екрані від силуетів; за рівного — найближче до want.
			if ok and (not widest or gap > best_gap + 1e-4 or (absf(gap - best_gap) <= 1e-4 and absf(t - want) < absf(best - want))):
				best = t
				best_gap = gap
			t += 0.04
		return Vector2(best, best_gap if best >= 0.0 else INF)

	## Точка всередині клітинки чужого двору, не на межі: межу двох дворів ставить один з них.
	func _in_other_lot(q: Vector2) -> bool:
		var c := Vector2i(roundi(q.x), roundi(q.y))
		var o: int = int(_owner_of.get(c, -1))
		return o >= 0 and o != _ring_i and absf(q.x - c.x) < 0.5 - 0.01 and absf(q.y - c.y) < 0.5 - 0.01

	## Скільки клітинок від середини сторони назовні до покриття дороги; INF — не далі за GATE_SIGHT.
	func _road_ahead(side: Dictionary) -> float:
		var mid := Vector2.ZERO
		var d := Vector2(side["d"] as Vector2i)
		for e: Array in side["edges"]:
			mid += Vector2(e[0] as Vector2i) + d * 0.5
		mid /= float((side["edges"] as Array).size())
		return road_ahead_of(mid, d)

	## Те саме від довільної точки: крок 0.05, щоб не проскочити вузьке покриття.
	func road_ahead_of(from: Vector2, dir: Vector2) -> float:
		for k in range(0, int(GATE_SIGHT / 0.05) + 1):
			if on_road(from + dir * (0.05 * k), 0.0):
				return 0.05 * k
		return INF

	## Сторони межі двору як замкнений обхід: кожна — {d: нормаль назовні, nb: садиба по той бік чи −1,
	## edges: [[клітинка, d], …], line: координата межі (x для вертикальної, y для горизонтальної)}.
	func _lot_sides(lot: Dictionary, owner_of: Dictionary) -> Array[Dictionary]:
		var by_start: Dictionary = {}
		var cells: Array = lot.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for g: Vector2i in cells:
			for d in Board.DIRS_4:
				if lot.has(g + d):
					continue
				var c := Vector2(g)
				var a: Vector2
				var b: Vector2
				if d == Vector2i(0, -1):
					a = c + Vector2(0.5, -0.5)
					b = c + Vector2(-0.5, -0.5)
				elif d == Vector2i(-1, 0):
					a = c + Vector2(-0.5, -0.5)
					b = c + Vector2(-0.5, 0.5)
				elif d == Vector2i(0, 1):
					a = c + Vector2(-0.5, 0.5)
					b = c + Vector2(0.5, 0.5)
				else:
					a = c + Vector2(0.5, 0.5)
					b = c + Vector2(0.5, -0.5)
				by_start[Vector2i(roundi(a.x * 2.0), roundi(a.y * 2.0))] = {"g": g, "d": d, "a": a, "b": b,
						"nb": int(owner_of.get(g + d, -1))}
		if by_start.is_empty():
			return []
		# Обхід від найменшого початку; кожне ребро веде до наступного, що починається в його кінці.
		var keys: Array = by_start.keys()
		keys.sort()
		var chain: Array[Dictionary] = []
		var cur: Dictionary = by_start[keys[0]]
		for guard in by_start.size():
			chain.append(cur)
			var nk := Vector2i(roundi(cur["b"].x * 2.0), roundi(cur["b"].y * 2.0))
			if not by_start.has(nk) or by_start[nk] == chain[0]:
				break
			cur = by_start[nk]
		# Зливаємо підряд ребра з тією самою нормаллю й тим самим сусідом у сторону.
		var sides: Array[Dictionary] = []
		for e in chain:
			if not sides.is_empty() and sides.back()["d"] == e["d"] and sides.back()["nb"] == e["nb"]:
				(sides.back()["edges"] as Array).append([e["g"], e["d"]])
				continue
			var line: float = e["a"].y if (e["d"] as Vector2i).y != 0 else e["a"].x
			sides.append({"d": e["d"], "nb": e["nb"], "edges": [[e["g"], e["d"]]], "line": line,
					"from": e["a"], "o": 0.0})
		# Перша й остання сторони можуть бути однією, розірваною початком обходу.
		if sides.size() > 1 and sides[0]["d"] == sides.back()["d"] and sides[0]["nb"] == sides.back()["nb"]:
			(sides[0]["edges"] as Array).append_array(sides.back()["edges"])
			sides[0]["from"] = sides.back()["from"]
			sides.pop_back()
		return sides

	## Кут між двома послідовними сторонами: x — з вертикальної, y — з горизонтальної (зі зсувами).
	func _ring_corner(s0: Dictionary, s1: Dictionary) -> Vector2:
		var v: Dictionary = s0 if (s0["d"] as Vector2i).x != 0 else s1
		var hz: Dictionary = s1 if v == s0 else s0
		var x: float = float(v["line"]) + float((v["d"] as Vector2i).x) * float(v["o"])
		var y: float = float(hz["line"]) + float((hz["d"] as Vector2i).y) * float(hz["o"])
		return Vector2(x, y)

	## Частка сторони на відступі o, що лягла б на дорогу, воду чи ближче 0.3 до будівлі або сараю.
	## Назовні на болото чи уламки сторона не виходить зовсім (частка 1).
	func _ring_side_blocked(sd: Dictionary, o: float, sheds: Array[Rect2]) -> float:
		var d: Vector2i = sd["d"]
		var hit: int = 0
		var n: int = 0
		for e: Array in sd["edges"]:
			var g: Vector2i = e[0]
			if o > 0.0 and kind(g + d) not in [Terrain.Kind.FIELD, Terrain.Kind.ROAD, Terrain.Kind.HILL, Terrain.Kind.BUILDING]:
				return 1.0
			var mid: Vector2 = Vector2(g) + Vector2(d) * (0.5 + o)
			var t := Vector2(absf(d.y), absf(d.x))
			for k in 9:
				n += 1
				if _fence_blocked(mid + t * (float(k) / 8.0 - 0.5), sheds, 0.32, t):
					hit += 1
		return float(hit) / float(maxi(n, 1))

	## Сторону кільця ще можна відсунути глибше в двір (межа з сусідом не рухається).
	func _ring_deeper(sd: Dictionary) -> bool:
		return int(sd["nb"]) < 0 and int(sd["oi"]) + 1 < RING_OFFSETS.size()

	## Точка паркану на дорозі чи над водою — там паркану бути не може взагалі (будівлю він обходить).
	func _fence_hard(q: Vector2) -> bool:
		# Ще й за полем дороги, яке малює шейдер: на заокругленнях розвилок асфальт ширший за осі з півшириною.
		if on_road(q, ROAD_PAD + 0.02) or road_edge_m(q) < FENCE_ROAD_INSET * 8.0 or _in_other_lot(q):
			return true
		# Вода й болото — квадратом довкола клітинки, не колом: паркан не підходить і до кута берега.
		# +0.08: на крутому березі секція нахилена схилом і верхом виходить за свій кінець.
		var c := Vector2i(roundi(q.x), roundi(q.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if kind(n) in [Terrain.Kind.WATER, Terrain.Kind.MARSH] \
						and absf(q.x - n.x) < 0.5 + WATER_CLEAR + 0.08 and absf(q.y - n.y) < 0.5 + WATER_CLEAR + 0.08:
					return true
		return false

	## Точка паркану заборонена: дорога, вода, ближче clear до обрису будівлі чи сараю (зі звісом
	## даху); +0.02 — товщина секції.
	func _fence_blocked(q: Vector2, sheds: Array[Rect2], clear: float, dir: Vector2 = Vector2.ZERO) -> bool:
		if _fence_hard(q) or (dir != Vector2.ZERO and _hugs_wall(q, dir)):
			return true
		for p: Array in placed:
			if (p[0] as Rect2).grow(clear).has_point(q):
				return true
		for r in sheds:
			if r.grow(clear).has_point(q):
				return true
		return false

	## Паркан, що йде вздовж стіни (проєкція на його напрям лежить у межах стіни) ближче FENCE_WALL, заслонює фасад
	## і вікна: там стіна сама межа двору. Прогін кінчається рівно на розі стіни, не за ним, і до стіни його
	## доводить _wall_connector. Стіни — обриси зі звісом даху (_wall_rects, зібрані один раз на кільце).
	func _hugs_wall(q: Vector2, dir: Vector2, slack: float = 0.005) -> bool:
		var along_x: bool = absf(dir.x) >= absf(dir.y)
		var a: float = q.x if along_x else q.y
		for r: Rect2 in _wall_rects:
			if a < (r.position.x if along_x else r.position.y) + slack or a > (r.end.x if along_x else r.end.y) - slack:
				continue
			var gap: float = maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0) if along_x \
					else maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0)
			if gap > (0.02 if slack < 0.01 else 0.03) and gap < (FENCE_WALL if slack < 0.01 else FENCE_WALL - 0.01):
				return true
		return false

	## Відрізок a→b у напрямі d іде вздовж якоїсь стіни (з відступом 0.03 від рогів).
	func _piece_hugs(a: Vector2, b: Vector2, d: Vector2) -> bool:
		for t in 6:
			if _hugs_wall(a.lerp(b, float(t) / 5.0), d, 0.03):
				return true
		return false

	## Відстань від e уздовж d до обрису r (розширеного на 0.02, щоб кінець не лишався на волосину від грані); INF —
	## промінь не влучає.
	func _ray_rect(e: Vector2, d: Vector2, r: Rect2) -> float:
		var g: Rect2 = r.grow(0.02)
		var t0: float = 0.0
		var t1: float = INF
		for ax in 2:
			if absf(d[ax]) < 1e-6:
				if e[ax] < g.position[ax] or e[ax] > g.end[ax]:
					return INF
				continue
			var ta: float = (g.position[ax] - e[ax]) / d[ax]
			var tb: float = (g.end[ax] - e[ax]) / d[ax]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		return t0 if t0 <= t1 else INF

	## Кінці секцій кільця, що висять у повітрі біля стіни, доводяться до її грані перпендикулярним відрізком;
	## ланцюги коротші за MIN_FENCE (уламки), які ні до чого не примикають, викидаються. Повертає відрізки для постановки.
	func _finish_pieces(pieces: Array, posts: Array[Vector2]) -> Array:
		# Кінці чужих парканів — лише довкола цього кільця: далі 0.03 від кінця вони нічого не прив'язують.
		var extent := Rect2(pieces[0][0] if not pieces.is_empty() else Vector2.ZERO, Vector2.ZERO)
		for pc: Array in pieces:
			extent = extent.expand(pc[0]).expand(pc[1])
		extent = extent.grow(0.7)
		var earlier: Array[Vector2] = []
		var earlier_segs: Array = []
		for sg: Array in _fence_segments():
			if extent.has_point(sg[0]) or extent.has_point(sg[1]):
				earlier.append_array([sg[0], sg[1]])
				earlier_segs.append(sg)
		# Відрізок, що все ж ліг уздовж стіни (кути кілець двох дворів, шов між ними), викидається: стіна — межа.
		var kept_pieces: Array = []
		for pc: Array in pieces:
			var along: Vector2 = ((pc[1] as Vector2) - (pc[0] as Vector2)).normalized()
			if not _piece_hugs(pc[0], pc[1], along):
				kept_pieces.append(pc)
		pieces = kept_pieces
		var out: Array = pieces.duplicate()
		var known: Array[Vector2] = posts + earlier
		for pc: Array in pieces:
			for end in 2:
				var e: Vector2 = pc[end]
				var dir: Vector2 = ((pc[1 - end] as Vector2) - e).normalized()
				var anchored: bool = false
				for q: Vector2 in known:
					anchored = anchored or q.distance_to(e) < 0.03
				for o: Array in pieces:
					for oe in 2:
						anchored = anchored or (o != pc and (o[oe] as Vector2).distance_to(e) < 0.03)
				for r: Rect2 in _wall_rects:
					anchored = anchored or r.grow(0.03).has_point(e)
				if anchored:
					continue
				var best: float = 0.6
				var hit_d := Vector2.ZERO
				for d: Vector2 in [Vector2(-dir.y, dir.x), Vector2(dir.y, -dir.x)]:
					for r: Rect2 in _wall_rects:
						var t: float = _ray_rect(e, d, r)
						if t < best and not _piece_hugs(e, e + d * t, d):
							best = t
							hit_d = d
				# Кінець, що впирається у стіну чи в кінець іншого відрізка уздовж ходу ближче FENCE_WALL, дотягується до них:
				# ближче паркан і не ліг би (_hugs_wall), тож кінець там — обрізаний стіною хід, а не уламок.
				var out_dir: Vector2 = -dir
				var reach: float = FENCE_WALL
				var reach_d := Vector2.ZERO
				for r: Rect2 in _wall_rects:
					var t2: float = _ray_rect(e, out_dir, r)
					if t2 < reach and not _piece_hugs(e, e + out_dir * t2, out_dir):
						reach = t2
						reach_d = out_dir
				for o: Array in pieces:
					for oe in 2:
						var v: Vector2 = (o[oe] as Vector2) - e
						if o != pc and v.dot(out_dir) > 0.02 and v.length() < reach and absf(v.cross(out_dir)) < 0.03 \
								and not _piece_hugs(e, e + out_dir * v.length(), out_dir):
							reach = v.length()
							reach_d = out_dir
				if reach_d != Vector2.ZERO and (hit_d == Vector2.ZERO or reach < best):
					out.append([e, e + reach_d * reach])
				elif hit_d != Vector2.ZERO:
					out.append([e, e + hit_d * best])
		out = _prune_dangling(_drop_short_runs(out, posts, earlier_segs, known, _wall_rects), known, _wall_rects)
		# Ланцюги за збігом кінців.
		var parent: Array[int] = []
		for k in out.size():
			parent.append(k)
		for k in out.size():
			for m in range(k + 1, out.size()):
				for ea: Vector2 in out[k]:
					for eb: Vector2 in out[m]:
						if ea.distance_to(eb) < 0.03:
							var rk: int = k
							while parent[rk] != rk:
								rk = parent[rk]
							var rm: int = m
							while parent[rm] != rm:
								rm = parent[rm]
							parent[rk] = rm
		var length: Dictionary = {}
		var tied: Dictionary = {}
		for k in out.size():
			var r: int = k
			while parent[r] != r:
				r = parent[r]
			length[r] = float(length.get(r, 0.0)) + (out[k][0] as Vector2).distance_to(out[k][1])
			for q: Vector2 in known:
				if q.distance_to(out[k][0]) < 0.03 or q.distance_to(out[k][1]) < 0.03:
					tied[r] = true
		var kept: Array = []
		for k in out.size():
			var r: int = k
			while parent[r] != r:
				r = parent[r]
			if float(length[r]) >= MIN_FENCE or tied.has(r):
				kept.append(out[k])
		return kept

	## Купки коротких (за SHORT_RUN) прямих ходів кільця, що не тримають ні воріт, ні довгого ходу (свого чи сусіднього
	## двору), викидаються: шматки довкола рогу хати, що замикаються самі на себе через стіну, — уламок, що закінчується в
	## нікуди. Купка, де хоч один хід тримає стовп воріт чи довгий хід (бічна стійка воріт, обхід перешкоди), лишається
	## цілою — інакше кільце розімкнулось би. Що після цього повисне, прибирає прохід «висить у повітрі».
	static func _drop_short_runs(out: Array, posts: Array, others: Array, known: Array, walls: Array) -> Array:
		# Купки — з поточного набору: після кожного викидання ходи й купки рахуються заново.
		var kept: Array = []
		var changed := true
		while changed:
			changed = false
			for cl: Array in _short_clusters(_collinear_runs(out + others), posts):
				var segs: Array = []
				for run: Dictionary in cl[0]:
					segs.append_array(run["segs"])
				if bool(cl[1]) or kept.has(segs):
					continue
				var rest: Array = out.filter(func(pc: Array) -> bool: return not segs.has(pc))
				var pruned: Array = _prune_dangling(rest, known, walls)
				# Купка, без якої повис би довгий хід (за довжиною всього прямого ходу, а не шматка), — частина замкненого
				# кільця, а не уламок: лишається.
				var lost_long := false
				for run: Dictionary in _collinear_runs(rest + others):
					if float(run["len"]) < SHORT_RUN:
						continue
					for sg: Array in run["segs"]:
						lost_long = lost_long or (rest.has(sg) and not pruned.has(sg))
				if lost_long:
					kept.append(segs)
					continue
				out = pruned
				changed = true
				break
		return out

	## Відрізок із кінцем, що висить у повітрі (ні стовпа, ні іншого відрізка, ні стіни поруч), викидається разом із
	## наслідками.
	static func _prune_dangling(out: Array, known: Array, walls: Array) -> Array:
		for pass_id in 6:
			var survivors: Array = []
			for pc: Array in out:
				var dangling := false
				for end in 2:
					var e: Vector2 = pc[end]
					var anchored := false
					for q: Vector2 in known:
						anchored = anchored or q.distance_to(e) < 0.03
					for o: Array in out:
						for oe in 2:
							anchored = anchored or (o != pc and (o[oe] as Vector2).distance_to(e) < 0.03)
					for r: Rect2 in walls:
						anchored = anchored or r.grow(0.03).has_point(e)
					dangling = dangling or not anchored
				if not dangling:
					survivors.append(pc)
			if survivors.size() == out.size():
				break
			out = survivors
		return out

	## Короткі ходи, згруповані за спільними кінцями: [[ходи…], тримає?] — тримає, коли кінець котрогось ходу на стовпі
	## воріт (ближче 0.04) чи на довгому ході (ближче 0.03).
	static func _short_clusters(runs: Array, posts: Array) -> Array:
		var short: Array = runs.filter(func(r: Dictionary) -> bool: return float(r["len"]) < SHORT_RUN)
		var long: Array = runs.filter(func(r: Dictionary) -> bool: return float(r["len"]) >= SHORT_RUN)
		var parent: Array[int] = []
		for k in short.size():
			parent.append(k)
		var root := func(k: int) -> int:
			while parent[k] != k:
				k = parent[k]
			return k
		for k in short.size():
			for m in range(k + 1, short.size()):
				var touch := false
				for sa: Array in short[k]["segs"]:
					for sb: Array in short[m]["segs"]:
						for ea: Vector2 in sa:
							for eb: Vector2 in sb:
								touch = touch or ea.distance_to(eb) < 0.03
				if touch:
					parent[root.call(k)] = root.call(m)
		var by_root: Dictionary = {}
		for k in short.size():
			var r: int = root.call(k)
			if not by_root.has(r):
				by_root[r] = [[], false]
			by_root[r][0].append(short[k])
			for e: Vector2 in short[k]["ends"]:
				for q: Vector2 in posts:
					if q.distance_to(e) < 0.04:
						by_root[r][1] = true
				for other: Dictionary in long:
					for sg: Array in other["segs"]:
						if Geometry2D.get_closest_point_to_segment(e, sg[0], sg[1]).distance_to(e) < 0.03:
							by_root[r][1] = true
		return by_root.values()

	## Ділянка паркану від a до b, розірвана там, де дорога, вода чи будівля: паркан доходить до стіни
	## (обрису зі звісом), і стіна хати чи сараю сама замикає двір. Коротких шматків не викидаємо —
	## інакше кільце розімкнулось би.
	func _fence_run(m: StringName, a: Vector2, b: Vector2, lot: Dictionary, sheds: Array[Rect2]) -> void:
		for sp: Array in _free_spans(a, b, sheds):
			_fence_straight(m, sp[0], sp[1], lot)

	## Перша точка від c до to (кроком 0.02, із запасом у крок), де паркан не на дорозі й не біля води;
	## c, якщо такої нема.
	func _first_free(c: Vector2, to: Vector2) -> Vector2:
		var total: float = c.distance_to(to)
		var t: float = 0.02
		while t < total:
			if not _fence_hard(c.lerp(to, t / total)):
				return c.lerp(to, minf(t + 0.02, total) / total)
			t += 0.02
		return c

	## Вільні ділянки відрізка a→b кроком 0.02 (~0.15 м): [[початок, кінець], …].
	func _free_spans(a: Vector2, b: Vector2, sheds: Array[Rect2]) -> Array:
		var out: Array = []
		var total: float = a.distance_to(b)
		if total < 0.05:
			return out
		var dir: Vector2 = (b - a) / total
		var steps: int = maxi(1, ceili(total / 0.02))
		var from: float = -1.0
		for k in steps + 1:
			var t: float = total * float(k) / float(steps)
			var free: bool = not _fence_blocked(a + dir * t, sheds, 0.02, dir)
			if free and from < 0.0:
				from = t
			if (not free or k == steps) and from >= 0.0:
				var to: float = t if free else t - total / float(steps)
				if to - from >= 0.02:
					out.append([a + dir * from, a + dir * to])
				from = -1.0
		return out

	## Пряма ділянка паркану: рівні секції не довші за клітинку, кожна лежить на землі обома кінцями;
	## секція належить найближчій клітинці двору, тож давить її той, хто заїхав у двір.
	func _fence_straight(m: StringName, a: Vector2, b: Vector2, lot: Dictionary) -> void:
		if _collecting:
			_pieces.append([a, b])
			return
		var total: float = a.distance_to(b)
		var n: int = maxi(1, ceili(total / 1.0))
		var along: Vector2 = (b - a) / float(n)
		var hs: float = float(PropLayer.spec_of(m).get("height", 1.0)) * _ring_hmul
		var model_len: float = ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.x
		var spans: Array = []
		for k in n:
			_fence_split(a + along * k, a + along * (k + 1), spans)
		for sp: Array in spans:
			var p0: Vector2 = sp[0]
			var p1: Vector2 = sp[1]
			var mid: Vector2 = (p0 + p1) * 0.5
			along = p1 - p0
			var yaw: float = atan2(-along.y, along.x)
			var y0: float = ground(p0.x, p0.y)
			var y1: float = ground(p1.x, p1.y)
			var length: float = along.length()
			var basis := Basis(Vector3.UP, yaw)
			basis = Basis(basis.z, atan2(y1 - y0, length)) * basis
			# Довжина вздовж схилу: інакше нахилена секція коротша за проліт і між сусідніми щілина.
			var slope_len: float = Vector2(length, y1 - y0).length()
			var xf := Transform3D(basis * Basis.from_scale(Vector3(slope_len / model_len, hs, 1.0)), Vector3(mid.x, (y0 + y1) * 0.5, mid.y))
			var c: Vector2i = lot.keys()[0]
			for g: Vector2i in lot:
				if Vector2(g).distance_squared_to(mid) < Vector2(c).distance_squared_to(mid):
					c = g
			var cells: Array[Vector2i] = [c]
			layer._add(m, xf, cells)
			yard_cells[c] = true

	## Секція p0→p1 — пряма між висотами кінців; де ґрунт під нею (на чверті, середині й трьох
	## чвертях) відходить від прямої більш ніж на FENCE_SAG (край майданчика будівлі, бровка), вона
	## ділиться навпіл, але не коротша за FENCE_MIN.
	func _fence_split(p0: Vector2, p1: Vector2, out: Array) -> void:
		var y0: float = ground(p0.x, p0.y)
		var y1: float = ground(p1.x, p1.y)
		if p0.distance_to(p1) >= 2.0 * FENCE_MIN:
			for t: float in [0.25, 0.5, 0.75]:
				var q: Vector2 = p0.lerp(p1, t)
				if absf(ground(q.x, q.y) - lerpf(y0, y1, t)) > FENCE_SAG:
					var mid: Vector2 = (p0 + p1) * 0.5
					_fence_split(p0, mid, out)
					_fence_split(mid, p1, out)
					return
		out.append([p0, p1])

	## Тюки з макету: на краю поля, поодинці чи вільною парою, кожен своїм поворотом.
	func _layout_hay() -> void:
		for p0: Vector2 in layout.get("hay", []):
			# Тюк — щойно за краєм ріллі (HAY_OUT від краю), ніколи на ній, посеред луку чи на схилі без
			# поля: точка з макету сідає на найближчий край поля; поля поруч нема — тюка нема.
			var best := Vector2.INF
			var normal := Vector2.ZERO
			var edge_dir := Vector2.ZERO
			for r: Rect2 in layer.field_edges:
				var q: Vector2 = p0.clamp(r.position, r.end)
				var n := Vector2.ZERO
				var t := Vector2.ZERO
				if r.has_point(p0):
					# Усередині поля: на найближчий бік.
					var dists: Array[float] = [p0.x - r.position.x, r.end.x - p0.x, p0.y - r.position.y, r.end.y - p0.y]
					var side: int = dists.find(dists.min())
					n = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)][side]
					q = Vector2(r.position.x if side == 0 else (r.end.x if side == 1 else p0.x),
							r.position.y if side == 2 else (r.end.y if side == 3 else p0.y))
				else:
					n = (p0 - q).normalized()
					if absf(n.x) > absf(n.y):
						n = Vector2(signf(n.x), 0.0)
					else:
						n = Vector2(0.0, signf(n.y))
				t = Vector2(-n.y, n.x)
				if q.distance_to(p0) < best.distance_to(p0):
					best = q
					normal = n
					edge_dir = t
			if best == Vector2.INF or best.distance_to(p0) > HAY_SNAP:
				continue
			var c := Vector2i(roundi(best.x), roundi(best.y))
			if not on_board(c):
				continue
			var m: StringName = pick_for_half(Kind.HAY, half(c))
			var n_bales: int = 1 + h(c, 7) % 2
			if m == &"":
				continue
			for k in n_bales:
				# Місце біля краю поля, де тюк не заходить у слід юніта жодної клітинки: трохи далі чи
				# ближче від краю, трохи вздовж нього.
				for cand: Vector2 in [Vector2(HAY_OUT, 0.0), Vector2(0.08, 0.0), Vector2(0.24, 0.0), Vector2(HAY_OUT, 0.2),
						Vector2(HAY_OUT, -0.2), Vector2(0.08, 0.35), Vector2(0.08, -0.35), Vector2(0.24, 0.35), Vector2(0.24, -0.35)]:
					var q: Vector2 = best + normal * cand.x + edge_dir * (cand.y + 0.18 * k)
					var qc := Vector2i(roundi(q.x), roundi(q.y))
					if not on_board(qc) or kind(qc) in [Terrain.Kind.WATER, Terrain.Kind.MARSH, Terrain.Kind.FOREST, Terrain.Kind.BUILDING, Terrain.Kind.RUBBLE] \
							or near_wet(q, WATER_CLEAR) or layer.field_edges.any(func(r: Rect2) -> bool: return r.has_point(q)):
						continue
					var xform := Transform3D(Basis(Vector3.UP, float(h(c, 16 + k) % 628) / 100.0), Vector3(q.x, ground(q.x, q.y), q.y))
					var box: AABB = xform * ((PropLayer.model(m) as Dictionary)["aabb"] as AABB)
					if _box_on_road(m, xform) or not clear_of_units(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)):
						continue
					var cells: Array[Vector2i] = [qc]
					layer._add(m, xform, cells)
					break

	## ЛЕП: мережу будує PowerGrid (10 кВ за намірами routes макета, ТП і дерево 0.4 кВ до хат, усе вздовж осей карти);
	## тут — стовпи на її точках, траверса впоперек прольоту, на куті — по бісектрисі; підстанції й відводи. Точка, де стовпу
	## не місце, лишає розрив, який ловить тест, а не мовчки зсувається.
	func _layout_poles() -> void:
		_index_obstacles()
		var grid := PowerGrid.new()
		grid.plan(self)
		for line: Dictionary in grid.lines:
			var kind_name: StringName = line["kind"]
			var m: StringName = &"infra_pole_concrete_10kv" if kind_name == &"10kv" else &"infra_pole_concrete_04kv"
			if PropLayer.model(m) == null:
				continue
			var pts: Array = line["points"]
			var prev: int = -1
			for k in pts.size():
				var p: Vector2 = pts[k]
				var idx: int = _pole_near(p, PropLayer.POLE_SNAP)
				if idx < 0:
					var t := Vector2.ZERO
					if k > 0:
						t += (p - (pts[k - 1] as Vector2)).normalized()
					if k < pts.size() - 1:
						t += ((pts[k + 1] as Vector2) - p).normalized()
					if t.length() < 0.1:
						t = (p - (pts[maxi(k - 1, 0)] as Vector2)).normalized()
					idx = _pole_on(m, p, t.normalized())
				if idx < 0:
					prev = -1
					continue
				if prev >= 0 and prev != idx:
					spans.append([prev, idx])
				prev = idx
		for p: Vector2 in grid.transformers:
			var i: int = _pole_near(p, PropLayer.POLE_SNAP)
			if i >= 0 and _is_10kv(i):
				layer._transformers[i] = true
		layer._skipped = grid.skipped
		_service_drops(grid.fed)

	func _is_10kv(i: int) -> bool:
		return PropLayer.spec_of(layer._instances[i]["model"]).get("line", &"") == &"10kv"

	## Індекс стовпа в межах r від p, або −1.
	func _pole_near(p: Vector2, r: float) -> int:
		for i in layer._instances.size():
			if int(PropLayer.spec_of(layer._instances[i]["model"])["kind"]) != Kind.POLE:
				continue
			var o: Vector3 = (layer._instances[i]["transform"] as Transform3D).origin
			if Vector2(o.x, o.z).distance_to(p) <= r:
				return i
		return -1

	## Обриси для стовпів і дротів ЛЕП: будівлі й руїни, мости, решта пропсів (паркани, тюки, причепи), грядки.
	func _index_obstacles() -> void:
		_index_fences()
		_bld_rects.clear()
		_bld_heights.clear()
		_home_rects.clear()
		_prop_rects.clear()
		_garden_rects.clear()
		_bridge_rects.clear()
		_hay_rects.clear()
		_chimneys.clear()
		for inst: Dictionary in layer._instances:
			var k: int = int(PropLayer.spec_of(inst["model"])["kind"])
			if k == Kind.POLE:
				continue
			var b: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
			var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
			if k == Kind.STRUCTURE or k == Kind.RUIN:
				_bld_rects.append(r)
				_bld_heights.append(b.size.y)
				var xf: Transform3D = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary).get("local", Transform3D()) as Transform3D)
				for ch: Vector3 in (PropLayer.model(inst["model"]) as Dictionary).get("chimneys", []):
					var w: Vector3 = xf * ch
					_chimneys.append(Vector3(w.x, w.y - b.position.y, w.z))
				if PropLayer.is_home(inst):
					_home_rects.append(r)
			elif k == Kind.BRIDGE:
				_bridge_rects.append(r)
			else:
				_prop_rects.append(r)
				if k == Kind.HAY:
					_hay_rects.append(r)
		for gp: Dictionary in garden_plots:
			_garden_rects.append(gp["rect"])

	## Знакова відстань (м, мінус на дорозі) від p до краю асфальту за полем дороги, яке малює шейдер землі.
	func road_edge_m(p: Vector2) -> float:
		if height == null or height.roads == null:
			return 1e9
		return (height.roads as RoadCourse).d_at(p)

	## Точка p клітинки двору c не далі YARD_EDGE від межі двору з боку вулиці (сусідня клітинка — не двір).
	func _on_fence_line(p: Vector2, c: Vector2i) -> bool:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: int = kind(c + d)
			if n == Terrain.Kind.BUILDING or n == Terrain.Kind.RUBBLE:
				continue
			var inside: float = 0.5 - (p - Vector2(c)).dot(Vector2(d))
			if inside >= 0.0 and inside <= PropLayer.YARD_EDGE:
				return true
		return false

	## Чи може тут стояти стовп: тверда земля (поле, пагорб; двір і поле руїн — лише коли yard_ok), не асфальт (за полем дороги), не
	## вода, не слід юніта, не ближче POLE_BUILDING_CLEAR до обрису будівлі, не в парканах, грядках і дрібних
	## речах, не на мосту.
	func pole_spot_ok(p: Vector2, tier: int = 2) -> bool:
		var c := Vector2i(roundi(p.x), roundi(p.y))
		# Стовп у дворі садиби — між сараєм і городом — не стоїть: лише на вулиці чи в полі.
		if in_yard(p) or near_gate(p):
			return false
		# Секції паркану стоять не точно на обрисі двору (вид паркану, відступ від перешкод): стовп міряє і до них.
		if fence_dist(p) < PropLayer.POLE_FENCE_SEG_CLEAR:
			return false
		var k: int = kind(c)
		var ground_kind: bool = k == Terrain.Kind.FIELD or k == Terrain.Kind.HILL
		# Порядок місць: 0 — поле й пагорб; 1 — узбіччя клітинки дороги поза асфальтом; 2 — край клітинки забудови чи
		# руїн з боку вулиці: двори садиб макету відкидає in_yard вище, тож це лише забудова кільця без двору.
		if not ground_kind:
			var shoulder: bool = tier >= 1 and k == Terrain.Kind.ROAD
			var fence_line: bool = tier >= 2 and (k == Terrain.Kind.BUILDING or k == Terrain.Kind.RUBBLE) and _on_fence_line(p, c)
			if not shoulder and not fence_line:
				return false
		if road_edge_m(p) < PropLayer.POLE_ROAD_CLEAR_M:
			return false
		# Стовп на березі, не в руслі й не над болотом.
		if near_wet(p, PropLayer.POLE_WET_CLEAR):
			return false
		for r: Rect2 in _bld_rects:
			if r.grow(PropLayer.POLE_BUILDING_CLEAR).has_point(p):
				return false
		for r: Rect2 in _home_rects:
			if r.grow(PropLayer.POLE_HOME_CLEAR).has_point(p):
				return false
		for r: Rect2 in _prop_rects:
			if r.grow(PropLayer.POLE_PROP_CLEAR).has_point(p):
				return false
		for r: Rect2 in _garden_rects:
			if r.grow(PropLayer.POLE_GARDEN_CLEAR).has_point(p):
				return false
		for r: Rect2 in _bridge_rects:
			if r.grow(PropLayer.POLE_BRIDGE_CLEAR).has_point(p):
				return false
		# Опора поруч із тюком читається шафою підстанції.
		for r: Rect2 in _hay_rects:
			if r.grow(PropLayer.POLE_HAY_CLEAR).has_point(p):
				return false
		# Не ближче UNIT_POLE_CLEAR до сліду юніта будь-якої клітинки дошки: стовп впритул до корпусу.
		return clear_of_units(Rect2(p - Vector2(0.03, 0.03), Vector2(0.06, 0.06)), PropLayer.UNIT_POLE_CLEAR)

	## Проліт a–b не лягає на жодну будівлю.
	func span_hits_building(a: Vector2, b: Vector2) -> bool:
		for r: Rect2 in _bld_rects:
			if _seg_hits_rect(a, b, r.grow(PropLayer.POLE_BUILDING_CLEAR)):
				return true
		return false

	## Анкер відтяжки: на ґрунті поза асфальтом, будівлями й слідом юніта.
	func anchor_ok(q: Vector2) -> bool:
		if road_edge_m(q) < PropLayer.POLE_ROAD_CLEAR_M or near_wet(q, PropLayer.POLE_WET_CLEAR):
			return false
		for r: Rect2 in _bld_rects:
			if r.grow(0.05).has_point(q):
				return false
		return clear_of_units(Rect2(q - Vector2(0.02, 0.02), Vector2(0.04, 0.04)), 0.0)

	## Площа шафи ТП (кути й центр): поза асфальтом (≥ POLE_ROAD_CLEAR_M), будівлями, парканами й слідом юніта.
	func cabinet_ok(corners: Array[Vector2]) -> bool:
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for q in corners:
			if road_edge_m(q) < PropLayer.POLE_ROAD_CLEAR_M:
				return false
			for r: Rect2 in _bld_rects:
				if r.grow(0.05).has_point(q):
					return false
			for r: Rect2 in _prop_rects:
				if r.has_point(q):
					return false
			lo = lo.min(q)
			hi = hi.max(q)
		return clear_of_units(Rect2(lo, hi - lo), 0.0)

	## Стовп на точці, якщо там можна; індекс екземпляра чи −1. Кільце теж: лінія йде за межу дошки.
	## Не put_small: той міряє дорогу за ламаною осі, а тут — за полем дороги, яке малює шейдер.
	func _pole_on(m: StringName, p: Vector2, t: Vector2) -> int:
		if not pole_spot_ok(p, 2):
			return -1
		var c := Vector2i(roundi(p.x), roundi(p.y))
		var xform := Transform3D(Basis(Vector3.UP, atan2(t.x, t.y)), Vector3(p.x, ground(p.x, p.y), p.y))
		if not clear_of_centre(m, xform, c):
			return -1
		var cells: Array[Vector2i] = [c]
		return layer._add(m, xform, cells)

	## Відвід до цілої хати, яку мережа вирішила живити (PowerGrid.fed), від найближчої опори 0.4 кВ (чи 10 кВ із
	## підстанцією), від якої він можливий (_drop_target). Хати без відводу — у layer._unfed.
	func _service_drops(fed_homes: Array[Vector2]) -> void:
		var poles: Array[int] = []
		for i in layer._instances.size():
			if int(PropLayer.spec_of(layer._instances[i]["model"])["kind"]) == Kind.POLE \
					and (not _is_10kv(i) or layer._transformers.has(i)):
				poles.append(i)
		layer._unfed.clear()
		for house_i in layer._instances.size():
			var inst: Dictionary = layer._instances[house_i]
			if not PropLayer.is_home(inst):
				continue
			var box: AABB = _box_of(inst)
			var centre := Vector2(box.get_center().x, box.get_center().z)
			var fed: bool = false
			var order: Array[int] = []
			if fed_homes.any(func(c: Vector2) -> bool: return c.distance_to(centre) < 0.05):
				order = poles.duplicate()
			order.sort_custom(func(x: int, y: int) -> bool: return _pole_xz(x).distance_to(centre) < _pole_xz(y).distance_to(centre))
			for pi in order:
				var at: Vector3 = _drop_target(house_i, pi)
				if at.is_finite():
					layer._drops.append([pi, at])
					fed = true
					break
			if not fed:
				layer._unfed.append(centre)

	func _box_of(inst: Dictionary) -> AABB:
		return (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)

	## Стіна хати rect, на якій лежить точка a, придатна для відводу: без власного димаря хати біля неї (ближче
	## DROP_CHIMNEY_WALL до її лінії і помітно ближче, ніж до протилежної стіни) — інакше відвід на екрані кінчається на
	## шапці димаря (димар на щиті чи зовнішній). Точка на розі лежить на двох стінах — придатні мають бути обидві.
	func drop_face_ok(rect: Rect2, a: Vector2) -> bool:
		for n: Vector2 in PropLayer.wall_normals(rect, a):
			if chimney_wall(rect, n):
				return false
		return true

	## Чи стоїть власний димар хати rect біля її стіни з зовнішньою нормаллю n.
	func chimney_wall(rect: Rect2, n: Vector2) -> bool:
		var wall: float = (rect.get_center() + rect.size * 0.5 * n).dot(n)
		var depth: float = absf(rect.size.dot(n))
		for ch: Vector3 in _chimneys:
			var q := Vector2(ch.x, ch.z)
			if not rect.grow(0.02).has_point(q):
				continue
			# Димар на гребені вузької хати однаково близько до обох довгих стін і жодній не належить.
			var off: float = absf(wall - q.dot(n))
			if off < PropLayer.DROP_CHIMNEY_WALL and off < absf(depth - off) - 0.1:
				return true
		return false

	## Відвід від точки from до хати з обрисом rect можливий: стіна з боку from не далі за DROP_DIRECT і не ближче за
	## DROP_MIN, відрізок не ближче DROP_GAP до чужих хат і як дріт можливий (wire_ok; через вулицю — не довший за
	## DROP_CROSS).
	func drop_ok(rect: Rect2, from: Vector2) -> bool:
		return drop_point(rect, from).is_finite()

	## Куди на стіні хати rect чіпляється відвід від опори from: найближча точка обрису, а коли відвід туди неможливий
	## (над грядкою, прямо до камери) — середина іншої стіни, повернутої до опори. INF — відводу нема.
	func drop_point(rect: Rect2, from: Vector2) -> Vector2:
		var near: Vector2 = PropLayer.drop_attach(rect, from)
		if not near.is_finite():
			return Vector2.INF
		var cands: Array[Vector2] = [near]
		var c: Vector2 = rect.get_center()
		for wall: Vector2 in [Vector2(rect.position.x, c.y), Vector2(rect.end.x, c.y), Vector2(c.x, rect.position.y), Vector2(c.x, rect.end.y)]:
			# Стіна повернута до опори: опора з її зовнішнього боку, тож дріт не йде над власним дахом. Середина й чверті
			# стіни: правило стіни з димарем (drop_face_ok) однакове для всієї стіни, але чверть може бути далі від димаря
			# (DROP_CHIMNEY_CLEAR) і ближче до опори (DROP_DIRECT, проєкція на будівлі) — без чвертей Перехрестя має 6 відводів
			# замість 9.
			if (from - wall).dot(wall - c) > 0.0:
				var along: Vector2 = (wall - c).normalized().orthogonal() * absf(rect.size.dot((wall - c).normalized().orthogonal())) * 0.25
				cands.append_array([wall, wall + along, wall - along])
		for a: Vector2 in cands:
			var d: float = from.distance_to(a)
			if d > PropLayer.DROP_DIRECT or d < PropLayer.DROP_MIN:
				continue
			if _chimneys.any(func(ch: Vector3) -> bool: return Vector2(ch.x, ch.z).distance_to(a) < PropLayer.DROP_CHIMNEY_CLEAR) \
					or not drop_face_ok(rect, a):
				continue
			# Відвід не лягає на жодну чужу будівлю, не ближче DROP_GAP.
			var clear: bool = true
			for r: Rect2 in _bld_rects:
				if not r.is_equal_approx(rect) and _seg_hits_rect(from, a, r.grow(PropLayer.DROP_GAP)):
					clear = false
					break
			# Навскісні відводи через вулицю, поле й сусідні двори до кожної хати робили село павутинням: відвід —
			# коротко від опори, через вулицю лише прямо впоперек, не чужим двором і не над грядкою.
			if clear and wire_ok(from, a, PropLayer.DROP_CROSS, rect):
				return a
		return Vector2.INF

	## Дріт від a до b (проліт 0.4 кВ чи відвід до хати own): не над грядкою, не крізь двір садиби (крім двору own), не
	## над будівлею з боку камери (окрім own), а асфальт перетинає лише прямо впоперек вулиці (DROP_CROSS_COS) і не
	## довшим за cross_max прольотом.
	func wire_ok(a: Vector2, b: Vector2, cross_max: float, own: Rect2 = Rect2()) -> bool:
		if not own.has_area() and not _span_above_ground(a, b):
			return false
		for r: Rect2 in _garden_rects:
			if _seg_hits_rect(a, b, r):
				return false
		if not _seen_clear(a, b, own):
			return false
		if own.has_area() and absf((b - a).normalized().dot(Vector2.ONE.normalized())) > PropLayer.DROP_VIEW_COS:
			return false
		var home: Variant = yard_owner.get(Vector2i(roundi(own.get_center().x), roundi(own.get_center().y))) if own.has_area() else null
		var len_: float = a.distance_to(b)
		var n: int = maxi(2, ceili(len_ / 0.1))
		var on_road: int = 0
		var deepest: float = 0.0
		for j in range(0, n + 1):
			var q: Vector2 = a.lerp(b, float(j) / n)
			var dm: float = road_edge_m(q)
			if dm < 0.0:
				on_road += 1
				deepest = minf(deepest, dm)
			# Опора стоїть на межі клітинок: точка в двір глибше за YARD_EPS — уже крізь двір.
			var c := Vector2i(roundi(q.x), roundi(q.y))
			# Дріт крізь ліс не видно: лінія, що виходить з-під крон, читається лінією нізвідки.
			if kind(c) == Terrain.Kind.FOREST:
				return false
			if yard_owner.has(c) and yard_owner[c] != home and minf(0.5 - absf(q.x - c.x), 0.5 - absf(q.y - c.y)) > PropLayer.YARD_EPS:
				return false
		# Над асфальтом дріт лише прямо впоперек. Перехід (дріт перетинає вісь): не довший за cross_max, на осі не далі за
		# 25° від прямого кута, і над асфальтом не довше за ROAD_SPAN_K ширини дороги (ширина — удвічі найглибша точка під
		# дротом). Дріт, що лише зрізає край асфальту на повороті, висить над ним не далі ROAD_CLIP: кут в одній точці
		# пропускав навскісні проліти над внутрішнім боком повороту.
		if on_road > 0:
			var over: float = len_ * on_road / (n + 1)
			if not _crosses_axis(a, b):
				return over <= PropLayer.ROAD_CLIP
			# Точки дроту — через 0.1 клітинки, тож довжина над асфальтом відома з точністю до кроку: він — у допуску.
			if len_ > cross_max or over > PropLayer.ROAD_SPAN_K * 2.0 * -deepest / 8.0 + len_ / n:
				return false
			if absf((b - a).normalized().dot(street_dir(a.lerp(b, 0.5), a, b))) > sqrt(1.0 - PropLayer.DROP_CROSS_COS * PropLayer.DROP_CROSS_COS):
				return false
		return true

	## Висота дроту від a до b над ґрунтом у частці t (клітинки): проліт — між траверсами опор 0.4 кВ із провисом,
	## відвід — від траверси до кріплення на стіні під звісом.
	func _wire_h(a: Vector2, b: Vector2, t: float, drop: bool) -> float:
		var top: float = _pole_top()
		var q: Vector2 = a.lerp(b, t)
		var base: float = lerpf(ground(a.x, a.y), ground(b.x, b.y), t) - ground(q.x, q.y)
		if drop:
			return base + lerpf(top, PropLayer.DROP_ATTACH_H, t)
		return base + top - PropLayer.WIRE_SAG_RATIO * a.distance_to(b) * 4.0 * t * (1.0 - t)

	func _pole_top() -> float:
		var info: Variant = PropLayer.model(&"infra_pole_concrete_04kv")
		if info == null:
			return 0.9
		var top: float = INF
		for w: Vector3 in (info as Dictionary)["wires"]:
			top = minf(top, w.y)
		return top

	## Дріт на висоті h у точці q камера бачить над точкою землі q − (до камери)·h·ctg(нахилу); камера стоїть на +x, +z
	## від фокуса (IsoCameraRig.YAW_DEGREES). Дріт не має читатися над будівлею (стіна, звіс і дах до висоти дроту — під
	## нахилом WIRE_SEEN_PITCH_DEG) і біля стовпчика димаря (під CHIMNEY_SEEN_PITCH_DEG). Двір, грядку й асфальт видно згори таким, як є, — вони
	## перевіряються на землі (wire_ok). Відвід може читатися над власною хатою лише в останніх DROP_END_FREE біля стіни.
	func _seen_clear(a: Vector2, b: Vector2, own: Rect2) -> bool:
		var drop: bool = own.has_area()
		var away := -Vector2(sin(deg_to_rad(IsoCameraRig.YAW_DEGREES)), cos(deg_to_rad(IsoCameraRig.YAW_DEGREES)))
		# Найбільший зсув — під найнижчим із двох нахилів.
		var cot_max: float = 1.0 / tan(deg_to_rad(minf(PropLayer.WIRE_SEEN_PITCH_DEG, PropLayer.CHIMNEY_SEEN_PITCH_DEG)))
		var cot_bld: float = 1.0 / tan(deg_to_rad(PropLayer.WIRE_SEEN_PITCH_DEG))
		var cot_chim: float = 1.0 / tan(deg_to_rad(PropLayer.CHIMNEY_SEEN_PITCH_DEG))
		var reach: float = (_pole_top() + 0.1) * cot_max
		# Лише ті будівлі й димарі, до яких дріт зі зсувом (від камери на висоту дроту, до камери — на висоту будівлі над
		# ним) узагалі може дістати.
		var box := Rect2(a, Vector2.ZERO).expand(b).expand(a + away * reach).expand(b + away * reach) \
				.expand(a - away * reach).expand(b - away * reach).grow(0.05)
		var near: Array[int] = []
		for i in _bld_rects.size():
			if _bld_rects[i].intersects(box):
				near.append(i)
		var chims: Array[Vector3] = _chimneys.filter(func(c: Vector3) -> bool: return box.has_point(Vector2(c.x, c.z)))
		if near.is_empty() and chims.is_empty():
			return true
		var len_: float = a.distance_to(b)
		var n: int = maxi(2, ceili(len_ / 0.15))
		for j in range(0, n + 1):
			var t: float = float(j) / n
			var q: Vector2 = a.lerp(b, t)
			var h: float = _wire_h(a, b, t, drop)
			var end_free: bool = drop and (1.0 - t) * len_ < PropLayer.DROP_END_FREE
			for i: int in near:
				var r: Rect2 = _bld_rects[i]
				var mine: bool = drop and r.is_equal_approx(own)
				if end_free and mine:
					continue
				# Точка будівлі на висоті z (до висоти дроту) на екрані збігається з дротом на висоті h, якщо лежить на
				# (h − z)·ctg від нього в бік від камери: стіна внизу — найдалі, на висоті дроту — під ним. Відвід
				# кріпиться на стіні власної хати, тож над її стіною він і має читатися — заборонено лише над дахом
				# (вище за звіс, DROP_ATTACH_H + 1 м).
				var z: float = PropLayer.DROP_ATTACH_H + 0.125 if mine else 0.0
				# Частина будівлі вища за дріт стоїть між камерою й дротом і ховає його, а не лягає під нього.
				var ztop: float = minf(_bld_heights[i], h)
				# Крок 0.1 і окремо сама верхня точка (z = ztop): інакше крок міг би її проминути.
				while z < ztop:
					if r.has_point(q + away * (h - z) * cot_bld):
						return false
					z += 0.1
				if ztop >= (PropLayer.DROP_ATTACH_H + 0.125 if mine else 0.0) and r.has_point(q + away * (h - ztop) * cot_bld):
					return false
			# Димар — стовпчик від гребеня до шапки: дріт не має читатися біля нього (відвід, що «закінчується» на
			# димарі).
			for c: Vector3 in chims:
				for zc: float in [c.y, c.y - 0.15, c.y - 0.3]:
					if (q + away * (h - zc) * cot_chim).distance_to(Vector2(c.x, c.z)) < PropLayer.WIRE_CHIMNEY_CLEAR:
						return false
		return true

	## Проліт 0.4 кВ між опорами в a і b висить не нижче WIRE_CLEAR_M над ґрунтом чи водою (з провисом): горб між
	## опорами — опора на горбі, а не дріт по траві.
	func _span_above_ground(a: Vector2, b: Vector2) -> bool:
		var info: Variant = PropLayer.model(&"infra_pole_concrete_04kv")
		if info == null or height == null:
			return true
		var top: float = INF
		for w: Vector3 in (info as Dictionary)["wires"]:
			top = minf(top, w.y)
		var sag: float = PropLayer.WIRE_SAG_RATIO * a.distance_to(b)
		var ga: float = ground(a.x, a.y)
		var gb: float = ground(b.x, b.y)
		for j in range(1, 20):
			var t: float = j / 20.0
			var q: Vector2 = a.lerp(b, t)
			var y: float = lerpf(ga, gb, t) + top - sag * 4.0 * t * (1.0 - t)
			if (y - maxf(ground(q.x, q.y), TerrainHeight.WATER_LEVEL)) * 8.0 < PropLayer.WIRE_CLEAR_M:
				return false
		return true

	## Чи стоїть p у прорізі воріт садиби чи ближче POLE_GATE_CLEAR до нього (стовп у воротах ними не проїхати).
	func near_gate(p: Vector2) -> bool:
		for g: Array in gate_segments:
			if Geometry2D.get_closest_point_to_segment(p, g[0], g[1]).distance_to(p) < PropLayer.POLE_GATE_CLEAR:
				return true
		return false

	## Чи лежить p у дворі садиби з макету: усередині обрису паркану чи ближче POLE_FENCE_CLEAR до нього.
	func in_yard(p: Vector2) -> bool:
		for poly: PackedVector2Array in yard_polys:
			if poly.size() < 3:
				continue
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
			for k in poly.size():
				if Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()]).distance_to(p) < PropLayer.POLE_FENCE_CLEAR:
					return true
		return false

	## Обрис паркану двору зі сторін _fence_ring: сторона — на своїй межі клітинок із відступом o назовні; кут двох
	## перпендикулярних сторін — їх перетин, сходинка між паралельними — дві точки на місці переходу. Вирізів паркану
	## навколо перешкод і прорізу воріт обрис не має: двір — суцільний, ворота стереже near_gate.
	static func _ring_polygon(sides: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		var n: int = sides.size()
		for k in n:
			var a: Dictionary = sides[k]
			var b: Dictionary = sides[(k + 1) % n]
			var da := Vector2(a["d"])
			var db := Vector2(b["d"])
			var la: float = float(a["line"]) + (da.x + da.y) * float(a["o"])
			var lb: float = float(b["line"]) + (db.x + db.y) * float(b["o"])
			if absf(da.dot(db)) < 0.5:
				out.append(Vector2(la, lb) if da.x != 0.0 else Vector2(lb, la))
			else:
				var t: Vector2 = b["from"]
				out.append(t + da * float(a["o"]))
				out.append(t + db * float(b["o"]))
		return out

	## Чи перетинає відрізок a–b вісь якоїсь дороги.
	func _crosses_axis(a: Vector2, b: Vector2) -> bool:
		if height == null or height.roads == null:
			return false
		for pts: PackedVector2Array in (height.roads as RoadCourse).lines:
			for k in range(1, pts.size()):
				if Geometry2D.segment_intersects_segment(a, b, pts[k - 1] - Vector2(ring, ring), pts[k] - Vector2(ring, ring)) != null:
					return true
		return false

	## Напрям осі вулиці (одиничний; нуль — доріг нема): відрізок осі, який перетинає дріт from–to, а коли такого нема —
	## найближчий до p (на розвилці найближчий може бути чужою вулицею).
	func street_dir(p: Vector2, from: Vector2 = Vector2.INF, to: Vector2 = Vector2.INF) -> Vector2:
		if height == null or height.roads == null:
			return Vector2.ZERO
		var best: float = INF
		var out := Vector2.ZERO
		for pts: PackedVector2Array in (height.roads as RoadCourse).lines:
			for k in range(1, pts.size()):
				var a: Vector2 = pts[k - 1] - Vector2(ring, ring)
				var b: Vector2 = pts[k] - Vector2(ring, ring)
				if a == b:
					continue
				var dd: float = Geometry2D.get_closest_point_to_segment(p, a, b).distance_squared_to(p)
				if from.is_finite() and Geometry2D.segment_intersects_segment(from, to, a, b) != null:
					dd = -1.0
				if dd < best:
					best = dd
					out = (b - a).normalized()
		return out

	## Точка кріплення відводу від опори pole_i до хати house_i: на стіні з боку стовпа, на висоті DROP_ATTACH_H над
	## ґрунтом; Vector3.INF — відводу нема.
	func _drop_target(house_i: int, pole_i: int) -> Vector3:
		var box: AABB = _box_of(layer._instances[house_i])
		var rect := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		var a: Vector2 = drop_point(rect, _pole_xz(pole_i))
		if not a.is_finite():
			return Vector3.INF
		return Vector3(a.x, ground(a.x, a.y) + PropLayer.DROP_ATTACH_H, a.y)

	func _pole_xz(i: int) -> Vector2:
		var o: Vector3 = (layer._instances[i]["transform"] as Transform3D).origin
		return Vector2(o.x, o.z)

	# --- мости -----------------------------------------------------------------------------

	## Переправа — модель на всю довжину вздовж дороги; настил — на deck_y. Мости своєї карти
	## розкладаються на переправи за порядком уздовж X; інакше — будь-який міст тієї ж довжини. Міст
	## кільця моделі не має: у нього нема й настилу, а правила його не бачать. Підрив буває на одній
	## клітинці, тож змішана переправа — по шматку на клітинку, кожен у власному стані: гравець бачить,
	## яку саме клітинку може відновити інженер. Ціла чи вся зруйнована — одна модель.
	func _bridges() -> void:
		if height == null:
			return
		var groups: Array[Dictionary] = []
		for g in height.bridge_groups():
			if (g["cells"] as Array).all(func(c: Vector2i) -> bool: return on_board(c)):
				groups.append(g)
		groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["centre"] as Vector2).x < (b["centre"] as Vector2).x)
		var own: Array[StringName] = PropLayer.models_of(Kind.BRIDGE).filter(
				func(m: StringName) -> bool: return PropLayer.spec_of(m).get("map", &"") == map_key)
		own.sort_custom(func(a: StringName, b: StringName) -> bool: return int(PropLayer.spec_of(a)["order"]) < int(PropLayer.spec_of(b)["order"]))
		var any: Array[StringName] = PropLayer.models_of(Kind.BRIDGE)
		for i in groups.size():
			var g: Dictionary = groups[i]
			var length: int = _length(g)
			var m: StringName = &""
			if own.size() == groups.size() and _model_length(own[i]) == length:
				m = own[i]
			else:
				for c in any:
					if _model_length(c) == length:
						m = c
						break
			if m == &"":
				push_warning("PropLayer: переправі довжиною %d нема моделі" % length)
				continue
			var axis: Vector2 = g["axis"]
			var cells: Array[Vector2i] = []
			cells.assign(g["cells"])
			# Клітинки за зростанням уздовж осі — у тому ж порядку, що й шматки моделі вздовж локальної Z.
			cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if axis.x != 0.0 else a.y < b.y)
			var broken_m := StringName(String(m) + "_broken")
			if PropLayer.model(broken_m) == null:
				broken_m = m
			var broken: Array = cells.map(func(c: Vector2i) -> bool: return kind(c) == Terrain.Kind.BRIDGE_DESTROYED)
			# Вісь моделі — Z; переправа вздовж X повертається на 90° (локальна +Z → світова +X).
			var turn := Basis() if axis.x == 0.0 else Basis(Vector3.UP, PI * 0.5)
			var centre: Vector2 = g["centre"]
			var y: float = height.deck_y(cells[0]) - float(PropLayer.spec_of(m)["deck_top"])
			var xform := Transform3D(turn, Vector3(centre.x, y, centre.y))
			if not broken.has(true):
				layer._add(m, xform, cells)
			elif not broken.has(false):
				layer._add(broken_m, xform, cells)
			else:
				for k in cells.size():
					var one: Array[Vector2i] = [cells[k]]
					layer._add(StringName("%s#%d" % [broken_m if broken[k] else m, k]), xform, one)

	func _length(g: Dictionary) -> int:
		var axis: Vector2 = g["axis"]
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := -lo
		for c: Vector2i in g["cells"]:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		return (hi.x - lo.x + 1) if axis.x != 0.0 else (hi.y - lo.y + 1)

	func _model_length(m: StringName) -> int:
		return roundi(((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.z)

	# --- дрібні пропси -------------------------------------------------------------------------

	## Прохідна клітинка дошки, де можуть стояти дрібні пропси.
	func open_ground(c: Vector2i) -> bool:
		return on_board(c) and kind(c) == Terrain.Kind.FIELD

	## Пропс уздовж ребра клітинки c з боку d, на KEEP_OUT…0.5 від центру.
	func put_on_edge(m: StringName, c: Vector2i, d: Vector2i, inset: float = 0.44) -> bool:
		var key := Vector4i(c.x, c.y, d.x, d.y)
		if edges.has(key):
			return false
		var yaw: float = 0.0 if d.y != 0 else PI * 0.5
		if put_small(m, c, Vector2(d) * inset, yaw, 1.0, true):
			edges[key] = true
			return true
		return false

	## Огорожа двору — замкнений контур одного типу довкола ділянки: клітинок дошки під будівлями
	## (сусідні будівлі ділять двір), на YARD_OUT за її межею, з хвірткою GATE перед дверима, на
	## дорогу. Порожні клітинки групи BUILDING лишаються за огорожею: обгороджене порожнє місце
	## читається уламком. На опуклих кутах сусідні прольоти подовжуються назустріч, на вгнутих
	## коротшають, тож кути зімкнуті й нічого не стирчить. Де за межею вода чи край дошки, контур
	## уривається: огорожі на воді не буває.
	func _yard_fences() -> void:
		var seen: Dictionary = {}
		var cells: Array = built.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for start: Vector2i in cells:
			if seen.has(start) or not on_board(start) or kind(start) != Terrain.Kind.BUILDING:
				continue
			var lot: Dictionary = {start: true}
			var queue: Array[Vector2i] = [start]
			seen[start] = true
			while not queue.is_empty():
				var q: Vector2i = queue.pop_back()
				for d in Board.DIRS_4:
					var n: Vector2i = q + d
					if built.has(n) and on_board(n) and not seen.has(n) and kind(n) == Terrain.Kind.BUILDING:
						seen[n] = true
						lot[n] = true
						queue.append(n)
			_fence_yard(lot, start)

	func _fence_yard(lot: Dictionary, first: Vector2i) -> void:
		# Один вид паркану двору з FENCE_FORMS на двір (за зерном двору й половиною карти) і ворота того самого роду,
		# як у дворів із макета.
		var palette: Array[StringName] = []
		for f: StringName in PropLayer.FENCE_FORMS:
			if PropLayer.model(StringName(String(f).get_slice("|", 0))) != null:
				palette.append(f)
		if palette.is_empty():
			return
		var base: int = absi(hash(Vector2i(salt, Kind.GARDEN_FENCE))) + half(first)
		var form: StringName = palette[(base + h(first, 121)) % palette.size()]
		var m := StringName(String(form).get_slice("|", 0))
		var hmul: float = float(String(form).get_slice("|", 1))
		var cells: Array = lot.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var sides: Array = []
		for g: Vector2i in cells:
			for d in Board.DIRS_4:
				var c: Vector2i = g + d
				if lot.has(c) or not on_board(c):
					continue
				if kind(c) in [Terrain.Kind.FIELD, Terrain.Kind.ROAD, Terrain.Kind.HILL, Terrain.Kind.BUILDING]:
					sides.append([g, d])
		if sides.is_empty():
			return
		# Хвіртка — перед дверима (фасад будинку) і, де можна, на дорогу.
		var door: Array = sides.filter(func(e: Array) -> bool: return built.get(e[0], Vector2i.ZERO) == e[1])
		var to_road: Array = sides.filter(func(e: Array) -> bool: return kind(e[0] + e[1]) == Terrain.Kind.ROAD)
		var door_road: Array = door.filter(func(e: Array) -> bool: return to_road.has(e))
		var pool: Array = door_road
		for alt: Array in [door, to_road, sides]:
			if pool.is_empty():
				pool = alt
		var gate: Array = pool[h(first, 120) % pool.size()]
		var plans: Array[Dictionary] = []
		for e: Array in sides:
			var plan: Dictionary = _yard_segment(lot, e[0], e[1], e == gate)
			if not plan.is_empty():
				plans.append(plan)
		# Секція, що ні з ким не стикується кінцем, — самотня панель серед двору: її нема.
		for plan in plans:
			var joined := false
			for other in plans:
				if other == plan:
					continue
				for a: Vector2 in plan["ends"]:
					for b: Vector2 in other["ends"]:
						joined = joined or a.distance_to(b) < 0.15
			if not joined:
				continue
			var c: Vector2i = plan["c"]
			if put_small(m, c, plan["local"], plan["yaw"], 1.0, true, plan["length"], hmul):
				edges[plan["key"]] = true
				yard_cells[c] = true
				if plan.has("gate"):
					var from: Vector2 = plan["gate"][0]
					var to: Vector2 = plan["gate"][1]
					layer._gates.append({"a": from, "mid": from + (to - from).normalized() * (GATE_LEAF + GATE_POST_SIZE.x),
							"b": to, "kind": PropLayer.spec_of(m).get("gate", PropLayer.GATE_KINDS[0]), "out": Vector2(plan["out"]),
							"height": GATE_H, "seed": h(first, 173), "clear": 0.0, "along": true, "screen": true})

	## План секції огорожі на ребрі ділянки (без розстановки): {} — секції тут не буде.
	func _yard_segment(lot: Dictionary, g: Vector2i, d: Vector2i, gate: bool) -> Dictionary:
		var c: Vector2i = g + d
		var t := Vector2i(absi(d.y), absi(d.x))
		var ext: Dictionary = {}
		for e: Vector2i in [t, -t]:
			if lot.has(g + e):
				ext[e] = -YARD_OUT if lot.has(c + e) else 0.0
			else:
				ext[e] = YARD_OUT
		# Проліт від lo до hi уздовж t (від центру клітинки); хвіртка вирізає GATE з одного кінця.
		var lo: float = -0.5 - float(ext[-t])
		var hi: float = 0.5 + float(ext[t])
		var opening := Vector2.ZERO
		if gate:
			if h(c, 122) & 1:
				opening = Vector2(lo, lo + GATE)
				lo += GATE
			else:
				opening = Vector2(hi - GATE, hi)
				hi -= GATE
		var key := Vector4i(c.x, c.y, -d.x, -d.y)
		if edges.has(key) or hi - lo < MIN_FENCE:
			return {}
		# Секція тримає ≥ 0.3 клітинки від будь-якої будівлі (зокрема руїни на сусідній клітинці) і
		# не лягає на дорогу: заважає — коротшає з обох кінців, коротша за MIN_FENCE не стає зовсім.
		var cut: float = 0.0
		while not _span_clear(c, d, t, lo + cut, hi - cut):
			cut += 0.05
			if hi - lo - 2.0 * cut < MIN_FENCE:
				return {}
		lo += cut
		hi -= cut
		var base: Vector2 = Vector2(c) - Vector2(d) * (0.5 - YARD_OUT)
		var plan: Dictionary = {"c": c, "key": key, "length": hi - lo, "yaw": 0.0 if d.y != 0 else PI * 0.5,
				"local": base - Vector2(c) + Vector2(t) * ((lo + hi) * 0.5),
				"ends": [base + Vector2(t) * lo, base + Vector2(t) * hi]}
		if gate:
			plan["gate"] = [base + Vector2(t) * opening.x, base + Vector2(t) * opening.y]
			plan["out"] = d
		return plan

	func _span_clear(c: Vector2i, d: Vector2i, t: Vector2i, lo: float, hi: float) -> bool:
		var mid: Vector2 = Vector2(c) - Vector2(d) * (0.5 - YARD_OUT) + Vector2(t) * ((lo + hi) * 0.5)
		var half_t: Vector2 = (Vector2(t) * (hi - lo) * 0.5).abs()
		# Паркан не лягає на дорогу й не висить над водою: секція коротшає, доки не зійде з них.
		for k in 9:
			var q: Vector2 = mid + (Vector2(t) * (hi - lo) * 0.5) * (float(k) / 4.0 - 1.0)
			if on_road(q, ROAD_PAD) or near_wet(q, WATER_CLEAR):
				return false
		var span := Rect2(mid - half_t, half_t * 2.0).grow(0.3 - 1e-3)
		for pl: Array in placed:
			if span.intersects(pl[0]):
				return false
		return true

	## Огорожа поля вздовж дороги: відрізками щонайменше у дві клітинки, з одного боку дороги на
	## відрізок і не біля дворів — подвійні паралельні ряди й самотня секція серед поля читаються
	## помилкою.
	func _field_fences() -> void:
		var picks: Dictionary = {}
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if not open_ground(c) or _near_yard(c):
					continue
				for d in Board.DIRS_4:
					var r: Vector2i = c + d
					if kind(r) != Terrain.Kind.ROAD:
						continue
					var t := Vector2i(absi(d.y), absi(d.x))
					var along: int = r.x if t.x != 0 else r.y
					var across: int = r.y if t.x != 0 else r.x
					var hr: int = h(Vector2i(along / FIELD_FENCE_RUN * 2 + t.x, across), 3)
					if hr % 16 >= FIELD_FENCE_CHANCE:
						continue
					var side: int = 1 if (hr / 16) % 2 == 0 else -1
					if -(d.y if t.x != 0 else d.x) != side:
						continue
					picks[Vector4i(c.x, c.y, d.x, d.y)] = true
		var keys: Array = picks.keys()
		keys.sort()
		for k: Vector4i in keys:
			var t := Vector2i(absi(k.w), absi(k.z))
			if not picks.has(Vector4i(k.x + t.x, k.y + t.y, k.z, k.w)) and not picks.has(Vector4i(k.x - t.x, k.y - t.y, k.z, k.w)):
				continue
			var c := Vector2i(k.x, k.y)
			put_on_edge(pick_for_half(Kind.FIELD_FENCE, half(c)), c, Vector2i(k.z, k.w))

	## Клітинка в межах однієї від двору чи будинку: польова огорожа поруч з огорожею двору читається
	## подвійним рядом.
	func _near_yard(c: Vector2i) -> bool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if yard_cells.has(n) or kind(n) == Terrain.Kind.BUILDING:
					return true
		return false

	## Тюки на луці, купкою в куті клітинки; не біля води, болота й дороги.
	func _hay() -> void:
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if not open_ground(c) or h(c, 5) % 16 >= HAY_CHANCE:
					continue
				var near_bad := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var k: int = kind(c + d)
					near_bad = near_bad or k == Terrain.Kind.WATER or k == Terrain.Kind.MARSH or k == Terrain.Kind.ROAD
				if near_bad:
					continue
				var corner := Vector2(1.0 if h(c, 6) & 1 else -1.0, 1.0 if h(c, 6) & 2 else -1.0) * 0.33
				var m: StringName = pick_for_half(Kind.HAY, half(c))
				# Тюк один чи вільна пара, кожен своїм поворотом: три однакові поруч читаються рядом копій.
				var n: int = 1 + h(c, 7) % 2
				for k in n:
					var off := Vector2(float(h(c, 8 + k) % 100) / 100.0 - 0.5, float(h(c, 12 + k) % 100) / 100.0 - 0.5) * 0.12
					var at: Vector2 = corner + off - corner.normalized() * 0.09 * k
					# Тюки лише край поля: на лузі й у дворі їм не місце.
					if not near_wet(Vector2(c) + at, WATER_CLEAR) and _at_field_edge(Vector2(c) + at):
						put_small(m, c, at, float(h(c, 16 + k) % 628) / 100.0)

	## Точка поза полем, але не далі HAY_EDGE від його краю.
	func _at_field_edge(q: Vector2) -> bool:
		for r: Rect2 in layer.field_edges:
			if not r.has_point(q) and q.distance_to(q.clamp(r.position, r.end)) <= HAY_EDGE:
				return true
		return false

	## Причіп біля подвір'я: один на групу, на полі за огорожею двору (ближче — сама огорожа), уздовж
	## ребра в бік двору.
	func _trailers() -> void:
		var done: Dictionary = {}
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if not open_ground(c) or yard_cells.has(c) or h(c, 20) % 16 >= 4:
					continue
				for d in Board.DIRS_4:
					var f: Vector2i = c + d
					var b: Vector2i = f + d
					if not yard_cells.has(f) or kind(b) != Terrain.Kind.BUILDING or done.has(b / 4) or not house_near(c):
						continue
					if put_on_edge(_trailer_apart(c), c, d, 0.39):
						done[b / 4] = true
					break

	## Бетонні блоки на дорозі біля мосту: блокпост на кожному в'їзді, по блоку з боків дороги.
	func _blocks() -> void:
		var m: StringName = pick_for_half(Kind.BLOCK, 0)
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if kind(c) != Terrain.Kind.ROAD:
					continue
				for d in Board.DIRS_4:
					var k: int = kind(c + d)
					if k != Terrain.Kind.BRIDGE and k != Terrain.Kind.BRIDGE_DESTROYED:
						continue
					var side := Vector2(d.y, d.x).abs()
					var yaw: float = PI * 0.5 if d.y == 0 else 0.0
					# На узбіччі, не на асфальті: put_small відкидає блок на покритті дороги.
					put_small(m, c, side * 0.43 - Vector2(d) * 0.2, yaw + 0.15)
					put_small(m, c, -side * 0.43 - Vector2(d) * 0.3, yaw - 0.1)

	## Каміння на пагорбах: одна-дві брили біля краю клітинки, кожна половина — свої дві породи.
	func _boulders() -> void:
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if kind(c) != Terrain.Kind.HILL:
					continue
				# Одна брила на клітинку, і не на кожній: дрібнота коштувала ~17 тис. трикутників на кадр.
				if h(c, 29) % 3 == 0:
					continue
				var n: int = 1
				var pool: Array[StringName] = PropLayer.models_of(Kind.BOULDER)
				var base: int = absi(hash(Vector2i(salt, Kind.BOULDER))) + half(c) * 2
				for k in n:
					var m: StringName = pool[(base + h(c, 32 + k) % 2) % pool.size()]
					for attempt in 4:
						var a: float = float(h(c, 40 + k * 5 + attempt) % 628) / 100.0
						var r: float = 0.34 + float(h(c, 60 + k) % 10) / 100.0
						var scale: float = float(PropLayer.spec_of(m).get("scale", 1.0)) * (0.85 + float(h(c, 80 + k) % 30) / 100.0)
						if put_small(m, c, Vector2(cos(a), sin(a)) * r, float(h(c, 70 + k) % 628) / 100.0, scale):
							break

	## Опори вздовж доріг: асфальт і ґрунтівка — 10 кВ з прольотом ~7.5 клітинки, вулиці (бруківка)
	## — 0.4 кВ з ~4.5. Опора стоїть за узбіччям на прохідній клітинці біля її краю; сусідні
	## опори однієї лінії з'єднує дріт.
	func _poles() -> void:
		if height == null or height.roads == null:
			return
		var roads: RoadCourse = height.roads
		for li in roads.lines.size():
			var pts: PackedVector2Array = roads.lines[li]
			if pts.size() < 2:
				continue
			var mid: Vector3 = roads.types[li][pts.size() / 2]
			var line: StringName = &"04kv" if mid.z > maxf(mid.x, mid.y) else &"10kv"
			# Ґрунтівки — лише через одну: не кожна польова дорога веде струм.
			if mid.y > maxf(mid.x, mid.z) and h(Vector2i(li, 0), 90) % 2 == 1:
				continue
			var first := Vector2i(roundi(pts[0].x) - ring, roundi(pts[0].y) - ring)
			var m: StringName = pick_for_half(Kind.POLE, half(first),
					func(n: StringName) -> bool: return PropLayer.spec_of(n)["line"] == line)
			if m == &"":
				continue
			var side: float = 1.0 if h(Vector2i(li, 1), 91) & 1 else -1.0
			var step: float = SPAN[line]
			var dist: float = 0.0
			var next: float = step * 0.5
			var prev: int = -1
			for k in range(1, pts.size()):
				var a: Vector2 = pts[k - 1]
				var b: Vector2 = pts[k]
				var seg: float = a.distance_to(b)
				while next <= dist + seg and seg > 0.0:
					var t: float = (next - dist) / seg
					var p: Vector2 = a.lerp(b, t) - Vector2(ring, ring)
					var tan: Vector2 = (b - a) / seg
					var nrm := Vector2(-tan.y, tan.x) * side
					var half_w: float = float(roads.halfs[li][k]) / 8.0
					var pole: int = _pole_at(m, p + nrm * (half_w + 0.3), tan)
					if pole >= 0 and prev >= 0:
						spans.append([prev, pole])
					prev = pole
					next += step
				dist += seg

	func _pole_at(m: StringName, p: Vector2, tan: Vector2) -> int:
		for shift: float in [0.0, 0.3, -0.3, 0.6, -0.6]:
			var q: Vector2 = p + tan * shift
			var c := Vector2i(roundi(q.x), roundi(q.y))
			if not open_ground(c) and not (on_board(c) and kind(c) == Terrain.Kind.HILL):
				continue
			var before: int = layer._instances.size()
			# Траверса впоперек дороги: дроти йдуть уздовж (локальна Z — вздовж дороги).
			if put_small(m, c, q - Vector2(c), atan2(tan.x, tan.y), float(PropLayer.spec_of(m).get("scale", 1.0))):
				return before
		return -1
