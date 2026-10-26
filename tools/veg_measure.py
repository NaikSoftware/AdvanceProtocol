"""Виміри рослинності на КАДРАХ (не на спрайтах і не на атласі): що бачить гравець.

Запуск (звичайний python, numpy + Pillow): python3 -I tools/veg_measure.py <режим> ...

  lum <кадр> [--empty E] [--box x0 y0 x1 y1] [--warm]
      Яскравість пікселів об'єкта (L = 0,2126 R + 0,7152 G + 0,0722 B, 0…255): p10, p50, p90 і
      частка пікселів, світліших за медіану ґрунту навколо. Маска об'єкта — різниця з порожнім
      кадром того самого ракурсу (--empty). Для чужого кропу без порожнього кадру — --warm:
      об'єкт = теплі пікселі (R − B > 6), ґрунт = решта.
  leaf <кадр> --empty E [--box ...]
      Частка листя серед пікселів рослини: листок — насичений (S ≥ 0,33) і не червоний (ягоди
      окремо). Лише на кадрах з --neutral (біле світло, без тону листя): під похмурим світлом
      Річки все ненасичене, а під сонцем Перехрестя тепла кора вдає листя.
"""
import os
import sys

import numpy as np
from PIL import Image

np.seterr(all="ignore")


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float64)


def luma(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def opts(args):
    o = {"box": None, "empty": None, "warm": False}
    i = 0
    rest = []
    while i < len(args):
        a = args[i]
        if a == "--box":
            o["box"] = tuple(int(v) for v in args[i + 1:i + 5])
            i += 5
        elif a == "--empty":
            o["empty"] = args[i + 1]
            i += 2
        elif a == "--warm":
            o["warm"] = True
            i += 1
        else:
            rest.append(a)
            i += 1
    return o, rest


def crop(a, box):
    if box is None:
        return a
    x0, y0, x1, y1 = box
    return a[y0:y1, x0:x1]


def object_mask(a, o):
    if o["warm"]:
        return (a[..., 0] - a[..., 2]) > 6.0
    e = crop(load(o["empty"]), o["box"])
    return np.abs(a - e).sum(-1) > 12.0


def cmd_lum(args):
    o, rest = opts(args)
    a = crop(load(rest[0]), o["box"])
    m = object_mask(a, o)
    L = luma(a)
    ground = np.median(L[~m]) if (~m).any() else float("nan")
    obj = L[m]
    print("%s: px %d  L p10 %.0f  p50 %.0f  p90 %.0f  ground p50 %.0f  brighter than ground %.0f%%" % (
        os.path.basename(rest[0]), m.sum(), np.percentile(obj, 10), np.percentile(obj, 50),
        np.percentile(obj, 90), ground, 100.0 * (obj > ground).mean()))


def cmd_leaf(args):
    o, rest = opts(args)
    a = crop(load(rest[0]), o["box"])
    m = object_mask(a, o)
    rgb = a[m] / 255.0
    mx, mn = rgb.max(1), rgb.min(1)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    red = (rgb[:, 0] > rgb[:, 1] * 1.8) & (sat > 0.45)
    leaf = (sat >= 0.33) & ~red
    print("%s: px %d  листя %.0f%%  ягоди %.0f%%" % (os.path.basename(rest[0]), m.sum(), 100 * leaf.mean(), 100 * red.mean()))


if __name__ == "__main__":
    {"lum": cmd_lum, "leaf": cmd_leaf}[sys.argv[1]](sys.argv[2:])
