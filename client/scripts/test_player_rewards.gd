extends SceneTree

const SERVER_HASH: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_player_rewards: " + message)

func _record(serial: int, secret: bool = false, status: String = "complete") -> Dictionary:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/player_record.json"))
	record["version"] = PlayerRecord.VERSION
	for counts: String in ["total", "attempt"]:
		while record[counts]["weapons"].size() < EquipmentState.WEAPONS.size():
			record[counts]["weapons"].append({"attacks": 0, "damaging_attacks": 0, "kills": 0, "hp_damage": 0, "armor_damage": 0})
	record["session_id"] = "00000000-0000-0000-0000-%012d" % serial
	record["tick"] = 10000
	record["map_id"] = 1001
	record["map_name"] = "Recall Notice"
	record["status"] = status
	record["scope"] = {"kind": "mission", "mission": MissionState.ID, "attempt": 1,
		"rules": {"revision": MissionState.RULES_REVISION, "difficulty": "standard"},
		"run": {"id": "00000000-0000-0000-0000-000000000003", "continues": 3,
			"level_start_continues": 3, "status": "playing" if status == "active" else status}}
	if secret:
		record["total"]["secrets"] = 1
		record["attempt"]["secrets"] = 1
	return record

func _run() -> void:
	var complete: Dictionary = _record(1)
	_check(PlayerRecord.validation_error(complete, complete["player_id"]).is_empty(), "durable completion fixture obeys the private wire boundary")
	var store: PlayerRecords = PlayerRecords.new("")
	_check(store.accept(complete, "local", SERVER_HASH) == OK and store.unlocks.size() == 1, "actual complete scope earns the completion award")
	var first_proof: Dictionary = store.unlocks[0].duplicate(true)
	_check(store.accept(complete, "local", SERVER_HASH) == OK and store.unlocks == [first_proof], "repeated snapshots never duplicate or replace the award identity")
	var reconnect: Dictionary = _record(2)
	_check(store.accept(reconnect, "local", SERVER_HASH) == OK and store.unlocks == [first_proof], "a new socket/session completing the same mission cannot re-award")
	var secret: Dictionary = _record(3, true, "active")
	_check(store.accept(secret, "local", SERVER_HASH) == OK and store.unlocks.size() == 2, "participant secret discovery earns before mission completion")
	var retry: Dictionary = secret.duplicate(true)
	retry["scope"]["attempt"] = 2
	retry["scope"]["run"]["continues"] = 2
	retry["attempt"] = PlayerRecord.empty_counts()
	retry["tick"] += 1
	_check(store.accept(retry, "local", SERVER_HASH) == OK and store.unlocks.size() == 2, "mission-entry retry retains awards without farming total secret counts")
	retry["status"] = "failed"
	retry["scope"]["run"]["status"] = "failed"
	retry["scope"]["run"]["continues"] = 0
	retry["scope"]["attempt"] = 4
	retry["tick"] += 1
	_check(store.accept(retry, "local", SERVER_HASH) == OK and store.unlocks.size() == 2, "failed/exhausted run does not erase the earlier discovery")
	for tier: String in MissionState.DIFFICULTIES:
		var record: Dictionary = _record(4)
		record["scope"]["rules"]["difficulty"] = tier
		_check(PlayerRewards.eligible(record, "local", SERVER_HASH) == ["recall_notice_complete"], "ordinary tier qualifies equally: " + tier)
	for dimension: String in ["external", "unknown_hash", "agent", "development", "active", "failed", "old_rules", "wrong_map"]:
		var record: Dictionary = complete.duplicate(true)
		var origin: String = "local"
		var hash_value: String = SERVER_HASH
		match dimension:
			"external": origin = "external"
			"unknown_hash": hash_value = ""
			"agent": record["role"] = "agent"
			"development": record["scope"]["run"] = null
			"active", "failed":
				record["status"] = dimension
				record["scope"]["run"]["status"] = "playing" if dimension == "active" else "failed"
			"old_rules": record["scope"]["rules"]["revision"] = 2
			"wrong_map": record["map_id"] = 1002
		_check(PlayerRewards.eligible(record, origin, hash_value).is_empty(), "ineligible completion is refused: " + dimension)
	var baseline: PlayerRecords = PlayerRecords.new("")
	_check(baseline.select_customization({"title": "none", "emblem": "none", "finish": "oxide"}) == OK, "baseline paint is immediately available")
	_check(baseline.select_customization({"title": "on_file", "emblem": "none", "finish": "standard"}) == ERR_INVALID_DATA, "preferences cannot bypass an unearned title")
	_check(baseline.select_customization({"title": "none", "emblem": "none", "finish": "gold"}) == ERR_INVALID_DATA, "unimplemented campaign paint cannot be selected")
	_check(store.select_customization({"title": "on_file", "emblem": "transfer_stamp", "finish": "margin_teal"}) == OK, "earned appearance uses the same profile writer")
	for serial: int in range(100, 100 + PlayerRecords.LIMIT + 2):
		_check(store.accept(_record(serial), "local", SERVER_HASH) == OK, "history eviction input remains valid")
	_check(store.entries.size() == PlayerRecords.LIMIT and store.unlocks[0] == first_proof, "bounded history eviction cannot remove or duplicate independent unlock proofs")
	await _persistence(complete, secret)
	await _historical_rules_profile(complete)
	await _presentation(store)
	await _profile_navigation()
	if failures == 0:
		print("test_player_rewards: PASS eligibility, idempotency, retries, eviction, recovery, migration, selectors and finish isolation")
	quit(0 if failures == 0 else 1)

func _write(path: String, data: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "isolated fixture opens")
	if file != null:
		file.store_string(data if data is String else JSON.stringify(data))
		file.close()

func _historical_rules_profile(current: Dictionary) -> void:
	var path: String = "user://test-rewards-rules-three-%d" % OS.get_process_id()
	var historical: Dictionary = current.duplicate(true)
	historical["version"] = PlayerRecord.EIGHT_COLUMN_VERSION
	historical["scope"]["rules"]["revision"] = 3
	for field: String in ["total", "attempt"]:
		historical[field]["weapons"].resize(8)
	var store: PlayerRecords = PlayerRecords.new(path)
	_check(store.accept(historical, "local", SERVER_HASH) == OK and store.unlocks.size() == 1, "earned version-two rules-three completion remains eligible")
	_check(store.select_customization({"title":"on_file", "emblem":"transfer_stamp", "finish":"oxide"}) == OK, "retained proof still selects its earned appearance")
	var read: PlayerRecords = PlayerRecords.new(path)
	_check(read.error == OK and read.unlocks.size() == 1 and read.customization == store.customization, "rules-four build reloads historical proof and appearance")
	if read.unlocks.size() == 1:
		var retained: Dictionary = read.unlocks[0]["record"]
		_check(PlayerRecord.validation_error(retained, retained["player_id"]).is_empty() and retained["total"]["weapons"].size() == 8 and PlayerRecord.weapon_count(retained["total"], 4, "hp_damage") == PlayerRecord.weapon_count(historical["total"], 4, "hp_damage"), "historical columns retain their actual finite outcome through JSON numeric roundtrip")
	_check(read.unlocks[0]["record"]["scope"]["rules"]["revision"] == 3 and read.unlocks[0]["record"]["version"] == 2, "history never relabels earned rules or weapon columns")
	for suffix: String in [".0.json", ".1.json"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

func _persistence(complete: Dictionary, secret: Dictionary) -> void:
	var path: String = "user://test-player-rewards-%d" % OS.get_process_id()
	for version: int in [1, 2]:
		var old_entry: Dictionary = {"origin": "local", "record": complete}
		if version == 2:
			old_entry["server_sha256"] = SERVER_HASH
		var old: Dictionary = {"version": version, "generation": 1, "profile_id": "1".repeat(32), "entries": [old_entry]}
		_write(path + ".1.json", old)
		var original: String = FileAccess.get_file_as_string(path + ".1.json")
		var migrated: PlayerRecords = PlayerRecords.new(path)
		_check(migrated.error == OK and migrated.unlocks.is_empty(), "historical version loads without retroactive awards: " + str(version))
		_check(migrated.accept(secret, "local", SERVER_HASH) == OK, "new ingress upgrades through the existing writer")
		_check(FileAccess.get_file_as_string(path + ".1.json") == original, "migration preserves the exact previous committed generation")
		migrated = PlayerRecords.new(path)
		_check(migrated.unlocks.size() == 1 and migrated.profile_id == "1".repeat(32), "unlock and profile survive JSON numeric roundtrip")
		for slot: int in range(2):
			DirAccess.remove_absolute("%s.%d.json" % [path, slot])
	var store: PlayerRecords = PlayerRecords.new(path)
	_check(store.accept(complete, "local", SERVER_HASH) == OK, "first award commits")
	_check(store.accept(secret, "local", SERVER_HASH) == OK, "second award commits")
	_check(store.select_customization({"title": "on_file", "emblem": "transfer_stamp", "finish": "margin_teal"}) == OK, "selection commits with proofs")
	store = PlayerRecords.new(path)
	_check(store.unlocks.size() == 2 and store.customization["finish"] == "margin_teal", "appearance survives reload separately from run progress")
	var doc: Dictionary = store._document(4).duplicate(true)
	doc["unlocks"].append(doc["unlocks"][0].duplicate(true))
	_check(not PlayerRecords._valid_document(doc), "duplicate award receipts fail strict disk validation")
	doc = store._document(4).duplicate(true)
	doc["unlocks"][0]["id"] = "future_award"
	_check(not PlayerRecords._valid_document(doc), "unknown awards are never silently reinterpreted")
	doc = store._document(4).duplicate(true)
	doc["unlocks"][0]["record"]["role"] = "agent"
	_check(not PlayerRecords._valid_document(doc), "proof must retain qualifying participant facts")
	# Generation 3 lives in slot 1. Obstruct only its replacement slot.
	DirAccess.remove_absolute(path + ".0.json")
	DirAccess.make_dir_absolute(path + ".0.json")
	var previous: Dictionary = store.customization.duplicate()
	_check(store.select_customization(PlayerRewards.DEFAULTS) != OK and store.customization == previous, "failed selection write leaves active appearance unchanged")
	var recovered: PlayerRecords = PlayerRecords.new(path)
	_check(recovered.unlocks.size() == 2 and recovered.customization == previous, "failed replacement retains prior valid unlock generation")
	DirAccess.remove_absolute(path + ".0.json")
	_check(store.select_customization(PlayerRewards.DEFAULTS) == OK, "failed selection can be retried after storage recovers")
	_write(path + ".0.json", "{truncated")
	recovered = PlayerRecords.new(path)
	_check(recovered.unlocks.size() == 2 and recovered.customization == previous, "corrupt newest generation recovers preceding earned appearance")
	_write(path + ".0.json", {"version": 99})
	recovered = PlayerRecords.new(path)
	_check(recovered.error == ERR_FILE_UNRECOGNIZED and recovered.accept(complete, "local", SERVER_HASH) == ERR_FILE_UNRECOGNIZED, "future profile cannot be overwritten by new ingress")
	for slot: int in range(2):
		DirAccess.remove_absolute("%s.%d.json" % [path, slot])
	var missing_parent: String = path + "-missing"
	var unavailable: PlayerRecords = PlayerRecords.new(missing_parent.path_join("profile"))
	_check(unavailable.select_customization({"title": "none", "emblem": "none", "finish": "oxide"}) != OK \
		and unavailable.error != OK and unavailable.customization == PlayerRewards.DEFAULTS, "open failure reports the same failure state and preserves active appearance")
	_check(unavailable.accept(complete, "local", SERVER_HASH) != OK \
		and unavailable.take_award_notices().is_empty(), "failed award write does not announce uncommitted progress")
	DirAccess.make_dir_absolute(missing_parent)
	_check(unavailable.accept(complete, "local", SERVER_HASH) == OK \
		and unavailable.take_award_notices() == ["recall_notice_complete"] \
		and unavailable.take_award_notices().is_empty(), "duplicate retry commits and announces the pending award exactly once")
	for slot: int in range(2):
		DirAccess.remove_absolute(missing_parent.path_join("profile.%d.json" % slot))
	DirAccess.remove_absolute(missing_parent)

func _presentation(store: PlayerRecords) -> void:
	var panel: RewardsPanel = RewardsPanel.new()
	panel.records = store
	panel.profile_name = "Patch"
	root.add_child(panel)
	await process_frame
	panel.focus_first()
	_check(root.gui_get_focus_owner() == panel._selectors["title"], "keyboard/controller focus starts at the title selector")
	_check(panel._preview.material != null and panel._identity.text.contains("ON FILE") and panel._stamp.visible, "earned selections preview on actual controls")
	panel._selectors["finish"].item_selected.emit(1)
	_check(store.customization["finish"] == "margin_teal" and panel.draft["finish"] == "oxide", "preview changes are isolated until Save")
	var selector: OptionButton = panel._selectors["title"]
	selector.grab_focus()
	selector.show_popup()
	await process_frame
	var cancel: InputEventKey = InputEventKey.new()
	cancel.physical_keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	await process_frame
	_check(not selector.get_popup().visible, "keyboard cancel dismisses the selector without saving")
	selector.show_popup()
	await process_frame
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	pad.pressed = true
	root.push_input(pad, true)
	await process_frame
	_check(not selector.get_popup().visible, "controller cancel dismisses the selector without saving")
	panel.queue_free()
	await process_frame
	panel = RewardsPanel.new()
	panel.records = PlayerRecords.new("")
	root.add_child(panel)
	await process_frame
	panel._selectors["finish"].item_selected.emit(2)
	_check(panel._save.disabled and panel._preview.material != null, "locked finishes can be previewed without entitlement")
	panel._commit()
	_check(panel.records.customization == PlayerRewards.DEFAULTS, "locked preview cannot save")
	panel.queue_free()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: Node = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	hud.set_fp_juice(true)
	hud.set_weapon_finish("oxide")
	hud.set_fp_weapon("Scatter")
	_check(hud.fp_weapon.material != null, "first-person firearm receives paint")
	var source: Texture2D = hud.fp_weapon.texture
	hud.set_fp_weapon("Shiv")
	_check(hud.fp_weapon.material == null, "knife and hand presentation remains original")
	hud.set_fp_weapon("Scatter")
	hud.set_weapon_finish("standard")
	_check(hud.fp_weapon.material == null and hud.fp_weapon.texture == source, "default finish restores identical source frame without changing gun timing")
	hud.set_weapon_finish("margin_teal")
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.hud = hud
	manager._prepare_benchmark_presentation()
	_check(hud.fp_weapon.material == null, "benchmark presentation explicitly restores standard paint before recording")
	manager.free()
	hud.queue_free()
	await process_frame

func _profile_navigation() -> void:
	var menu: Node = load("res://scenes/boot_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await menu._show("profile")
	menu._root.get_node("Callsign").text = "Draft callsign"
	menu._settings.set_value("profile", "body", "synthetic")
	menu._open_rewards()
	await process_frame
	var cancel: InputEventKey = InputEventKey.new()
	cancel.physical_keycode = KEY_ESCAPE
	cancel.pressed = true
	menu._unhandled_input(cancel)
	await process_frame
	_check(menu._page == "profile" and menu._root.get_node("Callsign").text == "Draft callsign" \
		and menu._settings.player_body() == "synthetic", "appearance cancel preserves the enclosing unsaved profile draft")
	menu._unhandled_input(cancel)
	await process_frame
	await menu._show("profile")
	_check(menu._root.get_node("Callsign").text == FragrSettings.DEFAULT_CALLSIGN \
		and menu._settings.player_body() == "human", "cancelling the enclosing profile still discards the whole unsaved draft")
	menu.queue_free()
	await process_frame
