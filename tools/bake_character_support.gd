extends SceneTree

## Offline weighted support curves keep vertex measurement out of live frames.
const SAMPLES: int = 128
const JsonMembers = preload("res://../tools/tern_glb.gd")
var failed: bool = false

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var only: String = ""
	var prior_body_members: Dictionary = {}
	if not args.is_empty():
		if args.size() != 2 or args[0] != "--only" or not SkinnedCharacter.SOURCES.has(args[1]):
			push_error("bake_character_support: expected optional --only registered body")
			quit(1)
			return
		only = args[1]
	var document: Dictionary = {"schema": 1, "pose_sha256": FileAccess.get_sha256("res://scripts/skinned_character.gd"), "bodies": {}}
	if not only.is_empty():
		var prior_text: String = FileAccess.get_file_as_string(SkinnedCharacter.SUPPORT_PATH)
		var prior: Variant = JSON.parse_string(prior_text)
		if not prior is Dictionary or prior.get("schema") != 1 or not prior.get("bodies") is Dictionary:
			push_error("bake_character_support: partial bake requires existing support document")
			quit(1)
			return
		for kind: String in SkinnedCharacter.SOURCES:
			if kind != only and (not SkinnedCharacter._valid_support(prior.bodies.get(kind)) or prior.bodies[kind].get("source_sha256") != FileAccess.get_sha256(SkinnedCharacter.SOURCES[kind])):
				push_error("bake_character_support: retained body support is missing or belongs to another source")
				quit(1)
				return
		document.bodies = prior.bodies
		prior_body_members = JsonMembers._raw_members(JsonMembers._raw_members(prior_text).get("bodies", ""))
		if prior_body_members.size() != prior.bodies.size():
			push_error("bake_character_support: cannot preserve retained support tokens")
			quit(1)
			return
	for kind: String in SkinnedCharacter.SOURCES:
		if not only.is_empty() and kind != only:
			continue
		var view: SkinnedCharacter = SkinnedCharacter.new()
		root.add_child(view)
		if not view.configure(kind, false):
			push_error("bake_character_support: unavailable source " + kind)
			failed = true
			view.free()
			continue
		var floor_curves: Dictionary = {}
		for action: String in ["idle", "walk", "duck", "duck_walk", "fall"]:
			var curve: Array[float] = []
			var count: int = SAMPLES if action in ["walk", "duck_walk", "fall"] else 1
			for sample: int in range(count + 1):
				var phase: float = float(sample) / count
				view.pose(phase, action in ["walk", "duck_walk"], false, action in ["duck", "duck_walk"], 1.0 if action == "fall" else 0.0)
				if action == "fall":
					view.source_body.rotation.x = -PI * 0.5 * phase
				var bounds: AABB = weighted_bounds(view)
				if bounds.size.y <= 0.0 or not bounds.position.is_finite():
					failed = true
				curve.append(bounds.position.y)
			floor_curves[action] = curve
		document["bodies"][kind] = {"source_sha256": FileAccess.get_sha256(SkinnedCharacter.SOURCES[kind]), "floor": floor_curves}
		view.free()
	if failed:
		quit(1)
		return
	var file: FileAccess = FileAccess.open(SkinnedCharacter.SUPPORT_PATH, FileAccess.WRITE)
	var text: String = JSON.stringify(document, "\t") + "\n"
	if not only.is_empty():
		# Keep previous bodies' exact decimal tokens, not a parse/stringify
		# round trip that can change a retained double by one ULP.
		var members: PackedStringArray = []
		for kind: String in document.bodies:
			members.append(JSON.stringify(kind) + ":" + (prior_body_members[kind] if kind != only else JSON.stringify(document.bodies[kind], "", true, true)))
		text = "{\"schema\":1,\"pose_sha256\":" + JSON.stringify(document.pose_sha256) + ",\"bodies\":{" + ",".join(members) + "}}\n"
	if file == null or not file.store_string(text):
		push_error("bake_character_support: cannot retain support document")
		quit(1)
		return
	file.close()
	print("bake_character_support: PASS %d retained skins, 128-phase weighted support curves" % document.bodies.size())
	quit(0)

static func weighted_bounds(view: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	var local: Transform3D = view.global_transform.affine_inverse()
	for node: Node in view.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var rig: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if rig == null or mesh.skin == null:
			return AABB()
		var transforms: Array[Transform3D] = []
		for bind: int in range(mesh.skin.get_bind_count()):
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = rig.find_bone(mesh.skin.get_bind_name(bind))
			transforms.append(local * rig.global_transform * rig.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = bones.size() / vertices.size()
			for vertex: int in range(vertices.size()):
				var point: Vector3 = Vector3.ZERO
				for influence: int in range(influences):
					var index: int = vertex * influences + influence
					point += (transforms[bones[index]] * vertices[vertex]) * weights[index]
				result = AABB(point, Vector3.ZERO) if first else result.expand(point)
				first = false
	return result
