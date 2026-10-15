extends SceneTree

var failures: int = 0

func _check(value: bool,message: String) -> void:
	if not value:
		failures += 1
		push_error("test_qa_m14: "+message)

func _initialize() -> void:
	var script: Script = load("res://scripts/qa_tour.gd")
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m14_launch_authority.json"))
	_check(script.valid_walks(tour["states"]),"connected candidate infantry route uses bounded QA actions")
	_check(QaCombat.valid_capture_interval({}),"default capture cadence stays available")
	for interval: Variant in [150,1000,2000.0]:
		_check(script.valid_walks([{"combat":{"capture_interval_ms":interval}}]),"bounded integral capture interval accepted through actual manifest boundary")
	for interval: Variant in [null,true,"1000",149,2001,1000.5,INF,NAN]:
		_check(not script.valid_walks([{"combat":{"capture_interval_ms":interval}}]),"malformed or unbounded capture interval refused by actual manifest boundary")
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m14_fact_vectors.json"))
	for map_key: String in ["map_info","fallen_map_info"]:
		var arena: Dictionary = {"solids":golden[map_key]["solids"]}
		for point: Vector2 in [Vector2(-1,28),Vector2(-1,38),Vector2(-1,50),Vector2(13,50)]:
			_check(not MoveStep.arena_blocked(arena,point.x,point.y),"battle escape and support search endpoints clear native "+map_key+" at "+str(point))
	var found: Dictionary = {}
	for state: Dictionary in tour["states"]:
		found[state["name"]] = state
		_check(script.combat_travel_enabled(tour,state)==state.has("combat_travel_targets"),"travel fire remains limited to named current guards")
	_check(found["m14_walker_and_supports"].get("m14_combat")==true and not found["m14_walker_and_supports"].has("walker_combat"),"connected battle uses its own support-aware probe")
	_check(found["m14_walker_and_supports"].get("expect_m14_completed",[]).size()==6 and not found["m14_gantry_defense"].has("combat"),"continuous battle clears final gantry guards before pausing for a still")
	_check(found["m14_pad_control"].get("interact")=="party_departed" and found["m14_pad_control"].get("expect_phase")=="departed","terminal exit requires ordinary Use and accepted departure")
	# This approach must go around the actual lander and gantry, not through a
	# visually open pad that still has a registered hull at ordinary eye height.
	var world: Dictionary = {"half":golden["map_info"]["half_extent"],"solids":golden["map_info"]["solids"]}
	var body: Dictionary = MoveStep.make_state(40,16,0)
	for goal: Array in found["m14_inner_apron_flank"]["walk_to"]:
		var arrived: bool = false
		for tick: int in range(300):
			if Vector2(body.x-goal[0],body.z-goal[2]).length()<0.3 and absf(body.y-goal[1])<0.03:
				arrived = true
				break
			var yaw: float = atan2(goal[2]-body.z,goal[0]-body.x)
			body = MoveStep.live_step(body,MoveStep.make_input(true,false,false,false,yaw),MoveStep.TOP_SPEED,MoveStep.DT_LIVE,world)
		_check(arrived,"shared movement clears native lander circuit toward "+str(goal))
	var valid: Dictionary = {"expect_m14_completed":["arrival","depot_secured"],"expect_m14_support_stage":0,"expect_m14_first_cycle_complete":false,"expect_m14_machine_fallen":false,"expect_m14_jeep_id":1,"expect_m14_depot_secured":true,"expect_m14_walker_disabled":false,"expect_m14_jeep_preserved":true,"expect_m14_on_foot":true}
	_check(script.valid_walks([valid]),"registered launch receipts are accepted by the actual tour boundary")
	for bad: Dictionary in [{"expect_m14_completed":["party_departed"]},{"expect_m14_completed":["arrival","arrival"]},{"expect_m14_completed":true},{"expect_m14_support_stage":-1},{"expect_m14_support_stage":3},{"expect_m14_support_stage":1.5},{"expect_m14_support_stage":true},{"expect_m14_machine_fallen":1},{"expect_m14_first_cycle_complete":"true"},{"expect_m14_jeep_id":0},{"expect_m14_jeep_id":true},{"expect_m14_jeep_preserved":null},{"expect_m14_on_foot":1},{"expect_m14_walker_disabed":true}]:
		_check(not script.valid_m14_expectations(bad),"malformed or misspelled launch receipt rejected")
		_check(not script.valid_walks([bad]),"tour cannot silently ignore a malformed launch receipt")
	if failures == 0:
		print("test_qa_m14: PASS strict launch expectations through tour boundary")
	quit(0 if failures == 0 else 1)
