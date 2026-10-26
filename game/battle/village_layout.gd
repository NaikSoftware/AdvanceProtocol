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
		# 10 кВ — від краю до краю кільця: північною дорогою кільця, узбіччям дороги рядка 3 і далі на південь вздовж
		# дороги колонки 13 через міст (стовпи на берегах: проліт через річку — 4.4 клітинки). Кожна підстанція — на стовпі
		# магістралі біля свого поселення; 0.4 кВ від неї доходить до дворів, схід — від південної підстанції.
		"lines": [
			{"kind": &"10kv", "points": [Vector2(6.53, -12.49), Vector2(6.52, -8.51), Vector2(6.51, -4.31), Vector2(6.51, -2.51), Vector2(9.51, -2.51), Vector2(9.51, 1.69), Vector2(9.51, 2.47), Vector2(13.51, 2.49), Vector2(13.51, 5.74), Vector2(13.51, 7.94), Vector2(13.51, 12.39), Vector2(13.51, 13.24), Vector2(13.51, 16.82), Vector2(13.51, 21.02), Vector2(13.51, 24.48), Vector2(13.51, 28.68), Vector2(13.51, 32.88), Vector2(13.51, 33.49)]},
			{"kind": &"04kv", "points": [Vector2(13.51, 5.74), Vector2(12.49, 5.03), Vector2(10.82, 4.51), Vector2(7.49, 5.53)]},
			{"kind": &"04kv", "points": [Vector2(13.51, 13.24), Vector2(13.53, 14.49)]},
			{"kind": &"04kv", "points": [Vector2(13.53, 14.49), Vector2(12.28, 14.49)]},
			{"kind": &"04kv", "points": [Vector2(13.53, 14.49), Vector2(15.49, 14.28), Vector2(19.28, 13.51)]},
		],
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
		# 10 кВ — від краю до краю кільця вздовж доріг: на захід від міста північним узбіччям дороги рядка 8, повз місто
		# північною вулицею (рядок 6), далі на схід узбіччям рядка 8. Підстанція — на стовпі магістралі біля міста;
		# від неї 0.4 кВ іде між садибами, опори — у дворах поза обрисом будинків.
		"lines": [
			{"kind": &"10kv", "points": [Vector2(-12.49, 6.51), Vector2(-8.29, 6.51), Vector2(-4.09, 6.51), Vector2(0.11, 6.51), Vector2(3.49, 6.51), Vector2(6.49, 6.51), Vector2(6.49, 5.49), Vector2(10.69, 5.49), Vector2(11.86, 5.49), Vector2(16.06, 5.49), Vector2(17.49, 5.49), Vector2(17.51, 7.49), Vector2(21.71, 7.49), Vector2(25.91, 7.49), Vector2(30.11, 7.49), Vector2(34.31, 7.49), Vector2(37.49, 7.49)]},
			{"kind": &"04kv", "points": [Vector2(11.86, 5.49), Vector2(12.49, 6.62), Vector2(13.49, 7.87), Vector2(11.49, 10.62), Vector2(14.51, 12.62)]},
		],
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
		# 10 кВ — від краю до краю кільця вздовж єдиної дороги: західною дільницею північним узбіччям, далі сходинками
		# дороги на південний схід (стовпи біля узбіччя, на межах клітинок) і виходом на схід кільцевою дорогою. Кожна
		# садиба — з підстанцією на найближчому стовпі магістралі й однією опорою 0.4 кВ, від якої відвід до хати.
		"lines": [
			{"kind": &"10kv", "points": [Vector2(-12.49, -5.51), Vector2(-8.53, -5.51), Vector2(-5.51, -5.51), Vector2(-5.51, -1.31), Vector2(-5.51, 0.49), Vector2(-1.31, 0.49), Vector2(2.89, 0.49), Vector2(7.09, 0.49), Vector2(7.49, 0.49), Vector2(7.49, 4.69), Vector2(7.49, 6.51), Vector2(8.49, 6.59), Vector2(11.49, 6.85), Vector2(11.49, 10.70), Vector2(11.49, 12.49), Vector2(12.33, 13.51), Vector2(12.49, 14.49), Vector2(13.51, 14.07), Vector2(17.51, 14.49), Vector2(17.51, 17.45), Vector2(17.51, 19.51), Vector2(19.45, 19.51), Vector2(23.65, 19.51), Vector2(27.97, 19.51), Vector2(28.32, 23.51), Vector2(28.49, 25.49), Vector2(32.69, 25.49), Vector2(36.89, 25.49), Vector2(37.49, 25.49)]},
			{"kind": &"04kv", "points": [Vector2(8.49, 6.59), Vector2(10.32, 5.49)]},
			{"kind": &"04kv", "points": [Vector2(11.49, 10.70), Vector2(11.49, 13.28)]},
		],
		"hay": [Vector2(16.5, 4.5), Vector2(9.5, 17.5), Vector2(7.5, 9.5), Vector2(19.5, 7.5)],
	},
}


static func for_map(key: StringName) -> Dictionary:
	return LAYOUTS.get(key, {})
