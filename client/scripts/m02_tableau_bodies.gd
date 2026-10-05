class_name M02TableauBodies
extends RefCounted

## Static ward figures, never damageable pawns or extra world cover.
const PARTS: Array[Array] = [
	["Torso", Vector3(0, 1.2, 0), Vector3(0.62, 0.78, 0.29), 0],
	["ChestPatch", Vector3(0.11, 1.38, 0.164), Vector3(0.22, 0.16, 0.035), 2],
	["Neck", Vector3(0, 1.69, 0), Vector3(0.2, 0.16, 0.19), 1],
	["Head", Vector3(0, 1.9, 0), Vector3(0.36, 0.32, 0.32), 0],
	["LeftLeg", Vector3(-0.18, 0.38, 0), Vector3(0.21, 0.68, 0.22), 1],
	["LeftFoot", Vector3(-0.18, 0.09, 0.1), Vector3(0.23, 0.13, 0.38), 0],
	["LeftForearm", Vector3(-0.42, 1.12, 0), Vector3(0.19, 0.66, 0.22), 1],
	["LeftHand", Vector3(-0.42, 0.77, 0.01), Vector3(0.13, 0.13, 0.15), 1],
	["RightLeg", Vector3(0.18, 0.38, 0), Vector3(0.21, 0.68, 0.22), 1],
	["RightFoot", Vector3(0.18, 0.09, 0.1), Vector3(0.23, 0.13, 0.38), 0],
	["RightForearm", Vector3(0.42, 1.12, 0), Vector3(0.19, 0.66, 0.22), 0],
	["RightHand", Vector3(0.42, 0.77, 0.01), Vector3(0.13, 0.13, 0.15), 1],
]

static func layout(info: Dictionary) -> Dictionary:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != 1002 \
		or info.get("map_name") != "Persons Unknown: ward graybox" or info.get("m02_objectives") == null:
		return {}
	var hosts: Array[Dictionary] = []
	for solid: Dictionary in info["solids"]:
		if solid.min_x == 8 and solid.max_x == 9 and solid.get("bottom", 0.0) == 0 \
			and solid.get("top", 0.0) == 2.6 and solid.min_z == -13 and solid.max_z == -9:
			hosts.append(solid)
	if hosts.size() != 1:
		return {}
	var host: Dictionary = hosts[0]
	return {"first": Vector3(host.min_x - 0.45, 0, host.max_z - 1.0),
		"bay": Vector3(host.min_x + 0.35, 0, host.min_z - 3.0),
		"notary": Vector3(host.min_x + 2.4, 4.35, host.min_z - 8.3)}

static func opening(phase: String, started: int, tick: int) -> float:
	if phase in ["following", "firing", "departed"]:
		return 1.0
	if phase != "releasing" or started < 0 or tick < 0:
		return 0.0
	return clampf((maxi(0, tick - started) - 70.0) / 22.0, 0.0, 1.0)

static func second_boxes(bound: Dictionary, open: float) -> Array[AABB]:
	var result: Array[AABB] = []
	if bound.is_empty() or not is_finite(open):
		return result
	var local_x: float = -0.12 + clampf(open, 0.0, 1.0) * 0.12
	var bay: Vector3 = bound["bay"]
	for part: Array in PARTS:
		var position: Vector3 = part[1]
		var size: Vector3 = part[2]
		var world: Vector3 = bay + Vector3(-position.z + 0.21, position.y, position.x + local_x)
		var rotated_size: Vector3 = Vector3(size.z, size.y, size.x)
		result.append(AABB(world - rotated_size * 0.5, rotated_size))
	return result

static func figure(shell: StandardMaterial3D, joints: StandardMaterial3D, patch: StandardMaterial3D) -> Node3D:
	var figure_node: Node3D = Node3D.new()
	figure_node.name = "SecondCaptive"
	var finishes: Array[StandardMaterial3D] = [shell, joints, patch]
	for part: Array in PARTS:
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = part[0]
		instance.position = part[1]
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = part[2]
		instance.mesh = mesh
		instance.material_override = finishes[part[3]]
		figure_node.add_child(instance)
	return figure_node
