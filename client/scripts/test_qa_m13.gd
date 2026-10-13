extends SceneTree
var failures: int = 0
func _check(value: bool,message: String) -> void:
	if not value:
		failures+=1
		push_error("test_qa_m13: "+message)
func _initialize() -> void:
	var script: Script = load("res://scripts/qa_tour.gd")
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m13_weight_of_permission.json"))
	_check(script.valid_walks(tour["states"]),"ordinary foundry route has bounded QA actions")
	var found: Dictionary = {}
	for state: Dictionary in tour["states"]:
		found[state["name"]]=state
		_check(script.combat_travel_enabled(tour,state)==state.has("combat_travel_targets"),"travel fights only named current guards, never future lesson enemies")
	_check(found.has("m13_first_rocket") and found["m13_first_rocket"].get("weapon")=="Rocket" and found["m13_first_rocket"].get("single_shot")==true,"first lesson uses a finite real rocket")
	_check(found["m13_worker_release"].get("interact")=="workers_released" and found["m13_lift_boarded"].get("interact")=="lift_boarded","optional release and physical lift retain distinct ordinary controls")
	_check(found["m13_lift_boarded"].get("strip_frames")==8 and found["m13_lift_boarded"].get("strip_interval_seconds")==0.25,"ordinary accepted boarding records bounded live ascent before the departure still")
	_check(found["m13_relay_disabled"].get("trigger")=="fire" and found["m13_lift_daylight"].get("expect_phase")=="departed","resolved relay and completed ride require observed facts")
	for bad: Dictionary in [{"wait_ticks":401},{"wait_ticks":-1},{"expect_phase":"made_up"},{"expect_m13_lift_phase":"teleported"},{"expect_m13_workers_arrived":[true,true,true]},{"expect_m13_completed":["party_departed"]},{"expect_m13_hazard_hurt":-1}]:
		_check(not script.valid_m13_expectations(bad),"bad foundry QA expectation rejected")
	if failures==0:
		print("test_qa_m13: PASS ordinary finite route, physical controls, bounded waits and strict receipts")
	quit(0 if failures==0 else 1)
