extends SceneTree

const SERVER_HASH: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_mission_bests: " + message)

func _record(serial: int, ticks: int = 2400) -> Dictionary:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/player_record.json"))
	record["session_id"] = "00000000-0000-0000-0000-%012d" % serial
	record["tick"] = 10000
	record["map_id"] = 1001
	record["map_name"] = "Recall Notice"
	record["scope"] = {"kind": "mission", "mission": MissionState.ID, "attempt": 1,
		"rules": {"revision": MissionState.RULES_REVISION, "difficulty": "standard"}, "run": null}
	record["mission_elapsed_ticks"] = ticks
	return record

func _run() -> void:
	var store: PlayerRecords = PlayerRecords.new("")
	var first: Dictionary = _record(10)
	_check(store.accept(first, "local", SERVER_HASH) == OK, "first measured local completion is accepted")
	var comparison: Dictionary = store.mission_comparison(first, SERVER_HASH)
	_check(comparison == {"best_ticks": 2400, "previous_ticks": -1, "count": 1, "delta_ticks": 0}, "the current identity is not its own previous best")
	_check(CampaignResult.comparison_text(comparison) == "FIRST LOCAL BEST: 2:00.00", "first completion is labelled explicitly")
	var faster: Dictionary = _record(11, 2399)
	_check(store.accept(faster, "local", SERVER_HASH) == OK, "faster completion is retained")
	comparison = store.mission_comparison(faster, SERVER_HASH)
	_check(comparison["delta_ticks"] == -1 and comparison["count"] == 2 and comparison["best_ticks"] == 2399, "one authoritative tick establishes a new best")
	_check(CampaignResult.comparison_text(comparison) == "NEW LOCAL BEST: 1:59.95, faster by 0:00.05", "subsecond improvement is explained without rounding it to a tie")
	var tied: Dictionary = _record(12, 2399)
	_check(store.mission_comparison(tied, SERVER_HASH)["delta_ticks"] == 0, "exact ticks, rather than displayed seconds, define a tie")
	_check(CampaignResult.comparison_text(store.mission_comparison(tied, SERVER_HASH)) == "LOCAL BEST TIED: 1:59.95", "tie is explicit")
	var slower: Dictionary = _record(13, 2401)
	_check(CampaignResult.comparison_text(store.mission_comparison(slower, SERVER_HASH)) == "LOCAL BEST: 1:59.95, behind by 0:00.10", "slower completion shows its actual delta")
	_check(CampaignResult.precise_time(0) == "0:00.00" and CampaignResult.precise_time(72001) == "60:00.05", "zero and hour-scale times keep clock precision")
	_check(store.mission_comparison(first, "").is_empty(), "unknown source identity cannot claim a compatible best")
	_check(store.accept(first, "external", SERVER_HASH) == ERR_INVALID_DATA, "remote records cannot adopt local provenance")
	_check(store.accept(first, "local", "b".repeat(64)) == ERR_INVALID_DATA, "source identity is immutable within a record")
	_check(store.accept(_record(14), "local", "not-a-hash") == ERR_INVALID_DATA, "malformed source identity is refused")
	_check(store.mission_comparison(_record(15), "b".repeat(64))["count"] == 1, "a different server build begins a new cohort")
	for dimension: String in ["map", "mission", "difficulty", "rules", "durable", "agent", "active", "legacy", "external"]:
		var isolated: PlayerRecords = PlayerRecords.new("")
		var other: Dictionary = _record(20, 2000)
		var origin: String = "local"
		match dimension:
			"map": other["map_id"] = 1002
			"mission": other["scope"]["mission"] = MissionState.M02_ID
			"difficulty": other["scope"]["rules"]["difficulty"] = "severe"
			"rules": other["scope"]["rules"]["revision"] = 1
			"durable": other["scope"]["run"] = {"id": "00000000-0000-0000-0000-000000000003", "continues": 3, "level_start_continues": 3, "status": "complete"}
			"agent": other["role"] = "agent"
			"active":
				other["status"] = "active"
				other.erase("mission_elapsed_ticks")
			"legacy": other.erase("mission_elapsed_ticks")
			"external": origin = "external"
		_check(isolated.accept(other, origin, SERVER_HASH if origin == "local" else "") == OK, "incompatible but valid fixture loads: " + dimension)
		_check(isolated.mission_comparison(first, SERVER_HASH)["count"] == 1, "incompatible observation cannot lower a best: " + dimension)
		if dimension in ["agent", "active", "legacy"]:
			_check(isolated.mission_comparison(other, SERVER_HASH).is_empty(), "ineligible current result has no comparison: " + dimension)
	await _persistence(first, faster)
	await _presentation(store, faster)
	if failures == 0:
		print("test_mission_bests: PASS compatible history, migration, provenance, exact times and rendered result controls")
	quit(0 if failures == 0 else 1)

func _persistence(first: Dictionary, faster: Dictionary) -> void:
	var path: String = "user://test-mission-bests-%d" % OS.get_process_id()
	var legacy: Dictionary = {"version": 1, "generation": 1, "profile_id": "1".repeat(32), "entries": [{"origin": "local", "record": first}]}
	var original: String = JSON.stringify(legacy)
	var file: FileAccess = FileAccess.open(path + ".1.json", FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var store: PlayerRecords = PlayerRecords.new(path)
	_check(store.error == OK and store.entries.size() == 1, "version one history loads without invented provenance")
	_check(store.accept(faster, "local", SERVER_HASH) == OK, "new observation upgrades through the existing two-slot writer")
	_check(FileAccess.get_file_as_string(path + ".1.json") == original, "the preceding committed slot survives migration unchanged")
	store = PlayerRecords.new(path)
	_check(store.entries.size() == 2 and store.profile_id == legacy["profile_id"], "profile and historical entries survive reload")
	_check(store.mission_comparison(faster, SERVER_HASH)["count"] == 1, "legacy unknown provenance is never assigned the new build")
	var later: Dictionary = _record(30, 2401)
	_check(store.accept(later, "local", SERVER_HASH) == OK, "second new comparison record persists")
	store = PlayerRecords.new(path)
	_check(store.mission_comparison(later, SERVER_HASH)["best_ticks"] == 2399, "best times survive process reload")
	var document: Dictionary = {"version": 2, "generation": 4, "profile_id": legacy["profile_id"], "entries": store.entries.duplicate(true)}
	document["entries"][0]["server_sha256"] = "bad"
	_check(not PlayerRecords._valid_document(document), "disk metadata has the same strict source boundary")
	for slot: int in range(2):
		DirAccess.remove_absolute("%s.%d.json" % [path, slot])

func _presentation(store: PlayerRecords, record: Dictionary) -> void:
	var result: Dictionary = CampaignResult.select(record, {"id": MissionState.ID, "attempt": 1, "phase": "departed", "rules": record["scope"]["rules"]}, record["player_id"])
	result["comparison"] = store.mission_comparison(record, SERVER_HASH)
	var view: CampaignResults = CampaignResults.new(result)
	root.add_child(view)
	await process_frame
	await process_frame
	var text: String = ""
	for label: Node in view.find_children("*", "Label", true, false):
		text += str(label.text) + "\n"
	_check(text.contains("NEW LOCAL BEST: 1:59.95") and text.contains("Same version and difficulty"), "actual result presents the comparison and its scope")
	_check(view.armed, "extra comparison rows preserve the existing release-to-continue control")
	view.queue_free()
	var panel: RecordsPanel = RecordsPanel.new()
	panel.records = store
	panel.preferences = FragrSettings.new("")
	root.add_child(panel)
	await process_frame
	panel._select_kind("mission")
	_check(panel._details.text.contains("Local best: 1:59.95 across 2 retained completions."), "service record derives the same retained best")
	panel.queue_free()
	await process_frame
