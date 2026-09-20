extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("test_player_records: " + message)

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture file opens")
	if file != null:
		_check(file.store_string(text), "fixture file writes")
		file.close()

func _run() -> void:
	var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/player_record.json"))
	_check(PlayerRecord.validation_error(sample, sample["player_id"]).is_empty(), "shared golden record validates")
	for field: String in ["round", "tick", "map_id", "version", "ticks_per_second", "entered_at", "round_started_at", "total", "attempt", "scope", "player_id", "session_id", "role", "status", "map_name"]:
		var broken: Dictionary = sample.duplicate(true)
		broken.erase(field)
		_check(not PlayerRecord.validation_error(broken, sample["player_id"]).is_empty(), "missing " + field)
	for value: Variant in [-1, 0.5, INF, "1", null]:
		var broken: Dictionary = sample.duplicate(true)
		broken["total"]["weapons"][4]["attacks"] = value
		_check(not PlayerRecord.validation_error(broken, sample["player_id"]).is_empty(), "invalid numeric count")
	var active: Dictionary = sample.duplicate(true)
	active["status"] = "active"
	_check(not PlayerRecord.validation_error(active, active["player_id"], sample).is_empty(), "terminal status cannot be undone")
	var backwards: Dictionary = active.duplicate(true)
	backwards["tick"] = 0
	_check(not PlayerRecord.validation_error(backwards, active["player_id"], active).is_empty(), "late observations are rejected")
	var mission: Dictionary = sample.duplicate(true)
	mission["scope"] = {"kind": "mission", "mission": MissionState.ID, "attempt": 1, "rules": {"difficulty": "standard", "revision": 1}, "run": {"id": "00000000-0000-0000-0000-000000000003", "continues": 3, "status": "complete"}}
	_check(PlayerRecord.validation_error(mission, mission["player_id"]).is_empty(), "mission record validates")
	var rewritten: Dictionary = mission.duplicate(true)
	rewritten["scope"]["attempt"] = 2
	rewritten["scope"]["run"]["continues"] = 2
	rewritten["attempt"] = PlayerRecord.empty_counts()
	_check(not PlayerRecord.validation_error(rewritten, mission["player_id"], mission).is_empty(), "finished attempt cannot be replaced while retaining totals")
	var network: Node = load("res://scripts/net_client.gd").new()
	network.player_id = sample["player_id"]
	var received: Array[Dictionary] = []
	var errors: Array[String] = []
	network.record_received.connect(func(record: Dictionary) -> void: received.append(record))
	network.server_error.connect(func(message: String) -> void: errors.append(message))
	var wire: Dictionary = sample.duplicate(true)
	wire["type"] = "record"
	network._handle_message(JSON.stringify(wire))
	_check(received.size() == 1 and network.record == wire, "live network boundary delivers validated records")
	wire["version"] = 99
	network._handle_message(JSON.stringify(wire))
	_check(received.size() == 1 and errors.size() == 1 and network.record.is_empty(), "invalid network record closes without presentation")
	network.free()

	var path: String = "user://test-records-%d" % OS.get_process_id()
	var store: PlayerRecords = PlayerRecords.new(path)
	_check(store.accept(sample, "external") == OK, "initial record persists")
	var profile: String = store.profile_id
	_check(store.accept(sample, "external") == OK and store.entries.size() == 1, "duplicate completion replaces nothing")
	var repeated: Dictionary = sample.duplicate(true)
	repeated["tick"] = 100
	_check(store.accept(repeated, "external") == OK and store.entries[0]["record"] == sample, "terminal retransmission does not cause another write")
	_check(PlayerRecord.sum_weapon(store.totals("arena"), "kills") == 1, "completion is counted once")
	_check(store.accept(sample, "local") == ERR_INVALID_DATA, "origin cannot change")
	var round_two: Dictionary = sample.duplicate(true)
	round_two["round"] = 2
	round_two["scope"]["round"] = 2
	round_two["tick"] = 50
	_check(store.accept(round_two, "external") == OK, "second round persists")
	var loaded: PlayerRecords = PlayerRecords.new(path)
	_check(loaded.profile_id == profile and loaded.entries.size() == 2, "latest generation loads with stable profile")
	_check(PlayerRecord.sum_weapon(loaded.totals("arena"), "kills") == 2, "totals sum records")
	_check(PlayerRecord.sum_weapon(loaded.totals("mission"), "kills") == 0, "arena never leaks into campaign")
	var export_path: String = path + ".export.json"
	_check(loaded.export_json(export_path) == OK, "export writes a standalone document")
	var exported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	_check(exported["entries"] == loaded.entries and exported["profile_id"] == loaded.profile_id, "export agrees exactly with history")
	_check(loaded.export_json(export_path) == ERR_ALREADY_EXISTS, "export never truncates an existing file")
	DirAccess.remove_absolute(export_path)
	# Block the replacement destination without touching the last committed slot.
	DirAccess.remove_absolute(path + ".1.json")
	_check(DirAccess.make_dir_absolute(path + ".1.json") == OK, "create isolated rename failure")
	var round_three: Dictionary = round_two.duplicate(true)
	round_three["round"] = 3
	round_three["scope"]["round"] = 3
	round_three["tick"] = 75
	_check(store.accept(round_three, "external") != OK, "failed replacement is observable")
	loaded = PlayerRecords.new(path)
	_check(loaded.entries.size() == 2 and loaded.profile_id == profile, "failed replacement preserves committed history")
	DirAccess.remove_absolute(path + ".1.json")
	_check(store.save() == OK, "failed save can be retried")
	_write(path + ".1.json", "{truncated")
	loaded = PlayerRecords.new(path)
	_check(loaded.entries.size() == 2, "truncated newest generation recovers previous")
	_write(path + ".1.json", JSON.stringify({"version": 99}))
	loaded = PlayerRecords.new(path)
	_check(loaded.error == ERR_FILE_UNRECOGNIZED, "future format blocks writes")
	_check(loaded.accept(sample, "external") == ERR_FILE_UNRECOGNIZED, "future file is not silently downgraded")
	_check(FileAccess.get_file_as_string(path + ".1.json") == JSON.stringify({"version": 99}), "future file remains intact")
	_write(path + ".0.json", "broken")
	_write(path + ".1.json", "broken")
	loaded = PlayerRecords.new(path)
	_check(loaded.error == ERR_FILE_CORRUPT, "two corrupt files are preserved")
	for slot: int in range(2):
		DirAccess.remove_absolute("%s.%d.json" % [path, slot])

	var memory: PlayerRecords = PlayerRecords.new("")
	for index: int in range(PlayerRecords.LIMIT + 1):
		var record: Dictionary = sample.duplicate(true)
		record["round"] = index + 1
		record["scope"]["round"] = index + 1
		_check(memory.accept(record, "external") == OK, "bounded memory record")
	_check(memory.entries.size() == PlayerRecords.LIMIT, "retention is bounded")
	_check(int(memory.entries.back()["record"]["round"]) == 2, "oldest observation expires")
	_check(RecordsPanel.commentary_key(sample).is_empty(), "ordinary shots do not fabricate a roast predicate")
	var dry: Dictionary = sample.duplicate(true)
	dry["total"]["dry_triggers"] = 1
	_check(RecordsPanel.commentary_key(dry) == "RECORD_QUIP_DRY", "dry-trigger quip uses observed fact")
	var panel: RecordsPanel = RecordsPanel.new()
	panel.records = memory
	panel.preferences = FragrSettings.new("user://unused-record-preferences.cfg")
	root.add_child(panel)
	await process_frame
	panel.call("_select_kind", "arena")
	await process_frame
	_check(panel.get("_details").text.contains("100.0"), "rendered analysis derives the ratio")
	panel.queue_free()
	await process_frame
	if _failures == 0:
		print("test_player_records: PASS validation, deduplication, retention, recovery, failed writes and presentation")
	quit(0 if _failures == 0 else 1)
