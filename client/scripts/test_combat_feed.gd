extends SceneTree

class Fighter extends Node:
	var player_id: String = "watched"

class CameraProbe extends Node:
	var target: Node
	var punches: int = 0
	func get_followed_target() -> Node:
		return target
	func camera_punch() -> void:
		punches += 1

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_combat_feed: " + message)

func _run() -> void:
	var feed: CombatFeed = CombatFeed.new()
	root.add_child(feed)
	feed.set_process(false)
	feed.push("older")
	feed._process(2.9)
	feed.push("newer")
	feed._process(0.2)
	_check(feed.get_child_count() == 1 and feed.get_child(0).text == "newer", "older expiry cannot hide a newer event")
	for index: int in range(100):
		feed.push(str(index))
	_check(feed.get_child_count() == 3 and feed.get_child(0).text == "97", "event bursts retain only the latest three rows")
	feed.push("[b]plain[/b]\nsecond line")
	_check(feed.get_child(2).text == "[b]plain[/b] second line", "peer text cannot introduce markup or extra lines")
	feed._process(3.1)
	_check(feed.get_child_count() == 0, "all rows expire without delayed callbacks")
	feed.queue_free()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	root.add_child(hud)
	hud.set_mode("PLAYING")
	game.hud = hud
	game.net_client = game.get_node("NetClient")
	game.net_client.player_id = "self"
	game.is_human_player = true
	var camera: CameraProbe = CameraProbe.new()
	var watched: Fighter = Fighter.new()
	camera.target = watched
	game.camera = camera
	game._on_event_received({"event":"pickup", "player":"Same label", "player_id":"other", "kind":"health", "amount":25})
	_check(hud.combat_feed.get_child_count() == 0, "another fighter's pickup is silent regardless of callsign")
	game._on_event_received({"event":"pickup", "player":"Same label", "player_id":"self", "kind":"health", "amount":25})
	_check(hud.combat_feed.get_child_count() == 1, "own pickup reaches the corner feed")
	game.is_human_player = false
	_check(game._shows_participant_notice("watched") and not game._shows_participant_notice("self"), "spectator notices follow the actual watched identity")
	camera.target = null
	_check(not game._shows_participant_notice("watched"), "free camera has no participant pickup notices")
	game.is_human_player = true
	game._on_event_received({"event":"frag", "killer":"Other", "victim":"Victim"})
	game._on_event_received({"event":"killstreak", "player":"Other", "player_id":"other", "streak":3, "tier":"triple", "message":"A loud announcement"})
	hud.show_speak("Agent", "Free weights.")
	hud.show_compliance_ping("Pressure")
	hud.show_boss_spawn("Drone", "Compliance drone")
	hud.show_boss_down("Gone", "Other")
	hud.show_host_join("Joined midway through combat")
	_check(not hud.round_message.visible, "routine combat events never occupy the centre")
	_check(not hud.streak_flash.visible and camera.punches == 0, "other people's events do not flash or shake the view")
	_check(hud.combat_feed.get_child_count() == 3, "all event routes share the same bound")
	var mission: MissionHud = MissionHud.new()
	hud.add_child(mission)
	mission.apply({"rules": {"difficulty": "standard"}, "phase": "find_transfer", "prompts": [], "party": [], "run": {"continues": 3, "status": "playing"}}, "self")
	hud.combat_feed.set_campaign(true)
	hud.combat_feed.set_process(false)
	for index: int in range(3):
		hud.combat_feed.push("Resistance dispatch %d: the transfer record is in Annex 67. Keep the exit clear." % index)
	await process_frame
	await process_frame
	mission.visible = true
	mission._process(0.0)
	_check(not hud.combat_feed.get_global_rect().intersects(mission._card.get_global_rect()), "campaign notices never overlap the objective panel")
	_check(not hud.combat_feed.get_global_rect().intersects(hud.vitals.get_global_rect()), "campaign feed reserves the actual health display below")
	_check(hud.combat_feed.get_child(0).horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "existing entries follow campaign layout")
	var capture_path: String = OS.get_environment("FRAGR_FEED_CAPTURE_PATH")
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(capture_path) == OK, "save campaign feed layout fixture")
	hud.combat_feed.set_campaign(false)
	_check(hud.combat_feed.anchor_right == 1.0 and hud.combat_feed.anchor_top == 0.0, "leaving a mission restores the arena corner")
	hud.show_round_start(2, "Round open")
	_check(hud.round_message.visible, "round starts retain a brief announcement")
	hud._process(0.8)
	hud.show_round_end("Winner", "Frag limit", 10, "Round closed", [])
	hud._process(0.3)
	_check(hud.round_message.visible and "Round closed" in hud.round_message.text, "an earlier banner cannot dismiss the newer result")
	hud._process(6.0)
	_check(not hud.round_message.visible, "round result expires through its owned timer")
	game.free()
	camera.free()
	watched.free()
	hud.queue_free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("test_combat_feed: PASS bounded expiry, clear aim, identity filtering and banner ownership")
	quit(0 if _failures == 0 else 1)
