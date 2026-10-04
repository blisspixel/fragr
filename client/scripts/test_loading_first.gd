extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://loading-first-%d.cfg" % OS.get_process_id())
	set_meta("fragr_records_memory", true)
	MouseCapture.release()
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_loading_first: " + message)

func _run() -> void:
	var card: LoadingCard = LoadingCard.new()
	card.begin_loading()
	root.add_child(card)
	card._process(10.0)
	card.dismiss()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	card._unhandled_input(key)
	_check(card.visible and card.waiting_for_world and not card._bar.visible,
		"elapsed time and early keys cannot reveal a pending world or claim progress")
	card.finish_loading(true)
	_check(not card.waiting_for_world and card.visible and card._bar.visible,
		"real readiness starts the existing controls card")
	card._process(0.4)
	card._unhandled_input(key)
	_check(not card.visible, "ready controls card permits dismissal")
	await process_frame

	set_meta("fragr_boot", {"mode": "spectate", "host": "127.0.0.1:1"})
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	# Stop polling the deliberately unreachable connection. Geometry and
	# snapshot ordering below are delivered at the real presenter boundaries.
	scene.net_client.set_process(false)
	card = scene.get_node_or_null("LoadingCard") as LoadingCard
	_check(card != null and card.visible and card.waiting_for_world and scene.controls_blocked(),
		"the main scene already covers its default arena before the first frame")
	var info: Dictionary = {"map_id": 1, "map_name": "Arena Duel", "half_extent": 20.0,
		"geometry_version": 2, "solids": [
			{"min_x": -3.0, "max_x": 3.0, "min_z": -3.0, "max_z": 3.0, "bottom": 0.0, "top": 2.0}]}
	scene._on_map_info(info)
	await process_frame
	_check(card.visible and card.waiting_for_world,
		"geometry alone does not expose a world without its matching snapshot")
	scene._queue_world_reveal({"map_id": 2})
	await process_frame
	_check(card.visible and card.waiting_for_world, "another map's snapshot cannot release the curtain")
	scene._queue_world_reveal({"map_id": 1})
	scene._on_server_error("A failed connection remains observable.")
	await process_frame
	await process_frame
	_check(card.visible and card.failed and card._return.visible and card._hint.text.contains("failed connection"),
		"an error cancels queued reveal and offers return without exposing the world")
	scene._begin_world_load()
	scene._queue_world_reveal({"map_id": 1})
	await process_frame
	_check(card.visible and card.waiting_for_world, "a new loading generation also requires geometry")
	scene._on_map_info(info)
	scene._queue_world_reveal({"map_id": 1})
	for index: int in range(4):
		await process_frame
	_check(scene.get_node_or_null("LoadingCard") == null,
		"spectator world becomes visible after matching readiness and a completed frame")
	_check(scene.place_armed and scene.throw_armed,
		"released devices accept a fresh press immediately after reveal")
	Input.action_press("throw_grenade")
	scene._on_loading_dismissed()
	_check(not scene.throw_armed and scene.place_armed,
		"a device held through dismissal still requires release")
	Input.action_release("throw_grenade")
	scene.show_loading_card(true)
	card = scene.get_node("LoadingCard") as LoadingCard
	card.finish_loading(false)
	_check(not scene.controls_blocked() and scene.place_armed and scene.throw_armed,
		"dismissal cannot block and disarm the next action while deferred deletion is pending")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "automation never captures the pointer")
	scene.queue_free()
	await process_frame
	# Scene teardown stops the radio; allow its mixer to release the decoder.
	await create_timer(0.1).timeout
	remove_meta("fragr_boot")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(get_meta("fragr_settings_path"))))
	if _failures == 0:
		print("test_loading_first: PASS first frame, real readiness, stale snapshots, errors and spectator reveal")
	quit(0 if _failures == 0 else 1)
