extends "res://scripts/qa_tour.gd"

var _body_samples: Array[Dictionary] = []
var _saw_releasing_body: bool = false

func _companion_observation() -> Dictionary:
	var observed: Dictionary = super._companion_observation()
	if observed.is_empty():
		return observed
	var manager: Node = _game_manager()
	var actor: Dictionary = {}
	for candidate: Dictionary in manager.latest_snapshot.get("players", []):
		if ActorState.is_companion(candidate):
			actor = candidate
			break
	var pawn: Node3D = manager.players.get(actor.get("id", "")) as Node3D
	var view: LatchView = pawn.get("latch_view") as LatchView if is_instance_valid(pawn) else null
	var source: Node3D = view.get_node_or_null("LatchSource") as Node3D if is_instance_valid(view) else null
	var skinned: int = 0
	var visible_meshes: int = 0
	var normals: int = 0
	var sprites: int = 0
	if is_instance_valid(source):
		for node: Node in source.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.skin != null:
				skinned += 1
			if mesh.is_visible_in_tree():
				visible_meshes += 1
			var material: Material = mesh.material_override
			if material is ShaderMaterial and material.get_shader_parameter("normal_enabled") == true:
				normals += 1
			sprites = source.find_children("*", "Sprite3D", true, false).size()
	var phase: String = observed["phase"]
	var actual: Dictionary = {"tick": observed["tick"], "phase": phase,
		"snapshot_position": observed["position"], "pawn_visible": observed["pawn_visible"],
		"ward_visible": observed["ward_visible"], "presenter": "LatchView" if view != null else "missing",
		"source_path": LatchSource.LATCH_SOURCE, "source_sha256": FileAccess.get_sha256(LatchSource.LATCH_SOURCE),
		"skinned_meshes": skinned, "visible_source_meshes": visible_meshes,
		"normal_materials": normals, "source_sprites": sprites,
		"render_position": [pawn.global_position.x, pawn.global_position.y, pawn.global_position.z] if pawn != null else [],
		"source_visible": source != null and source.is_visible_in_tree()}
	if _body_samples.size() < 80:
		_body_samples.append(actual)
	if phase == "releasing":
		_saw_releasing_body = true
		if not observed["pawn_visible"] or observed["ward_visible"] or skinned <= 0 or visible_meshes <= 0 or sprites != 0:
			push_error("m02_shot_occlusion: actual releasing body presentation disagrees with snapshot: " + JSON.stringify(actual))
			_failed = true
	return observed

func _retire_scene() -> void:
	var file: FileAccess = FileAccess.open(_out_dir.path_join("companion-body-source.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"samples": _body_samples, "releasing_observed": _saw_releasing_body,
			"scope": "ordinary ward combat and release; no independent rear-target alignment or full mission clear"}, "\t") + "\n")
		file.close()
	if not _saw_releasing_body:
		push_error("m02_shot_occlusion: no real releasing snapshot body was observed")
		_failed = true
	await super._retire_scene()
