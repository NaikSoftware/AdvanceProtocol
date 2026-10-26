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
			{"kind": &"10kv", "points": [Vector2(6.55, -12.49), Vector2(6.70, -9.49), Vector2(6.70, -6.51), Vector2(7.70, -4.49), Vector2(7.70, -0.49), Vector2(7.27, 2.49), Vector2(9.92, 2.49), Vector2(13.51, 2.45), Vector2(13.51, 4.45), Vector2(17.16, 4.49), Vector2(21.51, 4.45), Vector2(21.51, 8.60), Vector2(20.49, 12.85), Vector2(21.51, 15.60), Vector2(21.51, 18.55), Vector2(19.55, 18.51), Vector2(19.51, 21.66), Vector2(19.51, 24.91), Vector2(19.51, 29.16), Vector2(19.55, 33.49)]},
			{"kind": &"04kv", "points": [Vector2(19.55, 18.51), Vector2(17.51, 16.07), Vector2(16.49, 14.07), Vector2(13.51, 14.07), Vector2(11.53, 15.49), Vector2(9.53, 17.51), Vector2(10.03, 19.49), Vector2(13.03, 18.51), Vector2(13.53, 16.51)]},
			{"kind": &"04kv", "points": [Vector2(6.70, -9.49), Vector2(3.51, -8.93)]},
			{"kind": &"04kv", "points": [Vector2(3.51, -8.93), Vector2(3.51, -10.93), Vector2(7.49, -10.93)]},
			{"kind": &"04kv", "points": [Vector2(3.51, -8.93), Vector2(4.12, -6.51), Vector2(7.12, -5.49), Vector2(9.12, -5.51)]},
			{"kind": &"04kv", "points": [Vector2(7.27, 2.49), Vector2(6.07, 5.49), Vector2(8.49, 6.03), Vector2(10.49, 6.03), Vector2(10.49, 4.03), Vector2(11.51, 2.03)]},
			{"kind": &"04kv", "points": [Vector2(11.51, 2.03), Vector2(8.51, 0.53), Vector2(6.49, 4.03)]},
			{"kind": &"04kv", "points": [Vector2(11.51, 2.03), Vector2(13.57, 2.49), Vector2(16.57, 5.51)]},
			{"kind": &"04kv", "points": [Vector2(21.51, 15.60), Vector2(24.62, 14.49), Vector2(23.62, 12.49)]},
		],
		"transformers": [Vector2(19.55, 18.51), Vector2(6.70, -9.49), Vector2(7.27, 2.49), Vector2(21.51, 15.60)],
		"unfed": [],
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
			{"kind": &"10kv", "points": [Vector2(-12.49, 7.43), Vector2(-8.51, 7.33), Vector2(-4.51, 7.33), Vector2(-0.51, 7.33), Vector2(3.49, 7.33), Vector2(7.45, 7.49), Vector2(7.49, 6.05), Vector2(11.89, 5.49), Vector2(15.39, 5.49), Vector2(17.49, 5.45), Vector2(17.51, 7.45), Vector2(20.41, 7.49), Vector2(24.66, 7.49), Vector2(28.91, 7.49), Vector2(33.16, 7.49), Vector2(37.49, 7.45)]},
			{"kind": &"10kv", "points": [Vector2(33.16, 7.49), Vector2(32.66, 11.51), Vector2(32.41, 14.49), Vector2(31.91, 18.49), Vector2(31.51, 22.00)]},
			{"kind": &"04kv", "points": [Vector2(7.45, 7.49), Vector2(8.50, 11.51)]},
			{"kind": &"04kv", "points": [Vector2(8.50, 11.51), Vector2(6.51, 12.10)]},
			{"kind": &"04kv", "points": [Vector2(8.50, 11.51), Vector2(9.00, 13.49)]},
			{"kind": &"04kv", "points": [Vector2(8.50, 11.51), Vector2(10.49, 11.10), Vector2(12.00, 12.51)]},
			{"kind": &"04kv", "points": [Vector2(6.51, 12.10), Vector2(6.00, 9.51), Vector2(9.49, 7.80), Vector2(12.49, 7.60), Vector2(13.00, 5.49), Vector2(17.00, 5.49), Vector2(17.50, 8.51), Vector2(16.49, 12.60), Vector2(18.50, 13.51), Vector2(19.50, 10.49), Vector2(16.00, 8.49)]},
			{"kind": &"04kv", "points": [Vector2(6.51, 12.10), Vector2(7.49, 14.10), Vector2(9.50, 14.49)]},
			{"kind": &"04kv", "points": [Vector2(-8.51, 7.33), Vector2(-8.43, 10.49), Vector2(-5.43, 12.49), Vector2(-2.93, 11.49), Vector2(-3.43, 8.51), Vector2(-3.43, 6.51)]},
			{"kind": &"04kv", "points": [Vector2(28.91, 7.49), Vector2(29.07, 10.49), Vector2(29.07, 13.51)]},
			{"kind": &"04kv", "points": [Vector2(31.51, 22.00), Vector2(28.51, 24.03), Vector2(27.07, 25.51)]},
			{"kind": &"04kv", "points": [Vector2(27.07, 25.51), Vector2(24.51, 26.03)]},
			{"kind": &"04kv", "points": [Vector2(27.07, 25.51), Vector2(29.49, 28.53)]},
			{"kind": &"04kv", "points": [Vector2(29.49, 28.53), Vector2(28.51, 31.03), Vector2(24.51, 30.03), Vector2(21.51, 31.03), Vector2(20.51, 33.03)]},
			{"kind": &"04kv", "points": [Vector2(29.49, 28.53), Vector2(31.51, 28.80), Vector2(33.49, 30.03)]},
			{"kind": &"04kv", "points": [Vector2(24.51, 26.03), Vector2(22.51, 25.53), Vector2(19.07, 27.51)]},
			{"kind": &"04kv", "points": [Vector2(24.51, 26.03), Vector2(24.05, 28.51)]},
		],
		"transformers": [Vector2(7.45, 7.49), Vector2(-8.51, 7.33), Vector2(28.91, 7.49), Vector2(31.51, 22.00)],
		"unfed": [Vector2(14.00, 7.00)],
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
		# південний схід до рядка 26; відгалуження 10 кВ — до південно-східних хат кільця (рядком 26). Решту (стовпи, підстанції, гілки 0.4 кВ) обчислює tools/power_grid.py між мітками нижче.
		"routes": [
			{"kind": &"10kv", "axis": [Vector2(-13, -5), Vector2(-4, -5), Vector2(-4, 2), Vector2(8, 2), Vector2(8, 6), Vector2(12, 6), Vector2(12.5, 11), Vector2(13, 12.5), Vector2(13, 15), Vector2(17, 15), Vector2(17, 19), Vector2(29, 19), Vector2(29, 26), Vector2(38, 26)], "side": 1.0},
			{"kind": &"10kv", "axis": [Vector2(29, 26), Vector2(20, 26)], "side": 1.0, "from": 0},
		],
		# power:begin ridge
		"lines": [
			{"kind": &"10kv", "points": [Vector2(-12.49, -5.55), Vector2(-9.34, -5.51), Vector2(-7.34, -5.51), Vector2(-3.49, -5.55), Vector2(-3.09, -1.49), Vector2(-2.81, 1.49), Vector2(1.51, 1.35), Vector2(5.51, 1.35), Vector2(8.51, 1.45), Vector2(8.99, 5.49), Vector2(12.50, 6.37), Vector2(13.50, 10.58), Vector2(13.55, 12.51), Vector2(13.51, 14.07), Vector2(17.51, 14.45), Vector2(18.55, 18.49), Vector2(22.70, 18.49), Vector2(25.45, 18.49), Vector2(29.49, 18.45), Vector2(29.89, 21.51), Vector2(30.41, 25.49), Vector2(33.06, 25.49), Vector2(37.49, 25.45)]},
			{"kind": &"10kv", "points": [Vector2(30.41, 25.49), Vector2(27.40, 25.49), Vector2(23.15, 26.51), Vector2(20.00, 26.51)]},
			{"kind": &"04kv", "points": [Vector2(12.50, 6.37), Vector2(15.49, 6.10), Vector2(15.57, 3.51)]},
			{"kind": &"04kv", "points": [Vector2(13.51, 14.07), Vector2(10.51, 15.03)]},
			{"kind": &"04kv", "points": [Vector2(10.51, 15.03), Vector2(9.49, 17.03)]},
			{"kind": &"04kv", "points": [Vector2(10.51, 15.03), Vector2(10.10, 12.51), Vector2(12.10, 12.51), Vector2(12.49, 14.53)]},
			{"kind": &"04kv", "points": [Vector2(20.00, 26.51), Vector2(16.75, 27.51), Vector2(18.25, 31.51)]},
		],
		"transformers": [Vector2(12.50, 6.37), Vector2(13.51, 14.07), Vector2(20.00, 26.51)],
		"unfed": [],
		# power:end ridge
		"hay": [Vector2(16.5, 4.5), Vector2(9.5, 17.5), Vector2(7.5, 9.5), Vector2(19.5, 7.5)],
	},
}


static func for_map(key: StringName) -> Dictionary:
	return LAYOUTS.get(key, {})
