extends SceneTree

## Original bounded drone lesson, independent of connected mission progression.
func _initialize() -> void:
	var solids: Array[Dictionary] = []
	_add(solids, "west_wall", [-23,0,-23], [-22,4,23])
	_add(solids, "east_wall", [22,0,-23], [23,4,23])
	_add(solids, "south_wall", [-22,0,-23], [22,4,-22])
	_add(solids, "north_wall", [-22,0,22], [22,4,23])
	_add(solids, "maintenance_rack", [-16,0,-21], [-6,2.4,-20], "enamel")
	_add(solids, "maintenance_side", [-17,0,-21], [-16,3,-13], "enamel")
	_add(solids, "arrival_west", [-22,0,-8.5], [-3.5,4,-8])
	_add(solids, "arrival_east", [3.5,0,-8.5], [22,4,-8])
	_add(solids, "west_screen", [-7,0,-2], [-6.6,3.2,3], "enamel")
	_add(solids, "retake_screen", [-2,0,7], [2,3.2,7.4], "enamel")
	_add(solids, "rear_service_cover", [14,0,-3], [14.5,2.2,3], "enamel")
	_add(solids, "north_service_rack", [6,0,16], [14,2.4,17], "enamel")
	var document: Dictionary = {"version":1,"map_id":1043,"name":"Assessor Canister Court (development)",
		"half_extent":24,"ground":"concrete","equipment":"discovery","solids":solids,
		"spawns":[{"id":"entry","feet":[0,0,-18],"yaw":PI*0.5}],
		"landmarks":[{"id":"maintenance_bay","feet":[-10,0,-17]},
			{"id":"grounded_approach","feet":[0,0,0]},
			{"id":"west_cover","feet":[-8,0,0]},
			{"id":"rear_flank","feet":[12,0,5]},
			{"id":"exit","feet":[0,0,20]}],
		"supplies":[
			{"id":"maintenance_arc","feet":[-10,0,-17],"claim":"personal","grant":{"kind":"weapon","weapon":"arc"}},
			{"id":"arrival_armor","feet":[-2,0,-18],"claim":"contested","grant":{"kind":"armor","amount":100}},
			{"id":"court_medical","feet":[-9,0,4],"claim":"contested","grant":{"kind":"health","amount":40}}],
		"encounters":[{"id":"court","regions":[{"min":[-20,0,-7.5],"max":[20,3,20]}],
			"enemies":[{"id":"court_assessor","kind":"assessor","feet":[8,4,0],"yaw":PI,
				"hover":{"volume":{"min":[7.5,3,-2],"max":[8.5,5,2]},"band":[3,5],
					"patrol":[[8,4,-1],[8,4,1]],"approach":[0,0,0]}}]}],
		"decorations":[{"solid":"maintenance_rack","face":"north","kind":"maintenance_sign","center":[0,0.5],"size":[3,0.8]},
			{"solid":"arrival_west","face":"south","kind":"strip_light","center":[0,1],"size":[4,0.2]},
			{"solid":"north_service_rack","face":"south","kind":"strip_light","center":[0,0.5],"size":[4,0.2]}]}
	var file: FileAccess = FileAccess.open("../server/maps/test/assessor_foundation_development.json",FileAccess.WRITE)
	if file == null or not file.store_string(JSON.stringify(document,"  ",true)+"\n"):
		push_error("author_assessor_development: source write failed")
		quit(1)
		return
	file.close()
	print("author_assessor_development: PASS, bounded hover, ordinary cover/flank, one finite forty-Cell find")
	quit(0)

func _add(solids: Array[Dictionary], id: String, minimum: Array, maximum: Array, surface: String = "concrete") -> void:
	solids.append({"id":id,"min":minimum,"max":maximum,"surface":surface})
