class_name ShipFurnishings
extends RefCounted

## Select fixed source art only when the accepted physical host matches it.
## These bounds validate presentation; movement and shots use received solids.
const WORKBENCH_SOURCE: String = "res://assets/models/repair_workbench.glb"
const EPSILON: float = 0.0001
const WORKTOP_SIZE: Vector3 = Vector3(1.76, 0.09, 0.85)

static func _parts() -> Array[AABB]:
	var parts: Array[AABB] = [
		AABB(Vector3(-0.88, 0.81, -0.52), Vector3(1.76, 0.09, 0.85)),
		AABB(Vector3(-0.85, 0.14, -0.35), Vector3(0.46, 0.68, 0.65)),
		AABB(Vector3(0.39, 0.14, -0.35), Vector3(0.46, 0.68, 0.65)),
		AABB(Vector3(-0.76, 0.89, -0.514), Vector3(1.52, 0.22, 0.064))]
	for point: Vector2 in [Vector2(.8451,.3764),Vector2(.8402,-.2610),
		Vector2(.3753,.3041),Vector2(.3861,-.2572),Vector2(-.3908,-.2557),
		Vector2(-.3773,.3263),Vector2(-.8394,-.2553),Vector2(-.8402,.3815)]:
		parts.append(AABB(Vector3(-point.x - .04, 0.0, -point.y - .04), Vector3(.08, .15, .08)))
	return parts

static func _bounds(solid: Dictionary) -> AABB:
	var position: Vector3 = Vector3(float(solid["min_x"]),float(solid.get("bottom", MoveStep.GROUND_Y)),float(solid["min_z"]))
	return AABB(position, Vector3(float(solid["max_x"]),float(solid.get("top", MoveStep.WALL_TOP)),float(solid["max_z"])) - position)

static func _same_bounds(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) < EPSILON and a.size.distance_to(b.size) < EPSILON

static func matched_host(info: Dictionary) -> Dictionary:
	if not info.get("m10") is Dictionary or not MapGeometry.validation_error(info).is_empty() or not MissionState.map_error(info).is_empty():
		return {}
	var solids: Array = info["solids"]
	var candidates: Array[Dictionary] = []
	for index: int in range(solids.size()):
		var bounds: AABB = _bounds(solids[index])
		if bounds.size.distance_to(WORKTOP_SIZE) >= EPSILON:
			continue
		var origin: Vector3 = bounds.position + Vector3(.88,-.81,.52)
		var matched: Array[int] = []
		for local: AABB in _parts():
			var expected: AABB = AABB(local.position + origin, local.size)
			var matching: Array[int] = []
			for other: int in range(solids.size()):
				if _same_bounds(_bounds(solids[other]),expected):
					matching.append(other)
			if matching.size() != 1:
				matched.clear()
				break
			matched.append(matching[0])
		if matched.size() == 12:
			candidates.append({"origin":origin,"indices":matched})
	return candidates[0] if candidates.size() == 1 else {}

static func source_error(scene: Node3D) -> String:
	if scene == null:
		return "missing packaged workbench"
	var bodies: Array[Node] = scene.find_children("*","MeshInstance3D",true,false)
	if bodies.size() != 1:
		return "workbench fixed-body count"
	var body: MeshInstance3D = bodies[0] as MeshInstance3D
	if body.mesh == null or body.mesh.get_surface_count() != 1:
		return "workbench source mesh"
	var material: StandardMaterial3D = body.get_active_material(0) as StandardMaterial3D
	if material == null or material.albedo_texture == null or material.normal_texture == null or material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		return "workbench embedded surface"
	var bounds: AABB = body.mesh.get_aabb()
	if bounds.position.y < -EPSILON or absf(bounds.size.x - 1.815294) > EPSILON or absf(bounds.size.y - 1.135946) > EPSILON or absf(bounds.size.z - 1.039604) > EPSILON:
		return "workbench measured dimensions"
	return ""

static func instantiate_source() -> Node3D:
	var packed: PackedScene = load(WORKBENCH_SOURCE) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D

static func build(parent: Node3D, info: Dictionary, solid_views: Array[MeshInstance3D]) -> Node3D:
	var host: Dictionary = matched_host(info)
	if host.is_empty() or solid_views.size() != info["solids"].size():
		return null
	for index: int in host["indices"]:
		if not is_instance_valid(solid_views[index]) or not solid_views[index].visible:
			return null
	var scene: Node3D = instantiate_source()
	var problem: String = source_error(scene)
	if not problem.is_empty():
		if scene != null:
			scene.free()
		push_warning("ship furnishings: " + problem)
		return null
	scene.name = "RepairWorkbench"
	scene.position = host["origin"]
	scene.rotation.y = PI
	parent.add_child(scene)
	ArenaSky.mark_world(scene)
	for index: int in host["indices"]:
		solid_views[index].visible = false
	return scene
