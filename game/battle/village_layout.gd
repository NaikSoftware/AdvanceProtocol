class_name VillageLayout
extends RefCounted
## Макет сіл карт, складений вручну, як справжня місцевість: садиби (хата фасадом до дороги, город за
## хатою, сарай, один паркан довкола двору з воротами до дороги), сади між садибами, тюки на краю
## поля, траси ЛЕП через усю карту. Лише вигляд: правила, як і раніше, читають клітинки карти.
## Карта з макетом бере з нього садиби, сади, тюки й ЛЕП; процедура PropLayer там ставить лише
## будівлі кільця за дошкою, руїни на клітинках RUBBLE, брили, бетонні блоки й мости. Решта
## процедури (двори, огорожі полів, тюки, причепи, стовпи) — для дощок без макету, як тестові.
## Схеми — tools/maps/README.md, «Села».
##
## Садиба: house — клітинка BUILDING хати; face — куди дивиться фасад (і ворота); cells — усі
## клітинки двору; garden — клітинки городу за хатою; shed — клітинка сараю (необов'язково).
## Лінія: kind — &"10kv" чи &"04kv"; points — самі опори в координатах світу (дошка плюс кільце: від
## -ring до ширини дошки + ring - 1, межа дошки на -0.5 і ширині - 0.5). Магістраль 10 кВ іде від
## зовнішнього краю кільця до протилежного вздовж доріг; відгалуження 0.4 кВ починається зі стовпа
## магістралі, що стає підстанцією. Стовп стоїть там, де його дозволено: не в клітинці юніта (≥ 0.48
## від центру за більшою віссю — на межі клітинок), не на дорозі, не біля води, не в обрисі будинку.
## Точки поставлено інструментом із перевіркою цих умов; проліт не довший за SPAN.

const N := Vector2i(0, -1)
const S := Vector2i(0, 1)
const E := Vector2i(1, 0)
const W := Vector2i(-1, 0)

const LAYOUTS: Dictionary = {
	&"river": {
		"homes": [
			{"house": Vector2i(12, 6), "face": E, "cells": [Vector2i(11, 6), Vector2i(12, 6), Vector2i(11, 7)],
				"garden": [Vector2i(11, 6)], "shed": Vector2i(11, 7)},
			# (16,6) і (16,7) — над болотом: паркан туди не дістає, тож вони — лук поза двором.
			{"house": Vector2i(15, 6), "face": W, "cells": [Vector2i(15, 6), Vector2i(15, 7)], "shed": Vector2i(15, 7)},
			{"house": Vector2i(8, 4), "face": N, "cells": [Vector2i(7, 4), Vector2i(8, 4)], "garden": [Vector2i(7, 4)]},
			{"house": Vector2i(12, 4), "face": E, "cells": [Vector2i(11, 4), Vector2i(12, 4)], "garden": [Vector2i(11, 4)]},
			# (5,8) — на березі: паркан туди не дістає, тож клітинка — лук поза двором.
			{"house": Vector2i(5, 7), "face": W, "cells": [Vector2i(5, 7)]},
			# Біля руїни (11,14) дві хати з камери гри злипаються з нею: тут одна садиба, хата — до
			# південної дороги, городи й сарай за нею.
			{"house": Vector2i(10, 15), "face": S, "cells": [Vector2i(9, 13), Vector2i(10, 13), Vector2i(9, 14), Vector2i(10, 14),
				Vector2i(9, 15), Vector2i(10, 15)],
				"garden": [Vector2i(10, 14), Vector2i(9, 14)], "shed": Vector2i(9, 15)},
			# Двір — L, не сходинки клітинок: (14,15) і (16,17) — лук поза двором.
			{"house": Vector2i(15, 15), "face": N, "cells": [Vector2i(15, 15), Vector2i(15, 16), Vector2i(16, 16)],
				"garden": [Vector2i(15, 16)], "shed": Vector2i(16, 16)},
			{"house": Vector2i(22, 13), "face": W, "cells": [Vector2i(22, 13), Vector2i(23, 13), Vector2i(22, 14)],
				"garden": [Vector2i(23, 13)], "shed": Vector2i(22, 14)},
			{"house": Vector2i(12, 17), "face": E, "cells": [Vector2i(11, 17), Vector2i(12, 17)], "garden": [Vector2i(11, 17)]},
		],
		"orchards": [Vector2i(16, 6), Vector2i(16, 7), Vector2i(5, 8), Vector2i(14, 15), Vector2i(16, 17)],
		# Наміри трас. 10 кВ іде дорогами від краю до краю кільця: північною дорогою, дорогою рядка 3, колонки 13 і рядка 5, колонкою 21 через
		# міст, рядком 18 і дорогою колонки 19 на південь. axis — вісь дороги у світових координатах (дошка плюс кільце), side — з якого
		# боку від осі за ходом іде лінія (+1 ліворуч, -1 праворуч), from — відгалуження від стовпа вже складеної траси.
		# Точне місце кожного стовпа, підстанції й гілок 0.4 кВ обчислює tools/power_grid.py (між мітками нижче).
		"routes": [
			{"kind": &"10kv", "axis": [Vector2(6, -13), Vector2(6, 3), Vector2(13, 3), Vector2(13, 5), Vector2(21, 5), Vector2(21, 18), Vector2(19, 18), Vector2(19, 34)], "side": 1.0},
		],
		# power:begin river
		"lines": [
			{"kind": &"10kv", "points": [Vector2(6.75, -12.49), Vector2(6.51, -9.00), Vector2(5.49, -4.75), Vector2(5.49, -0.75), Vector2(5.25, 2.49), Vector2(9.49, 2.25), Vector2(13.51, 2.50), Vector2(14.00, 4.49), Vector2(17.25, 4.49), Vector2(21.51, 4.50), Vector2(21.51, 8.50), Vector2(20.49, 12.75), Vector2(21.50, 16.51), Vector2(21.50, 18.51), Vector2(19.75, 18.51), Vector2(19.75, 21.49), Vector2(19.75, 25.49), Vector2(19.51, 29.75), Vector2(19.50, 33.49)]},
			{"kind": &"04kv", "points": [Vector2(20.49, 12.75), Vector2(16.51, 14.25), Vector2(14.00, 13.49), Vector2(13.75, 15.49)]},
			{"kind": &"04kv", "points": [Vector2(13.75, 15.49), Vector2(11.75, 15.49)]},
			{"kind": &"04kv", "points": [Vector2(13.75, 15.49), Vector2(14.00, 17.49), Vector2(12.25, 18.49)]},
			{"kind": &"04kv", "points": [Vector2(5.49, -4.75), Vector2(3.00, -6.51), Vector2(3.25, -8.51)]},
			{"kind": &"04kv", "points": [Vector2(5.49, -4.75), Vector2(8.75, -5.51), Vector2(10.25, -8.51), Vector2(12.25, -8.51)]},
			{"kind": &"04kv", "points": [Vector2(9.49, 2.25), Vector2(10.75, 5.49), Vector2(6.75, 6.49), Vector2(6.51, 4.50)]},
			{"kind": &"04kv", "points": [Vector2(21.50, 16.51), Vector2(23.75, 14.49), Vector2(23.51, 12.50)]},
		],
		"transformers": [Vector2(20.49, 12.75), Vector2(5.49, -4.75), Vector2(9.49, 2.25), Vector2(21.50, 16.51)],
		"unfed": [Vector2(15.15, 6.00)],
		# power:end river
		"hay": [Vector2(17.0, 4.2), Vector2(9.3, 5.0), Vector2(18.5, 14.5), Vector2(9.5, 19.4)],
	},
	&"crossroads": {
		"homes": [
			{"house": Vector2i(10, 7), "face": N, "cells": [Vector2i(9, 7), Vector2i(10, 7), Vector2i(9, 8), Vector2i(10, 8)],
				"garden": [Vector2i(9, 8), Vector2i(10, 8)], "shed": Vector2i(9, 7)},
			{"house": Vector2i(16, 7), "face": N, "cells": [Vector2i(15, 7), Vector2i(16, 7), Vector2i(16, 8)],
				"garden": [Vector2i(16, 8)], "shed": Vector2i(15, 7)},
			{"house": Vector2i(14, 9), "face": W, "cells": [Vector2i(14, 9), Vector2i(15, 9), Vector2i(14, 10), Vector2i(15, 10)],
				"garden": [Vector2i(15, 9), Vector2i(15, 10)], "shed": Vector2i(14, 10)},
			{"house": Vector2i(13, 13), "face": E, "cells": [Vector2i(12, 13), Vector2i(13, 13), Vector2i(12, 14), Vector2i(13, 14)],
				"garden": [Vector2i(12, 13), Vector2i(12, 14)], "shed": Vector2i(13, 14)},
			{"house": Vector2i(16, 14), "face": S, "cells": [Vector2i(15, 13), Vector2i(16, 13), Vector2i(15, 14), Vector2i(16, 14)],
				"garden": [Vector2i(15, 13), Vector2i(16, 13)], "shed": Vector2i(15, 14)},
		],
		# Сади й городи між садибами: квартал обжитий, а хат — шість.
		"orchards": [Vector2i(12, 7), Vector2i(13, 7), Vector2i(12, 8), Vector2i(13, 8), Vector2i(14, 8),
			Vector2i(16, 9), Vector2i(16, 10), Vector2i(16, 11), Vector2i(14, 11), Vector2i(11, 10),
			Vector2i(11, 11), Vector2i(11, 12), Vector2i(9, 13), Vector2i(11, 13), Vector2i(9, 14), Vector2i(10, 14),
			# Між двома руїнами (10,10) і (10,13) хата з камери гри злипалась би з однією з них: город.
			Vector2i(9, 10), Vector2i(9, 11), Vector2i(9, 12), Vector2i(10, 11), Vector2i(10, 12)],
		# Наміри трас. 10 кВ — головними дорогами від краю до краю кільця: рядком 8 і навколо міста північною вулицею (рядок 6);
		# відгалуження — колонкою 31 до хутора на південному сході кільця (лінія зупиняється перед ним, решту живлення бере гілка 0.4 кВ). Решту (стовпи, підстанції, гілки 0.4 кВ) обчислює
		# tools/power_grid.py між мітками нижче.
		"routes": [
			{"kind": &"10kv", "axis": [Vector2(-13, 8), Vector2(8, 8), Vector2(8, 6), Vector2(17, 6), Vector2(17, 8), Vector2(38, 8)], "side": 1.0},
			{"kind": &"10kv", "axis": [Vector2(31, 8), Vector2(31, 22)], "side": 1.0, "from": 0},
		],
		# power:begin crossroads
		"lines": [
			{"kind": &"10kv", "points": [Vector2(-12.25, 6.51), Vector2(-8.75, 6.51), Vector2(-4.51, 5.75), Vector2(-1.51, 7.00), Vector2(2.49, 7.00), Vector2(6.51, 7.25), Vector2(6.75, 5.49), Vector2(10.25, 5.49), Vector2(12.50, 5.49), Vector2(14.51, 5.25), Vector2(17.49, 5.25), Vector2(18.00, 7.49), Vector2(22.25, 7.49), Vector2(24.75, 7.49), Vector2(29.00, 7.49), Vector2(33.25, 7.49), Vector2(37.49, 7.25)]},
			{"kind": &"10kv", "points": [Vector2(33.25, 7.49), Vector2(32.75, 11.51), Vector2(32.25, 15.51), Vector2(31.75, 19.51), Vector2(31.51, 22.00)]},
			{"kind": &"04kv", "points": [Vector2(12.50, 5.49), Vector2(12.00, 8.49), Vector2(11.49, 12.00), Vector2(9.50, 11.51), Vector2(7.49, 12.00)]},
			{"kind": &"04kv", "points": [Vector2(7.49, 12.00), Vector2(7.25, 9.51), Vector2(10.49, 7.75)]},
			{"kind": &"04kv", "points": [Vector2(7.49, 12.00), Vector2(7.49, 14.00), Vector2(9.50, 14.49), Vector2(10.51, 16.25), Vector2(13.49, 16.25), Vector2(17.51, 14.75), Vector2(17.51, 11.25), Vector2(16.25, 8.51)]},
			{"kind": &"04kv", "points": [Vector2(-8.75, 6.51), Vector2(-6.51, 10.00), Vector2(-3.51, 10.00), Vector2(-3.49, 7.25)]},
			{"kind": &"04kv", "points": [Vector2(29.00, 7.49), Vector2(29.00, 10.49), Vector2(29.00, 13.51)]},
			{"kind": &"04kv", "points": [Vector2(31.51, 22.00), Vector2(28.75, 23.51), Vector2(25.50, 25.49)]},
			{"kind": &"04kv", "points": [Vector2(31.51, 22.00), Vector2(34.00, 25.49), Vector2(30.49, 27.25)]},
			{"kind": &"04kv", "points": [Vector2(30.49, 27.25), Vector2(28.49, 27.25)]},
			{"kind": &"04kv", "points": [Vector2(30.49, 27.25), Vector2(30.49, 29.25), Vector2(33.00, 29.49), Vector2(33.00, 26.51)]},
			{"kind": &"04kv", "points": [Vector2(25.50, 25.49), Vector2(23.51, 24.75), Vector2(21.49, 25.75), Vector2(20.49, 28.75)]},
			{"kind": &"04kv", "points": [Vector2(25.50, 25.49), Vector2(23.75, 28.51)]},
		],
		"transformers": [Vector2(12.50, 5.49), Vector2(-8.75, 6.51), Vector2(29.00, 7.49), Vector2(31.51, 22.00)],
		"unfed": [Vector2(14.00, 7.00), Vector2(16.00, 14.00)],
		# power:end crossroads
		"hay": [Vector2(6.0, 10.5), Vector2(19.5, 10.5), Vector2(6.4, 18.4), Vector2(22.5, 4.5)],
	},
	&"ridge": {
		"homes": [
			{"house": Vector2i(13, 5), "face": W, "cells": [Vector2i(13, 4), Vector2i(13, 5), Vector2i(14, 5)],
				"garden": [Vector2i(14, 5)], "shed": Vector2i(13, 4)},
			{"house": Vector2i(12, 16), "face": E, "cells": [Vector2i(11, 16), Vector2i(12, 16), Vector2i(12, 17)],
				"garden": [Vector2i(11, 16)], "shed": Vector2i(12, 17)},
		],
		"orchards": [],
		# Наміри трас. 10 кВ — єдиною дорогою від краю до краю кільця: рядком -5, колонкою -4, рядком 2 і сходинками дороги на
		# південний схід до рядка 26; відгалуження 10 кВ — до північних руїн (рядком -5) і до південно-східних хат кільця (рядком 26). Решту (стовпи, підстанції, гілки 0.4 кВ) обчислює tools/power_grid.py між мітками нижче.
		"routes": [
			{"kind": &"10kv", "axis": [Vector2(-13, -5), Vector2(-4, -5), Vector2(-4, 2), Vector2(8, 2), Vector2(8, 6), Vector2(12, 6), Vector2(12.5, 11), Vector2(13, 12.5), Vector2(13, 15), Vector2(17, 15), Vector2(17, 19), Vector2(29, 19), Vector2(29, 26), Vector2(38, 26)], "side": 1.0},
			{"kind": &"10kv", "axis": [Vector2(-4, -5), Vector2(12, -5), Vector2(12, -8)], "side": 1.0, "from": 0},
			{"kind": &"10kv", "axis": [Vector2(29, 26), Vector2(20, 26)], "side": 1.0, "from": 0},
		],
		# power:begin ridge
		"lines": [
			{"kind": &"10kv", "points": [Vector2(-12.00, -5.51), Vector2(-7.75, -5.51), Vector2(-3.50, -5.51), Vector2(-3.00, -1.49), Vector2(-2.75, 1.49), Vector2(1.49, 1.25), Vector2(5.49, 1.25), Vector2(8.50, 1.49), Vector2(9.00, 5.49), Vector2(12.51, 6.25), Vector2(13.50, 10.51), Vector2(13.75, 12.51), Vector2(13.51, 14.00), Vector2(15.51, 14.25), Vector2(17.51, 14.50), Vector2(17.51, 17.25), Vector2(21.75, 17.51), Vector2(25.51, 18.00), Vector2(29.49, 18.25), Vector2(30.00, 21.51), Vector2(30.50, 25.49), Vector2(33.25, 25.49), Vector2(37.49, 25.25)]},
			{"kind": &"10kv", "points": [Vector2(-3.50, -5.51), Vector2(-1.25, -5.51), Vector2(3.00, -5.51), Vector2(7.00, -5.51), Vector2(11.25, -5.51)]},
			{"kind": &"10kv", "points": [Vector2(30.50, 25.49), Vector2(27.25, 25.49), Vector2(23.00, 26.51)]},
			{"kind": &"04kv", "points": [Vector2(13.50, 10.51), Vector2(15.75, 8.51), Vector2(14.51, 5.25)]},
			{"kind": &"04kv", "points": [Vector2(13.75, 12.51), Vector2(10.75, 13.51), Vector2(10.49, 15.50)]},
			{"kind": &"04kv", "points": [Vector2(11.25, -5.51), Vector2(14.51, -6.75), Vector2(14.49, -10.75), Vector2(12.25, -11.49), Vector2(9.51, -10.75)]},
			{"kind": &"04kv", "points": [Vector2(23.00, 26.51), Vector2(23.49, 30.00), Vector2(20.49, 30.25)]},
		],
		"transformers": [Vector2(13.50, 10.51), Vector2(13.75, 12.51), Vector2(11.25, -5.51), Vector2(23.00, 26.51)],
		"unfed": [Vector2(12.00, -9.00), Vector2(11.00, -9.00)],
		# power:end ridge
		"hay": [Vector2(16.5, 4.5), Vector2(9.5, 17.5), Vector2(7.5, 9.5), Vector2(19.5, 7.5)],
	},
}


static func for_map(key: StringName) -> Dictionary:
	return LAYOUTS.get(key, {})
