#!/usr/bin/env python3
"""Заміри яскравості рівних ділянок кадру — єдиний інструмент для чисел «дах/стіна» у звітах і рецензіях.

    measure_patch.py <кадр.png> <ім'я>=x0,y0,x1,y1 [<ім'я>=...] [--show <оверлей.png>]
    measure_patch.py --table <каталог кадрів> [tools/prop_patches.json] [--show <каталог оверлеїв>]

У режимі --table бере ділянки з prop_patches.json для кадрів <модель>_rl.png і <модель>_cr.png
і друкує таблицю roof/wall під обома світлами.

Для кожної ділянки (x1, y1 не входять, як у зрізі numpy): середнє sRGB 0..255 (його й порівнюють
рецензенти) і середня ЛІНІЙНА яскравість Y = 0.2126 R + 0.7152 G + 0.0722 B по пікселях після
переведення sRGB → лінійне. Якщо є ділянки roof і wall — друкує roof/wall лінійної яскравості.
Відношення яскравості sRGB (гамма) — не те саме: 0.66 у sRGB ≈ 0.40 лінійно.
--show малює прямокутники на копії кадру, щоб будь-хто перевірив, що міряли саме дах і стіну.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw


def srgb_to_linear(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def measure(img, box):
    x0, y0, x1, y1 = box
    px = img[y0:y1, x0:x1].reshape(-1, 3)
    lin = srgb_to_linear(px)
    y = lin @ np.array([0.2126, 0.7152, 0.0722])
    return px.mean(0), float(y.mean())


def table(argv):
    import json, os
    d = argv[2]
    rest = argv[3:]
    show = None
    if "--show" in rest:
        show = rest[rest.index("--show") + 1]
        rest = rest[:rest.index("--show")]
        os.makedirs(show, exist_ok=True)
    spec = json.load(open(rest[0] if rest else os.path.join(os.path.dirname(__file__), "prop_patches.json")))
    print(f"{'модель':12s} {'світло':6s} {'дах sRGB':>14s} {'стіна sRGB':>14s} {'Y дах':>7s} {'Y стіна':>8s} {'дах/стіна':>9s}")
    for name, boxes in spec.items():
        if name.startswith("_"):
            continue
        for light in ("rl", "cr"):
            path = os.path.join(d, f"{name}_{light}.png")
            if not os.path.exists(path):
                continue
            img = np.asarray(Image.open(path).convert("RGB")).astype(float)
            (rr, ry), (wr, wy) = measure(img, boxes["roof"]), measure(img, boxes["wall"])
            fmt = lambda c: "(%d,%d,%d)" % tuple(round(v) for v in c)
            print(f"{name:12s} {light:6s} {fmt(rr):>14s} {fmt(wr):>14s} {ry:7.4f} {wy:8.4f} {ry / wy:9.2f}")
            if show:
                im = Image.open(path).convert("RGB")
                dr = ImageDraw.Draw(im)
                for k, (x0, y0, x1, y1) in boxes.items():
                    dr.rectangle((x0, y0, x1 - 1, y1 - 1), outline=(255, 0, 0) if k == "roof" else (0, 255, 255))
                im.save(os.path.join(show, f"{name}_{light}.png"))


def main(argv):
    if len(argv) > 2 and argv[1] == "--table":
        return table(argv)
    if len(argv) < 3:
        sys.exit(__doc__)
    path, show, boxes = argv[1], None, {}
    rest = argv[2:]
    while rest:
        a = rest.pop(0)
        if a == "--show":
            show = rest.pop(0)
            continue
        name, coords = a.split("=")
        boxes[name] = tuple(int(v) for v in coords.split(","))
    img = np.asarray(Image.open(path).convert("RGB")).astype(float)
    res = {}
    for name, box in boxes.items():
        rgb, y = measure(img, box)
        res[name] = y
        print(f"{name:8s} {box}  sRGB=({rgb[0]:.0f},{rgb[1]:.0f},{rgb[2]:.0f})  Ylin={y:.4f}")
    if "roof" in res and "wall" in res:
        print(f"roof/wall (лінійна яскравість) = {res['roof'] / res['wall']:.2f}")
    if show:
        im = Image.open(path).convert("RGB")
        d = ImageDraw.Draw(im)
        for name, (x0, y0, x1, y1) in boxes.items():
            d.rectangle((x0, y0, x1 - 1, y1 - 1), outline=(255, 0, 0) if name == "roof" else (0, 255, 255), width=1)
            d.text((x0 + 2, y0 + 1), name, fill=(255, 255, 0))
        im.save(show)


if __name__ == "__main__":
    main(sys.argv)
