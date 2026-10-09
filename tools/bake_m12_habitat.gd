extends SceneTree
## Repeatable pressure-habitat development blockout. All props own collision.

var _solids: Array[Dictionary] = []

func _initialize() -> void:
	_shell()
	_market()
	_greenhouse()
	_pumps()
	var document: Dictionary = {
		"version": 1, "map_id": 1012, "name": "Terms of Cooperation (development)",
		"half_extent": 40.0, "ground": "concrete", "equipment": "discovery",
		"solids": _solids, "decorations": _details(), "supplies": _supplies(),
		"encounters": _encounters(),
		"spawns": [{"id": "pressure_arrival", "feet": [0.0, 0.3, -32.0], "yaw": PI / 2.0}],
		"landmarks": [
			_point("arrival_hall", [0.0, 0.3, -30.5]),
			_point("market_crossing", [0.0, 0.3, -15.0]),
			_point("market_store", [-11.0, 0.3, -19.0]),
			_point("maintenance_bay", [15.0, 0.3, -5.0]),
			_point("west_greenhouse_flank", [-12.0, 0.3, 2.4]),
			_point("greenhouse_bridge", [0.0, 1.3, 2.4]),
			_point("east_greenhouse_flank", [12.0, 0.3, 2.4]),
			_point("utility_gallery", [-23.0, 0.3, 6.0]),
			_point("utility_court_entrance", [-17.0, 0.3, 23.0]),
			_point("pumping_court", [0.0, 0.3, 22.0]),
			_point("shelter_approach", [16.0, 0.3, 26.0]),
			_point("depot_approach", [0.0, 0.3, 32.0]),
		],
	}
	var file: FileAccess = FileAccess.open("res://../server/maps/test/m12_habitat_development.json", FileAccess.WRITE)
	if file == null:
		push_error("Terms of Cooperation development source cannot be written")
		quit(1)
		return
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()
	print("bake_m12_habitat: PASS (%d solids, %d supplies)" % [_solids.size(), _supplies().size()])
	quit(0)

func _point(id: String, feet: Array) -> Dictionary:
	return {"id": id, "feet": feet}

func _box(id: String, lower: Array, upper: Array, surface: String = "enamel") -> void:
	_solids.append({"id": id, "min": lower, "max": upper, "surface": surface})

func _shell() -> void:
	_box("habitat_foundation", [-31.0, 0.0, -35.0], [31.0, 0.3, 35.0], "concrete")
	_box("west_pressure_boundary", [-31.0, 0.3, -35.0], [-30.7, 4.0, 35.0])
	_box("east_pressure_boundary", [30.7, 0.3, -35.0], [31.0, 4.0, 35.0])
	_box("south_pressure_boundary", [-30.7, 0.3, -35.0], [30.7, 4.0, -34.7])
	_box("north_pressure_boundary", [-30.7, 0.3, 34.7], [30.7, 4.0, 35.0])
	_box("arrival_west", [-8.0, 0.3, -34.7], [-7.7, 3.9, -24.0])
	_box("arrival_east", [7.7, 0.3, -34.7], [8.0, 3.9, -24.0])
	_box("arrival_north_left", [-7.7, 0.3, -24.3], [-2.5, 3.9, -24.0])
	_box("arrival_north_right", [2.5, 0.3, -24.3], [7.7, 3.9, -24.0])
	_box("arrival_lintel", [-2.5, 3.0, -24.3], [2.5, 3.9, -24.0], "service_steel")
	_box("arrival_roof", [-8.0, 3.9, -35.0], [8.0, 4.2, -24.0])
	_box("arrival_bench_left", [-6.9, 0.3, -32.8], [-5.5, 0.8, -27.0], "records_tile")
	_box("arrival_bench_right", [5.5, 0.3, -32.8], [6.9, 0.8, -27.0], "records_tile")
	# The utility gallery runs behind the market and reconnects at the court.
	_box("utility_outer", [-25.7, 0.3, -19.0], [-25.4, 3.4, 23.5], "service_steel")
	_box("utility_inner", [-20.6, 0.3, -10.0], [-20.3, 3.4, 18.0], "service_steel")
	_box("utility_roof", [-25.7, 3.4, -19.0], [-20.3, 3.7, 23.5])
	for index: int in range(5):
		var z: float = -15.0 + index * 8.0
		_box("gallery_pipe_%d" % index, [-25.2, 0.3, z], [-24.7, 2.5, z + 2.0], "lift_panel")

func _market() -> void:
	# Ordinary store rooms remain open through broad front doors.
	_box("market_store_west", [-15.3, 0.3, -24.0], [-15.0, 3.5, -14.0])
	_box("market_store_east", [-7.0, 0.3, -24.0], [-6.7, 3.5, -14.0])
	_box("market_store_south", [-15.0, 0.3, -24.0], [-7.0, 3.5, -23.7])
	_box("market_store_front_left", [-15.0, 0.3, -14.3], [-12.5, 3.5, -14.0])
	_box("market_store_front_right", [-9.5, 0.3, -14.3], [-7.0, 3.5, -14.0])
	_box("market_store_roof", [-15.3, 3.5, -24.0], [-6.7, 3.8, -14.0])
	_box("market_counter", [-14.6, 0.3, -22.0], [-10.5, 1.1, -20.8], "records_tile")
	_box("market_tools", [-14.6, 1.1, -21.8], [-12.8, 1.55, -21.1], "lift_panel")
	_box("east_workroom", [7.0, 0.3, -23.5], [16.0, 3.3, -15.0])
	_box("east_workroom_frame", [6.6, 0.3, -23.7], [7.0, 3.7, -14.7], "service_steel")
	_box("market_service_screen", [-3.0, 0.3, -18.0], [-0.8, 1.1, -16.9], "records_tile")
	_box("market_supply_screen", [1.8, 0.3, -11.5], [4.0, 1.2, -10.3], "records_tile")
	# The bay's intended Arc lesson remains unfinished. These are actual Heavy
	# and ordinary-gun placements, with a side opening to the greenhouse flank.
	_box("bay_west_rear", [9.3, 0.3, -7.0], [9.6, 3.5, 0.0])
	_box("bay_east", [20.4, 0.3, -10.0], [20.7, 3.5, 0.0])
	_box("bay_north_left", [9.6, 0.3, -0.3], [13.0, 3.5, 0.0])
	_box("bay_north_right", [17.0, 0.3, -0.3], [20.4, 3.5, 0.0])
	_box("bay_south_left", [9.3, 0.3, -10.0], [12.5, 3.5, -9.7])
	_box("bay_south_right", [17.5, 0.3, -10.0], [20.7, 3.5, -9.7])
	_box("bay_roof", [9.3, 3.5, -10.0], [20.7, 3.8, 0.0])
	_box("bay_blast_screen", [16.5, 0.3, -5.5], [19.8, 1.2, -5.2], "service_steel")
	_box("bay_workbench", [18.8, 0.3, -3.4], [20.0, 1.15, -1.0], "lift_panel")

func _greenhouse() -> void:
	for side: int in [-1, 1]:
		var x: float = side * 8.3
		for index: int in range(5):
			var z: float = -5.5 + index * 4.0
			_box("greenhouse_post_%d_%d" % [side + 1, index], [x - 0.18, 0.3, z], [x + 0.18, 4.5, z + 0.25], "service_steel")
	for index: int in range(5):
		var z: float = -5.5 + index * 4.0
		_box("greenhouse_roof_rib_%d" % index, [-8.5, 4.4, z], [8.5, 4.65, z + 0.25], "service_steel")
	for side: int in [-1, 1]:
		var lower_x: float = -6.5 if side < 0 else 3.5
		for row: int in range(2):
			var lower_z: float = -5.0 if row == 0 else 5.0
			_box("growth_bed_%d_%d" % [side + 1, row], [lower_x, 0.3, lower_z], [lower_x + 3.0, 1.15, lower_z + 5.5], "records_tile")
			for crop: int in range(4):
				var z: float = lower_z + 0.6 + crop * 1.3
				_box("cultivation_%d_%d_%d" % [side + 1, row, crop], [lower_x + 0.45, 1.15, z], [lower_x + 2.55, 1.5, z + 0.45], "records_tile")
	# An actual supported bridge, reached by four small walking steps each way.
	_box("greenhouse_bridge_deck", [-8.0, 1.05, 1.4], [8.0, 1.3, 3.4], "service_steel")
	for index: int in range(4):
		var z: float = -2.6 + index
		var top: float = 0.55 + index * 0.25
		_box("greenhouse_south_step_%d" % index, [-2.0, 0.3, z], [2.0, top, z + 1.0], "service_steel")
		_box("greenhouse_north_step_%d" % index, [-2.0, 0.3, 6.4 - index], [2.0, top, 7.4 - index], "service_steel")
	_box("greenhouse_west_service_shelf", [-17.5, 0.3, 7.0], [-15.6, 1.1, 10.0], "lift_panel")
	_box("greenhouse_east_recycling", [23.5, 0.3, 2.0], [26.5, 2.6, 10.0], "lift_panel")

func _pumps() -> void:
	for side: int in [-1, 1]:
		var x: float = side * 5.0
		_box("pump_tower_%d" % (side + 1), [x - 1.5, 0.3, 16.5], [x + 1.5, 6.3, 20.5], "lift_panel")
		_box("pump_cap_%d" % (side + 1), [x - 1.8, 6.3, 16.2], [x + 1.8, 6.7, 20.8], "enamel")
		_box("pump_ground_feed_%d" % (side + 1), [x - 0.55, 0.3, 12.5], [x + 0.55, 1.15, 16.5], "service_steel")
		var screen_x: float = -13.0 if side < 0 else 10.0
		_box("court_service_cover_%d" % (side + 1), [screen_x, 0.3, 22.0], [screen_x + 3.0, 1.3, 23.2], "records_tile")
	_box("court_overhead_feed", [-6.5, 5.2, 17.0], [6.5, 5.6, 17.6], "service_steel")
	# The residential frontage has no claimed rescue or interactive door state.
	_box("shelter_frontage", [20.0, 0.3, 18.0], [28.5, 4.5, 30.0])
	_box("shelter_antechamber_south", [16.0, 0.3, 18.0], [20.0, 3.0, 18.3])
	_box("shelter_antechamber_roof", [16.0, 3.0, 18.0], [20.0, 3.3, 30.0])
	_box("depot_canopy", [-10.0, 4.8, 30.0], [10.0, 5.1, 34.7])
	for side: int in [-1, 1]:
		var x: float = side * 9.5
		_box("depot_support_%d" % (side + 1), [x - 0.2, 0.3, 30.0], [x + 0.2, 4.8, 30.4], "service_steel")
	_box("depot_empty_supply_rack", [-8.8, 0.3, 32.5], [-6.0, 1.5, 34.3], "lift_panel")

func _detail(solid: String, face: String, kind: String, center: Array, size: Array) -> Dictionary:
	return {"solid": solid, "face": face, "kind": kind, "center": center, "size": size}

func _details() -> Array[Dictionary]:
	return [
		_detail("arrival_east", "west", "strip_light", [1.0, 0.7], [2.0, 0.25]),
		_detail("arrival_west", "east", "vent", [0.0, 0.0], [1.6, 0.8]),
		_detail("arrival_north_right", "south", "maintenance_sign", [0.0, 0.25], [2.1, 0.65]),
		_detail("market_store_east", "east", "lockers", [0.0, -0.3], [2.8, 1.6]),
		_detail("bay_east", "west", "strip_light", [0.0, 0.65], [2.0, 0.25]),
		_detail("bay_west_rear", "west", "maintenance_sign", [0.0, 0.15], [2.0, 0.65]),
		_detail("utility_inner", "west", "strip_light", [-8.0, 0.5], [2.0, 0.25]),
		_detail("utility_inner", "west", "strip_light", [8.0, 0.5], [2.0, 0.25]),
		_detail("pump_tower_0", "south", "terminal", [0.0, -0.7], [1.2, 1.5]),
		_detail("pump_tower_2", "south", "vent", [0.0, 0.0], [1.5, 1.5]),
		_detail("shelter_frontage", "west", "strip_light", [-2.0, 0.2], [2.0, 0.25]),
		_detail("depot_empty_supply_rack", "south", "property_sign", [0.0, 0.0], [1.9, 0.65]),
	]

func _weapon(id: String, feet: Array, weapon: String) -> Dictionary:
	return {"id": id, "feet": feet, "grant": {"kind": "weapon", "weapon": weapon}, "claim": "personal"}

func _supply(id: String, feet: Array, kind: String, amount: int, pool: String = "", secret: bool = false) -> Dictionary:
	var grant: Dictionary = {"kind": kind, "amount": amount}
	if not pool.is_empty():
		grant["pool"] = pool
	return {"id": id, "feet": feet, "grant": grant, "claim": "contested", "secret": secret}

func _supplies() -> Array[Dictionary]:
	return [
		_weapon("arrival_pistol", [0.0, 0.3, -29.0], "tack"),
		_weapon("arrival_rifle", [-1.4, 0.3, -25.7], "flechette"),
		_supply("arrival_bullets", [0.0, 0.3, -27.5], "ammo", 80, "bullets"),
		_supply("arrival_armor", [2.0, 0.3, -28.0], "armor", 50),
		_supply("market_medical", [-11.0, 0.3, -19.0], "health", 50),
		_supply("market_bullets", [-11.0, 0.3, -17.0], "ammo", 60, "bullets"),
		_weapon("bay_scatter", [10.5, 0.3, -12.5], "scatter"),
		_weapon("bay_rail", [13.0, 0.3, -8.5], "rail"),
		_supply("bay_cells", [15.0, 0.3, -8.5], "ammo", 24, "cells"),
		_supply("bay_shells", [17.0, 0.3, -8.5], "ammo", 12, "shells"),
		_supply("bay_medical", [15.0, 0.3, -1.5], "health", 50),
		_supply("west_cells", [-12.0, 0.3, 8.0], "ammo", 12, "cells"),
		_supply("east_bullets", [12.0, 0.3, 10.0], "ammo", 60, "bullets"),
		_supply("utility_medical", [-23.0, 0.3, 12.0], "health", 50),
		_supply("utility_armor", [-23.0, 0.3, -4.0], "armor", 50, "", true),
		_supply("court_medical", [-12.0, 0.3, 25.0], "health", 50),
		_supply("court_cells", [10.0, 0.3, 20.5], "ammo", 16, "cells"),
		_supply("depot_medical", [4.0, 0.3, 32.0], "health", 40),
	]

func _enemy(id: String, kind: String, feet: Array) -> Dictionary:
	return {"id": id, "kind": kind, "feet": feet, "yaw": PI * 1.5}

func _notary(id: String, feet: Array, lower: Array, upper: Array, patrol: Array, approach: Array) -> Dictionary:
	var result: Dictionary = _enemy(id, "notary", feet)
	result["hover"] = {"volume": {"min": lower, "max": upper}, "band": [3.5, 5.8], "patrol": patrol, "approach": approach}
	return result

func _group(id: String, after: String, lower: Array, upper: Array, enemies: Array) -> Dictionary:
	var result: Dictionary = {"id": id, "regions": [{"min": lower, "max": upper}], "enemies": enemies}
	if not after.is_empty():
		result["after"] = after
	return result

func _encounters() -> Array[Dictionary]:
	return [
		_group("market_defense", "", [-25.0, 0.0, -25.0], [25.0, 2.5, -10.0], [
			_enemy("market_clerk_left", "clerk", [-4.5, 0.3, -18.5]),
			_enemy("market_clerk_right", "clerk", [3.5, 0.3, -15.0]),
			_enemy("market_sweeper_left", "sweeper", [-12.0, 0.3, -11.0]),
			_enemy("market_sweeper_right", "sweeper", [5.0, 0.3, -11.0]),
		]),
		_group("maintenance_defense", "market_defense", [-25.0, 0.0, -10.0], [25.0, 2.5, 0.0], [
			_enemy("maintenance_heavy", "heavy_sweeper", [15.0, 0.3, -4.5]),
			_enemy("maintenance_clerk", "clerk", [12.0, 0.3, -7.0]),
		]),
		_group("greenhouse_defense", "maintenance_defense", [-25.0, 0.0, 0.0], [25.0, 3.0, 12.0], [
			_enemy("greenhouse_clerk", "clerk", [-11.0, 0.3, 8.0]),
			_enemy("greenhouse_sweeper", "sweeper", [11.0, 0.3, 7.0]),
			_notary("greenhouse_notary", [18.0, 4.2, 6.0], [16.0, 3.5, 4.0], [20.0, 5.5, 8.0], [[16.5, 4.2, 4.5], [19.5, 4.6, 7.5]], [12.0, 0.3, 7.0]),
		]),
		_group("court_defense", "greenhouse_defense", [-28.0, 0.0, 12.0], [28.0, 3.0, 31.0], [
			_enemy("court_clerk_west", "clerk", [-10.0, 0.3, 19.0]),
			_enemy("court_clerk_east", "clerk", [10.0, 0.3, 18.0]),
			_enemy("court_sweeper_west", "sweeper", [-14.0, 0.3, 26.0]),
			_enemy("court_sweeper_east", "sweeper", [14.0, 0.3, 26.0]),
			_enemy("court_enforcer", "enforcer", [-17.5, 0.3, 22.0]),
			_notary("court_notary", [0.0, 4.3, 26.0], [-2.0, 3.5, 24.0], [2.0, 5.5, 28.0], [[-1.5, 4.3, 24.5], [1.5, 4.6, 27.5]], [0.0, 0.3, 22.0]),
		]),
	]
