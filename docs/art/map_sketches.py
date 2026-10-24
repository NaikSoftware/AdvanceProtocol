"""Throwaway: draws 3 map concepts (180-degree symmetric) and measures turns base to base."""
import heapq, sys

W, H = 26, 22
PEN = {'=': 0, 'H': 0, 'r': 5, '.': 10, '^': 20, 'T': 20, 'B': 100, '~': None, 'w': None}
COL = {'=': '#6b6558', 'H': '#a08a5a', 'r': '#6e6a63', '.': '#7a9450', '^': '#a08c5c',
       'T': '#3f5c34', 'B': '#8a8378', '~': '#56664a', 'w': '#3a6b8a'}
UNITS = {'піхота': (30, 80), 'розвідка': (48, 8), 'бронеавто': (68, 5), 'сер. танк': (48, 12), 'важкий': (40, 9)}


def blank():
    return [['.'] * W for _ in range(H)]


def rect(g, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = c


def mirror(g):
    for y in range(H // 2, H):
        for x in range(W):
            g[y][x] = g[H - 1 - y][W - 1 - x]


def turns(g, a, b, ap, xc):
    def cost(c):
        p = PEN[c]
        return None if p is None or 10 + p - xc > ap else max(10, 10 + p - xc)
    dist = {a: 0}
    q = [(0, a)]
    while q:
        d, (x, y) = heapq.heappop(q)
        if (x, y) == b:
            return d / ap
        if d > dist[(x, y)]:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H:
                c = cost(g[ny][nx])
                if c is not None and d + c < dist.get((nx, ny), 1e9):
                    dist[(nx, ny)] = d + c
                    heapq.heappush(q, (d + c, (nx, ny)))
    return None


def concept_river():
    g = blank()
    rect(g, 0, 10, W - 1, 10, 'w')
    for x in (4, 12, 13, 21):
        g[10][x] = 'H'
    rect(g, 0, 8, 2, 9, '~'); rect(g, 23, 9, 25, 9, '~'); rect(g, 7, 9, 9, 9, '~')
    rect(g, 13, 3, 13, 9, '=')
    rect(g, 4, 3, 13, 3, '='); rect(g, 4, 3, 4, 9, '='); rect(g, 6, 1, 6, 2, '=')
    rect(g, 10, 6, 11, 8, 'B'); rect(g, 15, 6, 16, 8, 'B'); g[7][14] = 'r'; g[6][12] = 'B'
    rect(g, 17, 1, 24, 5, 'T'); rect(g, 19, 6, 21, 7, 'T'); rect(g, 0, 4, 2, 6, 'T')
    rect(g, 6, 5, 8, 7, '^'); g[5][9] = '^'
    rect(g, 0, 0, 3, 1, 'T')
    mirror(g)
    return g, (6, 1), (19, 20)


def concept_crossroads():
    g = blank()
    rect(g, 9, 7, 16, 10, 'B')
    rect(g, 4, 1, 4, 8, '='); rect(g, 0, 8, 7, 8, '='); rect(g, 17, 8, 25, 8, '=')
    rect(g, 9, 6, 16, 6, '='); rect(g, 8, 6, 8, 10, '=')
    g[9][10] = 'r'; g[7][15] = 'r'; g[10][13] = 'r'
    rect(g, 18, 2, 23, 6, 'T'); rect(g, 19, 7, 22, 7, '^'); rect(g, 24, 3, 25, 6, '^')
    rect(g, 6, 3, 9, 4, 'w'); rect(g, 5, 5, 10, 5, '~')
    rect(g, 2, 0, 5, 1, 'T')
    mirror(g)
    return g, (4, 1), (21, 20)


def concept_ridge():
    g = blank()
    for i in range(-14, 15):
        for t in (-1, 0, 1):
            x, y = 12 + i + t, 10 - i
            if 0 <= x < W and 0 <= y < H // 2:
                g[y][x] = '^' if t else 'T'
    for x, y in ((12, 10), (13, 9), (11, 10)):
        g[y][x] = '.'
    rect(g, 7, 2, 12, 2, '='); rect(g, 12, 1, 12, 10, '=')
    rect(g, 4, 4, 6, 5, 'B'); g[5][7] = 'r'
    rect(g, 19, 0, 21, 2, 'w'); rect(g, 18, 3, 22, 3, '~')
    for x, y in ((5, 7), (6, 6)):
        g[y][x] = '.'
    mirror(g)
    return g, (7, 2), (18, 19)


def html_grid(g, a, b):
    cells = []
    for y in range(H):
        for x in range(W):
            mark = '1' if (x, y) == a else ('0' if (x, y) == b else '')
            cells.append(f'<div style="background:{COL[g[y][x]]}">{mark}</div>')
    return ('<div style="display:grid;grid-template-columns:repeat(%d,12px);gap:1px;'
            'font:bold 9px sans-serif;color:#fff;text-align:center;line-height:12px">%s</div>'
            % (W, ''.join(cells)))


def main(out):
    concepts = [
        ('a', 'Річка з трьома мостами', concept_river(),
         'Річка ділить карту. Центральний міст веде в містечко, де господарює піхота; два флангові '
         'мости інженер може підірвати. У кожного гравця своя швидка дорога до «свого» флангу.'),
        ('b', 'Перехрестя', concept_crossroads(),
         'Містечко в центрі — суцільні квартали, техніка йде лише вулицями. Один фланг відкритий '
         '(танкове поле за ставком), другий — ліс і пагорби для піхоти й розвідки.'),
        ('c', 'Хребет', concept_ridge(),
         'Лісистий хребет по діагоналі між базами. Один прохід дорогою в центрі, дві вузькі '
         'щілини по краях, хутір на схилі.'),
    ]
    cards = []
    for key, name, (g, a, b), text in concepts:
        rows = ''.join(
            f'<tr><td>{u}</td><td style="padding-left:12px">'
            f'{(t := turns(g, a, b, ap, xc)) and f"{t:.1f}" or "—"}</td></tr>'
            for u, (ap, xc) in UNITS.items())
        cards.append(f'''<div class="card" data-choice="{key}" onclick="toggleSelect(this)">
  <div class="card-image" style="padding:10px;background:#222">{html_grid(g, a, b)}</div>
  <div class="card-body"><h3>{key.upper()}. {name}</h3><p>{text}</p>
  <p class="label">ходів від бази до бази</p><table>{rows}</table></div></div>''')
    legend = ''.join(f'<span style="display:inline-block;margin-right:12px">'
                     f'<span style="display:inline-block;width:12px;height:12px;background:{COL[c]}"></span> {n}</span>'
                     for c, n in (('=', 'дорога'), ('.', 'поле'), ('T', 'ліс'), ('^', 'пагорб'), ('B', 'будівлі'),
                                  ('r', 'руїни'), ('~', 'болото'), ('w', 'вода'), ('H', 'міст')))
    with open(out, 'w') as f:
        f.write(f'''<h2>Яка ідея карти вам ближча?</h2>
<p class="subtitle">Грубі ескізи 26×22, центральна симетрія — кожен гравець має дзеркально ту саму позицію.
«0» і «1» — бази. Місцевість впливає лише на ціну руху, тож стратегія — це маршрути, вузькі місця й мости.
Числа — реальна кількість ходів від бази до бази за нашими правилами руху (без ворога на шляху).</p>
<p>{legend}</p>
<div class="cards">{''.join(cards)}</div>''')


main(sys.argv[1])
