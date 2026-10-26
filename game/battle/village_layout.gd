class_name VillageLayout
extends RefCounted
## Макет сіл карт, складений вручну, як справжня місцевість: садиби (хата фасадом до дороги, город за
## хатою, сарай, один паркан довкола двору з воротами до дороги), сади між садибами, тюки на краю
## поля, траси ЛЕП через усю карту вздовж доріг. Лише вигляд: правила, як і раніше, читають клітинки
## карти. Процедура PropLayer лишається для дрібниць (поворот тюків, уламки) і для кільця за дошкою.
## Схеми — tools/maps/README.md, «Села».
##
## Садиба: house — клітинка BUILDING хати; face — куди дивиться фасад (і ворота); cells — усі
## клітинки двору; garden — клітинки городу за хатою; shed — клітинка сараю (необов'язково).
## Лінія: kind — &"10kv" чи &"04kv"; points — ламана в координатах дошки по узбіччю (~0.6 клітинки
## від осі дороги), від краю до краю чи відгалуження від стовпа іншої лінії. Стовпи — на кожному
## зламі й не далі SPAN один від одного.

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
			{"house": Vector2i(15, 15), "face": N, "cells": [Vector2i(14, 15), Vector2i(15, 15), Vector2i(15, 16), Vector2i(16, 16), Vector2i(16, 17)],
				"garden": [Vector2i(14, 15), Vector2i(15, 16), Vector2i(16, 17)], "shed": Vector2i(16, 16)},
			{"house": Vector2i(22, 13), "face": W, "cells": [Vector2i(22, 13), Vector2i(23, 13), Vector2i(22, 14)],
				"garden": [Vector2i(23, 13)], "shed": Vector2i(22, 14)},
			{"house": Vector2i(12, 17), "face": E, "cells": [Vector2i(11, 17), Vector2i(12, 17)], "garden": [Vector2i(11, 17)]},
		],
		"orchards": [Vector2i(16, 6), Vector2i(16, 7), Vector2i(5, 8)],
		# 10 кВ — уздовж центральної дороги від краю до краю; через річку — поруч із мостом, стовпи на
		# берегах. 0.4 кВ — уздовж верхньої, нижньої й східної доріг.
		"lines": [
			{"kind": &"10kv", "points": [Vector2(13.6, -0.4), Vector2(13.6, 21.4)]},
			{"kind": &"04kv", "points": [Vector2(13.6, 2.4), Vector2(3.6, 2.4), Vector2(3.4, 8.6)]},
			{"kind": &"04kv", "points": [Vector2(13.6, 18.6), Vector2(20.4, 18.6), Vector2(20.4, 21.4)]},
			{"kind": &"04kv", "points": [Vector2(20.4, 18.6), Vector2(20.4, 4.4), Vector2(25.4, 4.4)]},
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
		# 10 кВ уздовж головних доріг; у місті дорога рядом 8 переходить у забудову, тож лінія огинає
		# квартал північною й південною вулицями, не над дахами.
		"lines": [
			{"kind": &"10kv", "points": [Vector2(-0.4, 7.4), Vector2(7.4, 7.4), Vector2(7.4, 5.4), Vector2(17.6, 5.4),
				Vector2(17.6, 7.4), Vector2(25.4, 7.4)]},
			# 0.4 кВ відгалужується від 10 кВ і обходить квартал західною, південною й східною вулицями.
			# Друга 10 кВ поруч лише дублювала б першу: дві паралельні лінії за клітинку читаються помилкою.
			# Південно-східний кут вулиць — біля болота (18,16), стовпа там нема: дві гілки без кута.
			{"kind": &"04kv", "points": [Vector2(7.4, 7.4), Vector2(7.4, 15.6), Vector2(16.6, 15.6)]},
			{"kind": &"04kv", "points": [Vector2(17.6, 7.4), Vector2(17.6, 14.4)]},
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
		# 10 кВ уздовж головної дороги через усю карту, з заходу на схід.
		"lines": [
			# Сільська лінія не повторює кожен вигин ґрунтівки: прямо між кутовими опорами, через поля, —
			# північним узбіччям дороги рядка 2, навскіс до середини карти, далі до дороги рядка 19.
			{"kind": &"10kv", "points": [Vector2(-0.4, 1.4), Vector2(8.6, 1.4), Vector2(11.4, 8.4), Vector2(14.2, 13.8),
				Vector2(16.4, 18.4), Vector2(25.4, 18.4)]},
		],
		"hay": [Vector2(16.5, 4.5), Vector2(9.5, 17.5), Vector2(7.5, 9.5), Vector2(19.5, 7.5)],
	},
}


static func for_map(key: StringName) -> Dictionary:
	return LAYOUTS.get(key, {})
