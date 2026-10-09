extends SceneTree

const SOURCE_SHA256: String = "002749ba040d15703605693563b6e1b1f1ceebe554ebb2a5e2461da2f1f48f98"
var _failures: PackedStringArray = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	_expect(FileAccess.get_sha256(SpliceCharacter.SOURCE) == SOURCE_SHA256, "selected source matches reviewed compact bytes")
	var view: SpliceCharacter = SpliceCharacter.new()
	root.add_child(view)
	_expect(view.configure(), "actual imported resource configures")
	if view.source_body == null:
		_finish()
		return
	var original: Node3D = view.source_body
	_expect(not view.configure() and view.source_body == original, "repeated configure cannot replace an active body")
	var native: Node3D = SpliceCharacter._packed[SpliceCharacter.SOURCE].instantiate() as Node3D
	root.add_child(native)
	var player: AnimationPlayer = native.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var meshes: Array[MeshInstance3D] = []
	var controls: Array[MeshInstance3D] = []
	var points: Array[PackedVector3Array] = []
	var triangles: int = 0
	for part: String in SpliceCharacter.PARTS:
		var mesh: MeshInstance3D = view.source_body.find_child(part + "_surface", true, false) as MeshInstance3D
		var control: MeshInstance3D = native.find_child(part + "_surface", true, false) as MeshInstance3D
		_expect(mesh != null and control != null, "retained source region " + part)
		if mesh == null or control == null:
			continue
		meshes.append(mesh)
		controls.append(control)
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		points.append(arrays[Mesh.ARRAY_VERTEX])
		triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		_expect(mesh.layers == ArenaSky.ACTOR_LAYERS, "actor lighting layer " + part)
	_expect(triangles == 16602, "all original source faces remain selected")
	_expect(view.source_body.find_children("OriginalEdgeClosure_*", "MeshInstance3D", true, false).size() == 28, "actual exported edge closures remain present")
	var maximum: float = 0.0
	var floor_error: float = 0.0
	for clip: String in ["calm", "walk"]:
		for index: int in 128:
			var phase: float = (float(index) + 0.413) / 128.0
			player.play(clip)
			player.seek(phase * player.get_animation(clip).length, true)
			player.pause()
			view.pose(phase, clip == "walk", phase)
			var floor_y: float = INF
			for part: int in meshes.size():
				for point: Vector3 in points[part]:
					var actual: Vector3 = meshes[part].global_transform * point
					maximum = maxf(maximum, actual.distance_to(controls[part].global_transform * point))
					floor_y = minf(floor_y, actual.y)
			floor_error = maxf(floor_error, absf(floor_y))
	_expect(maximum < 0.00001, "imported sampler matches native clips across 256 off-grid phases")
	_expect(floor_error < 0.002, "actual imported gait remains at accepted feet")
	var changed: Animation = player.get_animation("walk").duplicate(true) as Animation
	changed.track_set_path(0, NodePath("../../"))
	var library: AnimationLibrary = player.get_animation_library(&"").duplicate(true) as AnimationLibrary
	library.remove_animation(&"walk")
	library.add_animation(&"walk", changed)
	player.remove_animation_library(&"")
	player.add_animation_library(&"", library)
	var rejected: SpliceCharacter = SpliceCharacter.new()
	_expect(not rejected._bind(native), "actual outside-subtree animation target is rejected")
	rejected.free()
	native.free()
	view.free()
	var saved: PackedScene = SpliceCharacter._packed[SpliceCharacter.SOURCE]
	for mode: String in ["missing_surface", "null_mesh", "missing_closure"]:
		var incomplete: Node3D = saved.instantiate() as Node3D
		var target: MeshInstance3D = incomplete.find_child("OriginalEdgeClosure_0_0" if mode == "missing_closure" else "left_forearm_surface", true, false) as MeshInstance3D
		if mode == "null_mesh":
			target.mesh = null
		else:
			target.get_parent().remove_child(target)
			target.free()
		var packed: PackedScene = PackedScene.new()
		_expect(packed.pack(incomplete) == OK, "actual incomplete imported resource packs: " + mode)
		incomplete.free()
		SpliceCharacter._packed[SpliceCharacter.SOURCE] = packed
		var invalid: SpliceCharacter = SpliceCharacter.new()
		_expect(not invalid.configure() and invalid.source_body == null and invalid.get_child_count() == 0, "incomplete packed source leaves no partial figure: " + mode)
		invalid.free()
		var restored: CivilianFigure = CivilianFigure.new()
		root.add_child(restored)
		restored.configure("splice", Color.WHITE)
		_expect(restored.rigid == null and restored.skin == null and restored.strip != null and restored.get_child_count() == 1, "incomplete packed source restores one strip: " + mode)
		_expect(restored.strip.texture == load(PlayerBody.strip_path(PlayerBody.SYNTHETIC)), "incomplete source fallback retains synthetic identity: " + mode)
		restored.free()
	SpliceCharacter._packed[SpliceCharacter.SOURCE] = null
	var fallback: CivilianFigure = CivilianFigure.new()
	root.add_child(fallback)
	fallback.configure("splice", Color.WHITE)
	_expect(fallback.rigid == null and fallback.skin == null and fallback.strip != null, "unavailable selected model restores one strip")
	_expect(fallback.strip.texture == load(PlayerBody.strip_path(PlayerBody.SYNTHETIC)), "missing named source keeps synthetic identity")
	fallback.free()
	SpliceCharacter._packed[SpliceCharacter.SOURCE] = saved
	var person: CivilianFigure = CivilianFigure.new()
	root.add_child(person)
	person.configure("splice", Color.WHITE)
	person.place_feet(Vector3(4, 0, 8))
	person._process(0.05)
	_expect(person.position == Vector3(4, 0, 8) and person._moving_age >= 0.15, "first accepted placement remains calm")
	person.place_feet(Vector3(4.2, 0, 8))
	person._process(0.05)
	_expect(person._walked > 0.19 and person._moving_age < 0.15 and is_equal_approx(person.rotation.y, PI / 2.0), "accepted route travel drives gait and facing")
	person._process(0.2)
	_expect(person._moving_age >= 0.15, "stopped route returns to calm")
	person.place_feet(Vector3(-10, 1, -20))
	person._process(0.05)
	_expect(person._walked == 0.0 and person._moving_age >= 0.15 and person.position == Vector3(-10, 1, -20), "teleport resets gait without lifting accepted feet")
	person.free()
	print("test_splice_character: actual imported maximum_geometry_difference_m=", maximum, " maximum_floor_error_m=", floor_error)
	_finish()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	for failure: String in _failures:
		push_error("test_splice_character: " + failure)
	if _failures.is_empty():
		print("test_splice_character: PASS imported clips, source faces, feet, travel, fallback and rejected target")
	quit(0 if _failures.is_empty() else 1)
