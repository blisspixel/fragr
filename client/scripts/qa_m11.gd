extends "res://scripts/qa_tour.gd"

const LocalFixture = preload("res://scripts/test_m11_local.gd")
var _owned: LocalMatch
var _previous_server: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	_prepare.call_deferred()

func _prepare() -> void:
	var output: String = OS.get_environment("FRAGR_QA_DIR")
	if output.is_empty():
		push_error("qa_m11: FRAGR_QA_DIR is required for isolated evidence")
		quit(1)
		return
	var runs: String = output.path_join("local-run")
	DirAccess.make_dir_recursive_absolute(runs)
	var file: FileAccess = FileAccess.open(runs.path_join("run.json"), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(LocalFixture.completed_ship()) + "\n  \n")
	file.close()
	_previous_server = OS.get_environment("FRAGR_SERVER")
	OS.set_environment("FRAGR_RUN_DIR", runs)
	_owned = LocalMatch.for_tree(self)
	await process_frame
	if not _owned.start_mission("standard", "resume", MissionState.M11_ID):
		quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 20000
	while _owned.state == LocalMatch.State.STARTING and Time.get_ticks_msec() < deadline:
		await process_frame
	if _owned.state != LocalMatch.State.RUNNING:
		push_error("qa_m11: owned native child did not become ready")
		quit(1)
		return
	OS.set_environment("FRAGR_SERVER", _owned.url)
	OS.set_environment("FRAGR_QA_MANIFEST", "res://qa/m11_right_of_search.json")
	await _run()

func _finalize() -> void:
	if is_instance_valid(_owned):
		_owned.stop()
	if _previous_server.is_empty():
		OS.unset_environment("FRAGR_SERVER")
	else:
		OS.set_environment("FRAGR_SERVER", _previous_server)
	OS.unset_environment("FRAGR_RUN_DIR")
	super._finalize()
