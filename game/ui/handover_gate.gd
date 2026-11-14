class_name HandoverGate
extends Control
## Task 2.9: гейт передачі пристрою. §1.2 — прихована інформація священна;
## §3.5 — гейт не можна пропустити, не можна анімувати наскрізь, і камера не
## сміє видати позиції попереднього гравця.
##
## КОНТРАКТ ПОРЯДКУ ДЛЯ TASK 2.10 (обов'язковий, не необов'язкова порада):
##
## 1. Спершу — show_for(player). Панель стає непрозорою й видимою ТУТ, синхронно,
##    одним кадром: жодного fade-in із проміжною прозорістю, бо кожен кадр із
##    alpha < 1.0 — це кадр, крізь який видно позиції попереднього гравця.
## 2. Поки панель на екрані, і лише тепер:
##    a) IsoCameraRig.center_on() на перший юніт гравця, що заходить.
##       ОБОВ'ЯЗКОВО до зняття панелі: центр камери — це теж інформація.
##       Якби рецентрування сталось ПІСЛЯ зняття панелі, перший кадр нового
##       ходу показав би позицію попереднього гравця (там, де камера стояла
##       наприкінці його ходу) ще до того, як гравець встиг би збагнути, що
##       дивиться на чуже.
##    b) вузли ворожих юнітів перебудовуються під `seen` гравця, що заходить
##       (§3.5). ОБОВ'ЯЗКОВО до зняття панелі й ОБОВ'ЯЗКОВО до (a) чи після —
##       порядок між (a) і (b) між собою не має значення, бо обидва мають
##       завершитись поки панель ще повністю закриває дошку. Місцевість
##       публічна (§3.5) і перебудови не потребує — приховані рівно юніти й
##       міни, тож рівно вузли юнітів і мають бути перебудовані тут.
## 3. Лише після того, як і (a), і (b) застосовані — зняти панель (наприклад
##    `gate.visible = false`). Це НЕ обов'язок цього файла: show_for()
##    вмикає гейт, але не вимикає його сама після confirmed — вимкнення
##    належить сцені бою (Task 2.10), яка спершу мусить встигнути виконати
##    кроки 2a/2b, реагуючи на сигнал `confirmed`.
##
## Чому саме так: якщо зняти панель до (2a) чи (2b), перший кадр нового ходу
## або на секунду показує камеру там, де стояв попередній гравець (2a), або
## показує ворожі юніти, видимі під старим `seen` замість нового (2b) — в
## обох випадках прихована інформація витікає саме в той момент, заради
## якого й існує весь гейт.
##
## 4. Поки гейт видимий, маршрутизація тапів по дошці мусить бути вимкнена
##    АБО йти через `_unhandled_input`. `%Panel`/сам гейт стоять на
##    `MOUSE_FILTER_STOP`, але це лише зупиняє GUI-подію в самому дереві
##    Control — воно нічого не каже про `_input()`/raycast-обробник, яким
##    Task 2.10 ще має підключити InputController.tap_cell(). Якщо тапи
##    дошки йдуть із `_input()` напряму, або з raycast-зворотного виклику, що не
##    перевіряє `get_viewport().is_input_handled()`, `STOP` тут НІЧОГО не
##    блокує — і гравець, що виходить, встигає рухати юнітів крізь
##    непрозору панель, поки вона на екрані.
## 5. Гейт мусить бути прямим нащадком повнорозмірного `CanvasLayer`,
##    впорядкованого НАД дошкою (вищий `layer`, або останній у списку
##    сусідніх вузлів над 3D-`Viewport`). Anchors (0,0,1,1) із нульовими offset —
##    це заповнення rect БАТЬКА, не `Viewport`: запхнутий у MarginContainer,
##    спліт чи Control під 3D-`SubViewport`ом гейт пройде кожен тест цього
##    файла (вони перевіряють лише власні anchors/offsets) і водночас
##    покаже дошку навколо або поверх себе — суцільна непрозорість стає
##    декором, не гейтом.
##
## 6. Вхідна анімація (один твін, 350 мс) рухає лише акценти: фон, підпис, інфо-плита й
##    кнопка стоять з першого кадру, гейт сам ніколи не з'являється плавно (крок 1).
##    «Готово» не реагує, доки твін не скінчився: подвійний тап гравця, що виходить,
##    по «Кінець ходу» не сміє заодно зняти гейт.
##
## Ця сцена свідомо НЕ підписується на Events.TurnStarted сама — контейнера
## юнітів і живої battle_screen.tscn ще нема (вони з'являються в Task 2.10),
## і саме той файл вирішує, коли викликати show_for() і в якому порядку
## виконати кроки 2a/2b після сигналу confirmed (Ruling R7).

## Явне натискання — єдиний шлях відкрити хід. Ніякого автозняття по
## таймеру чи по кліку повз кнопку: кнопки «пропустити» немає в сцені
## взагалі (перевірено тестом), а не лише прихована.
signal confirmed

const _PLATE_PATH := "res://assets/ui/gate/%s.webp"
const _DEFAULT_PLATE := "res://assets/ui/gate/default.webp"
## Ширина нікнейм-плити й інфо-плити одна: ширина інфо-плити, не менша за це.
const MIN_WIDTH := 400.0
const ENTRANCE_S := 0.35
const SLIDE_DP := 12.0
const _HORIZON_ALPHA := 0.7

## Лишається публічним, щоб тест міг докрутити твін вручну (custom_step), не чекаючи реального часу.
var entrance_tween: Tween

var _accepting: bool = false
var _map_name_key: String = ""

@onready var _player_value: Label = %PlayerValue
@onready var _confirm_button: Button = %ConfirmButton
@onready var _plate: TextureRect = %Plate
@onready var _caption: Label = %Caption
@onready var _info_plate: PanelContainer = %InfoPlate
@onready var _name_slide: Control = %NameSlide
@onready var _nameplate: Control = %Nameplate
@onready var _wipes: Array[Control] = [%RuleTop, %RuleBottom, %Horizon]


func _ready() -> void:
	HudKit.group_content(_confirm_button, 22.0)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	for w in _wipes:
		w.pivot_offset_ratio = Vector2(0.5, 0.5)


## Плита-фон за ім'ям ресурсу карти (maps/river.tres -> river.webp); для карти без плити
## (редактор робить нові) — загальна темна. Плита запечена офлайн: у ній немає юнітів.
## Пауза бере ту саму плиту.
static func plate_for(map_path: String) -> Texture2D:
	var path: String = _PLATE_PATH % map_path.get_file().get_basename()
	if map_path == "" or not ResourceLoader.exists(path):
		path = _DEFAULT_PLATE
	return load(path) as Texture2D


## Карта незмінна протягом матчу: сцена бою задає їх раз, а не на кожному show_for.
func set_context(map_path: String, name_key: String) -> void:
	_plate.texture = plate_for(map_path)
	_map_name_key = name_key


## Показує гейт для гравця, що заходить. Синхронно й одразу непрозоро —
## жодного проміжного кадру з часткою прозорості (§3.5 «жодної анімації
## проїзду»). player — 0-based індекс, як і скрізь у BattleState; на екрані
## показується 1-based. turn — номер кола (BattleState.turn_number).
##
## Кнопка тут же вмикається заново: попередній show_for міг лишити її
## вимкненою (див. _on_confirm_pressed) — новий виклик мусить давати новий
## шанс натиснути, а не успадковувати «вже натиснуто» від чужого ходу.
func show_for(player: int, turn: int = 1) -> void:
	_player_value.text = "%s %d" % [tr("hud_player"), player + 1]
	# Тема не вміє верхній регістр, тож підписи капсом — з коду.
	_caption.text = tr("handover_pass_device").to_upper()
	%TurnCaption.text = tr("hud_turn").to_upper()
	%TurnValue.text = str(turn)
	%MapCaption.text = tr("hud_map").to_upper()
	%MapValue.text = tr(_map_name_key) if _map_name_key != "" else "-"
	_fit_width()
	_confirm_button.disabled = false
	visible = true
	_play_entrance(UnitView.PLAYER_COLORS[player % UnitView.PLAYER_COLORS.size()])


## Одна ширина на нікнейм-плиту й інфо-плиту: природна ширина інфо-плити, не менша за MIN_WIDTH.
func _fit_width() -> void:
	_info_plate.custom_minimum_size.x = 0.0
	var width: float = maxf(MIN_WIDTH, _info_plate.get_combined_minimum_size().x)
	_info_plate.custom_minimum_size.x = width
	_name_slide.custom_minimum_size.x = width


func _play_entrance(player_color: Color) -> void:
	if entrance_tween != null:
		entrance_tween.kill()
	_accepting = false
	%RuleTop.color = player_color
	%RuleBottom.color = player_color
	%Horizon.color = Color(player_color, _HORIZON_ALPHA)
	for w in _wipes:
		w.scale.x = 0.0
	_nameplate.position.y = SLIDE_DP
	_nameplate.modulate.a = 0.0
	entrance_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for w in _wipes:
		entrance_tween.tween_property(w, "scale:x", 1.0, ENTRANCE_S)
	entrance_tween.tween_property(_nameplate, "position:y", 0.0, ENTRANCE_S)
	entrance_tween.tween_property(_nameplate, "modulate:a", 1.0, ENTRANCE_S)
	entrance_tween.chain().tween_callback(func() -> void: _accepting = true)


## §3.5/крок 3 контракту: поки панель ще на екрані, Task 2.10 виконує
## рецентрування камери й перебудову ворожих вузлів (кроки 2a/2b) — і саме
## в це вікно кнопка лишається видимою й натискною. Без вимкнення тут другий
## дотик (звичайний подвійний тап на телефоні) видав би confirmed двічі й
## запустив послідовність передачі ходу вдруге. Гейт — єдиний об'єкт, що
## знає про сам факт натискання, тож саме він і мусить це гасити, а не
## Task 2.10 здогадуватися про дебаунс ззовні.
func _on_confirm_pressed() -> void:
	if not _accepting or _confirm_button.disabled:
		return
	_confirm_button.disabled = true
	confirmed.emit()
