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

var _built_info: Dictionary = {}
var _half_extent: float = 0.0
var _materials: Array[Material] = []
var _solid_views: Array[MeshInstance3D] = []

func _ready() -> void:
	name = "ArenaCover"

## Rebuild from a MapInfo payload. Cheap to call again; it only rebuilds when
## the map actually changed, because the server resends on rotation.
func apply_map_info(info: Dictionary) -> void:
	var problem: String = MapGeometry.validation_error(info)
	if problem != "":
		push_warning("arena_cover: " + problem)
		return
	var map_id: int = int(info.get("map_id", -1))
	_hide_scene_props()
	if info == _built_info:
		return
	if is_inside_tree():
		# Finish render layers before any new geometry can pair with the
		# actor-only camera light. Changing a paired mesh's layer leaves stale
		# light membership in the pinned renderer, exposed on map retirement.
		var prepared := ArenaCover.new()
		prepared.apply_map_info(info)
		if prepared._built_info != info:
			prepared.free()
			push_error("arena_cover: detached map preparation failed")
			return
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		_built_info = prepared._built_info
		_half_extent = prepared._half_extent
		_materials = prepared._materials
		_solid_views = prepared._solid_views
		for child: Node in prepared.get_children():
			prepared.remove_child(child)
			add_child(child)
		prepared.free()
		_hide_scene_props()
		return
	_built_info = info.duplicate(true)
	_half_extent = float(info.get("half_extent", 50.0))
	_materials.clear()
	_solid_views.clear()
	for kind: int in range(4):
		_materials.append(ArenaMaterials.make(map_id, kind))
	var presentation: Dictionary = info.get("presentation") if info.get("presentation") is Dictionary else {}
	var venue: String = venue_for(info)
	if venue.is_empty() and map_id in [1001, 1002, 1003]:
		venue = "earth_yard" if map_id == 1003 else "earth_union"
	var authored_materials: Dictionary[String, Material] = {}
	if map_id == 7:
		venue = "holdfast_atoll"
	if not presentation.is_empty():
		for surface: String in MapGeometry.SURFACES:
			authored_materials[surface] = ArenaMaterials.authored(surface, venue)
			# Planned Works is Low Water at night: the daylight plaster repairs
			# read as pale ghosts under the moon, so its walls keep plain paint.
			if info.get("m19") is Dictionary and authored_materials[surface] is ShaderMaterial:
				(authored_materials[surface] as ShaderMaterial).set_shader_parameter("detail_enabled", false)
		_materials[0] = ArenaMaterials.ground(authored_materials[presentation["ground"]], presentation["ground"], venue)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_shell(_half_extent, 3.2 if venue == "holdfast_atoll" else BOUNDARY_HEIGHT)
	# The lunar map supplies its own opaque pressure perimeter and glass views.
	# The generic decorative arena wall would hide those registered windows.
	# Planned Works ends at the river railing; the presenter owns what lies past it.
	var planned_works: bool = info.get("m19") is Dictionary
	if planned_works or venue in ["moon_port", "moon_town", "common_carrier", "right_of_search", "holdfast_atoll", "launch_works", "mars_habitat", "mars_foundry"]:
		for side: int in range(4):
			var boundary: Node3D = get_node_or_null("MapBoundary%d" % side) as Node3D
			if boundary != null:
				boundary.visible = false
	if venue in ["common_carrier", "right_of_search"]:
		# The authored sealed hull supplies every usable floor. The generic
		# outside arena plane would turn the command window into a courtyard.
		get_node("MapFloor").visible = false
	var solids: Array = info.get("solids", [])
	var walker_solids: Array[int] = []
	if info.get("walker") is Dictionary:
		for index: Variant in info["walker"]["solids"]:
			walker_solids.append(int(index))
	elif info.get("m14") is Dictionary and info["m14"].get("fallen") == true:
		for index: Variant in info["m14"]["walker_solids"]:
			walker_solids.append(int(index))
	for index: int in range(solids.size()):
		var material: Material = null
		if not presentation.is_empty():
			material = authored_materials[presentation["solids"][index]]
		if venue == "holdfast_atoll":
			material = HoldfastScenery.material_for(solids[index], index)
		_add_solid(solids[index], material)
		if index in walker_solids:
			_solid_views.back().visible = false
	if venue == "holdfast_atoll":
		var coast: HoldfastScenery = HoldfastScenery.new()
		add_child(coast)
		coast.build(info)
		var ocean: IslandWater = IslandWater.new()
		add_child(ocean)
		ocean.build(info)
	if venue == "common_carrier":
		ShipFurnishings.build(self, info, _solid_views)
	var marked_terminal: int = -1
	var terminal_key: String = "WORLD_LATCH_RECORD"
	var mission: Variant = info.get("mission")
	if mission is Dictionary and mission.get("record") is Dictionary:
		var decoration: Variant = mission["record"].get("decoration")
		if decoration is int or decoration is float:
			marked_terminal = int(decoration)
	if info.get("m14") is Dictionary and M14MissionState.map_error(info).is_empty():
		marked_terminal = int(info["m14"]["departure"]["decoration"])
		terminal_key = "WORLD_M14_DEPARTURE_CONSOLE"
	ArenaDecoration.build(self, solids, presentation.get("decorations", []), ArenaSky.preset_for(str(info.get("map_name", ""))), marked_terminal, terminal_key)
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.build(map_id, _half_extent, "planned_works" if planned_works else venue)
	add_child(backdrop)
	var water: ArenaWater = ArenaWater.new()
	water.build(info)
	if water.patches.is_empty():
		water.free()
	else:
		add_child(water)
	ArenaSky.mark_world(self)
	_hide_scene_props()

static func venue_for(info: Dictionary) -> String:
	match str(info.get("map_name", "")).strip_edges().to_lower():
		"low water", "planned works": return "low_water"
		"launch authority", "launch authority (development)", "continuance walker (development)": return "launch_works"
		"terms of cooperation (development)": return "mars_habitat"
		"terms of cooperation": return "mars_habitat"
		"the weight of permission (development)": return "mars_foundry"
		"the weight of permission": return "mars_foundry"
	if info.get("m11") is Dictionary:
		return "right_of_search"
	if info.get("m10") is Dictionary:
		return "common_carrier"
	if info.get("m06") is Dictionary or info.get("m08") is Dictionary:
		return "moon_port"
	if info.get("m07") is Dictionary:
		return "moon_town"
	if info.get("m04") is Dictionary or info.get("m05") is Dictionary:
		return "low_water"
	return ""

## Half width of the playable square the server last described, so the camera
## and the far-plane work can size themselves to the map rather than to a
## constant that was right for one of them.
func half_extent() -> float:
	return _half_extent

## The floor and the four boundary walls, sized from the map. Without this a
## two hundred and eighty metre map is drawn inside whatever square the scene
## file happened to have in it.
func _build_shell(half: float, boundary_height: float = BOUNDARY_HEIGHT) -> void:
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
			mesh.size = Vector3(half * 2.0, boundary_height, 1.0)
		else:
			mesh.size = Vector3(1.0, boundary_height, half * 2.0)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "MapBoundary%d" % side
		node.mesh = mesh
		if along_x:
			node.position = Vector3(0.0, boundary_height * 0.5, sign * half)
		else:
			node.position = Vector3(sign * half, boundary_height * 0.5, 0.0)
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

func _add_solid(solid: Dictionary, material: Material = null) -> void:
	var min_x: float = float(solid.get("min_x", 0.0))
	var max_x: float = float(solid.get("max_x", 0.0))
	var min_z: float = float(solid.get("min_z", 0.0))
	var max_z: float = float(solid.get("max_z", 0.0))
	var size_x: float = absf(max_x - min_x)
	var size_z: float = absf(max_z - min_z)
	if size_x <= 0.0 or size_z <= 0.0:
		return

	# Draw the same finite volume used for collision and shots, including space
	# beneath raised floors. Legacy boxes have a bottom at ground level.
	var bottom: float = float(solid.get("bottom", MoveStep.GROUND_Y))
	var top: float = float(solid.get("top", MoveStep.WALL_TOP))
	var height: float = top - bottom
	if height <= 0.0:
		return

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(size_x, height, size_z)

	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Solid_%d" % _solid_views.size()
	_solid_views.append(node)
	node.mesh = mesh
	node.position = Vector3((min_x + max_x) * 0.5, bottom + height * 0.5, (min_z + max_z) * 0.5)
	node.material_override = material if material != null else _materials[3 if top <= LOW_TOP else 2]
	if material is ShaderMaterial and height >= 2.6 and minf(size_x, size_z) <= 1.5 and maxf(size_x, size_z) >= 2.4:
		node.mesh = ArchitectureMesh.wall(Vector3(size_x, height, size_z))
	elif material is ShaderMaterial and bottom >= 2.5 and height >= 0.25 and height <= 1.0 and minf(size_x, size_z) >= 4.0:
		node.mesh = ArchitectureMesh.ceiling(Vector3(size_x, height, size_z))
	add_child(node)

## Only the registered tram solid and its surface panels move. The baseline
## MapInfo stays immutable so prepared freight worlds retain their identity.
func apply_m05(state: Dictionary) -> void:
	var geometry: Dictionary = MissionState.geometry_for(_built_info)
	if geometry.get("id") != MissionState.M05_ID:
		return
	var index: int = int(geometry["m05"]["tram"]["solid"])
	if index >= _solid_views.size():
		return
	var valid: bool = state.get("id") == MissionState.M05_ID and state.get("m05") is Dictionary
	var node: MeshInstance3D = _solid_views[index]
	node.visible = valid
	var delta: float = float(state["m05"]["tram"]["feet"][2]) - float(geometry["m05"]["tram"]["start"][2]) if valid else 0.0
	var solid: Dictionary = geometry["tram_solid"]
	node.position.z = (float(solid["min_z"]) + float(solid["max_z"])) * 0.5 + delta
	for child: Node in get_children():
		if child.has_meta("host_solid") and int(child.get_meta("host_solid")) == index:
			(child as Node3D).visible = valid
			(child as Node3D).position = child.get_meta("baseline_position") + Vector3(0.0, 0.0, delta)

func apply_m13(state: Dictionary) -> void:
	var geometry: Dictionary = MissionState.geometry_for(_built_info)
	if geometry.get("id") != MissionState.M13_ID or state.get("id") != MissionState.M13_ID or not state.get("m13") is Dictionary:
		return
	var facts: Dictionary = state["m13"]
	if not M13MissionState.validation_error({"tick":facts.get("lift",{}).get("tick"),"state":state},geometry).is_empty():
		return
	var index: int = int(geometry["m13"]["deck"])
	if index >= _solid_views.size():
		return
	var delta: float = float(facts["lift"]["top"])-float(geometry["m13"]["parked_top"])
	var solid: Dictionary = geometry["solids"][index]
	_solid_views[index].position.y = (float(solid["bottom"])+float(solid["top"]))*0.5+delta
	for child: Node in get_children():
		if child.has_meta("host_solid") and int(child.get_meta("host_solid")) == index:
			(child as Node3D).position = child.get_meta("baseline_position")+Vector3(0.0,delta,0.0)
