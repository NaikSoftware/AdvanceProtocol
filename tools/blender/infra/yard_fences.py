"""Паркани сільських дворів: п'ять видів в одній моделі й одному атласі (один виклик малювання на всі двори).

Кожен вид — двобічна картка 8 м уздовж X із альфою. Атлас — п'ять смуг одна над одною; смуга k (рахуючи згори, як
UV.y у Godot) — вид k, і шейдер prop_thin (uniform kinds) лишає з картки лише вид екземпляра (INSTANCE_CUSTOM.r):
решту вершин стягує в точку. Смуга вкриває висоту 0..H_MAX, тож v — це висота; u по довжині шейдер рахує сам,
кроком TILE_M від початку секції (стовп — на стику секцій).

Види відрізняються формою, не лише кольором (prop_thin знебарвлює фарбу): штахет 1.3 м, профлист 1.8 м суцільний,
сітка-рабиця 1.5 м на трубах, цегляний цоколь із металевими прутами 1.6 м, горизонтальні дошки 1.45 м. Дерево —
кольору кори й старої дошки, не світле.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *

KINDS = ("picket", "sheet", "chainlink", "brickbars", "slat")
TILE_M = 2.5          # крок стовпів, м — один повтор текстури по довжині
H_MAX = 2.0           # висота, яку вкриває смуга атласу, м
W, HS = 256, 192      # смуга: ~1 см на тексель уздовж, ~1 см угору
HEIGHT = {"picket": 1.3, "sheet": 1.8, "chainlink": 1.5, "brickbars": 1.6, "slat": 1.45}


def _grid():
    """Координати текселів смуги в метрах: x уздовж (0..TILE_M), z угору (0..H_MAX); рядок 0 — низ (як у Blender)."""
    x = (np.arange(W) + 0.5) / W * TILE_M
    z = (np.arange(HS) + 0.5) / HS * H_MAX
    return np.meshgrid(x, z)


def _grain(seed, cx=6, cy=40):
    """Волокна дошки: шум, витягнутий уздовж (cy > cx — уздовж z)."""
    n = tile_noise(cx, cy, max(W, HS), seed)
    return n[:HS, :W]


def _post(xx, x0, w):
    return np.abs(((xx - x0 + TILE_M / 2) % TILE_M) - TILE_M / 2) < w / 2


def picket():
    """Штахет: дошки 8 см з просвітом 7.6 см, верх дошки трохи гуляє, дві планки позаду, стовп 10 см на стику."""
    xx, zz = _grid()
    rng = np.random.default_rng(71)
    pitch = TILE_M / 16
    idx = np.floor(xx / pitch).astype(int) % 16
    fx = (xx / pitch) % 1.0
    top = 1.22 + rng.uniform(-0.05, 0.03, 16)[idx]
    point = top - 0.06 * np.abs(fx - 0.5) * 2                    # скошений верх дошки
    board = (np.abs(fx - 0.5) < 0.26) & (zz > 0.06) & (zz < point)
    rail = ((np.abs(zz - 0.3) < 0.035) | (np.abs(zz - 1.0) < 0.035)) & (zz < 1.3)
    post = _post(xx, 0.05, 0.10) & (zz < 1.3)
    tone = rng.uniform(0.82, 1.08, 16)[idx]
    g = _grain(73)
    base = np.array([0.29, 0.25, 0.21])                         # сіро-бура стара дошка, не світла
    col = base * (tone * (0.82 + 0.3 * g))[..., None]
    col = np.where(board[..., None], col, col * 0.6)            # планки й стовп — у тіні дощок
    col = np.where((board & (np.abs(fx - 0.5) > 0.2))[..., None], col * 0.6, col)   # темні краї дощок
    col = np.where(post[..., None], base * 0.62 * (0.85 + 0.3 * g)[..., None], col)
    col = col * np.where(zz < 0.18, 0.75, 1.0)[..., None]       # бруд біля землі
    return col, (board | rail | post).astype(float)


def sheet():
    """Профнастил 1.8 м: трапецієвидні ребра кроком ~0.21 м, темно-коричневий (RAL 8017), суцільний, бруд унизу."""
    xx, zz = _grid()
    pitch = TILE_M / 12
    f = (xx / pitch) % 1.0
    # профіль ребра: верх 0.25, схили по 0.15, дно 0.45 кроку — світло-тінь рельєфу під денним світлом
    shade = np.select([f < 0.25, f < 0.40, f < 0.85], [1.12, 0.92, 0.80], 0.70)
    g = tile_noise(8, 8, max(W, HS), 75)[:HS, :W]
    base = np.array([0.27, 0.19, 0.15])
    col = base * (shade * (0.9 + 0.2 * g))[..., None]
    col = col * np.where(zz < 0.25, 0.7 + 0.3 * zz / 0.25, 1.0)[..., None]      # бруд і бризки знизу
    col = np.where((zz > 1.75)[..., None], col * 0.65, col)                     # загнутий верхній край
    rust = (tile_noise(24, 6, max(W, HS), 77)[:HS, :W] > 0.82) & (zz < 0.6)
    col = np.where(rust[..., None], col * np.array([1.25, 0.85, 0.6]), col)
    return col, (zz < 1.8).astype(float)


def chainlink():
    """Сітка-рабиця на трубах: ромб 5 см, дріт ~3 мм — на текселі товщий, щоб здалеку сітка лишалась сірою пеленою, а не
    зникала; труба-стовп 6 см і верхня труба."""
    xx, zz = _grid()
    cell = 0.05
    a = ((xx + zz) / cell) % 1.0
    b = ((xx - zz) / cell) % 1.0
    wire = ((a < 0.34) | (b < 0.34)) & (zz > 0.05) & (zz < 1.45)
    post = _post(xx, 0.03, 0.06) & (zz < 1.52)
    pipe = (np.abs(zz - 1.46) < 0.02)
    g = tile_noise(16, 16, max(W, HS), 79)[:HS, :W]
    wire_col = np.array([0.30, 0.30, 0.29]) * (0.8 + 0.3 * g)[..., None]       # стара оцинковка, приглушена
    steel = np.array([0.17, 0.17, 0.18]) * (0.85 + 0.3 * g)[..., None]
    col = np.where((post | pipe)[..., None], steel, wire_col)
    col = np.where(((zz < 0.4) & wire)[..., None], col * np.array([0.95, 0.8, 0.65]), col)  # рудий наліт знизу
    return col, (wire | post | pipe).astype(float)


def brickbars():
    """Цоколь 0.5 м із темної цегли, бетонна шапка, металеві прути 4 см кроком 12 см до 1.6 м (тонші на зумі 8 зникали);
    цегляний стовп 38 см на стику."""
    xx, zz = _grid()
    row = np.floor(zz / 0.075)
    u = (xx / 0.25 + 0.5 * (row % 2)) % 1.0
    v = (zz / 0.075) % 1.0
    mortar = (u < 0.05) | (v < 0.13)
    g = tile_noise(20, 20, max(W, HS), 81)[:HS, :W]
    brick = np.array([0.33, 0.19, 0.15]) * (0.8 + 0.35 * g)[..., None]
    brick = np.where(mortar[..., None], np.array([0.24, 0.22, 0.20]), brick)
    pillar = _post(xx, 0.19, 0.38) & (zz < 1.66)
    base = zz < 0.5
    cap = ((zz >= 0.5) & (zz < 0.56)) | (pillar & (zz >= 1.6))
    bars = (np.abs(((xx / 0.12) % 1.0) - 0.5) < 0.17) & (zz >= 0.56) & (zz < 1.6)
    rails = ((np.abs(zz - 0.66) < 0.025) | (np.abs(zz - 1.1) < 0.02) | (np.abs(zz - 1.56) < 0.03)) & (zz < 1.6)
    steel = np.array([0.15, 0.15, 0.16]) * (0.85 + 0.3 * g)[..., None]
    col = np.where((base | pillar)[..., None], brick, steel)
    col = np.where(cap[..., None], np.array([0.26, 0.25, 0.23]) * (0.85 + 0.3 * g)[..., None], col)
    col = col * np.where(zz < 0.12, 0.78, 1.0)[..., None]
    return col, (base | pillar | cap | bars | rails).astype(float)


def slat():
    """Горизонтальні дошки 12 см з просвітом 4 см від 0.1 до 1.45 м, стовп 10 см на стику; стара темна деревина."""
    xx, zz = _grid()
    rng = np.random.default_rng(83)
    pitch = 0.16
    k = np.floor((zz - 0.1) / pitch).astype(int)
    fz = ((zz - 0.1) / pitch) % 1.0
    board = (fz < 0.75) & (zz >= 0.1) & (zz < 1.45)
    tone = rng.uniform(0.8, 1.1, 16)[np.clip(k, 0, 15)]
    g = tile_noise(40, 6, max(W, HS), 85)[:HS, :W]               # волокна вздовж дошки (по x)
    base = np.array([0.27, 0.23, 0.19])
    col = base * (tone * (0.82 + 0.3 * g))[..., None]
    col = np.where((board & ((fz < 0.08) | (fz > 0.67)))[..., None], col * 0.65, col)   # тінь під кромкою
    post = _post(xx, 0.05, 0.10) & (zz < 1.5)
    col = np.where(post[..., None], base * 0.6 * (0.85 + 0.3 * g)[..., None], col)
    col = col * np.where(zz < 0.2, 0.75, 1.0)[..., None]
    return col, (board | post).astype(float)


def atlas():
    """Смуги згори вниз — у порядку KINDS (рядки масиву йдуть знизу, тож вид 0 — найвищі рядки)."""
    strips = []
    for k in reversed(KINDS):
        col, alpha = globals()[k]()
        strips.append(np.concatenate([np.clip(col, 0, 1), alpha[..., None]], -1))
    # Без карти нормалей: prop_thin нахиляє нормаль картки до неба, і рельєф текстури на зумі 8 не читався б.
    return pbr("yard_fence_atlas", albedo=np.concatenate(strips, 0), tile=TILE_M, rough=0.92, alpha=True, double_sided=True)


def build(name="infra_fence_yard"):
    b = B()
    mat = atlas()
    uv = b.bm.loops.layers.uv.verify()
    n = len(KINDS)
    for k, kind in enumerate(KINDS):
        h = HEIGHT[kind] + 0.06
        vs = [b.bm.verts.new(p) for p in ((-4, 0, 0), (4, 0, 0), (4, 0, h), (-4, 0, h))]
        f = b.bm.faces.new(vs)
        f.material_index = b.mi(mat)
        b.skip_uv.add(f)
        b.keep.add(f)
        # v у Blender — знизу; смуга виду k у Godot (UV.y згори) — [k/n, (k+1)/n], тут — [1 − (k+1)/n, 1 − k/n].
        # Відступ 1 % від меж смуги: шейдер бере вид як floor(UV.y·n), і точна межа дала б сусідній вид.
        for l in f.loops:
            z = l.vert.co.z
            l[uv].uv = ((l.vert.co.x + 4) / TILE_M, (n - 1 - k + 0.01 + 0.98 * z / H_MAX) / n)
    finish(b, name, jpeg=False, floor=0.0)


reset()
if want("infra_fence_yard"):
    build()
