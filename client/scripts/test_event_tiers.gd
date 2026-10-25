extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_event_tiers: " + message)

func _run() -> void:
	_check_queue()
	_check_identity()
	await _check_presenters()
	await _check_voice_presented()
	await _check_board_identity()
	await _check_board_retirement()
	if _failures == 0:
		print("test_event_tiers: PASS admission clocks, overflow and identity")
	quit(0 if _failures == 0 else 1)

func _check_queue() -> void:
	var queue := HudNoticeQueue.new(5, 64, 4.5)
	var source: Dictionary = {"name": "accepted", "nested": {"team": "union"}}
	queue.push(source)
	source.name = "changed"
	source.nested.team = "coalition"
	queue.advance(30.0)
	_check(queue.active.size() == 1 and queue.active[0].remaining == 4.5, "the prior long frame cannot consume a new admission")
	_check(queue.active[0].payload.name == "accepted" and queue.active[0].payload.nested.team == "union", "arrival facts are copied deeply")
	for index: int in range(4):
		queue.push({"index": index})
	queue.advance(0.0)
	for index: int in range(64):
		_check(queue.push({"waiting": index}), "bounded pending slot is available")
	_check(not queue.push({"rejected": true}) and queue.rejected == 1, "overflow rejects newest without displacing an admission")
	queue.advance(100.0, true)
	_check(queue.active.size() == 5 and queue.pending.size() == 64 and queue.active[0].remaining == 4.5, "cover pauses clocks and admission")
	queue.advance(4.49)
	_check(queue.active.size() == 5 and queue.pending.size() == 64, "visible rows remain for their full lifetime")
	queue.advance(0.02)
	_check(queue.active.size() == 5 and queue.pending.size() == 59 and queue.active[0].payload.waiting == 0, "expiry fills vacancies in FIFO order")
	_check(queue.active[0].remaining == 4.5, "refill does not inherit the expired row's frame delta")
	var serial: int = queue.active[0].serial
	queue.clear()
	queue.push({})
	queue.advance(0)
	_check(queue.active[0].serial > serial and queue.rejected == 0, "retirement cannot reuse old presentation ownership")

func _check_board_retirement() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	var roster: Array = []
	for index: int in range(64):
		roster.append({"id":str(index), "name":"Participant %d" % index, "score":index})
	hud.sync_scores_from_players(roster)
	hud.set_leaderboard_open(true)
	await process_frame
	hud.sync_scores_from_players(roster)
	hud.set_leaderboard_open(true)
	hud.free()
	for frame: int in range(4):
		await process_frame
	# The checker also requires a clean engine log after the pending turn.

func _check_identity() -> void:
	const A: String = "00000000-0000-0000-0000-000000000001"
	const B: String = "00000000-0000-0000-0000-000000000002"
	var identity := FragIdentity.new()
	identity.observe([{"id": A, "name": "Same"}])
	_check(identity.resolve({}, "killer_id", "Same") == A, "unique accepted legacy identity is available")
	_check(identity.resolve({"killer_id": B}, "killer_id", "Same") == B, "a supplied different identity never falls back to the name")
	for malformed: Variant in [3, "self", {}, true]:
		_check(identity.resolve({"killer_id": malformed}, "killer_id", "Same").is_empty(), "malformed modern identity cannot become legacy input")
	identity.observe([{"id": B, "name": "Same"}])
	identity.observe([{"id": A, "name": "Same"}])
	_check(identity.unique("Same").is_empty(), "body omission cannot erase known ambiguity")
	identity.clear()
	var roster: Array = []
	for index: int in range(FragIdentity.LIMIT + 1):
		roster.append({"id": str(index), "name": "Name %d" % index})
	identity.observe(roster)
	_check(identity._names.size() == FragIdentity.LIMIT and identity.unique("Name 0").is_empty(), "exhaustion fails closed without an unbounded history")
	_check(identity.resolve({"killer_id": A}, "killer_id", "Name 0") == A, "exhaustion does not invalidate explicit modern identity")
	identity.clear()
	identity.observe([{"id": A, "name": "Same"}])
	identity.observe_event({"killer_id": B, "killer": "Same"})
	_check(identity.unique("Same").is_empty(), "modern event-only identities retain ambiguity for later legacy events")

func _check_presenters() -> void:
	var feed := FragFeed.new()
	root.add_child(feed)
	feed.set_process(false)
	feed.set_region(Rect2(0, 0, 560, 216))
	var data: Dictionary = {"killer": "TOWN SOCKET 02", "victim": "Nightfall-2", "weapon": "sniper", "killer_team": "union", "victim_team": "coalition"}
	feed.push(data, "a", "b", "a", "union")
	feed._process(10)
	_check(feed.notices.active[0].remaining == 4.5 and feed.notices.active[0].payload.own, "own plate uses actual local identity with full admission lifetime")
	_check(feed.notices.active[0].payload.killer_relation == "mate" and feed.notices.active[0].payload.victim_relation == "foe", "accepted viewer relations use the shared UI helper")
	data.killer_team = "coalition"
	feed.push(data, "a", "b", "", "coalition")
	feed._process(0)
	_check(not feed.notices.active[1].payload.own and feed.notices.active[0].payload.killer_team == "union", "following never becomes local ownership or recolors an old frag")
	feed.push({"killer": "[color=red]literal", "victim": "測試界name", "weapon": "unknown_weapon"})
	feed._process(0)
	var row: PanelContainer = feed._rows[feed.notices.active[2].serial]
	var plain: Label = row.get_node("Content/Killer")
	_check(plain.get_meta("full_name") == "[color=red]literal" and plain.tooltip_text == "[color=red]literal" and row.get_node("Content/Weapon").text == "unknown_weapon", "peer names stay plain and missing glyph uses literal wire ID")
	feed.set_covered(true)
	feed._process(40)
	_check(not feed.visible and feed.notices.active[0].remaining == 4.5, "covered presenter does not age readable time")
	feed.set_covered(false)
	feed._process(0)
	await process_frame
	_check(feed._rows[feed.notices.active[0].serial].size.x == 560, "measured row retains bounded width")
	var objective := ObjectiveCall.new()
	root.add_child(objective)
	objective.set_process(false)
	objective.set_region(Rect2(0, 300, 720, 100))
	objective.push("FIRST")
	objective.push("SECOND")
	objective._process(30)
	_check(objective._copy.text == "FIRST" and objective.notices.active[0].remaining == 1.5, "one objective is admitted at a time")
	objective.set_covered(true)
	objective._process(30)
	objective.set_covered(false)
	objective._process(1.51)
	_check(objective._copy.text == "SECOND" and objective.notices.active[0].remaining == 1.5, "covered objective retains FIFO and gives its successor a full lifetime")
	feed.free()
	objective.free()
	await process_frame

func _check_voice_presented() -> void:
	var feed := CombatFeed.new()
	root.add_child(feed)
	feed.set_process(false)
	feed.set_region(Rect2(0, 0, 560, 230))
	var ducks: Array[float] = []
	feed.host_presented.connect(func(seconds: float) -> void: ducks.append(seconds))
	feed.push("evicted before drawing", MenuTheme.EMBER, 2.0)
	for index: int in range(3):
		feed.push("plain %d" % index)
	for frame: int in range(3):
		await process_frame
	_check(ducks.is_empty(), "a replaced Host row cannot duck before presentation")
	feed.set_covered(true)
	feed.push("covered Host", MenuTheme.EMBER, 2.0)
	feed._process(10)
	for frame: int in range(3):
		await process_frame
	_check(ducks.is_empty(), "covered Host draw notifications cannot duck")
	feed.set_covered(false)
	for frame: int in range(3):
		await process_frame
	_check(ducks == [2.0], "the surviving Host ducks exactly once when first presented")
	feed.set_region(Rect2(0, 0, 520, 230))
	for entry: CombatFeed.Entry in feed._entries:
		entry.label.queue_redraw()
	for frame: int in range(3):
		await process_frame
	_check(ducks == [2.0], "reflow and redraw retain the presentation latch")
	feed.clear()
	feed.push("stale Host", MenuTheme.EMBER, 3.0)
	feed.clear()
	for frame: int in range(3):
		await process_frame
	_check(ducks == [2.0], "retirement invalidates pending first-draw ownership")
	feed.free()
	await process_frame

func _check_board_identity() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	game.free()
	root.add_child(hud)
	hud.set_process(false)
	hud.set_match_rules(MatchRules.parse({"mode":"tdm"}))
	hud.set_round_info("Active", 120, 20)
	hud.sync_scores_from_players([
		{"id":"a", "name":"Same", "score":3, "team":"union", "deaths":1},
		{"id":"b", "name":"Same", "score":2, "team":"coalition", "deaths":4},
	])
	hud.set_viewer_context("a", "union")
	hud.set_leaderboard_open(true)
	for frame: int in range(3):
		await process_frame
	var text: String = hud.leaderboard_text()
	_check(text.count("Same") == 2 and text.count("YOU") == 1 and text.contains("1. [UNION] Same  3  1  --  YOU") and text.contains("2. [FREE] Same  2  4  --"), "duplicate callsigns retain separate identities and counts: " + text)
	_check(hud._leaderboard_rows.get_child(1).get_meta("relation") == "mate" and hud._leaderboard_rows.get_child(2).get_meta("relation") == "foe", "board uses the same relation helper as the feed")
	hud.set_viewer_context("absent", "union")
	_check(not hud.leaderboard_text().contains("YOU"), "unmatched modern identity cannot fall back to a callsign")
	hud.set_board_name("Same")
	_check(not hud.leaderboard_text().contains("YOU"), "ambiguous explicit legacy input has no YOU marker")
	hud.set_viewer_context("", "coalition")
	_check(not hud.leaderboard_text().contains("YOU"), "a spectator's followed side never supplies local identity")
	hud.show_frag_event({"killer":"Same", "victim":"Same", "weapon":"rocket", "killer_team":"union", "victim_team":"coalition"}, "a", "b")
	hud.frag_feed._process(0)
	hud.objective_call.push("preserved")
	hud.set_match_rules(MatchRules.parse({"mode":"tdm"}), false)
	_check(hud.frag_feed.notices.active.size() == 1 and hud.objective_call.notices.pending.size() == 1 and hud._standings.size() == 2, "geometry-only refresh preserves accepted event and roster ownership: " + str([hud.frag_feed.notices.active.size(), hud.frag_feed.notices.pending.size(), hud.objective_call.notices.pending.size(), hud._standings.size(), hud.frag_feed.get_global_rect(), hud._leaderboard.get_global_rect()]))
	hud.set_match_rules(MatchRules.parse({"mode":"ffa"}))
	_check(hud._standings.is_empty(), "a new venue cannot reuse accepted standings")
	hud.reset_event_context(true)
	_check(hud.frag_feed.notices.active.is_empty() and hud.objective_call.notices.pending.is_empty(), "connection retirement clears every event tier")
	hud.free()
	await process_frame
