extends SceneTree

const CharacterView = preload("res://scripts/skinned_character.gd")
const HASHES: Dictionary[String, String] = {
	"human": "94f09896185df36697307e990ebce85fa7871c356be96394cac0a3dd83cd5dff",
	"synthetic": "82107fdc3b0cc17eef6237e3776ae4dfcae59be2b082f66040396175f4eea3f7",
	"tern": "0f8bfd1c99b1d7c1172eaaa76203d28234a1d3f3db793f6f81bc6b5740fa993f",
	"edda": "cbf1e1e16329da194fdf058f308676e72bfefb357faeea915fc3d9500d57ea40",
}
const PHASES: Array[float] = [0.0037, 0.217, 0.219, 0.3141, 0.5013, 0.739, 0.997]
const FLOOR_TOLERANCE: float = 0.01
var _failures: PackedStringArray = []
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var supports: Variant = JSON.parse_string(FileAccess.get_file_as_string(CharacterView.SUPPORT_PATH))
	_expect(supports is Dictionary, "support document available")
	if not supports is Dictionary:
		quit(1)
		return
	_expect(supports.get("pose_sha256") == FileAccess.get_sha256("res://scripts/skinned_character.gd"), "support curves bind the current pose implementation")
	for invalid: String in ["", "C-tern", "unknown", "../tern", "human.glb"]:
		var rejected: Node3D = CharacterView.new()
		root.add_child(rejected)
		_expect(not rejected.configure(invalid) and rejected.source_body == null and rejected.get_child_count() == 0, "invalid id has no partial figure: " + invalid)
		rejected.free()
	for kind: String in HASHES:
		var view: Node3D = CharacterView.new()
		root.add_child(view)
		_expect(view.configure(kind), "configured " + kind)
		if view.source_body == null:
			view.free()
			continue
		_expect(FileAccess.get_sha256(CharacterView.SOURCES[kind]) == HASHES[kind], "packaged reviewed source identity " + kind)
		_expect(supports.bodies[kind].source_sha256 == HASHES[kind], "support source identity " + kind)
		_expect(view.skeleton.get_bone_count() == 24, "retained full rig " + kind)
		var original_body: Node3D = view.source_body
		_expect(not view.configure("tern") and view.source_body == original_body and view.kind == kind, "second configure cannot replace a live figure " + kind)
		var arrays: Array = _mesh(view).mesh.surface_get_arrays(0)
		var raw_points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var rest_segments: PackedFloat32Array = _arm_lengths(view)
		var idle: Dictionary = _skin(view)
		_expect(idle.valid and idle.points.size() > 10000, "valid complete weighted skin " + kind)
		_expect(float(idle.bounds.size.y) > 1.65 and float(idle.bounds.size.y) < 1.95, "ordinary adult weighted idle scale " + kind)
		_expect(absf(float(idle.bounds.position.y)) <= FLOOR_TOLERANCE, "weighted idle feet registered " + kind)
		for node: Node in view.find_children("*", "MeshInstance3D", true, false):
			_expect(node.layers == ArenaSky.ACTOR_LAYERS, "actor light layers " + kind)
			for surface: int in range(node.mesh.get_surface_count()):
				var material: StandardMaterial3D = node.get_active_material(surface) as StandardMaterial3D
				_expect(material != null and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "pixel material filtering " + kind)
		_expect(view.find_children("*", "CollisionObject3D", true, false).is_empty(), "presenter adds no collision authority " + kind)
		var maximum_floor_error: float = 0.0
		var maximum_motion: float = 0.0
		for action: String in ["walk", "duck", "duck_walk", "fall"]:
			for phase: float in PHASES:
				view.pose(phase, action in ["walk", "duck_walk"], phase > 0.5, action in ["duck", "duck_walk"], phase if action == "fall" else 0.0)
				var skin: Dictionary = _skin(view)
				_expect(skin.valid, "finite weighted " + kind + " " + action)
				var error: float = absf(float(skin.bounds.position.y))
				maximum_floor_error = maxf(maximum_floor_error, error)
				_expect(error <= FLOOR_TOLERANCE, "%s %s off-grid %.4f floor %.6fm" % [kind, action, phase, skin.bounds.position.y])
				_expect(_same_lengths(rest_segments, _arm_lengths(view)), "arm segments retain length " + kind + " " + action)
				_expect(_mesh(view).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == raw_points, "pose changes skin without rewriting geometry " + kind)
				if action == "walk":
					maximum_motion = maxf(maximum_motion, _motion(idle.points, skin.points))
				if action == "duck":
					_expect(skin.bounds.size.y < idle.bounds.size.y - 0.25, "actual weighted crouch lowers silhouette " + kind)
				if action == "fall" and phase > 0.99:
					_expect(skin.bounds.size.y < idle.bounds.size.y * 0.55, "actual weighted fallen body stays low " + kind)
		_expect(maximum_motion > 0.08, "true weighted walk deformation " + kind)
		view.pose(0.447, true, true, false)
		view.position = Vector3(7.0, 2.0, -3.0)
		view.rotation.y = 0.63
		var hand_world: Vector3 = view.skeleton.global_transform * view.skeleton.get_bone_global_pose(view.skeleton.find_bone("RightHand")).origin
		_expect((view.global_transform * view.hand_transform().origin).distance_to(hand_world) < 0.0001, "carried anchor matches actual posed wrist " + kind)
		view.position = Vector3.ZERO
		view.rotation = Vector3.ZERO
		view.advance(0.2, 0.0, false, true, false)
		view.advance(0.2, 0.0, false, true, false)
		_expect(view.source_body.rotation.x < -1.5, "advance presents the completed fall " + kind)
		view.advance(0.05, 0.0, true, false, false)
		_expect(absf(view.source_body.rotation.x) < 0.0001, "accepted alive state restores upright pose " + kind)
		_expect(absf(float(_skin(view).bounds.position.y)) < FLOOR_TOLERANCE, "respawn pose registered " + kind)
		_rows.append({"kind": kind, "vertices": idle.points.size(), "weighted_idle_height": idle.bounds.size.y,
			"maximum_off_grid_floor_error_m": maximum_floor_error, "maximum_actual_walk_vertex_motion_m": maximum_motion})
		view.free()
	_alias_and_tint()
	await _pawn_seats()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 1:
		var file: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"schema": 1, "floor_tolerance_m": FLOOR_TOLERANCE, "phases": PHASES,
				"sources": HASHES, "pose_sha256": FileAccess.get_sha256("res://scripts/skinned_character.gd"),
				"support_sha256": FileAccess.get_sha256(CharacterView.SUPPORT_PATH), "bodies": _rows, "failures": _failures}, "\t") + "\n")
			file.close()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("test_skinned_character: " + failure)
		quit(1)
		return
	print("test_skinned_character: PASS (actual weighted off-grid poses, source identity, skin motion, aliases, materials and anchors)")
	quit(0)

func _pawn_seats() -> void:
	for kind: String in ["human", "synthetic"]:
		var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
		root.add_child(pawn)
		await process_frame
		pawn.set_process(false)
		pawn.set_player_data("seat-fixture", "Seat fixture")
		var state: Dictionary = {"x": 0.0, "y": 1.5, "z": 0.0, "yaw": 0.0,
			"hp": 100, "weapon": "Tack", "body": kind, "ducking": false}
		pawn.update_state(state, 1)
		pawn.vehicle_seated = true
		for driver: bool in [true, false]:
			pawn.clear_predicted_position()
			state.ducking = driver
			pawn.update_state(state, 2 if driver else 3)
			pawn.set_predicted_position(Vector3(0, 1.5, 0), 5.0)
			var stride: float = pawn.character_view._stride
			pawn._process(0.05)
			pawn.set_predicted_position(Vector3(0.25, 1.5, 0), 5.0)
			pawn._process(0.05)
			_expect(pawn.character_view._stride == stride and pawn.presentation_speed == 0.0,
				"seated accepted displacement never walks " + kind)
			_expect(not pawn._held_root.visible and not pawn.weapon_sprite.is_visible_in_tree(),
				"seated driver/gunner never shows a carried firearm " + kind)
			var skin: Dictionary = _skin(pawn.character_view)
			_expect(skin.valid, "valid accepted seat skin " + kind)
			_expect(skin.bounds.size.y < 1.55 if driver else skin.bounds.size.y > 1.65,
				"driver obeys authoritative crouch and gunner remains upright " + kind)
		pawn.vehicle_seated = false
		state.ducking = false
		for yaw: float in [0.0, 1.2, -2.1]:
			for pitch: float in [-ServerYaw.PITCH_LIMIT, -0.4, 0.0, 0.7, ServerYaw.PITCH_LIMIT]:
				pawn.clear_predicted_position()
				state.yaw = yaw
				state.pitch = pitch
				pawn.update_state(state)
				pawn.set_predicted_position(Vector3(0, 1.5, 0), 0.0)
				pawn._process(0.05)
				var direction: Vector3 = pawn._held_root.global_basis.x.normalized()
				_expect(direction.distance_to(ServerYaw.aim_direction(yaw, pitch)) < 0.0001,
					"carried direction matches accepted extreme pitch " + kind)
				_expect(pawn.weapon_sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED,
					"live profile does not override accepted pitch with fixed-Y " + kind)
				_expect(pawn._held_root.basis.is_equal_approx(Basis(Vector3.BACK, pitch)),
					"no-camera profile has stable pitched basis " + kind)
				_expect(pawn.weapon_sprite.flip_h, "pistol painted muzzle points along positive gun axis " + kind)
				var painted_grip: Vector3 = pawn.weapon_sprite.position + Vector3(-7.0, -3.0, 0.0) * pawn.weapon_sprite.pixel_size
				_expect(painted_grip.length() < 0.0001, "pistol painted grip reaches posed wrist " + kind)
				var before: PackedFloat32Array = _arm_lengths(pawn.character_view)
				pawn.character_view.pose(0.371, true, true, false)
				_expect(_same_lengths(before, _arm_lengths(pawn.character_view)), "aim pose retains weighted arm lengths " + kind)
		var camera: Camera3D = Camera3D.new()
		root.add_child(camera)
		camera.current = true
		for yaw: float in [0.0, 1.2, -2.1]:
			for pitch: float in [-ServerYaw.PITCH_LIMIT, 0.0, ServerYaw.PITCH_LIMIT]:
				state.yaw = yaw
				state.pitch = pitch
				pawn.update_state(state)
				pawn._process(0.05)
				var axis: Vector3 = ServerYaw.aim_direction(yaw, pitch)
				var wrist: Vector3 = pawn._held_root.global_position
				for offset: Vector3 in [Vector3(3, 2, 4), Vector3(-2, 4, -3), axis * 4.0]:
					camera.position = wrist + offset
					pawn._attach_carried()
					var basis: Basis = pawn._held_root.global_basis
					_expect(basis.is_finite() and absf(basis.determinant() - 1.0) < 0.0001,
						"camera-facing and end-on carried basis remains orthonormal " + kind)
					_expect(basis.x.distance_to(axis) < 0.0001 and pawn.weapon_sprite.global_basis.x.distance_to(axis) < 0.0001,
						"camera-facing profile keeps actual gun axis " + kind)
					var projected: Vector3 = offset - axis * offset.dot(axis)
					if projected.length() > 0.01:
						_expect(absf(basis.z.dot(projected.normalized())) > 0.9999,
							"profile plane faces camera subject to accepted gun axis " + kind)
		_expect(pawn.weapon_sprite.double_sided, "profile remains visible from either side " + kind)
		camera.free()
		pawn.free()

func _alias_and_tint() -> void:
	var first: Node3D = CharacterView.new()
	var second: Node3D = CharacterView.new()
	root.add_child(first)
	root.add_child(second)
	if not first.configure("tern") or not second.configure("tern"):
		_expect(false, "two actual Tern instances available")
		first.free()
		second.free()
		return
	var player: AnimationPlayer = first.source_body.get_node("AnimationPlayer") as AnimationPlayer
	var original: StringName = &"Armature|walking_man|baselayer"
	_expect(player.has_animation(original) and player.has_animation(&"walk"), "Tern original and walk alias retained")
	if player.has_animation(original):
		_expect(player.get_animation(original) == player.get_animation(&"walk") and player.get_animation(original).get_track_count() > 0, "walk alias keeps the actual imported original keys")
	var packed: PackedScene = load(CharacterView.SOURCES["tern"]) as PackedScene
	var untouched: Node3D = packed.instantiate() as Node3D
	_expect(not (untouched.get_node("AnimationPlayer") as AnimationPlayer).has_animation(&"walk"), "alias does not mutate the cached source library")
	untouched.free()
	var first_material: StandardMaterial3D = _mesh(first).get_active_material(0) as StandardMaterial3D
	var second_material: StandardMaterial3D = _mesh(second).get_active_material(0) as StandardMaterial3D
	var original_color: Color = second_material.albedo_color
	first.tint(Color(1.0, 0.2, 0.3))
	_expect(first_material != second_material and second_material.albedo_color == original_color, "tint remains local to the actual instance")
	first.tint(Color.WHITE)
	_expect(first_material.albedo_color == original_color, "tint restoration uses source color")
	first.free()
	second.free()

func _skin(view: Node3D) -> Dictionary:
	var result: PackedVector3Array = []
	var valid: bool = true
	var local: Transform3D = view.global_transform.affine_inverse()
	for node: Node in view.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var rig: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if rig == null or mesh.skin == null:
			return {"valid": false, "points": result, "bounds": AABB()}
		var bindings: Array[Transform3D] = []
		for bind: int in range(mesh.skin.get_bind_count()):
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = rig.find_bone(mesh.skin.get_bind_name(bind))
			if bone < 0 or bone >= rig.get_bone_count():
				return {"valid": false, "points": result, "bounds": AABB()}
			bindings.append(local * rig.global_transform * rig.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = int(joints.size() / positions.size())
			if influences not in [4, 8] or weights.size() != joints.size():
				return {"valid": false, "points": result, "bounds": AABB()}
			for vertex: int in range(positions.size()):
				var point: Vector3 = Vector3.ZERO
				var total: float = 0.0
				for influence: int in range(influences):
					var at: int = vertex * influences + influence
					if joints[at] < 0 or joints[at] >= bindings.size() or not is_finite(weights[at]) or weights[at] < 0.0:
						return {"valid": false, "points": result, "bounds": AABB()}
					point += (bindings[joints[at]] * positions[vertex]) * weights[at]
					total += weights[at]
				valid = valid and point.is_finite() and absf(total - 1.0) < 0.0001
				result.append(point)
	var bounds: AABB = AABB(result[0], Vector3.ZERO) if not result.is_empty() else AABB()
	for point: Vector3 in result:
		bounds = bounds.expand(point)
	return {"valid": valid and not result.is_empty(), "points": result, "bounds": bounds}

func _mesh(view: Node3D) -> MeshInstance3D:
	return view.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D

func _arm_lengths(view: Node3D) -> PackedFloat32Array:
	var result: PackedFloat32Array = []
	for side: String in ["Right", "Left"]:
		for pair: PackedStringArray in [PackedStringArray([side + "Arm", side + "ForeArm"]), PackedStringArray([side + "ForeArm", side + "Hand"])]:
			var a: Vector3 = view.skeleton.get_bone_global_pose(view.skeleton.find_bone(pair[0])).origin
			var b: Vector3 = view.skeleton.get_bone_global_pose(view.skeleton.find_bone(pair[1])).origin
			result.append(a.distance_to(b))
	return result

func _same_lengths(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	for index: int in range(a.size()):
		if not is_finite(b[index]) or absf(a[index] - b[index]) > 0.001:
			return false
	return true

func _motion(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var maximum: float = 0.0
	for index: int in range(a.size()):
		maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
