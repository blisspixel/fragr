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
	var found: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/player_record_shiv.json"))
	_check(PlayerRecord.validation_error(found, found["player_id"]).is_empty(), "shared six-slot Shiv record validates")
	_check(PlayerRecord.secrets(found["total"]) == 1 and PlayerRecord.weapon_count(sample["total"], 5, "attacks") == 0, "a five-slot record reads as no Shiv use")
	for patch: Dictionary in [{"secrets": 0}, {"secrets": -1}, {"secrets": 22}, {"secrets": "1"}]:
		var broken: Dictionary = found.duplicate(true)
		broken["total"].merge(patch, true)
		broken["attempt"].merge(patch, true)
		_check(not PlayerRecord.validation_error(broken, found["player_id"]).is_empty(), "invalid secret count: " + str(patch))
	for size: int in [4, 8]:
		var broken: Dictionary = found.duplicate(true)
		broken["total"]["weapons"].resize(size)
		_check(not PlayerRecord.validation_error(broken, found["player_id"]).is_empty(), "weapon slots must be five, six or seven")
	var scoped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/player_record_sniper.json"))
	_check(PlayerRecord.validation_error(scoped, scoped["player_id"]).is_empty(), "shared seven-slot Sniper record validates")
	var eight_column: Dictionary = scoped.duplicate(true)
	eight_column["version"] = PlayerRecord.EIGHT_COLUMN_VERSION
	for field: String in ["total", "attempt"]:
		eight_column[field]["weapons"].append({"attacks": 0, "damaging_attacks": 0, "kills": 0, "hp_damage": 0, "armor_damage": 0})
	_check(PlayerRecord.validation_error(eight_column, eight_column["player_id"]).is_empty(), "retained version two has exactly eight columns")
	var current: Dictionary = eight_column.duplicate(true)
	current["version"] = PlayerRecord.VERSION
	for field: String in ["total", "attempt"]:
		current[field]["weapons"].append({"attacks": 0, "damaging_attacks": 0, "kills": 0, "hp_damage": 0, "armor_damage": 0})
	_check(PlayerRecord.validation_error(current, current["player_id"]).is_empty(), "current record has a distinct ninth Arc column")
	for width: int in [5, 6, 7, 9, 10]:
		var forged_eight: Dictionary = eight_column.duplicate(true)
		forged_eight["attempt"]["weapons"].resize(width)
		_check(not PlayerRecord.validation_error(forged_eight, forged_eight["player_id"]).is_empty(), "version two refuses width " + str(width))
	var remote_counts: Dictionary = {"alive_ticks": 20, "deaths": 0, "hp_lost": 0, "armor_lost": 0, "dry_triggers": 0, "weapons": [], "remote_mines": {"attacks": 2, "damaging_attacks": 1, "kills": 1, "hp_damage": 35, "armor_damage": 20}}
	for _index: int in range(EquipmentState.WEAPONS.size()):
		remote_counts["weapons"].append({"attacks": 0, "damaging_attacks": 0, "kills": 0, "hp_damage": 0, "armor_damage": 0})
	_check(PlayerRecord.valid_counts(remote_counts) and PlayerRecord.sum_combat(remote_counts, "attacks") == 2, "Remote Mine attacks occupy their independent current column")
	_check(not PlayerRecord.valid_counts(remote_counts, PlayerRecord.LEGACY_VERSION), "historical record cannot invent a remote column")
	var forged_remote_legacy: Dictionary = sample["total"].duplicate(true)
	forged_remote_legacy["remote_mines"] = {"attacks": 0, "damaging_attacks": 0, "kills": 0, "hp_damage": 0, "armor_damage": 0}
	_check(not PlayerRecord.valid_counts(forged_remote_legacy, PlayerRecord.LEGACY_VERSION), "exact historical weapon width still refuses a forged zero remote column")
	var remote_total: Dictionary = PlayerRecord.empty_counts()
	PlayerRecord.add_counts(remote_total, remote_counts)
	_check(PlayerRecord.column_count(remote_total, "remote_mines", "hp_damage") == 35 and PlayerRecord.mine_count(remote_total, "hp_damage") == 0 and PlayerRecord.grenade_count(remote_total, "hp_damage") == 0, "history never misattributes remote damage to existing explosives")
	var remote_regression: Dictionary = remote_counts.duplicate(true)
	remote_regression["remote_mines"]["hp_damage"] = 34
	_check(not PlayerRecord.contains(remote_regression, remote_counts), "remote damage cannot regress")
	for remote_patch: Dictionary in [{"damaging_attacks": 3}, {"hp_damage": 9007199254740992}, {"kills": 257}, {"attacks": "2"}]:
		var remote_bad: Dictionary = remote_counts.duplicate(true)
		remote_bad["remote_mines"].merge(remote_patch, true)
		_check(not PlayerRecord.valid_counts(remote_bad), "invalid remote counts: " + str(remote_patch))
	_check(not PlayerRecord.validation_error(current, current["player_id"], scoped).is_empty(), "negotiated record version cannot change inside one connection")
	var forged_legacy: Dictionary = current.duplicate(true)
	forged_legacy["version"] = PlayerRecord.LEGACY_VERSION
	_check(not PlayerRecord.validation_error(forged_legacy, forged_legacy["player_id"]).is_empty(), "legacy record refuses zero eighth column")
	for size: int in [5, 6, 7, 8, 10]:
		var wrong_current: Dictionary = current.duplicate(true)
		wrong_current["attempt"]["weapons"].resize(size)
		_check(not PlayerRecord.validation_error(wrong_current, wrong_current["player_id"]).is_empty(), "current record requires exact nine columns")
	_check(PlayerRecord.weapon_count(scoped["total"], 6, "kills") == 1 and PlayerRecord.weapon_count(found["total"], 6, "attacks") == 0, "a six-slot record reads as no Sniper use")
	var overkill: Dictionary = scoped.duplicate(true)
	overkill["total"]["weapons"][6]["kills"] = 3
	_check(not PlayerRecord.validation_error(overkill, scoped["player_id"]).is_empty(), "one Sniper ray cannot kill twice")
	var seventh: Dictionary = PlayerRecord.empty_counts()
	PlayerRecord.add_counts(seventh, found["total"])
	PlayerRecord.add_counts(seventh, scoped["total"])
	_check(int(seventh["weapons"][5]["kills"]) == 1 and int(seventh["weapons"][6]["kills"]) == 1, "history adds six and seven slot records without shifting a slot")
	var fewer: Dictionary = found.duplicate(true)
	fewer["attempt"]["secrets"] = 2
	_check(not PlayerRecord.validation_error(fewer, found["player_id"]).is_empty(), "an attempt cannot find more secrets than the total")
	var mixed: Dictionary = PlayerRecord.empty_counts()
	PlayerRecord.add_counts(mixed, sample["total"])
	PlayerRecord.add_counts(mixed, found["total"])
	_check(PlayerRecord.sum_weapon(mixed, "attacks") == 7 and PlayerRecord.secrets(mixed) == 1 and int(mixed["weapons"][5]["kills"]) == 1, "history adds five and six slot records without shifting a slot")
	var active: Dictionary = sample.duplicate(true)
	active["status"] = "active"
	_check(not PlayerRecord.validation_error(active, active["player_id"], sample).is_empty(), "terminal status cannot be undone")
	var backwards: Dictionary = active.duplicate(true)
	backwards["tick"] = 0
	_check(not PlayerRecord.validation_error(backwards, active["player_id"], active).is_empty(), "late observations are rejected")
	var mission: Dictionary = sample.duplicate(true)
	mission["scope"] = {"kind": "mission", "mission": MissionState.ID, "attempt": 1, "rules": {"difficulty": "standard", "revision": 1}, "run": {"id": "00000000-0000-0000-0000-000000000003", "continues": 3, "status": "complete"}}
	_check(PlayerRecord.validation_error(mission, mission["player_id"]).is_empty(), "historical three-key M01 record remains readable")
	var ward: Dictionary = mission.duplicate(true)
	ward["scope"]["mission"] = MissionState.M02_ID
	_check(not PlayerRecord.validation_error(ward, ward["player_id"]).is_empty(), "new M02 durable records need the level baseline")
	ward["scope"]["run"] = {"id": mission["scope"]["run"]["id"], "status": "playing", "continues": 2, "level_start_continues": 2}
	ward["scope"]["attempt"] = 1
	ward["status"] = "active"
	_check(PlayerRecord.validation_error(ward, ward["player_id"]).is_empty(), "M02 durable record accepts a reset level attempt and retained allowance")
	ward["scope"]["run"] = null
	_check(PlayerRecord.validation_error(ward, ward["player_id"]).is_empty(), "an M02 development record validates without a run")
	var yard: Dictionary = ward.duplicate(true)
	yard["scope"]["mission"] = MissionState.M03_ID
	_check(PlayerRecord.validation_error(yard, yard["player_id"]).is_empty(), "M03 development records validate on the shared record boundary")
	yard["scope"]["run"] = {"id": mission["scope"]["run"]["id"], "status": "playing", "continues": 1, "level_start_continues": 1}
	_check(PlayerRecord.validation_error(yard, yard["player_id"]).is_empty(), "M03 records retain the level allowance without a refill")
	var berth: Dictionary = yard.duplicate(true)
	berth["scope"]["mission"] = MissionState.M09_ID
	berth["scope"]["rules"]["revision"] = MissionState.RULES_REVISION
	_check(PlayerRecord.validation_error(berth, berth["player_id"]).is_empty(), "M09 private record retains version one and exact run baseline")
	berth["scope"]["mission"] = MissionState.M10_ID
	_check(PlayerRecord.validation_error(berth, berth["player_id"]).is_empty(), "M10 records bind the authored ship mission")
	berth["scope"]["mission"] = "right_of_search"
	_check(PlayerRecord.validation_error(berth, berth["player_id"]).is_empty(), "M11 records bind the authored tender mission")
	berth["scope"]["mission"] = MissionState.M12_ID
	_check(PlayerRecord.validation_error(berth, berth["player_id"]).is_empty(), "M12 records bind the authored habitat mission")
	berth["scope"]["mission"] = "weight_of_permission"
	_check(not PlayerRecord.validation_error(berth, berth["player_id"]).is_empty(), "pending M13 cannot forge a playable participant record")
	var habitat: Dictionary = current.duplicate(true)
	habitat["map_id"] = 1012
	habitat["map_name"] = "Terms of Cooperation"
	habitat["status"] = "active"
	habitat["scope"] = {"kind": "mission", "mission": MissionState.M12_ID, "attempt": 2, "rules": {"difficulty": "standard", "revision": MissionState.RULES_REVISION}, "run": {"id": mission["scope"]["run"]["id"], "status": "playing", "continues": 1, "level_start_continues": 2}}
	_check(PlayerRecord.validation_error(habitat, habitat["player_id"]).is_empty(), "current nine-column M12 record accepts its retained second-attempt allowance")
	var habitat_bad: Dictionary = habitat.duplicate(true)
	habitat_bad["scope"]["run"]["continues"] = 2
	_check(not PlayerRecord.validation_error(habitat_bad, habitat["player_id"]).is_empty(), "M12 record still rejects an allowance that contradicts its actual attempt")
	yard["scope"]["mission"] = MissionState.M04_ID
	yard["scope"]["rules"]["revision"] = MissionState.RULES_REVISION
	_check(PlayerRecord.validation_error(yard, yard["player_id"]).is_empty(), "M04 retained allowance and current rules validate")
	yard["scope"]["rules"]["revision"] = 2
	_check(PlayerRecord.validation_error(yard, yard["player_id"]).is_empty(), "historical revision 2 records remain readable")
	yard["scope"]["mission"] = MissionState.M07_ID
	_check(PlayerRecord.validation_error(yard, yard["player_id"]).is_empty(), "M07 records retain the level allowance through the shared record boundary")
	yard["scope"]["mission"] = "unavailable_mission"
	_check(not PlayerRecord.validation_error(yard, yard["player_id"]).is_empty(), "unknown mission record scope is rejected")
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
	var habitat_network: Node = load("res://scripts/net_client.gd").new()
	habitat_network.player_id = habitat["player_id"]
	var habitat_received: Array[Dictionary] = []
	var habitat_errors: Array[String] = []
	habitat_network.record_received.connect(func(record: Dictionary) -> void: habitat_received.append(record))
	habitat_network.server_error.connect(func(message: String) -> void: habitat_errors.append(message))
	# Compare the decoded wire shape, including JSON numeric variants.
	var habitat_wire: Dictionary = JSON.parse_string(JSON.stringify(habitat))
	habitat_wire["type"] = "record"
	habitat_network._handle_message(JSON.stringify(habitat_wire))
	_check(habitat_received.size() == 1 and habitat_errors.is_empty() and habitat_network.record == habitat_wire, "live M12 record reaches presentation without disconnecting the owned mission: received=%d, errors=%s, unchanged=%s" % [habitat_received.size(), str(habitat_errors), str(habitat_network.record == habitat_wire)])
	habitat_wire["scope"]["mission"] = "weight_of_permission"
	habitat_network._handle_message(JSON.stringify(habitat_wire))
	_check(habitat_received.size() == 1 and habitat_errors.size() == 1 and habitat_network.record.is_empty(), "live M12 boundary still refuses an unimplemented successor mission")
	habitat_network.free()

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
	var shown: String = panel.get("_details").text
	_check(shown.contains("100.0") and shown.contains("2.0 shots per kill (2/1)"), "rendered analysis keeps the counts beside the rate: " + shown)
	_check(shown.contains("57.1 frags per minute and 7142.9 dealt per minute, over 0:01 alive"), "pace uses the ticks that were lived: " + shown)
	_check(shown.contains("95% Wilson on hurt: 34.2% to 100.0% (2/2)"), "two perfect shots are not certainty: " + shown)
	_check(not shown.contains("Body "), "an older damaging column does not pretend the connect was measured")
	_check(memory.accept(found, "local") == OK, "a six-slot record is retained")
	panel.call("_select_kind", "practice")
	await process_frame
	var details: String = panel.get("_details").text
	_check(details.contains("SHIV: 3 shots") and details.contains("Secrets found: 1"), "the service record names the Shiv and the found secret")
	_check(not details.contains("Body "), "the Shiv column predates connect accounting")
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/combat_ratios.json"))
	for row: Dictionary in table["ratios"]:
		var got: int = PlayerRecord.ratio_scaled(int(row["numerator"]), int(row["denominator"]), int(row["scale"]))
		var expected: int = -1 if row["value"] == null else int(row["value"])
		_check(got == expected, "ratio %s/%s scale %s -> %s, got %s" % [row["numerator"], row["denominator"], row["scale"], expected, got])
	_check(PlayerRecord.ratio_scaled((1 << 53) - 1, 3, 1000) == 3002399751580330333, "a ratio past the float mantissa stays on integers")
	_check(PlayerRecord.wilson_thousandths(1, 0) == Vector2i(-1, -1), "zero trials publish no interval")
	for row: Dictionary in table["wilson"]:
		var interval: Vector2i = PlayerRecord.wilson_thousandths(int(row["hits"]), int(row["trials"]))
		_check(interval == Vector2i(int(row["low"]), int(row["high"])), "wilson %s/%s -> %s, got %s" % [row["hits"], row["trials"], Vector2i(int(row["low"]), int(row["high"])), interval])
		var point: int = PlayerRecord.ratio_scaled(int(row["hits"]), int(row["trials"]), 1000)
		_check(interval.x <= point and point <= interval.y and interval.x <= interval.y, "wilson contains its rounded rate")
	var wide: Vector2i = PlayerRecord.wilson_thousandths(5, 10)
	var narrow: Vector2i = PlayerRecord.wilson_thousandths(500, 1000)
	_check(narrow.x >= wide.x and narrow.y <= wide.y and narrow.y - narrow.x < wide.y - wide.x, "five hundred of a thousand is a tighter interval than five of ten")
	var measured: Dictionary = {"attacks": 2, "damaging_attacks": 2, "kills": 1, "hp_damage": 100, "armor_damage": 25, "connects": 2, "heads": 1}
	var block: Array[String] = RecordsPanel.weapon_lines("RAIL", measured, true)
	_check(block[0] == "RAIL: 2 shots, 125 dealt (100 HP + 25 armor), 62.5 per shot", block[0])
	_check(block[2] == "Body 2/2 (100.0%)", block[2])
	_check(block[3] == "Head band 1/2 (50.0%)", block[3])
	_check(block[4] == "95% Wilson on bodies: 34.2% to 100.0% (2/2)", block[4])
	_check(block[5] == "95% Wilson on heads: 9.5% to 90.5% (1/2)", block[5])
	var split: Dictionary = {"attacks": 4, "damaging_attacks": 1, "kills": 1, "hp_damage": 100, "armor_damage": 0, "connects": 2, "heads": 1}
	var split_lines: Array[String] = RecordsPanel.weapon_lines("RAIL", split, true)
	_check(split_lines[0] == "RAIL: 4 shots, 100 dealt (100 HP + 0 armor), 25.0 per shot, 50.0 per body, 100.0 per hurt", split_lines[0])
	var counts: Dictionary = PlayerRecord.empty_counts()
	counts["alive_ticks"] = 4
	counts["weapons"][4] = measured
	_check(PlayerRecord.valid_counts(counts), "a measured connect column validates")
	counts["weapons"][4] = measured.duplicate()
	counts["weapons"][4]["heads"] = 3
	_check(not PlayerRecord.valid_counts(counts), "heads cannot exceed connects")
	counts["weapons"][4] = {"attacks": 2, "damaging_attacks": 2, "kills": 1, "hp_damage": 100, "armor_damage": 0}
	_check(PlayerRecord.valid_counts(counts), "an older damaging column still validates")
	_check(RecordsPanel.commentary_key(found).is_empty(), "a pistol attack is not a melee-only run")
	var remote_display: Dictionary = current.duplicate(true)
	remote_display["total"] = remote_counts.duplicate(true)
	remote_display["attempt"] = remote_counts.duplicate(true)
	remote_display["tick"] = 80
	_check(PlayerRecord.validation_error(remote_display, remote_display["player_id"]).is_empty(), "remote presentation uses a valid complete record")
	var remote_entries: Array[Dictionary] = [{"origin": "local", "record": remote_display}]
	panel.set("_filtered", remote_entries)
	panel.call("_show_record", 0)
	var remote_details: String = panel.get("_details").text
	_check(remote_details.contains("REMOTE MINES: 2 uses") and remote_details.contains("1/2") and remote_details.contains("50.0"), "service record names actual remote placements separately")
	_check(not remote_details.contains("GRENADES:") and not remote_details.contains("\nMINES:"), "remote presentation never invents another explosive column")
	panel.queue_free()
	await process_frame
	if _failures == 0:
		print("test_player_records: PASS validation, deduplication, retention, recovery, failed writes and presentation")
	quit(0 if _failures == 0 else 1)
