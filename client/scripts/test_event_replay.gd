extends SceneTree

class Followed extends Node:
	var player_id: String = "bcd3b3bf-d6eb-4cfb-8f45-8127bdb30572"

class ReplayCamera extends Node:
	var followed: Node
	func get_followed_target() -> Node:
		return followed
	func lock_on_frag(_id: String, _seconds: float) -> void:
		pass

var failures: int = 0

func _fixture_path() -> String:
	return "res://qa/fixtures/busy-round-events-20261018.json"

func _harness_name() -> String:
	return "test_event_replay"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_event_replay: " + message)

func _run() -> void:
	var capture: String = OS.get_environment("FRAGR_EVENT_REPLAY_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i(1920, 1080)
		Engine.max_fps = 60
		var background := ColorRect.new()
		background.color = MenuTheme.SURFACE
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(background)
		_check(DirAccess.make_dir_recursive_absolute(capture) == OK, "rendered replay capture directory")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_fixture_path()))
	var modern: bool = fixture.source.get("modern", false)
	_check(fixture.source.sha256 == ("3f07b7890a7edb99dfba328eaf5e141682e90f50f573d8597e400d487f454b3d" if modern else "e93f4dd7ea972331315a462bbfaa4ee06483c5711dd4a08561cec7106252aded"), "retained recording provenance")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	root.add_child(hud)
	hud.set_process(false)
	hud.frag_feed.set_process(false)
	hud.combat_feed.set_process(false)
	hud.objective_call.set_process(false)
	hud.set_round_info("Active", 180, 10)
	game.hud = hud
	game.net_client = game.get_node("NetClient")
	game.is_human_player = false
	var watched := Followed.new()
	if modern:
		watched.player_id = fixture.view.followed_id
	var camera := ReplayCamera.new()
	camera.followed = watched
	game.camera = camera
	var cursor: int = 0
	var admitted: Dictionary = {}
	var live: Dictionary = {}
	var finished: int = 0
	var pickups: int = 0
	var frags: int = 0
	var maximum_pending: int = 0
	var ended_with: int = 0
	var next_capture: int = 15000
	var wall_start: int = Time.get_ticks_msec()
	var now: int = 0
	var previous: int = 0
	while now < int(fixture.source.duration_ms) + 10000:
		while cursor < fixture.entries.size() and int(fixture.entries[cursor].ms) <= now:
			var event: Dictionary = fixture.entries[cursor].event
			if event.event == "frag":
				frags += 1
				if modern:
					_check(MissionState._uuid(event.get("killer_id")) and MissionState._uuid(event.get("victim_id")) and event.get("weapon") in ["flechette", "rail", "scatter"], "fresh recorded identities and resolved weapon provenance remain intact")
				else:
					_check(not event.has("weapon") and not event.has("killer_id") and not event.has("victim_id"), "recorded legacy facts must remain absent")
			var before: int = hud.combat_feed.get_child_count()
			game._on_event_received(event)
			if event.event == "pickup" and event.get("player_id") == watched.player_id:
				pickups += 1
				_check(hud.combat_feed.get_child_count() >= before, "followed personal pickup takes its own voice lane")
			if event.event == "round_end":
				ended_with = hud.frag_feed.notices.active.size()
			cursor += 1
		var delta: float = float(now - previous) / 1000.0 if not capture.is_empty() else 0.016
		hud._process(delta)
		hud.frag_feed._process(delta)
		hud.combat_feed._process(delta)
		hud.objective_call._process(delta)
		maximum_pending = maxi(maximum_pending, hud.frag_feed.notices.pending.size())
		var current: Dictionary = {}
		for entry: Dictionary in hud.frag_feed.notices.active:
			var serial: int = entry.serial
			current[serial] = true
			if not admitted.has(serial):
				admitted[serial] = now
		for serial: Variant in live:
			if not current.has(serial):
				_check(now - int(admitted[serial]) >= 4500, "every admitted frag retains its full 4.5-second lifetime")
				finished += 1
		live = current
		previous = now
		if capture.is_empty():
			now += 16
		else:
			if now >= next_capture:
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png(capture.path_join("replay-%d.png" % now)) == OK, "save rendered retained HUD replay")
				next_capture += 20000
			await process_frame
			now = Time.get_ticks_msec() - wall_start
	_check(cursor == fixture.entries.size() and frags == int(fixture.expected.frags) and admitted.size() == frags and finished == frags, "complete ordered busy round and post-result drain")
	_check(pickups == int(fixture.expected.get("personal_pickups", 4)), "declared Scout Ant replay view exercises actual personal pickups")
	_check((modern or not capture.is_empty() or (maximum_pending == 1 and ended_with == 3)) and hud.frag_feed.notices.rejected == 0, "original busy-round queue and RoundEnd boundary remain observable")
	if not capture.is_empty():
		print("RENDERED_REPLAY ", JSON.stringify({"duration_ms": now, "frags":frags, "expired":finished, "peak_pending":maximum_pending, "visible_at_result":ended_with, "source_sha256":fixture.source.sha256}))
	_check(hud.frag_feed.notices.active.is_empty() and hud.frag_feed.notices.pending.is_empty(), "advance beyond the final recorded frag's expiry")
	_check_round_boundary(hud)
	game.free()
	camera.free()
	watched.free()
	hud.free()
	await process_frame
	await process_frame
	if failures == 0:
		print(_harness_name() + ": PASS %d frags, %d personal pickups, full lifetimes and result drain" % [frags, pickups])
	quit(0 if failures == 0 else 1)

func _check_round_boundary(hud: CanvasLayer) -> void:
	hud.reset_event_context(true)
	for index: int in range(6):
		hud.show_frag("Killer %d" % index, "Victim")
	hud.frag_feed._process(0)
	hud.show_round_end("Winner", "Frag limit", 10, "Round closed")
	hud.show_warmup_bumper("Next round", 4, [])
	hud.frag_feed._process(10)
	_check(hud.frag_feed.notices.active.size() == 5 and hud.frag_feed.notices.pending.size() == 1 and hud.frag_feed.notices.active[0].remaining == 4.5, "warmup covers but never discards visible or queued frags")
	hud.show_round_start(2, "Round open")
	hud.frag_feed._process(0)
	_check(hud.frag_feed.notices.pending.size() == 1, "ordinary round start preserves pending frags")
	hud.frag_feed._process(4.51)
	_check(hud.frag_feed.notices.active.size() == 1 and hud.frag_feed.notices.active[0].remaining == 4.5, "the pending frag gets its own full admission after the boundary")
