extends SceneTree
## Deterministic collision blockout for the Common Carrier's inhabited decks.

var _solids: Array[Dictionary] = []

func _initialize() -> void:
	var footprint := Rect2(-7.8, -17.8, 15.6, 35.6)
	var holes: Array[Rect2] = [
		Rect2(-2.0, -3.0, 4.0, 8.0),
		Rect2(-7.65, -16.0, 4.2, 13.0),
		Rect2(3.45, 3.0, 4.2, 13.0),
	]
	_box("lower_pressure_floor", [-8.0, 1.7, -18.0], [8.0, 2.0, 18.0])
	for deck: int in range(2):
		var pieces: Array[Rect2] = [footprint]
		for hole: Rect2 in holes:
			pieces = _cut(pieces, hole)
		var top: float = 4.8 + 2.8 * deck
		for index: int in range(pieces.size()):
			var piece: Rect2 = pieces[index]
			_box("deck_%d_%d" % [deck + 1, index],
				[piece.position.x, top - 0.2, piece.position.y],
				[piece.end.x, top, piece.end.y])
	_box("pressure_roof", [-8.0, 10.1, -18.0], [8.0, 10.4, 18.0], "enamel")
	_box("pressure_west", [-8.0, 0.0, -18.0], [-7.8, 10.4, 18.0], "enamel")
	_box("pressure_east", [7.8, 0.0, -18.0], [8.0, 10.4, 18.0], "enamel")
	_box("pressure_fore", [-7.8, 0.0, -18.0], [7.8, 8.05, -17.8], "enamel")
	_box("fore_window_head", [-7.8, 9.55, -18.0], [7.8, 10.4, -17.8], "enamel")
	_box("fore_window_port", [-7.8, 8.05, -18.0], [-4.0, 9.55, -17.8], "enamel")
	_box("fore_window_starboard", [4.0, 8.05, -18.0], [7.8, 9.55, -17.8], "enamel")
	_box("fore_pressure_glass", [-4.0, 8.05, -18.0], [4.0, 9.55, -17.8], "inspection_glass")
	_box("pressure_aft", [-7.8, 0.0, 17.8], [7.8, 10.4, 18.0], "enamel")
	_stairs("west", -7.45, -16.0, 1.0)
	_stairs("east", 3.65, 16.0, -1.0)
	_inhabited()
	var landmarks: Array[Dictionary] = [
		{"id": "passenger_hall", "feet": [0.0, 4.8, -15.0]},
		{"id": "forward_cargo", "feet": [0.0, 2.0, -12.0]},
		{"id": "lower_service", "feet": [-4.0, 2.0, 1.0]},
		{"id": "aft_hold", "feet": [0.0, 2.0, 14.0]},
		{"id": "command_approach", "feet": [0.0, 7.6, -15.0]},
		{"id": "upper_overlook", "feet": [-4.0, 7.6, 1.0]},
		{"id": "aft_gallery", "feet": [0.0, 7.6, 14.0]},
		{"id": "east_middle_landing", "feet": [6.65, 4.8, 14.5]},
		{"id": "west_middle_landing", "feet": [-4.45, 4.8, -14.5]},
	]
	var document: Dictionary = {
		"version": 1, "map_id": 1010, "name": "Common Carrier",
		"half_extent": 24, "ground": "service_steel", "equipment": "discovery",
		"solids": _solids, "landmarks": landmarks,
		"decorations": _details(), "supplies": _supplies(),
		"m10": _mission(), "encounters": _encounters(),
		"spawns": [{"id": "passenger_entry", "feet": [0.0, 4.8, -15.0], "yaw": 0.0}],
	}
	var file: FileAccess = FileAccess.open("res://../server/maps/m10_common_carrier.json", FileAccess.WRITE)
	if file == null:
		push_error("Common Carrier source cannot be written")
		quit(1)
		return
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()
	print("author_common_carrier: PASS (%d solids)" % _solids.size())
	quit(0)

func _box(id: String, lower: Array, upper: Array, surface: String = "service_steel") -> void:
	_solids.append({"id": id, "min": lower, "max": upper, "surface": surface})

func _inhabited() -> void:
	# The side cabin uses the hull and deck slabs for its outer shell. Its
	# ordinary 2.2-metre doorway connects to the passenger hall without a gate.
	_box("bunk_wall_fore", [4.3, 4.8, -17.8], [4.5, 7.4, -15.1], "enamel")
	_box("bunk_wall_aft", [4.3, 4.8, -12.9], [4.5, 7.4, -11.0], "enamel")
	_box("bunk_end", [4.3, 4.8, -11.0], [7.8, 7.4, -10.8], "enamel")
	_box("bunk_fore", [5.4, 4.8, -17.1], [7.3, 5.3, -15.9], "enamel")
	_box("bunk_aft", [5.4, 4.8, -12.7], [7.3, 5.3, -11.5], "enamel")
	_box("galley_counter", [4.5, 4.8, -5.8], [7.3, 5.9, -4.5], "records_tile")
	_box("passenger_repair_bench", [4.5, 4.8, -9.8], [7.3, 5.65, -8.6], "lift_panel")
	_box("command_console", [1.5, 7.6, -16.8], [3.5, 8.5, -16.0], "lift_panel")
	_box("forward_lashed_cargo", [3.0, 2.0, -12.0], [5.5, 3.8, -10.8], "enamel")
	_box("cargo_transfer_stack", [-3.2, 2.0, -5.8], [-1.1, 3.8, -4.4], "enamel")
	_box("service_power_bank", [2.8, 2.0, 0.0], [4.8, 3.8, 2.5], "lift_panel")
	_box("service_coolant_bank", [-4.8, 2.0, 9.3], [-3.0, 3.8, 11.0], "service_steel")
	# Short rails explain the freight drop while the side aisles stay open.
	for level: int in range(2):
		var feet: float = 4.8 + level * 2.8
		_box("freight_fore_rail_%d" % level, [-1.8, feet, -3.15], [1.8, feet + 0.95, -3.0], "lift_panel")
		_box("freight_aft_rail_%d" % level, [-1.8, feet, 5.0], [1.8, feet + 0.95, 5.15], "lift_panel")

func _detail(solid: String, face: String, kind: String, center: Array, size: Array) -> Dictionary:
	return {"solid": solid, "face": face, "kind": kind, "center": center, "size": size}

func _details() -> Array[Dictionary]:
	var details: Array[Dictionary] = [
		_detail("forward_lashed_cargo", "north", "m10_cargo_deck", [0.0, 0.2], [1.8, 0.6]),
		_detail("bunk_wall_fore", "west", "m10_passenger_deck", [0.0, 0.35], [1.8, 0.6]),
		_detail("fore_window_starboard", "south", "m10_command_deck", [0.0, 0.0], [2.0, 0.55]),
	]
	for spec: Array in [["pressure_west", "east", 14.0, 3.6], ["pressure_east", "west", -3.0, 3.6],
		["pressure_west", "east", -12.0, 3.6], ["pressure_east", "west", -14.0, 6.4],
		["pressure_west", "east", 0.0, 6.4], ["pressure_east", "west", 16.0, 6.4],
		["pressure_east", "west", -14.0, 9.1], ["pressure_west", "east", -12.0, 9.1]]:
		details.append(_detail(spec[0], spec[1], "strip_light", [spec[2], float(spec[3]) - 5.2], [1.2, 0.25]))
	return details

func _supply(id: String, feet: Array, kind: String, amount: int, pool: String = "", secret: bool = false) -> Dictionary:
	var grant: Dictionary = {"kind": kind, "amount": amount}
	if not pool.is_empty():
		grant["pool"] = pool
	return {"id": id, "feet": feet, "grant": grant, "claim": "contested", "secret": secret}

func _supplies() -> Array[Dictionary]:
	return [
		_supply("passenger_medical", [5.5, 4.8, -14.0], "health", 50),
		_supply("cargo_bullets", [3.2, 2.0, -14.0], "ammo", 60, "bullets"),
		_supply("cargo_shells", [4.6, 2.0, -14.0], "ammo", 12, "shells"),
		_supply("repair_medical", [5.8, 2.0, -1.0], "health", 30),
		_supply("aft_medical", [-3.0, 2.0, 15.0], "health", 40),
		_supply("crew_armor", [-2.8, 7.6, -15.5], "armor", 50, "", true),
		_supply("surplus_bullets", [5.7, 4.8, -7.0], "ammo", 60, "bullets", true),
		_supply("surplus_shells", [7.1, 4.8, -7.0], "ammo", 12, "shells", true),
	]

func _cut(pieces: Array[Rect2], hole: Rect2) -> Array[Rect2]:
	var output: Array[Rect2] = []
	for piece: Rect2 in pieces:
		var common: Rect2 = piece.intersection(hole)
		if not common.has_area():
			output.append(piece)
			continue
		var candidates: Array[Rect2] = [
			Rect2(piece.position, Vector2(common.position.x - piece.position.x, piece.size.y)),
			Rect2(common.end.x, piece.position.y, piece.end.x - common.end.x, piece.size.y),
			Rect2(common.position.x, piece.position.y, common.size.x, common.position.y - piece.position.y),
			Rect2(common.position.x, common.end.y, common.size.x, piece.end.y - common.end.y),
		]
		for candidate: Rect2 in candidates:
			if candidate.has_area():
				output.append(candidate)
	return output

func _stairs(label: String, first_x: float, origin_z: float, direction: float) -> void:
	var second_x: float = first_x + 2.1
	var lower_z: float = minf(origin_z, origin_z + direction * 3.0)
	var upper_z: float = maxf(origin_z, origin_z + direction * 3.0)
	var turn_begin: float = origin_z + direction * 10.0
	var turn_end: float = origin_z + direction * 13.0
	_box(label + "_stair_spine", [first_x + 1.8, 2.0, minf(origin_z + direction * 3.0, turn_begin)],
		[first_x + 2.1, 10.1, maxf(origin_z + direction * 3.0, turn_begin)])
	for level: int in range(2):
		var base: float = 2.0 + level * 2.8
		# Match the actual Rect2-cut deck edges at both heights. Leaving the
		# earlier 0.10/0.20-metre gaps causes real unsupported side transfers.
		var return_min_x: float = 3.450000047683716 if label == "east" else first_x
		var return_max_x: float = -3.450000286102295 if label == "west" else second_x + 1.8
		_box("%s_return_%d" % [label, level], [return_min_x, base + 2.6, lower_z],
			[return_max_x, base + 2.8, upper_z])
		_box("%s_turn_%d" % [label, level], [first_x, base + 1.2, minf(turn_begin, turn_end)],
			[second_x + 1.8, base + 1.4, maxf(turn_begin, turn_end)])
		for step: int in range(7):
			var from_z: float = origin_z + direction * (3.0 + step * 1.0)
			var to_z: float = from_z + direction * 1.0
			var first_top: float = base + (step + 1) * 0.2
			var second_top: float = base + 2.8 - step * 0.2
			_box("%s_first_%d_%d" % [label, level, step],
				[first_x, first_top - 0.18, minf(from_z, to_z)],
				[first_x + 1.8, first_top, maxf(from_z, to_z)])
			_box("%s_second_%d_%d" % [label, level, step],
				[second_x, second_top - 0.18, minf(from_z, to_z)],
				[second_x + 1.8, second_top, maxf(from_z, to_z)])

func _region(feet: Array, width: float = 1.0) -> Dictionary:
	return {"min": [feet[0] - width, feet[1] - 0.1, feet[2] - width],
		"max": [feet[0] + width, feet[1] + 0.3, feet[2] + width]}

func _mission() -> Dictionary:
	var ids: Array[String] = ["forward_secured", "service_secured", "aft_secured", "passengers_secured"]
	var groups: Array[String] = ["forward_boarders", "service_crawlers", "aft_boarders", "passenger_defense"]
	var approaches: Array[Array] = [[0.0, 2.0, -8.0], [-3.0, 2.0, 8.0], [0.0, 7.6, 14.0], [0.0, 4.8, -12.0]]
	var objectives: Array[Dictionary] = []
	for i: int in range(4):
		objectives.append({"id": ids[i], "requires_encounter": groups[i], "approach": approaches[i], "arrival": _region(approaches[i])})
	return {"objectives": objectives, "pilot": [2.0, 7.6, -15.0], "companion_start": [3.0, 4.8, -15.0],
		"passengers": [{"id": "berth_crew_a", "feet": [2.0, 4.8, -16.0]}, {"id": "berth_crew_b", "feet": [-2.0, 4.8, -16.0]},
			{"id": "edda", "feet": [2.0, 4.8, -14.0]}, {"id": "splice", "feet": [-2.0, 4.8, -14.0]}],
		"departure": {"requires_encounter": groups[3], "approach": [0.0, 4.8, -16.0], "boarding": _region([0.0, 4.8, -16.0], 1.2),
			"panel": {"solid": "pressure_fore", "face": "south", "kind": "m10_ship_confirmation", "center": [0.0, 2.275], "size": [0.7, 0.6]}}}

func _enemy(id: String, kind: String, feet: Array) -> Dictionary:
	return {"id": id, "kind": kind, "feet": feet, "yaw": 0.0}

func _encounters() -> Array[Dictionary]:
	var notary: Dictionary = _enemy("aft_notary", "notary", [0.0, 4.0, 1.0])
	notary["hover"] = {"volume": {"min": [-0.7, 4.0, -1.0], "max": [0.7, 6.0, 3.0]}, "band": [3.5, 6.5],
		"patrol": [[0.0, 4.0, 0.0], [0.0, 5.0, 2.0]], "approach": [0.0, 2.0, 6.2]}
	return [
		{"id": "forward_boarders", "regions": [_region([0.0, 2.0, -12.0], 2.0), _region([0.0, 4.8, -9.0], 2.0)], "enemies": [
			_enemy("forward_clerk_a", "clerk", [-2.0, 2.0, -10.0]), _enemy("forward_clerk_b", "clerk", [2.0, 2.0, -10.0]),
			_enemy("forward_sweeper_a", "sweeper", [-2.0, 2.0, -7.0]), _enemy("forward_sweeper_b", "sweeper", [2.0, 4.8, -7.0])]},
		{"id": "service_crawlers", "after": "forward_boarders", "regions": [_region([-4.0, 2.0, 1.0], 2.0)], "enemies": [
			_enemy("service_crawler_a", "crawler", [-5.0, 2.0, 2.0]), _enemy("service_crawler_b", "crawler", [-5.0, 2.0, 8.0]),
			_enemy("service_crawler_c", "crawler", [-2.0, 2.0, 12.0]), _enemy("service_clerk", "clerk", [2.0, 2.0, 8.0]),
			_enemy("service_sweeper", "sweeper", [0.0, 2.0, 10.0])]},
		{"id": "aft_boarders", "after": "service_crawlers", "regions": [_region([0.0, 7.6, 14.0], 2.0)], "enemies": [
			_enemy("aft_heavy", "heavy_sweeper", [3.0, 2.0, 14.0]), _enemy("aft_sweeper", "sweeper", [0.0, 4.8, 14.0]),
			_enemy("aft_clerk", "clerk", [-3.0, 7.6, 14.0]), notary]},
		{"id": "passenger_defense", "after": "aft_boarders", "regions": [_region([0.0, 4.8, -12.0], 2.0)], "enemies": [
			_enemy("passenger_clerk_a", "clerk", [-2.0, 4.8, -9.0]), _enemy("passenger_clerk_b", "clerk", [2.0, 4.8, -9.0]),
			_enemy("passenger_sweeper", "sweeper", [-2.0, 4.8, -12.0]), _enemy("passenger_enforcer", "enforcer", [2.0, 4.8, -12.0])]},
	]
