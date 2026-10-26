#!/usr/bin/env python3
"""Генератор опор ЛЕП для VillageLayout: з намірів (routes) і будівель карти обчислює, де стоїть кожен
стовп, і пише результат (lines, transformers, unfed) у game/battle/village_layout.gd між мітками
`# power:begin <карта>` і `# power:end <карта>` — і лише коли зібрано всі названі карти.

Власних правил тут нема: константи, поле відстані до асфальту (те, що малює шейдер землі), обриси, клітини
появи й місця, звідки гра дозволяє відвід до хати (PropLayer._drop_target, у тому числі «не крізь власний
дах»), приходять з tools/power_dump.gd. Python ≥ 3.8, лише стандартна бібліотека.

Рельєф, дороги, майданчики й паркани змінюються, тож опори не вгадуються вручну. Після таких змін:

    $GODOT --headless --path . --script tools/power_dump.gd -- /tmp/power.json crossroads ridge river
    python3 tools/power_grid.py /tmp/power.json crossroads ridge river

Тести мережі в tests/game/test_prop_layer.gd падають, коли збережена опора вже не може стати на своє місце
або порушує правила: тоді генератор запускають знову.

Мережа: магістраль 10 кВ уздовж доріг (стовпи на межах клітинок, у вершинах і не рідше за проліт),
відгалуження 10 кВ; для кожного поселення — підстанція на стовпі 10 кВ і гілка 0.4 кВ у вигляді дерева
(без кілець і без перетину прольотів у плані), де кожна опора живить хату або веде до неї.
"""
import heapq
import json
import math
import random
import sys
from pathlib import Path

MINSPAN = 2.0       # сусідні опори — не ближче (крім кутової)
SEP = 1.3           # опори, що не сусідять прольотом, — не ближче (скупчень біля підстанції й зламів нема)
NEAR_TRUNK = 0.2    # опора й проліт 0.4 кВ — не ближче до чужого прольоту 10 кВ
TP_CLEAR = 2.0      # біля підстанції — жодних чужих опор ближче за стільки (крім сусідів по прольоту)
ROOTMIN = 3.0       # перший проліт від підстанції — звичайний проліт, а не скупчення опор
CORNER_MIN = 1.4    # найкоротший проліт між двома кутовими опорами
LAT = 1.1           # наскільки опора магістралі може відійти від лінії узбіччя, коли на ній нема місця
STEP = 0.25         # крок сітки місць уздовж межі клітинок (як у tools/power_dump.gd)
ANGLE_COS = 0.1736  # cos 80°: найгостріший кут між прольотами на опорі
TEE_COS = 0.5       # cos 60°: найгостріший кут між гілкою 0.4 кВ і прольотами 10 кВ на підстанції
EPS_ROAD = 0.004    # запас на округлення поля дороги в дампі
FIELD, FOREST, HILL, BUILDING, RUBBLE = 1, 2, 3, 6, 7
LAYOUT = Path(__file__).resolve().parent.parent / "game/battle/village_layout.gd"


def rnd(v):
    """Як roundi у Godot: половина — від нуля."""
    return int(math.floor(abs(v) + 0.5)) * (1 if v >= 0 else -1)


def center(h):
    return (h[0] + h[2] / 2, h[1] + h[3] / 2)


def rect_gap(p, r):
    return math.hypot(max(r[0] - p[0], 0, p[0] - (r[0] + r[2])), max(r[1] - p[1], 0, p[1] - (r[1] + r[3])))


def grid_points(lo, hi):
    """Усі місця сітки в прямокутнику: межі клітинок (k ± 0.01) і крок STEP уздовж них."""
    out = {}
    for k in range(math.floor(lo[0]) - 1, math.ceil(hi[0]) + 1):
        for o in (0.49, 0.51):
            x = round(k + o, 2)
            if lo[0] <= x <= hi[0]:
                for n in range(math.floor(lo[1] / STEP), math.ceil(hi[1] / STEP) + 1):
                    out[(x, round(n * STEP, 2))] = 1
    for k in range(math.floor(lo[1]) - 1, math.ceil(hi[1]) + 1):
        for o in (0.49, 0.51):
            y = round(k + o, 2)
            if lo[1] <= y <= hi[1]:
                for n in range(math.floor(lo[0] / STEP), math.ceil(hi[0] / STEP) + 1):
                    out[(round(n * STEP, 2), y)] = 1
    return list(out)


class Net:
    def __init__(self, name, data):
        self.name = name
        self.K = data["consts"]
        self.r = data["ring"]
        self.W, self.H = data["size"]
        self.wk = data["wkinds"]
        self.road = data["road_d"]
        self.ground_grid = data["ground"]
        self.bld = [tuple(b["rect"]) for b in data["buildings"]]
        self.homes = [dict(h, rect=tuple(h["rect"])) for h in data["homes"]]
        for h in self.homes:
            h["c"] = center(h["rect"])
            h["f04"] = {(f[0], f[1]): (f[2], f[3]) for f in h["f04"]}
            h["f10"] = {(f[0], f[1]): (f[2], f[3]) for f in h["f10"]}
        self.oth = [tuple(o["rect"]) for o in data["others"] if o["model"] != "garden"]
        self.gar = [tuple(o["rect"]) for o in data["others"] if o["model"] == "garden"]
        self.brg = [tuple(b["rect"]) for b in data["bridges"]]
        self.spawns = {tuple(s) for s in data["spawns"]}
        self.routes = data["routes"]
        self._why = {}
        self._relax = {}
        self._span = {}
        self._bix = self._rect_index(self.bld, 0.7)
        self._oix = self._rect_index(self.oth, 0.7)
        self._gix = self._rect_index(self.gar, 0.7)
        self._xix = self._rect_index(self.brg, 0.7)
        self.wet = [(x - self.r, y - self.r) for y, row in enumerate(self.wk) for x, k in enumerate(row) if k in (4, 5)]

    @staticmethod
    def _rect_index(rects, g):
        ix = {}
        for r in rects:
            for cx in range(math.floor(r[0] - g), math.ceil(r[0] + r[2] + g) + 1):
                for cy in range(math.floor(r[1] - g), math.ceil(r[1] + r[3] + g) + 1):
                    ix.setdefault((cx, cy), []).append(r)
        return ix

    def on_board(self, c):
        return 0 <= c[0] < self.W and 0 <= c[1] < self.H

    def kind(self, c):
        x, y = c[0] + self.r, c[1] + self.r
        return self.wk[y][x] if 0 <= y < len(self.wk) and 0 <= x < len(self.wk[0]) else -1

    def road_edge(self, p):
        """Знакова відстань до краю асфальту, м (RoadCourse.d_at)."""
        rd = self.road
        if rd["w"] == 0:
            return 1e9
        rw, rh, px = rd["w"], rd["h"], self.K["px"]
        tx = (p[0] + 0.5 + self.r) * px - 0.5
        tz = (p[1] + 0.5 + self.r) * px - 0.5
        ix = min(max(math.floor(tx), 0), rw - 2)
        iz = min(max(math.floor(tz), 0), rh - 2)
        fx = min(max(tx - ix, 0.0), 1.0)
        fz = min(max(tz - iz, 0.0), 1.0)
        v = rd["v"]
        a = v[iz * rw + ix] * (1 - fx) + v[iz * rw + ix + 1] * fx
        b = v[(iz + 1) * rw + ix] * (1 - fx) + v[(iz + 1) * rw + ix + 1] * fx
        return a * (1 - fz) + b * fz

    def ground_at(self, p):
        """Висота ґрунту (клітинки), білінійно за сіткою дампу; не нижче рівня води."""
        g = self.ground_grid
        tx = (p[0] + self.r + 0.5) / STEP
        tz = (p[1] + self.r + 0.5) / STEP
        ix = min(max(math.floor(tx), 0), g["w"] - 2)
        iz = min(max(math.floor(tz), 0), g["h"] - 2)
        fx = min(max(tx - ix, 0.0), 1.0)
        fz = min(max(tz - iz, 0.0), 1.0)
        v, w = g["v"], g["w"]
        a = v[iz * w + ix] * (1 - fx) + v[iz * w + ix + 1] * fx
        b = v[(iz + 1) * w + ix] * (1 - fx) + v[(iz + 1) * w + ix + 1] * fx
        return max(a * (1 - fz) + b * fz, self.K["water_level"])

    def wire_ok(self, a, b):
        """Найнижчий дріт прольоту — не нижче wire_clear_m над ґрунтом і водою (провис посередині)."""
        K = self.K
        la = self.ground_at(a) + K["wire_low"]
        lb = self.ground_at(b) + K["wire_low"]
        length = math.dist(a, b)
        n = max(2, int(length / STEP))
        for i in range(n + 1):
            t = i / n
            p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            y = la + (lb - la) * t - K["wire_sag"] * length * 4 * t * (1 - t)
            if (y - self.ground_at(p)) * 8.0 < K["wire_clear_m"] + 0.05:
                return False
        return True

    def cabinet_possible(self, p):
        """Біля підстанції є місце для КТП-шафи: бодай з одного боку уся її площа поза асфальтом і будівлями."""
        K = self.K
        hw, hd = K["cabinet_w"] / 2, K["cabinet_d"] / 2
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c = (p[0] + d[0] * K["cabinet_offset"], p[1] + d[1] * K["cabinet_offset"])
            ok = True
            # шафа не заходить у слід юніта клітинки дошки (півсторона UNIT_HALF, клітина появи — 0.5)
            r = max(hw, hd) * 1.25
            cc = (rnd(c[0]), rnd(c[1]))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    n = (cc[0] + dx, cc[1] + dy)
                    if self.on_board(n) and self.kind(n) != 5:
                        half = 0.5 if n in self.spawns else K["unit_half"]
                        if abs(c[0] - n[0]) < half + r and abs(c[1] - n[1]) < half + r:
                            ok = False
            for q in ((c[0] + hw, c[1] + hd), (c[0] + hw, c[1] - hd), (c[0] - hw, c[1] + hd), (c[0] - hw, c[1] - hd), c):
                if self.road_edge(q) < K["road_m"] + 0.1 or self._inside(self._bix, q, 0.05) or self._inside(self._oix, q, 0.0):
                    ok = False
                    break
            if ok:
                return True
        return False

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
        """None — стовп тут стати може; інакше причина (PropLayer.pole_spot_ok і _pole_on)."""
        key = (round(p[0], 3), round(p[1], 3))
        if key not in self._why:
            self._why[key] = self._check(p, None)
        return self._why[key]

    def why_for(self, p, rect):
        """Те саме, але стовп, що живить хату rect, може стояти до неї на POLE_HOME_CLEAR."""
        key = (round(p[0], 3), round(p[1], 3), tuple(rect))
        if key not in self._relax:
            self._relax[key] = self._check(p, tuple(rect))
        return self._relax[key]

    def _check(self, p, relax):
        K = self.K
        c = (rnd(p[0]), rnd(p[1]))
        if self.kind(c) not in (FIELD, HILL, BUILDING, RUBBLE):
            return "cell%d" % self.kind(c)
        if self.road_edge(p) < K["road_m"] + EPS_ROAD:
            return "road"
        if self.wet_d(p) < K["wet"]:
            return "wet"
        for r in self._bix.get(c, []):
            g = K["home"] if r == relax else K["building"]
            if r[0] - g <= p[0] <= r[0] + r[2] + g and r[1] - g <= p[1] <= r[1] + r[3] + g:
                return "bld"
        if self._inside(self._oix, p, K["prop"]) or self._inside(self._xix, p, K["bridge"]) or self._inside(self._gix, p, K["garden"]):
            return "prop"
        # слід юніта лише на клітинках дошки; клітина появи — повна клітинка
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                n = (c[0] + dx, c[1] + dy)
                if not self.on_board(n) or self.kind(n) == 5:
                    continue
                half = 0.5 if n in self.spawns else K["unit_half"] + K["unit_pole"]
                if abs(p[0] - n[0]) < half + 0.03 and abs(p[1] - n[1]) < half + 0.03:
                    return "unit"
        # поблизу центру клітинки не ставить сам put: корпус опори будь-якого повороту
        if max(abs(p[0] - c[0]), abs(p[1] - c[1])) < K["keep_out"] + K["pole_half"]:
            return "centre"
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
        """Проліт не довший за SPAN і не ближче POLE_BUILDING_CLEAR до будівель; біля кінця, що живить хату
        (relax_*), до самої хати можна ближче — POLE_HOME_CLEAR."""
        key = (a, b, relax_a, relax_b) if a < b else (b, a, relax_b, relax_a)
        if key not in self._span:
            ok = math.dist(a, b) <= self.K["span"] - 0.02 and self.wire_ok(a, b)
            if ok:
                for r in self.bld:
                    g = self.K["home"] if r in (relax_a, relax_b) else self.K["building"]
                    if self.seg_hits(a, b, r, g):
                        ok = False
                        break
            self._span[key] = ok
        return self._span[key]


def interior_ok(a, b, c, cos=ANGLE_COS):
    """Кут у b між прольотами ba й bc не гостріший за 80° (прямий з допуском на косу траси)."""
    la, lb = math.dist(a, b), math.dist(c, b)
    return (a[0] - b[0]) * (c[0] - b[0]) + (a[1] - b[1]) * (c[1] - b[1]) <= cos * la * lb + 1e-6


def segs_cross(a, b, c, d):
    """Прольоти a–b і c–d перетинаються в плані (спільний кінець не рахується)."""
    if a in (c, d) or b in (c, d):
        return False

    def ccw(p, q, r):
        return (r[1] - p[1]) * (q[0] - p[0]) - (q[1] - p[1]) * (r[0] - p[0])
    return ccw(c, d, a) * ccw(c, d, b) < 0 and ccw(a, b, c) * ccw(a, b, d) < 0


def pt_seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    ll = dx * dx + dy * dy
    t = 0 if ll < 1e-9 else max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ll))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


# --- траси ---------------------------------------------------------------------------------
def offset_poly(pts, side, d=0.55):
    """Ламана на відстані d від осі дороги: ліворуч (side > 0) чи праворуч (side < 0) за ходом."""
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


def vertex_cands(net, p, rad, keep):
    """Придатні місця сітки поблизу p, найближчі першими."""
    out = []
    for q in grid_points((p[0] - rad, p[1] - rad), (p[0] + rad, p[1] + rad)):
        d = math.dist(p, q)
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
    """Стовпи між кутами A і B: обидва кінці стоять; між ними — місця сітки поблизу прямої з мінімумом
    стовпів і відхилу. None — не вийшло."""
    if net.why(A) is not None or net.why(B) is not None:
        return None
    span = net.K["span"]
    L = math.dist(A, B)
    if L < MINSPAN:
        # короткий відрізок між двома зламами: кутова опора може стояти ближче за MINSPAN
        return [A, B] if L >= CORNER_MIN and net.span_ok(A, B) else None
    ux, uy = (B[0] - A[0]) / L, (B[1] - A[1]) / L
    lo = (min(A[0], B[0]) - LAT - 0.5, min(A[1], B[1]) - LAT - 0.5)
    hi = (max(A[0], B[0]) + LAT + 0.5, max(A[1], B[1]) + LAT + 0.5)
    pts = {}
    for p in grid_points(lo, hi):
        t = (p[0] - A[0]) * ux + (p[1] - A[1]) * uy
        dv = abs((p[0] - A[0]) * uy - (p[1] - A[1]) * ux)
        if dv <= LAT and 0.0 < t < L and net.why(p) is None:
            pts[p] = (t, dv)
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
            if tj - ti > span:
                break
            if cost[i] >= 1e8:
                continue
            d = math.dist(pi, pj)
            if d < MINSPAN - 1e-6 or d > span - 0.02:
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
    гостріший за 80°; відгалуження починається з наявного стовпа (anchors) під кутом до його прольотів."""
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
            cand.append(vertex_cands(net, p, 1.6, 10))
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
def clusters(homes):
    cl = [[h] for h in homes]
    changed = True
    while changed:
        changed = False
        for i in range(len(cl)):
            for j in range(i + 1, len(cl)):
                if any(math.dist(a["c"], b["c"]) <= 6.0 + 1e-9 for a in cl[i] for b in cl[j]):
                    cl[i] += cl.pop(j)
                    changed = True
                    break
            if changed:
                break
    return cl


def relaxed_nodes(net, cl, bb):
    """Місця, де стовп може стояти до хати ближче за POLE_BUILDING_CLEAR (на POLE_HOME_CLEAR), але лише щоб
    живити її саму."""
    out = {}
    for h in cl:
        c = h["c"]
        for p in grid_points((c[0] - 2.3, c[1] - 2.3), (c[0] + 2.3, c[1] + 2.3)):
            if bb[0] <= p[0] <= bb[2] and bb[1] <= p[1] <= bb[3] and net.why(p) is not None and net.why_for(p, h["rect"]) is None:
                out.setdefault(p, h["rect"])
    return out


class Tree:
    """Гілка 0.4 кВ від підстанції: дерево стовпів, де кожна хата кластера має відвід від найближчого дозволеного."""

    def __init__(self, net, root, root_nb, cl, nodes, relax_for, trunk, trunk_spans, rootmin=ROOTMIN):
        self.net, self.root, self.cl = net, root, cl
        self.rootmin = rootmin
        self.relax_for = relax_for
        self.trunk, self.trunk_spans = trunk, trunk_spans
        self.parent = {root: None}
        self.adj = {root: list(root_nb)}
        self.edges = []
        self.nodes = nodes
        self.feeders = [{p for p in nodes if p != root and self._feeds(p, h)} for h in cl]
        buck = {}
        for p in nodes:
            buck.setdefault((int(p[0] // 4), int(p[1] // 4)), []).append(p)
        self.buck = buck
        self._nbr = {}

    def _feeds(self, p, h):
        if self.relax_for.get(p, h["rect"]) != h["rect"]:
            return False
        return p in h["f04"]

    def neighbours(self, u):
        if u not in self._nbr:
            out = []
            bx, by = int(u[0] // 4), int(u[1] // 4)
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    for v in self.buck.get((bx + ox, by + oy), []):
                        d = math.dist(u, v)
                        lo = self.rootmin if (u == self.root or v == self.root) else MINSPAN
                        if v != u and lo <= d <= self.net.K["span"] - 0.02 \
                                and self.net.span_ok(u, v, self.relax_for.get(u), self.relax_for.get(v)):
                            out.append((v, d))
            self._nbr[u] = out
        return self._nbr[u]

    def allowed(self, u, v):
        """Нова опора v не стоїть упритул до чужих опор, а проліт не лягає на 10 кВ і не перетинає прольотів."""
        if u != self.root and math.dist(v, self.root) < TP_CLEAR:
            return False
        for t in self.trunk:
            if t != self.root and math.dist(v, t) < SEP:
                return False
        for t in self.parent:
            if t != u and math.dist(v, t) < SEP:
                return False
        for a, b in self.trunk_spans:
            if segs_cross(u, v, a, b):
                return False
            if (a != self.root and b != self.root) and min(pt_seg_dist(v, a, b), pt_seg_dist(a, u, v), pt_seg_dist(b, u, v)) < NEAR_TRUNK:
                return False
        for a, b in self.edges:
            if segs_cross(u, v, a, b):
                return False
            # опора не лежить під чужим прольотом, а проліт не проходить крізь чужу опору
            if a != u and b != u and pt_seg_dist(v, a, b) < NEAR_TRUNK:
                return False
        for t in self.parent:
            if t != u and pt_seg_dist(t, u, v) < NEAR_TRUNK:
                return False
        return True

    def grow(self, mode="hard", rng=None):
        covered = [self.root in h["f10"] for h in self.cl]
        guard = 0
        while not all(covered) and guard < 80:
            guard += 1
            dist = {t: 0.0 for t in self.parent}
            prev = {}
            pq = [(0.0, t) for t in self.parent]
            heapq.heapify(pq)
            found = None
            # Спершу найважчу хату (найменше місць, звідки до неї можна дотягнутись): інакше дерево
            # встигає загородити шлях до неї.
            todo = [i for i in range(len(self.cl)) if not covered[i]]
            if mode == "hard":
                hard = min(todo, key=lambda i: len(self.feeders[i]))
            elif mode == "random":
                hard = rng.choice(todo)
            else:
                hard = -1
            while pq:
                d, u = heapq.heappop(pq)
                if d > dist.get(u, 9e9) + 1e-9:
                    continue
                if u not in self.parent and (u in self.feeders[hard] if hard >= 0 else any(u in self.feeders[i] for i in todo)):
                    found = u
                    break
                back = [prev[u]] if u in prev else []
                for v, dd in self.neighbours(u):
                    if v in self.parent:
                        continue
                    # на підстанції гілка відходить від 10 кВ під кутом не гострішим за 60°
                    if u == self.root:
                        if any(not interior_ok(w, u, v, TEE_COS) for w in self.adj.get(u, [])):
                            continue
                    elif any(not interior_ok(w, u, v) for w in self.adj.get(u, []) + back):
                        continue
                    if not self.allowed(u, v):
                        continue
                    turn = 0.0
                    if back:
                        a = (u[0] - back[0][0], u[1] - back[0][1])
                        b = (v[0] - u[0], v[1] - u[1])
                        turn = 1 - (a[0] * b[0] + a[1] * b[1]) / (math.hypot(*a) * math.hypot(*b))
                    diag = 1 - max(abs(v[0] - u[0]), abs(v[1] - u[1])) / dd
                    nd = d + 1 + 0.08 * dd + 0.5 * turn + 0.6 * diag
                    if nd < dist.get(v, 9e9):
                        dist[v] = nd
                        prev[v] = u
                        heapq.heappush(pq, (nd, v))
            if found is None:
                return False
            chain = []
            u = found
            while u not in self.parent:
                chain.append(u)
                u = prev[u]
            top = u
            for node in reversed(chain):
                self.parent[node] = top
                self.adj.setdefault(top, []).append(node)
                self.adj.setdefault(node, []).append(top)
                self.edges.append((top, node))
                top = node
            for i, f in enumerate(self.feeders):
                if any(t in f for t in self.parent):
                    covered[i] = True
        return all(covered)


def chains(parent, root):
    kids = {}
    for n, p in parent.items():
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


def assign(net, p04, tps, homes):
    """Що зробить гра: кожна хата — відвід від найближчої до її центру опори, від якої він можливий."""
    eligible = [(p, "04") for p in p04] + [(p, "10") for p in tps]
    fed = {}
    for h in homes:
        for p, k in sorted(eligible, key=lambda e: math.dist(e[0], h["c"])):
            if p in (h["f04"] if k == "04" else h["f10"]):
                fed[h["rect"]] = p
                break
    return fed


def trunk_roots(net, poles10, spans10, centre):
    """Де може стояти підстанція: наявні опори магістралі поблизу й нові — на прольотах (проліт ділиться)."""
    out = [(p, nb, None) for p, nb in poles10 if math.dist(p, centre) <= 16 and net.cabinet_possible(p)]
    syn = []
    for a, b in spans10:
        length = math.dist(a, b)
        if length < 2 * MINSPAN or pt_seg_dist(centre, a, b) > 14:
            continue
        lo = (min(a[0], b[0]) - 0.5, min(a[1], b[1]) - 0.5)
        hi = (max(a[0], b[0]) + 0.5, max(a[1], b[1]) + 0.5)
        cand = [p for p in grid_points(lo, hi) if pt_seg_dist(p, a, b) <= 0.3 and math.dist(p, a) >= MINSPAN
                and math.dist(p, b) >= MINSPAN and net.why(p) is None and net.cabinet_possible(p)]
        cand.sort(key=lambda p: math.dist(p, centre))
        syn += [(p, [a, b], (a, b)) for p in cand[:5]]
    syn.sort(key=lambda e: math.dist(e[0], centre))
    return sorted(out, key=lambda e: math.dist(e[0], centre))[:12] + syn[:12]


def plan_settlement(net, cl, poles10, trunk_spans):
    """Підстанція й дерево 0.4 кВ для кластера. Хата, до якої нема як дотягнутись, лишається без відводу (unfed):
    спершу та, що без жодного місця для стовпа, потім — найважча, поки дерево не зійдеться."""
    xs = [h["rect"][0] for h in cl] + [h["rect"][0] + h["rect"][2] for h in cl]
    ys = [h["rect"][1] for h in cl] + [h["rect"][1] + h["rect"][3] for h in cl]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    bb = (min(xs) - 3.5, min(ys) - 3.5, max(xs) + 3.5, max(ys) + 3.5)
    trunk = [p for p, _ in poles10]

    def off_trunk(p):
        """Місце для опори 0.4 кВ: не на лінії 10 кВ і не впритул до її опор."""
        return all(math.dist(p, t) >= SEP for t in trunk) and all(pt_seg_dist(p, a, b) >= NEAR_TRUNK for a, b in trunk_spans)

    strict = [p for p in grid_points((bb[0], bb[1]), (bb[2], bb[3])) if net.why(p) is None and off_trunk(p)]
    relax_for = {p: r for p, r in relaxed_nodes(net, cl, bb).items() if off_trunk(p)}
    nodes = list(dict.fromkeys(strict + list(relax_for)))
    # хата без жодного місця, звідки можливий відвід, лишається без нього
    unfed = [h for h in cl if not any(relax_for.get(p, h["rect"]) == h["rect"] and p in h["f04"] for p in nodes)]
    cl = [h for h in cl if h not in unfed]
    roots = trunk_roots(net, poles10, trunk_spans, (cx, cy))
    while cl:
        best = None
        # Перший проліт від підстанції — звичайний (ROOTMIN); у щільному місці — не коротший за MINSPAN.
        for rootmin in (ROOTMIN, MINSPAN):
            for r, nb, split in roots:
                spans = trunk_spans if split is None else [e for e in trunk_spans if e != split] + [(split[0], r), (r, split[1])]
                nd = list(dict.fromkeys(nodes + [r]))
                for mode, seed in [("hard", 0), ("near", 0)] + [("random", k) for k in range(1, 5)]:
                    t = Tree(net, r, nb, cl, nd, relax_for, trunk + ([r] if split else []), spans, rootmin)
                    if t.grow(mode, random.Random(seed)):
                        t = prune(net, t, cl)
                        if best is None or len(t.parent) < best[0]:
                            best = (len(t.parent), r, t, split)
                        break
            if best:
                break
        if best:
            return (best[1], best[2], best[3]), unfed
        # не зійшлося: найважча хата лишається без відводу, решту пробуємо знову
        hardest = min(cl, key=lambda h: sum(1 for p in nodes if relax_for.get(p, h["rect"]) == h["rect"] and p in h["f04"]))
        unfed.append(hardest)
        cl = [h for h in cl if h is not hardest]
    return None, unfed


def prune(net, t, cl):
    """Опора, від якої гра не дасть жодного відводу й за якою нічого нема, не потрібна: знімаємо листки без відводу."""
    while True:
        p04 = [p for p in t.parent if p != t.root]
        fed = set(assign(net, p04, [t.root], cl).values())
        leaves = [p for p in p04 if len(t.adj[p]) == 1 and p not in fed]
        if not leaves:
            return t
        for p in leaves:
            par = t.parent.pop(p)
            t.adj[par].remove(p)
            del t.adj[p]
            t.edges = [e for e in t.edges if p not in e]


# --- запис ---------------------------------------------------------------------------------
def fmt_pts(pts):
    return ", ".join("Vector2(%.2f, %.2f)" % p for p in pts)


def generate(name, data):
    net = Net(name, data)
    lines = []        # (kind, points)
    poles10 = []      # (позиція, сусіди-стовпи)
    spans10 = []
    for ri, route in enumerate(net.routes):
        anchors = [(p, list(nb)) for p, nb in poles10] if route["from"] >= 0 else []
        pl = plan_route(net, route, anchors)
        if pl is None:
            print("%s: траса %d не вийшла" % (name, ri))
            return None
        lines.append(("10kv", pl))
        for k, p in enumerate(pl):
            nb = [pl[k - 1]] if k > 0 else []
            if k < len(pl) - 1:
                nb.append(pl[k + 1])
                spans10.append((p, pl[k + 1]))
            hit = [e for e in poles10 if e[0] == p]
            if hit:
                hit[0][1].extend(nb)
            else:
                poles10.append((p, nb))
    tps, unfed, p04_all = [], [], []
    powered = [h for h in net.homes if h["powered"]]
    for cl in clusters(powered):
        res, unf = plan_settlement(net, cl, poles10, spans10)
        unfed += unf
        if res is None:
            if unf and len(unf) == len(cl):
                continue
            print("%s: поселення біля %s не живиться" % (name, [round(v, 1) for v in cl[0]["c"]]))
            return None
        root, tree, split = res
        if split is not None:
            # підстанція на новому стовпі: проліт магістралі ділиться на два
            a, b = split
            for kind, pts in lines:
                if kind == "10kv":
                    for k in range(len(pts) - 1):
                        if pts[k] == a and pts[k + 1] == b:
                            pts.insert(k + 1, root)
                            break
                    else:
                        continue
                    break
            spans10.remove(split)
            spans10 += [(a, root), (root, b)]
            for e in poles10:
                if e[0] == a:
                    e[1][e[1].index(b)] = root
                elif e[0] == b:
                    e[1][e[1].index(a)] = root
            poles10.append((root, [a, b]))
        tps.append(root)
        for ch in chains(tree.parent, root):
            lines.append(("04kv", ch))
        p04_all += [p for p in tree.parent if p != root]
        print("%s: поселення з %d хат — підстанція %s%s, %d опор 0.4 кВ" % (name, len(cl) - len(unf), root, " (нова)" if split else "", len(tree.parent) - 1))
    # відгалуження 10 кВ закінчується підстанцією: опори за останньою підстанцією не потрібні
    for k in range(len(net.routes)):
        if net.routes[k]["from"] < 0:
            continue
        pts = lines[k][1]
        last = max((i for i, p in enumerate(pts) if p in tps), default=-1)
        lines[k] = ("10kv", pts[:last + 1] if last >= 1 else [])
    lines = [(kind, pts) for kind, pts in lines if len(pts) >= 2]
    problems = verify(net, lines, tps, [h for h in powered if h not in unfed], spans10)
    for pr in problems:
        print("%s: %s" % (name, pr))
    for h in unfed:
        print("%s: хата %s лишається без відводу — немає місця для стовпа" % (name, [round(v, 1) for v in h["c"]]))
    return None if problems else (lines, tps, [h["c"] for h in unfed])


def verify(net, lines, tps, homes, spans10):
    """Те, що перевірять тести: відвід кожній хаті, відстані, перетини, дерево, скупчення."""
    K = net.K
    poles = {p for _, pts in lines for p in pts}
    p04 = {p for kind, pts in lines if kind == "04kv" for p in pts}
    fed = assign(net, [p for p in p04 if p not in tps], tps, homes)
    problems = []
    for h in homes:
        if h["rect"] not in fed:
            problems.append("хата %s без відводу" % [round(v, 1) for v in h["c"]])
    fed_poles = set(fed.values())
    spans = []
    for kind, pts in lines:
        spans += [(pts[k], pts[k + 1]) for k in range(len(pts) - 1)]
    adj = {}
    for a, b in spans:
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    for p in p04:
        if p not in tps and len(adj.get(p, ())) == 1 and p not in fed_poles:
            problems.append("опора %s не живить хату й нікуди не веде" % (p,))
    for p in poles:
        for b in net.bld:
            gap = rect_gap(p, b)
            ok_home = any(fed.get(h["rect"]) == p and tuple(b) == h["rect"] for h in homes)
            if gap < K["building"] - 0.01 and not (ok_home and gap >= K["home"] - 0.01):
                problems.append("стовп %s за %.2f від будівлі %s" % (p, gap, [round(v, 1) for v in b[:2]]))
    pl = sorted(poles)
    for i, a in enumerate(pl):
        for b in pl[i + 1:]:
            d = math.dist(a, b)
            near = b in adj.get(a, ())
            if d < 1.4 or (d < SEP - 0.01 and not near):
                problems.append("опори %s і %s на відстані %.2f" % (a, b, d))
            if (a in tps or b in tps) and d < TP_CLEAR - 0.01 and not near:
                problems.append("біля підстанції опори %s і %s на відстані %.2f" % (a, b, d))
    for i, (a, b) in enumerate(spans):
        for c, d in spans[i + 1:]:
            if segs_cross(a, b, c, d):
                problems.append("прольоти %s–%s і %s–%s перетинаються" % (a, b, c, d))
    for p in poles:
        for a, b in spans:
            if p != a and p != b and pt_seg_dist(p, a, b) < NEAR_TRUNK - 0.01:
                problems.append("опора %s лежить під прольотом %s–%s" % (p, a, b))
    for tp in tps:
        for n in adj.get(tp, ()):
            if n in p04 and math.dist(tp, n) < MINSPAN - 0.01:
                problems.append("перший проліт від підстанції %s коротший за %.1f" % (tp, MINSPAN))
    return problems


def write_layout(results):
    text = LAYOUT.read_text()
    for name, (lines, tps, unfed) in results.items():
        begin = "\t\t# power:begin %s\n" % name
        end = "\t\t# power:end %s\n" % name
        a, b = text.index(begin), text.index(end)
        body = '\t\t"lines": [\n'
        for kind, pts in lines:
            body += '\t\t\t{"kind": &"%s", "points": [%s]},\n' % (kind, fmt_pts(pts))
        body += "\t\t],\n"
        body += '\t\t"transformers": [%s],\n' % fmt_pts(tps)
        body += '\t\t"unfed": [%s],\n' % fmt_pts(unfed)
        text = text[:a + len(begin)] + body + text[b:]
    LAYOUT.write_text(text)


def main():
    data = json.load(open(sys.argv[1]))
    results = {}
    for name in sys.argv[2:]:
        res = generate(name, data[name])
        if res is None:
            sys.exit(1)
        results[name] = res
    write_layout(results)


if __name__ == "__main__":
    main()
