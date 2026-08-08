"""Повреждения одежды: прореха, прожог, иней, пропитка кровью.

Одежда до сих пор оставалась целой при любом бое: тело помнило удары
рассечениями, а куртка на нём — нет. Здесь набор накладок, которые игра
сажает на место попадания.

Все накладки ПЛОСКИЕ и лежат в плоскости XY (нормаль по +Z): Godot
разворачивает их по нормали тела в точке удара. Размер задаётся масштабом,
поэтому базовый радиус здесь единичный.

Запуск:  PYTHONPATH=.bpy python3 tools/blender/cloth.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402  ВАЖНО: bpy первым
import bmesh  # noqa: E402

from wolflib import (  # noqa: E402
    M_CHAR, M_FROST, M_GUT, M_MEAT, Part, export_glb, fbm3, reset_scene,
)

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "..", "godot", "assets", "damage")

M_CLOTH = "dmg_cloth"     # ткань: переплетение нитей
M_BLOOD = "dmg_blood"     # мокрое пятно


def _ring(bm, radius, wobble, seed, segs=24, z=0.0):
    """Кольцо вершин с неровным краем."""
    out = []
    for i in range(segs):
        a = i / segs * math.tau
        r = radius * (1.0 + fbm3(math.cos(a) * 3.0, math.sin(a) * 3.0, 0.0, 3, seed) * wobble)
        out.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
    return out


def build_tear() -> None:
    """Прореха: рваная дыра в ткани и отогнутые лоскуты по краю.

    Дыра сама по себе читается пятном; узнаваемой её делают именно лоскуты —
    ткань не испаряется, она отгибается и висит.
    """
    part = Part("tear")
    bm = part.bm
    inner = _ring(bm, 0.55, 0.30, 5)
    outer = _ring(bm, 1.0, 0.22, 9)
    faces = []
    n = len(inner)
    for i in range(n):
        faces.append(bm.faces.new((inner[i], inner[(i + 1) % n],
                                   outer[(i + 1) % n], outer[i])))
    part.assign(faces, M_CLOTH)

    # Лоскуты: треугольники, отогнутые наружу от края дыры.
    flaps = []
    for k in range(5):
        a = math.tau * k / 5 + 0.3
        ca, sa = math.cos(a), math.sin(a)
        base = 0.5
        tip = 1.25 + fbm3(ca * 5.0, sa * 5.0, 1.0, 2, 17) * 0.3
        v0 = bm.verts.new((ca * base - sa * 0.16, sa * base + ca * 0.16, 0.0))
        v1 = bm.verts.new((ca * base + sa * 0.16, sa * base - ca * 0.16, 0.0))
        # Кончик приподнят: лоскут отогнут от тела.
        v2 = bm.verts.new((ca * tip, sa * tip, 0.10))
        flaps.append(bm.faces.new((v0, v1, v2)))
    part.assign(flaps, M_CLOTH)

    # Нити, свисающие из разреза.
    threads = []
    for k in range(4):
        a = math.tau * k / 4 + 0.9
        ca, sa = math.cos(a), math.sin(a)
        t0 = bm.verts.new((ca * 0.5, sa * 0.5, 0.0))
        t1 = bm.verts.new((ca * 0.55, sa * 0.55, 0.02))
        t2 = bm.verts.new((ca * 1.05, sa * 1.05, 0.06))
        t3 = bm.verts.new((ca * 1.0, sa * 1.0, 0.045))
        threads.append(bm.faces.new((t0, t1, t2, t3)))
    part.assign(threads, M_CLOTH)
    bm.verts.index_update()
    part.finish(recalc=False, uv_scale=2.0)


def build_scorch() -> None:
    """Прожог: обугленная корка с рваным краем и дырой в середине."""
    part = Part("scorch")
    bm = part.bm
    inner = _ring(bm, 0.35, 0.35, 21)
    mid = _ring(bm, 0.72, 0.25, 23, z=0.008)
    outer = _ring(bm, 1.0, 0.20, 27, z=0.002)
    n = len(inner)
    core = []
    edge = []
    for i in range(n):
        core.append(bm.faces.new((inner[i], inner[(i + 1) % n], mid[(i + 1) % n], mid[i])))
        edge.append(bm.faces.new((mid[i], mid[(i + 1) % n], outer[(i + 1) % n], outer[i])))
    part.assign(core, M_CHAR)
    part.assign(edge, M_CLOTH)
    bm.verts.index_update()
    part.finish(recalc=False, uv_scale=2.0)


def build_frost() -> None:
    """Иней на ткани: корка с игольчатым краем."""
    part = Part("frost")
    bm = part.bm
    inner = _ring(bm, 0.3, 0.3, 31, z=0.012)
    outer = _ring(bm, 0.95, 0.32, 35)
    n = len(inner)
    faces = []
    for i in range(n):
        faces.append(bm.faces.new((inner[i], inner[(i + 1) % n],
                                   outer[(i + 1) % n], outer[i])))
    part.assign(faces, M_FROST)
    # Иглы наружу.
    spikes = []
    for k in range(7):
        a = math.tau * k / 7 + 0.2
        ca, sa = math.cos(a), math.sin(a)
        s0 = bm.verts.new((ca * 0.85 - sa * 0.09, sa * 0.85 + ca * 0.09, 0.0))
        s1 = bm.verts.new((ca * 0.85 + sa * 0.09, sa * 0.85 - ca * 0.09, 0.0))
        s2 = bm.verts.new((ca * 1.3, sa * 1.3, 0.03))
        spikes.append(bm.faces.new((s0, s1, s2)))
    part.assign(spikes, M_FROST)
    bm.verts.index_update()
    part.finish(recalc=False, uv_scale=2.0)


def build_soak() -> None:
    """Пропитка кровью: мокрое пятно с потёками вниз."""
    part = Part("soak")
    bm = part.bm
    core = _ring(bm, 0.45, 0.28, 41, z=0.004)
    edge = _ring(bm, 1.0, 0.34, 43)
    n = len(core)
    faces = []
    for i in range(n):
        faces.append(bm.faces.new((core[i], core[(i + 1) % n], edge[(i + 1) % n], edge[i])))
    part.assign(faces, M_BLOOD)
    # Потёки: кровь идёт вниз, а не расползается кругом.
    drips = []
    for k in range(4):
        x = -0.5 + k * 0.33
        w = 0.10 - abs(k - 1.5) * 0.02
        y0 = -0.7 - fbm3(x * 4.0, 0.0, 2.0, 2, 51) * 0.2
        d0 = bm.verts.new((x - w, -0.4, 0.002))
        d1 = bm.verts.new((x + w, -0.4, 0.002))
        d2 = bm.verts.new((x + w * 0.4, y0 - 0.5, 0.002))
        d3 = bm.verts.new((x - w * 0.4, y0 - 0.45, 0.002))
        drips.append(bm.faces.new((d0, d1, d2, d3)))
    part.assign(drips, M_BLOOD)
    bm.verts.index_update()
    part.finish(recalc=False, uv_scale=2.0)


BUILDERS = {
    "tear": build_tear,
    "scorch": build_scorch,
    "frost": build_frost,
    "soak": build_soak,
}


def main() -> None:
    out = os.path.abspath(OUT_DIR)
    os.makedirs(out, exist_ok=True)
    for name, fn in BUILDERS.items():
        reset_scene()
        fn()
        path = os.path.join(out, "cloth_%s.glb" % name)
        export_glb(path)
        print("СОБРАНО %s  %d КБ" % (os.path.basename(path),
                                     os.path.getsize(path) // 1024))
    print("ВСЕГО: %d накладок" % len(BUILDERS))


if __name__ == "__main__":
    main()
