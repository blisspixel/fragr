extends "res://scripts/qa_tour.gd"

## Real local M01 completion, using the existing unweakened ordinary-input
## records route. Run with a framebuffer and FRAGR_QA_DIR set to isolated output.
var _owned: LocalMatch
var _result_run_dir: String = ""
var _result_settings: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_result_settings = "user://campaign-results-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", _result_settings)
	set_meta("fragr_records_path", "")
	MouseCapture.release()
	_run.call_deferred()

func _run() -> void:
	var output: String = OS.get_environment("FRAGR_QA_DIR")
	if not output.is_absolute_path():
		push_error("campaign_results_live: absolute isolated FRAGR_QA_DIR required")
		quit(1)
		return
	_result_run_dir = output.path_join("run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", _result_run_dir)
	var preferences: FragrSettings = FragrSettings.new(_result_settings)
	preferences.set_value("video", "display_mode", 0)
	if preferences.save_to_disk() != OK:
		push_error("campaign_results_live: isolated settings could not be saved")
		quit(1)
		return
	_owned = LocalMatch.for_tree(self)
	if not _owned.start_mission("standard", "new", MissionState.ID):
		push_error("campaign_results_live: owned local campaign failed to start")
		quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 20000
	while _owned.state == LocalMatch.State.STARTING and Time.get_ticks_msec() < deadline:
		await process_frame
	if _owned.state != LocalMatch.State.RUNNING:
		push_error("campaign_results_live: owned campaign did not become ready")
		quit(1)
		return
	set_meta("fragr_boot", {"mode": "campaign", "host": _owned.url, "run_mode": "new"})
	await super._run()

func _load_manifest() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m01-records.json"))
	return value if value is Dictionary else {}

func _wait_live_joined_fighter(state_name: String) -> bool:
	var manager: Node = _game_manager()
	if manager != null and is_instance_valid(manager.opening):
		manager.opening.finish()
	return await super._wait_live_joined_fighter(state_name)

func _use_mission_control(expected_phase: String) -> void:
	await super._use_mission_control(expected_phase)
	if expected_phase != "departed" or _failed:
		return
	var manager: Node = _game_manager()
	var deadline: int = Time.get_ticks_msec() + 3000
	while manager.net_client.record.get("status") != "complete" and Time.get_ticks_msec() < deadline:
		await process_frame
	if is_instance_valid(manager.interlude):
		manager.interlude.finish()
	while not is_instance_valid(manager.campaign_results) and Time.get_ticks_msec() < deadline:
		await process_frame
	var result: Dictionary = CampaignResult.select(manager.net_client.record, manager.net_client.mission["state"], manager.net_client.player_id)
	if result.is_empty() or result["elapsed_ticks"] == null or not is_instance_valid(manager.campaign_results) \
		or manager.campaign_results.result != result or manager._onward_available():
		push_error("campaign_results_live: genuine departure did not present matching results before onward")
		_failed = true
	else:
		print("campaign_results_live: actual completion tally ", JSON.stringify(result))

func _observed_state() -> Dictionary:
	var observed: Dictionary = super._observed_state()
	var manager: Node = _game_manager()
	if manager != null and is_instance_valid(manager.campaign_results):
		observed["campaign_result"] = manager.campaign_results.result.duplicate(true)
	return observed

func _retire_scene() -> void:
	await super._retire_scene()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_result_run_dir.path_join("run.json")))
	if not saved is Dictionary or saved.get("step", {}).get("kind") != "awaiting_mission" \
		or saved.get("step", {}).get("next_mission") != MissionState.M02_ID:
		push_error("campaign_results_live: completion failed to retain actual campaign carry")
		_failed = true
	elif not _failed:
		print("campaign_results_live: PASS actual M01 completion, rendered tally and durable carry")

func _finalize() -> void:
	if is_instance_valid(_owned):
		_owned.stop()
	OS.unset_environment("FRAGR_RUN_DIR")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_result_settings))
	super._finalize()
