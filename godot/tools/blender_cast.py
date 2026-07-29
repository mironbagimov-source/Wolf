# Лепит четыре модели «Считалки» и кладёт их в assets/cast.glb.
#
#     blender --background --python godot/tools/blender_cast.py
#
# Что здесь происходит. Скелет и анимации берутся из assets/soldier.glb — он
# остаётся донором рига, но его собственные меши выбрасываются. На кости
# насаживаются свои тела: гость, Трикстер, Ведьма и Весёлый Роджер. Каждая
# деталь целиком привязана к одной кости (жёсткий скиннинг), поэтому фигуры
# получаются угловатыми — это осознанный лоу-поли, а не недоделка: он читается
# в тумане силуэтом, а не текстурой, и не требует ручной развесовки.
#
# Все четыре меша сидят на одном скелете и лежат в одном файле — анимации не
# дублируются вчетверо, а игра при спавне оставляет нужный меш и удаляет
# остальные.

import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
DONOR = os.path.join(ASSETS, "soldier.glb")
OUTPUT = os.path.join(ASSETS, "cast.glb")

# Единицы арматуры — сантиметры (сам объект отмасштабирован в 0.01).
CM = 1.0

PALETTE = {
	"guest_cloth": (0.42, 0.35, 0.24, 1.0),
	"guest_skin": (0.55, 0.44, 0.35, 1.0),
	"guest_dark": (0.16, 0.14, 0.12, 1.0),

	"trick_red": (0.55, 0.09, 0.16, 1.0),
	"trick_dark": (0.13, 0.05, 0.07, 1.0),
	"trick_bone": (0.88, 0.85, 0.78, 1.0),
	"steel": (0.62, 0.65, 0.70, 1.0),

	"witch_green": (0.13, 0.27, 0.14, 1.0),
	"witch_dark": (0.07, 0.12, 0.08, 1.0),
	"witch_thorn": (0.35, 0.62, 0.32, 1.0),

	"roger_canvas": (0.33, 0.34, 0.36, 1.0),
	"roger_dark": (0.14, 0.15, 0.17, 1.0),
	"roger_iron": (0.45, 0.47, 0.50, 1.0),
}


def log(message):
	print("[cast] " + message)


# --- сцена и донор ---------------------------------------------------------

def wipe_scene():
	for obj in list(bpy.data.objects):
		bpy.data.objects.remove(obj, do_unlink=True)
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.actions, bpy.data.armatures):
		for item in list(block):
			block.remove(item)


def import_donor():
	bpy.ops.import_scene.gltf(filepath=DONOR)
	armature = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

	# Донорские меши не нужны — забираем только кости и анимации.
	for obj in [o for o in bpy.data.objects if o.type == 'MESH']:
		bpy.data.objects.remove(obj, do_unlink=True)

	# glTF-импорт плодит по действию на каждую мелкую кость; оставляем четыре
	# настоящих клипа и возвращаем им короткие имена, под которыми их ждёт игра.
	for action in list(bpy.data.actions):
		if action.name.endswith("_Character"):
			action.name = action.name[:-len("_Character")]
		else:
			bpy.data.actions.remove(action)

	log("донор: %d костей, клипы %s" % (
		len(armature.data.bones), sorted(a.name for a in bpy.data.actions)))
	return armature


class Rig:
	"""Кости в системе координат арматуры плюс её собственные оси."""

	def __init__(self, armature):
		self.armature = armature
		self.bones = {}
		for bone in armature.data.bones:
			self.bones[bone.name.split(":")[-1].replace("mixamorig_", "")] = bone

		# Хвосты у Mixamo-рига через glTF приходят мусорные (кость «длиной» в
		# девять метров), поэтому геометрия строится только по головам костей.
		self.up = (self.head("Neck") - self.head("Hips")).normalized()
		toe = (self.head("LeftToeBase") - self.head("LeftFoot"))
		self.fwd = (toe - self.up * toe.dot(self.up)).normalized()
		self.left = self.up.cross(self.fwd).normalized()
		if (self.head("LeftArm") - self.head("RightArm")).dot(self.left) < 0:
			self.left = -self.left

	def name(self, short):
		return self.bones[short].name

	def head(self, short):
		return self.bones[short].head_local.copy()

	def height(self):
		return (self.head("Head") - self.head("LeftFoot")).dot(self.up) + 20.0 * CM


# --- построение деталей ----------------------------------------------------

class Body:
	"""Копилка деталей одной фигуры: геометрия + к какой кости она привязана."""

	def __init__(self, rig, name):
		self.rig = rig
		self.name = name
		self.parts = []   # (bmesh, bone_name, material_key)

	def tube(self, bone, a, b, r_start, r_end, material, sides=6):
		mesh = bmesh.new()
		axis = (b - a)
		length = axis.length
		if length < 0.001:
			return
		rot = axis.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
		bmesh.ops.create_cone(
			mesh, cap_ends=True, cap_tris=False, segments=sides,
			radius1=r_start, radius2=r_end, depth=length,
			matrix=Matrix.Translation((a + b) * 0.5) @ rot,
		)
		self.parts.append((mesh, bone, material))

	def box(self, bone, centre, size, material, rotation=None):
		mesh = bmesh.new()
		matrix = Matrix.Translation(centre)
		if rotation is not None:
			matrix = matrix @ rotation
		matrix = matrix @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
		bmesh.ops.create_cube(mesh, size=1.0, matrix=matrix)
		self.parts.append((mesh, bone, material))

	def ball(self, bone, centre, radius, material, squash=None):
		mesh = bmesh.new()
		scale = squash or Vector((1, 1, 1))
		matrix = Matrix.Translation(centre) @ Matrix.Diagonal(
			(radius * scale.x, radius * scale.y, radius * scale.z, 1.0))
		bmesh.ops.create_icosphere(mesh, subdivisions=1, radius=1.0, matrix=matrix)
		self.parts.append((mesh, bone, material))

	def ring(self, bone, centre, radius, thickness, material, axis=None):
		mesh = bmesh.new()
		rot = Matrix.Identity(4)
		if axis is not None:
			rot = axis.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
		bmesh.ops.create_circle(mesh, cap_ends=False, segments=10, radius=radius,
								matrix=Matrix.Translation(centre) @ rot)
		bmesh.ops.extrude_edge_only(mesh, edges=mesh.edges[:])
		bmesh.ops.translate(mesh, vec=Vector((0, 0, thickness)),
							verts=[v for v in mesh.verts if v.is_boundary is False] or mesh.verts[:])
		bmesh.ops.solidify(mesh, geom=mesh.faces[:], thickness=thickness)
		self.parts.append((mesh, bone, material))

	def build(self):
		"""Сшивает детали в один меш, вешает вершинные группы и модификатор."""
		mesh_data = bpy.data.meshes.new(self.name)
		obj = bpy.data.objects.new(self.name, mesh_data)
		bpy.context.scene.collection.objects.link(obj)

		combined = bmesh.new()
		groups = {}
		material_slots = {}

		for part, bone, material_key in self.parts:
			if material_key not in material_slots:
				material_slots[material_key] = len(material_slots)
				obj.data.materials.append(make_material(material_key))
			slot = material_slots[material_key]

			offset = len(combined.verts)
			combined.from_mesh(bmesh_to_mesh(part))
			combined.verts.ensure_lookup_table()
			combined.faces.ensure_lookup_table()

			for face in combined.faces:
				if face.index >= 0 and all(v.index >= offset for v in face.verts):
					face.material_index = slot

			groups.setdefault(bone, []).extend(range(offset, len(combined.verts)))
			part.free()

		combined.to_mesh(mesh_data)
		combined.free()

		for bone, indices in groups.items():
			group = obj.vertex_groups.new(name=bone)
			group.add(indices, 1.0, 'REPLACE')

		# Ставим меш в систему координат арматуры: вершины уже посчитаны в ней.
		obj.parent = self.rig.armature
		obj.matrix_parent_inverse = Matrix.Identity(4)
		obj.matrix_local = Matrix.Identity(4)
		modifier = obj.modifiers.new(name="Armature", type='ARMATURE')
		modifier.object = self.rig.armature
		return obj


def bmesh_to_mesh(source):
	temp = bpy.data.meshes.new("temp")
	source.to_mesh(temp)
	return temp


_materials = {}


def make_material(key):
	if key in _materials:
		return _materials[key]
	material = bpy.data.materials.new(key)
	material.use_nodes = True
	bsdf = material.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = PALETTE[key]
	bsdf.inputs["Roughness"].default_value = 0.85
	bsdf.inputs["Metallic"].default_value = 0.6 if key in ("steel", "roger_iron") else 0.0
	_materials[key] = material
	return material


# --- общая анатомия --------------------------------------------------------

def skeleton_parts(body, rig, spec):
	"""Туловище, руки и ноги по головам костей — общая основа всех четверых."""
	up, fwd, left = rig.up, rig.fwd, rig.left
	cloth = spec["cloth"]
	dark = spec["dark"]
	skin = spec["skin"]
	thin = spec["limb"]

	hips = rig.head("Hips")
	spine = rig.head("Spine")
	spine2 = rig.head("Spine2")
	neck = rig.head("Neck")
	head = rig.head("Head")

	body.tube(rig.name("Hips"), hips - up * 2, spine, spec["hip"], spec["waist"], cloth)
	body.tube(rig.name("Spine1"), spine, spine2, spec["waist"], spec["chest"], cloth)
	body.tube(rig.name("Spine2"), spine2, neck, spec["chest"], spec["chest"] * 0.7, cloth)
	body.tube(rig.name("Neck"), neck, head, thin * 0.9, thin * 0.9, skin)
	body.ball(rig.name("Head"), head + up * spec["head"] * 0.75, spec["head"], skin,
			  squash=Vector((0.85, 1.0, 0.9)))

	for side in ("Left", "Right"):
		shoulder = rig.head(side + "Shoulder")
		arm = rig.head(side + "Arm")
		fore = rig.head(side + "ForeArm")
		hand = rig.head(side + "Hand")
		hand_dir = (hand - fore).normalized()

		body.tube(rig.name(side + "Shoulder"), shoulder, arm, spec["chest"] * 0.55, thin * 1.25, cloth)
		body.tube(rig.name(side + "Arm"), arm, fore, thin * 1.15, thin, cloth)
		body.tube(rig.name(side + "ForeArm"), fore, hand, thin, thin * 0.85, skin)
		body.box(rig.name(side + "Hand"), hand + hand_dir * thin * 1.2,
				 Vector((thin * 1.9, thin * 1.5, thin * 2.4)), skin)

		up_leg = rig.head(side + "UpLeg")
		leg = rig.head(side + "Leg")
		foot = rig.head(side + "Foot")
		toe = rig.head(side + "ToeBase")

		body.tube(rig.name(side + "UpLeg"), up_leg, leg, spec["thigh"], spec["thigh"] * 0.8, cloth)
		body.tube(rig.name(side + "Leg"), leg, foot, spec["thigh"] * 0.75, thin * 1.1, cloth)
		body.box(rig.name(side + "Foot"), (foot + toe) * 0.5 + fwd * 3 * CM,
				 Vector((thin * 2.2, thin * 2.0, (toe - foot).length + 6 * CM)), dark)


# --- роли ------------------------------------------------------------------

def build_guest(rig):
	"""Гость: обычный человек в тряпье. Ничего страшного — в этом и дело."""
	body = Body(rig, "guest")
	spec = {
		"cloth": "guest_cloth", "dark": "guest_dark", "skin": "guest_skin",
		"limb": 4.2 * CM, "hip": 9.5 * CM, "waist": 8.5 * CM, "chest": 11.0 * CM,
		"thigh": 6.5 * CM, "head": 9.0 * CM,
	}
	skeleton_parts(body, rig, spec)

	# Рваная куртка: юбка от пояса и воротник.
	spine = rig.head("Spine")
	body.tube(rig.name("Spine"), spine + rig.up * 2, spine - rig.up * 16 * CM,
			  12.0 * CM, 14.5 * CM, "guest_dark")
	body.tube(rig.name("Spine2"), rig.head("Neck") - rig.up * 3 * CM,
			  rig.head("Neck") + rig.up * 4 * CM, 9.5 * CM, 8.0 * CM, "guest_dark")
	return body


def build_trickster(rig):
	"""Трикстер: арлекин в смеющейся маске, с серпом в правой руке."""
	body = Body(rig, "trickster")
	spec = {
		"cloth": "trick_red", "dark": "trick_dark", "skin": "trick_red",
		"limb": 4.0 * CM, "hip": 9.0 * CM, "waist": 7.5 * CM, "chest": 10.5 * CM,
		"thigh": 6.0 * CM, "head": 8.5 * CM,
	}
	skeleton_parts(body, rig, spec)

	up, fwd, left = rig.up, rig.fwd, rig.left
	head = rig.head("Head")

	# Маска: плоская личина на лице, а не шар на голове.
	body.ball(rig.name("Head"), head + up * 6.5 * CM + fwd * 5.0 * CM, 7.5 * CM,
			  "trick_bone", squash=Vector((0.9, 1.05, 0.42)))
	# Два рога колпака.
	for sign in (-1, 1):
		tip = head + up * 20 * CM + left * sign * 12 * CM - fwd * 4 * CM
		body.tube(rig.name("Head"), head + up * 10 * CM + left * sign * 3 * CM, tip,
				  4.0 * CM, 0.4 * CM, "trick_dark", sides=5)

	# Фалды: рваный подол куртки.
	spine = rig.head("Spine")
	for i in range(6):
		angle = (i / 6.0) * math.tau
		direction = (left * math.cos(angle) + fwd * math.sin(angle))
		body.tube(rig.name("Hips"), spine + direction * 6 * CM,
				  spine + direction * 9 * CM - up * (14 + (i % 3) * 5) * CM,
				  3.5 * CM, 0.6 * CM, "trick_dark", sides=4)

	# Серп в правой руке и нож в левой — оружие теперь видно, а не подразумевается.
	hand = rig.head("RightHand")
	hand_dir = (hand - rig.head("RightForeArm")).normalized()
	shaft_end = hand + hand_dir * 42 * CM
	body.tube(rig.name("RightHand"), hand - hand_dir * 8 * CM, shaft_end,
			  1.6 * CM, 1.3 * CM, "trick_dark", sides=6)
	blade_dir = (fwd * 0.85 + up * 0.25).normalized()
	body.tube(rig.name("RightHand"), shaft_end, shaft_end + blade_dir * 26 * CM,
			  2.6 * CM, 0.5 * CM, "steel", sides=4)

	left_hand = rig.head("LeftHand")
	left_dir = (left_hand - rig.head("LeftForeArm")).normalized()
	body.tube(rig.name("LeftHand"), left_hand + left_dir * 3 * CM,
			  left_hand + left_dir * 20 * CM, 1.4 * CM, 0.3 * CM, "steel", sides=4)
	return body


def build_witch(rig):
	"""Ведьма: балахон до земли и венец из шипов. Ног не видно вовсе."""
	body = Body(rig, "witch")
	spec = {
		"cloth": "witch_green", "dark": "witch_dark", "skin": "witch_green",
		"limb": 3.8 * CM, "hip": 8.5 * CM, "waist": 8.0 * CM, "chest": 10.0 * CM,
		"thigh": 5.0 * CM, "head": 8.5 * CM,
	}
	skeleton_parts(body, rig, spec)

	up, fwd, left = rig.up, rig.fwd, rig.left
	head = rig.head("Head")
	hips = rig.head("Hips")

	# Балахон: конус от пояса до пола, привязанный к тазу — ноги под ним просто
	# не читаются, и это ровно тот силуэт, который нужен.
	body.tube(rig.name("Hips"), hips + up * 6 * CM, hips - up * 88 * CM,
			  13.0 * CM, 27.0 * CM, "witch_green", sides=8)
	body.tube(rig.name("Spine1"), rig.head("Spine2"), hips + up * 4 * CM,
			  12.5 * CM, 13.5 * CM, "witch_dark", sides=8)

	# Венец из шипов.
	for i in range(7):
		angle = (i / 7.0) * math.tau
		direction = (left * math.cos(angle) + fwd * math.sin(angle))
		base = head + up * 13 * CM + direction * 6 * CM
		body.tube(rig.name("Head"), base, base + (direction * 0.5 + up).normalized() * 13 * CM,
				  1.8 * CM, 0.3 * CM, "witch_thorn", sides=4)

	# Лоза с шипами вместо правого предплечья.
	fore = rig.head("RightForeArm")
	hand = rig.head("RightHand")
	for i in range(4):
		t = 0.2 + i * 0.22
		base = fore.lerp(hand, t)
		direction = (fwd * math.cos(i * 2.1) + up * math.sin(i * 2.1)).normalized()
		body.tube(rig.name("RightForeArm"), base, base + direction * 7 * CM,
				  1.4 * CM, 0.2 * CM, "witch_thorn", sides=4)
	return body


def build_roger(rig):
	"""Весёлый Роджер: туша в парусине, якорная цепь и кулаки не по росту."""
	body = Body(rig, "roger")
	spec = {
		"cloth": "roger_canvas", "dark": "roger_dark", "skin": "roger_canvas",
		"limb": 6.5 * CM, "hip": 13.0 * CM, "waist": 13.5 * CM, "chest": 17.0 * CM,
		"thigh": 9.5 * CM, "head": 9.5 * CM,
	}
	skeleton_parts(body, rig, spec)

	up, fwd, left = rig.up, rig.fwd, rig.left
	neck = rig.head("Neck")
	head = rig.head("Head")

	# Горб и покатые плечи: голова сидит в туше, а не над ней.
	body.ball(rig.name("Spine2"), neck - fwd * 6 * CM - up * 2 * CM, 15.0 * CM,
			  "roger_canvas", squash=Vector((1.25, 0.85, 1.0)))
	# Мешок на голове.
	body.ball(rig.name("Head"), head + up * 7 * CM, 10.5 * CM, "roger_dark",
			  squash=Vector((0.95, 1.1, 0.95)))

	# Якорная цепь через грудь.
	for i in range(7):
		t = i / 6.0
		point = (rig.head("LeftShoulder").lerp(rig.head("Spine"), t)
				 + fwd * (9 - abs(t - 0.5) * 6) * CM)
		body.ball(rig.name("Spine2"), point, 3.2 * CM, "roger_iron")

	# Кулаки: вдвое больше человеческих.
	for side in ("Left", "Right"):
		hand = rig.head(side + "Hand")
		hand_dir = (hand - rig.head(side + "ForeArm")).normalized()
		body.ball(rig.name(side + "Hand"), hand + hand_dir * 9 * CM, 8.5 * CM, "roger_iron",
				  squash=Vector((1.0, 1.0, 1.15)))
	return body


# --- сборка ----------------------------------------------------------------

def main():
	wipe_scene()
	armature = import_donor()
	rig = Rig(armature)
	log("оси: up=%s fwd=%s left=%s, рост ~%.0f см" % (
		tuple(round(v, 2) for v in rig.up), tuple(round(v, 2) for v in rig.fwd),
		tuple(round(v, 2) for v in rig.left), rig.height()))

	built = []
	for builder in (build_guest, build_trickster, build_witch, build_roger):
		body = builder(rig)
		obj = body.build()
		built.append(obj)
		log("%s: %d деталей, %d полигонов" % (obj.name, len(body.parts), len(obj.data.polygons)))

	bpy.ops.object.select_all(action='DESELECT')
	armature.select_set(True)
	for obj in built:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = armature

	bpy.ops.export_scene.gltf(
		filepath=OUTPUT,
		export_format='GLB',
		use_selection=True,
		export_animations=True,
		export_animation_mode='ACTIONS',
		export_apply=False,
	)
	log("готово: %s (%.1f КБ)" % (OUTPUT, os.path.getsize(OUTPUT) / 1024.0))


main()
