"""Сборка имплантов в Blender → GLB для Godot.

Раньше начинка была набором Box/Sphere/Torus прямо в GDScript: коробка с
подписью «детонатор». Здесь каждое устройство — настоящая геометрия со
скруглениями, портами, кабелями и рёбрами радиатора, а полость вокруг него —
вывернутая наизнанку чаша с неровными стенками, обломками рёбер и рваной
губой разреза по краю.

Система координат ЛОКАЛЬНАЯ И ПО-GODOT'ОВСКИ: пишем v(x, up, out), где out —
наружу из груди. Пересчёт в блендеровские оси и дальше в оси Godot (glTF
переворачивает Y/Z) спрятан в v().

Запуск:  PYTHONPATH=.bpy python3 tools/blender/implants.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402  ВАЖНО: bpy первым — он бутстрапит остальное
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from wolflib import (  # noqa: E402
    M_BONE, M_CHAR, M_FROST, M_GEL, M_GLOW, M_GUT, M_MEAT, M_PCB, M_STEEL,
    Part, add_box, add_cone, add_cyl, add_sphere, add_torus, add_tube,
    export_glb, fbm3, orient_toward, reset_scene, roughen, sag_path,
)

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "..", "godot", "assets", "implants")

# Радиус разреза в игре — под него подогнаны чаша и губа.
WOUND_R = 0.135
# Устье раны: НА КОЖЕ, а не на кости. Сборка крепится к позвонку, а кожа
# груди у нормализованной модели примерно на этом расстоянии от него. Всё,
# что глубже, уходит внутрь тела; всё, что ближе, торчало бы наружу.
MOUTH = 0.105


def v(x: float, up: float, out: float) -> tuple:
    """Godot-подобные координаты → блендеровские.

    glTF-экспорт делает godot=(bx, bz, -by), поэтому чтобы «наружу» пришло
    в Godot по +Z, в Blender это -Y.
    """
    return (x, -out, up)


def vr(rx: float, ry: float, rz: float) -> tuple:
    """Поворот в тех же осях (радианы)."""
    return (-ry, rz, rx)


# --- Полость --------------------------------------------------------------

def build_cavity(name: str = "Cavity", radius: float = WOUND_R * 1.05,
                 depth: float = 0.155, burned: bool = False) -> bpy.types.Object:
    """Чаша внутренностей: то, что видно СКВОЗЬ вырезанную кожу.

    Устье лежит на коже, стенки уходят вглубь тела. Нормали разворачиваем
    к устью явно — иначе полость смотрит от зрителя и просто не рисуется.
    """
    part = Part(name)
    bm = part.bm

    rings = 9
    segs = 28
    grid = []
    for i in range(rings):
        t = i / (rings - 1)
        # Профиль: у края почти вертикальная стенка, дальше заваливается в дно.
        r = radius * math.cos(t * math.pi * 0.5) ** 0.65
        d = depth * math.sin(t * math.pi * 0.52)
        ring = []
        for j in range(segs):
            a = j / segs * math.tau
            # Неровность стенки: полость не выточена на станке.
            n = fbm3(math.cos(a) * 2.2, math.sin(a) * 2.2, t * 3.0, 3, 7)
            rr = r * (1.0 + n * 0.12 * (0.35 + t))
            ring.append(bm.verts.new(v(rr * math.cos(a), rr * math.sin(a), MOUTH - d)))
        grid.append(ring)

    wall_faces = []
    for i in range(rings - 1):
        for j in range(segs):
            a = grid[i][j]
            b = grid[i][(j + 1) % segs]
            c = grid[i + 1][(j + 1) % segs]
            d2 = grid[i + 1][j]
            wall_faces.append(bm.faces.new((d2, c, b, a)))
    bottom = bm.faces.new(tuple(reversed(grid[-1])))
    bm.verts.index_update()
    bm.faces.index_update()

    # Ближе к краю — живое мясо, в глубине — тёмная влажная полость.
    edge_zone = int((rings - 1) * 0.4) * segs
    part.assign(wall_faces[:edge_zone], M_CHAR if burned else M_MEAT)
    part.assign(wall_faces[edge_zone:], M_GUT)
    part.assign([bottom], M_GUT)
    roughen(part, wall_faces, 0.006, 26.0, seed=11)

    # Обломки рёбер поперёк полости: НЕ поперёк устья, а в глубине — иначе
    # они закрывают собой всю начинку и торчат белыми палками.
    for i in range(3):
        y = 0.062 - i * 0.062
        tilt = math.radians(-7.0 + i * 7.0)
        add_box(part, (radius * 1.25, 0.012, 0.014), at=v(0, y, MOUTH - 0.085),
                rot=vr(0, 0, tilt), bevel=0.003, mat=M_BONE)

    orient_toward(part, wall_faces + [bottom], v(0, 0, MOUTH))
    return part.finish(recalc=False)


def build_rim(name: str = "Rim", radius: float = WOUND_R,
              burned: bool = False) -> bpy.types.Object:
    """Губа разреза: рваный валик кожи и жира по краю дыры.

    Без неё край выреза — математически ровная линия пикселей, и дыра
    читается как прореха в текстуре, а не как разрез. Валик тонкий: он
    обрамляет отверстие, а не лежит вокруг него бубликом.
    """
    part = Part(name)
    bm = part.bm
    segs = 40
    # Профиль: от кромки наружу и назад, под кожу.
    prof = [(0.96, 0.000), (1.02, 0.011), (1.08, 0.008), (1.11, -0.005), (1.09, -0.016)]
    grid = []
    for j in range(segs):
        a = j / segs * math.tau
        # Рваность: край не круг, его резали и рвали.
        tear = 1.0 + fbm3(math.cos(a) * 3.1, math.sin(a) * 3.1, 0.0, 3, 23) * 0.08
        col = []
        for (pr, pz) in prof:
            r = radius * pr * tear
            col.append(bm.verts.new(v(r * math.cos(a), r * math.sin(a), MOUTH + pz)))
        grid.append(col)

    faces = []
    for j in range(segs):
        c0 = grid[j]
        c1 = grid[(j + 1) % segs]
        for k in range(len(prof) - 1):
            faces.append(bm.faces.new((c0[k], c0[k + 1], c1[k + 1], c1[k])))
    bm.verts.index_update()
    part.assign(faces, M_CHAR if burned else M_MEAT)
    roughen(part, faces, 0.0025, 30.0, seed=31)
    return part.finish()


# --- Железо ---------------------------------------------------------------

def anchors(part: Part, count: int = 4, radius: float = 0.105) -> None:
    """Крепёж в кость: штыри по кругу, вбитые в стенку полости.

    Устройство не висит в мясе само по себе — его к чему-то прикрутили.
    Без штырей вся начинка выглядит подброшенной в дыру.
    """
    for i in range(count):
        a = math.tau * i / count + 0.4
        x = math.cos(a) * radius
        y = math.sin(a) * radius
        # Шляпка снаружи и стержень, уходящий в кость.
        add_cyl(part, 0.010, 0.008, at=v(x, y, MOUTH - 0.030),
                rot=vr(math.pi / 2, 0, 0), segs=8, mat=M_STEEL)
        add_cyl(part, 0.0055, 0.055, at=v(x, y, MOUTH - 0.060),
                rot=vr(math.pi / 2, 0, 0), segs=6, mat=M_STEEL)


def leads(part: Part, count: int = 3, from_out: float = 0.055) -> None:
    """Провода от устройства в мясо: провисают и уходят под стенку."""
    for i in range(count):
        a = math.tau * i / count + 1.1
        end = v(math.cos(a) * 0.115, math.sin(a) * 0.115, MOUTH - 0.075)
        start = v(math.cos(a) * 0.035, math.sin(a) * 0.035, from_out)
        # Кабель — резина и оплётка, а не плата: с текстурой платы труба
        # читается цепью, а не проводом.
        add_tube(part, sag_path(start, end, 0.012, 7), 0.0045, 7,
                 M_GUT if i % 2 == 0 else M_STEEL)


def indicators(part: Part, pts, radius: float = 0.006) -> None:
    """Мелкие огоньки состояния: по ним видно, что железо ЖИВОЕ."""
    for p in pts:
        add_sphere(part, radius, at=p, segs=8, mat=M_GLOW)


def lens(part: Part, at, r: float = 0.022) -> None:
    """Стекло с ободком — окошко, за которым что-то происходит."""
    add_torus(part, r, 0.004, at=at, rot=vr(math.pi / 2, 0, 0),
              major_segs=16, minor_segs=6, mat=M_STEEL)
    add_cyl(part, r * 0.85, 0.006, at=at, rot=vr(math.pi / 2, 0, 0),
            segs=16, mat=M_GEL)



def hw_bomb(part: Part) -> None:
    """Три брикета в ленте, детонатор, таймер."""
    for i in range(3):
        add_box(part, (0.048, 0.125, 0.058), at=v(-0.058 + i * 0.058, 0.015, 0.055),
                bevel=0.005, mat=M_STEEL)
    # Стяжная лента поперёк брикетов.
    add_box(part, (0.20, 0.026, 0.066), at=v(0, 0.015, 0.056), bevel=0.004, mat=M_STEEL)
    # Плата детонатора с распайкой.
    add_box(part, (0.165, 0.038, 0.012), at=v(0, -0.058, 0.088), bevel=0.002, mat=M_PCB)
    for i in range(4):
        add_cyl(part, 0.005, 0.012, at=v(-0.05 + i * 0.033, -0.058, 0.096),
                rot=vr(math.pi / 2, 0, 0), segs=8, mat=M_STEEL)
    # Таймер и красная лампа — то, что мигает.
    add_box(part, (0.046, 0.024, 0.018), at=v(-0.04, 0.088, 0.07), bevel=0.003, mat=M_PCB)


def hw_slime(part: Part) -> None:
    """Мешки с жижей и трубки, уходящие в мясо."""
    for i in range(3):
        add_sphere(part, 0.044 - i * 0.006, at=v(-0.058 + i * 0.058, -0.018 + i * 0.028, 0.062),
                   segs=18, mat=M_GEL, squash=(1.0, 0.85, 1.0))
    for i in range(4):
        add_cyl(part, 0.0065, 0.09, at=v(-0.068 + i * 0.045, 0.075, 0.05),
                rot=vr(0, 0, 0), segs=10, mat=M_MEAT)


def hw_softener(part: Part) -> None:
    """Электродная гребёнка, вбитая в мясо, и жгут проводов."""
    for i in range(4):
        add_cyl(part, 0.008, 0.155, at=v(-0.068 + i * 0.045, 0.0, 0.062),
                rot=vr(0, 0, 0), segs=10, mat=M_STEEL, bevel=0.002)
        add_cone(part, 0.008, 0.0, 0.02, at=v(-0.068 + i * 0.045, -0.088, 0.062),
                 rot=vr(0, 0, math.pi), segs=10, mat=M_STEEL)
    # Шина, стягивающая электроды сверху.
    add_box(part, (0.185, 0.02, 0.02), at=v(0, 0.082, 0.068), bevel=0.004, mat=M_STEEL)
    # Жгут вниз.
    for i in range(3):
        add_cyl(part, 0.0055, 0.14, at=v(-0.03 + i * 0.03, -0.06, 0.05),
                rot=vr(0, 0, math.radians(8 - i * 8)), segs=8, mat=M_PCB)


def hw_flare(part: Part) -> None:
    """ТЭН в кожухе: толстый стержень и рёбра отвода тепла."""
    add_cyl(part, 0.028, 0.20, at=v(0, 0, 0.065), rot=vr(0, 0, 0), segs=20,
            mat=M_GLOW, bevel=0.004)
    for s in (-1.0, 1.0):
        add_box(part, (0.018, 0.19, 0.05), at=v(0.058 * s, 0, 0.065), bevel=0.004,
                mat=M_STEEL)
    for i in range(5):
        add_torus(part, 0.036, 0.005, at=v(0, 0.075 - i * 0.038, 0.065),
                  rot=vr(math.pi / 2, 0, 0), major_segs=18, minor_segs=6, mat=M_STEEL)


def hw_cryo(part: Part) -> None:
    """Два баллона, намёрзшая корка и трубки инея."""
    for s in (-1.0, 1.0):
        add_cyl(part, 0.033, 0.175, at=v(0.055 * s, 0, 0.065), rot=vr(0, 0, 0),
                segs=18, mat=M_GLOW if s > 0 else M_FROST, bevel=0.006)
        # Вентиль сверху баллона.
        add_cyl(part, 0.012, 0.026, at=v(0.055 * s, 0.098, 0.065), rot=vr(0, 0, 0),
                segs=10, mat=M_STEEL)
    for i in range(6):
        a = i / 6 * math.tau
        add_cone(part, 0.011, 0.002, 0.032,
                 at=v(math.cos(a) * 0.105, math.sin(a) * 0.105 + 0.02, 0.05),
                 rot=vr(math.pi / 2, 0, a), segs=7, mat=M_FROST)


def hw_emp(part: Part) -> None:
    """Катушка с обмоткой и конденсаторные банки по бокам."""
    add_torus(part, 0.048, 0.019, at=v(0, 0, 0.065), rot=vr(math.pi / 2, 0, 0),
              major_segs=26, minor_segs=12, mat=M_GLOW)
    # Обмотка — витки поперёк тора.
    for i in range(14):
        a = i / 14 * math.tau
        add_torus(part, 0.020, 0.0035,
                  at=v(math.cos(a) * 0.048, math.sin(a) * 0.048, 0.065),
                  rot=vr(0, a + math.pi / 2, 0), major_segs=10, minor_segs=5, mat=M_STEEL)
    for s in (-1.0, 1.0):
        add_cyl(part, 0.024, 0.09, at=v(0.092 * s, 0, 0.065), rot=vr(0, 0, 0),
                segs=14, mat=M_STEEL, bevel=0.004)
        add_cyl(part, 0.006, 0.014, at=v(0.092 * s, 0.052, 0.065), rot=vr(0, 0, 0),
                segs=8, mat=M_PCB)


def hw_singularity(part: Part) -> None:
    """Чёрное зерно в кольце-ускорителе."""
    add_sphere(part, 0.034, at=v(0, 0, 0.065), segs=20, mat=M_CHAR)
    add_torus(part, 0.062, 0.013, at=v(0, 0, 0.065), rot=vr(math.radians(75), 0, 0),
              major_segs=30, minor_segs=10, mat=M_GLOW)
    add_torus(part, 0.078, 0.008, at=v(0, 0, 0.065), rot=vr(math.radians(-40), 0, 0),
              major_segs=30, minor_segs=8, mat=M_STEEL)
    for i in range(4):
        a = i / 4 * math.tau + 0.4
        add_box(part, (0.014, 0.03, 0.014),
                at=v(math.cos(a) * 0.062, math.sin(a) * 0.062, 0.065),
                bevel=0.003, mat=M_STEEL)


def hw_holo(part: Part) -> None:
    """Линза проектора и стопка рёбер радиатора."""
    add_cone(part, 0.02, 0.055, 0.048, at=v(0, 0.02, 0.078), rot=vr(math.pi / 2, 0, 0),
             segs=24, mat=M_GLOW)
    add_torus(part, 0.056, 0.007, at=v(0, 0.02, 0.10), rot=vr(math.pi / 2, 0, 0),
              major_segs=26, minor_segs=7, mat=M_STEEL)
    for i in range(5):
        add_box(part, (0.15, 0.009, 0.042), at=v(0, -0.048 - i * 0.021, 0.062),
                bevel=0.002, mat=M_STEEL)
    add_box(part, (0.16, 0.03, 0.012), at=v(0, -0.148, 0.06), bevel=0.002, mat=M_PCB)


def hw_brood(part: Part) -> None:
    """Кладка: мокрые яйца в плёнке."""
    for i in range(5):
        x = -0.068 + (i % 3) * 0.068
        y = 0.048 - (i // 3) * 0.078
        add_sphere(part, 0.031, at=v(x, y, 0.066), segs=16, mat=M_GEL,
                   squash=(1.0, 1.18, 0.9))
    # Плёнка-подстилка под кладкой.
    add_box(part, (0.21, 0.15, 0.014), at=v(0, -0.018, 0.045), bevel=0.006, mat=M_MEAT)
    for i in range(4):
        add_cyl(part, 0.005, 0.07, at=v(-0.06 + i * 0.04, 0.09, 0.05),
                rot=vr(0, 0, math.radians(-12 + i * 8)), segs=8, mat=M_MEAT)


def hw_puppet(part: Part) -> None:
    """Слизень, свернувшийся в полости, усики наружу."""
    # Тело слизня — цепочка сегментов по дуге.
    for i in range(6):
        t = i / 5.0
        a = math.radians(-60 + t * 120)
        r = 0.058
        add_sphere(part, 0.032 - i * 0.0022,
                   at=v(math.cos(a) * r, math.sin(a) * r * 0.8, 0.066),
                   segs=14, mat=M_GLOW, squash=(1.0, 1.0, 0.85))
    for s in (-1.0, 1.0):
        add_cyl(part, 0.005, 0.085, at=v(0.048 * s, 0.078, 0.072),
                rot=vr(0, 0, math.radians(22 * s)), segs=8, mat=M_GLOW)
        add_sphere(part, 0.008, at=v(0.062 * s, 0.118, 0.072), segs=10, mat=M_GLOW)


# --- Боевые импланты наёмника --------------------------------------------
# Эти не в ране — они вживлены под кожу и торчат наружу, поэтому идут
# отдельными сборками без полости.

def hw_dermal(part: Part) -> None:
    """Железы-разжижители: капсулы на груди и трубки под кожу."""
    for s in (-1.0, 1.0):
        add_sphere(part, 0.052, at=v(0.19 * s, 0.02, 0.0), segs=18, mat=M_GEL,
                   squash=(0.92, 1.5, 0.85))
        add_cyl(part, 0.013, 0.24, at=v(0.14 * s, -0.16, 0.03),
                rot=vr(0, 0, math.radians(6 * s)), segs=12, mat=M_MEAT)
        add_torus(part, 0.053, 0.008, at=v(0.19 * s, 0.02, 0.0),
                  rot=vr(math.pi / 2, 0, 0), major_segs=20, minor_segs=6, mat=M_STEEL)
    add_box(part, (0.15, 0.1, 0.06), at=v(0, -0.12, 0.02), bevel=0.012, mat=M_STEEL)
    add_box(part, (0.12, 0.05, 0.012), at=v(0, -0.12, 0.055), bevel=0.003, mat=M_PCB)


def hw_subdermal(part: Part) -> None:
    """Сегментные пластины под кожей: торс и наручи."""
    for i in range(3):
        w = 0.33 - i * 0.03
        add_box(part, (w, 0.092, 0.046), at=v(0, 0.12 - i * 0.125, 0.0),
                bevel=0.012, mat=M_STEEL, segments=3)
        # Крепёж по краям пластины.
        for s in (-1.0, 1.0):
            add_cyl(part, 0.008, 0.05, at=v(w * 0.44 * s, 0.12 - i * 0.125, 0.012),
                    rot=vr(math.pi / 2, 0, 0), segs=8, mat=M_STEEL)
    for s in (-1.0, 1.0):
        add_box(part, (0.095, 0.22, 0.11), at=v(0.27 * s, -0.32, 0.0),
                rot=vr(0, 0, math.radians(4 * s)), bevel=0.016, mat=M_STEEL, segments=3)
        add_box(part, (0.135, 0.085, 0.17), at=v(0.24 * s, 0.19, 0.0),
                bevel=0.02, mat=M_STEEL, segments=3)


def hw_kerenzikov(part: Part) -> None:
    """Позвоночный бустер: порты вдоль хребта и разъёмы на шее."""
    for i in range(4):
        add_box(part, (0.085, 0.062, 0.055), at=v(0, 0.17 - i * 0.105, -0.11),
                bevel=0.008, mat=M_STEEL)
        add_cyl(part, 0.016, 0.02, at=v(0, 0.17 - i * 0.105, -0.14),
                rot=vr(math.pi / 2, 0, 0), segs=12, mat=M_PCB)
    # Светящаяся шина вдоль позвоночника.
    add_box(part, (0.03, 0.44, 0.018), at=v(0, -0.02, -0.135), bevel=0.006, mat=M_GLOW)
    for s in (-1.0, 1.0):
        add_cyl(part, 0.018, 0.075, at=v(0.07 * s, 0.26, -0.075),
                rot=vr(math.pi / 2, 0, 0), segs=12, mat=M_STEEL, bevel=0.004)
        add_torus(part, 0.019, 0.005, at=v(0.07 * s, 0.26, -0.042),
                  rot=vr(math.pi / 2, 0, 0), major_segs=14, minor_segs=6, mat=M_GLOW)


def hw_synthlungs(part: Part) -> None:
    """Жабры-фильтры по рёбрам и патрубок на шее."""
    for s in (-1.0, 1.0):
        for i in range(2):
            add_box(part, (0.12, 0.03, 0.045), at=v(0.13 * s, 0.06 - i * 0.085, 0.095),
                    rot=vr(0, 0, math.radians(-7 * s)), bevel=0.006, mat=M_STEEL)
            # Прорези жабр.
            for k in range(3):
                add_box(part, (0.1, 0.006, 0.05),
                        at=v(0.13 * s, 0.068 - i * 0.085 - k * 0.009, 0.098),
                        rot=vr(0, 0, math.radians(-7 * s)), mat=M_GUT)
    add_cyl(part, 0.021, 0.13, at=v(0.05, 0.22, 0.06), rot=vr(math.radians(10), 0,
            math.radians(6)), segs=14, mat=M_STEEL, bevel=0.004)
    add_box(part, (0.105, 0.085, 0.055), at=v(0, -0.09, 0.1), bevel=0.012, mat=M_STEEL)
    add_sphere(part, 0.032, at=v(0, -0.09, 0.13), segs=16, mat=M_GEL,
               squash=(1.3, 1.0, 0.7))


CIV_HW = {
    "bomb": hw_bomb,
    "slime": hw_slime,
    "softener": hw_softener,
    "flare": hw_flare,
    "cryo": hw_cryo,
    "emp": hw_emp,
    "singularity": hw_singularity,
    "holo": hw_holo,
    "brood": hw_brood,
    "puppet": hw_puppet,
}

MERC_HW = {
    "dermal": hw_dermal,
    "subdermal": hw_subdermal,
    "kerenzikov": hw_kerenzikov,
    "synthlungs": hw_synthlungs,
}

# Что в каждой начинке считается «ядром» — Godot берёт объект по имени Core и
# гоняет ему свечение. Ядро — это отдельная деталь, а не вся сборка.
CORE_MAT = M_GLOW


def build_civ(kind: str, out_dir: str) -> str:
    reset_scene()
    build_cavity(burned=(kind == "emp"))
    build_rim(burned=(kind == "emp"))
    part = Part("Core")
    CIV_HW[kind](part)
    # Общая обвязка: штыри в кость, провода в мясо, огоньки состояния.
    # Это то, что превращает «предмет в дыре» во «вживлённое устройство».
    anchors(part)
    leads(part)
    indicators(part, [v(-0.052, 0.088, 0.098), v(-0.028, 0.088, 0.098),
                      v(0.052, -0.086, 0.094)])
    part.finish()
    path = os.path.abspath(os.path.join(out_dir, "civ_%s.glb" % kind))
    export_glb(path)
    return path


def build_merc(kind: str, out_dir: str) -> str:
    reset_scene()
    part = Part("Core")
    MERC_HW[kind](part)
    part.finish()
    path = os.path.abspath(os.path.join(out_dir, "merc_%s.glb" % kind))
    export_glb(path)
    return path


def main() -> None:
    out = os.path.abspath(OUT_DIR)
    os.makedirs(out, exist_ok=True)
    built = []
    for kind in CIV_HW:
        built.append(build_civ(kind, out))
    for kind in MERC_HW:
        built.append(build_merc(kind, out))
    for p in built:
        print("СОБРАНО %s  %d КБ" % (os.path.basename(p), os.path.getsize(p) // 1024))
    print("ВСЕГО: %d сборок" % len(built))


if __name__ == "__main__":
    main()
