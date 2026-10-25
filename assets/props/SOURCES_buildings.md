# Джерела будівель (tools/blender/buildings)

Усе, що потрапило у `.glb` будівель, — CC0 або написане в цьому репозиторії.

## Скани уламків (геометрія)

Poly Haven, ліцензія CC0 (<https://polyhaven.com/license>), 1k glTF, зведені `make_debris_lib.py` до ~110
трикутників кожен і записані в `tools/blender/buildings/debris_scans.json`. Колір і текстура — власні (мозаїка
уламків із `lib.py`), з сканів береться лише форма.

| актив | сторінка |
| --- | --- |
| rock_07 | <https://polyhaven.com/a/rock_07> |
| rock_09 | <https://polyhaven.com/a/rock_09> |
| stone_01 | <https://polyhaven.com/a/stone_01> |
| namaqualand_boulder_05 | <https://polyhaven.com/a/namaqualand_boulder_05> |
| namaqualand_boulder_06 | <https://polyhaven.com/a/namaqualand_boulder_06> |
| namaqualand_rocks_01 | <https://polyhaven.com/a/namaqualand_rocks_01> |

## Матеріали

ambientCG, ліцензія CC0 (<https://docs.ambientcg.com/license/>), 1K JPG, завантажуються
`fetch_textures.sh`: Concrete034, Concrete046, Concrete019, Plaster001, CorrugatedSteel005, CorrugatedSteel007A,
Bricks105, MetalPlates013, Asphalt031, PaintedMetal012, Rust004, Planks021. Кожен атласується (запікається) разом
із картою нормалей у одну текстуру на будівлю.
