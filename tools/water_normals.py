#!/usr/bin/env python3
"""Карти нормалей води (Phase 5a, Task 6). Запуск: python3 -I tools/water_normals.py

Висота — шум зі смугою частот (випадковий спектр, обернене FFT), тож тайл
періодичний точно, без змішування країв. Нормаль — та сама конвенція, що в
terrain_tex.py: X = -dh/dx, +Y — угору картинки (OpenGL/Godot).

Найдовші хвилі — ~10 циклів на картинку, далі спектр спадає степенево, тож
переважають ~10–14 циклів. Масштаб на воді задає water.gdshader (A повторюється
кожні ~8 м — брижа ~0.5–0.8 м; B — кожні ~4 м, ~0.25–0.4 м).
"""
import numpy as np
from PIL import Image

SIZE = 512
OUT = "assets/water/water_normal_%s.png"


def height(seed, k_lo=10.0, k_hi=45.0):
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(SIZE) * SIZE  # цикли на картинку
    k = np.hypot(f[None, :], f[:, None])
    k[0, 0] = 1.0
    # Степеневий спектр (як у брижі на воді), м'яко обрізаний знизу на k_lo і зверху
    # на k_hi. Вузька смуга частот дає «лабіринт» однакових черв'ячків — регулярний
    # візерунок, який око ловить одразу.
    amp = k ** -2.8 * (1.0 - np.exp(-((k / k_lo) ** 4))) * np.exp(-((k / k_hi) ** 2))
    amp[0, 0] = 0.0
    spec = amp * (rng.normal(size=(SIZE, SIZE)) + 1j * rng.normal(size=(SIZE, SIZE)))
    h = np.real(np.fft.ifft2(spec))
    return h / np.abs(h).max()


def normal(h, rms_slope=0.5):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) * 0.5  # +Y — угору картинки
    s = rms_slope / np.sqrt(np.mean(dx * dx + dy * dy))
    n = np.stack([-dx * s, -dy * s, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return np.clip((n * 0.5 + 0.5) * 255 + 0.5, 0, 255).astype(np.uint8)


if __name__ == "__main__":
    for name, seed in (("a", 11), ("b", 29)):
        Image.fromarray(normal(height(seed))).save(OUT % name)
        print("wrote", OUT % name)
