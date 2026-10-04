extends SceneTree

var failures: int = 0

class Beneath extends Node:
	var heard: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_pressed():
			heard += 1

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_campaign_results: " + message)

func _record() -> Dictionary:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/player_record.json"))
	record["map_id"] = 1001
	record["map_name"] = "Recall Notice"
	record["scope"] = {"kind": "mission", "mission": MissionState.ID, "attempt": 2,
		"rules": {"revision": MissionState.RULES_REVISION, "difficulty": "standard"}, "run": null}
	record["mission_elapsed_ticks"] = 20
	record["total"]["deaths"] = 1
	record["total"]["secrets"] = 1
	return record

func _state() -> Dictionary:
	return {"id": MissionState.ID, "attempt": 2, "phase": "departed",
		"rules": {"revision": MissionState.RULES_REVISION, "difficulty": "standard"}}

func _run() -> void:
	var record: Dictionary = _record()
	var selected: Dictionary = CampaignResult.select(record, _state(), record["player_id"])
	_check(not selected.is_empty(), "completed authoritative record is selected")
	_check(selected["attempt"] == {"kills": 1, "secrets": 0, "deaths": 0}, "successful attempt uses resolved columns")
	_check(selected["total"] == {"kills": 1, "secrets": 1, "deaths": 1}, "retry effort retains distinct secrets and earlier deaths")
	_check(CampaignResult.elapsed_text(selected) == "0:01" and not selected.has("par"), "server time is formatted without invented par")
	var explosive: Dictionary = record.duplicate(true)
	for scope: String in ["total", "attempt"]:
		explosive[scope]["grenades"] = {"attacks": 1, "damaging_attacks": 1, "kills": 2, "hp_damage": 100, "armor_damage": 0}
		explosive[scope]["mines"] = {"attacks": 1, "damaging_attacks": 1, "kills": 3, "hp_damage": 100, "armor_damage": 0}
	_check(CampaignResult.select(explosive, _state(), record["player_id"])["attempt"]["kills"] == 6, "resolved explosive kills share the tally without separate combat counting")
	for malformed: Variant in [-1, 0.5, "20", 22, null, true]:
		var broken: Dictionary = record.duplicate(true)
		broken["mission_elapsed_ticks"] = malformed
		_check(CampaignResult.select(broken, _state(), record["player_id"]).is_empty(), "malformed timing is refused: " + str(malformed))
	var active: Dictionary = record.duplicate(true)
	active.erase("mission_elapsed_ticks")
	active["status"] = "active"
	_check(CampaignResult.select(active, _state(), record["player_id"]).is_empty(), "active record cannot claim completion")
	_check(CampaignResult.select(record, {"id": MissionState.ID, "attempt": 2, "phase": "reach_lift"}, record["player_id"]).is_empty(), "record alone cannot override mission state")
	_check(CampaignResult.select(record, {"id": MissionState.ID, "attempt": 3, "phase": "departed"}, record["player_id"]).is_empty(), "old attempt cannot become a new tally")
	var wrong_rules: Dictionary = _state()
	wrong_rules["rules"]["difficulty"] = "severe"
	_check(CampaignResult.select(record, wrong_rules, record["player_id"]).is_empty(), "a differently configured mission cannot use the record")
	var rewritten: Dictionary = record.duplicate(true)
	rewritten["mission_elapsed_ticks"] = 19
	_check(not PlayerRecord.validation_error(rewritten, record["player_id"], record).is_empty(), "terminal timing cannot be rewritten")
	var legacy: Dictionary = record.duplicate(true)
	legacy.erase("mission_elapsed_ticks")
	_check(not CampaignResult.select(legacy, _state(), record["player_id"]).is_empty(), "legacy completion remains usable")
	_check(CampaignResult.elapsed_text(CampaignResult.select(legacy, _state(), record["player_id"])) == tr("RESULT_TIME_UNAVAILABLE"), "absent historical time is unavailable")
	await _manager_order(record, false)
	await _manager_order(record, true)
	if failures == 0:
		print("test_campaign_results: PASS strict completion, retry counts, time, story, order, input and retirement")
	quit(0 if failures == 0 else 1)

func _manager_order(record: Dictionary, record_first: bool) -> void:
	# Keep the manager outside the tree, as the existing departure-hook test
	# does. Its actual presenter enters the tree and receives ordinary input.
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var owned: LocalMatch = LocalMatch.new()
	var net: Node = load("res://scripts/net_client.gd").new()
	manager.local_match = owned
	manager.net_client = net
	manager.is_human_player = true
	manager.records = PlayerRecords.new("")
	net.player_id = record["player_id"]
	if record_first:
		net.record = record.duplicate(true)
	else:
		net.mission = {"state": _state()}
	manager._try_campaign_results()
	_check(manager.campaign_results == null, "one half of completion does not present")
	net.record = record.duplicate(true)
	net.mission = {"state": _state()}
	manager._try_campaign_results()
	_check(manager.interlude != null and manager.campaign_results == null, "departure story precedes tally in either wire order")
	Input.action_press("ui_accept")
	manager.interlude.finish()
	var view: CampaignResults = manager.campaign_results
	_check(view != null and not manager._onward_available(), "tally blocks onward after story")
	manager.remove_child(view)
	root.add_child(view)
	var beneath: Beneath = Beneath.new()
	root.add_child(beneath)
	await process_frame
	_check(not view.armed, "held story dismissal cannot arm tally")
	view.finish()
	_check(not view.finished, "held input cannot dismiss tally")
	Input.action_release("ui_accept")
	await process_frame
	_check(view.armed, "release arms the result control")
	var press: InputEventAction = InputEventAction.new()
	press.action = "ui_accept"
	press.pressed = true
	Input.action_press("ui_accept")
	Input.parse_input_event(press)
	await process_frame
	# Input dispatch and queue_free finish at separate frame boundaries.
	# Bound retirement explicitly rather than assuming the first resumed frame.
	for frame: int in range(2):
		if not is_instance_valid(view):
			break
		await process_frame
	_check(not is_instance_valid(view) and manager.campaign_results == null, "fresh input closes and retires actual tally")
	_check(beneath.heard == 0, "tally dismissal consumes the actual viewport input")
	manager._arm_onward()
	_check(not manager._onward_armed, "tally dismissal cannot also arm onward")
	Input.action_release("ui_accept")
	# Durable onward needs a completed run; the result hook also serves practice.
	net.mission["state"]["run"] = {"status": "complete"}
	manager._arm_onward()
	_check(manager._onward_armed, "released input permits the existing onward prompt")
	manager._try_campaign_results()
	_check(manager.campaign_results == null, "duplicate completion cannot replay tally")
	net.record["round"] = 2
	manager._try_campaign_results()
	var retiring: CampaignResults = manager.campaign_results
	_check(retiring != null, "a new record identity can present a new result")
	manager.remove_child(retiring)
	root.add_child(retiring)
	manager._close_campaign_results()
	_check(retiring.is_queued_for_deletion(), "disconnect cleanup actually queues the live result")
	_check(manager.campaign_results == null, "world teardown retires tally")
	beneath.queue_free()
	manager.local_match = null
	manager.net_client = null
	manager.free()
	net.free()
	owned.free()
	await process_frame
