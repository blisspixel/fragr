extends SceneTree
const PLAYER: String = "00000000-0000-0000-0000-000000001212"
var failures: int = 0
func _initialize() -> void:
	set_meta("fragr_automated",true)
	_run.call_deferred()
func _check(value: bool,message: String) -> void:
	if not value:
		failures+=1
		push_error("test_m12_presentation: " + message)
static func fixture_map() -> Dictionary:
	var solids: Array = []
	var surfaces: Array = []
	for index: int in range(7):
		solids.append({"min_x":index*2,"max_x":index*2+1,"min_z":-4,"max_z":-3,"bottom":0,"top":3})
		surfaces.append("enamel")
	var details: Array = []
	var targets: Array = []
	for index: int in range(4):
		details.append({"solid":index,"face":"south","center":[0,0],"size":[0.3,0.8],"kind":"terminal"})
		targets.append({"decoration":index,"approach":[index*2+0.5,0,-1.5]})
	var objectives: Array = []
	for index: int in range(5):
		objectives.append({"id":M12MissionState.OBJECTIVES[index],"action":{"kind":"arrival","feet":[0,0,0],"region":{"min":[-1,0,-1],"max":[1,2,1]}}})
	objectives.append({"id":"coalition_commitment","action":{"kind":"use","target":targets[2]}})
	return {"type":"map_info","map_id":1012,"map_name":"Terms of Cooperation","geometry_version":2,"half_extent":20,
		"solids":solids,"presentation":{"ground":"concrete","solids":surfaces,"decorations":details},
		"m12":{"objectives":objectives,"shelter_release":targets[0],"worker_release":targets[1],"commitment":targets[2],"departure":targets[3],
			"boarding":{"min":[5,0,-2],"max":[8,2,0]},"shelter_door":6,"shelter_open":false,
			"shelter_people":[[3,0,0],[5,0,0],[7,0,0]],"workers":[[-3,0,0],[-5,0,0],[-7,0,0]],
			"pumps":[{"id":"west","solids":[0,1,2],"health":100},{"id":"east","solids":[3,4,5],"health":100}],
			"aid_vehicles":[{"feet":[-4,0,8],"yaw":0},{"feet":[4,0,8],"yaw":0}]}}
static func fixture_state(info: Dictionary) -> Dictionary:
	return {"id":MissionState.M12_ID,"rules":{"difficulty":"standard","revision":MissionState.RULES_REVISION},"attempt":1,"phase":"in_progress","changed_at":10,
		"party":[{"id":PLAYER,"name":"Habitat visitor","ready":true,"alive":true,"aboard":false}],"prompts":[],
		"m12":{"completed":[],"current":info["m12"]["objectives"][0].duplicate(true),"aid_vehicle_ids":[],
			"challenges":{"shelter_opened":false,"workers_released":false,"pump_health":[100,100],"assessor_wreck_union_kills":0}}}
func _run() -> void:
	var info: Dictionary = fixture_map()
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(),"shared map boundary accepts registered habitat geometry")
	var habitat := M12Habitat.new()
	root.add_child(habitat)
	habitat.configure_map(info)
	var shelter: WorldSign = habitat.get_node("Shelter") as WorldSign
	var aid: WorldSign = habitat.get_node("MutualAid") as WorldSign
	for sign: WorldSign in [shelter,aid]:
		_check(sign != null and not sign.double_sided and not sign.text.is_empty()
			and sign.text == WorldSign.localized(sign.message_key) and not sign.no_depth_test,
			"habitat copy is keyed, fitted, opaque-world-facing and never mirrored from the rear")
		var plate: MeshInstance3D = sign.get_node("Plate") as MeshInstance3D
		_check(plate.mesh is QuadMesh and sign.bounds.x < (plate.mesh as QuadMesh).size.x
			and sign.bounds.y < (plate.mesh as QuadMesh).size.y and plate.position.z < 0.0,
			"actual translated glyph bounds fit inside their existing-wall cosmetic plate")
	_check((shelter.basis.z).dot(Vector3(17.16,2.0,24.52)-shelter.position) > 0.0
		and (aid.basis.z).dot(Vector3(0.25,2.0,31.0)-aid.position) > 0.0,
		"actual occupied shelter and aid approaches see the front of each label")
	var first: Dictionary = fixture_state(info)
	habitat.apply_state(first)
	_check(habitat.state_applied == 1 and habitat._people.size() == 6 and habitat._pumps.size() == 2,"accepted geometry places exactly six civilians and two pump indicators")
	_check(not habitat._aid.visible,"decorative aid equipment stays absent until actual vehicle identities arrive")
	var positions: Array[Vector3] = []
	for person: CivilianFigure in habitat._people:
		positions.append(person.position)
	var invalid: Dictionary = first.duplicate(true)
	invalid["m12"]["aid_vehicle_ids"]=[1,2]
	habitat.apply_state(invalid)
	_check(habitat.state_applied == 1 and not habitat._aid.visible,"unearned aid facts cannot change presentation")
	var later: Dictionary = first.duplicate(true)
	later["m12"]["completed"]=M12MissionState.OBJECTIVES.slice(0,5)
	later["m12"]["current"]=info["m12"]["objectives"][5].duplicate(true)
	later["m12"]["aid_vehicle_ids"]=[1,2]
	later["m12"]["challenges"]["pump_health"]=[80,0]
	later["m12"]["challenges"]["first_pump_damage_at"]=40
	later["m12"]["challenges"]["shelter_route_secured_at"]=50
	later["m12"]["challenges"]["workers_released"]=true
	habitat.apply_state(later)
	_check(habitat.state_applied == 2 and habitat._aid.visible and habitat._aid.get_child_count() == 3,"actual aid identities reveal the three equipment cases")
	_check((habitat._pumps[0].material_override as StandardMaterial3D).albedo_color == Color("d2a65a") and (habitat._pumps[1].material_override as StandardMaterial3D).albedo_color == Color("a94d46"),"damaged and broken pump lights follow exact HP")
	for index: int in range(6):
		_check(habitat._people[index].position == positions[index],"release facts do not invent autonomous evacuation")
	var hud := MissionHud.new()
	root.add_child(hud)
	hud.apply(first,PLAYER)
	_check(hud._copy.text == tr("M12_OBJECTIVE_MARKET_SECURED"),"HUD follows the current required objective")
	_check(LocalMatch.MISSION_GAMEPLAY.get(MissionState.M12_ID) == 44 and StoryScene.exists("m12_arrival"),"local capability and story handoff agree")
	_check(ArenaSky.preset_for("Terms of Cooperation").ambient_color == ArenaSky.mars_habitat().ambient_color and ArenaCover.venue_for(info) == "mars_habitat","canonical habitat uses its own registered Mars presentation")
	habitat.clear_map()
	_check(habitat.get_child_count() == 0 and habitat._people.is_empty() and habitat._pumps.is_empty() and habitat._geometry.is_empty(),"map retirement removes every habitat presenter")
	habitat.queue_free()
	hud.queue_free()
	await process_frame
	await process_frame
	if failures == 0:
		print("test_m12_presentation: PASS accepted habitat facts, static civilian limits, pump HP, aid visibility, HUD and retirement")
	quit(0 if failures == 0 else 1)
