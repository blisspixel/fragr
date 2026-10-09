extends SceneTree

## Repeatable finite Arc maintenance lesson, separate from connected M12.
const OUTPUT: String = "../server/maps/test/arc_foundation_development.json"

func _initialize() -> void:
	var solids: Array[Dictionary] = []
	_add(solids, "perimeter_west", [-23, 0, -23], [-22, 4, 23])
	_add(solids, "perimeter_east", [22, 0, -23], [23, 4, 23])
	_add(solids, "perimeter_south", [-22, 0, -23], [22, 4, -22])
	_add(solids, "perimeter_north", [-22, 0, 22], [22, 4, 23])
	_add(solids, "maintenance_rack", [-13, 0, -20], [-4, 2.2, -19], "enamel")
	_add(solids, "maintenance_side", [-15, 0, -20], [-14, 2.8, -11], "enamel")
	_add(solids, "arrival_left", [-22, 0, -6.4], [-4, 4, -6])
	_add(solids, "arrival_right", [4, 0, -6.4], [22, 4, -6])
	_add(solids, "court_left", [-22, 0, 6], [-4, 4, 6.4])
	_add(solids, "court_right", [4, 0, 6], [22, 4, 6.4])
	_add(solids, "final_left", [-22, 0, 15.5], [-4, 4, 15.9])
	_add(solids, "final_right", [4, 0, 15.5], [22, 4, 15.9])
	_add(solids, "first_cover_west", [-10, 0, -2], [-6, 1.2, 0], "enamel")
	_add(solids, "first_cover_east", [6, 0, 0], [10, 1.2, 2], "enamel")
	_add(solids, "second_cover_east", [3, 0, 9], [7, 1.2, 12], "enamel")
	_add(solids, "final_cover_west", [-10, 0, 18], [-6, 1.2, 20], "enamel")
	var document: Dictionary = {"version":1, "map_id":1042, "name":"Arc Maintenance (development)",
		"half_extent":24, "ground":"concrete", "equipment":"discovery", "solids":solids,
		"spawns":[{"id":"entry", "feet":[0,0,-18], "yaw":PI * 0.5}],
		"landmarks":[{"id":"maintenance_bay", "feet":[-8,0,-16]}, {"id":"first_approach", "feet":[0,0,-5]},
			{"id":"court_approach", "feet":[0,0,8]}, {"id":"pre_final_stock", "feet":[-2,0,13.5]}, {"id":"exit", "feet":[0,0,21]}],
		"supplies":[
			_stock("maintenance_arc", [-8,0,-16], {"kind":"weapon", "weapon":"arc"}),
			_stock("arrival_rifle", [2,0,-18], {"kind":"weapon", "weapon":"flechette"}),
			_stock("arrival_armor", [-2,0,-18], {"kind":"armor", "amount":100}),
			_stock("maintenance_medical", [-17,0,-12], {"kind":"health", "amount":40}),
			_stock("pre_final_medical", [-2,0,13.5], {"kind":"health", "amount":40})],
		"encounters":[
			_group("first_armor", "", [-20,0,-8], [20,3,5.5], "first_heavy", [0,0,1]),
			_group("court_armor", "first_armor", [-20,0,6.5], [20,3,15], "court_heavy", [-9,0,11]),
			_group("final_armor", "court_armor", [-20,0,16], [20,3,22], "final_heavy", [9,0,19])],
		"decorations":[
			{"solid":"maintenance_rack", "face":"north", "kind":"maintenance_sign", "center":[0,0.4], "size":[3,0.8]},
			{"solid":"arrival_left", "face":"south", "kind":"strip_light", "center":[0,1], "size":[4,0.2]},
			{"solid":"court_right", "face":"south", "kind":"strip_light", "center":[0,1], "size":[4,0.2]},
			{"solid":"final_left", "face":"south", "kind":"strip_light", "center":[0,1], "size":[4,0.2]}]}
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null or not file.store_string(JSON.stringify(document, "  ", true) + "\n"):
		push_error("author_arc_development: source write failed")
		quit(1)
		return
	file.close()
	print("author_arc_development: PASS 16 solids, three ordered armored guards, one forty-Cell Arc find")
	quit(0)

func _add(solids: Array[Dictionary], id: String, minimum: Array, maximum: Array, surface: String = "concrete") -> void:
	solids.append({"id":id, "min":minimum, "max":maximum, "surface":surface})

func _stock(id: String, feet: Array, grant: Dictionary) -> Dictionary:
	return {"id":id, "feet":feet, "claim":"personal" if grant.kind == "weapon" else "contested", "grant":grant}

func _group(id: String, after: String, minimum: Array, maximum: Array, name: String, feet: Array) -> Dictionary:
	var group: Dictionary = {"id":id, "regions":[{"min":minimum, "max":maximum}],
		"enemies":[{"id":name, "kind":"heavy_sweeper", "feet":feet, "yaw":PI * 1.5, "armor":100}]}
	if not after.is_empty():
		group["after"] = after
	return group
