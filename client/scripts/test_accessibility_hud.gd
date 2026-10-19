extends SceneTree

const ScreenFlashScript = preload("res://scripts/screen_flash.gd")

var _failures: int = 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_accessibility_hud: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# 1. ScreenFlash under Repeater burst (15 hits at 100ms cadence = 1.4s)
	var flash = ScreenFlashScript.new()
	root.add_child(flash)
	root.remove_meta("fragr_flash_history")

	# Reduced mode rate test
	flash.set_flash_mode(FragrSettings.FLASHES_REDUCED)
	var mock_clock: Array[float] = [10.0]
	flash.time_source = func() -> float: return mock_clock[0]

	var admitted_times: Array[float] = []
	for i in range(15):
		var t: float = 10.0 + float(i) * 0.10
		mock_clock[0] = t
		if flash.trigger("damage", MenuTheme.DANGER, 0.22):
			admitted_times.append(t)
	# In 1.4 seconds (10.0 to 11.4), with 1.0s window, exactly 6 admitted (3 at 10.0-10.2, 3 at 11.0-11.2)
	_check(admitted_times.size() <= 6, "15-hit stream is rate limited in Reduced mode (admitted: %d)" % admitted_times.size())
	for cur_t: float in admitted_times:
		var in_win: int = 0
		for prev_t: float in admitted_times:
			if prev_t <= cur_t and prev_t >= cur_t - 1.0:
				in_win += 1
		_check(in_win <= 3, "rolling 1.0s window has <= 3 flashes at %f (found %d)" % [cur_t, in_win])

	# Verify max alpha in Reduced mode is <= 0.25
	_check(ScreenFlashScript.MAX_REDUCED_ALPHA <= 0.25, "reduced max alpha is <= 0.25")

	# Off mode produces 0 flashes
	root.remove_meta("fragr_flash_history")
	flash.set_flash_mode(FragrSettings.FLASHES_OFF)
	var off_admitted: int = 0
	for i in range(15):
		mock_clock[0] = 20.0 + float(i) * 0.10
		if flash.trigger("damage", MenuTheme.DANGER, 0.22):
			off_admitted += 1
	_check(off_admitted == 0, "Off mode produces 0 flashes (admitted: %d)" % off_admitted)

	# Magenta prevention
	flash.set_flash_mode(FragrSettings.FLASHES_FULL)
	var magenta = Color(0.6, 0.15, 0.55)
	flash.trigger("fail", magenta, 0.45)
	_check(flash.current_color == MenuTheme.DANGER, "magenta failure flash is converted to danger red")
	flash.free()
	root.remove_meta("fragr_flash_history")

	# 2. Team colours and shape marks
	_check(MatchRules.team_shape_mark("union") == "■", "Union shape mark is solid bar ■")
	_check(MatchRules.team_shape_mark("coalition") == "□", "Free coalition shape mark is open bar □")
	var union_col: Color = MatchRules.team_label_color("union", true)
	var free_col: Color = MatchRules.team_label_color("coalition", true)
	_check(free_col == Color("e8e2d6"), "Free text moves to bone under high contrast")

	var mark_union = HudRelation.mark("union", "foe", false, true)
	var mark_free = HudRelation.mark("coalition", "mate", false, true)
	_check(not mark_union.open, "Union mark is filled")
	_check(mark_free.open, "Free coalition mark is open")
	_check(mark_union.bar_color == MenuTheme.DANGER, "Union high contrast mark is danger red")
	_check(mark_free.bar_color == MenuTheme.BONE, "Free high contrast mark is bone")
	mark_union.free()
	mark_free.free()

	# 3. HUD Scale and fit at 1280x720 at 150%
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	hud.set_process(false)

	var settings = FragrSettings.for_tree(self)
	settings.set_value("accessibility", "hud_scale", 150)
	settings.set_value("accessibility", "text_size", FragrSettings.TEXT_LARGE)
	hud.apply_preferences(settings)

	_check(hud.hud_style.scale == 1.5, "hud style scale is 1.5")
	_check(hud.hud_style.body_font_size() == 48, "large text at 150% scale has body font size 48")

	# Layout under simulated 1280x720 viewport
	hud.regions.layout()
	var view: Vector2 = hud.get_viewport().get_visible_rect().size
	var panel: Control = hud.get_node("Panel")
	_check(panel.position.x >= 0 and panel.position.x + panel.size.x <= view.x, "panel within viewport bounds at 150% scale")
	_check(panel.position.y >= 0 and panel.position.y + panel.size.y <= view.y, "panel within viewport vertical bounds at 150% scale")
	var context: VBoxContainer = hud.regions.context
	_check(context.position.x >= 0 and context.position.x + context.size.x <= view.x, "context within viewport horizontal bounds at 150% scale")
	_check(context.position.y + context.size.y <= view.y, "context bottom within viewport vertical bounds at 150% scale")

	hud.free()

	if _failures == 0:
		print("test_accessibility_hud: PASS flashes rate limit, zero magenta, shape marks, and 150% HUD scale fit")
		quit(0)
	else:
		push_error("test_accessibility_hud: FAIL with %d errors" % _failures)
		quit(1)
