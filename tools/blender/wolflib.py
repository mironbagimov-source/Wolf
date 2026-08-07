"""Общая кухня блендеровского пайплайна Wolf.

Всё строится из кода и БЕЗ случайности между запусками: сид фиксирован, так что
один и тот же скрипт даёт байт-в-байт одинаковый GLB. Это важно — GLB лежат в
репозитории, и пересборка не должна создавать шум в диффе.

Геометрия отдаётся в Godot вместе с ИМЕНАМИ материалов (imp_steel, imp_meat…).
Сами текстуры Blender не пишет: их процедурно печёт игра (WolfLevel._mat_imp_*),
поэтому здесь материал — это просто ярлык, по которому Godot подставит свой.
"""

import bpy   # ВАЖНО: bpy первым — он бутстрапит bmesh и mathutils
import bmesh
import math
from mathutils import Matrix, Vector

# Ярлыки материалов — ровно те, что понимает godot/scripts/level.gd.
M_STEEL = "imp_steel"    # хирургическая сталь
M_PCB = "imp_pcb"        # плата с дорожками
M_MEAT = "imp_meat"      # мышца: волокно, вены
M_GUT = "imp_gut"        # тёмная влажная полость
M_BONE = "imp_bone"      # кость с порами
M_GEL = "imp_gel"        # био-гель с пузырями
M_FROST = "imp_frost"    # иней
M_CHAR = "imp_char"      # обугленное с углями
M_GLOW = "imp_glow"      # светящееся ядро

ALL_MATS = [M_STEEL, M_PCB, M_MEAT, M_GUT, M_BONE, M_GEL, M_FROST, M_CHAR, M_GLOW]


# --- Детерминированный шум ------------------------------------------------
# Свой, а не random: нужен ГЛАДКИЙ шум по координате, повторяемый между
# запусками и не зависящий от версии стандартной библиотеки.

def _hash1(n: int) -> float:
    n = (n << 13) ^ n
    n = (n * (n * n * 15731 + 789221) + 1376312589) & 0x7FFFFFFF
    return 1.0 - n / 1073741824.0


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def noise3(x: float, y: float, z: float, seed: int = 0) -> float:
    """Гладкий шум в [-1, 1] по трёхмерной координате."""
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    # сглаживание, чтобы не было граней между ячейками
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    fz = fz * fz * (3.0 - 2.0 * fz)

    def corner(dx: int, dy: int, dz: int) -> float:
        return _hash1((ix + dx) * 374761393 + (iy + dy) * 668265263
                      + (iz + dz) * 1274126177 + seed * 951274213)

    x00 = _lerp(corner(0, 0, 0), corner(1, 0, 0), fx)
    x10 = _lerp(corner(0, 1, 0), corner(1, 1, 0), fx)
    x01 = _lerp(corner(0, 0, 1), corner(1, 0, 1), fx)
    x11 = _lerp(corner(0, 1, 1), corner(1, 1, 1), fx)
    return _lerp(_lerp(x00, x10, fy), _lerp(x01, x11, fy), fz)


def fbm3(x: float, y: float, z: float, octaves: int = 3, seed: int = 0) -> float:
    """Несколько октав шума: крупные волны плюс мелкая рябь."""
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for o in range(octaves):
        total += noise3(x * freq, y * freq, z * freq, seed + o * 17) * amp
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm


# --- Сцена ----------------------------------------------------------------

def reset_scene() -> None:
    """Пустая сцена: сборка каждого импланта начинается с чистого листа."""
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    for ma in list(bpy.data.materials):
        if ma.users == 0:
            bpy.data.materials.remove(ma)


def material(name: str) -> bpy.types.Material:
    ma = bpy.data.materials.get(name)
    if ma is None:
        ma = bpy.data.materials.new(name)
        ma.use_nodes = False
    return ma


class Part:
    """Кусок геометрии в работе: bmesh плюс раскладка материалов по граням."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.slots: list[str] = []

    def slot(self, mat_name: str) -> int:
        if mat_name not in self.slots:
            self.slots.append(mat_name)
        return self.slots.index(mat_name)

    def assign(self, faces, mat_name: str) -> None:
        idx = self.slot(mat_name)
        for f in faces:
            f.material_index = idx

    def new_faces(self, before: set, mat_name: str) -> list:
        """Грани, появившиеся после последней операции, — им и красим слот."""
        fresh = [f for f in self.bm.faces if f not in before]
        self.assign(fresh, mat_name)
        return fresh

    def snapshot(self) -> set:
        return set(self.bm.faces)

    def finish(self, smooth: bool = True, recalc: bool = True,
               uv_scale: float = 7.0) -> bpy.types.Object:
        me = bpy.data.meshes.new(self.name)
        if uv_scale > 0.0:
            box_uv(self, uv_scale)
        if recalc:
            # Для замкнутых объёмов нормали наружу — то, что нужно. Для чаши,
            # в которую смотрят ИЗНУТРИ, пересчёт всё портит: см. orient_toward.
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        self.bm.to_mesh(me)
        self.bm.free()
        for slot_name in self.slots:
            me.materials.append(material(slot_name))
        if smooth:
            for poly in me.polygons:
                poly.use_smooth = True
            # Резкие грани железа остаются резкими, мясо — гладким.
            me.shade_smooth()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def box_uv(part: "Part", scale: float = 7.0) -> None:
    """Развёртка проекцией по кубу.

    Без UV процедурные текстуры (травление стали, волокно мышцы, поры кости)
    не ложатся вообще, и вся сборка читается как крашеный пластилин. Умная
    развёртка тут не нужна: текстуры тайлятся и без швов, важна лишь ровная
    плотность текселя. Плоскость проекции выбираем по главной оси нормали
    грани — то есть по той стороне «коробки», к которой грань ближе всего.
    """
    uv = part.bm.loops.layers.uv.verify()
    for f in part.bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if ax >= ay and ax >= az:
                u, w = co.y, co.z
            elif ay >= az:
                u, w = co.x, co.z
            else:
                u, w = co.x, co.y
            loop[uv].uv = (u * scale, w * scale)


# --- Примитивы ------------------------------------------------------------

def add_box(part: Part, size, at=(0, 0, 0), rot=(0, 0, 0), bevel: float = 0.0,
            mat: str = M_STEEL, segments: int = 2) -> list:
    """Скруглённая коробка — база всего железа."""
    before = part.snapshot()
    res = bmesh.ops.create_cube(part.bm, size=1.0)
    verts = res["verts"]
    mat_s = Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
    bmesh.ops.transform(part.bm, matrix=mat_s, verts=verts)
    if bevel > 0.0:
        faces = {f for v in verts for f in v.link_faces}
        edges = {e for v in verts for e in v.link_edges}
        bmesh.ops.bevel(part.bm, geom=list(verts) + list(edges), offset=bevel,
                        segments=segments, affect='EDGES', clamp_overlap=True)
        del faces
    _place(part, before, at, rot)
    return part.new_faces(before, mat)


def add_cyl(part: Part, radius: float, depth: float, at=(0, 0, 0), rot=(0, 0, 0),
            segs: int = 16, mat: str = M_STEEL, cap: bool = True,
            bevel: float = 0.0) -> list:
    before = part.snapshot()
    res = bmesh.ops.create_cone(part.bm, cap_ends=cap, cap_tris=False, segments=segs,
                                radius1=radius, radius2=radius, depth=depth)
    if bevel > 0.0:
        verts = res["verts"]
        edges = {e for v in verts for e in v.link_edges}
        bmesh.ops.bevel(part.bm, geom=list(verts) + list(edges), offset=bevel,
                        segments=2, affect='EDGES', clamp_overlap=True)
    _place(part, before, at, rot)
    return part.new_faces(before, mat)


def add_cone(part: Part, r1: float, r2: float, depth: float, at=(0, 0, 0),
             rot=(0, 0, 0), segs: int = 16, mat: str = M_STEEL) -> list:
    before = part.snapshot()
    bmesh.ops.create_cone(part.bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=r1, radius2=r2, depth=depth)
    _place(part, before, at, rot)
    return part.new_faces(before, mat)


def add_sphere(part: Part, radius: float, at=(0, 0, 0), segs: int = 16,
               mat: str = M_GLOW, squash=(1.0, 1.0, 1.0)) -> list:
    before = part.snapshot()
    res = bmesh.ops.create_uvsphere(part.bm, u_segments=segs, v_segments=max(4, segs // 2),
                                    radius=radius)
    if squash != (1.0, 1.0, 1.0):
        bmesh.ops.transform(
            part.bm,
            matrix=Matrix.Diagonal(Vector((squash[0], squash[1], squash[2], 1.0))),
            verts=res["verts"])
    _place(part, before, at, (0, 0, 0))
    return part.new_faces(before, mat)


def add_torus(part: Part, major: float, minor: float, at=(0, 0, 0), rot=(0, 0, 0),
              major_segs: int = 24, minor_segs: int = 10, mat: str = M_STEEL) -> list:
    """Кольцо. bmesh своего тора не имеет — крутим профиль руками."""
    before = part.snapshot()
    verts = []
    for i in range(major_segs):
        a = i / major_segs * math.tau
        ring = []
        for j in range(minor_segs):
            b = j / minor_segs * math.tau
            r = major + minor * math.cos(b)
            ring.append(part.bm.verts.new((r * math.cos(a), r * math.sin(a),
                                           minor * math.sin(b))))
        verts.append(ring)
    for i in range(major_segs):
        for j in range(minor_segs):
            a, b = verts[i][j], verts[i][(j + 1) % minor_segs]
            c = verts[(i + 1) % major_segs][(j + 1) % minor_segs]
            d = verts[(i + 1) % major_segs][j]
            part.bm.faces.new((a, b, c, d))
    part.bm.verts.index_update()
    _place(part, before, at, rot)
    return part.new_faces(before, mat)


def _place(part: Part, before: set, at, rot) -> None:
    """Двигает и вращает то, что только что добавили."""
    fresh_faces = [f for f in part.bm.faces if f not in before]
    verts = {v for f in fresh_faces for v in f.verts}
    if not verts:
        return
    m = Matrix.Translation(Vector(at))
    if rot != (0, 0, 0):
        m = m @ (Matrix.Rotation(rot[2], 4, 'Z')
                 @ Matrix.Rotation(rot[1], 4, 'Y')
                 @ Matrix.Rotation(rot[0], 4, 'X'))
    bmesh.ops.transform(part.bm, matrix=m, verts=list(verts), space=Matrix.Identity(4))


def roughen(part: Part, faces, amount: float, scale: float = 12.0, seed: int = 1) -> None:
    """Органическая неровность: смещает вершины по шуму вдоль их нормалей.

    Именно это отличает мясо от параллелепипеда — ровных поверхностей в теле
    не бывает.
    """
    verts = {v for f in faces for v in f.verts}
    for v in verts:
        n = fbm3(v.co.x * scale, v.co.y * scale, v.co.z * scale, 3, seed)
        v.co += v.normal * (n * amount)


def orient_toward(part: Part, faces, target) -> None:
    """Разворачивает грани лицом к точке.

    У открытой чаши нет «наружу»: recalc_face_normals для неё гадает и обычно
    выворачивает стенки от зрителя, после чего полость просто не рисуется.
    Здесь направление задаём явно — от грани к центру устья.
    """
    tgt = Vector(target)
    for f in faces:
        c = f.calc_center_median()
        if f.normal.dot(tgt - c) < 0.0:
            f.normal_flip()


def export_glb(path: str, name_root: str = "") -> None:
    """Пишет всю сцену в GLB рядом с проектом Godot."""
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False,
    )
