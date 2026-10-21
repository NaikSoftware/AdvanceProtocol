#!/usr/bin/env python3
"""Обробка текстур місцевості: seamless, normal, height, imports, match, check. Запуск: python3 -I tools/terrain_tex.py <cmd> ..."""
import sys
import numpy as np
from PIL import Image

LIMIT = 2.5  # шов / типова різниця сусідів усередині


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
    n = np.stack([-dx * strength,  # OpenGL/Godot: X = -dh/dx
                   dy * strength, np.ones_like(g)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return tie((n * 0.5 + 0.5) * 255)


def height(a, sigma=6.0):
    # sigma 6 px: сирий піксельний шум яскравості давав би рваний паралакс (променя стрибає на десятки текселів).
    # Висота з яскравості: світле (камінь, пучок трави) вище, темне (колія, калюжа, щілина) нижче.
    # Гаусс через FFT з wrap — карта висот тайлиться так само, як альбедо. Перцентилі 1..99 -> 0..1,
    # щоб шейдер міг рахувати глибину в частках однієї шкали для всіх шарів.
    g = a @ np.array([0.299, 0.587, 0.114], np.float32)
    h, w = g.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    g = np.fft.ifft2(np.fft.fft2(g) * k).real
    lo, hi = np.percentile(g, [1, 99])
    return tie(np.clip((g - lo) / (hi - lo), 0, 1) * 255)


def save_rgba(a, hgt, p):
    # Висота — в альфі альбедо: один семпл дає колір і висоту, масиви лишаються двома.
    rgba = np.dstack([np.clip(a + 0.5, 0, 255), np.clip(hgt + 0.5, 0, 255)]).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(p)


_M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], np.float32)
_WHITE = np.array([0.9505, 1.0, 1.089], np.float32)


def to_lab(rgb):
    c = rgb / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    f = (lin @ _M.T) / _WHITE
    f = np.where(f > 0.008856, np.cbrt(f), 7.787 * f + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def from_lab(lab):
    fy = (lab[..., 0] + 16) / 116
    f = np.stack([fy + lab[..., 1] / 500, fy, fy - lab[..., 2] / 200], -1)
    f = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * _WHITE
    lin = np.clip(f @ np.linalg.inv(_M).T, 0, 1)
    c = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    return np.clip(c, 0, 1) * 255


def blur(g, sigma):
    h, w = g.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    return np.fft.ifft2(np.fft.fft2(g) * np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))).real


def match(a, ref, chroma=1.0, contrast=1.0, gain=1.0, hf=1.0, hfs=4.0):
    # Перенос середнього й std по каналах у Lab: структура макро лишається, тон — з еталона.
    # chroma масштабує a/b навколо сірого, contrast — відхили від середнього, gain — L.
    la, lr = to_lab(a), to_lab(ref)
    ma, sa = la.mean((0, 1)), la.std((0, 1)) + 1e-6
    mr, sr = lr.mean((0, 1)), lr.std((0, 1))
    out = (la - ma) / sa * sr * contrast + mr
    if hf != 1.0:
        # Дрібні штрихи (лезо трави 2-4 px) на ближньому зумі читаються як «шкрябини»:
        # зменшуємо амплітуду частот вище ~4 px (9 см), великі форми не чіпаємо.
        low = blur(out[..., 0], hfs)
        out[..., 0] = low + (out[..., 0] - low) * hf
    out[..., 1:] = out[..., 1:] * chroma
    out[..., 0] = out[..., 0] * gain
    return tie(from_lab(out))


def edge_diffs(a):
    # Останній рядок/стовпець після tie() дорівнює першому, тому міряємо справжній шов:
    # сусід по колу — це 1022 і 0, а не 1023 і 0. Абсолютний поріг 6/255 тут безглуздий:
    # у детальній текстурі сусідні пікселі відрізняються на 20-40 самі по собі. Тому шов
    # порівнюємо з типовою різницею сусідів усередині: це відношення, ~1 = шва не видно.
    sx = np.abs(a[:, 0] - a[:, -2]).mean() / np.abs(np.diff(a[:, :-1], axis=1)).mean()
    sy = np.abs(a[0] - a[-2]).mean() / np.abs(np.diff(a[:-1], axis=0)).mean()
    return sx, sy


def main(argv):
    if len(argv) >= 3 and argv[0] == "seamless":
        save(seamless(load(argv[1])), argv[2])
    elif len(argv) >= 3 and argv[0] == "normal":
        s = float(argv[argv.index("--strength") + 1]) if "--strength" in argv else 2.0
        save(normal(load(argv[1]), s), argv[2])
    elif len(argv) >= 3 and argv[0] == "height":
        a = load(argv[1])
        s = float(argv[argv.index("--sigma") + 1]) if "--sigma" in argv else 6.0
        save_rgba(a, height(a, s), argv[2])
    elif len(argv) >= 2 and argv[0] == "imports":
        # .import для PNG макро-текстур: ті самі правила, що в assets/terrain (VRAM, міпмапи,
        # fix_alpha_border=false — альфа тут висота). Godot сам дописує uid/path при імпорті.
        import glob
        tpl = open("assets/terrain/mud_albedo.png.import").read()
        params = tpl[tpl.index("[params]"):]
        for png in sorted(glob.glob(argv[1] + "/*.png")):
            res = "res://" + png
            open(png + ".import", "w").write(
                '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                f'[deps]\n\nsource_file="{res}"\n\n' + params)
            print("wrote", png + ".import")
    elif len(argv) >= 4 and argv[0] == "match":
        opt = lambda k, d: float(argv[argv.index(k) + 1]) if k in argv else d
        save(match(load(argv[1]), load(argv[2]), opt("--chroma", 1.0), opt("--contrast", 1.0), opt("--gain", 1.0), opt("--hf", 1.0), opt("--hfs", 4.0)), argv[3])
    elif len(argv) >= 3 and argv[0] == "macro":
        # Повний прогін СИРИХ макро: тон з еталона (стара деталь шару в HEAD), висота в альфу, .import.
        # Запускати лише на сирих файлах: match нормалізує std, але hf/contrast накопичувались би.
        import subprocess, io
        # contrast 0.55: макро з Lab-std еталона давало «камуфляж» (еталон — дрібна деталь, макро — великі плями).
        preset = {"road": dict(contrast=0.4, gain=0.72), "marsh": dict(chroma=0.5, hf=0.5, contrast=0.55),
                  "field": dict(hf=0.5, contrast=0.55), "forest": dict(hf=0.6, contrast=0.55),
                  # Баки колій у багні — не до смаку власнику (2026-10-21): контраст 0.3 і зрізання штрихів
                  # до ~23 см (hfs 10 px), доки не буде макро без колій.
                  "mud": dict(contrast=0.3, hf=0.25, hfs=10.0),
                  "cobble": dict(gain=0.8)}
        for n in ("hill", "rubble", "bank"):
            preset[n] = dict(contrast=0.55)
        # Еталон тону: стара деталь шару в HEAD; ґрунтівка — середнє доріг і багна.
        ref_of = {"dirt": ("road", "mud"), "cobble": ("road",)}
        sig = {"field": 5.0, "marsh": 5.0}
        import os
        variants = int(argv[argv.index("--variants") + 1]) if "--variants" in argv else 2
        for name in ["road", "field", "forest", "hill", "marsh", "mud", "rubble", "bank", "dirt", "cobble"]:
            ref = np.concatenate([np.asarray(Image.open(io.BytesIO(subprocess.check_output(
                ["git", "show", f"HEAD:assets/terrain/{r}_albedo.png"]))).convert("RGB"), np.float32)
                for r in ref_of.get(name, (name,))])
            # Сирий варіант n: <шар>_<n>.png; нема — <шар>_albedo.png (старе ім'я варіанта 0), далі варіант 0.
            raw0 = next((f for f in (f"{argv[1]}/{name}_0.png", f"{argv[1]}/{name}_albedo.png") if os.path.exists(f)), None)
            if raw0 is None:  # шар підтипу без сирого файлу — пропускаємо (GroundSurface візьме базовий)
                continue
            for n in range(variants):
                src = f"{argv[1]}/{name}_{n}.png"
                a = load(src if os.path.exists(src) else raw0)
                if a.shape[0] != 512:  # сирі Tripo 2048 px -> 512 (12 м, ~2.3 см/px)
                    a = np.asarray(Image.fromarray(a.astype(np.uint8)).resize((512, 512), Image.LANCZOS), np.float32)
                m = match(a, ref, **preset.get(name, {}))
                save_rgba(m, height(m, sig.get(name, 3.0)), f"{argv[2]}/{name}_albedo_{n}.png")
            print("macro", name)
    elif argv and argv[0] == "selftest":
        r = np.tile(np.linspace(0, 255, 64, dtype=np.float32), (64, 1))[:, :, None].repeat(3, 2)
        up = r.transpose(1, 0, 2)[::-1]  # росте до верху зображення
        R = normal(r, 2)[:, :, 0].mean()
        G = normal(up, 2)[:, :, 1].mean()
        print(f"ramp right: mean R={R:.1f} (want <127.5); ramp to top: mean G={G:.1f}")
        assert R < 127.5
        assert G < 127.5, "поверхня росте до верху: нормаль дивиться вниз, G<128"
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
