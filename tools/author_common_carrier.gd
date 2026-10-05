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
	_box("pressure_fore", [-7.8, 0.0, -18.0], [7.8, 10.4, -17.8], "enamel")
	_box("pressure_aft", [-7.8, 0.0, 17.8], [7.8, 10.4, 18.0], "enamel")
	_stairs("west", -7.45, -16.0, 1.0)
	_stairs("east", 3.65, 16.0, -1.0)
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
		_box("%s_return_%d" % [label, level], [first_x, base + 2.6, lower_z],
			[second_x + 1.8, base + 2.8, upper_z])
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
