extends SceneTree
const PLAYER: String = "00000000-0000-0000-0000-000000001313"
var failures: int = 0
func _initialize() -> void:
	set_meta("fragr_automated",true)
	_run.call_deferred()
func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m13_mission_state: "+message)
static func fixture_map() -> Dictionary:
	var solids: Array = [
		{"min_x":-10,"max_x":-9,"min_z":0,"max_z":2,"bottom":0,"top":2},
		{"min_x":-10,"max_x":-9,"min_z":3,"max_z":5,"bottom":0,"top":2},
		{"min_x":-2,"max_x":2,"min_z":10,"max_z":12,"bottom":3.3,"top":3.6},
		{"min_x":2,"max_x":6,"min_z":-4,"max_z":-3,"bottom":0,"top":3}]
	var details: Array = [{"solid":3,"face":"south","center":[0,0],"size":[0.8,0.8],"kind":"terminal"},{"solid":2,"face":"up","center":[1.2,0],"size":[0.8,0.6],"kind":"lift_control"}]
	var release: Dictionary = {"decoration":0,"approach":[4,0,-1.5]}
	var departure: Dictionary = {"decoration":1,"approach":[0,3.6,11]}
	var objectives: Array = []
	for index: int in range(7):
		var action: Dictionary = {"kind":"arrival","feet":[0,0,0],"region":{"min":[-1,0,-1],"max":[1,2,1]}}
		if index == 4:
			action = {"kind":"shoot","solid":0,"approach":[-7,0,1],"aim":[-9,1.4,1]}
		elif index == 6:
			action = {"kind":"use","target":departure}
		objectives.append({"id":M13MissionState.OBJECTIVES[index],"action":action})
	return {"type":"map_info","map_id":1013,"map_name":"The Weight of Permission","geometry_version":2,"half_extent":20,"solids":solids,"presentation":{"ground":"concrete","solids":["enamel","service_steel","service_steel","enamel"],"decorations":details},
		"m13":{"objectives":objectives,"release":release,"departure":departure,"relay":0,"protected":[1],"hazard":{"min":[10,0,-10],"max":[13,2,-8]},"bypass":{"min":[10,0,-7],"max":[13,2,-5]},"cycle":{"period":160,"warning":40,"active":40},"deck":2,"parked_top":3.6,"lift_top":14.6,"inset_min":[-1.4,10.4],"inset_max":[1.4,11.6],"workers":[[3,0,0],[5,0,0],[7,0,0]],"worker_destinations":[[3,0,4],[5,0,4],[7,0,0]],"overseer":[9,0,0]}}
static func fixture_state(info: Dictionary, stage: int = 0, tick: int = 10) -> Dictionary:
	var order: Array[String] = M13MissionState.OBJECTIVES.duplicate()
	order.append("party_departed")
	var progress: Dictionary = {"completed":order.slice(0,stage),"challenges":{"workers_arrived":[false,false,false],"hazard_hurt":0,"supports_cleared":stage>=6},"relay_disabled":stage>=5,"overseer_surrendered":stage>=3,"worker_feet":info["m13"]["workers"].duplicate(true),"lift":{"phase":"arrived" if stage==8 else "moving" if stage==7 else "parked","top":14.6 if stage==8 else 3.6,"tick":tick,"returning":false},"hazard_phase":"idle"}
	if stage < 8:
		progress["current"]=info["m13"]["objectives"][stage].duplicate(true) if stage<7 else M13MissionState.departure_objective(info["m13"])
	return {"id":MissionState.M13_ID,"rules":{"difficulty":"standard","revision":4},"attempt":1,"phase":"departed" if stage==8 else "in_progress","changed_at":tick,"party":[{"id":PLAYER,"name":"Foundry visitor","ready":true,"alive":true,"aboard":stage>=6}],"prompts":[],"m13":progress}
func _run() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m13_fact_vectors.json"))
	var native_info: Dictionary = vectors["map_info"]
	_check(MapGeometry.validation_error(native_info).is_empty() and MissionState.map_error(native_info).is_empty(),"actual native foundry geometry crosses client boundary")
	_check(ArenaCover.venue_for(native_info)=="mars_foundry" and ArenaSky.preset_for(native_info["map_name"]).ambient_color==ArenaSky.mars_foundry().ambient_color,"canonical mission retains its authored Mars materials and lighting")
	var native_geometry: Dictionary = MissionState.geometry_for(native_info)
	var briefing: Dictionary = vectors["valid"][0].duplicate(true)
	briefing["state"]["phase"] = "briefing"
	briefing["state"]["party"] = []
	_check(M13MissionState.validation_error(briefing,native_geometry).is_empty(),"wire-decoded briefing accepts numeric zero without deep dictionary type equality")
	briefing["state"]["m13"]["challenges"]["hazard_hurt"] = 1
	_check(not M13MissionState.validation_error(briefing,native_geometry).is_empty(),"briefing still rejects invented pre-readiness harm")
	for entry: Dictionary in vectors["valid"]:
		_check(M13MissionState.validation_error(entry,native_geometry).is_empty(),"native "+str(entry["name"]))
	for entry: Dictionary in vectors["invalid"]:
		_check(not M13MissionState.validation_error(entry,native_geometry).is_empty(),"native refuses "+str(entry["name"]))
	var network: Node = preload("res://scripts/net_client.gd").new()
	var wire_errors: Array[String] = []
	var accepted: Array[Dictionary] = []
	network.server_error.connect(func(reason: String) -> void: wire_errors.append(reason))
	network.mission_received.connect(func(value: Dictionary) -> void: accepted.append(value))
	network._handle_message(JSON.stringify(native_info))
	var live: Dictionary = vectors["valid"][0].duplicate(true)
	live.erase("name")
	live["type"]="mission"
	network._handle_message(JSON.stringify(live))
	_check(wire_errors.is_empty() and accepted.size()==2 and not accepted.back().is_empty(),"actual MapInfo then mission passes live network boundary")
	var drift: Dictionary = native_info.duplicate(true)
	drift["solids"][int(drift["m13"]["deck"])]["top"]+=0.5
	network._handle_message(JSON.stringify(drift))
	_check(wire_errors.size()==1 and network.mission.is_empty(),"live map drift closes rather than rebinding lift identity")
	network.free()
	var info: Dictionary = fixture_map()
	var geometry: Dictionary = MissionState.geometry_for(info)
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(),"strict registered foundry map")
	for stage: int in range(9):
		var value: Dictionary = fixture_state(info,stage)
		_check(M13MissionState.validation_error({"tick":10,"state":value},geometry).is_empty(),"ordered required stage %d" % stage)
		_check(not M13MissionState.brief_completed(value["m13"]["challenges"],"assisted"),"optional workers never inferred from required completion")
	var first: Dictionary = fixture_state(info,3)
	var released: Dictionary = first.duplicate(true)
	released["m13"]["challenges"]["workers"]=M13MissionState.RESPONSES.duplicate()
	_check(M13MissionState.validation_error({"tick":10,"state":released},geometry).is_empty(),"physical release keeps separate voluntary choices")
	for bad: Dictionary in [{"workers":null},{"workers_arrived":[false,false,true]},{"hazard_hurt":-1},{"workers":["volunteered","volunteered","volunteered"]}]:
		var broken: Dictionary = released.duplicate(true)
		broken["m13"]["challenges"].merge(bad,true)
		_check(not M13MissionState.validation_error({"tick":10,"state":broken},geometry).is_empty(),"reject contradictory choice/hazard receipt")
	var arrival: Dictionary = released.duplicate(true)
	arrival["m13"]["challenges"]["workers_arrived"]=[true,false,false]
	_check(not M13MissionState.validation_error({"tick":10,"state":arrival},geometry).is_empty(),"arrival requires actual destination feet")
	arrival["m13"]["worker_feet"][0]=info["m13"]["worker_destinations"][0].duplicate()
	_check(M13MissionState.validation_error({"tick":10,"state":arrival},geometry).is_empty(),"accepted worker arrival uses destination")
	arrival["m13"]["worker_feet"][0][2] -= 0.035
	_check(M13MissionState.validation_error({"tick":10,"state":arrival},geometry).is_empty(),"server arrival receipt permits its actual stopped feet within native tolerance")
	arrival["m13"]["worker_feet"][0][0] += 0.2
	_check(not M13MissionState.validation_error({"tick":10,"state":arrival},geometry).is_empty(),"worker cannot leave its registered physical route")
	arrival["m13"]["worker_feet"][0] = [3,0,2]
	arrival["m13"]["challenges"]["workers_arrived"][0] = false
	_check(not M13MissionState.validation_error({"tick":10,"state":released},geometry,{"tick":10,"state":arrival}).is_empty(),"worker cannot reverse accepted route progress within an attempt")
	arrival["m13"]["worker_feet"][0] = [3,0,4]
	arrival["m13"]["challenges"]["workers_arrived"][0] = true
	var parked: Dictionary = fixture_state(info,7)
	parked["m13"]["challenges"]["workers"]=M13MissionState.RESPONSES.duplicate()
	parked["m13"]["lift"]["phase"]="parked"
	parked["prompts"]=[{"player_id":PLAYER,"kind":"objective_use"}]
	_check(M13MissionState.validation_error({"tick":10,"state":parked},geometry).is_empty(),"returned lift allows fresh whole-party use without undoing boarded receipt")
	parked["party"][0]["aboard"]=false
	_check(not M13MissionState.validation_error({"tick":10,"state":parked},geometry).is_empty(),"incomplete party cannot invent boarding prompt")
	var previous: Dictionary = {"tick":10,"state":released}
	_check(not M13MissionState.validation_error({"tick":10,"state":first},geometry,previous).is_empty(),"same attempt cannot erase release")
	first["attempt"]=2
	_check(M13MissionState.validation_error({"tick":10,"state":first},geometry,previous).is_empty(),"new attempt can restore foundry state")
	for key: String in ["relay","deck"]:
		var broken: Dictionary = info.duplicate(true)
		broken["m13"][key]=999
		_check(not MissionState.map_error(broken).is_empty(),"reject unregistered "+key)
	var overlap: Dictionary = info.duplicate(true)
	overlap["m13"]["bypass"]=overlap["m13"]["hazard"].duplicate(true)
	_check(not MissionState.map_error(overlap).is_empty(),"hazard cannot consume its permanent bypass")
	var changed: Dictionary = geometry.duplicate(true)
	changed["solids"][2]["top"]=4
	_check(not M13MissionState.same_contract(geometry,changed),"map replacement cannot silently move registered deck")
	var predictor := LocalPrediction.new()
	predictor.configure_map(info)
	var moving: Dictionary = fixture_state(info,7)
	moving["m13"]["lift"]["top"]=6.0
	var before_lift: Dictionary = {"tick":10,"state":moving.duplicate(true)}
	var jumped_lift: Dictionary = moving.duplicate(true)
	jumped_lift["m13"]["lift"]["tick"]=11
	jumped_lift["m13"]["lift"]["top"]=7.0
	_check(not M13MissionState.validation_error({"tick":11,"state":jumped_lift},geometry,before_lift).is_empty(),"accepted tick interval cannot teleport the lift")
	jumped_lift["m13"]["lift"]["top"]=5.95
	jumped_lift["m13"]["lift"]["returning"]=true
	_check(not M13MissionState.validation_error({"tick":11,"state":jumped_lift},geometry,before_lift).is_empty(),"a moving sample cannot claim the return direction")
	jumped_lift["m13"]["lift"]["phase"]="returning"
	_check(M13MissionState.validation_error({"tick":11,"state":jumped_lift},geometry,before_lift).is_empty(),"bounded physical descent remains accepted")
	var sparse: Dictionary = fixture_state(info,7,60)
	sparse["m13"]["lift"]["phase"]="parked"
	_check(M13MissionState.validation_error({"tick":60,"state":sparse},geometry,before_lift).is_empty(),"sparse delivery may skip the complete return before a parked sample")
	var initial_parked: Dictionary = fixture_state(info,7,10)
	initial_parked["m13"]["lift"]["phase"]="parked"
	sparse["m13"]["lift"]["phase"]="returning"
	sparse["m13"]["lift"]["returning"]=true
	sparse["m13"]["lift"]["top"]=5.0
	_check(M13MissionState.validation_error({"tick":60,"state":sparse},geometry,{"tick":10,"state":initial_parked}).is_empty(),"sparse delivery may skip ascent before observing a returning deck above its start")
	predictor.apply_m13(moving)
	_check(predictor._foundry_moving and predictor.arena["solids"][2]["top"]==6.0 and not predictor.active(),"moving deck follows authoritative collision and suspends speculative player carry")
	moving["m13"]["lift"]["phase"]="returning"
	moving["m13"]["lift"]["returning"]=true
	moving["m13"]["lift"]["top"]=5.0
	predictor.apply_m13(moving)
	_check(predictor.arena["solids"][2]["top"]==5.0,"supported return follows descending accepted collision")
	predictor.apply_m13(fixture_state(info,8))
	_check(not predictor._foundry_moving and predictor.arena["solids"][2]["top"]==14.6,"arrived deck returns to ordinary prediction")
	var cover := ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	cover.apply_m13(moving)
	_check(absf(cover._solid_views[2].position.y-4.85)<0.001,"rendered deck centre follows accepted descending top and original thickness")
	var host_found: bool = false
	for child: Node in cover.get_children():
		if child.has_meta("host_solid") and int(child.get_meta("host_solid"))==2:
			host_found=true
			_check((child as Node3D).position.is_equal_approx(child.get_meta("baseline_position")+Vector3(0,1.4,0)),"lift control panel moves with the accepted deck")
	_check(host_found,"registered physical lift panel is actually present")
	cover.queue_free()
	var foundry := M13Foundry.new()
	root.add_child(foundry)
	foundry.configure_map(info)
	foundry.apply_state(released)
	_check(foundry.state_applied==1 and foundry._people.size()==3 and foundry._overseer.visible and not foundry._restraints[0].visible,"release presents three conscious workers and a surrendered overseer")
	_check(foundry._relay_label.text == tr("M13_RELAY_ACTIVE") and foundry._relay.position.x > float(info["solids"][0]["max_x"]),"relay cue faces the ordinary approach instead of hiding above the housing")
	foundry.apply_state(arrival)
	_check(foundry._people[0].position==Vector3(3,0,4) and foundry._people[2].position==Vector3(7,0,0),"worker positions follow actual travel while refusal stays at work")
	var warning: Dictionary = arrival.duplicate(true)
	warning["m13"]["lift"]["tick"]=100
	warning["m13"]["hazard_phase"]="warning"
	foundry.apply_state(warning)
	_check(foundry._hazard_label.text==tr("M13_HAZARD_WARNING") and not foundry._hazard_label.double_sided,"floor warning uses fitted keyed copy on its actual machine zone")
	foundry.apply_state({"id":MissionState.M13_ID,"m13":{}})
	_check(foundry.state_applied==3,"malformed presentation input cannot alter accepted scene")
	foundry.clear_map()
	_check(foundry.get_child_count()==0 and foundry._geometry.is_empty(),"retirement removes foundry state")
	foundry.queue_free()
	var hud := MissionHud.new()
	root.add_child(hud)
	hud.apply(released,PLAYER)
	_check(hud._copy.text==tr("M13_OBJECTIVE_FREIGHT_LOOP_SECURED") and hud._evac_badge.text==tr("M13_WORKERS_CHOSE"),"HUD retains required fight and optional voluntary choices separately")
	await process_frame
	await process_frame
	_check(hud._evac_badge.get_line_count()>1 and hud._evac_badge.position.x+hud._evac_badge.size.x<=hud.get_viewport_rect().size.x-23.0,"worker choices wrap inside the actual HUD width instead of clipping at the right edge")
	hud.queue_free()
	_check(LocalMatch.MISSION_GAMEPLAY.get(MissionState.M13_ID)==47 and LocalMatch.CAMPAIGN_COMPLETE=="still_here" and StoryScene.exists("m13_arrival"),"frontend capability and built boundary agree")
	_check(not LocalMatch.parse_run_preview('{"status":"ready","mission":"weight_of_permission","difficulty":"standard","continues":2,"attempt":1,"pending_continue":false,"body":null}'.to_ascii_buffer()).is_empty(),"saved foundry preview accepted without refill assumption")
	_check(not LocalMatch.parse_run_preview('{"status":"ready","mission":"launch_authority","difficulty":"standard","continues":2,"attempt":1,"pending_continue":false,"body":null}'.to_ascii_buffer()).is_empty(),"completed foundry opens the built launch works")
	await process_frame
	await process_frame
	if failures==0:
		print("test_m13_mission_state: PASS ordered facts, voluntary workers, bypass, lift return, presentation and saved frontend")
	quit(0 if failures==0 else 1)
