#!/usr/bin/env python3
"""Обробка текстур місцевості: seamless, normal, check. Запуск: python3 -I tools/terrain_tex.py <cmd> ..."""
import sys
import numpy as np
from PIL import Image

LIMIT = 6.0  # макс. середня різниця протилежних країв, з 255


def load(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)


def save(a, p):
    Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8)).save(p)


def tie(a):
    # Дублюємо перший рядок/стовпець в останній: краї збігаються точно (1 px з 1024 невидимий).
    # Без цього сусідні пікселі шуму дають різницю країв ~20/255 навіть у ідеальному тайлі.
    a[:, -1] = a[:, 0]
    a[-1] = a[0]
    return a


def seamless(a):
    # Змішуємо з копією, зсунутою на півкартинки: вага 0 на краях, 1 в центрі,
    # тож краї беруться з центру зсунутої копії, а вона стикується сама з собою.
    h, w = a.shape[:2]
    wy = 1 - np.abs(2 * (np.arange(h) + 0.5) / h - 1)
    wx = 1 - np.abs(2 * (np.arange(w) + 0.5) / w - 1)
    m = (wy[:, None] * wx[None, :])[:, :, None]
    # shortcut: лінійна вага трохи «розмиває» контраст у центрі, коли дефекти помітні — міняти на smoothstep
    return tie(a * m + np.roll(a, (h // 2, w // 2), (0, 1)) * (1 - m))


def normal(a, strength):
    g = a @ np.array([0.299, 0.587, 0.114], np.float32) / 255.0
    p = lambda dy, dx: np.roll(g, (dy, dx), (0, 1))  # wrap: нормаль теж тайлиться
    dx = (p(-1, -1) + 2 * p(0, -1) + p(1, -1)) - (p(-1, 1) + 2 * p(0, 1) + p(1, 1))
    dy = (p(-1, -1) + 2 * p(-1, 0) + p(-1, 1)) - (p(1, -1) + 2 * p(1, 0) + p(1, 1))
    n = np.stack([dx * strength, dy * strength, np.ones_like(g)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return tie((n * 0.5 + 0.5) * 255)


def edge_diffs(a):
    return (np.abs(a[:, 0] - a[:, -1]).mean(), np.abs(a[0] - a[-1]).mean())


def main(argv):
    if len(argv) >= 3 and argv[0] == "seamless":
        save(seamless(load(argv[1])), argv[2])
    elif len(argv) >= 3 and argv[0] == "normal":
        s = float(argv[argv.index("--strength") + 1]) if "--strength" in argv else 2.0
        save(normal(load(argv[1]), s), argv[2])
    elif argv and argv[0] == "check":
        bad = 0
        for p in argv[1:]:
            lr, tb = edge_diffs(load(p))
            ok = lr <= LIMIT and tb <= LIMIT
            bad += not ok
            print(f"{'ok  ' if ok else 'FAIL'} {p}  lr={lr:.2f} tb={tb:.2f}")
        return 1 if bad else 0
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
