extends SceneTree

const Source = preload("res://art/models/sweeper_skinned_source.gd")
const ClerkSource = preload("res://art/models/clerk_source.gd")
const SWEEPER_SOURCES: Array[String] = [Source.SKIN_SOURCE, Source.SKIN_SOURCE + ".import",
	"res://art/models/sweeper_skinned_source.gd", "res://art/models/clerk_source.gd",
	"res://art/models/sweeper_source.gd", "res://art/characters/geometry.gd",
	"res://scripts/model_geometry.gd", "res://scripts/enemy_animation.gd",
	"res://art/models/normal_bake.gdshader", "res://assets/models/finishes/metal.png",
	"res://assets/models/finishes/enamel.png", "res://assets/models/finishes/wood.png"]
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	var source: RefCounted = Source.new()
	var poses: Array[Node3D] = []
	for action: String in ["idle", "walk", "raise", "fire", "recover", "hit", "death"]:
		for progress: float in [0.0, 0.5, 1.0]:
			var model: Node3D = source.build_pose(action, progress)
			root.add_child(model)
			poses.append(model)
			var body: Node3D = model.get_node("Sweeper")
			var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
			_check(skeleton.get_bone_count() == 24, "retained reviewed bot skin")
			var rifle: Node3D = body.get_node("IssuedRifle")
			for side: String in ["Right", "Left"]:
				var palm: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin)
				var grip: Node3D = rifle.get_node(NodePath(side + "Grip"))
				_check(palm.distance_to(grip.global_position) < 0.012,
					"both real posed hands follow the same rifle anchors: " + action + " " + side)
			_check(model.find_children("*", "CollisionObject3D", true, false).is_empty(),
				"source has no gameplay collision")
	var idle: Node3D = poses[0]
	var walk_a: Node3D = poses[3]
	var walk_b: Node3D = poses[4]
	_check(_bone(walk_a, "LeftFoot").distance_to(_bone(walk_b, "LeftFoot")) > 0.1,
		"real walk changes feet")
	_check(absf(_bone(walk_a, "Hips").x - _bone(walk_b, "Hips").x) < 0.001
		and absf(_bone(walk_a, "Hips").z - _bone(walk_b, "Hips").z) < 0.001,
		"sampled walk removes lateral root travel")
	_check(_bone(poses[8], "RightHand").y > _bone(idle, "RightHand").y + 0.15,
		"windup actually raises the held rifle and hand")
	_check(_bone(poses[14], "RightHand").distance_to(_bone(idle, "RightHand")) < 0.001,
		"full recovery returns to the carried grip")
	_check(not _bone(poses[15], "Head").is_equal_approx(_bone(idle, "Head")),
		"first hit cell physically reacts")
	var ready: Node3D = source.build_pose("raise", 1.0, true)
	var strike: Node3D = source.build_pose("fire", 0.0, true)
	root.add_child(ready)
	root.add_child(strike)
	poses.append(ready)
	poses.append(strike)
	_check(ready.find_children("IssuedRifle", "Node3D", true, false).is_empty()
		and strike.find_children("IssuedRifle", "Node3D", true, false).is_empty(),
		"exhausted melee has no gun")
	_check(_bone(strike, "RightHand").z > _bone(ready, "RightHand").z + 0.2,
		"melee strikes forward rather than recoiling like a firearm")
	var corpse: Node3D = poses[20].get_node("Sweeper")
	_check(is_equal_approx(corpse.rotation.x, -PI * 0.5) and is_equal_approx(corpse.position.y, 0.2),
		"terminal corpse is laid down with fixed floor clearance")
	var gun: Node3D = corpse.get_node("IssuedRifle")
	_check(absf(gun.global_basis.z.dot(Vector3.UP)) < 0.001,
		"terminal rifle lies across the corpse instead of pointing up")
	var corpse_bounds: AABB = AABB()
	# Locate the actual weighted mesh rather than testing only its root transform.
	for node: Node in corpse.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.skin != null:
			corpse_bounds = _skin_bounds(mesh)
	_check(corpse_bounds.size.x > 0.6 and corpse_bounds.size.z > 1.5
		and corpse_bounds.position.y > -0.025 and corpse_bounds.end.y < 0.65,
		"actual posed corpse vertices settle above the floor with a low silhouette")
	var albedo: Image = (load("res://assets/characters/union/sweeper.png") as Texture2D).get_image()
	var normals: Image = (load("res://assets/characters/union/sweeper_normals.png") as Texture2D).get_image()
	_check(albedo.get_size() == normals.get_size() and not normals.has_mipmaps(),
		"paired Sweeper normals retain the fixed nearest pixel layout")
	var mismatches: int = 0
	for y: int in range(0, albedo.get_height(), 3):
		for x: int in range(0, albedo.get_width(), 3):
			if (albedo.get_pixel(x,y).a > 0.5) != (normals.get_pixel(x,y).a > 0.5):
				mismatches += 1
	_check(mismatches == 0, "paired silhouettes align across all directions and phases")
	var clerk: Node3D = ClerkSource.new().build_pose("idle",0.0)
	root.add_child(clerk)
	_check(clerk.has_node("Clerk") and not clerk.has_node("Sweeper"),
		"path-keyed shared pose cache keeps Clerk and Sweeper identities separate")
	clerk.free()
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/union/manifest.json"))
	if not receipt is Dictionary or not receipt.get("sources") is Dictionary \
		or not receipt.get("rendered_kinds") is Array or not receipt.get("retained_kinds") is Array \
		or not receipt.get("entries") is Array:
		_check(false, "standing receipt describes current and retained roles")
	else:
		_check(receipt["sources"].get(Source.SKIN_SOURCE, "") == FileAccess.get_sha256(Source.SKIN_SOURCE),
			"live selected skin is included in standing atlas source freshness")
		_check(_sweeper_role_has_proof(receipt),
			"receipt gives Sweeper exactly one rendered or source-bound retained role")
		var unassigned: Dictionary = receipt.duplicate(true)
		unassigned["rendered_kinds"].erase("sweeper")
		unassigned["retained_kinds"].erase("sweeper")
		_check(not _sweeper_role_has_proof(unassigned), "receipt refuses an unassigned Sweeper")
		var duplicated: Dictionary = unassigned.duplicate(true)
		duplicated["rendered_kinds"].append("sweeper")
		duplicated["retained_kinds"].append("sweeper")
		_check(not _sweeper_role_has_proof(duplicated), "receipt refuses contradictory Sweeper roles")
		var retained: Dictionary = unassigned.duplicate(true)
		retained["retained_kinds"].append("sweeper")
		var sources: Dictionary = {}
		for path: String in SWEEPER_SOURCES:
			sources[path] = FileAccess.get_sha256(path)
		retained["retained_receipt"] = {"sources": sources}
		_check(_sweeper_role_has_proof(retained), "partial bake retains unchanged Sweeper geometry and atlas outputs")
		for path: String in SWEEPER_SOURCES:
			var stale: Dictionary = retained.duplicate(true)
			stale["retained_receipt"]["sources"][path] = "0".repeat(64)
			_check(not _sweeper_role_has_proof(stale), "retained Sweeper refuses stale dependency " + path)
		var stale_atlas: Dictionary = retained.duplicate(true)
		for entry: Dictionary in stale_atlas["entries"]:
			if entry["file"] == "sweeper_normals.png":
				entry["sha256"] = "0".repeat(64)
		_check(not _sweeper_role_has_proof(stale_atlas), "retained Sweeper refuses stale paired output")
		var rendered: Dictionary = unassigned.duplicate(true)
		rendered["rendered_kinds"].append("sweeper")
		rendered.erase("retained_receipt")
		_check(_sweeper_role_has_proof(rendered), "a newly rendered Sweeper needs no retained source history")
		retained.erase("retained_receipt")
		_check(not _sweeper_role_has_proof(retained), "retained Sweeper requires its historical skin receipt")
		if not receipt["retained_kinds"].is_empty():
			var prior: Variant = receipt.get("retained_receipt")
			_check(prior is Dictionary and prior.get("sources") is Dictionary
				and prior["sources"].has("res://art/models/clerk_source.gd"),
				"retained cast keeps its historical source receipt")
	for model: Node3D in poses:
		model.free()
	await process_frame
	if _failures == 0:
		print("test_sweeper_skin: PASS skin, two-hand rifle grip, gait, root registration, recoil, recovery, melee and settled death")
	quit(0 if _failures == 0 else 1)

func _sweeper_role_has_proof(receipt: Dictionary) -> bool:
	var rendered: bool = receipt["rendered_kinds"].has("sweeper")
	var retained: bool = receipt["retained_kinds"].has("sweeper")
	if rendered == retained:
		return false
	var found: Dictionary = {}
	for entry: Dictionary in receipt["entries"]:
		var file: String = entry.get("file", "")
		if file not in ["sweeper.png", "sweeper_normals.png"]:
			continue
		if found.has(file) or entry.get("sha256", "") != FileAccess.get_sha256("res://assets/characters/union/" + file):
			return false
		found[file] = true
	if found.size() != 2:
		return false
	if retained:
		var prior: Variant = receipt.get("retained_receipt")
		if not prior is Dictionary or not prior.get("sources") is Dictionary:
			return false
		for path: String in SWEEPER_SOURCES:
			if prior["sources"].get(path, "") != FileAccess.get_sha256(path):
				return false
	return true

func _bone(model: Node3D, label: String) -> Vector3:
	var skeleton: Skeleton3D = model.get_node("Sweeper/Armature/Skeleton3D") as Skeleton3D
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(label)).origin)

func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("test_sweeper_skin: " + message)

func _skin_bounds(node: Node3D) -> AABB:
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance == null or instance.skin == null:
		return AABB()
	var skeleton: Skeleton3D = instance.get_node(instance.skeleton) as Skeleton3D
	var transforms: Array[Transform3D] = []
	for bind: int in range(instance.skin.get_bind_count()):
		var bone: int = instance.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(instance.skin.get_bind_name(bind))
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
	var bounds: AABB = AABB()
	var started: bool = false
	for surface: int in range(instance.mesh.get_surface_count()):
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences: int = int(bones.size() / vertices.size())
		for vertex: int in range(vertices.size()):
			var point: Vector3 = Vector3.ZERO
			for influence: int in range(influences):
				var slot: int = vertex * influences + influence
				point += (transforms[bones[slot]] * vertices[vertex]) * weights[slot]
			bounds = bounds.expand(point) if started else AABB(point, Vector3.ZERO)
			started = true
	return bounds
