extends Node3D
class_name ArenaCover

## Builds the arena from the MapInfo the server sends: the floor, the boundary
## walls, and every solid at the height the server says it is.
##
## The cover used to be hand-placed boxes in the scene file, duplicating a list
## of rectangles that the server also held. That is the same class of bug that
## produced the ninety degree facing mismatch and the silently dropped jump
## field: two copies of one shape, and nothing making them agree. When the
## arena doubled, the server's cover moved and the scene's did not, so
## fighters spawned in open ground that still looked like it had walls in it.
##
## Now there is one copy. The server owns the geometry, sends it once on join
## and again when the map changes, and this builds what it is told. What you
## can hide behind, what you can stand on, and what actually blocks a shot
## cannot disagree.

## Height of the boundary wall around the playable square.
const BOUNDARY_HEIGHT: float = 8.0
## A solid at or under this is a step or a kerb rather than a wall, and gets
## the lighter surface so a player can read it as walkable at a glance.
const LOW_TOP: float = 1.6

var _built_for: int = -1
var _half_extent: float = 0.0
var _materials: Array[ShaderMaterial] = []

func _ready() -> void:
	name = "ArenaCover"

## Rebuild from a MapInfo payload. Cheap to call again; it only rebuilds when
## the map actually changed, because the server resends on rotation.
func apply_map_info(info: Dictionary) -> void:
	var map_id: int = int(info.get("map_id", -1))
	_hide_scene_props()
	if map_id == _built_for:
		return
	_built_for = map_id
	_half_extent = float(info.get("half_extent", 50.0))
	_materials.clear()
	for kind: int in range(4):
		_materials.append(ArenaMaterials.make(map_id, kind))
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_shell(_half_extent)
	var solids: Array = info.get("solids", [])
	for entry in solids:
		if typeof(entry) == TYPE_DICTIONARY:
			_add_solid(entry as Dictionary)
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.build(map_id, _half_extent)
	add_child(backdrop)
	_hide_scene_props()

## Half width of the playable square the server last described, so the camera
## and the far-plane work can size themselves to the map rather than to a
## constant that was right for one of them.
func half_extent() -> float:
	return _half_extent

## The floor and the four boundary walls, sized from the map. Without this a
## two hundred and eighty metre map is drawn inside whatever square the scene
## file happened to have in it.
func _build_shell(half: float) -> void:
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(half * 2.0, half * 2.0)
	var floor_node: MeshInstance3D = MeshInstance3D.new()
	floor_node.name = "MapFloor"
	floor_node.mesh = floor_mesh
	floor_node.position = Vector3.ZERO
	floor_node.material_override = _materials[0]
	add_child(floor_node)

	for side in range(4):
		var along_x: bool = side < 2
		var sign: float = -1.0 if side % 2 == 0 else 1.0
		var mesh: BoxMesh = BoxMesh.new()
		if along_x:
			mesh.size = Vector3(half * 2.0, BOUNDARY_HEIGHT, 1.0)
		else:
			mesh.size = Vector3(1.0, BOUNDARY_HEIGHT, half * 2.0)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "MapBoundary%d" % side
		node.mesh = mesh
		if along_x:
			node.position = Vector3(0.0, BOUNDARY_HEIGHT * 0.5, sign * half)
		else:
			node.position = Vector3(sign * half, BOUNDARY_HEIGHT * 0.5, 0.0)
		node.material_override = _materials[1]
		add_child(node)

## The scene files still carry a floor, four walls and some legacy low walls
## from when cover lived in the scene. They are the wrong size for every map
## but one, so the server-built shell replaces them.
func _hide_scene_props() -> void:
	var arena_root: Node = get_parent()
	if arena_root == null:
		return
	var layout: Node = arena_root.get_node_or_null("Layout")
	if layout == null:
		return
	for legacy_name in [
		"Floor",
		"WallNorth",
		"WallSouth",
		"WallEast",
		"WallWest",
		"LowWallNorth",
		"LowWallSouth",
		"LowWallEast",
		"LowWallWest",
		"ZoneCenter", "ZoneNorthEast", "ZoneSouthWest", "ZoneNorthWest", "ZoneSouthEast",
	]:
		var node: Node = layout.get_node_or_null(NodePath(legacy_name))
		if node is Node3D:
			(node as Node3D).visible = false

func _add_solid(solid: Dictionary) -> void:
	var min_x: float = float(solid.get("min_x", 0.0))
	var max_x: float = float(solid.get("max_x", 0.0))
	var min_z: float = float(solid.get("min_z", 0.0))
	var max_z: float = float(solid.get("max_z", 0.0))
	var size_x: float = absf(max_x - min_x)
	var size_z: float = absf(max_z - min_z)
	if size_x <= 0.0 or size_z <= 0.0:
		return

	# The server says how tall it is. A solid runs from the floor to its top,
	# so what is drawn and what a fighter stands on are the same box.
	var height: float = float(solid.get("top", MoveStep.WALL_TOP))
	if height <= 0.0:
		return

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(size_x, height, size_z)

	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.position = Vector3((min_x + max_x) * 0.5, height * 0.5, (min_z + max_z) * 0.5)
	node.material_override = _materials[3 if height <= LOW_TOP else 2]
	add_child(node)
