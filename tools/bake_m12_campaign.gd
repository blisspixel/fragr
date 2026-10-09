extends SceneTree
## Canonical connected habitat derived from the frozen development geometry.
const STAIR_ARCHITECTURE: Script = preload("res://../tools/author_campaign_stairs.gd")
func _initialize() -> void:
	var source := "res://../server/maps/test/m12_habitat_development.json"
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	map.map_id = 1012
	map.version = int(map.version)
	map.name = "Terms of Cooperation"
	# Keep original pump IDs and source indices stable.
	for solid in map.solids:
		if solid.id == "shelter_frontage":
			solid.min = [28.2, 0.3, 18.0]
	for enemy in map.encounters[1].enemies:
		if enemy.kind == "heavy_sweeper":
			enemy.armor = 100
	map.encounters[2].enemies = [
		_enemy("greenhouse_clerk_west", "clerk", [17.3,0.3,6.2]),
		_enemy("greenhouse_clerk_east", "clerk", [18.7,0.3,6.2]),
		_enemy("greenhouse_clerk_north", "clerk", [18.0,0.3,7.5]),
		_flying("greenhouse_assessor", "assessor", [18.0,4.2,6.5], [16.8,3.5,5.3], [19.2,5.0,7.7], [[17.7,4.2,6.2],[18.3,4.4,6.8]], [12.0,0.3,7.0])
	]
	map.encounters[3].enemies.append(_flying("court_notary_west","notary",[-18.0,4.3,27.0],[-19.5,3.5,25.5],[-16.5,5.5,28.5],[[-19.0,4.3,26.0],[-17.0,4.6,28.0]],[-17.0,0.3,23.0]))
	for stock in map.supplies:
		if stock.grant.has("amount"):
			stock.grant.amount = int(stock.grant.amount)
		if stock.id == "bay_rail":
			stock.id = "bay_arc"
			stock.grant.weapon = "arc"
		if stock.id == "bay_cells":
			stock.claim = "contested"
			stock.grant.amount = 40
		if stock.id == "depot_medical":
			stock.id = "aid_medical"
			stock.feet = [1.8,0.3,31.0]
	map.supplies.append({"id":"aid_cells","feet":[-1.8,0.3,31.0],"grant":{"kind":"ammo","pool":"cells","amount":24},"claim":"contested"})
	map.supplies.append({"id":"aid_armor","feet":[-1.8,0.3,32.0],"grant":{"kind":"armor","amount":50},"claim":"contested"})
	_box(map,"shelter_south",[20.0,0.3,18.0],[28.2,4.5,18.3],"enamel")
	_box(map,"shelter_north",[20.0,0.3,29.7],[28.2,4.5,30.0],"enamel")
	_box(map,"shelter_front_south",[20.0,0.3,18.3],[20.3,4.5,24.8],"enamel")
	_box(map,"shelter_front_north",[20.0,0.3,28.0],[20.3,4.5,29.7],"enamel")
	_box(map,"shelter_roof",[20.0,4.5,18.0],[28.5,4.8,30.0],"enamel")
	_box(map,"shelter_control",[18.7,0.3,24.2],[19.0,2.7,24.6],"service_steel")
	_box(map,"worker_control",[-25.0,0.3,12.8],[-24.6,2.7,13.2],"service_steel")
	_box(map,"depot_commitment",[1.0,0.3,32.3],[1.4,2.7,32.7],"service_steel")
	_box(map,"depot_departure",[-1.4,0.3,33.3],[-1.0,2.7,33.7],"service_steel")
	_box(map,"shelter_door",[20.0,0.3,24.8],[20.3,3.3,28.0],"service_steel")
	map.m12 = {
		"objectives":[
			_arrival("market_secured",[0.0,0.3,-15.0],"market_defense"),
			_arrival("arc_found",[13.0,0.3,-8.5],"maintenance_defense"),
			_arrival("greenhouse_secured",[12.0,0.3,10.0],"greenhouse_defense"),
			_arrival("shelter_route_secured",[0.0,0.3,22.0],"court_defense"),
			_arrival("aid_force_arrived",[0.0,0.3,31.0],"court_defense"),
			{"id":"coalition_commitment","requires_encounter":"court_defense"}
		],
		"shelter_release":_panel("shelter_control","west",[17.2,0.3,24.4]),
		"worker_release":_panel("worker_control","east",[-23.1,0.3,13.0]),
		"commitment":_panel("depot_commitment","west",[-0.5,0.3,32.5]),
		"departure":_panel("depot_departure","east",[0.5,0.3,33.5]),
		"boarding":{"min":[-2.0,0.0,30.5],"max":[2.2,2.6,34.3]},
		"shelter_door":"shelter_door",
		"shelter_people":[[24.0,0.3,21.0],[26.0,0.3,23.0],[24.0,0.3,27.0]],
		"workers":[[-23.0,0.3,9.0],[-23.0,0.3,11.0],[-23.0,0.3,15.0]],
		"aid_vehicles":[{"id":"aid_west","feet":[-4.0,0.3,32.0],"yaw":PI/2.0},{"id":"aid_east","feet":[4.0,0.3,32.0],"yaw":PI/2.0}]
	}
	if not STAIR_ARCHITECTURE.append_enclosures(map,12):
		quit(1)
		return
	var file := FileAccess.open("res://../server/maps/m12-terms-of-cooperation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(map,"  ",true,true)+"\n")
	file.close()
	print("Canonical Terms of Cooperation authored: ",map.solids.size()," solids")
	quit()

func _box(map: Dictionary,id: String,low: Array,high: Array,surface: String) -> void:
	map.solids.append({"id":id,"min":low,"max":high,"surface":surface})
func _enemy(id: String,kind: String,feet: Array) -> Dictionary:
	return {"id":id,"kind":kind,"feet":feet,"yaw":PI*1.5}
func _flying(id: String,kind: String,feet: Array,low: Array,high: Array,patrol: Array,approach: Array) -> Dictionary:
	var e := _enemy(id,kind,feet)
	e.hover={"volume":{"min":low,"max":high},"band":[3.5,5.8],"patrol":patrol,"approach":approach}
	return e
func _arrival(id: String,feet: Array,group: String) -> Dictionary:
	return {"id":id,"arrival":{"min":[feet[0]-2.0,0.0,feet[2]-2.0],"max":[feet[0]+2.0,3.0,feet[2]+2.0]},"approach":feet,"requires_encounter":group}
func _panel(host: String,face: String,approach: Array) -> Dictionary:
	return {"panel":{"solid":host,"face":face,"kind":"terminal","center":[0.0,0.0],"size":[0.3,0.8]},"approach":approach}
