extends SceneTree
var failures: int = 0
func _check(value: bool,message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m12_mission_state: " + message)
func _initialize() -> void:
	var vectors: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m12_fact_vectors.json"))
	_check(vectors is Array and vectors.size() == 31,"shared habitat vectors are complete")
	for entry: Dictionary in vectors:
		_check(M12MissionState.facts_error(entry["state"],entry["phase"],int(entry["tick"])).is_empty() == entry["valid"],entry["id"])
		if entry.has("briefs"):
			for difficulty: String in entry["briefs"]:
				_check(M12MissionState.brief_completed(entry["state"]["challenges"],difficulty) == entry["briefs"][difficulty],entry["id"] + "/" + difficulty)
	var objectives: Array = []
	for index: int in range(5):
		objectives.append({"id":M12MissionState.OBJECTIVES[index],"action":{"kind":"arrival","region":{"min":[-1,0,-1],"max":[1,2,1]},"feet":[0,0,0]}})
	var use: Dictionary = {"decoration":2,"approach":[0,0,0]}
	objectives.append({"id":"coalition_commitment","action":{"kind":"use","target":use}})
	var g: Dictionary = {"objectives":objectives,"shelter_release":{"decoration":0,"approach":[0,0,0]},"worker_release":{"decoration":1,"approach":[0,0,0]},"commitment":use,"departure":{"decoration":3,"approach":[0,0,0]},"boarding":{"min":[-1,0,-1],"max":[1,2,1]},"shelter_door":6,"shelter_open":false,"shelter_people":[[3,0,0],[5,0,0],[7,0,0]],"workers":[[-3,0,0],[-5,0,0],[-7,0,0]],"pumps":[{"id":"west","solids":[0,1,2],"health":100},{"id":"east","solids":[3,4,5],"health":100}],"aid_vehicles":[{"feet":[-4,0,8],"yaw":0},{"feet":[4,0,8],"yaw":0}]}
	var solids: Array = []
	for index: int in range(7):
		solids.append({"min_x":float(index*2),"max_x":float(index*2+1),"min_z":-1.0,"max_z":1.0,"bottom":0.0,"top":3.0})
	var panels: Array = [{"kind":"terminal"},{"kind":"terminal"},{"kind":"terminal"},{"kind":"terminal"}]
	_check(M12MissionState.map_value_error(g,20.0,panels,solids).is_empty(),"registered habitat geometry")
	for key: String in ["shelter_release","worker_release","commitment","departure"]:
		var broken: Dictionary = g.duplicate(true)
		broken[key]["decoration"]=7
		_check(not M12MissionState.map_value_error(broken,20.0,panels,solids).is_empty(),key+" cannot invent a control")
	var broken: Dictionary = g.duplicate(true)
	broken["pumps"][1]["solids"][0]=0
	_check(not M12MissionState.map_value_error(broken,20.0,panels,solids).is_empty(),"pump hosts cannot overlap")
	for group: String in ["shelter_people","workers"]:
		broken=g.duplicate(true)
		broken[group][1]=broken[group][0]
		_check(not M12MissionState.map_value_error(broken,20.0,panels,solids).is_empty(),group + " cannot overlap living contacts")
	var contract: Dictionary = {"id":MissionState.M12_ID,"map_id":1012,"half_extent":20.0,"m12":g,"solids":solids,"presentation":{"decorations":panels}}
	var opened: Dictionary = contract.duplicate(true)
	opened["m12"]["shelter_open"]=true
	opened["solids"][6]["bottom"]=4.2
	opened["solids"][6]["top"]=7.2
	_check(M12MissionState.same_contract(contract,opened),"only the registered door raises")
	_check(M12MissionState.same_contract(opened,contract),"retry can return to the exact closed world")
	opened["solids"][1]["max_x"]+=0.1
	_check(not M12MissionState.same_contract(contract,opened),"unrelated collision cannot drift")
	var member: Dictionary = {"id":"00000000-0000-0000-0000-000000001212","name":"Habitat visitor","ready":true,"alive":true,"aboard":false}
	var message: Dictionary = {"tick":110,"state":{"id":MissionState.M12_ID,"rules":{"difficulty":"standard","revision":MissionState.RULES_REVISION},"attempt":1,"phase":"in_progress","changed_at":100,"party":[member],"prompts":[{"player_id":member["id"],"kind":"objective_use"}]}}
	for entry: Dictionary in vectors:
		if entry["id"] == "stage_3":
			message["state"]["m12"]=entry["state"].duplicate(true)
	message["state"]["m12"]["current"]=g["objectives"][3].duplicate(true)
	_check(M12MissionState.validation_error(message,contract).is_empty(),"released route exposes the physical optional worker control")
	message["state"]["m12"]["challenges"]["workers_released"]=true
	_check(not M12MissionState.validation_error(message,contract).is_empty(),"already used optional control cannot invent a prompt")
	for entry: Dictionary in vectors:
		if entry["id"] == "stage_6":
			message["state"]["m12"]=entry["state"].duplicate(true)
	message["state"]["m12"]["current"]={"id":"party_departed","action":{"kind":"use","target":g["departure"].duplicate(true)}}
	message["state"]["m12"]["challenges"]["workers_released"]=true
	message["state"]["m12"]["challenges"]["shelter_opened"]=true
	var opened_contract: Dictionary = contract.duplicate(true)
	opened_contract["m12"]["shelter_open"]=true
	_check(not M12MissionState.validation_error(message,opened_contract).is_empty(),"departure prompt requires the whole living party aboard")
	message["state"]["party"][0]["aboard"]=true
	_check(M12MissionState.validation_error(message,opened_contract).is_empty(),"actual all-party boarding permits the shared use")
	if failures == 0:
		print("test_m12_mission_state: PASS shared facts, optional briefs, pump bounds, aid identities and shelter worlds")
	quit(0 if failures == 0 else 1)
