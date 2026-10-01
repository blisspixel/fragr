extends SceneTree

var _failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("test_town_backdrop: " + message)

func _run() -> void:
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	root.add_child(backdrop)
	backdrop.build(1004, 40.0, "low_water")
	ArenaSky.mark_world(backdrop)
	await process_frame
	_check(backdrop.get_child_count() == 20, "town has bounded rows of homes")
	var meshes: Array[Node] = backdrop.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() > 100, "upper windows and household details exist")
	for item: Node in meshes:
		var node: MeshInstance3D = item as MeshInstance3D
		var bounds: AABB = node.mesh.get_aabb()
		var world_bounds: AABB = node.global_transform * bounds
		var far: Vector3 = world_bounds.end
		_check(world_bounds.position.x >= 40.5 or far.x <= -40.5
			or world_bounds.position.z >= 40.5 or far.z <= -40.5,
			"scenery remains completely outside playable bounds")
		_check(node.layers == 2, "town uses authored world lighting")
		var material: StandardMaterial3D = node.material_override as StandardMaterial3D
		_check(material != null and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
			"town preserves nearest surfaces")
	_check(backdrop.find_children("*", "CollisionObject3D", true, false).is_empty(), "town has no cosmetic collision")
	_check(backdrop.find_children("*", "Label3D", true, false).is_empty(), "town omits arena signs")
	var town: ShaderMaterial = ArenaMaterials.authored("enamel", "low_water") as ShaderMaterial
	var ordinary: ShaderMaterial = ArenaMaterials.authored("enamel") as ShaderMaterial
	_check(town.get_shader_parameter("surface_color") != ordinary.get_shader_parameter("surface_color"),
		"town treatment does not mutate ordinary mission materials")
	backdrop.free()
	var legacy: ArenaBackdrop = ArenaBackdrop.new()
	root.add_child(legacy)
	legacy.build(1, 40.0)
	_check(legacy.find_children("*", "Label3D", true, false).size() == 4, "arcade retains its signs")
	legacy.free()
	if not _failed:
		print("test_town_backdrop: PASS")
	quit(1 if _failed else 0)
