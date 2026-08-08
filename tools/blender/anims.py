"""Сборка анимационных клипов в Blender → GLB для Godot.

Раньше «производные» клипы ковались из библиотеки прямо в игре: брался
готовый Kneel и на него накладывался постоянный доворот плюс синусоида. Все
такие клипы — это одна и та же поза с рябью поверх: трапеза и вживление
импланта отличались только амплитудой волны.

Здесь клипы поставлены КЛЮЧЕВЫМИ ПОЗАМИ на том же риге Mixamo, что и тела,
поэтому у движения есть фазы, вес и разное время на замах и на удар.

Оси рига (замерены по xbot.fbx): вверх +Y, влево +X, вперёд +Z, сантиметры.
Повороты задаём В ПРОСТРАНСТВЕ АРМАТУРЫ и переводим в локальные оси кости —
угадывать локальную ось каждой из 52 костей бессмысленно.

Запуск:  PYTHONPATH=.bpy python3 tools/blender/anims.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402  ВАЖНО: bpy первым
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
RIG_FBX = os.path.join(HERE, "..", "..", "godot", "assets", "characters", "bodies", "xbot.fbx")
OUT_GLB = os.path.join(HERE, "..", "..", "godot", "assets", "anims", "wolf_clips.glb")

FPS = 24
P = "mixamorig:"


# --- Работа с ригом -------------------------------------------------------

def load_rig() -> bpy.types.Object:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(RIG_FBX), ignore_leaf_bones=True,
                             automatic_bone_orientation=False)
    arm = None
    for o in list(bpy.data.objects):
        if o.type == 'ARMATURE':
            arm = o
        else:
            # Меш не нужен: экспортируем только скелет с дорожками.
            bpy.data.objects.remove(o, do_unlink=True)
    if arm is None:
        raise SystemExit("в риге нет арматуры")
    # FBX приносит собственный экшен с T-позой — он попал бы в GLB отдельным
    # клипом и сбивал бы ретаргет.
    if arm.animation_data is not None:
        arm.animation_data.action = None
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    bpy.context.scene.render.fps = FPS
    return arm


def q_arm(pb: bpy.types.PoseBone, rx: float, ry: float, rz: float) -> Quaternion:
    """Поворот кости, заданный В ОСЯХ АРМАТУРЫ (градусы), → локальный кватернион."""
    rot = (Matrix.Rotation(math.radians(rz), 4, 'Z')
           @ Matrix.Rotation(math.radians(ry), 4, 'Y')
           @ Matrix.Rotation(math.radians(rx), 4, 'X'))
    m = pb.bone.matrix_local
    return (m.inverted() @ rot @ m).to_quaternion()


def v_arm(pb: bpy.types.PoseBone, dx: float, dy: float, dz: float) -> Vector:
    """Сдвиг кости в осях арматуры (см) → локальный вектор."""
    m = pb.bone.matrix_local.to_3x3()
    return m.inverted() @ Vector((dx, dy, dz))


def apply_pose(arm: bpy.types.Object, pose: dict, frame: int) -> None:
    """Ставит позу и снимает ключи со всех участвующих костей.

    Кости, которых в позе нет, всё равно получают ключ — иначе клип наследует
    позу от предыдущего кадра и цикл разъезжается.
    """
    for name, val in pose.items():
        pb = arm.pose.bones.get(P + name)
        if pb is None:
            continue
        if len(val) == 6:
            pb.location = v_arm(pb, val[3], val[4], val[5])
            pb.keyframe_insert(data_path="location", frame=frame)
        pb.rotation_quaternion = q_arm(pb, val[0], val[1], val[2])
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def make_clip(arm: bpy.types.Object, name: str, keys: list, loop: bool) -> None:
    """Клип из списка (кадр, поза). Позы складываются с базовой."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True     # иначе экспортёр выбросит неиспользуемое
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act

    # Все кости, что встречаются хоть в одном ключе: у каждой должен быть
    # ключ в каждом кадре, иначе поза «протекает» между фазами.
    bones = set()
    for _f, pose in keys:
        bones |= set(pose.keys())
    for frame, pose in keys:
        full = {b: pose.get(b, (0.0, 0.0, 0.0)) for b in bones}
        apply_pose(arm, full, frame)
    if loop and keys:
        # Замыкаем цикл: последний кадр повторяет первый.
        last = keys[-1][0]
        full0 = {b: keys[0][1].get(b, (0.0, 0.0, 0.0)) for b in bones}
        apply_pose(arm, full0, last)
    for fc in action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
    arm.animation_data.action = None


def action_fcurves(act: bpy.types.Action) -> list:
    """F-кривые экшена.

    В Blender 4.4+ плоский act.fcurves убрали: кривые лежат в слоях и
    «мешках каналов» под слотом. Поддерживаем оба варианта, чтобы скрипт
    не ломался на другой версии Blender.
    """
    flat = getattr(act, "fcurves", None)
    if flat is not None:
        return list(flat)
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for slot in act.slots:
                bag = strip.channelbag(slot)
                if bag is not None:
                    out.extend(bag.fcurves)
    return out


# --- Позы -----------------------------------------------------------------
# (rx, ry, rz) в градусах, оси арматуры: X — наклон вперёд/назад,
# Y — разворот, Z — заваливание набок. Шесть чисел = ещё и сдвиг (см).

# Стойка на коленях: таз опущен, бёдра отведены назад, голени сложены.
KNEEL = {
    "Hips": (12, 0, 0, 0, -38, -6),
    "RightUpLeg": (-72, 0, 4),
    "LeftUpLeg": (-70, 0, -4),
    "RightLeg": (105, 0, 0),
    "LeftLeg": (102, 0, 0),
    "RightFoot": (-28, 0, 0),
    "LeftFoot": (-26, 0, 0),
    "Spine": (14, 0, 0),
    "Spine1": (10, 0, 0),
    "Spine2": (6, 0, 0),
}


def merge(*poses: dict) -> dict:
    """Складывает позы покомпонентно: база плюс то, что делает клип."""
    out: dict = {}
    for pose in poses:
        for k, v in pose.items():
            cur = out.get(k, (0.0,) * len(v))
            if len(cur) < len(v):
                cur = tuple(cur) + (0.0,) * (len(v) - len(cur))
            elif len(v) < len(cur):
                v = tuple(v) + (0.0,) * (len(cur) - len(v))
            out[k] = tuple(a + b for a, b in zip(cur, v))
    return out


def build_feed(arm: bpy.types.Object) -> None:
    """Трапеза: гуль рвёт тело — замах головой, укус, рывок назад, жуёт.

    Фазы разной длины: укус быстрый, рывок медленный, жевание мелкое. Именно
    неравномерность и отличает трапезу от «покачивания в позе Kneel».
    """
    over = {"Spine": (16, 0, 0), "Spine1": (12, 0, 0), "Neck": (14, 0, 0),
            "Head": (10, 0, 0),
            "RightArm": (0, 0, -38), "RightForeArm": (52, 0, 0),
            "LeftArm": (0, 0, 34), "LeftForeArm": (48, 0, 0)}
    keys = [
        # занёс голову
        (0, merge(KNEEL, over, {"Neck": (-16, 0, 0), "Head": (-12, 0, 0)})),
        # рухнул вниз — укус
        (4, merge(KNEEL, over, {"Neck": (22, 0, 0), "Head": (16, 0, 0),
                                "Spine1": (7, 0, 0)})),
        # вцепился и тянет назад, руки упираются
        (14, merge(KNEEL, over, {"Neck": (-24, 6, 0), "Head": (-18, 8, 0),
                                 "Spine": (-8, 0, 0), "Spine1": (-6, 0, 0),
                                 "RightForeArm": (-16, 0, 0), "LeftForeArm": (-14, 0, 0)})),
        # оторвал, качнуло вбок
        (19, merge(KNEEL, over, {"Neck": (-6, -10, 4), "Head": (-4, -12, 6)})),
        # жуёт
        (24, merge(KNEEL, over, {"Neck": (6, 0, 0), "Head": (9, 0, -3)})),
        (28, merge(KNEEL, over, {"Neck": (2, 0, 0), "Head": (2, 0, 3)})),
        (32, merge(KNEEL, over, {"Neck": (6, 2, 0), "Head": (8, 0, -2)})),
        (36, merge(KNEEL, over, {"Neck": (-16, 0, 0), "Head": (-12, 0, 0)})),
    ]
    make_clip(arm, "Feed", keys, loop=True)


def build_implant(arm: bpy.types.Object) -> None:
    """Вживление: хирург налегает весом, вкручивает, отдёргивает руки.

    Здесь важен ВЕС: на вдавливании плечи идут вниз и вперёд вместе с телом,
    а не одни предплечья дёргаются.
    """
    over = {"Spine": (20, 0, 0), "Spine1": (14, 0, 0), "Neck": (18, 0, 0),
            "Head": (12, 0, 0),
            "RightArm": (0, 0, -46), "LeftArm": (0, 0, 42),
            "RightForeArm": (64, 0, 0), "LeftForeArm": (60, 0, 0)}
    keys = [
        # занёс руки
        (0, merge(KNEEL, over, {"RightForeArm": (-20, 0, 0), "LeftForeArm": (-18, 0, 0),
                                "Spine": (-6, 0, 0)})),
        # вдавил — весом всего корпуса
        (7, merge(KNEEL, over, {"Spine": (10, 0, 0), "Spine1": (8, 0, 0),
                                "RightArm": (0, 0, -8), "LeftArm": (0, 0, 8),
                                "RightForeArm": (14, 0, 0), "LeftForeArm": (12, 0, 0),
                                "Hips": (0, 0, 0, 0, -5, 2)})),
        # вкручивает: кисти крутятся в разные стороны
        (14, merge(KNEEL, over, {"Spine": (8, 0, 0), "RightHand": (0, 38, 0),
                                 "LeftHand": (0, -34, 0),
                                 "RightForeArm": (18, 0, 0), "LeftForeArm": (16, 0, 0),
                                 "Hips": (0, 0, 0, 0, -5, 2)})),
        (21, merge(KNEEL, over, {"Spine": (9, 0, 0), "RightHand": (0, -30, 0),
                                 "LeftHand": (0, 26, 0),
                                 "RightForeArm": (16, 0, 0), "LeftForeArm": (15, 0, 0),
                                 "Hips": (0, 0, 0, 0, -5, 2)})),
        # отдёрнул руки и выпрямился — посмотреть, что вышло
        (30, merge(KNEEL, over, {"Spine": (-10, 0, 0), "Spine1": (-8, 0, 0),
                                 "Neck": (-10, 0, 0), "Head": (-8, 0, 0),
                                 "RightForeArm": (-26, 0, 0), "LeftForeArm": (-24, 0, 0)})),
        (40, merge(KNEEL, over, {"RightForeArm": (-20, 0, 0), "LeftForeArm": (-18, 0, 0),
                                 "Spine": (-6, 0, 0)})),
    ]
    make_clip(arm, "Implant", keys, loop=True)


def build_activate(arm: bpy.types.Object) -> None:
    """Подрыв: вскинуть детонатор, вдавить большим пальцем, отшатнуться.

    Прежний вариант был «щёлкнул тумблером у груди» — жест ни о чём: со
    стороны непонятно, что человек только что сделал. Здесь читаемая
    последовательность из четырёх фаз, и главное в ней — ОТДАЧА: тело
    отворачивается от вспышки и прикрывается локтем. Именно по отшатыванию
    зритель понимает, что рвануло, даже если сам взрыв за стеной.
    """
    keys = [
        (0, {"RightArm": (0, 0, 0), "RightForeArm": (0, 0, 0), "RightHand": (0, 0, 0),
             "LeftArm": (0, 0, 0), "LeftForeArm": (0, 0, 0),
             "Spine": (0, 0, 0), "Spine1": (0, 0, 0), "Neck": (0, 0, 0), "Head": (0, 0, 0)}),
        # 1. Выхватил: рука идёт вверх-вперёд, вторая подхватывает снизу.
        (4, {"RightArm": (0, 0, -48), "RightForeArm": (64, 0, 0), "RightHand": (-22, 0, 0),
             "LeftArm": (0, 0, 34), "LeftForeArm": (52, 0, 0),
             "Spine": (3, 0, 0), "Spine1": (4, 0, -2), "Neck": (4, 0, 0), "Head": (6, 0, 0)}),
        # 2. Замер, глядя на устройство: короткая пауза перед нажатием.
        (7, {"RightArm": (0, 0, -54), "RightForeArm": (72, 0, 0), "RightHand": (-14, 0, 0),
             "LeftArm": (0, 0, 38), "LeftForeArm": (58, 0, 0),
             "Spine": (5, 0, 0), "Spine1": (6, 0, -2), "Neck": (10, 0, 0), "Head": (12, 0, 0)}),
        # 3. Вдавил: кисть резко клюёт вниз, плечо просаживается.
        (9, {"RightArm": (0, 0, -50), "RightForeArm": (78, 0, 0), "RightHand": (30, 0, 0),
             "LeftArm": (0, 0, 38), "LeftForeArm": (60, 0, 0),
             "Spine": (7, 0, 0), "Spine1": (8, 0, -3), "Neck": (12, 0, 0), "Head": (15, 0, 0)}),
        # 4. ОТДАЧА: корпус уходит назад и вбок, локоть прикрывает лицо.
        (13, {"RightArm": (0, 0, -78), "RightForeArm": (96, 0, 0), "RightHand": (-30, 0, 0),
              "LeftArm": (0, 0, 20), "LeftForeArm": (30, 0, 0),
              "Spine": (-16, -12, 0), "Spine1": (-12, -10, 0), "Neck": (-14, -14, 0),
              "Head": (-18, -18, 0)}),
        # 5. Отпустило, но ещё смотрит в сторону взрыва.
        (19, {"RightArm": (0, 0, -22), "RightForeArm": (30, 0, 0), "RightHand": (-8, 0, 0),
              "LeftArm": (0, 0, 8), "LeftForeArm": (12, 0, 0),
              "Spine": (-5, -6, 0), "Spine1": (-4, -5, 0), "Neck": (-5, -8, 0),
              "Head": (-7, -10, 0)}),
        (27, {"RightArm": (0, 0, 0), "RightForeArm": (0, 0, 0), "RightHand": (0, 0, 0),
              "LeftArm": (0, 0, 0), "LeftForeArm": (0, 0, 0),
              "Spine": (0, 0, 0), "Spine1": (0, 0, 0), "Neck": (0, 0, 0), "Head": (0, 0, 0)}),
    ]
    make_clip(arm, "Activate", keys, loop=False)


def build_convulse(arm: bpy.types.Object) -> None:
    """Судороги: тело на полу выгибает дугой и бьёт.

    Работает поверх лежачей позы — сюда идут только рывки, не сама поза.
    """
    keys = [
        (0, {"Spine": (0, 0, 0), "Spine1": (0, 0, 0), "Neck": (0, 0, 0), "Head": (0, 0, 0),
             "RightArm": (0, 0, 0), "LeftArm": (0, 0, 0),
             "RightUpLeg": (0, 0, 0), "LeftUpLeg": (0, 0, 0)}),
        # выгнуло дугой
        (3, {"Spine": (-22, 0, 0), "Spine1": (-16, 0, 0), "Neck": (-24, 0, 0),
             "Head": (-20, 0, 0), "RightArm": (0, 0, -26), "LeftArm": (0, 0, 22),
             "RightUpLeg": (-14, 0, 0), "LeftUpLeg": (-10, 0, 0)}),
        # обмякло
        (9, {"Spine": (6, 0, 0), "Spine1": (4, 0, 0), "Neck": (8, 0, 0), "Head": (6, 0, 0),
             "RightArm": (0, 0, 6), "LeftArm": (0, 0, -4),
             "RightUpLeg": (4, 0, 0), "LeftUpLeg": (3, 0, 0)}),
        # второй, слабее
        (13, {"Spine": (-14, 0, 4), "Spine1": (-10, 0, 3), "Neck": (-16, 6, 0),
              "Head": (-12, 8, 0), "RightArm": (0, 0, -16), "LeftArm": (0, 0, 12),
              "RightUpLeg": (-8, 0, 0), "LeftUpLeg": (-5, 0, 0)}),
        (20, {"Spine": (2, 0, 0), "Spine1": (1, 0, 0), "Neck": (3, 0, 0), "Head": (2, 0, 0),
              "RightArm": (0, 0, 0), "LeftArm": (0, 0, 0),
              "RightUpLeg": (0, 0, 0), "LeftUpLeg": (0, 0, 0)}),
        (24, {"Spine": (0, 0, 0), "Spine1": (0, 0, 0), "Neck": (0, 0, 0), "Head": (0, 0, 0),
              "RightArm": (0, 0, 0), "LeftArm": (0, 0, 0),
              "RightUpLeg": (0, 0, 0), "LeftUpLeg": (0, 0, 0)}),
    ]
    make_clip(arm, "Convulse", keys, loop=True)


CLIPS = [build_feed, build_implant, build_activate, build_convulse]


def main() -> None:
    arm = load_rig()
    for fn in CLIPS:
        fn(arm)
    out = os.path.abspath(OUT_GLB)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format='GLB',
        use_selection=False,
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_yup=True,
        export_apply=False,
    )
    print("СОБРАНО %s  %d КБ, клипов: %d"
          % (os.path.basename(out), os.path.getsize(out) // 1024, len(bpy.data.actions)))
    for a in bpy.data.actions:
        print("   клип %-10s кадров %d" % (a.name, int(a.frame_range[1] - a.frame_range[0]) + 1))


if __name__ == "__main__":
    main()
