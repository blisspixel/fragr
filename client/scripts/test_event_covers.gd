extends SceneTree

class QuietManager extends "res://scripts/game_manager.gd":
	func _ready() -> void:
		pass

const A: String = "00000000-0000-0000-0000-000000000001"
const B: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0
var game: Node
var hud: CanvasLayer

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://event-covers-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_event_covers: " + message)

func _settle() -> void:
	for frame: int in range(4):
		await process_frame

func _tick(seconds: float) -> void:
	hud.frag_feed._process(seconds)
	hud.objective_call._process(seconds)
	hud.combat_feed._process(seconds)

func _seed() -> void:
	hud.reset_event_context(true)
	hud.show_frag("Accepted", "Victim")
	hud.objective_call.push("OBJECTIVE")
	hud.combat_feed.push("VOICE")
	_tick(0)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	game = load("res://scenes/main.tscn").instantiate()
	game.set_script(QuietManager)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	hud = game.hud
	hud.set_process(false)
	hud.frag_feed.set_process(false)
	hud.objective_call.set_process(false)
	hud.combat_feed.set_process(false)
	hud.event_cover_query = game._event_full_cover
	hud.event_region_query = game._event_cover_regions
	hud.set_match_rules(MatchRules.parse({"mode":"tdm"}))
	hud.set_round_info("Active", 100, 20)
	await _settle()
	await _full_covers()
	await _region_covers()
	await _host_and_identity()
	_conquest_changes()
	await _measured_geometry()
	_mission_attempts()
	game.free()
	await _settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(get_meta("fragr_settings_path"))))
	if failures == 0:
		print("test_event_covers: PASS actual covers, draw ownership, identity and Conquest changes")
	quit(0 if failures == 0 else 1)

func _full_covers() -> void:
	_seed()
	var loading := LoadingCard.new()
	loading.name = "LoadingCard"
	game.add_child(loading)
	loading.set_process(false)
	loading.begin_loading()
	_tick(20)
	_check(not hud.frag_feed.visible and hud.frag_feed.notices.active[0].remaining == 4.5, "actual loading cover pauses visible frag time")
	loading.finish_loading(true)
	_tick(20)
	_check(game._event_full_cover() and hud.objective_call.notices.active[0].remaining == 1.5, "controls card remains a cover after world readiness")
	loading.show_error("retained error")
	_tick(20)
	_check(game._event_full_cover() and hud.combat_feed._entries[0].remaining == 3.0, "error card pauses the independent voice clock")
	loading.free()
	_tick(0)
	_check(hud.frag_feed.visible and hud.frag_feed.notices.active[0].remaining == 4.5, "uncover restores the retained full lifetime")
	var pause := PauseMenu.new()
	game.add_child(pause)
	game.pause_menu = pause
	pause.preferences = FragrSettings.new(str(get_meta("fragr_settings_path")))
	pause.open()
	await _settle()
	_tick(20)
	_check(game._event_full_cover() and not hud.frag_feed.visible, "actual pause veil covers all event lanes")
	pause.show_settings()
	_tick(20)
	_check(not pause._panel.visible and game._event_full_cover(), "settings keeps the pause veil cover while its match panel is hidden")
	pause.close()
	pause.free()
	game.pause_menu = null
	for property: String in ["opening", "interlude", "campaign_results"]:
		var result_test: Script = load("res://scripts/test_campaign_results.gd")
		var result_source: SceneTree = result_test.new()
		var record: Dictionary = result_source._record()
		var result: Dictionary = CampaignResult.select(record, result_source._state(), record.player_id)
		result_source.free()
		var cover: CanvasLayer = CampaignResults.new(result) if property == "campaign_results" else CampaignOpening.new()
		game.add_child(cover)
		game.set(property, cover)
		_tick(20)
		_check(game._event_full_cover() and not hud.objective_call.visible, "visible story/result cover: " + property)
		cover.visible = false
		_check(not game._event_full_cover(), "hidden story/result owner does not cover: " + property)
		game.set(property, null)
		cover.free()
	_tick(0)
	_check(hud.frag_feed.get_index() > hud.sniper_scope.get_index() and hud.objective_call.get_index() > hud.sniper_scope.get_index(), "event tiers draw above the actual scope side bars")
	_check(hud.combat_feed.get_index() > hud.sniper_scope.get_index(), "voice also draws above the actual scope side bars")
	_check(hud.frag_feed.get_index() < hud.warmup_tv.get_index(), "warmup remains above the event tiers")

func _region_covers() -> void:
	_seed()
	var console := FragrConsole.new()
	game.add_child(console)
	game.console = console
	console.set_open(true)
	await _settle()
	_tick(20)
	_check(console.occupied_region().intersects(hud.frag_feed.get_global_rect()) and not hud.frag_feed.visible, "actual console geometry pauses the obscured frag lane")
	console.set_open(false)
	console.free()
	game.console = null
	var mission := MissionHud.new()
	hud.add_child(mission)
	game.mission_hud = mission
	mission.set_process(false)
	mission.show()
	mission._card.hide()
	mission._recovery.show()
	mission._show_recovery("RECOVERY\nCONTINUE OR LEAVE")
	await _settle()
	mission._device_revision = InputDevice.revision
	mission._process(0)
	_tick(20)
	_check(not hud.objective_call.visible and hud.frag_feed.visible, "actual recovery panel covers the objective without covering corner frags: " + str(mission.event_cover_regions()) + " objective=" + str(hud.objective_call.occupied_region()))
	mission.hide()
	var departure := DepartureReview.new()
	game.add_child(departure)
	game.departure_review = departure
	departure.apply({"m05":{"group_released":true, "captives":[]}}, {})
	await _settle()
	_tick(20)
	_check(departure.occupied_region().has_area() and not hud.objective_call.visible and hud.frag_feed.visible, "actual departure review pauses only intersecting event lanes")
	departure.free()
	game.departure_review = null
	mission.free()
	game.mission_hud = null
	_seed()
	hud.sync_scores_from_players([{"id":A,"name":"Short","score":1}])
	hud.set_leaderboard_open(true)
	await _settle()
	_tick(0)
	_check(hud.frag_feed.visible, "short central standings leave the frag region readable")
	var roster: Array = []
	for index: int in range(64):
		roster.append({"id":str(index), "name":"Long participant %d" % index, "score":index})
	hud.sync_scores_from_players(roster)
	await _settle()
	_tick(0)
	_check(not hud.objective_call.visible, "expanded held standings pause covered objective time")
	hud.set_leaderboard_open(false)
	_seed()
	hud._show_round_banner("RESULT", 2.0, true)
	_tick(20)
	_check(not hud.objective_call.visible and hud.frag_feed.visible, "ordinary result card covers center calls and preserves readable corner frags")
	hud._process(2.1)

func _host_and_identity() -> void:
	_seed()
	var ducks: Array[float] = []
	hud.host_spoke.connect(func(seconds: float) -> void: ducks.append(seconds))
	hud.show_host_join("HOST: SAME WORDS")
	hud.sniper_scope.update_scope(1.0, "Sniper", true, true)
	var loading := LoadingCard.new()
	loading.name = "LoadingCard"
	game.add_child(loading)
	loading.set_process(false)
	await _settle()
	_check(ducks.is_empty(), "cover opened before first draw blocks Host duck even before the next feed process")
	loading.free()
	_tick(0)
	await _settle()
	_check(ducks == [2.0], "uncovered Host first draw owns one duck")
	_check(hud.sniper_scope.visible and hud.combat_feed.get_index() > hud.sniper_scope.get_index(), "scoped Host remains above the opaque scope surround")
	hud.show_host_join("HOST: SAME WORDS")
	await _settle()
	_check(ducks == [2.0, 2.0], "a later identical Host arrival is a new presentation")
	hud.reset_event_context(true)
	hud.set_match_rules(MatchRules.parse({"mode":"sabotage"}))
	game._on_event_received({"event":"round_end", "host_line":"HOST: RESULT", "winning_team":"union"})
	await _settle()
	_check(ducks.size() == 3, "Sabotage result card and corner voice share a single duck")
	hud._process(10)
	hud.set_match_rules(MatchRules.parse({"mode":"tdm", "lives":3}))
	game.is_human_player = true
	game.net_client.player_id = A
	game._refresh_ui_context([{"id":A,"name":"Same","team":"union"}])
	game._refresh_ui_context([])
	_check(hud.board_id == A and hud.viewer_team == "union", "joined side survives own-body respawn omission")
	hud.set_own_lives(3)
	game._frag_identity.observe([{"id":A,"name":"Same"}, {"id":B,"name":"Same"}])
	game._on_event_received({"event":"frag","killer":"Same","victim":"Same"})
	_check(hud.own_lives == 3, "ambiguous legacy death cannot consume local lives")
	game._on_event_received({"event":"frag","killer":"Same","victim":"Same","killer_id":A,"victim_id":B})
	_check(hud.own_lives == 3, "another same-named modern victim cannot consume local lives")
	game._on_event_received({"event":"frag","killer":"Same","victim":"Same","victim_id":42})
	_check(hud.own_lives == 3, "malformed supplied victim identity cannot fall back to a name")
	game.is_human_player = false
	game._refresh_ui_context([])
	_check(hud.board_id.is_empty(), "spectator context has no local ownership")

func _conquest_changes() -> void:
	hud.reset_event_context(true)
	var snapshot: Dictionary = load("res://scripts/test_conquest_state.gd").snapshot()
	hud.observe_conquest(snapshot)
	_check(hud.objective_call.notices.pending.is_empty(), "first accepted Conquest snapshot primes silently")
	snapshot.conquest.points[0].capturing = "union"
	snapshot.conquest.points[0].progress = 10
	hud.observe_conquest(snapshot)
	_check(hud.objective_call.notices.pending.is_empty(), "capture progress alone is not a takeover")
	snapshot.conquest.points[0].owner = "union"
	snapshot.conquest.points[4].owner = "coalition"
	hud.observe_conquest(snapshot)
	_check(hud.objective_call.notices.pending.size() == 2, "each actual ownership change queues once")
	if hud.objective_call.notices.pending.size() == 2:
		_check(str(hud.objective_call.notices.pending[0].text).begins_with(ConquestState.label(ConquestState.SITES[0])), "simultaneous changes retain canonical site order")
	hud.observe_conquest(snapshot)
	_check(hud.objective_call.notices.pending.size() == 2, "unchanged accepted owners do not repeat")

func _measured_geometry() -> void:
	hud.reset_event_context(true)
	hud.set_match_rules(MatchRules.parse({"mode":"sabotage"}))
	hud.set_round_info("Active", 100, 20)
	for index: int in range(5):
		hud.show_frag_event({"killer":"測試界abcdefghijklmnopqr", "victim":"測試界abcdefghijklmnopqr", "weapon":"article_blade"}, "", "")
	hud.frag_feed._process(0)
	await _settle()
	for row: Control in hud.frag_feed._rows.values():
		_check(row.get_global_rect().end.y + 12 <= hud.combat_feed.get_global_rect().position.y, "measured Unicode row clears voice reservation")
	# System fallback fonts differ across desktop platforms. Exercise the
	# natural Unicode metrics above, then require deterministic taller rows
	# to prove reflow independently of the host's installed fallback font.
	for row: Control in hud.frag_feed._rows.values():
		row.custom_minimum_size.y = 64
	hud.frag_feed._process(0)
	await _settle()
	_check(hud.frag_feed.reserved_height == 336, "five measured taller rows expand the lane by their actual minimum heights")
	for row: Control in hud.frag_feed._rows.values():
		_check(row.get_global_rect().end.y + 12 <= hud.combat_feed.get_global_rect().position.y, "taller platform/style rows retain the full gap before voice")
	# Long enough to wrap at the objective's pixel size.
	for text: String in ["TOWN SOCKET 02 IS DEFUSING THE CHARGE AT THE CLINIC STEPS", "TOWN SOCKET 02 HAS THE CHARGE AND IS RUNNING FOR THE TRAM STOP"]:
		hud.objective_call.clear()
		hud.objective_call.push(text)
		hud.objective_call._process(0)
		await _settle()
		var rect: Rect2 = hud.objective_call.occupied_region()
		_check(rect.end.y <= 516 and rect.size.y > 96, "wrapped objective grows above its bottom anchor without crossing aim")
		_check(rect == hud.objective_call._plate.get_global_rect(), "cover query uses the actual wrapped plate bounds")
		hud.event_region_query = func() -> Array[Rect2]: return [Rect2(rect.position, Vector2(10, 10))]
		hud.objective_call._process(20)
		_check(not hud.objective_call.visible and hud.objective_call.notices.active[0].remaining == 1.5, "cover in the measured upward extension pauses objective lifetime")
		hud.event_region_query = game._event_cover_regions

func _mission_attempts() -> void:
	for human: bool in [false, true]:
		game.is_human_player = human
		game._event_mission_receipt = ""
		game._on_mission_received({"id":MissionState.ID,"attempt":1,"phase":"in_progress","run":null})
		_seed()
		game._on_mission_received({"id":MissionState.ID,"attempt":1,"phase":"in_progress","run":null})
		_check(hud.objective_call.notices.active.size() == 1, "same-attempt geometry/state refresh preserves calls for human=" + str(human))
		game._on_mission_received({"id":MissionState.ID,"attempt":2,"phase":"in_progress","run":null})
		_check(hud.objective_call.notices.active.is_empty() and hud.combat_feed._entries.is_empty() and hud.frag_feed.notices.active.size() == 1, "accepted retry retires old objectives/voice while retaining frags for human=" + str(human))
		_seed()
		game._on_mission_received({"id":MissionState.ID,"attempt":2,"phase":"in_progress","run":null})
		_check(hud.objective_call.notices.active.size() == 1, "subsequent retry state does not repeatedly clear calls for human=" + str(human))
	game.is_human_player = false
