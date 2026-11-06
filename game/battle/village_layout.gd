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
## клітинки двору; garden — клітинки городу за хатою; shed — клітинка сараю (необов'язково); fenced — клітинки
## поза двором (не BUILDING), які паркан обгороджує разом із ним, щоб двір був прямокутником довкола хати
## (необов'язково); street — хата на розі двору при вулиці: паркан по зовнішніх межах її клітинки йде врівень зі
## стінами, а не перед ними (необов'язково).
## Траса 10 кВ (routes): kind — &"10kv"; axis — вісь дороги у світових координатах (дошка плюс кільце); side — з якого
## боку від осі за ходом іде лінія (+1 ліворуч, −1 праворуч); from — індекс траси, від чийого стовпа відгалужується
## ця (для відгалужень). Стовпи, ТП і мережу 0.4 кВ уздовж вулиць сіл PowerGrid будує сам.

const N := Vector2i(0, -1)
const S := Vector2i(0, 1)
const E := Vector2i(1, 0)
const W := Vector2i(-1, 0)

const LAYOUTS: Dictionary = {
	&"river": {
		"homes": [
			# Паркан — повний квадрат 2×2: без (12,7) він упирався б у південну стіну хати. Хата на розі двору при вулиці
			# (street): до асфальту ~1.5 м, тож паркан продовжує фасад і північну стіну.
			{"house": Vector2i(12, 6), "face": E, "cells": [Vector2i(11, 6), Vector2i(12, 6), Vector2i(11, 7)], "fenced": [Vector2i(12, 7)],
				"garden": [Vector2i(11, 6)], "shed": Vector2i(11, 7), "street": true},
			# (16,6) і (16,7) — над болотом: паркан туди не дістає, тож вони — лук поза двором.
			{"house": Vector2i(15, 6), "face": W, "cells": [Vector2i(15, 6), Vector2i(15, 7)], "shed": Vector2i(15, 7)},
			{"house": Vector2i(8, 4), "face": N, "cells": [Vector2i(7, 4), Vector2i(8, 4)], "garden": [Vector2i(7, 4)]},
			{"house": Vector2i(12, 4), "face": E, "cells": [Vector2i(11, 4), Vector2i(12, 4)], "garden": [Vector2i(11, 4)]},
			# (5,8) — на березі: паркан туди не дістає, тож клітинка — лук поза двором. Паркан іде на дві клітинки на північ:
			# в одній клітинці він ліг би впритул до стін хати, а ворота до дороги — за хатою на екрані.
			{"house": Vector2i(5, 7), "face": W, "cells": [Vector2i(5, 7)], "fenced": [Vector2i(5, 5), Vector2i(5, 6)]},
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
		"routes": [
			{"kind": &"10kv", "axis": [Vector2(6, -13), Vector2(6, 3), Vector2(13, 3), Vector2(13, 5), Vector2(21, 5), Vector2(21, 18), Vector2(19, 18), Vector2(19, 34)], "side": 1.0},
			# Хутори на краю світу: лінія від краю вздовж бічної дороги до хати.
			{"kind": &"10kv", "axis": [Vector2(38, -0.8), Vector2(33, -0.8)], "side": 1.0},
			{"kind": &"10kv", "axis": [Vector2(-13, 22.5), Vector2(-8, 22.5)], "side": 1.0},
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
		"routes": [
			{"kind": &"10kv", "axis": [Vector2(-13, 8), Vector2(7, 8)], "side": 1.0},
			{"kind": &"10kv", "axis": [Vector2(38, 8), Vector2(31, 8), Vector2(31, 22)], "side": 1.0},
		],
		"hay": [Vector2(6.0, 10.5), Vector2(19.5, 10.5), Vector2(6.4, 18.4), Vector2(22.5, 4.5)],
	},
	&"ridge": {
		"homes": [
			# Садиба відступає від дороги на клітинку: між парканом і узбіччям — смуга лугу, ворота — на дорогу.
			{"house": Vector2i(14, 5), "face": W, "cells": [Vector2i(14, 4), Vector2i(14, 5), Vector2i(15, 5)],
				"garden": [Vector2i(15, 5)], "shed": Vector2i(14, 4)},
			{"house": Vector2i(11, 16), "face": E, "cells": [Vector2i(10, 16), Vector2i(11, 16), Vector2i(11, 17)],
				"garden": [Vector2i(10, 16)], "shed": Vector2i(11, 17)},
		],
		"orchards": [],
		"routes": [
			# Траса не йде впритул до дороги, а зрізає поле сходинками з кутами біля обох хат (ТП на куті, хата живиться
			# відводом) і перетинає дорогу впоперек: на півночі вона на схід від дороги, на півдні — на захід, обабіч
			# хати. Вісь тут — намічена лінія мінус узбіччя (PowerGrid.VERGE), а не вісь дороги.
			{"kind": &"10kv", "axis": [Vector2(-13, -5), Vector2(-4, -5), Vector2(-4, 3.8), Vector2(7.6, 3.8), Vector2(7.6, 7.4), Vector2(12.6, 7.4), Vector2(12.6, 10.4), Vector2(10.6, 10.4), Vector2(10.6, 15.4), Vector2(15.6, 15.4), Vector2(15.6, 19), Vector2(29, 19), Vector2(29, 26), Vector2(38, 26)], "side": 1.0},
			{"kind": &"10kv", "axis": [Vector2(29, 26), Vector2(20, 26)], "side": 1.0, "from": 0},
		],
		"hay": [Vector2(16.5, 4.5), Vector2(9.5, 17.5), Vector2(7.5, 9.5), Vector2(19.5, 7.5)],
	},
}


static func for_map(key: StringName) -> Dictionary:
	return LAYOUTS.get(key, {})
