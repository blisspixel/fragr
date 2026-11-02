extends SceneTree

## The humour pass's screens as review stills at the window's own size: the
## main menu motto, callsign page, Graphics, Accessibility and Audio notes,
## the Benchmark page, the first-launch tune card, the join page, a loading
## card, the hold-Tab board with its MVP and aura debt marks, and the fun
## tally feed line. Run it windowed at each size under a real display
## (--resolution 1920x1080, then 1280x800); stills land in LOCALEXCEPTION_QA_DIR.
## Development inspection only, never an acceptance.
const ME: String = "00000000-0000-0000-0000-000000000001"
var _out_dir: String = ""

func _initialize() -> void:
	set_meta("localexception_automated", true)
	_run.call_deferred()

func _run() -> void:
	_out_dir = OS.get_environment("LOCALEXCEPTION_QA_DIR")
	if _out_dir.is_empty():
		push_error("humour_review: LOCALEXCEPTION_QA_DIR is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	set_meta("localexception_settings_path", _out_dir.path_join("settings.cfg"))
	set_meta(&"localexception_tune_offered", true)
	var asked: PackedStringArray = OS.get_environment("LOCALEXCEPTION_QA_SIZE").split("x")
	var size: Vector2i = Vector2i(int(asked[0]), int(asked[1])) if asked.size() == 2 else Vector2i(1920, 1080)
	DisplayServer.window_set_size(size)
	root.size = size
	for frame: int in range(10):
		await process_frame
	var tag: String = "%dx%d" % [size.x, size.y]
	await _menus(tag)
	await _loading(tag)
	await _board(tag)
	quit(0)

func _menus(tag: String) -> void:
	var menu: Node = (load("res://scenes/boot_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await create_timer(1.0).timeout
	for page: String in ["main", "profile", "benchmark", "join"]:
		menu.call("_show", page)
		await create_timer(0.6).timeout
		await _save("%s_menu_%s" % [tag, page])
	menu.call("_show", "settings")
	await create_timer(0.6).timeout
	var panel: SettingsPanel = menu.find_child("SettingsPanel", true, false) as SettingsPanel
	for tab: String in ["GRAPHICS", "ACCESSIBILITY", "AUDIO"]:
		panel.show_page(tab)
		await create_timer(0.5).timeout
		await _save("%s_settings_%s" % [tag, tab.to_lower()])
	# Each graphics tier's line, as the note shows it when that tier is picked.
	panel.show_page("GRAPHICS")
	await create_timer(0.3).timeout
	var quality: OptionButton = panel.find_child("quality", true, false) as OptionButton
	for tier: int in [RenderQuality.POTATO, RenderQuality.ULTRA]:
		quality.select(tier)
		quality.item_selected.emit(tier)
		await create_timer(0.4).timeout
		await _save("%s_settings_graphics_%s" % [tag, RenderQuality.TIER_NAMES[tier].to_lower()])
	menu.call("_show", "main")
	await create_timer(0.4).timeout
	set_meta(&"localexception_tune_offer_force", true)
	menu.call("_open_tune_offer")
	await create_timer(0.6).timeout
	await _save("%s_tune_offer" % tag)
	menu.queue_free()
	await process_frame

func _loading(tag: String) -> void:
	var card: LoadingCard = LoadingCard.new()
	root.add_child(card)
	await create_timer(0.3).timeout
	card.begin_loading()
	await create_timer(0.3).timeout
	await _save("%s_loading_wait" % tag)
	card.queue_free()
	await process_frame

func _board(tag: String) -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	game.free()
	root.add_child(hud)
	hud.set_process(false)
	await process_frame
	var roster: Array = [
		{"id": ME, "name": "Nightfall", "team": "coalition", "score": 5, "deaths": 2},
		{"id": "00000000-0000-0000-0000-000000000002", "name": "Aunt Linda", "team": "coalition", "score": 1, "deaths": 4},
		{"id": "00000000-0000-0000-0000-000000000003", "name": "Never Signed", "team": "union", "score": 7, "deaths": 1},
		{"id": "00000000-0000-0000-0000-000000000004", "name": "Static Kid", "team": "union", "score": 3, "deaths": 3},
		{"id": "00000000-0000-0000-0000-000000000005", "name": "Probe", "team": "union", "score": 0, "deaths": 5}]
	hud.set_match_rules(MatchRules.parse({"mode": "tdm"}))
	hud.set_round_info("Active", 120, 20)
	hud.sync_scores_from_players(roster)
	hud.set_viewer_context(ME, "coalition")
	hud.set_team_scores({"union": 10, "coalition": 6})
	hud.observe_board_story({"story": [{"id": ME, "name": "Nightfall", "kind": "human", "nemesis": "Never Signed", "rivals": [
		{"name": "Never Signed", "kind": "bot", "won": 1, "lost": 5},
		{"name": "Static Kid", "kind": "bot", "won": 4, "lost": 1},
		{"name": "Probe", "kind": "agent", "won": 2, "lost": 2}]}]}, ME)
	hud.set_process(true)
	hud.show_venue_notice(TranslationServer.translate("HUD_FUN_METRICS"))
	await create_timer(0.5).timeout
	await _save("%s_feed_fun_tally" % tag)
	hud.show_round_end("Never Signed", "Frag limit reached", 7)
	hud.sync_scores_from_players(roster)
	hud.set_leaderboard_open(true)
	for frame: int in range(4):
		await process_frame
	await _save("%s_board_marks" % tag)
	hud.set_leaderboard_open(false)
	hud.queue_free()
	await process_frame

func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var path: String = _out_dir.path_join(name + ".png")
	image.save_png(path)
	print("humour_review: saved ", path)
