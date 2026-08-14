class_name UnitView
extends Node3D
## Юніт на дошці: примітив-заступник майбутнього 3D-асета, факінг, HP-бар,
## лічильник дронів і твін руху (§1.5, Task 2.4).
##
## Туман живе не тут. `UnitView` не читає й не питає клітинкову видимість — вирішує, чи
## існувати цьому вузлу взагалі, власник контейнера (Task 2.10): ворожий
## юніт отримує вузол лише коли він є в known_occupied_map активного
## гравця (§3.5). Невидимий ворог не тьмяніє і не лишає силует — у нього
## просто нема вузла. `set_dimmed` нижче — про інше: про свій юніт, який
## уже відстрілявся цей хід.

## Крок факінгу: вісім напрямків Board.DIRS_8 рівномірно по колу.
const _DEGREES_PER_FACING: float = 45.0

## §3.9: 2 дрони на загін за матч — більше ніколи не буває, тож це стеля
## відображення, а не число з ростера.
const _MAX_DRONES: int = 2

## Наскільки темніє корпус юніта, що вже відстрілявся.
const _DIM_FACTOR: float = 0.45

const _DESTROY_DURATION: float = 0.6

## Розмір Hull-меша на клас — і сама причина, чому силуети не сплутати
## (§1.5): піхота низька й вузька, легка техніка плаский подовжений блок,
## танк масивний, арта витягнута під довгий ствол, інженер — компактна
## коробка (жовту смугу додає _build_stripe).
const _HULL_SIZES: Dictionary = {
	UnitTypes.UnitClass.INFANTRY: Vector3(0.40, 0.35, 0.40),
	UnitTypes.UnitClass.LIGHT_VEHICLE: Vector3(0.55, 0.30, 0.85),
	UnitTypes.UnitClass.TANK: Vector3(0.75, 0.50, 0.90),
	UnitTypes.UnitClass.ARTILLERY: Vector3(0.55, 0.35, 0.60),
	UnitTypes.UnitClass.ENGINEER: Vector3(0.60, 0.40, 0.60),
}

## Абстрактні кольори гравців-плейсхолдерів (§2 — жодного реального прапора
## чи армії). Індекс — Unit.owner. Колір іде лише на корпус (Hull), не на
## ствол чи смугу — вони нейтральні для будь-якого власника.
const _PLAYER_COLORS: Array[Color] = [
	Color("3a6ea5"),
	Color("a54a3a"),
	Color("5a8a4a"),
]

## Поточний факінг (0..7, порядок Board.DIRS_8). Читається ззовні для UI цілей.
var facing: int = 0

@onready var _silhouette: Node3D = $Silhouette
@onready var _hp_bar: Sprite3D = $HpBar
@onready var _drone_icon: Sprite3D = $DroneIcon

var _hull_material: StandardMaterial3D
var _base_hull_color: Color = Color.WHITE
var _drones_left: int = 0


func _ready() -> void:
	# Заступники текстур: суцільний колір замість реального арту, той самий
	# підхід, що й нейтральні кольори тайлів у BoardView.
	_hp_bar.texture = _flat_texture(Color.WHITE)
	_drone_icon.texture = _flat_texture(Color("d9b23a"))


func bind(unit: Unit) -> void:
	position = IsoCameraRig.cell_to_world(unit.pos)
	_build_silhouette(unit.unit_class(), unit.owner)
	face(unit.facing)
	set_hp(unit.hp, unit.max_hp())
	set_drones(unit.drones_left)
	set_dimmed(unit.has_fired)


## Твін по шляху, повертає tween.finished. AP і туман сюди не заглядають —
## контролер вирішує, коли рухати, view лише показує вже прийняте рішення.
func move_along(path: Array[Vector2i], duration_per_step: float) -> Signal:
	var tween: Tween = create_tween()
	if path.is_empty():
		# Твін без жодного кроку міг би ніколи не подати finished — гарантований
		# нульовий інтервал забезпечує, що сигнал таки настане.
		tween.tween_interval(0.0)
	else:
		for cell in path:
			tween.tween_property(self, "position", IsoCameraRig.cell_to_world(cell), duration_per_step)
	return tween.finished


func face(direction: int) -> void:
	assert(direction >= 0 and direction < 8, "напрямок поза межами 8 фейсингів: %d" % direction)
	facing = direction
	rotation_degrees.y = float(direction) * _DEGREES_PER_FACING


func set_hp(hp: int, max_hp: int) -> void:
	var ratio: float = 0.0
	if max_hp > 0:
		ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_hp_bar.scale.x = ratio
	_hp_bar.modulate = Color.RED.lerp(Color.GREEN, ratio)


## §3.9: залишок дронів публічний — показується на будь-якому видимому
## загоні для будь-якого гравця, тож метод свідомо не питає й не знає, чий
## це юніт.
func set_drones(count: int) -> void:
	_drones_left = clampi(count, 0, _MAX_DRONES)
	_drone_icon.visible = _drones_left > 0
	_drone_icon.scale = Vector3.ONE * (0.5 + 0.25 * float(_drones_left))


func play_destroyed() -> Signal:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, _DESTROY_DURATION)
	return tween.finished


## Для свого юніта, який уже витратив AP на постріл цей хід (§3.2) — і
## більше ні для чого. Туман сюди не потрапляє свідомо: невидимого ворога
## не тьмянять, у нього просто нема вузла (Task 2.10, §3.5) — «останній
## відомий» приглушений юніт був би витоком, а не зручністю. Якщо колись
## захочеться підв'язати цей метод до видимості — це і є та помилка, про
## яку попереджає коментар зверху файлу.
func set_dimmed(dimmed: bool) -> void:
	if _hull_material == null:
		return
	var target_color: Color = _base_hull_color
	if dimmed:
		target_color = _base_hull_color * Color(_DIM_FACTOR, _DIM_FACTOR, _DIM_FACTOR, 1.0)
	_hull_material.albedo_color = target_color


func _build_silhouette(unit_class: int, owner: int) -> void:
	# free(), не queue_free(): відкладене звільнення лишає щойно відкріплений
	# вузол «сиротою» до наступного кадру, і headless-тести це фіксують.
	for child in _silhouette.get_children():
		child.free()

	var hull_size: Vector3 = _HULL_SIZES.get(unit_class, Vector3.ONE)
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = hull_size
	hull.mesh = hull_mesh
	hull.position.y = hull_size.y * 0.5

	_hull_material = StandardMaterial3D.new()
	_base_hull_color = _PLAYER_COLORS[owner % _PLAYER_COLORS.size()]
	_hull_material.albedo_color = _base_hull_color
	hull.material_override = _hull_material
	_silhouette.add_child(hull)

	match unit_class:
		UnitTypes.UnitClass.TANK, UnitTypes.UnitClass.ARTILLERY:
			_silhouette.add_child(_build_barrel(unit_class, hull_size))
		UnitTypes.UnitClass.ENGINEER:
			_silhouette.add_child(_build_stripe(hull_size))


## Танк — короткий виступ ствола, арта — довгий тонкий ствол (§1.5): та сама
## деталь, різна довжина, а не два окремі меші.
func _build_barrel(unit_class: int, hull_size: Vector3) -> MeshInstance3D:
	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	var mesh := BoxMesh.new()
	var length: float = 0.90 if unit_class == UnitTypes.UnitClass.ARTILLERY else 0.40
	mesh.size = Vector3(0.10, 0.10, length)
	barrel.mesh = mesh
	barrel.position = Vector3(0.0, hull_size.y * 0.5, -(hull_size.z * 0.5 + length * 0.5))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2e2b27")  # нейтральний метал ствола — колір гравця сюди не йде
	barrel.material_override = mat
	return barrel


func _build_stripe(hull_size: Vector3) -> MeshInstance3D:
	var stripe := MeshInstance3D.new()
	stripe.name = "Stripe"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(hull_size.x + 0.02, 0.04, hull_size.z * 0.3)
	stripe.mesh = mesh
	stripe.position = Vector3(0.0, hull_size.y + 0.02, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("d9b23a")  # жовта смуга інженера — впізнавана незалежно від власника
	stripe.material_override = mat
	return stripe


static func _flat_texture(color: Color, size: int = 8) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
