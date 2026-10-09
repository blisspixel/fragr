class_name SkinnedCharacter
extends Node3D

## Render-only skin. Callers own accepted feet, facing, health and equipment.
const SOURCES: Dictionary[String, String] = {
	"human": "res://assets/models/free_human_live.glb",
	"synthetic": "res://assets/models/free_synthetic_live.glb",
	"tern": "res://assets/models/tern_live.glb",
	"edda": "res://assets/models/edda_live.glb",
}
const SUPPORT_PATH: String = "res://assets/models/character_support.json"
const FALL_SECONDS: float = 0.35
static var _packed: Dictionary[String, PackedScene] = {}
static var _supports: Dictionary = {}
var kind: String = ""
var source_body: Node3D
var skeleton: Skeleton3D
var aim_pitch: float = 0.0
var _source: LatchSource = LatchSource.new()
var _materials: Dictionary[StandardMaterial3D, Color] = {}
var _stride: float = 0.0
var _fall: float = 0.0
var _register_floor: bool = true

func configure(body_kind: String, register_floor: bool = true) -> bool:
	if not SOURCES.has(body_kind) or source_body != null:
		return false
	if not _packed.has(body_kind):
		if not ResourceLoader.exists(SOURCES[body_kind], "PackedScene"):
			return false
		_packed[body_kind] = load(SOURCES[body_kind]) as PackedScene
	if _packed[body_kind] == null:
		return false
	if register_floor and _supports.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUPPORT_PATH)) \
			if FileAccess.file_exists(SUPPORT_PATH) else null
		if data is Dictionary and data.get("schema") == 1 and data.get("bodies") is Dictionary:
			_supports = data["bodies"]
	if register_floor and not _valid_support(_supports.get(body_kind)):
		return false
	var candidate: Node3D = _packed[body_kind].instantiate() as Node3D
	var rig: Skeleton3D = candidate.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	var player: AnimationPlayer = candidate.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if rig == null or player == null:
		candidate.free()
		return false
	for bone: String in ["Hips", "RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		if rig.find_bone(bone) < 0:
			candidate.free()
			return false
	if not player.has_animation(&"walk"):
		for clip: StringName in player.get_animation_list():
			if str(clip).contains("walking_man"):
				# Alias the retained keys in this instance, never edit the GLB.
				var animation: Animation = player.get_animation(clip)
				var library: AnimationLibrary = player.get_animation_library(&"").duplicate() as AnimationLibrary
				player.remove_animation_library(&"")
				library.add_animation(&"walk", animation)
				player.add_animation_library(&"", library)
				break
	if not player.has_animation(&"walk"):
		candidate.free()
		return false
	kind = body_kind
	_register_floor = register_floor
	source_body = candidate
	skeleton = rig
	source_body.name = "CharacterSkin"
	add_child(source_body)
	for node: Node in source_body.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		part.layers = ArenaSky.ACTOR_LAYERS
		for surface: int in range(part.mesh.get_surface_count()):
			var original: StandardMaterial3D = part.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var material: StandardMaterial3D = original.duplicate() as StandardMaterial3D
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			part.set_surface_override_material(surface, material)
			_materials[material] = material.albedo_color
	pose(0.0, false, false, false)
	return true

static func _valid_support(value: Variant) -> bool:
	if not value is Dictionary or not value.get("floor") is Dictionary:
		return false
	for action: String in ["idle", "walk", "duck", "duck_walk", "fall"]:
		var curve: Variant = value["floor"].get(action)
		if not curve is Array or curve.size() < 2 or curve.size() > 257:
			return false
		for height: Variant in curve:
			if not (height is float or height is int) or not is_finite(float(height)) or absf(float(height)) > 2.0:
				return false
	return true

func advance(delta: float, travel: float, alive: bool, armed: bool, ducked: bool, seated: bool = false) -> void:
	var moving: bool = alive and travel > 0.0001 and travel < 2.0
	if moving:
		_stride = fposmod(_stride + travel / EnemyAnimation.STRIDE_METRES, 1.0)
	elif travel >= 2.0:
		_stride = 0.0
	_fall = 0.0 if alive else minf(1.0, _fall + maxf(0.0, delta) / FALL_SECONDS)
	pose(_stride, moving, armed, ducked, _fall, seated)

func pose(phase: float, moving: bool, armed: bool, ducked: bool, fallen: float = 0.0, seated: bool = false) -> void:
	if source_body == null:
		return
	source_body.position = Vector3.ZERO
	source_body.rotation = Vector3.ZERO
	skeleton.reset_bone_poses()
	fallen = clampf(fallen, 0.0, 1.0)
	if moving and fallen == 0.0:
		_source._sample_walk(source_body, skeleton, phase)
	var drop: float = 45.0 if ducked and fallen == 0.0 else 0.0
	if drop > 0.0:
		var feet: Dictionary = {}
		for side: String in ["Left", "Right"]:
			feet[side] = skeleton.get_bone_global_pose(skeleton.find_bone(side + "Foot")).origin
		var hips: int = skeleton.find_bone("Hips")
		var at: Vector3 = skeleton.get_bone_pose_position(hips)
		at.y -= drop
		skeleton.set_bone_pose_position(hips, at)
		for side: String in ["Left", "Right"]:
			_source._two_bone(skeleton, side + "UpLeg", side + "Leg", side + "Foot", feet[side], feet[side] + Vector3(0, 60, 65))
	var sway: float = sin(phase * TAU) * 2.0 if moving else 0.0
	var right: Vector3 = Vector3(-24, 96 + sway - drop, 8)
	var left: Vector3 = Vector3(24, 96 - sway - drop, 8)
	var right_pole: Vector3 = Vector3(-44, 108 - drop, 2)
	var left_pole: Vector3 = Vector3(44, 108 - drop, 2)
	if kind == "edda":
		# Measured resting wrists stay outside her original left-hip satchel.
		right = Vector3(-27, 97 - drop, 8)
		left = Vector3(35, 97 - drop, 8)
		right_pole = Vector3(-46, 108 - drop, 2)
		left_pole = Vector3(49, 108 - drop, 2)
	if armed and fallen == 0.0:
		var pitch: float = clampf(aim_pitch, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)
		var shoulder: Vector3 = Vector3(0, 122 - drop, 0)
		right = shoulder + Vector3(-18, 0, 35).rotated(Vector3.RIGHT, -pitch)
		left = shoulder + Vector3(12, -5, 38).rotated(Vector3.RIGHT, -pitch)
	elif seated and fallen == 0.0:
		right = Vector3(-18, 109 - drop, 32)
		left = Vector3(18, 109 - drop, 32)
	# Her accepted unarmed gait includes the retained walking arm tracks.
	if kind != "edda" or not moving or armed or seated or fallen > 0.0:
		_source._two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", right, right_pole)
		_source._two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", left, left_pole)
	var action: String = ("duck_walk" if moving else "duck") if ducked else ("walk" if moving else "idle")
	var progress: float = phase
	if fallen > 0.0:
		action = "fall"
		progress = smoothstep(0.0, 1.0, fallen)
		source_body.rotation.x = -PI * 0.5 * progress
	if _register_floor:
		source_body.position.y = -_floor(action, progress)

func _floor(action: String, progress: float) -> float:
	var curve: Array = _supports[kind]["floor"][action]
	var index: float = clampf(progress, 0.0, 1.0) * (curve.size() - 1) if action == "fall" \
		else fposmod(progress, 1.0) * (curve.size() - 1)
	var start: int = mini(int(floor(index)), curve.size() - 2)
	return lerpf(float(curve[start]), float(curve[start + 1]), index - start)

func hand_transform() -> Transform3D:
	return source_body.transform * _source.bone_transform(source_body, "RightHand")

func tint(color: Color) -> void:
	for material: StandardMaterial3D in _materials:
		material.albedo_color = _materials[material] * color
