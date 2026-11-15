#!/usr/bin/env python3
"""Запікає плиту-фон екрана передачі й паузи (assets/ui/gate/<map>.webp) з кадру без юнітів.

Кадр — стан `mood` інструмента tools/hud_shot.gd без HUD (юнітів у ньому немає, тож плита
нічого не видає). Потрібні numpy і Pillow.

    tools/godot_run.sh --path . res://tools/hud_shot.tscn -- <dir> <map> 1600x720 uk mood hud=off
    python3 -I tools/bake_gate.py <dir>/<map>_1600x720_mood_nohud.png assets/ui/gate/<map>.webp \\
        [--rain] [--band cy,sigma_y,sigma_x,alpha]

--rain — рідкі смуги дощу (карта з дощем, як Річка). --band — м'яка еліптична смуга скриму за
підписом «ПЕРЕДАЙТЕ ПРИСТРІЙ», у пікселях кадру, коли під ним світла стіна. Розширення виходу
задає формат. Скрипт друкує середню яскравість, std, p99 і max — за ними плиту звіряють.
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(np.float32)

# Червона лінія краю дошки — тонка й насичена, дахи темніші й ширші. Її пікселі (розширені на 1)
# замінює медіана 9 px кадру.
r, g, b = a[..., 0], a[..., 1], a[..., 2]
line = (r > 150) & (r - g > 90) & (r - b > 90)
mask = Image.fromarray((line * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))
med = np.asarray(im.filter(ImageFilter.MedianFilter(9))).astype(np.float32)
m = (np.asarray(mask) > 0)[..., None]
a = np.where(m, med, a)

# Темніше на ~55 % і мінус 35 % насиченості: увесь колір на гейті належить кольору гравця.
lum = (a @ np.array([.2126, .7152, .0722], np.float32))[..., None]
a = (lum + (a - lum) * .65) * .45

# Скрим знизу вгору: #0d1013 на 85 % біля нижнього краю, зникає на 55 % висоти.
h = a.shape[0]
t = np.clip((np.arange(h)[::-1] / h) / .55, 0, 1)
alpha = (.85 * (1 - t) ** 1.6)[:, None, None]
scrim = np.array([13, 16, 19], np.float32)
a = a * (1 - alpha) + scrim * alpha
# Скрим зверху: у верхніх кутах кадру світлий холодний туман краю світу. 80 % біля верхнього
# краю, зникає на 35 % висоти, у кутах трохи густіше.
yy = np.arange(h)[:, None] / h
xx = np.abs(np.arange(a.shape[1])[None, :] / a.shape[1] - .5) * 2
alpha = (.80 * np.clip(1 - yy / .35, 0, 1) ** 1.4 * (.75 + .25 * xx))[..., None]
a = a * (1 - alpha) + scrim * alpha

# Дощ: тонкі смуги ~12° від вертикалі, світліші на 6–14 рівнів.
if "--rain" in sys.argv:
    rng = np.random.default_rng(7)
    rain = Image.new("L", (a.shape[1], h), 0)
    d = ImageDraw.Draw(rain)
    for _ in range(int(a.shape[1] * h / 2600)):
        x, y = rng.uniform(-60, a.shape[1]), rng.uniform(-60, h)
        ln = rng.uniform(18, 46)
        d.line((x, y, x + ln * .21, y + ln), fill=int(rng.uniform(6, 14)), width=1)
    a = a + np.asarray(rain.filter(ImageFilter.GaussianBlur(.4))).astype(np.float32)[..., None] * 1.2

# Смуга за підписом: світла стіна під літерами інакше з'їдає контраст підпису. Центр x — центр кадру.
if "--band" in sys.argv:
    cy, sy, sx, al = [float(v) for v in sys.argv[sys.argv.index("--band") + 1].split(",")]
    yy2 = (np.arange(h)[:, None] - cy) / sy
    xx2 = (np.arange(a.shape[1])[None, :] - a.shape[1] / 2) / sx
    alpha = (al * np.exp(-(yy2 ** 2 + xx2 ** 2) / 2))[..., None]
    a = a * (1 - alpha) + scrim * alpha

Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(out, optimize=True)
L = np.asarray(Image.open(out).convert("L")).astype(np.float32)
print(f"{out}: mean {L.mean():.1f} std {L.std():.1f} p99 {np.percentile(L, 99):.0f} max {L.max():.0f}")
