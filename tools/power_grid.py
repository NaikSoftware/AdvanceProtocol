#!/usr/bin/env python3
"""Генератор опор ЛЕП для VillageLayout: з намірів (routes) і будівель карти обчислює, де стоїть кожен
стовп, і пише результат (lines, transformers) у game/battle/village_layout.gd між мітками
`# power:begin <карта>` і `# power:end <карта>`.

Рельєф, дороги, майданчики й паркани змінюються, тож опори не вгадуються вручну. Після таких змін:

    $GODOT --headless --path . --script tools/power_dump.gd -- /tmp/power.json crossroads ridge river
    python3 tools/power_grid.py /tmp/power.json crossroads ridge river

Тест test_power_lines_match_the_terrain (tests/game/test_prop_layer.gd) падає, коли збережена опора вже
не може стати на своє місце або порушує правила мережі: тоді генератор запускають знову.

Правила місця стовпа (ті самі, що в PropLayer._pole_on): межа клітинок (поза слідом юніта), не на
дорозі (≥ ROAD від асфальту), не ближче WET до води й болота, не в клітинці лісу, руїн, моста, не
ближче BLD до обрису будь-якої будівлі, не в обрисі парканів і дрібних речей. Проліт — не довший за
MAXSPAN і не ближче BLD до обрису будівлі. Відвід — від стовпа до стіни не довший за DROPMAX, не
ближче DROP_GAP до чужих будівель і не через дорогу. Кут між будь-якими двома прольотами на стовпі —
не гостріший за 80°, сусідні стовпи — не ближче MINSPAN, крім кутового.
"""
import heapq
import json
import math
import re
import sys
from pathlib import Path

BLD = 0.5       # стовп і проліт від обрису будь-якої будівлі
BLD_HOME = 0.3  # стовп, що живить хату, може стояти ближче до неї самої (PropLayer.POLE_HOME_CLEAR)
PROP = 0.1      # стовп від паркану й дрібної речі
GARDEN = 0.02   # стовп від грядок (край городу — місце)
ROAD = 0.2      # стовп від краю асфальту
WET = 0.55      # стовп від води й болота
MAXSPAN = 4.5
MINSPAN = 2.0
ROOTMIN = 3.0   # перший проліт від підстанції — звичайний проліт, а не скупчення опор
DROPMAX = 1.5
DROPMIN = 0.3
DROP_GAP = 0.25
SETTLE_R = 6.0
LAT = 1.1       # наскільки стовп магістралі може відійти від лінії узбіччя, коли на ній нема місця
FIELD, FOREST, HILL, BUILDING = 1, 2, 3, 6
LAYOUT = Path(__file__).resolve().parent.parent / "game/battle/village_layout.gd"


def rnd(v):
    """Як roundi у Godot: половина — від нуля."""
    return int(math.floor(abs(v) + 0.5)) * (1 if v >= 0 else -1)


class Net:
    def __init__(self, name, data):
        self.name = name
        self.r = data["ring"]
        self.W, self.H = data["size"]
        self.wk = data["wkinds"]
        self.bld = [b["rect"] for b in data["buildings"]]
        self.homes = data["homes"]
        self.houses = [h["rect"] for h in self.homes]
        self.oth = [o["rect"] for o in data["others"] if o["model"] != "garden"]
        self.gar = [o["rect"] for o in data["others"] if o["model"] == "garden"]
        self.brg = [b["rect"] for b in data["bridges"]]
        self.spawns = [tuple(s) for s in data["spawns"]]
        self.roads = data["roads"]
        self.routes = data["routes"]
        self.home_rects = {tuple(h["rect"]) for h in self.homes}
        self._why = {}
        self._relax = {}
        self._span = {}
        self._rix = self._road_index()
        self._bix = self._rect_index(self.bld)
        self._oix = self._rect_index(self.oth)
        self._gix = self._rect_index(self.gar)
        self._xix = self._rect_index(self.brg)

    # --- індекси ------------------------------------------------------------------------
    def _road_index(self):
        ix = {}
        for ln in self.roads:
            for k in range(1, len(ln)):
                a, b = ln[k - 1], ln[k]
                h = max(a[2], b[2])
                for cx in range(math.floor(min(a[0], b[0]) - h - 0.5), math.ceil(max(a[0], b[0]) + h + 0.5) + 1):
                    for cy in range(math.floor(min(a[1], b[1]) - h - 0.5), math.ceil(max(a[1], b[1]) + h + 0.5) + 1):
                        ix.setdefault((cx, cy), []).append((a, b, h))
        return ix

    @staticmethod
    def _rect_index(rects):
        ix = {}
        for r in rects:
            for cx in range(math.floor(r[0] - 0.7), math.ceil(r[0] + r[2] + 0.7) + 1):
                for cy in range(math.floor(r[1] - 0.7), math.ceil(r[1] + r[3] + 0.7) + 1):
                    ix.setdefault((cx, cy), []).append(r)
        return ix

    # --- запити -------------------------------------------------------------------------
    def kind(self, c):
        x, y = c[0] + self.r, c[1] + self.r
        return self.wk[y][x] if 0 <= y < len(self.wk) and 0 <= x < len(self.wk[0]) else -1

    def road_d(self, p):
        """Відстань від краю асфальту (від'ємна — на асфальті)."""
        best = 9e9
        for a, b, h in self._rix.get((rnd(p[0]), rnd(p[1])), []):
            dx, dy = b[0] - a[0], b[1] - a[1]
            ll = dx * dx + dy * dy
            t = 0 if ll < 1e-9 else max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ll))
            best = min(best, math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy) - h)
        return best

    def wet_d(self, p):
        c = (rnd(p[0]), rnd(p[1]))
        best = 9
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                n = (c[0] + dx, c[1] + dy)
                if self.kind(n) in (4, 5):
                    nx = max(n[0] - .5, min(p[0], n[0] + .5))
                    ny = max(n[1] - .5, min(p[1], n[1] + .5))
                    best = min(best, math.hypot(p[0] - nx, p[1] - ny))
        return best

    @staticmethod
    def _inside(ix, p, g):
        for r in ix.get((rnd(p[0]), rnd(p[1])), []):
            if r[0] - g <= p[0] <= r[0] + r[2] + g and r[1] - g <= p[1] <= r[1] + r[3] + g:
                return True
        return False

    def why(self, p):
        """None — стовп тут стати може; інакше причина."""
        key = (round(p[0], 3), round(p[1], 3))
        if key not in self._why:
            self._why[key] = self._check(p)
        return self._why[key]

    def why_for(self, p, rect):
        """Те саме, що why, але стовп, який живить хату rect, може стояти до неї на BLD_HOME."""
        key = (round(p[0], 3), round(p[1], 3), tuple(rect))
        if key not in self._relax:
            self._relax[key] = self._check(p, tuple(rect))
        return self._relax[key]

    def _near_building(self, p, relax=None):
        for r in self._bix.get((rnd(p[0]), rnd(p[1])), []):
            g = BLD_HOME if (relax is not None and tuple(r) == relax) else BLD
            if r[0] - g <= p[0] <= r[0] + r[2] + g and r[1] - g <= p[1] <= r[1] + r[3] + g:
                return True
        return False

    def _check(self, p, relax=None):
        c = (rnd(p[0]), rnd(p[1]))
        k = self.kind(c)
        if k not in (FIELD, HILL, BUILDING):
            return "cell%d" % k
        if self._near_building(p, relax):
            return "bld"
        if self._inside(self._oix, p, PROP) or self._inside(self._xix, p, 0.3) or self._inside(self._gix, p, GARDEN):
            return "prop"
        if self.road_d(p) < ROAD:
            return "road"
        if self.wet_d(p) < WET:
            return "wet"
        for sc in self.spawns:
            if abs(p[0] - sc[0]) < 0.54 and abs(p[1] - sc[1]) < 0.54:
                return "spawn"
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                n = (c[0] + dx, c[1] + dy)
                if abs(p[0] - n[0]) < 0.485 and abs(p[1] - n[1]) < 0.485 and self.kind(n) != 5:
                    return "unit"
        return None

    @staticmethod
    def seg_hits(a, b, r, g):
        x0, y0, x1, y1 = r[0] - g, r[1] - g, r[0] + r[2] + g, r[1] + r[3] + g
        if max(a[0], b[0]) < x0 or min(a[0], b[0]) > x1 or max(a[1], b[1]) < y0 or min(a[1], b[1]) > y1:
            return False
        t0, t1 = 0.0, 1.0
        dx, dy = b[0] - a[0], b[1] - a[1]
        for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
            if abs(p) < 1e-12:
                if q < 0:
                    return False
            else:
                t = q / p
                if p < 0:
                    t0 = max(t0, t)
                else:
                    t1 = min(t1, t)
        return t0 <= t1

    def span_ok(self, a, b, relax_a=None, relax_b=None):
        """Проліт не довший за MAXSPAN і не ближче BLD до будівель; біля кінця, що живить хату (relax_*),
        до самої хати можна ближче — BLD_HOME."""
        key = (a, b, relax_a, relax_b) if a < b else (b, a, relax_b, relax_a)
        if key not in self._span:
            ok = math.dist(a, b) <= MAXSPAN - 0.02
            if ok:
                for r in self.bld:
                    g = BLD_HOME if tuple(r) in (relax_a, relax_b) else BLD
                    if self.seg_hits(a, b, r, g):
                        ok = False
                        break
            self._span[key] = ok
        return self._span[key]


ANGLE_COS = 0.1736  # cos 80°: прямий кут з допуском на косу траси


def interior_ok(a, b, c):
    """Кут у b між прольотами ba й bc не гостріший за 80° (прямий з допуском)."""
    la, lb = math.dist(a, b), math.dist(c, b)
    return (a[0] - b[0]) * (c[0] - b[0]) + (a[1] - b[1]) * (c[1] - b[1]) <= ANGLE_COS * la * lb + 1e-6


# --- траси ---------------------------------------------------------------------------------
def offset_poly(pts, side, d=0.55):
    """Ламана на відстані d від осі дороги: праворуч (side < 0) чи ліворуч (side > 0) за ходом."""
    n = len(pts)
    norm = []
    for k in range(1, n):
        dx, dy = pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]
        ll = math.hypot(dx, dy)
        norm.append((side * dy / ll, -side * dx / ll))
    out = []
    for k in range(n):
        if k == 0:
            nn = norm[0]
            out.append((pts[0][0] + nn[0] * d, pts[0][1] + nn[1] * d))
        elif k == n - 1:
            nn = norm[-1]
            out.append((pts[k][0] + nn[0] * d, pts[k][1] + nn[1] * d))
        else:
            a, b = norm[k - 1], norm[k]
            dot = a[0] * b[0] + a[1] * b[1]
            out.append((pts[k][0] + (a[0] + b[0]) / (1 + dot) * d, pts[k][1] + (a[1] + b[1]) / (1 + dot) * d))
    return out


def clamp_world(net, p):
    lo = -net.r - 0.49
    return (min(max(p[0], lo), net.W + net.r - 1 + 0.49), min(max(p[1], lo), net.H + net.r - 1 + 0.49))


def lattice_near(net, p, rad, keep):
    """Придатні місця стовпа на межах клітинок поблизу p, найближчі першими."""
    out = []
    n = int(rad / 0.02)
    for dx in range(-n, n + 1):
        for dy in range(-n, n + 1):
            q = (round(p[0] + dx * 0.02, 2), round(p[1] + dy * 0.02, 2))
            if max(abs(q[0] - rnd(q[0])), abs(q[1] - rnd(q[1]))) < 0.485:
                continue
            d = math.hypot(dx * 0.02, dy * 0.02)
            if d <= rad and net.why(q) is None:
                out.append((d, q))
    out.sort()
    res = []
    for d, q in out:
        if all(math.dist(q, r[1]) >= 0.3 for r in res):
            res.append((d, q))
        if len(res) >= keep:
            break
    return res


def seg_poles(net, A, B):
    """Стовпи між кутами A і B: обидва кінці стоять; між ними — місця поблизу прямої (на межах клітинок)
    з найменшою кількістю стовпів і найменшим відхилом. None — не вийшло."""
    if net.why(A) is not None or net.why(B) is not None:
        return None
    L = math.dist(A, B)
    if L < MINSPAN:
        # короткий відрізок між двома зламами: кутова опора може стояти ближче за MINSPAN
        return [A, B] if L >= 0.8 and net.span_ok(A, B) else None
    ux, uy = (B[0] - A[0]) / L, (B[1] - A[1]) / L
    x0, x1 = min(A[0], B[0]) - LAT - 0.5, max(A[0], B[0]) + LAT + 0.5
    y0, y1 = min(A[1], B[1]) - LAT - 0.5, max(A[1], B[1]) + LAT + 0.5
    pts = {}

    def add(p):
        p = (round(p[0], 2), round(p[1], 2))
        if p in pts:
            return
        t = (p[0] - A[0]) * ux + (p[1] - A[1]) * uy
        dv = abs((p[0] - A[0]) * uy - (p[1] - A[1]) * ux)
        if dv <= LAT and 0.0 < t < L and net.why(p) is None:
            pts[p] = (t, dv)

    for k in range(math.floor(x0) - 1, math.ceil(x1) + 1):
        for o in (0.49, 0.51):
            y = y0
            while y <= y1:
                add((k + o, y))
                y += 0.25
    for k in range(math.floor(y0) - 1, math.ceil(y1) + 1):
        for o in (0.49, 0.51):
            x = x0
            while x <= x1:
                add((x, k + o))
                x += 0.25
    nodes = [(0.0, 0.0, A)] + sorted((t, dv, p) for p, (t, dv) in pts.items()) + [(L, 0.0, B)]
    n = len(nodes)
    cost = [1e9] * n
    prev = [-1] * n
    cost[0] = 0.0
    for j in range(1, n):
        tj, dj, pj = nodes[j]
        preds = []
        for i in range(j - 1, -1, -1):
            ti, di, pi = nodes[i]
            if tj - ti > MAXSPAN:
                break
            if cost[i] >= 1e8:
                continue
            d = math.dist(pi, pj)
            if d < MINSPAN - 1e-6 or d > MAXSPAN - 0.02:
                continue
            preds.append((cost[i] + abs(dj - di) * 1.5, i))
        preds.sort()
        for c, i in preds:
            if net.span_ok(nodes[i][2], pj):
                cost[j] = c + 1.0 + 3.0 * dj * dj
                prev[j] = i
                break
    if cost[n - 1] >= 1e8:
        return None
    path = []
    j = n - 1
    while j >= 0:
        path.append(nodes[j][2])
        j = prev[j]
    return path[::-1]


def plan_route(net, route, anchors):
    """Стовпи однієї траси. Вершини — найближчі придатні місця до зсунутої ламаної; кут у вершині не
    гостріший за прямий; відгалуження починається з наявного стовпа (anchors) під кутом ≥ 90° до його
    прольотів."""
    axis = [tuple(p) for p in route["axis"]]
    off = offset_poly(axis, route["side"])
    spur = route["from"] >= 0
    off = [clamp_world(net, p) if (k == len(off) - 1 or (k == 0 and not spur)) else p for k, p in enumerate(off)]
    first_nb = []
    cand = []
    for k, p in enumerate(off):
        if k == 0 and spur:
            if not anchors:
                return None
            # стовп, від якого відгалуження виходить під прямим кутом до обох прольотів, а не просто найближчий
            ahead = off[1]
            good = [e for e in anchors if math.dist(e[0], p) <= 2.5 and all(
                interior_ok(nb, e[0], (e[0][0] + ahead[0] - p[0], e[0][1] + ahead[1] - p[1])) for nb in e[1])]
            a = min(good or anchors, key=lambda e: math.dist(e[0], p))
            first_nb = a[1]
            cand.append([(math.dist(a[0], p), a[0])])
        else:
            cand.append(lattice_near(net, p, 1.0, 6) or lattice_near(net, p, 1.6, 6))
    if any(not c for c in cand):
        print("  %s: немає місця для вершини %s" % (net.name, [k for k, c in enumerate(cand) if not c]))
        return None
    m = len(off)
    cache = {}

    def sp(k, i, j):
        key = (k, i, j)
        if key not in cache:
            cache[key] = seg_poles(net, cand[k][i][1], cand[k + 1][j][1])
        return cache[key]

    # dp[k][(a, b)] = (ціна, батьківський стан): a — вибір у вершині k-1, b — у вершині k
    dp = [dict() for _ in range(m)]
    for i in range(len(cand[0])):
        for j in range(len(cand[1])):
            pl = sp(0, i, j)
            if pl is None:
                continue
            if any(not interior_ok(nb, pl[0], pl[1]) for nb in first_nb):
                continue
            dp[1][(i, j)] = (len(pl) + cand[0][i][0] * 2 + cand[1][j][0] * 2, None)
    for k in range(2, m):
        for (a, b), (v, _) in list(dp[k - 1].items()):
            pa = sp(k - 2, a, b)
            for c in range(len(cand[k])):
                pb = sp(k - 1, b, c)
                if pb is None or not interior_ok(pa[-2], pa[-1], pb[1]):
                    continue
                t = v + len(pb) + cand[k][c][0] * 2
                if (b, c) not in dp[k] or t < dp[k][(b, c)][0]:
                    dp[k][(b, c)] = (t, (a, b))
    if not dp[m - 1]:
        print("  %s: траса не складається" % net.name)
        return None
    state = min(dp[m - 1], key=lambda s: dp[m - 1][s][0])
    idx = [state[1], state[0]]
    for k in range(m - 1, 1, -1):
        state = dp[k][state][1]
        idx.append(state[0])
    idx.reverse()
    poles = []
    for k in range(m - 1):
        pl = sp(k, idx[k], idx[k + 1])
        poles += pl if k == 0 else pl[1:]
    return poles


# --- поселення -----------------------------------------------------------------------------
def center(h):
    return (h[0] + h[2] / 2, h[1] + h[3] / 2)


def clusters(houses):
    cl = [[h] for h in houses]
    changed = True
    while changed:
        changed = False
        for i in range(len(cl)):
            for j in range(i + 1, len(cl)):
                if any(math.dist(center(a), center(b)) <= SETTLE_R for a in cl[i] for b in cl[j]):
                    cl[i] += cl.pop(j)
                    changed = True
                    break
            if changed:
                break
    return cl


DROP_EAVE = 0.08    # кріплення під кромкою даху (як PropLayer.DROP_EAVE_DROP)
DROP_FLOOR = 0.3    # нижче цієї висоти над ґрунтом кріплення не стає (PropLayer.DROP_MIN_H)
DROP_LIP_MIN = 0.25  # кромка ближче до осі — дірка в зруйнованому даху (PropLayer.DROP_LIP_MIN)
DROP_SAFE = 0.04    # запас на точність (кромка за 72 напрямками, поворот опори)


def home_of(net, rect):
    for h in net.homes:
        if h["rect"] == rect:
            return h
    return None


def drop_to(net, p, rect):
    """Точка кріплення (кромка даху з боку p), якщо відвід від p до хати можливий; інакше None. Правила ті
    самі, що в PropLayer._drop_target: довжина до кромки, висота кромки, зазор до чужих будівель, дорога."""
    h = home_of(net, rect)
    c = center(rect)
    d0 = math.dist(p, c)
    if d0 < 1e-6:
        return None
    ang = math.atan2(p[1] - c[1], p[0] - c[0]) % (2 * math.pi)
    r, top, gnd = h["lips"][int(round(ang / (2 * math.pi / 72))) % 72]
    if r < DROP_LIP_MIN:
        return None
    lip = (c[0] + (p[0] - c[0]) / d0 * r, c[1] + (p[1] - c[1]) / d0 * r)
    d = math.dist(p, lip)
    if d > DROPMAX - DROP_SAFE or d < DROPMIN + DROP_SAFE:
        return None
    if top - gnd < DROP_FLOOR + 0.02 + DROP_SAFE:
        return None
    for r2 in net.bld:
        if r2 != rect and net.seg_hits(p, lip, r2, DROP_GAP):
            return None
    n = int(d / 0.1) + 1
    for i in range(n + 1):
        q = (p[0] + (lip[0] - p[0]) * i / n, p[1] + (lip[1] - p[1]) * i / n)
        if net.road_d(q) < 0.0:
            return None
    return lip


def lattice_box(net, bb, step=0.5, strict=True):
    out = {}
    x0, y0, x1, y1 = bb
    for k in range(math.floor(x0) - 1, math.ceil(x1) + 1):
        for o in (0.49, 0.51):
            y = y0
            while y <= y1:
                if x0 <= k + o <= x1:
                    out[(round(k + o, 2), round(y, 2))] = 1
                y += step
    for k in range(math.floor(y0) - 1, math.ceil(y1) + 1):
        for o in (0.49, 0.51):
            x = x0
            while x <= x1:
                if y0 <= k + o <= y1:
                    out[(round(x, 2), round(k + o, 2))] = 1
                x += step
    return [p for p in out if net.why(p) is None] if strict else list(out)


def relaxed_nodes(net, houses, bb):
    """Місця, де стовп може стояти до хати ближче за BLD (на BLD_HOME), але лише щоб живити її саму."""
    out = {}
    for h in houses:
        c = center(h)
        for p in lattice_box(net, (c[0] - 2.2, c[1] - 2.2, c[0] + 2.2, c[1] + 2.2), 0.25, strict=False):
            if net.why(p) is not None and net.why_for(p, h) is None and bb[0] <= p[0] <= bb[2] and bb[1] <= p[1] <= bb[3]:
                out.setdefault(p, tuple(h))
    return out


def grow_tree(net, root, root_nb, houses, nodes, relax_for):
    """Гілка 0.4 кВ від підстанції root: стовпи так, щоб кожна хата мала відвід. Найдешевший шлях від
    дерева до найближчого непокритого живильника, поки всі не покриті; кути ≥ 90°."""
    feeders = [{p for p in nodes if relax_for.get(p, tuple(h)) == tuple(h) and drop_to(net, p, h) is not None} for h in houses]
    if any(not f for f in feeders):
        return None
    buck = {}
    for p in nodes:
        buck.setdefault((int(p[0] // 4), int(p[1] // 4)), []).append(p)
    nbr = {}

    def neighbours(u):
        if u not in nbr:
            out = []
            bx, by = int(u[0] // 4), int(u[1] // 4)
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    for v in buck.get((bx + ox, by + oy), []):
                        d = math.dist(u, v)
                        if v != u and (ROOTMIN if (u == root or v == root) else MINSPAN) <= d <= MAXSPAN - 0.02 and net.span_ok(u, v, relax_for.get(u), relax_for.get(v)):
                            out.append((v, d))
            nbr[u] = out
        return nbr[u]

    tree = {root: None}
    adj = {root: list(root_nb)}
    covered = [root in f for f in feeders]
    guard = 0
    while not all(covered) and guard < 60:
        guard += 1
        dist = {t: 0.0 for t in tree}
        prev = {}
        pq = [(0.0, t) for t in tree]
        heapq.heapify(pq)
        found = None
        while pq:
            d, u = heapq.heappop(pq)
            if d > dist.get(u, 9e9) + 1e-9:
                continue
            if u not in tree and any((not covered[i]) and u in feeders[i] for i in range(len(houses))):
                found = u
                break
            back = [prev[u]] if u in prev else []
            for v, dd in neighbours(u):
                if v in tree:
                    continue
                if any(not interior_ok(w, u, v) for w in adj.get(u, []) + back):
                    continue
                turn = 0.0
                if back:
                    a = (u[0] - back[0][0], u[1] - back[0][1])
                    b = (v[0] - u[0], v[1] - u[1])
                    turn = 1 - (a[0] * b[0] + a[1] * b[1]) / (math.hypot(*a) * math.hypot(*b))
                nd = d + 1 + 0.02 * dd + 0.6 * turn
                if nd < dist.get(v, 9e9):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
        if found is None:
            return None
        chain = []
        u = found
        while u not in tree:
            chain.append(u)
            u = prev[u]
        top = u
        for node in reversed(chain):
            tree[node] = top
            adj.setdefault(top, []).append(node)
            adj.setdefault(node, []).append(top)
            top = node
        for i, f in enumerate(feeders):
            if any(t in f for t in tree):
                covered[i] = True
    return tree if all(covered) else None


def chains(tree, root):
    kids = {}
    for n, p in tree.items():
        if p is not None:
            kids.setdefault(p, []).append(n)
    out = []
    stack = [root]
    while stack:
        s = stack.pop()
        for c in sorted(kids.get(s, [])):
            ch = [s, c]
            cur = c
            while len(kids.get(cur, [])) == 1:
                cur = kids[cur][0]
                ch.append(cur)
            out.append(ch)
            if len(kids.get(cur, [])) > 1:
                stack.append(cur)
    return out


def plan_settlement(net, cl, poles10):
    xs = [h[0] for h in cl] + [h[0] + h[2] for h in cl]
    ys = [h[1] for h in cl] + [h[1] + h[3] for h in cl]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    bb = (min(xs) - 3.5, min(ys) - 3.5, max(xs) + 3.5, max(ys) + 3.5)
    nodes = lattice_box(net, bb)
    relax_for = relaxed_nodes(net, cl, bb)
    nodes = list(dict.fromkeys(nodes + list(relax_for)))
    # хата, до якої нема де поставити стовп так, щоб відвід був можливий, лишається без відводу
    unfed = [h for h in cl if not any(relax_for.get(p, tuple(h)) == tuple(h) and drop_to(net, p, h) for p in nodes)]
    cl = [h for h in cl if h not in unfed]
    if not cl:
        return None, unfed
    best = None
    near = sorted(poles10, key=lambda p: math.dist(p[0], (cx, cy)))[:8]
    for r, nb in near:
        nd = list(dict.fromkeys(nodes + [r]))
        tree = grow_tree(net, r, nb, cl, nd, relax_for)
        if tree and (best is None or len(tree) < len(best[1])):
            best = (r, tree)
    return best, unfed


# --- запис ---------------------------------------------------------------------------------
def fmt_pts(pts):
    return ", ".join("Vector2(%.2f, %.2f)" % p for p in pts)


def generate(name, data):
    net = Net(name, data)
    lines = []        # (kind, points)
    poles10 = []      # (позиція, сусіди-стовпи)
    for ri, route in enumerate(net.routes):
        anchors = [(p, [q for q in nb]) for p, nb in poles10] if route["from"] >= 0 else []
        pl = plan_route(net, route, anchors)
        if pl is None:
            print("%s: траса %d не вийшла" % (name, ri))
            return None
        lines.append(("10kv", pl))
        for k, p in enumerate(pl):
            nb = [pl[k - 1]] if k > 0 else []
            if k < len(pl) - 1:
                nb.append(pl[k + 1])
            hit = [e for e in poles10 if e[0] == p]
            if hit:
                hit[0][1].extend(nb)
            else:
                poles10.append((p, nb))
    tps = []
    unfed = []
    lone = []
    for cl in clusters(net.houses):
        on_board = any(-0.5 <= center(h)[0] < net.W - 0.5 and -0.5 <= center(h)[1] < net.H - 0.5 for h in cl)
        if not on_board and len(cl) < 2:
            print("%s: окрема хата кільця %s без живлення" % (name, [round(v, 1) for v in center(cl[0])]))
            lone += cl
            continue
        res, unf = plan_settlement(net, cl, poles10)
        unfed += unf
        if res is None and unf and len(unf) == len(cl):
            continue
        if res is None:
            print("%s: поселення біля %s не живиться" % (name, [round(v, 1) for v in center(cl[0])]))
            return None
        root, tree = res
        tps.append(root)
        for ch in chains(tree, root):
            lines.append(("04kv", ch))
        print("%s: поселення з %d хат — підстанція %s, %d опор 0.4 кВ" % (name, len(cl), root, len(tree) - 1))
    problems = verify(net, lines, tps, unfed + lone)
    for pr in problems:
        print("%s: %s" % (name, pr))
    for h in unfed:
        print("%s: хата %s лишається без відводу — немає місця для стовпа" % (name, [round(v, 1) for v in center(h)]))
    return None if problems else (lines, tps, [center(h) for h in unfed])


def rect_gap(p, r):
    return math.hypot(max(r[0] - p[0], 0, p[0] - (r[0] + r[2])), max(r[1] - p[1], 0, p[1] - (r[1] + r[3])))


def verify(net, lines, tps, unfed):
    """Те, що зробить гра: відвід кожній хаті від найближчої можливої опори. Помилка — хата без відводу чи
    стовп ближче за BLD до будівлі, яку він не живить."""
    poles = {p for _, pts in lines for p in pts}
    eligible = {p for kind, pts in lines if kind == "04kv" for p in pts} | set(tps)
    fed = {}
    problems = []
    for h in net.houses:
        if h in unfed:
            continue
        c = center(h)
        for p in sorted(eligible, key=lambda q: math.dist(q, c)):
            if drop_to(net, p, h):
                fed[tuple(h)] = p
                break
        else:
            problems.append("хата %s без відводу" % [round(v, 1) for v in c])
    for p in poles:
        for b in net.bld:
            gap = rect_gap(p, b)
            if gap < BLD - 0.01 and not (fed.get(tuple(b)) == p and gap >= BLD_HOME - 0.01):
                problems.append("стовп %s за %.2f від будівлі %s" % (p, gap, [round(v, 1) for v in b[:2]]))
    return problems


def write_layout(name, lines, tps, unfed):
    text = LAYOUT.read_text()
    begin = "\t\t# power:begin %s\n" % name
    end = "\t\t# power:end %s\n" % name
    a, b = text.index(begin), text.index(end)
    body = '\t\t"lines": [\n'
    for kind, pts in lines:
        body += '\t\t\t{"kind": &"%s", "points": [%s]},\n' % (kind, fmt_pts(pts))
    body += "\t\t],\n"
    body += '\t\t"transformers": [%s],\n' % fmt_pts(tps)
    body += '\t\t"unfed": [%s],\n' % fmt_pts(unfed)
    LAYOUT.write_text(text[:a + len(begin)] + body + text[b:])


def main():
    data = json.load(open(sys.argv[1]))
    for name in sys.argv[2:]:
        res = generate(name, data[name])
        if res is None:
            sys.exit(1)
        write_layout(name, *res)


if __name__ == "__main__":
    main()
