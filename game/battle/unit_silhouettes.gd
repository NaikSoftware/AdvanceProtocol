class_name UnitSilhouettes
extends RefCounted
## Тимчасові примітиви-заступники до асетів Фази 5.2: мінімум, що відрізняє 12 типів
## з фіксованого ізо-ракурсу. Ціна — кількість мешів (§8: <= 4 на юніт). Перед — -Z.

## Єдиний колір тіла для всіх власників: сторону показує смуга HP, не фарба юніта.
const BODY_COLOR := Color("4f5240")
const _BARREL_COLOR := Color("2e2b27")  # нейтральний метал
const _STRIPE_COLOR := Color("d9b23a")

## hull — розмір корпусу (1 тайл = 8 м, тож 3,6 м = 0,45); barrel — довжина ствола від центру
## корпусу/башти вперед (0 — без); extras — деталі. Ствол може виступати за корпус: у танка
## він 3,5–7 м від центру тайла. Висота танка = корпус + башта (TURRET_HEIGHT = 0,8 м).
## `roof_gun` — гармата чи кулемет на даху колісної машини: вісь ствола на висоті башти, а коробки-башти немає, бо модель тримає
## ствол у межах корпусу; корінь полум'я на уламках стоїть на висоті башти, як у башти.
## `flame` (лише гармати): два корені полум'я уламка — точки на металі моделі в системі юніта (формула з корпусу
## потрапила б у порожнечу між циліндром і колесом).
## `crew` (лише гармати): де стоять двоє розрахунків у системі юніта — (x, z) і поворот у градусах; ноги на землі,
## 1,8 м, без масштабування. Вони не входять до корпусу: уламки, тінь і дуло рахуються без них.
## `crew_travel` (лише гармати): те саме для похідного положення (станини зведені, на мосту): перед лафетом, збоку від
## ствола, на 0,3 м від моделі, і так, щоб камера бачила обох (свій рядок на гармату: ширша гаубиця
## ховає за лафетом бійця, якого видно біля польової). Між поручнями — лише поперек настилу: вздовж
## нього тайл не обмежений поручнями.
## `body_spots` (лише гармати): місця тіл розрахунку, коли гармату знищено, у системі гармати — (x, z) і курс у градусах;
## `body_legal` — для кожного з восьми напрямів гармати маска тих, що дозволені: поза уламком, яким його малюють, у тайлі
## й на виду з камери. Маску складає tools/crew_body_table.gd; тест порівнює її з перерахунком.
const _SPECS: Array[Dictionary] = [
	{"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures"]},  # 0 стрілецький загін
	{"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures", &"drone_rack"]},  # 1 штурмовий
	{"hull": Vector3(0.3375, 0.30, 0.825), "barrel": 0.33, "wheel": 0.0828, "extras": [&"wheels", &"roof_gun"]},  # 2 бронеавто 2,7×2,4×6,6 м
	{"hull": Vector3(0.3375, 0.325, 0.95), "barrel": 0.10, "wheel": 0.0796, "extras": [&"wheels", &"roof_gun"]},  # 3 транспортер 2,7×2,6×7,6 м
	{"hull": Vector3(0.275, 0.25, 0.6125), "barrel": 0.15, "wheel": 0.0606, "extras": [&"wheels", &"roof_gun"]},  # 4 розвідувальне 2,2×2,0×4,9 м
	{"hull": Vector3(0.43, 0.20, 0.84), "barrel": 0.625, "wheel": 0.036, "extras": [&"turret"]},  # 5 середній танк 3,4×2,4×6,7 м
	{"hull": Vector3(0.4375, 0.1875, 0.9375), "barrel": 0.86, "wheel": 0.045, "extras": [&"turret"]},  # 6 винищувач танків 3,5×2,3×7,5 м
	{"hull": Vector3(0.3675, 0.1875, 0.70), "barrel": 0.46, "wheel": 0.034, "extras": [&"turret"]},  # 7 легкий танк 2,9×2,3×5,6 м
	{"hull": Vector3(0.475, 0.25, 0.90), "barrel": 0.75, "wheel": 0.039, "extras": [&"turret"]},  # 8 важкий танк 3,8×2,8×(корпус 7,2) м
	{"hull": Vector3(0.27, 0.28, 0.34), "barrel": 0.36, "wheel": 0.067, "bore": 0.317, "flame": [Vector3(0.0, 0.27, -0.08), Vector3(0.0, 0.24, 0.02)], "extras": [&"trail"], "crew": [Vector3(0.02, 0.27, 0.0), Vector3(-0.04, 0.43, 0.0)], "crew_travel": [Vector3(-0.12, -0.30, 0.0), Vector3(0.12, -0.28, 0.0)], "body_spots": [Vector3(-0.36, 0.08, 0.0), Vector3(-0.32, -0.08, 135.0), Vector3(-0.2, -0.32, 135.0), Vector3(-0.08, -0.36, 0.0), Vector3(0.2, -0.32, 135.0), Vector3(0.24, -0.28, 45.0), Vector3(0.36, -0.08, 90.0), Vector3(0.36, 0.0, 0.0), Vector3(-0.28, -0.2, 45.0), Vector3(0.36, -0.16, 135.0)], "body_legal": [763, 765, 1023, 895, 1023, 479, 495, 1023]},  # 9 польова гармата: лафет з колесами й щитом; ствол і станини за його межами
	{"hull": Vector3(0.305, 0.40, 0.52), "barrel": 0.73, "wheel": 0.075, "bore": 0.487, "flame": [Vector3(0.0, 0.37, -0.13), Vector3(0.0, 0.34, 0.02)], "extras": [&"trail"], "crew": [Vector3(-0.09, 0.33, 0.0), Vector3(0.13, 0.40, 0.0)], "crew_travel": [Vector3(-0.07, -0.44, 0.0), Vector3(0.10, -0.34, 0.0)], "body_spots": [Vector3(0.0, -0.36, 90.0), Vector3(0.2, -0.32, 135.0), Vector3(-0.16, -0.32, 135.0), Vector3(0.16, -0.32, 45.0), Vector3(-0.32, -0.2, 45.0), Vector3(0.36, -0.16, 135.0), Vector3(0.36, -0.04, 0.0), Vector3(-0.36, -0.16, 45.0), Vector3(-0.12, -0.36, 0.0), Vector3(0.28, -0.24, 45.0)], "body_legal": [619, 875, 891, 958, 413, 407, 469, 762]},  # 10 гаубиця: лафет з колесами; ствол і станини за його межами
	{"hull": Vector3(0.45, 0.22, 0.92), "barrel": 0.0, "wheel": 0.04, "extras": [&"stripe"]},  # 11 інженерна машина: корпус без плуга
]

## Башта: 0,8 м заввишки.
const TURRET_HEIGHT: float = 0.10

## Справжні моделі (docs/art-direction.md, «Unit models»): є файл — тіло з нього, нема — коробки.
## `_SPECS` лишаються метаданими для спалахів, уламків і плям тіні. `wheel` — радіус коліс моделі.
const MODEL_DIR: String = "res://assets/units/"
## Три набори техніки; набір 0 — моделі й `_SPECS` вище, набори 1 і 2 — у підкаталогах set1/, set2/.
const SET_COUNT: int = 3
## Виміри наборів: набір → {тип → рядок як у `_SPECS`}. Модель набору діє лише разом із рядком —
## без нього тип повністю береться з набору 0; тож рядок додають у тому самому коміті, що й GLB.
const _SET_SPECS: Dictionary = {
	1: {
		# відділення набору: ті самі мірки, що в набору 0, бо фігура — 1,8 м на будь-якому наборі;
		# рядок вмикає й моделі
		0: {"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures"]},
		1: {"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures", &"drone_rack"]},
		# важкий танк набору 1: корпус і висота осі ствола виміряні з моделі, дуло й колесо — як у _SPECS
		8: {"hull": Vector3(0.4793, 0.1903, 0.8877), "barrel": 0.75, "wheel": 0.039, "extras": [&"turret"]},
		# середній: корпус і висота осі ствола виміряні з моделі; дуло коротше за _SPECS, щоб відрізнятися від важкого
		5: {"hull": Vector3(0.4260, 0.1605, 0.7830), "barrel": 0.61, "wheel": 0.036, "extras": [&"turret"]},
		# винищувач: без башти, але extras як у _SPECS
		6: {"hull": Vector3(0.4299, 0.2238, 0.8971), "barrel": 0.86, "wheel": 0.045, "extras": [&"turret"]},
		# легкий: корпус вужчий за коробку, бо джерело довше за свою ширину; вісь ствола виміряна
		7: {"hull": Vector3(0.3390, 0.1705, 0.7020), "barrel": 0.46, "wheel": 0.034, "extras": [&"turret"]},
		# бронеавто, транспортер і розвідувальна машина набору 1: корпус виміряний з моделі, висота осі ствола — з осі гармати, колесо — радіус осей
		2: {"hull": Vector3(0.3273, 0.2519, 0.8280), "barrel": 0.30, "wheel": 0.0808, "extras": [&"wheels", &"roof_gun"]},
		3: {"hull": Vector3(0.3331, 0.3276, 0.9540), "barrel": 0.12, "wheel": 0.0753, "extras": [&"wheels", &"roof_gun"]},
		4: {"hull": Vector3(0.2385, 0.2163, 0.6180), "barrel": 0.12, "wheel": 0.0624, "extras": [&"wheels", &"roof_gun"]},
		9: {"hull": Vector3(0.2252, 0.34, 0.30), "barrel": 0.27, "wheel": 0.0677, "bore": 0.357, "flame": [Vector3(0.0, 0.32, -0.08), Vector3(0.0, 0.261, 0.04)], "extras": [&"trail"], "crew": [Vector3(0.02, 0.28, 0.0), Vector3(-0.26, 0.18, 0.0)], "crew_travel": [Vector3(-0.04, -0.26, 0.0), Vector3(0.12, -0.26, 0.0)], "body_spots": [Vector3(-0.2, -0.28, 135.0), Vector3(0.08, -0.36, 90.0), Vector3(0.24, -0.28, 45.0), Vector3(-0.12, -0.36, 0.0), Vector3(0.36, -0.04, 0.0), Vector3(0.32, -0.2, 135.0), Vector3(-0.28, -0.24, 45.0), Vector3(0.36, 0.04, 90.0), Vector3(-0.04, -0.36, 0.0), Vector3(-0.04, -0.28, 90.0)], "body_legal": [958, 895, 991, 1007, 959, 367, 987, 245]},  # 9 польова гармата набору 1: лафет з колесами; ствол, станини й ящики за його межами
		10: {"hull": Vector3(0.317, 0.39, 0.30), "barrel": 0.785, "wheel": 0.0813, "bore": 0.537, "flame": [Vector3(0.0, 0.374, -0.08), Vector3(0.0, 0.336, 0.04)], "extras": [&"trail"], "crew": [Vector3(-0.18, 0.44, 0.0), Vector3(-0.34, 0.2, 0.0)], "crew_travel": [Vector3(-0.04, -0.34, 0.0), Vector3(0.1, -0.28, 0.0)], "body_spots": [Vector3(-0.04, -0.36, 90.0), Vector3(0.04, -0.36, 90.0), Vector3(-0.36, -0.12, 45.0), Vector3(0.36, -0.08, 0.0), Vector3(-0.28, -0.16, 135.0), Vector3(-0.04, -0.28, 0.0), Vector3(-0.16, -0.36, 135.0), Vector3(0.32, -0.2, 45.0), Vector3(0.12, -0.32, 45.0)], "body_legal": [427, 491, 443, 471, 311, 375, 111, 220]},  # 10 гаубиця набору 1: лафет з колесами; ствол і станини за його межами
		11: {"hull": Vector3(0.44, 0.185, 0.89), "barrel": 0.0, "wheel": 0.0469, "flame": [Vector3(-0.08, 0.39, -0.1), Vector3(0.0, 0.228, 0.05)], "extras": [&"stripe"]},  # 11 інженерна машина набору 1: корпус без відвалу й стріли
	},
	2: {
		# відділення набору: ті самі мірки, що в набору 0, бо фігура — 1,8 м на будь-якому наборі;
		# рядок вмикає й моделі
		0: {"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures"]},
		1: {"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures", &"drone_rack"]},
		5: {"hull": Vector3(0.4083, 0.1487, 0.8040), "barrel": 0.625, "wheel": 0.036, "extras": [&"turret"]},  # середній (набір 2) 3,4×6,7 м
		6: {"hull": Vector3(0.4350, 0.2726, 0.9423), "barrel": 0.86, "wheel": 0.045, "extras": [&"turret"]},  # винищувач (набір 2) 3,5×7,6 м
		7: {"hull": Vector3(0.3585, 0.153, 0.705), "barrel": 0.46, "wheel": 0.034, "extras": [&"turret"]},  # легкий (набір 2) 2,9×5,6 м
		8: {"hull": Vector3(0.4712, 0.175, 0.9031), "barrel": 0.75, "wheel": 0.0391, "extras": [&"turret"]},  # важкий (набір 2) 3,8×7,2 м
		# бронеавто, транспортер і розвідувальна машина набору 2: так само виміряні з моделей
		2: {"hull": Vector3(0.3271, 0.2734, 0.8280), "barrel": 0.30, "wheel": 0.0833, "extras": [&"wheels", &"roof_gun"]},
		3: {"hull": Vector3(0.3348, 0.3633, 0.9450), "barrel": 0.12, "wheel": 0.0813, "extras": [&"wheels", &"roof_gun"]},
		4: {"hull": Vector3(0.2530, 0.2315, 0.6192), "barrel": 0.12, "wheel": 0.0642, "extras": [&"wheels", &"roof_gun"]},
		9: {"hull": Vector3(0.237, 0.29, 0.30), "barrel": 0.383, "wheel": 0.0632, "bore": 0.319, "flame": [Vector3(0.0, 0.275, -0.08), Vector3(0.0, 0.233, 0.04)], "extras": [&"trail"], "crew": [Vector3(0.02, 0.3, 0.0), Vector3(-0.22, 0.16, 0.0)], "crew_travel": [Vector3(0.18, 0.3, 0.0), Vector3(0.14, -0.16, 0.0)], "body_spots": [Vector3(-0.08, -0.36, 90.0), Vector3(0.24, -0.28, 135.0), Vector3(-0.36, 0.08, 90.0), Vector3(0.36, -0.08, 0.0), Vector3(-0.36, 0.16, 45.0), Vector3(-0.36, -0.04, 90.0), Vector3(-0.2, -0.28, 135.0), Vector3(-0.32, -0.12, 135.0), Vector3(0.08, -0.36, 90.0), Vector3(0.32, -0.2, 135.0)], "body_legal": [959, 895, 1023, 1023, 1023, 223, 1023, 1023]},  # 9 польова гармата набору 2: лафет з колесами; ствол, станини й ящики за його межами
		10: {"hull": Vector3(0.348, 0.435, 0.30), "barrel": 0.59, "wheel": 0.067, "bore": 0.581, "flame": [Vector3(0.0, 0.425, -0.08), Vector3(0.0, 0.359, 0.04)], "extras": [&"trail"], "crew": [Vector3(0.0, 0.34, 0.0), Vector3(-0.26, 0.14, 0.0)], "crew_travel": [Vector3(-0.06, -0.32, 0.0), Vector3(0.12, -0.26, 0.0)], "body_spots": [Vector3(0.03, -0.36, 90.0), Vector3(-0.03, -0.36, 90.0), Vector3(-0.36, 0.12, 90.0), Vector3(0.36, -0.06, 0.0), Vector3(-0.36, 0.06, 90.0), Vector3(-0.36, -0.06, 150.0), Vector3(-0.09, -0.33, 60.0), Vector3(-0.36, 0.0, 90.0), Vector3(0.33, 0.0, 0.0), Vector3(-0.36, 0.18, 60.0), Vector3(0.09, -0.33, 120.0), Vector3(-0.03, -0.3, 60.0), Vector3(0.36, 0.15, 60.0), Vector3(0.36, 0.09, 0.0), Vector3(0.36, 0.21, 0.0), Vector3(0.03, -0.3, 120.0), Vector3(-0.33, 0.24, 150.0), Vector3(0.36, -0.15, 150.0), Vector3(-0.36, 0.12, 150.0), Vector3(-0.36, -0.03, 150.0), Vector3(0.0, -0.36, 90.0), Vector3(-0.36, 0.12, 60.0)], "body_legal": [1172895, 1060171, 1075531, 1089271, 1148055, 3932193, 1076191, 135836]},  # 10 гаубиця набору 2: лафет з колесами; ствол і станини за його межами
		11: {"hull": Vector3(0.475, 0.225, 0.9475), "barrel": 0.0, "wheel": 0.0463, "flame": [Vector3(0.0, 0.322, -0.04), Vector3(0.0, 0.32, 0.08)], "extras": [&"stripe"]},  # 11 інженерна машина набору 2: корпус без плуга
	},
}
## Чинні рядки: таблиця вище, а тести підміняють їх через `use_set_specs()`.
static var _set_specs: Dictionary = _SET_SPECS.duplicate(true)
const MODEL_SLUGS: Array[String] = [
	"rifle_soldier", "assault_soldier", "armoured_car", "troop_carrier", "scout_car", "medium_tank",
	"tank_destroyer", "light_tank", "heavy_tank", "field_gun", "howitzer", "engineer_vehicle",
]
const _MODEL_SHADER: Shader = preload("res://game/battle/shaders/unit_model.gdshader")
const _FALLEN_SHADER: Shader = preload("res://game/battle/shaders/unit_fallen.gdshader")
## Сітка моделі за (набір, тип) у системі юніта (null — файлу нема); у відділення — одна фігура.
static var _models: Dictionary = {}
## Тести підставляють сітки самі: тоді типи поза словником — без моделі, диск не читається.
static var _models_pinned: bool = false
static var _model_materials: Dictionary = {}

static var _materials: Dictionary = {}
## Злита сітка тіла за типом і кольором власника: один меш на всі юніти того самого вигляду.
static var _merged_meshes: Dictionary = {}
static var _merged_material: StandardMaterial3D
static var _figure_mesh: BoxMesh
static var _figure_material: StandardMaterial3D

## Фігура відділення: 1,8 × 0,5 м (1 тайл = 8 м). Колір дає екземпляр MultiMesh — живі в
## кольорі власника, загиблі темні (L* 20–28), тож уся четвірка — один виклик малювання.
const FIGURE_SIZE: Vector3 = Vector3(0.0625, 0.225, 0.05)
const FALLEN_COLOR: Color = Color("3a342c")
## Квадрат зі стороною 0,2 (1,6 м), повернутий на 22,5°: кожна пара бійців лежить під 22,5° до будь-якого з
## восьми напрямів погляду камери на відділення, тож поперек погляду їх розділяє щонайменше 0,38 сторони.
## Рівний ромб по осях ставив двох одного за одним на кожному другому напрямі. Перші два — передні.
const _FIGURE_SLOTS: Array[Vector2] = [Vector2(-0.0541, -0.1306), Vector2(0.1306, -0.0541), Vector2(-0.1306, 0.0541), Vector2(0.0541, 0.1306)]
## Сталий поворот кожного місця, рад: четверо однаково повернутих бійців читаються як клони. Середнє
## близьке до нуля, тож відділення далі дивиться туди, куди його напрям.
const _FIGURE_YAW: Array[float] = [-0.24, 0.12, 0.3, -0.12]
## Куди лежить кожен загиблий (рад від напряму відділення): різні напрями читаються як «упали», а не «лягли строєм».
const _LIE_YAW: Array[float] = [0.35, -1.9, 2.6, -0.6]
## Тип, чия модель — простий боєць кожного відділення: у штурмовому без труби дрона стоїть він. Тіла
## лягають теж ним — трубу загиблий лишає.
const PLAIN_FIGURE: int = 0


## Кінчик ствола в локальних координатах юніта: звідси вилітає спалах.
static func muzzle(type_id: int, set_id: int = 0) -> Vector3:
	return Vector3(0.0, barrel_y(type_id, set_id), -float(spec(type_id, set_id).barrel))


## Висота осі ствола: у башті — посередині неї, у піднятого ствола — виміряна `bore` рядка, інакше — з корпусу.
static func barrel_y(type_id: int, set_id: int = 0) -> float:
	var s: Dictionary = spec(type_id, set_id)
	if s.has("bore"):
		# піднятий ствол: висота дульного зрізу виміряна з моделі, а не виведена з корпусу
		return float(s.bore)
	var h: float = (s.hull as Vector3).y
	var extras: Array = s.extras
	if extras.has(&"turret") or extras.has(&"roof_gun"):
		return h + TURRET_HEIGHT * 0.5
	return h * 0.5


## Рядок набору діє лише разом з його моделлю: без неї тип — це модель і рядок набору 0.
static func spec(type_id: int, set_id: int = 0) -> Dictionary:
	var resolved: int = _resolved_set(type_id, set_id)
	return _SPECS[type_id] if resolved == 0 else (_set_specs[resolved] as Dictionary)[type_id]


## Набір — це місце гравця: власник 4 носить набір 1.
static func set_of(owner: int) -> int:
	return owner % SET_COUNT


## Матеріали спільні між усіма юнітами одного кольору (батчинг).
static func shared_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_materials[color] = mat
	return _materials[color]


static func build(type_id: int, set_id: int = 0) -> Node3D:
	var s: Dictionary = spec(type_id, set_id)
	var hull_size: Vector3 = s.hull
	var extras: Array = s.extras
	var root := Node3D.new()
	var hull := _box(root, "Hull", hull_size, Vector3(0, hull_size.y * 0.5, 0), BODY_COLOR)

	var top := hull_size.y
	if extras.has(&"turret"):
		_box(root, "Turret", Vector3(hull_size.x * 0.6, TURRET_HEIGHT, hull_size.z * 0.5), Vector3(0, top + TURRET_HEIGHT * 0.5, 0), BODY_COLOR)
		top += TURRET_HEIGHT
	if extras.has(&"stripe"):
		_box(root, "Stripe", Vector3(hull_size.x + 0.01, 0.02, hull_size.z * 0.3), Vector3(0, hull_size.y + 0.01, 0), _STRIPE_COLOR)
	if extras.has(&"figures"):
		root.add_child(figures(4, BODY_COLOR))
	if extras.has(&"drone_rack"):
		_box(root, "DroneRack", Vector3(0.30, 0.10, 0.12), Vector3(0, hull_size.y + 0.05, hull_size.z * 0.5 - 0.06), _BARREL_COLOR)
	if extras.has(&"wheels"):
		# одна ширша плита під корпусом замість чотирьох коліс — економія мешів
		_box(root, "Wheels", Vector3(hull_size.x + 0.05, 0.10, hull_size.z * 0.75), Vector3(0, 0.05, 0), _BARREL_COLOR)
	if extras.has(&"trail"):
		# станина лафета позаду гармати: разом з корпусом дає 5–6 м довжини
		var trail_len: float = hull_size.z * 1.05
		_box(root, "Trail", Vector3(hull_size.x * 0.25, 0.03, trail_len), Vector3(0, 0.015, (hull_size.z + trail_len) * 0.5), _BARREL_COLOR)

	var barrel_len: float = s.barrel
	if barrel_len > 0.0:
		var thick := 0.07 if barrel_len > 0.6 else 0.05
		_box(root, "Barrel", Vector3(thick, thick, barrel_len), Vector3(0, barrel_y(type_id, set_id), -barrel_len * 0.5), _BARREL_COLOR)
	return root


## Той самий силует, але корпус, башта, ствол, ходова й фігури відділення — одна сітка `Hull` з
## кольорами у вершинах (однаковими для всіх власників):
## один виклик малювання й один у тіні замість трьох-п'яти на юніт (§8). `standing` — скільки
## фігур стоїть; `drones` — скільки з них несе трубу дрона.
static func build_merged(type_id: int, standing: int = -1, set_id: int = 0, drones: int = 0, layout: int = 0, travel: bool = false) -> Node3D:
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	# `travel`: гармата на мосту — у похідному положенні (станини зведені), якщо модель такого вигляду є
	travel = travel and travel_mesh(type_id, set_id) != null
	if travel:
		hull.mesh = travel_mesh(type_id, set_id)
		hull.material_override = model_material(type_id, set_id, true)
	else:
		hull.mesh = merged_mesh(type_id, standing, set_id, drones, layout)
		if has_model(type_id, set_id):
			hull.material_override = model_material(type_id, set_id)
		else:
			hull.material_override = _merged_mat()
	var out := Node3D.new()
	out.add_child(hull)
	var crew_m: ArrayMesh = crew_mesh(type_id, set_id, travel)
	if crew_m != null:
		# Розрахунок — окремий вузол зі своїм матеріалом: атлас бійця не дістати з атласу гармати. Це один виклик
		# малювання зверху на гармату, а не на бійця.
		var crew := MeshInstance3D.new()
		crew.name = "Crew"
		crew.mesh = crew_m
		crew.material_override = model_material(PLAIN_FIGURE, set_id) if has_model(PLAIN_FIGURE, set_id) else _merged_mat()
		out.add_child(crew)
	return out


static func _merged_mat() -> StandardMaterial3D:
	if _merged_material == null:
		_merged_material = StandardMaterial3D.new()
		_merged_material.vertex_color_use_as_albedo = true
		_merged_material.vertex_color_is_srgb = true
	return _merged_material


## Меш тіла на тип і кількість стоячих фігур; спільний для всіх юнітів того
## самого вигляду, тож падіння фігури — підміна меша, а не новий. Відділення несе лише
## стоячих: загиблі лежать там, де впали (шар тіл WreckLayer), а не йдуть із ним.
## Труб дрона на відділенні стільки, скільки дронів лишилось (§3.9, число публічне), і несуть їх
## перші стоячі місця — вони падають останніми; решта — простий боєць (`PLAIN_FIGURE`). Модель із
## трубою має той самий атлас, що й простий боєць, тож обидва малює її матеріал одним викликом.
## Ключ кешу злитих мешів (merged_mesh): набір, тип, стоячі, труби, розкладка, напрям.
static func _merged_key(type_id: int, standing: int, set_id: int, drones: int, layout: int, face: int) -> String:
	var has_figures: bool = (spec(type_id, set_id).extras as Array).has(&"figures")
	var up: int = _FIGURE_SLOTS.size() if standing < 0 else clampi(standing, 0, _FIGURE_SLOTS.size())
	var model: ArrayMesh = model_mesh(type_id, set_id)
	var plain: ArrayMesh = model_mesh(PLAIN_FIGURE, set_id) if model != null else null
	var tubes: int = clampi(drones, 0, up) if plain != null and plain != model else 0
	return "%d:%d:%s:%d:%d:%d:%d" % [_resolved_set(type_id, set_id), type_id, "model" if model != null else "box", up if has_figures else 0, tubes, layout, face if has_figures else 0]


## Чи меш уже злитий (кеш merged_mesh): тоді виклик нічого не будує.
static func merged_cached(type_id: int, standing: int, set_id: int, drones: int, layout: int, face: int) -> bool:
	return _merged_meshes.has(_merged_key(type_id, standing, set_id, drones, layout, face))


## `face` — напрям відділення (0–7): меш будується у світових осях (вузол відділення повертають назад), і в
## неї вписаний поворот самих фігур.
static func merged_mesh(type_id: int, standing: int = -1, set_id: int = 0, drones: int = 0, layout: int = 0, face: int = 0) -> ArrayMesh:
	var has_figures: bool = (spec(type_id, set_id).extras as Array).has(&"figures")
	var up: int = _FIGURE_SLOTS.size() if standing < 0 else clampi(standing, 0, _FIGURE_SLOTS.size())
	var model: ArrayMesh = model_mesh(type_id, set_id)
	if model != null and not has_figures:
		return model
	var plain: ArrayMesh = model_mesh(PLAIN_FIGURE, set_id) if model != null else null
	var tubes: int = clampi(drones, 0, up) if plain != null and plain != model else 0
	var key: String = _merged_key(type_id, standing, set_id, drones, layout, face)
	if _merged_meshes.has(key):
		return _merged_meshes[key]
	if model != null:
		var bare_mesh: ArrayMesh = plain if plain != null else model
		var crouch: ArrayMesh = crouch_mesh(set_id)
		var with_tube: Array[Transform3D] = []
		var bare: Array[Transform3D] = []
		var crouched: Array[Transform3D] = []
		for i in up:
			var xf: Transform3D = model_figure_transform(i, layout, deg_to_rad(UnitView._degrees_for_facing(face)))
			if i < tubes:
				with_tube.append(xf)
			elif crouch != null and CROUCH_SLOTS.has(i):
				crouched.append(xf)
			else:
				bare.append(xf)
		# Без жодного стоячого — порожній меш: вузол знищеного відділення нічого не малює.
		_merged_meshes[key] = _merge_parts([[model, with_tube], [bare_mesh, bare], [crouch, crouched]]) if up > 0 else ArrayMesh.new()
		return _merged_meshes[key]
	var root := build(type_id, set_id)
	var pieces: Array[Array] = []  ## [масиви меша, перетворення, колір]
	for part: Node in root.get_children():
		if part is MeshInstance3D:
			var mi := part as MeshInstance3D
			pieces.append([mi.mesh.surface_get_arrays(0), Transform3D(Basis(), mi.position), (mi.material_override as StandardMaterial3D).albedo_color])
		elif part is MultiMeshInstance3D:
			for i in up:
				pieces.append([_figure_mesh.surface_get_arrays(0), figure_transform(i, true, layout), BODY_COLOR])
	root.free()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for piece: Array in pieces:
		var src: Array = piece[0]
		var xf: Transform3D = piece[1]
		var base: int = v.size()
		var src_v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var src_n: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		for i in src_v.size():
			v.append(xf * src_v[i])
			n.append(xf.basis * src_n[i])
			c.append(piece[2])
		for i: int in src[Mesh.ARRAY_INDEX]:
			idx.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_merged_meshes[key] = mesh
	return mesh


## Боєць розрахунку гармати: стоїть на землі в точці (x, z), обличчям у бік `yaw` (градуси довкола Y), `lift` — висота центру меша.
static func _crew_transform(c: Vector3, lift: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(c.z)), Vector3(c.x, lift, c.y))


static func _crew_box() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = FIGURE_SIZE
	return b


## Двоє бійців розрахунку гармати одним мешем (рядок `crew`): справжній боєць набору (`PLAIN_FIGURE`, ступні на землі,
## 1,8 м, без масштабування), поки є його модель, інакше коробка-фігура. Другий боєць — у присіді (як заряджаючий), коли
## набір його має: стоячі з гвинтівками разом читались двома стрілками. Меш має атлас бійця, тож малюється його
## матеріалом. Кеш — за гарматою й розв'язаним набором бійця: набір без власного бійця бере набір 0.
static func crew_mesh(type_id: int, set_id: int = 0, travel: bool = false) -> ArrayMesh:
	var crew: Array = crew_rows(type_id, set_id, travel)
	if crew.is_empty():
		return null
	var key := "crew:%d:%d:%d:%s:%s" % [_resolved_set(type_id, set_id), type_id, _resolved_set(PLAIN_FIGURE, set_id), has_model(PLAIN_FIGURE, set_id), travel]
	if _merged_meshes.has(key):
		return _merged_meshes[key]
	var soldier: ArrayMesh = model_mesh(PLAIN_FIGURE, set_id)
	var xfs: Array[Transform3D] = []
	for c: Vector3 in crew:
		xfs.append(_crew_transform(c, 0.0 if soldier != null else FIGURE_SIZE.y * 0.5))
	var parts: Array = []
	if soldier == null:
		parts.append([_crew_box(), xfs])
	else:
		var kneel: ArrayMesh = crouch_mesh(set_id)
		for i in xfs.size():
			var one: Array[Transform3D] = [xfs[i]]
			parts.append([kneel if i == 1 and kneel != null else soldier, one])
	var a: Array = _merge_parts(parts).surface_get_arrays(0)
	# Маски колеса й гусениці та вісь UV2 — для техніки: боєць їх не має й крутитись не мусить.
	var n: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var colours := PackedColorArray()
	colours.resize(n)
	colours.fill(Color.BLACK if soldier != null else BODY_COLOR)
	a[Mesh.ARRAY_COLOR] = colours
	var zero := PackedVector2Array()
	zero.resize(n)
	a[Mesh.ARRAY_TEX_UV2] = zero
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	_merged_meshes[key] = mesh
	return mesh


## Місця розрахунку гармати: у похідному положенні (на мосту) — рядок `crew_travel`, бо між станинами, зведеними докупи, стояти ніде.
static func crew_rows(type_id: int, set_id: int = 0, travel: bool = false) -> Array:
	var row: Dictionary = spec(type_id, set_id)
	if travel and row.has("crew_travel"):
		return row.crew_travel
	return row.get("crew", [])


## Де стоїть розрахунок у системі юніта: стопи кожного — для тіні-контакту.
static func crew_feet(type_id: int, set_id: int = 0, travel: bool = false) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c: Vector3 in crew_rows(type_id, set_id, travel):
		out.append(Vector3(c.x, 0.0, c.y))
	return out


## Четвірка фігур одним MultiMesh: стоять перші `standing`, решта лежить на тих самих місцях.
static func figures(standing: int, stand_color: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _figure_box()
	mm.instance_count = _FIGURE_SLOTS.size()
	var mi := MultiMeshInstance3D.new()
	mi.name = "Figures"
	mi.multimesh = mm
	mi.material_override = _figure_material
	set_standing(mi, standing, stand_color)
	return mi


static func _figure_box() -> BoxMesh:
	if _figure_mesh == null:
		_figure_mesh = BoxMesh.new()
		_figure_mesh.size = FIGURE_SIZE
		_figure_material = StandardMaterial3D.new()
		_figure_material.vertex_color_use_as_albedo = true
		_figure_material.vertex_color_is_srgb = true
	return _figure_mesh


## Загибла фігура лежить уздовж землі на своєму місці, ледь зсунута вбік: не стоїть і не
## здіймається над основою — загиблі не перешкода.
static func set_standing(mi: MultiMeshInstance3D, standing: int, stand_color: Color) -> void:
	var mm: MultiMesh = mi.multimesh
	for i in mm.instance_count:
		mm.set_instance_transform(i, figure_transform(i, i < standing))
		mm.set_instance_color(i, stand_color if i < standing else FALLEN_COLOR)


## Коробка-заступник на місці `i` розкладки `layout` (центр коробки) у системі відділення, чия основа на 0,05
## над його початком. Лежачу коробку малює лише `build()`: тіла в бою — шар тіл (WreckLayer).
static func figure_transform(i: int, standing: bool, layout: int = 0) -> Transform3D:
	var s: Vector3 = _slot(layout, i)
	if standing:
		return Transform3D(Basis(Vector3.UP, s.z), Vector3(s.x, 0.05 + FIGURE_SIZE.y * 0.5, s.y))
	var b := Basis(Vector3.UP, _LIE_YAW[i]) * Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(b, Vector3(s.x * 1.2, 0.05 + FIGURE_SIZE.z * 0.5, s.y * 1.2))


## Стоячий боєць-модель на місці `i` розкладки `layout` (ступні моделі на y = 0) у тій самій системі;
## `face_yaw` — напрям відділення: місце в світі стале, повертається лише фігура.
static func model_figure_transform(i: int, layout: int = 0, face_yaw: float = 0.0) -> Transform3D:
	var s: Vector3 = _slot(layout, i)
	return Transform3D(Basis(Vector3.UP, s.z + face_yaw), Vector3(s.x, 0.05, s.y))


## Розкладки місць — у світі, не в системі відділення: камера не обертається, тож місця розставлені вздовж
## осі «поперек погляду» через ~0,76 м і зигзагом уздовж погляду, і жоден поворот відділення не ставить двох
## бійців один за одним (повертаються лише самі фігури, `face_yaw`). Розкладка — перестановка місць між
## бійцями, сталий зсув до ±0,06 м поперек і ±0,24 м уздовж і поворот фігури до ±20°; сід — номер розкладки.
const LAYOUT_COUNT: int = 8
const _ACROSS: Array[float] = [-0.1425, -0.0475, 0.0475, 0.1425]
const _ALONG: Array[float] = [0.045, -0.06, 0.06, -0.045]
const _LAYOUT_SHIFT: float = 0.0075
const _LAYOUT_DEPTH: float = 0.03
const _LAYOUT_TURN: float = 0.35
## Щонайменше стільки (одиниць світу поперек погляду камери, 0,6 м) між стоячими: ширина бійця з проміжком.
const MIN_SCREEN_GAP: float = 0.075
static var _layouts: Array = []


## (x, z, поворот) місця `i` розкладки `layout` у світових осях (поворот — фігури відносно напряму відділення).
static func _slot(layout: int, i: int) -> Vector3:
	if _layouts.is_empty():
		var cam: float = deg_to_rad(IsoCameraRig.YAW_DEGREES)
		var across := Vector2(cos(cam), -sin(cam))
		var along := Vector2(sin(cam), cos(cam))
		for k in LAYOUT_COUNT:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7919 * (k + 1)
			var order: Array[int] = [0, 1, 2, 3]
			if k > 0:
				for n in range(order.size() - 1, 0, -1):
					var m: int = rng.randi_range(0, n)
					var t: int = order[n]
					order[n] = order[m]
					order[m] = t
			var slots: Array[Vector3] = []
			for j in order.size():
				var u: float = _ACROSS[order[j]]
				var w: float = _ALONG[order[j]]
				var turn: float = _FIGURE_YAW[j]
				if k > 0:
					u += rng.randf_range(-_LAYOUT_SHIFT, _LAYOUT_SHIFT)
					w += rng.randf_range(-_LAYOUT_DEPTH, _LAYOUT_DEPTH)
					turn += rng.randf_range(-_LAYOUT_TURN, _LAYOUT_TURN)
				var at: Vector2 = across * u + along * w
				slots.append(Vector3(at.x, at.y, turn))
			_layouts.append(slots)
	return _layouts[layout][i]


## Найменший проміжок між першими `up` стоячими розкладки `layout` поперек погляду камери: менший за ширину
## бійця — і з камери двоє зливаються в одну фігуру з двома головами. Напряму відділення тут нема — місця
## стоять у світі, повертаються лише фігури.
static func screen_gap(layout: int, up: int) -> float:
	var cam: float = deg_to_rad(IsoCameraRig.YAW_DEGREES)
	var across := Vector2(cos(cam), -sin(cam))
	var xs: Array[float] = []
	for i in up:
		var s: Vector3 = _slot(layout, i)
		xs.append(Vector2(s.x, s.y).dot(across))
	var gap: float = INF
	for i in xs.size():
		for j in range(i + 1, xs.size()):
			gap = minf(gap, absf(xs[i] - xs[j]))
	return gap


## Розкладка відділення `seed` (id юніта): перша, починаючи від сіда, де жодні два з
## чотирьох не стоять один за одним уздовж погляду; коли такої нема — найкраща. Обирається за всіма чотирма,
## тож годиться для будь-якої кількості стоячих: коли фігура падає, решта не перескакує.
static func pick_layout(seed: int) -> int:
	var up: int = _FIGURE_SLOTS.size()
	var best: int = 1
	var best_gap: float = -1.0
	for n in LAYOUT_COUNT - 1:
		var k: int = 1 + posmod(seed + n, LAYOUT_COUNT - 1)
		var gap: float = screen_gap(k, up)
		if gap >= MIN_SCREEN_GAP:
			return k
		if gap > best_gap:
			best_gap = gap
			best = k
	return best


## Загиблий — окрема модель (`rifle_soldier_body.glb`): лежить на боці, ноги зігнуті, гвинтівка поруч, а
## не стоячий боєць, покладений долілиць. Той самий атлас, що й у простого бійця, тож матеріал — його ж,
## лише з `fallen`. Без файлу — коробка-заступник плазом.
const BODY_SLUG: String = "rifle_soldier_body"
## Ключ сітки тіла в `use_models()` для тестів (тип такого номера не існує).
const BODY_KEY: int = 100
## Місця, де простий боєць пригнувся (друга поза); решта стоїть.
const CROUCH_SLOTS: Array[int] = [1, 3]


## Сітка загиблого набору (null — файлу нема): найнижча точка на y = 0, середина тіла на початку.
static func body_mesh(set_id: int, pose: int = 0) -> ArrayMesh:
	return _figure_variant(set_id, BODY_KEY + pose * 10, BODY_SLUG + BODY_POSES[pose])


## Пози загиблого: на боці, ниць, на спині — різні, щоб тіла знищеного відділення не лежали парадом. Ключ
## у `use_models()` — `BODY_KEY + 10 · поза`.
const BODY_POSES: Array[String] = ["", "_prone", "_back"]


## Скільки поз загиблого має набір (щонайменше одна: без файлів — коробка).
static func body_pose_count(set_id: int) -> int:
	var n: int = 1
	for pose in range(1, BODY_POSES.size()):
		if body_mesh(set_id, pose) != null:
			n = pose + 1
		else:
			break
	return n


## Друга поза простого бійця — пригнувся (`rifle_soldier_crouch.glb`): та сама модель і атлас, лише ноги
## зігнуті, тож відділення з обома позами — один матеріал і один виклик. Її беруть непарні місця без труби
## дрона (`CROUCH_SLOTS`), щоб четверо не стояли в одній позі. Null — файлу нема: усі стоять.
const CROUCH_SLUG: String = "rifle_soldier_crouch"
const CROUCH_KEY: int = 101


static func crouch_mesh(set_id: int) -> ArrayMesh:
	return _figure_variant(set_id, CROUCH_KEY, CROUCH_SLUG)


## Окрема модель бійця набору (загиблий, друга поза) — поруч із простим бійцем і з його набору.
static func _figure_variant(set_id: int, key_id: int, slug: String) -> ArrayMesh:
	var resolved: int = _resolved_set(PLAIN_FIGURE, set_id)
	var key := Vector2i(resolved, key_id)
	if not _models.has(key):
		var path: String = model_dir(resolved) + slug + ".glb"
		_models[key] = _load_model(path) if not _models_pinned and ResourceLoader.exists(path) else null
	return _models[key]


static var _fallen_materials: Dictionary = {}


const FALLEN_SPECULAR: float = 0.1
## Відтінок альбедо загиблих набору — множник кольору в sRGB: `albedo_color` у шейдері має підказку
## `source_color`, тож
## Godot переводить колір у лінійний простір сам. Піскова тканина набору 2 темніла до тону ґрунту
## під хмарами
## (L* 24,5 на ґрунті 25,2), і тіло читалось грудкою землі: світліше, але не вище за ґрунт + 2 L*. У
## набору 1 тепле
## забарвлення загиблих зсувало тон зеленої тканини жовтіше за живих, і трохи холодніший множник
## гасить цей зсув.
const FALLEN_TINT: Dictionary = {1: Color(0.985, 1.0, 1.015), 2: Color(1.08, 1.08, 1.08)}


## Матеріал загиблих набору: матеріал простого бійця з шейдером `unit_fallen` (темнить), один на набір, тож
## увесь шар тіл набору — один виклик малювання. Без моделі — темний колір коробок.
static func fallen_material(set_id: int) -> Material:
	var key: int = _resolved_set(PLAIN_FIGURE, set_id)
	if not _fallen_materials.has(key):
		if body_mesh(set_id) != null and has_model(PLAIN_FIGURE, set_id):
			var m := model_material(PLAIN_FIGURE, set_id).duplicate() as ShaderMaterial
			m.shader = _FALLEN_SHADER
			# Мокра від багна тканина не блищить: з відблиском бійця тіло під сонцем сіріло.
			m.set_shader_parameter("specular", FALLEN_SPECULAR)
			m.set_shader_parameter("roughness", 1.0)
			var tint: Variant = m.get_shader_parameter("albedo_color")
			if FALLEN_TINT.has(key) and tint is Color:
				var c: Color = tint
				var t: Color = FALLEN_TINT[key]
				m.set_shader_parameter("albedo_color", Color(c.r * t.r, c.g * t.g, c.b * t.b, c.a))
			_fallen_materials[key] = m
		else:
			var box := StandardMaterial3D.new()
			box.albedo_color = FALLEN_COLOR
			_fallen_materials[key] = box
	return _fallen_materials[key]


## Перетворення сітки загиблого відносно його місця на землі: модель лежить як є, коробку кладемо плазом.
static func body_pose(set_id: int, pose: int = 0) -> Transform3D:
	if body_mesh(set_id, pose) != null:
		return Transform3D()
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, FIGURE_SIZE.z * 0.5, 0.0))


static func body_or_box(set_id: int, pose: int = 0) -> Mesh:
	var m: ArrayMesh = body_mesh(set_id, pose)
	return m if m != null else _figure_box()


static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = shared_material(color)
	parent.add_child(m)
	return m


static func model_dir(set_id: int) -> String:
	return MODEL_DIR if set_id == 0 else "%sset%d/" % [MODEL_DIR, set_id]


static func model_path(type_id: int, set_id: int = 0) -> String:
	return model_dir(set_id) + MODEL_SLUGS[type_id] + ".glb"


static func has_model(type_id: int, set_id: int = 0) -> bool:
	return model_mesh(type_id, set_id) != null


## Набір, чия модель і чий рядок справді діють: свій, коли має і модель, і рядок типу, інакше 0.
static func _resolved_set(type_id: int, set_id: int) -> int:
	if set_id == 0 or not (_set_specs.get(set_id, {}) as Dictionary).has(type_id):
		return 0
	return set_id if _own_model(type_id, set_id) != null else 0


## Сітка моделі в системі юніта (перетворення вузлів GLB уже впечені), або null, коли файлу нема.
## Матеріал поверхні — імпортований: з нього `model_material()` бере текстури.
static func model_mesh(type_id: int, set_id: int = 0) -> ArrayMesh:
	return _own_model(type_id, _resolved_set(type_id, set_id))


## Похідне положення гармати (станини зведені докупи): на мосту, де розведені станини стирчали б за поручні. Є лише в
## наборів, що мають файл `<slug>_travel.glb` (поки лише набір 0); решта — без нього, і гармата лишається як є.
const TRAVEL_SLUG_SUFFIX: String = "_travel"
const TRAVEL_KEY: int = 1000
static var _travel_models: Dictionary = {}


static func travel_mesh(type_id: int, set_id: int = 0) -> ArrayMesh:
	var resolved: int = _resolved_set(type_id, set_id)
	var key := Vector2i(resolved, type_id)
	if not _travel_models.has(key):
		var path: String = model_dir(resolved) + MODEL_SLUGS[type_id] + TRAVEL_SLUG_SUFFIX + ".glb"
		_travel_models[key] = _load_model(path) if not _models_pinned and ResourceLoader.exists(path) else null
	return _travel_models[key]


static func _own_model(type_id: int, set_id: int) -> ArrayMesh:
	var key := Vector2i(set_id, type_id)
	if not _models.has(key):
		var path: String = model_path(type_id, set_id)
		_models[key] = _load_model(path) if not _models_pinned and ResourceLoader.exists(path) else null
	return _models[key]


## Для тестів: лише ці сітки, решта — коробки, хай що лежить на диску. Ключ — тип (набір 0)
## або Vector2i(набір, тип).
static func use_models(models: Dictionary) -> void:
	reset_models()
	for k: Variant in models:
		_models[k if k is Vector2i else Vector2i(0, k as int)] = models[k]
	_models_pinned = true


## Для тестів: рядки наборів замість таблиці; `reset_models()` повертає таблицю.
static func use_set_specs(rows: Dictionary) -> void:
	_set_specs = rows.duplicate(true)
	_merged_meshes.clear()
	_model_materials.clear()
	_fallen_materials.clear()


static func reset_models() -> void:
	_travel_models.clear()
	_set_specs = _SET_SPECS.duplicate(true)
	_models.clear()
	_models_pinned = false
	_model_materials.clear()
	_fallen_materials.clear()
	_merged_meshes.clear()


static func _load_model(path: String) -> ArrayMesh:
	var root: Node = (load(path) as PackedScene).instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var out: ArrayMesh = null
	if found.is_empty():
		push_error("%s: немає сітки" % path)
	else:
		var mi := found[0] as MeshInstance3D
		var xf := Transform3D()
		var n: Node = mi
		while n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var xfs: Array[Transform3D] = [xf]
		out = _merge_model(mi.mesh, xfs)
		out.surface_set_material(0, mi.get_active_material(0))
	root.free()
	return out


## Копії поверхні 0 сітки `src` за перетвореннями в одну поверхню з усіма атрибутами: дотичні й
## UV2 потрібні карті нормалей, гусеницям і колесам.
static func _merge_model(src: Mesh, xfs: Array[Transform3D]) -> ArrayMesh:
	return _merge_parts([[src, xfs]])


## Те саме для кількох сіток: `parts` — пари [сітка, Array[Transform3D]]. Так відділення збирає в одну
## поверхню бійців із трубою й без неї (їхні GLB мають один атлас, тож і матеріал один).
static func _merge_parts(parts: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var tangents: bool = true
	for part: Array in parts:
		if part[0] == null or (part[1] as Array).is_empty():
			continue
		var a: Array = (part[0] as Mesh).surface_get_arrays(0)
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var count: int = sv.size()
		var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var st: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var sc: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var su: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var su2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var si: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(count))
		tangents = tangents and st.size() == count * 4
		for xf: Transform3D in part[1] as Array[Transform3D]:
			var base: int = v.size()
			for i in count:
				v.append(xf * sv[i])
				n.append((xf.basis * sn[i]).normalized())
				if st.size() == count * 4:
					var tg: Vector3 = (xf.basis * Vector3(st[i * 4], st[i * 4 + 1], st[i * 4 + 2])).normalized()
					t.append_array([tg.x, tg.y, tg.z, st[i * 4 + 3]])
				var col: Color = sc[i] if sc.size() == count else Color.BLACK
				c.append(col)
				uv.append(su[i] if su.size() == count else Vector2.ZERO)
				var u2: Vector2 = su2[i] if su2.size() == count else Vector2.ZERO
				if col.b > 0.5:
					# Вісь колеса їде разом із вершинами. shortcut: вісь лишається паралельною X лише
					# без повороту довкола Y/Z; у GLB вузли без такого повороту, тож поки досить.
					var axle: Vector3 = xf * Vector3(0.0, u2.x, u2.y)
					u2 = Vector2(axle.y, axle.z)
				uv2.append(u2)
			for i: int in si:
				idx.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	if tangents and t.size() == v.size() * 4:
		arrays[Mesh.ARRAY_TANGENT] = t
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Відблиск тканини бійця: зі звичайних 0,5 шолом і плечі під сонцем горіли білими цятками.
const FIGURE_SPECULAR: float = 0.2


## Один матеріал на тип: текстури, шорсткість і specular — з імпортованого матеріалу моделі.
static func model_material(type_id: int, set_id: int = 0, travel: bool = false) -> ShaderMaterial:
	var key := Vector2i(_resolved_set(type_id, set_id), type_id + (TRAVEL_KEY if travel else 0))
	if _model_materials.has(key):
		return _model_materials[key]
	var m := ShaderMaterial.new()
	m.shader = _MODEL_SHADER
	m.set_shader_parameter("wheel_radius", float(spec(type_id, set_id).get("wheel", 0.06)))
	var src := (travel_mesh(type_id, set_id) if travel else model_mesh(type_id, set_id)).surface_get_material(0) as BaseMaterial3D
	if src != null:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("albedo_color", src.albedo_color)
		if src.normal_enabled:
			m.set_shader_parameter("normal_tex", src.normal_texture)
			m.set_shader_parameter("normal_scale", src.normal_scale)
		m.set_shader_parameter("orm_tex", src.roughness_texture)
		m.set_shader_parameter("roughness_channel", _channel(src.roughness_texture_channel))
		m.set_shader_parameter("metallic_channel", _channel(src.metallic_texture_channel))
		m.set_shader_parameter("roughness", src.roughness)
		m.set_shader_parameter("metallic", src.metallic)
		var cloth: bool = (spec(type_id, set_id).extras as Array).has(&"figures")
		m.set_shader_parameter("specular", minf(src.metallic_specular, FIGURE_SPECULAR) if cloth else src.metallic_specular)
	_model_materials[key] = m
	return m


static func _channel(ch: BaseMaterial3D.TextureChannel) -> Vector4:
	if ch == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
		return Vector4(1.0, 1.0, 1.0, 0.0) / 3.0
	var out := Vector4.ZERO
	out[ch] = 1.0
	return out
