extends SceneTree

## Repeatable static foundry. Every usable platform and obstructing prop is
## authoritative geometry. Forge surfaces are protected scenery, not hazards.
const OUTPUT: String = "res://../server/maps/test/m13_foundry_development.json"
var _solids: Array[Dictionary] = []

func _initialize() -> void:
	_shell()
	_foundry_edge()
	_machine_hall()
	_quarters_and_office()
	_freight_loop()
	_ladle_galleries()
	var document: Dictionary = {
		"version": 1, "map_id": 1013, "name": "The Weight of Permission (development)",
		"half_extent": 58, "ground": "concrete", "equipment": "discovery",
		"solids": _solids, "supplies": _supplies(), "encounters": _encounters(),
		"spawns": [{"id": "service_arrival", "feet": [0.0, 0.3, -49.0], "yaw": PI / 2.0}],
		"landmarks": _landmarks(), "decorations": _details(),
	}
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Foundry development source cannot be written")
		quit(1)
		return
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()
	print("author_foundry_development: PASS (%d solids, %d supplies, 22 guards)" % [_solids.size(), _supplies().size()])
	quit(0)

func _box(id: String, lower: Array, upper: Array, surface: String = "service_steel") -> void:
	_solids.append({"id": id.replace("-", "n"), "min": lower, "max": upper, "surface": surface})

func _shell() -> void:
	_box("foundry_foundation", [-40, 0, -54], [40, 0.3, 54], "concrete")
	_box("west_perimeter", [-40, 0.3, -54], [-39.5, 10, 54], "enamel")
	_box("east_perimeter", [39.5, 0.3, -54], [40, 10, 54], "enamel")
	_box("south_perimeter", [-39.5, 0.3, -54], [39.5, 10, -53.5], "enamel")
	_box("north_perimeter", [-39.5, 0.3, 53.5], [39.5, 14, 54], "enamel")
	_box("main_roof", [-29, 9.8, -39], [39.5, 10.1, 27], "enamel")
	_box("ladle_roof", [-39.5, 14, 27], [39.5, 14.3, 54], "enamel")
	_box("entry_roof", [-8, 4.5, -53.5], [8, 4.8, -39], "enamel")
	_box("entry_west", [-8, 0.3, -53.5], [-7.6, 4.5, -39], "enamel")
	_box("entry_east", [7.6, 0.3, -53.5], [8, 4.5, -39], "enamel")
	_box("entry_supply_counter", [-6.7, 0.3, -51], [-4.8, 1.2, -46], "lift_panel")
	_box("entry_roof_lintel", [-7.6, 3.5, -39.4], [7.6, 4.5, -39], "enamel")
	_box("ring_roof", [-39.5, 4.2, -39], [-29, 4.5, 27], "enamel")
	for segment: Array in [[-39, -25], [-21, 0], [4, 22]]:
		_box("ring_divider_%d" % segment[0], [-29.4, 0.3, segment[0]], [-29, 4.2, segment[1]], "enamel")
	_box("ring_water_feed", [-38.7, 0.3, -31], [-37.2, 2.4, 20], "lift_panel")
	_box("ring_relay_housing", [-36.8, 0.3, 9], [-35.7, 2.0, 11], "enamel")

func _foundry_edge() -> void:
	# Visible warm process surfaces stand behind full-height approach shields.
	_box("edge_furnace_base", [13, 0.3, -36], [26, 1.0, -27], "records_tile")
	_box("edge_heat_shield_west", [12.5, 0.3, -36.5], [13, 2.4, -26.5], "enamel")
	_box("edge_heat_shield_front", [13, 0.3, -27], [26.5, 2.4, -26.5], "enamel")
	_box("edge_heat_shield_east", [26, 0.3, -36.5], [26.5, 2.4, -27], "enamel")
	_box("edge_furnace_back", [13, 0.3, -36.5], [26, 4.0, -36], "service_steel")
	_box("edge_furnace_hood", [13, 5.4, -36.5], [26.5, 6.2, -26.5])
	_box("edge_furnace_duct", [18, 6.2, -33], [21, 9.8, -30])
	_box("edge_west_machine", [-23, 0.3, -35], [-17, 2.0, -31], "lift_panel")
	_box("edge_west_screen", [-15, 0.3, -28], [-9, 1.35, -27.2], "enamel")
	_box("edge_central_cart", [-3, 0.3, -32], [3, 1.2, -29], "lift_panel")
	_box("edge_south_beam", [-28.5, 8.7, -23], [39, 9.3, -22])

func _machine_hall() -> void:
	for side: int in [-1, 1]:
		var x: float = side * 9.0
		_box("machine_%d" % side, [x - 3, 0.3, -17], [x + 3, 2.3, -10], "lift_panel")
		_box("machine_head_%d" % side, [x - 2, 2.3, -15.5], [x + 2, 3.2, -11.5])
		_box("machine_control_%d" % side, [x - 2.5, 0.3, -8.5], [x - 0.5, 1.3, -7], "enamel")
	_box("machine_center_press", [-2.5, 0.3, -4.5], [2.5, 3.0, -1])
	_box("machine_press_header", [-4, 5.0, -5.5], [4, 5.6, 0])
	_box("machine_press_left", [-4, 0.3, -5.5], [-3.3, 5.0, 0])
	_box("machine_press_right", [3.3, 0.3, -5.5], [4, 5.0, 0])
	_box("machine_overhead_service", [-28, 8.7, -2], [38, 9.2, -1])
	_box("machine_east_screen", [27, 0.3, -18], [28, 2.2, -5], "enamel")

func _quarters_and_office() -> void:
	# Open doors and static frames establish rooms without inventing a rescue.
	for side: int in [-1, 1]:
		var left: float = -27.0 if side == -1 else 13.0
		var right: float = -13.0 if side == -1 else 27.0
		var prefix: String = "quarters" if side == -1 else "office"
		_box(prefix + "_back", [left, 0.3, 10], [right, 3.8, 10.4], "enamel")
		_box(prefix + "_south", [left, 0.3, 2.0], [right, 3.8, 2.4], "enamel")
		_box(prefix + "_roof", [left, 3.8, 2], [right, 4.1, 10.4], "enamel")
		var outer: float = left if side == -1 else right - 0.4
		var inner: float = right - 0.4 if side == -1 else left
		_box(prefix + "_outer", [outer, 0.3, 2.4], [outer + 0.4, 3.8, 10], "enamel")
		_box(prefix + "_door_south", [inner, 0.3, 2.4], [inner + 0.4, 3.8, 4.5], "enamel")
		_box(prefix + "_door_north", [inner, 0.3, 7.5], [inner + 0.4, 3.8, 10], "enamel")
		_box(prefix + "_door_lintel", [inner, 3.0, 4.5], [inner + 0.4, 3.8, 7.5], "enamel")
	for index: int in range(3):
		var x: float = -24.0 + index * 3.3
		_box("worker_frame_%d" % index, [x, 0.3, 8.3], [x + 1.0, 2.6, 9.0], "lift_panel")
	_box("quarters_bench", [-25.5, 0.3, 3.1], [-19, 0.8, 4.0], "enamel")
	_box("office_freight_desk", [19, 0.3, 8.3], [25.5, 1.2, 9.4], "lift_panel")
	_box("office_supply_pallet", [23.5, 0.3, 3.2], [26.0, 0.7, 4.2], "enamel")

func _freight_loop() -> void:
	_box("freight_cart", [-4.5, 0.3, 17], [4.5, 1.25, 21], "lift_panel")
	_box("freight_cart_load", [-3.8, 1.25, 17.7], [1.5, 2.2, 20.2], "enamel")
	_box("freight_west_crates", [-19, 0.3, 13], [-14, 1.8, 17], "enamel")
	_box("freight_east_crates", [13, 0.3, 21], [18, 2.1, 25], "enamel")
	for side: int in [-1, 1]:
		var x: float = side * 3.0
		_box("freight_rail_%d" % side, [x - 0.1, 0.3, 11], [x + 0.1, 0.36, 27])
	_box("freight_hoist_beam", [-27, 8.1, 18], [28, 8.7, 19])
	_box("freight_hoist_hook", [-0.4, 5.7, 18.2], [0.4, 8.1, 18.8], "lift_panel")
	_box("gallery_staging_screen", [-13, 0.3, 24], [-7, 1.2, 24.6], "enamel")

func _ladle_galleries() -> void:
	# Two twelve-tread stairs reach the same connected gallery without jumping.
	for side: int in [-1, 1]:
		var x: float = -26.0 if side == -1 else 21.0
		for index: int in range(12):
			_box("gallery_stair_%d_%02d" % [side, index], [x, 0.3, 16 + index], [x + 5, 0.55 + index * 0.25, 17 + index], "enamel")
		_box("gallery_side_%d" % side, [x, 3.0, 28], [x + 5, 3.3, 47])
		_box("gallery_outer_rail_%d" % side, [x if side == -1 else x + 4.7, 3.3, 28], [x + 0.3 if side == -1 else x + 5, 4.4, 50], "enamel")
	_box("gallery_front_bridge", [-26, 3.0, 28], [26, 3.3, 31])
	_box("gallery_back_bridge", [-26, 3.0, 47], [26, 3.3, 51])
	_box("gallery_back_rail_west", [-26, 3.3, 50.7], [-5, 4.4, 51], "enamel")
	_box("gallery_back_rail_east", [5, 3.3, 50.7], [26, 4.4, 51], "enamel")
	_box("gallery_north_cover", [-12, 3.3, 47], [-6, 4.2, 47.7], "enamel")
	_box("ladle_basin", [-8, 6.6, 33], [8, 7.0, 43], "records_tile")
	_box("ladle_west_wall", [-8.8, 6.1, 32.5], [-8, 9.1, 43.5])
	_box("ladle_east_wall", [8, 6.1, 32.5], [8.8, 9.1, 43.5])
	_box("ladle_back_wall", [-8, 6.1, 43], [8, 9.1, 43.8])
	_box("ladle_front_left", [-8, 6.1, 32.5], [-1, 9.1, 33])
	_box("ladle_front_right", [1, 6.1, 32.5], [8, 9.1, 33])
	_box("protected_pour", [-0.6, 0.3, 32.7], [0.6, 7.0, 33.3], "records_tile")
	_box("pour_shield_front", [-9.5, 0.3, 31.8], [9.5, 2.6, 32.3], "enamel")
	_box("pour_shield_west", [-9.5, 0.3, 32.3], [-9.0, 2.6, 44], "enamel")
	_box("pour_shield_east", [9.0, 0.3, 32.3], [9.5, 2.6, 44], "enamel")
	_box("pour_shield_back", [-9.5, 0.3, 44], [9.5, 2.6, 44.5], "enamel")
	_box("ladle_crane_beam", [-28, 11.3, 36], [28, 12.1, 39])
	_box("ladle_crane_hanger_west", [-6.5, 9.1, 36.5], [-5.7, 11.3, 38.5])
	_box("ladle_crane_hanger_east", [5.7, 9.1, 36.5], [6.5, 11.3, 38.5])
	_box("lift_landing", [-5, 0.3, 47], [5, 3.3, 53.5], "lift_panel")
	_box("lift_shaft_back", [-5, 3.3, 53], [5, 13.5, 53.5], "enamel")
	_box("lift_shaft_west", [-5, 3.3, 51], [-4.6, 13.5, 53], "enamel")
	_box("lift_shaft_east", [4.6, 3.3, 51], [5, 13.5, 53], "enamel")

func _weapon(id: String, feet: Array, weapon: String) -> Dictionary:
	return {"id": id, "feet": feet, "grant": {"kind": "weapon", "weapon": weapon}, "claim": "personal"}

func _supply(id: String, feet: Array, kind: String, amount: int, pool: String = "", secret: bool = false) -> Dictionary:
	var grant: Dictionary = {"kind": kind, "amount": amount}
	if not pool.is_empty(): grant["pool"] = pool
	return {"id": id, "feet": feet, "grant": grant, "claim": "contested", "secret": secret}

func _supplies() -> Array[Dictionary]:
	return [
		_weapon("entry_tack", [0, 0.3, -49], "tack"),
		_weapon("entry_flechette", [0, 0.3, -44], "flechette"),
		_supply("entry_bullets", [2, 0.3, -46], "ammo", 90, "bullets"),
		_supply("entry_armor", [-2, 0.3, -46], "armor", 50),
		_supply("edge_bullets", [-23, 0.3, -27], "ammo", 70, "bullets"),
		_supply("edge_medical", [-24, 0.3, -24], "health", 50),
		_weapon("machine_rail", [-20, 0.3, -23], "rail"),
		_supply("machine_cells", [-18, 0.3, -23], "ammo", 24, "cells"),
		_weapon("quarters_scatter", [-18, 0.3, 6], "scatter"),
		_supply("quarters_medical", [-24, 0.3, 6], "health", 50),
		_supply("office_bullets", [21, 0.3, 6], "ammo", 80, "bullets"),
		_supply("office_cells", [23, 0.3, 6], "ammo", 20, "cells"),
		_supply("office_shells", [25, 0.3, 6], "ammo", 20, "shells"),
		_supply("ring_secret_cells", [-34, 0.3, -12], "ammo", 12, "cells", true),
		_supply("ring_medical", [-34, 0.3, 15], "health", 50),
		_supply("staging_bullets", [-11, 0.3, 23], "ammo", 80, "bullets"),
		_supply("staging_cells", [-9, 0.3, 23], "ammo", 20, "cells"),
		_supply("staging_medical", [-7, 0.3, 23], "health", 60),
		_supply("gallery_armor", [23.5, 3.3, 41], "armor", 50, "", true),
	]

func _enemy(id: String, kind: String, feet: Array) -> Dictionary:
	return {"id": id, "kind": kind, "feet": feet, "yaw": PI * 1.5}

func _notary(id: String, x: float) -> Dictionary:
	var result: Dictionary = _enemy(id, "notary", [x, 5.0, -10])
	result["hover"] = {"volume": {"min": [x - 2, 4, -13], "max": [x + 2, 7, -7]}, "band": [4, 7], "patrol": [[x - 1.5, 5, -12.5], [x + 1.5, 5.8, -7.5]], "approach": [x, 0.3, -16]}
	return result

func _group(id: String, after: String, lower: Array, upper: Array, enemies: Array) -> Dictionary:
	var result: Dictionary = {"id": id, "regions": [{"min": lower, "max": upper}], "enemies": enemies}
	if not after.is_empty(): result["after"] = after
	return result

func _encounters() -> Array[Dictionary]:
	return [
		_group("foundry_edge", "", [-39, 0, -38], [39, 9, -21], [
			_enemy("edge_clerk_west", "clerk", [-18, 0.3, -28]),
			_enemy("edge_clerk_east", "clerk", [7, 0.3, -29]),
			_enemy("edge_sweeper_west", "sweeper", [-7, 0.3, -24]),
			_enemy("edge_sweeper_east", "sweeper", [29, 0.3, -25]),
		]),
		_group("machine_hall", "foundry_edge", [-39, 0, -21], [39, 9, 2], [
			_enemy("machine_heavy", "heavy_sweeper", [0, 0.3, -8]),
			_enemy("machine_clerk", "clerk", [-15, 0.3, -6]),
			_enemy("machine_sweeper", "sweeper", [15, 0.3, -3]),
			_notary("machine_notary_west", -20), _notary("machine_notary_east", 20),
		]),
		_group("quarters_approach", "machine_hall", [-39, 0, 2], [39, 5, 12], [
			_enemy("quarters_clerk", "clerk", [-16, 0.3, 6]),
			_enemy("office_clerk", "clerk", [18, 0.3, 6]),
		]),
		_group("freight_counterattack", "quarters_approach", [-39, 0, 12], [39, 9, 27], [
			_enemy("freight_sweeper_west", "sweeper", [-10, 0.3, 18]),
			_enemy("freight_sweeper_center", "sweeper", [0, 0.3, 23]),
			_enemy("freight_sweeper_east", "sweeper", [10, 0.3, 18]),
			_enemy("freight_clerk_west", "clerk", [-17, 0.3, 22]),
			_enemy("freight_clerk_east", "clerk", [18, 0.3, 16]),
			_enemy("freight_enforcer", "enforcer", [7, 0.3, 24]),
		]),
		_group("ladle_galleries", "freight_counterattack", [-39, 0, 27], [39, 10, 53], [
			_enemy("gallery_clerk_west", "clerk", [-23.5, 3.3, 35]),
			_enemy("gallery_clerk_east", "clerk", [23.5, 3.3, 35]),
			_enemy("gallery_clerk_back", "clerk", [10, 3.3, 49]),
			_enemy("gallery_heavy", "heavy_sweeper", [-15, 3.3, 49]),
			_enemy("gallery_marksman", "ranged_sweeper", [16, 3.3, 29.5]),
		]),
	]

func _point(id: String, feet: Array) -> Dictionary:
	return {"id": id, "feet": feet}

func _landmarks() -> Array[Dictionary]:
	return [
		_point("service_entrance", [0, 0.3, -49]),
		_point("foundry_edge_bypass", [-23, 0.3, -29]),
		_point("machine_west_flank", [-20, 0.3, -8]),
		_point("machine_east_flank", [20, 0.3, -8]),
		_point("maintenance_ring_south", [-34, 0.3, -35]),
		_point("maintenance_ring_north", [-34, 0.3, 24]),
		_point("worker_quarters", [-21, 0.3, 6]),
		_point("freight_office", [21, 0.3, 6]),
		_point("freight_loop_west", [-11, 0.3, 20]),
		_point("freight_loop_east", [10, 0.3, 23]),
		_point("gallery_resupply_approach", [-11, 0.3, 22]),
		_point("gallery_resupply", [-7, 0.3, 23]),
		_point("west_stair_foot", [-23.5, 0.3, 15]),
		_point("west_stair_top", [-23.5, 3.3, 29.5]),
		_point("east_stair_foot", [23.5, 0.3, 15]),
		_point("east_stair_top", [23.5, 3.3, 29.5]),
		_point("ladle_gallery_back", [12, 3.3, 49]),
		_point("freight_lift_landing", [0, 3.3, 52]),
	]

func _detail(solid: String, face: String, kind: String, center: Array, size: Array) -> Dictionary:
	return {"solid": solid, "face": face, "kind": kind, "center": center, "size": size}

func _details() -> Array[Dictionary]:
	return [
		_detail("entry_east", "west", "strip_light", [0, 0.6], [3, 0.3]),
		_detail("ring_divider_n21", "west", "strip_light", [0, 0.5], [3, 0.3]),
		_detail("machine_control_n1", "south", "terminal", [0, 0.05], [1.1, 0.7]),
		_detail("quarters_back", "south", "maintenance_sign", [0, 0.5], [2.4, 0.8]),
		_detail("office_back", "south", "property_sign", [0, 0.5], [2.4, 0.8]),
		_detail("office_roof", "down", "strip_light", [0, 0], [3, 0.3]),
		_detail("lift_shaft_back", "south", "lift_sign", [0, 1], [3, 1.3]),
		_detail("lift_shaft_back", "south", "strip_light", [0, 3.5], [4, 0.4]),
	]
