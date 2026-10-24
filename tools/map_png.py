"""Renders every tools/maps/*.txt with its outer ring to <out>/<map>.png for review by eye.
The playable board is outlined; the ring outside it is landscape only (no rule reads it).

    python3 tools/map_png.py <out_dir>
"""
import pathlib, re, sys
from PIL import Image, ImageDraw

CELL = 10
# Колір на (вид, підтип); підтип за легендою tools/maps/README.md.
COL = {
    ('=', '0'): '#55524c', ('=', '1'): '#8a7350', ('=', '2'): '#77736b',
    ('.', '0'): '#7a9450', ('.', '1'): '#7b5e3c',
    ('T', '0'): '#3f5c34', ('T', '1'): '#2f4a30', ('T', '2'): '#4f6e36',
    '^': '#c4ad74', '~': '#56664a', 'w': '#3a6b8a', 'B': '#b0a596', 'r': '#6e6a63',
    'H': '#a08a5a', 'x': '#5a4a3a',
}


def grid(text, sec):
    m = re.search(rf'^{sec}:\n(.*?)(?=^\w+:|\Z)', text, re.S | re.M)
    return [l for l in m.group(1).split('\n') if l and not l.startswith('#')] if m else None


def render(path, out):
    text = path.read_text()
    tiles, surf = grid(text, 'tiles'), grid(text, 'surface')
    mm = re.search(r'^outer_margin=(\d+)', text, re.M)
    mg = int(mm.group(1)) if mm else 0
    outer = grid(text, 'outer') or tiles
    osurf = grid(text, 'outer_surface')
    h, w = len(tiles), len(tiles[0])
    img = Image.new('RGB', (len(outer[0]) * CELL, len(outer) * CELL))
    d = ImageDraw.Draw(img)
    for y, row in enumerate(outer):
        for x, c in enumerate(row):
            s = osurf[y][x] if osurf else '.'
            if c == '#':  # на місці дошки — сама дошка з tiles:
                c = tiles[y - mg][x - mg]
                s = surf[y - mg][x - mg] if surf else '.'
            col = COL.get((c, '0' if s == '.' else s)) or COL[c]
            d.rectangle([x * CELL, y * CELL, (x + 1) * CELL - 1, (y + 1) * CELL - 1], fill=col)
    d.rectangle([mg * CELL - 1, mg * CELL - 1, (mg + w) * CELL, (mg + h) * CELL], outline='#ff3030', width=2)
    img.save(out / f'{path.stem}.png')
    print(out / f'{path.stem}.png')


out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for p in sorted(pathlib.Path(__file__).parent.joinpath('maps').glob('*.txt')):
    render(p, out)
