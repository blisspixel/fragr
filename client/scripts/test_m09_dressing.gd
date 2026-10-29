extends SceneTree

## Passenger Manifest golden-slice dressing: an authored-layout guard keyed on
## solids that never move (never the boarding hatch), a re-sent map with the
## hatch opened keeping one set of rooms, every region dressed, local lamps and
## floods with no red or cyan light, no words and no collision of its own, no
## rail drawn where the server has none; solid views restyled by use with no
## glowing paint and nothing in the Union's black-and-red livery, the ship and
## the passengers' things clear of the reserved faction reads, and a deck floor
## in tiles that keep their own lights. The berth presenter keeps the dressing
## across the hatch's re-sent map and puts the impound notice only on a closed
## hatch.
const ROOMS: Array[String] = ["Loading", "Office", "Stern", "GantryWest", "GantryNorth", "GantryEast", "Gallery", "Cradle", "Shell"]
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m09_dressing: " + message)

static func authored_info() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m09_passenger_manifest.json"))
	if not source is Dictionary:
		return {}
	var solids: Array = []
	var surfaces: Array = []
	for solid: Dictionary in source["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2],
			"bottom": solid["min"][1], "top": solid["max"][1]})
		surfaces.append(solid.get("surface", "concrete"))
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"],
		"half_extent": source["half_extent"], "solids": solids, "m09": {},
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": []}}

static func _reserved(colour: Color) -> bool:
	var black_red: bool = colour.v <= 0.3
	var off_white: bool = colour.v >= 0.8 and colour.s <= 0.15
	var cyan: bool = colour.s > 0.25 and colour.h * 360.0 >= 165.0 and colour.h * 360.0 <= 200.0
	return black_red or off_white or cyan

## The authored map with the boarding hatch lifted to its open position, as
## the server re-sends it when the hatch opens.
static func opened(info: Dictionary) -> Dictionary:
	var moved: Dictionary = info.duplicate(true)
	for solid: Dictionary in moved["solids"]:
		if is_equal_approx(float(solid["min_x"]), -3.0) and is_equal_approx(float(solid["min_z"]), -31.0) and is_equal_approx(float(solid["bottom"]), 12.0):
			solid["bottom"] = 16.0
			solid["top"] = 20.0
	return moved

func _run() -> void:
	var info: Dictionary = authored_info()
	_expect(M09Dressing.berth_layout(info), "the authored berth layout is recognized")
	_expect(not M06Dressing.authored(info) and not M07Dressing.town_layout(info), "the berth never receives the port or town dressing")
	var hatch_open: Dictionary = opened(info)
	_expect(hatch_open["solids"] != info["solids"], "the fixture really moves the hatch")
	_expect(M09Dressing.berth_layout(hatch_open), "the moving hatch is not part of the guard")
	var other: Dictionary = info.duplicate(true)
	other["map_id"] = 1008
	_expect(not M09Dressing.berth_layout(other), "another lunar mission never receives the berth dressing")
	var moved: Dictionary = info.duplicate(true)
	for solid: Dictionary in moved["solids"]:
		if is_equal_approx(float(solid["min_x"]), 16.0) and is_equal_approx(float(solid["min_z"]), -24.0) and is_equal_approx(float(solid["bottom"]), 9.4):
			solid["max_x"] = 38.0
	_expect(not M09Dressing.berth_layout(moved), "a reused id with a moved gallery gets no floating props")
	_expect(not M09Dressing.berth_layout({"map_id": 1009}), "a malformed map is refused")
	for colour: Color in [M09Dressing.HULL, M09Dressing.HULL_DARK, M09Dressing.BONE, M09Dressing.EMBER, M09Dressing.CRADLE] + M09Dressing.BAGS:
		_expect(not _reserved(colour), "ship and passenger colours avoid the reserved faction reads: " + colour.to_html(false))
	var berth: M09Dressing = M09Dressing.new()
	root.add_child(berth)
	berth.configure_map(moved)
	_expect(berth.get_child_count() == 0 and not berth.active(), "unrecognized layouts stay bare")
	berth.configure_map(info)
	for room: String in ROOMS:
		_expect(room in berth.rooms and berth.has_node(room), "room dressed: " + room)
	_expect(berth.lamps >= 24, "practical light and issued floods shape the berth, found %d" % berth.lamps)
	_expect(berth.find_children("BerthFlood*", "SpotLight3D", true, false).size() >= 4, "the Union's cold floods light the landing, the hatch and the hull")
	for light: Node in berth.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
		if lamp is SpotLight3D:
			_expect((lamp as SpotLight3D).spot_range <= 14.0 and (lamp as SpotLight3D).spot_angle <= 45.0, "floods and pools stay bounded: " + lamp.name)
	for node: Node in berth.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(berth.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(berth.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	for room: String in berth.rooms:
		var props: Node = berth.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	# The landing's real rail stops at the gap: no rail piece crosses it.
	for segment: Array in M09Dressing.LANDING_RAILS:
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var crosses: bool = a.x > -18.3 and b.x > -18.3 and minf(a.z, b.z) < -29.6 and maxf(a.z, b.z) > -32.4
		_expect(not crosses, "no rail across the landing's gap: %s to %s" % [a, b])
	_expect(M09Dressing.LANDING_RAILS.size() == 3, "the landing's three real guards carry a top rail")
	# A re-sent MapInfo with the hatch opened keeps one set of rooms.
	var first: Node = berth.get_child(0)
	berth.configure_map(hatch_open)
	_expect(berth.rooms.size() == ROOMS.size() and berth.get_child_count() == ROOMS.size() and berth.get_child(0) == first,
		"the hatch's re-sent map keeps the same rooms")
	berth.configure_map(other)
	_expect(not berth.active(), "another map clears the berth dressing")
	await process_frame
	_expect(berth.get_child_count() == 0, "cleared rooms leave the tree")
	berth.queue_free()
	await _check_restyle(info)
	await _check_presenter(info)
	if failures == 0:
		print("test_m09_dressing: PASS static-solid guard, hatch re-send, nine dressed regions, floods without red or cyan, no words or bodies, surfaces by use, a tiled deck and a notice only on the closed hatch")
	quit(0 if failures == 0 else 1)

func _check_restyle(info: Dictionary) -> void:
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	_expect(cover._solid_views.size() == info["solids"].size(), "every solid keeps its view")
	var roles: Dictionary = {}
	for index: int in range(info["solids"].size()):
		var view: MeshInstance3D = cover._solid_views[index]
		var material: Material = view.material_override
		var box: AABB = M09Dressing._bounds(info["solids"][index])
		var role: String = M09Dressing.berth_role(box, str(info["presentation"]["solids"][index]))
		roles[role] = true
		if role == "glass":
			_expect(material is StandardMaterial3D and (material as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "the roof glazing stays transparent")
			continue
		_expect(material is ShaderMaterial, "solid %d is restyled" % index)
		if material is ShaderMaterial:
			var shader: ShaderMaterial = material
			_expect(float(shader.get_shader_parameter("trim_glow")) == 0.0, "no solid's paint emits light: solid %d" % index)
			var base: Color = shader.get_shader_parameter("surface_color")
			var accent: Color = shader.get_shader_parameter("accent_color")
			var union_livery: bool = base.v <= 0.3 and accent.s > 0.5 and (accent.h < 0.06 or accent.h > 0.94)
			_expect(not union_livery, "no solid wears the Union's black and red: solid %d (%s)" % [index, role])
			if role in ["hull", "deck_upper", "bow", "hatch"]:
				_expect(not _reserved(base), "the ship is neither Union black nor matte off-white: solid %d (%s)" % [index, role])
	for role: String in ["shell", "roof", "frame", "column", "hull", "deck_upper", "bow", "engine", "cradle", "tower", "hatch", "stair",
		"rail", "locker", "ceiling", "deck_block", "office", "gantry", "car", "goods", "barrier", "receiving", "panel", "glass"]:
		_expect(roles.has(role), "the berth uses its %s surface" % role)
	_expect(M09Dressing.berth_role(AABB(Vector3(-3, 12, -31), Vector3(6, 4, 1)), "enamel") == "hatch", "the closed hatch is the ship's bone door")
	_expect(M09Dressing.berth_role(AABB(Vector3(-3, 16, -31), Vector3(6, 4, 1)), "enamel") == "hatch", "the opened hatch keeps its door")
	_expect(M09Dressing.berth_role(AABB(Vector3(-8, 2, -18), Vector3(16, 7, 36)), "enamel") == "hull", "the keel is gunmetal plate")
	_expect(not (cover.get_node("MapFloor") as Node3D).visible, "the single floor plane gives way to deck plate")
	var tiles: Array[Node] = cover.find_children("*Deck*", "MeshInstance3D", true, false)
	_expect(tiles.size() >= 100, "the berth floor is decked in tiles, found %d" % tiles.size())
	_expect(cover.find_children("*CradleDeck*", "MeshInstance3D", true, false).size() >= 8, "the cradle's footprint is its own scorched plate")
	for tile: Node in tiles:
		var size: Vector2 = ((tile as MeshInstance3D).mesh as PlaneMesh).size
		_expect(size.x <= M06Dressing.FLOOR_TILE + 0.01 and size.y <= M06Dressing.FLOOR_TILE + 0.01, "deck tiles stay small enough to carry their own lights")
	_expect(cover.find_children("*", "CollisionObject3D", true, false).is_empty(), "restyling adds no bodies")
	var bare: Dictionary = info.duplicate(true)
	bare["map_id"] = 1008
	cover.apply_map_info(bare)
	_expect((cover.get_node("MapFloor") as Node3D).visible and cover.find_children("*CradleDeck*", "MeshInstance3D", true, false).is_empty(), "another map keeps its plain floor")
	cover.queue_free()
	await process_frame

## The berth presenter with the real authored map and mission facts: the
## dressing survives the hatch's re-sent map, the readable notice is pasted
## only on the closed hatch, and the windows, clamps and engines follow facts.
func _check_presenter(source: Dictionary) -> void:
	var geometry: Dictionary = _mission_info(false)
	if geometry.is_empty():
		_expect(false, "the authored berth builds a mission MapInfo")
		return
	var berth: M09Berth = M09Berth.new()
	root.add_child(berth)
	berth.configure_map(geometry)
	var dressing: Node = berth.get_node_or_null("BerthDressing")
	_expect(dressing != null and (dressing as M09Dressing).active(), "the authored berth is dressed")
	_expect(berth.find_children("ImpoundNotice", "Label3D", true, false).size() == 1, "the closed hatch carries the impound notice")
	var name_signs: Array[Node] = berth.find_children("CommonCarrierHullName", "Label3D", true, false)
	_expect(name_signs.size() == 1 and (name_signs[0] as Node3D).global_position.x < -8.0, "the hull name is painted on the port side, outside the keel")
	_expect(berth._windows.size() == M09Berth.WINDOWS * 2 and berth._clamps.size() == 4, "the ship has its windows and clamps")
	_expect(_clamps_clear(berth, geometry), "no held clamp piece sits inside a server solid")
	# Facts drive the fittings: windows, clamps and engines, only on change.
	berth.apply_state(_state(geometry, 3))
	_expect(berth.state_applied == 1 and not berth.clamps_released() and not berth.engines_lit(), "the freed crew leave clamps held and engines cold")
	var window: Material = berth._windows[0].material_override
	berth.apply_state(_state(geometry, 3))
	_expect(berth.state_applied == 2 and berth._windows[0].material_override == window, "a repeated message reuses the same finishes")
	var open: Dictionary = _mission_info(true)
	berth.configure_map(open)
	berth.apply_state(_state(open, 7))
	_expect(berth.state_applied == 1 and berth.clamps_released() and not berth.engines_lit(), "the cradle releases before the hatch is won")
	_expect(_clamps_clear(berth, open), "no released clamp piece sits inside a server solid")
	berth.apply_state(_state(open, 8))
	_expect(berth.engines_lit(), "the engines light when the hatch is won, before departure")
	var lit_finish: Material = berth._engine_lamps[0].material_override
	_expect(lit_finish == berth._engine_lamps[1].material_override, "both engines share one lit finish")
	_expect(berth.get_node_or_null("BerthDressing") == dressing, "the hatch's re-sent map keeps the same dressing")
	_expect(berth.find_children("ImpoundNotice", "Label3D", true, false).is_empty(), "the opened hatch has no notice: Tern kept it")
	berth.clear_map()
	await process_frame
	_expect(berth.get_child_count() == 0, "map retirement removes the dressing too")
	berth.queue_free()
	await process_frame
	_expect(source.size() > 0, "the source map loaded")

## Whether every clamp piece stays out of every solid (a touching face is fine).
static func _clamps_clear(berth: M09Berth, info: Dictionary) -> bool:
	var boxes: Array[AABB] = berth.clamp_boxes()
	if boxes.size() != 12:
		return false
	for box: AABB in boxes:
		var inner: AABB = box.grow(-0.005)
		for solid: Dictionary in info["solids"]:
			if M09Dressing._bounds(solid).intersects(inner):
				return false
	return true

## A Mission message for the authored berth with `done` steps complete: the
## crew stand on their recorded route as far as the facts let them.
static func _state(info: Dictionary, done: int) -> Dictionary:
	var crew: Array = []
	var boarding: Dictionary = info["m09"]["boarding"]
	for definition: Dictionary in info["m09"]["crew"]:
		var at: int = 0
		if done >= 3:
			for index: int in range(definition["held_until"].size()):
				if int(definition["held_until"][index]) <= done:
					at = index
		var feet: Array = definition["route"][at]
		var inside: bool = M03MissionState._inside(feet, boarding)
		crew.append({"id": definition["id"], "feet": feet, "aboard": done >= 3 and inside})
	var facts: Dictionary = {"completed": M09MissionState.OBJECTIVES.slice(0, mini(done, 8)), "crew_released": done >= 3, "crew": crew,
		"hatch_open": bool(info["m09"]["hatch_open"]), "charge_falls": 0}
	if done < 9:
		facts["current"] = M09MissionState.step(info["m09"], done)
	return {"id": MissionState.M09_ID, "rules": {"difficulty": "standard", "revision": MissionState.RULES_REVISION},
		"attempt": 1, "phase": "in_progress", "changed_at": 10,
		"party": [{"id": "00000000-0000-0000-0000-000000000009", "name": "Visitor", "ready": true, "alive": true, "aboard": done >= 8}], "prompts": [], "m09": facts}

## A MapInfo the client's M09 check accepts, built from the authored map:
## the server's control decorations and the hatch index, closed or opened.
static func _mission_info(hatch_open: bool) -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m09_passenger_manifest.json"))
	if not source is Dictionary:
		return {}
	var solids: Array = []
	var surfaces: Array = []
	var index_of: Dictionary = {}
	for solid: Dictionary in source["solids"]:
		index_of[solid["id"]] = solids.size()
		var bottom: float = float(solid["min"][1])
		var top: float = float(solid["max"][1])
		if solid["id"] == source["m09"]["hatch"]["solid"] and hatch_open:
			bottom = float(source["m09"]["hatch"]["open"]["min"][1])
			top = float(source["m09"]["hatch"]["open"]["max"][1])
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2],
			"bottom": bottom, "top": top})
		surfaces.append(solid.get("surface", "concrete"))
	var bound: Dictionary = source["m09"]
	var decorations: Array = []
	var controls: Dictionary = {}
	for key: String in ["crew_release", "departure"]:
		var panel: Dictionary = bound[key]["panel"].duplicate(true)
		panel["solid"] = index_of[panel["solid"]]
		controls[key] = {"decoration": decorations.size(), "approach": bound[key]["approach"]}
		decorations.append(panel)
	var objectives: Array = []
	for objective: Dictionary in bound["objectives"]:
		objectives.append({"id": objective["id"], "action": {"kind": "arrival", "feet": objective["approach"], "region": objective["arrival"]}})
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"],
		"half_extent": source["half_extent"], "solids": solids,
		"m09": {"objectives": objectives, "crew_release": controls["crew_release"], "crew": bound["crew"], "departure": controls["departure"],
			"boarding": bound["departure"]["boarding"], "companion_start": bound["companion_start"], "hatch": index_of[bound["hatch"]["solid"]], "hatch_open": hatch_open},
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": decorations}}
