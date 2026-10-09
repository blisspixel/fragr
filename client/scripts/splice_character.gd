class_name SpliceCharacter
extends Node3D

## Named civilian appearance. Accepted mission feet and travel stay with callers.
const SOURCE: String = "res://assets/models/splice_live.glb"
const PARTS: PackedStringArray = ["head", "neck", "torso", "pelvis", "left_upper_arm", "left_forearm", "left_hand", "right_upper_arm", "right_forearm", "right_hand", "left_upper_leg", "left_lower_leg", "left_foot", "right_upper_leg", "right_lower_leg", "right_foot", "right_rack_and_stored_tools"]
const PARENTS: PackedInt32Array = [1, 2, 3, -1, 2, 4, 5, 2, 7, 8, 3, 10, 11, 3, 13, 14, 13]
const CAP_JOINTS: PackedInt32Array = [0, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
static var _packed: Dictionary[String, PackedScene] = {}
var source_body: Node3D
var _tracks: Dictionary[String, Array] = {}
var _lengths: Dictionary[String, float] = {}
var _rests: Dictionary[Node3D, Transform3D] = {}

func configure() -> bool:
	if source_body != null:
		return false
	if not _packed.has(SOURCE):
		if not ResourceLoader.exists(SOURCE, "PackedScene"):
			return false
		_packed[SOURCE] = load(SOURCE) as PackedScene
	if _packed[SOURCE] == null:
		return false
	var candidate: Node3D = _packed[SOURCE].instantiate() as Node3D
	if candidate == null:
		return false
	if not _bind(candidate):
		candidate.free()
		_tracks.clear()
		_lengths.clear()
		_rests.clear()
		return false
	source_body = candidate
	add_child(source_body)
	for node: Node in source_body.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers = ArenaSky.ACTOR_LAYERS
	pose(0.0, false)
	return true

func _bind(body: Node3D) -> bool:
	_tracks.clear()
	_lengths.clear()
	_rests.clear()
	var source: Node3D = body.find_child("SplicePrepared", true, false) as Node3D
	var players: Array[Node] = body.find_children("*", "AnimationPlayer", true, false)
	if source == null or players.size() != 1:
		return false
	var allowed: Array[Node3D] = [source]
	for part: int in PARTS.size():
		var pivot: Node3D = source.find_child(PARTS[part], true, false) as Node3D
		var expected: String = "SplicePrepared" if PARENTS[part] < 0 else PARTS[PARENTS[part]]
		if pivot == null or String(pivot.get_parent().name) != expected:
			return false
		if not _valid_surface(pivot.get_node_or_null(PARTS[part] + "_surface")):
			return false
		allowed.append(pivot)
	for child: int in CAP_JOINTS:
		for owner: int in [PARENTS[child], child]:
			var name: String = "OriginalEdgeClosure_%d_%d" % [child, owner]
			if not _valid_surface(allowed[owner + 1].get_node_or_null(name)):
				return false
	if source.find_children("*", "MeshInstance3D", true, false).size() != PARTS.size() + CAP_JOINTS.size() * 2:
		return false
	for node: Node3D in allowed:
		_rests[node] = node.transform
	var player: AnimationPlayer = players[0] as AnimationPlayer
	var origin: Node = player.get_node_or_null(player.root_node)
	if origin == null:
		return false
	for clip: String in ["calm", "walk"]:
		if not player.has_animation(clip):
			return false
		var animation: Animation = player.get_animation(clip)
		if not is_finite(animation.length) or animation.length <= 0.0 or animation.length > 4.001 or animation.get_track_count() > 64:
			return false
		var rows: Array = []
		for track: int in animation.get_track_count():
			var type: int = animation.track_get_type(track)
			var path: NodePath = animation.track_get_path(track)
			var target: Node3D = origin.get_node_or_null(path) as Node3D
			if path.get_subname_count() != 0 or target == null or target not in allowed or type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				return false
			rows.append({"type": type, "node": target, "animation": animation, "track": track})
		if rows.is_empty():
			return false
		_tracks[clip] = rows
		_lengths[clip] = animation.length
	player.stop()
	return true

static func _valid_surface(node: Node) -> bool:
	var surface: MeshInstance3D = node as MeshInstance3D
	return surface != null and surface.mesh is ArrayMesh and surface.mesh.get_surface_count() == 1

func pose(phase: float, moving: bool, calm_phase: float = 0.0) -> void:
	if source_body == null or not is_finite(phase) or not is_finite(calm_phase):
		return
	var clip: String = "walk" if moving else "calm"
	var seconds: float = fposmod(phase if moving else calm_phase, 1.0) * _lengths[clip]
	for node: Node3D in _rests:
		node.transform = _rests[node]
	for row: Dictionary in _tracks[clip]:
		var animation: Animation = row.animation
		var node: Node3D = row.node
		match int(row.type):
			Animation.TYPE_POSITION_3D:
				node.position = animation.position_track_interpolate(int(row.track), seconds)
			Animation.TYPE_ROTATION_3D:
				node.quaternion = animation.rotation_track_interpolate(int(row.track), seconds)
			Animation.TYPE_SCALE_3D:
				node.scale = animation.scale_track_interpolate(int(row.track), seconds)
