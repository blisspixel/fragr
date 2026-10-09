extends SceneTree

## Repeatable static launch-works development map. Every playable prop is a
## server solid. Driving landmarks leave a broad circuit around the berms.
const OUTPUT: String = "res://../server/maps/test/launch_authority_development.json"
var _solids: Array[Dictionary] = []
var _supplies: Array[Dictionary] = []

func _initialize() -> void:
	_perimeter()
	_arrival_and_depot()
	_field()
	_gantry()
	_trenches()
	_stock()
	var document: Dictionary = {
		"version": 1, "map_id": 1014, "name": "Launch Authority (development)",
		"half_extent": 70, "ground": "concrete", "equipment": "discovery",
		"solids": _solids, "supplies": _supplies, "encounters": _encounters(),
		"spawns": [{"id": "freight_lift_entry", "feet": [-46.0, 2.0, -52.0], "yaw": PI / 2.0}],
		"vehicles": [{"id": "captured_jeep", "feet": [-24.0, 0.0, -24.0], "yaw": PI / 2.0}],
		"landmarks": _landmarks(),
		"decorations": [
			{"solid": "lift_back", "face": "south", "kind": "lift_sign", "center": [0.0, 0.5], "size": [2.4, 1.0]},
			{"solid": "motorpool_back", "face": "south", "kind": "maintenance_sign", "center": [0.0, 0.0], "size": [2.4, 1.0]},
			{"solid": "gantry_control_back", "face": "south", "kind": "terminal", "center": [0.0, -0.2], "size": [1.4, 1.1]},
			{"solid": "depot_roof", "face": "down", "kind": "strip_light", "center": [0.0, 0.0], "size": [2.0, 0.3]},
			{"solid": "motorpool_roof", "face": "down", "kind": "strip_light", "center": [0.0, 0.0], "size": [2.0, 0.3]},
		],
	}
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Launch Authority source cannot be written")
		quit(1)
		return
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()
	print("author_launch_authority: PASS (%d solids, %d supplies, 20 guards)" % [_solids.size(), _supplies.size()])
	quit(0)

func _box(id: String, lower: Array, upper: Array, surface: String = "service_steel") -> void:
	_solids.append({"id": id, "min": lower, "max": upper, "surface": surface})

func _perimeter() -> void:
	# Authoritative excavated rims make the closed development yard legible.
	# The entire registered driving circuit stays clear of their inner faces.
	_box("perimeter_south", [-70, 0, -70], [70, 3.6, -68.5], "concrete")
	_box("perimeter_north", [-70, 0, 68.5], [70, 3.6, 70], "concrete")
	_box("perimeter_west", [-70, 0, -68.5], [-68.5, 3.6, 68.5], "concrete")
	_box("perimeter_east", [68.5, 0, -68.5], [70, 3.6, 68.5], "concrete")

func _arrival_and_depot() -> void:
	_box("freight_lift", [-50, 0, -58], [-42, 2, -50])
	_box("lift_back", [-50, 2, -58], [-42, 7, -57.6], "enamel")
	_box("lift_west", [-50, 2, -58], [-49.6, 5, -50], "enamel")
	_box("lift_east", [-42.4, 2, -58], [-42, 5, -50], "enamel")
	for index: int in range(7):
		var z: float = -50.0 + float(index)
		_box("lift_step_%02d" % index, [-48, 0, z], [-44, 1.75 - index * 0.25, z + 1], "enamel")
	# Cargo explains freight arrival without obscuring the gantry sightline.
	_box("incoming_freight_a", [-37, 0, -47], [-31, 2.6, -42], "enamel")
	_box("incoming_freight_b", [-17, 0, -46], [-10, 2.1, -41], "enamel")
	_box("incoming_freight_c", [-15, 2.1, -45], [-11, 3.8, -42], "records_tile")
	_box("depot_west", [-40, 0, -27], [-39.6, 3.5, -16], "enamel")
	_box("depot_back", [-40, 0, -16.4], [-31, 3.5, -16], "enamel")
	_box("depot_east", [-31.4, 0, -27], [-31, 3.5, -16], "enamel")
	_box("depot_front_port", [-40, 0, -27], [-37, 3.5, -26.6], "enamel")
	_box("depot_front_starboard", [-34, 0, -27], [-31, 3.5, -26.6], "enamel")
	_box("depot_roof", [-40.3, 3.2, -27.3], [-30.7, 3.5, -15.7], "enamel")
	for index: int in range(14):
		var z: float = -31.0 + float(index)
		_box("depot_stair_%02d" % index, [-43, 0, z], [-40, (index + 1) * 0.25, z + 1], "enamel")
	_box("depot_stair_landing", [-43, 0, -17], [-39.6, 3.5, -15.7], "enamel")
	_box("depot_roof_cover", [-38, 3.5, -18.3], [-32, 4.5, -17.7])
	_box("depot_sandbag_west", [-33, 0, -34], [-27, 1.0, -33.1], "concrete")
	_box("depot_sandbag_east", [-21, 0, -33], [-16, 1.0, -32.1], "concrete")
	_box("arrival_blast_screen", [-41, 0, -38], [-34, 2.8, -37.2], "enamel")
	_box("depot_workbench", [-38.5, 0, -19], [-36.5, 1.0, -18.1], "lift_panel")
	# Four slender posts and a high tarp leave the shared full occupant hull clear.
	_box("motorpool_roof", [-30.5, 4.1, -28.5], [-17.5, 4.3, -19.5], "enamel")
	_box("motorpool_back", [-30, 0, -28.4], [-18, 3.4, -28])
	for column: int in range(2):
		var x: float = -30.0 + column * 12.0
		for row: int in range(2):
			var z: float = -28.0 + row * 8.0
			_box("motorpool_post_%d_%d" % [column, row], [x - 0.15, 0, z - 0.15], [x + 0.15, 4.1, z + 0.15])
	_box("repair_bay_back", [-13, 0, -27], [-4, 3.8, -26.6], "enamel")
	_box("repair_bay_east", [-4.4, 0, -27], [-4, 3.8, -19], "enamel")
	_box("repair_bay_roof", [-13, 3.8, -27], [-4, 4.1, -19], "enamel")
	_box("repair_toolbox", [-6.5, 0, -25.4], [-5.2, 1.0, -24.5], "lift_panel")

func _field() -> void:
	# The outside circuit is flat. Berms stand in its central island, leaving
	# vehicle-width bends and ordinary infantry lanes along both inner flanks.
	_box("west_berm_south", [-35, 0, -6], [-28, 3.2, 12], "concrete")
	_box("west_berm_north", [-35, 0, 20], [-28, 3.8, 38], "concrete")
	_box("east_berm_south", [28, 0, -10], [35, 3.8, 8], "concrete")
	_box("east_berm_north", [28, 0, 17], [35, 3.2, 38], "concrete")
	_box("center_berm_west", [-16, 0, 10], [-5, 2.4, 14], "concrete")
	_box("center_berm_east", [5, 0, 20], [17, 2.4, 24], "concrete")
	_box("midfield_bunker_west_back", [-23.5, 0, 10], [-17, 3.4, 10.4], "enamel")
	_box("midfield_bunker_west_side", [-23.5, 0, 4], [-23.1, 3.4, 10.4], "enamel")
	_box("midfield_bunker_west_roof", [-23.5, 3.4, 4], [-17, 3.7, 10.4], "enamel")
	_box("midfield_bunker_east_back", [17, 0, 12], [23.5, 3.4, 12.4], "enamel")
	_box("midfield_bunker_east_side", [23.1, 0, 6], [23.5, 3.4, 12.4], "enamel")
	_box("midfield_bunker_east_roof", [17, 3.4, 6], [23.5, 3.7, 12.4], "enamel")
	_box("berm_watch_cover", [-5, 0, 4], [3, 1.1, 4.8], "concrete")
	# Supported marksman nest has a normal stair route from either field flank.
	_box("marksman_plinth", [8, 0, -2], [14, 2.0, 3], "enamel")
	for index: int in range(8):
		_box("marksman_stair_%02d" % index, [8, 0, -10 + index], [12, (index + 1) * 0.25, -9 + index], "enamel")
	_box("marksman_sill", [12.2, 2, -2.2], [14, 2.9, -1.8])
	_box("bend_turret_shield", [37, 0, 18], [38, 1.1, 23], "concrete")
	_box("apron_freight_west", [-12, 0, 29], [-6, 2.6, 33], "enamel")
	_box("apron_freight_east", [17, 0, 29], [24, 2.6, 33], "enamel")
	_box("apron_low_cover", [0, 0, 30], [5, 1.0, 30.8], "concrete")
	# Plain curb markers outline road edges without becoming a ramp or hazard.
	for index: int in range(6):
		var z: float = -12 + index * 10
		_box("west_road_marker_%02d" % index, [-58, 0, z], [-57.3, 0.5, z + 1.2], "enamel")
		_box("east_road_marker_%02d" % index, [57.3, 0, z], [58, 0.5, z + 1.2], "enamel")

func _gantry() -> void:
	# The tall service frame is visible above all depot and berm geometry.
	for x: float in [0.0, 10.0]:
		for z: float in [41.0, 47.0]:
			_box("gantry_pier_%d_%d" % [int(x), int(z)], [x, 0, z], [x + 1, 28, z + 1])
	for index: int in range(5):
		var y: float = 6 + index * 5
		_box("gantry_cross_%02d" % index, [0, y, 41], [11, y + 0.65, 42])
		_box("gantry_service_deck_%02d" % index, [0, y, 47], [11, y + 0.4, 49], "enamel")
	_box("gantry_top_beam", [-1, 28, 40], [12, 29, 49], "enamel")
	_box("gantry_control_back", [2, 0, 46.5], [8, 3.2, 47], "enamel")
	_box("gantry_control_west", [1.6, 0, 42.5], [2, 3.2, 47], "enamel")
	_box("gantry_control_roof", [1.6, 3.2, 42.5], [8, 3.5, 47], "enamel")
	_box("gantry_guard_cover_west", [-7, 0, 39], [-3, 1.1, 39.8], "concrete")
	_box("gantry_guard_cover_east", [12, 0, 39], [16, 1.1, 39.8], "concrete")
	# A grounded cargo lander and pad establish departure logistics. Their
	# bounds are real cover; neither supplies a boarding or launch operation.
	_box("lander_pad", [22, 0, 38], [37, 0.2, 49], "enamel")
	_box("lander_body", [27, 0.2, 40], [32, 18, 45], "enamel")
	_box("lander_upper", [28, 18, 41], [31, 24, 44], "enamel")
	_box("lander_cargo_spine", [26.5, 5, 39.7], [32.5, 12, 45.3])
	_box("lander_left_foot", [24, 0.2, 41], [27, 1.0, 43])
	_box("lander_right_foot", [32, 0.2, 41], [35, 1.0, 43])

func _trenches() -> void:
	# Head-high parapets cut the berm field. Flank lanes and the outer circuit
	# stay open, so infantry can use either the trench or the road.
	var top := 1.75
	_box("trench_west_00", [-0.75, 0, 6.25], [-0.25, top, 15.0], "concrete")
	_box("trench_west_01", [-0.75, 0, 17.5], [-0.25, top, 22.25], "concrete")
	_box("trench_east_00", [1.25, 0, 6.25], [1.75, top, 8.0], "concrete")
	_box("trench_east_01", [1.25, 0, 10.5], [1.75, top, 22.25], "concrete")
	_box("trench_bunker_west_south", [-4.25, 0, 14.5], [-0.75, top, 15.0], "concrete")
	_box("trench_bunker_west_north", [-4.25, 0, 17.5], [-0.75, top, 18.0], "concrete")
	_box("trench_bunker_west_back", [-4.25, 0, 14.5], [-3.75, top, 18.0], "concrete")
	_box("trench_bunker_east_south", [1.75, 0, 7.5], [5.0, top, 8.0], "concrete")
	_box("trench_bunker_east_north", [1.75, 0, 10.5], [5.0, top, 11.0], "concrete")
	_box("trench_bunker_east_back", [4.5, 0, 7.5], [5.0, top, 11.0], "concrete")

func _supply(id: String, feet: Array, grant: Dictionary, personal: bool = false, secret: bool = false) -> void:
	var value: Dictionary = {"id": id, "feet": feet, "grant": grant, "claim": "personal" if personal else "contested"}
	if secret:
		value["secret"] = true
	_supplies.append(value)

func _stock() -> void:
	_supply("arrival_rifle", [-46, 2, -52], {"kind": "weapon", "weapon": "flechette"}, true)
	_supply("arrival_armor", [-46, 2, -54], {"kind": "armor", "amount": 60})
	_supply("depot_shotgun", [-36, 0, -23.5], {"kind": "weapon", "weapon": "scatter"}, true)
	_supply("depot_bullets", [-38, 0, -40], {"kind": "ammo", "pool": "bullets", "amount": 90})
	_supply("depot_first_aid", [-36, 0, -21], {"kind": "health", "amount": 50})
	_supply("motorpool_shells", [-26, 0, -25.5], {"kind": "ammo", "pool": "shells", "amount": 24})
	_supply("repair_bay_medkit", [-9, 0, -24], {"kind": "health", "amount": 70}, false, true)
	_supply("repair_bay_armor", [-9, 0, -22], {"kind": "armor", "amount": 50})
	_supply("west_flank_rifle", [-20, 0, 6], {"kind": "weapon", "weapon": "flechette"}, true)
	_supply("west_flank_bullets", [-20, 0, 8], {"kind": "ammo", "pool": "bullets", "amount": 100})
	_supply("west_flank_medkit", [-18.5, 0, 8], {"kind": "health", "amount": 70})
	_supply("west_flank_grenades", [-18.5, 0, 6], {"kind": "grenade", "amount": 2}, true)
	_supply("east_flank_railgun", [20, 0, 8], {"kind": "weapon", "weapon": "rail"}, true)
	_supply("east_flank_cells", [20, 0, 10], {"kind": "ammo", "pool": "cells", "amount": 12}, false, true)
	_supply("east_flank_shells", [18.5, 0, 10], {"kind": "ammo", "pool": "shells", "amount": 24})
	_supply("east_flank_medkit", [18.5, 0, 8], {"kind": "health", "amount": 70})
	# The western staging lane allows resupply before entering gantry defense.
	_supply("apron_bullets", [-24, 0, 31], {"kind": "ammo", "pool": "bullets", "amount": 100})
	_supply("apron_shells", [-24, 0, 33], {"kind": "ammo", "pool": "shells", "amount": 24})
	_supply("apron_medkit", [-24, 0, 35], {"kind": "health", "amount": 70})
	_supply("gantry_armor", [14, 0, 45], {"kind": "armor", "amount": 50}, false, true)
	_supply("trench_west_bullets", [-2.5, 0, 16.5], {"kind": "ammo", "pool": "bullets", "amount": 80})
	_supply("trench_east_medkit", [3.5, 0, 9.5], {"kind": "health", "amount": 50})

func _landmarks() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id": "depot_court", "feet": [-25, 0, -36]},
		{"id": "depot_roof_flank", "feet": [-35, 3.5, -20]},
		{"id": "jeep_boarding", "feet": [-25.8, 0, -24]},
		{"id": "parked_mount_lesson", "feet": [-24, 0, -13]},
		{"id": "west_infantry_flank", "feet": [-22, 0, 16]},
		{"id": "east_infantry_flank", "feet": [22, 0, 16]},
		{"id": "marksman_flank", "feet": [11, 2, 1]},
		{"id": "apron_resupply_approach", "feet": [-24, 0, 27]},
		{"id": "apron_resupply", "feet": [-24, 0, 35]},
		{"id": "gantry_apron", "feet": [5, 0, 36]},
		{"id": "gantry_control_approach", "feet": [5, 0, 44.5]},
	]
	var circuit: Array = [[-50, 0, -24], [-50, 0, 30], [-40, 0, 50], [-20, 0, 56], [28, 0, 56], [48, 0, 38], [50, 0, -22], [48, 0, -54], [36, 0, -63], [-36, 0, -63], [-56, 0, -63], [-56, 0, -50], [-56, 0, -24]]
	for index: int in range(circuit.size()):
		result.append({"id": "circuit_%02d" % index, "feet": circuit[index]})
	result.append({"id": "trench_south_mouth", "feet": [0.5, 0, 5.5]})
	result.append({"id": "trench_lane", "feet": [0.5, 0, 12.5]})
	result.append({"id": "trench_bunker_west", "feet": [-2.5, 0, 16.5]})
	result.append({"id": "trench_bunker_east", "feet": [3.5, 0, 9.5]})
	result.append({"id": "trench_north_mouth", "feet": [0.5, 0, 23.5]})
	return result

func _enemy(id: String, kind: String, feet: Array, yaw: float = PI * 1.5) -> Dictionary:
	return {"id": id, "kind": kind, "feet": feet, "yaw": yaw}

func _notary(id: String, x: float, z: float, height: float) -> Dictionary:
	var actor: Dictionary = _enemy(id, "notary", [x, height, z])
	actor["hover"] = {"volume": {"min": [x - 3, 3, z - 2], "max": [x + 3, 4.8, z + 2]},
		"band": [3.0, 4.8], "patrol": [[x - 2, height, z], [x + 2, height, z]],
		"approach": [x, 0, z - 9]}
	return actor

func _group(id: String, after: String, lower: Array, upper: Array, enemies: Array) -> Dictionary:
	var group: Dictionary = {"id": id, "regions": [{"min": lower, "max": upper}], "enemies": enemies}
	if not after.is_empty():
		group["after"] = after
	return group

func _encounters() -> Array[Dictionary]:
	return [
		_group("depot_defense", "", [-54, 0, -43], [-6, 5, -14], [
			_enemy("depot_clerk_west", "clerk", [-30, 0, -31.5]),
			_enemy("depot_clerk_east", "clerk", [-18, 0, -30.5]),
			_enemy("depot_sweeper_west", "sweeper", [-35.5, 0, -23]),
			_enemy("depot_sweeper_east", "sweeper", [-13.5, 0, -23]),
			_enemy("depot_roof_turret", "turret", [-35, 3.5, -20]),
		]),
		_group("parked_notary_lesson", "depot_defense", [-31, 0, -29], [-6, 5, -10], [
			_notary("road_notary_west", -24, -4, 3.6), _notary("road_notary_east", -11, 2, 4.2),
		]),
		_group("berm_watch", "parked_notary_lesson", [-57, 0, -10], [57, 5, 26], [
			_enemy("berm_clerk_west", "clerk", [-14, 0, 6]),
			_enemy("berm_clerk_east", "clerk", [16, 0, 16]),
			_enemy("berm_marksman", "ranged_sweeper", [11, 2, 1]),
			_enemy("bend_turret", "turret", [40, 0, 20], PI),
		]),
		_group("apron_watch", "berm_watch", [-55, 0, 26], [55, 5, 40], [
			_enemy("apron_clerk_west", "clerk", [-9, 0, 35]),
			_enemy("apron_clerk_east", "clerk", [20, 0, 35]),
			_enemy("apron_sweeper_west", "sweeper", [-16, 0, 38]),
			_enemy("apron_sweeper_east", "sweeper", [17, 0, 38]),
		]),
		_group("gantry_defense", "apron_watch", [-22, 0, 33], [24, 5, 54], [
			_enemy("gantry_clerk_west", "clerk", [-5, 0, 42]),
			_enemy("gantry_clerk_east", "clerk", [14, 0, 42]),
			_enemy("gantry_heavy", "heavy_sweeper", [5, 0, 43]),
			_enemy("gantry_sweeper_west", "sweeper", [-10, 0, 46]),
			_enemy("gantry_sweeper_east", "sweeper", [18, 0, 46]),
		]),
	]
