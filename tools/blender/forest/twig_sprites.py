"""Вирізає спрайти хвойних гілок із CC0-текстур Poly Haven (pine_tree_01, fir_tree_01).

Запуск: python3 -I twig_sprites.py <каталог із twig_diff/twig_alpha png> <вихідний каталог>
Вхідні файли: <asset>_twig_diff_<asset>_twig_diff_1k.png і ..._twig_alpha_...png.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

# Рамки островів гілок на атласі 1024x1024 (виміряні на перегляді).
BOXES = {
    "pine": [(26, 38, 243, 461), (640, 326, 973, 538)],
    "fir": [(192, 38, 435, 320), (666, 26, 998, 384), (307, 422, 666, 794), (640, 448, 998, 845)],
}

for kind, asset in (("pine", "pine_tree_01"), ("fir", "fir_tree_01")):
    d = Image.open(f"{src}/{asset}_twig_diff_{asset}_twig_diff_1k.png").convert("RGB")
    a = Image.open(f"{src}/{asset}_twig_alpha_{asset}_twig_alpha_1k.png").convert("L")
    for i, box in enumerate(BOXES[kind]):
        rgb = np.asarray(d.crop(box), dtype=np.float32)
        al = np.asarray(a.crop(box), dtype=np.float32)
        al = np.clip((al - 90) / 80, 0, 1)  # жорсткіший край: під alpha-cut
        # Поза островом UV альфа біла: заливка від рамки прибирає шматки кори.
        bw = Image.fromarray((al > 0.5).astype(np.uint8) * 255)
        for x in range(0, bw.width, 6):
            for y in (0, bw.height - 1):
                if bw.getpixel((x, y)) == 255:
                    ImageDraw.floodfill(bw, (x, y), 128)
        for y in range(0, bw.height, 6):
            for x in (0, bw.width - 1):
                if bw.getpixel((x, y)) == 255:
                    ImageDraw.floodfill(bw, (x, y), 128)
        al = al * (np.asarray(bw) != 128)
        if kind == "pine":  # кора лишається там, де заливка не дотягнулась: голки зеленіші за неї
            al = al * (rgb[..., 1] >= rgb[..., 0] * 0.97)
        if kind == "pine" and i == 0:
            al[285:] = 0  # шматок кори під стеблом
            al[:, 190:] = 0
        # Прозорі пікселі беруть середній колір голок, інакше мипи дають світлий ореол.
        m = al > 0.5
        mean = rgb[m].mean(axis=0) if m.any() else rgb.mean(axis=(0, 1))
        rgb = np.where(m[..., None], rgb, mean)
        img = np.dstack([rgb, al * 255]).astype(np.uint8)
        im = Image.fromarray(img, "RGBA")
        bb = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        im.crop(bb).save(f"{out}/{kind}_{i}.png")
        print(kind, i, im.crop(bb).size)
