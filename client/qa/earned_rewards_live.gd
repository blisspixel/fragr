extends "res://scripts/qa_tour.gd"

## Owned ordinary-input mission and real authored secret, followed by its profile.
var _owned: LocalMatch
var _reward_root: String

func _run() -> void:
	_reward_root = OS.get_environment("FRAGR_QA_DIR")
	if not _reward_root.is_absolute_path():
		push_error("earned_rewards_live: absolute isolated FRAGR_QA_DIR required")
		quit(1)
		return
	OS.set_environment("FRAGR_RUN_DIR", _reward_root.path_join("run"))
	_owned = LocalMatch.for_tree(self)
	if not _owned.start_mission("standard", "new"):
		push_error("earned_rewards_live: local start refused")
		quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 25000
	while _owned.state == LocalMatch.State.STARTING and Time.get_ticks_msec() < deadline:
		await process_frame
	if _owned.state != LocalMatch.State.RUNNING:
		push_error("earned_rewards_live: owned child did not become ready")
		_owned.stop()
		quit(1)
		return
	set_meta("fragr_boot", {"mode": "campaign", "host": _owned.url, "run_mode": "new"})
	await super._run()

func _load_manifest() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m01-records.json"))
	manifest["states"].insert(2, {"name": "authored_secret", "camera": "first_person",
		"walk_to": [[6, 0, -21], [7.6, 0, -21.4], [9.2, 0, -23.2]],
		"expect_equipment": {"selected": "shiv"}, "look_at": [4, 1.4, -19],
		"note": "Actual personal alcove Shiv claim, no injected record or unlock."})
	manifest["states"].insert(3, {"name": "secret_return", "camera": "first_person",
		"walk_to": [[7.6, 0, -21.4], [0, 0, -21]], "weapon": "Tack"})
	return manifest

func _retire_scene() -> void:
	var manager: Node = _game_manager()
	if manager != null and not _failed:
		if is_instance_valid(manager.interlude):
			manager.interlude.finish()
		var deadline: int = Time.get_ticks_msec() + 5000
		while manager.net_client.record.get("status") != "complete" and Time.get_ticks_msec() < deadline:
			await process_frame
		var store: PlayerRecords = manager.records
		if store.unlocks.size() != 2 or not PlayerRewards.owns(store.unlocks, "recall_notice_complete") \
			or not PlayerRewards.owns(store.unlocks, "authored_secret_found") \
			or store.error != OK or PlayerRecord.secrets(manager.net_client.record.get("total", {})) != 1:
			push_error("earned_rewards_live: actual departure and secret did not retain both awards")
			_failed = true
		else:
			var receipt: Dictionary = {"record": manager.net_client.record.duplicate(true),
				"profile": store._document(1).duplicate(true), "server_sha256": _owned.server_sha256}
			var file: FileAccess = FileAccess.open(_out_dir.path_join("earned-record.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify(receipt, "\t"))
			file.close()
			print("earned_rewards_live: actual participant earned both awards, ", PlayerRecord.sum_combat(receipt["record"]["total"], "kills"), " kills")
	await super._retire_scene()
	_owned.stop()
	var stop_deadline: int = Time.get_ticks_msec() + 5000
	while _owned.state == LocalMatch.State.STOPPING and Time.get_ticks_msec() < stop_deadline:
		await process_frame
	if _owned.state != LocalMatch.State.IDLE:
		push_error("earned_rewards_live: owned child did not retire")
		_failed = true
	if _failed:
		return
	change_scene_to_file("res://scenes/boot_menu.tscn")
	await process_frame
	await process_frame
	var menu: Node = current_scene
	await menu._show("rewards")
	var panel: RewardsPanel = menu._root.get_node("RewardsPanel")
	panel._selectors["title"].item_selected.emit(1)
	panel._selectors["emblem"].item_selected.emit(1)
	panel._selectors["finish"].item_selected.emit(2)
	panel._commit()
	await process_frame
	await menu._show("rewards")
	await RenderingServer.frame_post_draw
	_grab().save_png(_out_dir.path_join("earned-profile.png"))
	var reloaded: PlayerRecords = PlayerRecords.for_tree(self)
	if reloaded.unlocks.size() != 2 or reloaded.customization != {"title": "on_file", "emblem": "transfer_stamp", "finish": "margin_teal"}:
		push_error("earned_rewards_live: appearance did not survive menu save/reload")
		_failed = true
	else:
		print("earned_rewards_live: PASS real secret, completion, profile persistence and earned appearance")
	await super._retire_scene()
