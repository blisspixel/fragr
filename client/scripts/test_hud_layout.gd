extends SceneTree

## Headless geometry regressions for #437: the top band shared by the HUD
## columns and the frame counter; and result cards whose
## readable copy stays upright while their stamp follows the card's lifetime.
## Rendered evidence is qa_hud_layout.gd; this harness keeps the rules.
## Run: godot --path client --headless --script res://scripts/test_hud_layout.gd

var failures: int = 0
var hud: CanvasLayer
var counter: PerformanceOverlay
var query_answer: Variant = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://test-hud-layout-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_hud_layout: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_band_math()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	hud = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	hud.set_process(false)
	await _test_reservation_validation()
	await _test_real_top_layers()
	await _test_nameplate_blockers()
	await _test_scaled_columns()
	await _test_result_cards()
	await _test_card_placement()
	hud.top_region_query = Callable()
	counter.queue_free()
	hud.queue_free()
	await process_frame
	if failures == 0:
		print("test_hud_layout: PASS top band reservations, nameplate blockers, scaled columns, upright cards, stamp lifetime and card placement")
		quit(0)
	else:
		push_error("test_hud_layout: FAIL with %d failures" % failures)
		quit(1)

func _settle() -> void:
	for index: int in range(3):
		hud.regions.layout()
		await process_frame

func _test_band_math() -> void:
	for width: float in [1920.0, 2560.0, 3440.0]:
		for hud_scale: float in [0.75, 1.0, 1.25, 1.5]:
			for text_scale: float in [hud_scale, hud_scale * 32.0 / 24.0]:
				var band: Dictionary = HudRegions.top_band(width, hud_scale, text_scale)
				var center_x: float = (width - band.center_width) * 0.5
				var tag: String = " at %d, scale %.2f, text %.2f" % [width, hud_scale, text_scale]
				_check(20.0 + band.left_width + HudRegions.GAP <= center_x + 0.01, "corner clears center" + tag)
				_check(center_x + band.center_width + HudRegions.GAP <= width - 16.0 - band.right_width + 0.01, "center clears feed" + tag)
				_check(band.center_width + 0.01 >= minf(HudRegions.CENTER_FLOOR * text_scale, width * 0.5), "center keeps its text floor" + tag)
				_check(band.left_width > 0.0 and band.right_width > 0.0, "sides keep positive width" + tag)
	_check(is_zero_approx(HudRegions.fit_shift(200.0, 400.0, 100.0, 800.0)), "a card that fits stays put")
	_check(is_equal_approx(HudRegions.fit_shift(600.0, 900.0, 100.0, 800.0), -100.0), "a card past the floor moves up the least distance")
	_check(is_equal_approx(HudRegions.fit_shift(50.0, 300.0, 100.0, 800.0), 50.0), "a card above the ceiling moves down the least distance")
	_check(is_equal_approx(HudRegions.fit_shift(300.0, 1200.0, 100.0, 800.0), -200.0), "a card taller than the room keeps its first lines at the ceiling")
	var standard: Dictionary = HudRegions.top_band(1920.0, 1.0)
	_check(is_equal_approx(standard.center_width, 720.0) and is_equal_approx(standard.left_width, 460.0) and is_equal_approx(standard.right_width, 560.0), "100 percent layout keeps the accepted widths: " + str(standard))
	var ffa_line: float = MenuTheme.FONT.get_string_size("MEAT PROXY: 10 // FIRST TO 10 // 12:59", HORIZONTAL_ALIGNMENT_LEFT, -1, MenuTheme.BODY).x
	_check(ffa_line <= standard.center_width, "an FFA score line stays one row at 100 percent: %.0f" % ffa_line)
	var wide: Dictionary = HudRegions.top_band(1920.0, 1.5, 1.5, 700.0)
	_check(wide.center_width >= 700.0 and 20.0 + wide.left_width + HudRegions.GAP <= (1920.0 - wide.center_width) * 0.5 + 0.01, "the center never falls under its widest unbreakable fact")
	var label := Label.new()
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", 36)
	label.text = "UNION 2 : 2 FREE COALITION // FIRST TO 25 // 2:35"
	var wrapped: String = HudRegions.wrap_segments(label.text, MenuTheme.FONT, 36, HudRegions.segment_width(label))
	_check(wrapped == "UNION 2 : 2 FREE COALITION\nFIRST TO 25 // 2:35", "match facts wrap only between whole facts: " + wrapped.c_escape())
	_check(HudRegions.wrap_segments(wrapped, MenuTheme.FONT, 36, HudRegions.segment_width(label)) == wrapped, "wrapping twice is stable")
	label.free()
	var reserved: Array[Rect2] = [Rect2(1500, 2, 412, 31)]
	_check(HudRegions.column_top(20.0, 1344.0, 560.0, reserved) > 33.0, "a crossing reservation pushes the column below it")
	_check(is_equal_approx(HudRegions.column_top(16.0, 600.0, 720.0, reserved), 16.0), "a reservation outside the span leaves the column alone")
	_check(is_equal_approx(HudRegions.column_top(16.0, 1500.0 - 100.0, 100.0, reserved), 16.0), "touching edges do not count as crossing")

func _test_reservation_validation() -> void:
	hud.top_region_query = func() -> Variant: return query_answer
	var rejected: Array = [
		"not an array",
		[Vector2(1, 2), "rect", null],
		[Rect2(0, 0, 0, 40), Rect2(10, 10, 100, 0)],
		[Rect2(NAN, 0, 100, 40), Rect2(0, 0, INF, 40)],
	]
	for answer: Variant in rejected:
		query_answer = answer
		_check(hud.regions.reserved_regions().is_empty(), "invalid reservation answer is ignored: " + str(answer))
	query_answer = [Rect2(600, 0, 720, 64), "junk"]
	var kept: Array[Rect2] = hud.regions.reserved_regions()
	_check(kept.size() == 1 and kept[0] == Rect2(600, 0, 720, 64), "valid rectangles survive beside junk")
	hud.top_region_query = Callable()
	_check(hud.regions.reserved_regions().is_empty(), "no query means no reservations")
	await _settle()

func _busy_top() -> void:
	hud.set_mode("SPECTATING")
	hud.set_match_rules(MatchRules.parse({"mode": "tdm", "mutators": ["rail-only"], "friendly_fire": true}))
	hud.set_round_info("Active", 164, 30)
	hud.set_team_scores({"union": 27, "coalition": 29})
	for index: int in range(5):
		hud.show_frag_event({"killer": "Extremely Long Callsign Of Record", "victim": "Static Kid %d" % index, "weapon": "rail"}, "a", "b%d" % index)
	hud.frag_feed._process(0.0)

func _test_real_top_layers() -> void:
	counter = PerformanceOverlay.new()
	root.add_child(counter)
	hud.top_region_query = func() -> Array[Rect2]: return [counter.occupied_region()]
	_busy_top()
	await _settle()
	var base_feed: float = hud.frag_feed.position.y
	var base_center: float = hud.mode_chip_label.position.y
	var base_corner: float = hud.get_node("Panel").position.y
	_check(counter.occupied_region() == Rect2(), "an off counter reserves nothing")
	var view: Rect2 = hud.get_viewport().get_visible_rect()
	counter.set_mode(PerformanceOverlay.DETAIL)
	# The readout before its first refresh is empty; the region already holds the widest text.
	var region: Rect2 = counter.occupied_region()
	_check(region.has_area() and view.encloses(region), "detail counter reserves a region inside the view: " + str(region))
	counter.get_node("FrameCounter").text = PerformanceOverlay.format(PerformanceOverlay.DETAIL, {"fps": 999.0, "frame_ms": 16.7, "low_fps": 888.0})
	await _settle()
	var drawn: Rect2 = HudRegions.text_bounds(counter.get_node("FrameCounter"))
	_check(view.encloses(drawn), "a wide readout grows inward instead of past the right edge: " + str(drawn))
	_check(region.encloses(drawn), "the reservation covers the drawn readout")
	_check(hud.frag_feed.position.y >= region.end.y, "frag feed starts below the counter")
	_check(not hud.frag_feed.get_global_rect().intersects(drawn), "frag rows never sit under the counter")
	_check(is_equal_approx(hud.mode_chip_label.position.y, base_center) and is_equal_approx(hud.get_node("Panel").position.y, base_corner), "counter does not move columns it does not cross")
	# Dynamic change: retire the layer and the columns return. (A benchmark
	# hides the match HUD outright, and its own HUD clears the counter; see
	# test_benchmark.gd.)
	counter.set_mode(PerformanceOverlay.OFF)
	await _settle()
	_check(is_equal_approx(hud.frag_feed.position.y, base_feed) and is_equal_approx(hud.mode_chip_label.position.y, base_center), "columns return when the layer turns off")

## A watched match's nameplate never draws under a HUD plate: the FOLLOWING
## context plate (seen in tour_combat_follow on 2026-10-24) and the frag feed
## rows are blockers, and a plate touching one yields while a clear one stays.
func _test_nameplate_blockers() -> void:
	_busy_top()
	hud.weapon_label.text = "FOLLOWING: AUNT LINDA [BAL]\nRIFLE"
	hud.weapon_label.show()
	hud.map_chip_label.text = "LARAK LOT"
	hud.map_chip_label.show()
	hud.round_message.hide()
	await _settle()
	hud.regions.fit_backings()
	var plate: Panel = hud.regions.backings["context"]
	_check(plate.visible, "the context plate backs the FOLLOWING facts")
	var blockers: Array[Rect2] = hud.regions.world_label_blockers()
	var context: Rect2 = plate.get_global_rect()
	_check(blockers.any(func(rect: Rect2) -> bool: return rect.encloses(context)), "the context plate blocks world labels: " + str(context))
	_check(hud.frag_feed.get_child_count() > 0, "the busy top band has frag rows")
	for row: Node in hud.frag_feed.get_children():
		var row_rect: Rect2 = (row as Control).get_global_rect()
		_check(blockers.any(func(rect: Rect2) -> bool: return rect.encloses(row_rect)), "frag feed rows block world labels")
	var plates: Array[Dictionary] = [
		{"id": "under", "rect": Rect2(context.position + Vector2(16.0, -12.0), Vector2(320.0, 24.0)), "priority": 1, "distance": 6.0},
		{"id": "clear", "rect": Rect2(560.0, 400.0, 180.0, 24.0), "priority": 2, "distance": 12.0},
	]
	_check(NameplateLayout.choose(plates, blockers) == ["clear"], "a nameplate under a HUD plate hides and a clear one stays")
	hud.objective_call.push("COMPLIANCE-DRONE ON DECK.")
	hud.objective_call._process(0.0)
	await _settle()
	var call_rect: Rect2 = hud.objective_call.occupied_region()
	_check(call_rect.has_area() and hud.regions.world_label_blockers().any(func(rect: Rect2) -> bool: return rect.encloses(call_rect)), "the centre call blocks world labels: " + str(call_rect))
	hud.objective_call.clear()
	hud.weapon_label.text = ""
	hud.map_chip_label.text = ""
	await _settle()

func _test_scaled_columns() -> void:
	for spec: Array in [[1.5, FragrSettings.TEXT_LARGE], [1.5, FragrSettings.TEXT_STANDARD], [1.0, FragrSettings.TEXT_LARGE], [0.75, FragrSettings.TEXT_STANDARD]]:
		hud.hud_style = HudStyle.new(spec[0], spec[1], false, hud.hud_style.revision + 1)
		hud.call("_apply_hud_style")
		_busy_top()
		await _settle()
		var center: Rect2 = HudRegions.text_bounds(hud.mode_chip_label)
		var tag: String = " at scale %.2f text %d" % spec
		for label: Label in [hud.mode_label, hud.round_label]:
			_check(not HudRegions.text_bounds(label).intersects(center), "corner text clears center facts" + tag)
		for row: Node in hud.frag_feed.get_children():
			_check(not (row as Control).get_global_rect().intersects(center), "frag rows clear center facts" + tag)
		for line: Node in hud.combat_feed.get_children():
			if line is Label:
				_check(not HudRegions.text_bounds(line).intersects(center), "notices clear center facts" + tag)
	hud.hud_style = HudStyle.new(1.0, FragrSettings.TEXT_STANDARD, false, hud.hud_style.revision + 1)
	hud.call("_apply_hud_style")
	await _settle()

func _upright(message: String) -> void:
	_check(is_zero_approx(hud.round_message.rotation) and hud.round_message.scale.is_equal_approx(Vector2.ONE), message + ": rotation %f scale %s" % [hud.round_message.rotation, hud.round_message.scale])

## No HUD status label, text-bearing container or stamp carries a rotation
## (#437 decision: no tilted text, anywhere). Walks every canvas item in the HUD.
func _level_hud(message: String) -> void:
	var pending: Array[Node] = [hud]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is CanvasItem or not (node as CanvasItem).is_visible_in_tree():
			continue
		var angle: float = (node as CanvasItem).get_global_transform().get_rotation()
		_check(is_zero_approx(angle), "%s is level %s: %f" % [hud.get_path_to(node), message, angle])

func _test_result_cards() -> void:
	var stamp: StampCard = hud.stamp_card
	_check(hud.get_children().find(stamp) > hud.get_children().find(hud.round_backdrop) and hud.get_children().find(stamp) < hud.get_children().find(hud.round_message), "ink draws on the backing and under the copy")
	for reduced: bool in [false, true]:
		var mode: String = "reduced" if reduced else "standard"
		hud.reduced_motion = reduced
		hud.show_round_end("Winner", "frag limit", 20, "", [{"name": "Winner", "score": 20}], "free")
		_upright("round result copy lands upright, " + mode)
		_check(stamp.active() and stamp.visible, "result is stamped, " + mode)
		_check(is_equal_approx(stamp.ink_scale, 1.0 if reduced else StampCard.FRAME1_SCALE), "only the ink carries the settle, " + mode)
		stamp._process(0.016)
		_check(is_equal_approx(stamp.ink_scale, 1.0) and not stamp.is_animating, "ink settles at 100 percent, " + mode)
		_upright("copy stays upright after settle, " + mode)
		var ink: Rect2 = stamp.ink_rect()
		var copy: Rect2 = stamp.get_global_transform().affine_inverse() * HudRegions.text_bounds(hud.round_message)
		_check(ink.encloses(copy), "border surrounds the drawn copy, " + mode)
		_level_hud("after a settled result, " + mode)
		# Consecutive cards: the next result replaces the ink; nothing leaks.
		hud.show_sabotage_result("UNION TAKES ROUND 3\nCHARGE DETONATED", "")
		_upright("consecutive backed result is upright, " + mode)
		_level_hud("after a backed result, " + mode)
		_check(stamp.active() and hud.round_backdrop.visible, "backed result is stamped on its backing, " + mode)
		hud.show_episode_fail("HOST: Reload.")
		_upright("episode fail copy is upright, " + mode)
		_check(not hud.round_backdrop.visible and is_equal_approx(hud.round_message.offset_left, -600.0), "unbacked card does not inherit backed geometry, " + mode)
		hud.show_episode_complete("HOST: Done.", "Next: Episode V")
		_upright("episode complete copy is upright, " + mode)
		_level_hud("after episode cards, " + mode)
		# An ordinary card after a result carries no ink.
		hud.show_round_start(4)
		_check(not stamp.active() and not stamp.visible, "a new ordinary card retires the result ink, " + mode)
		_upright("ordinary card after results is upright, " + mode)
		_level_hud("after an ordinary card, " + mode)
		# Expiry hides the card and the ink together.
		hud.show_round_end("Winner", "", 20)
		hud.round_banner_remaining = 0.01
		hud._process(0.1)
		_check(not hud.round_message.visible and not stamp.active() and not stamp.visible, "card expiry retires the ink, " + mode)
	hud.reduced_motion = false
	# A card hidden by any other owner retires its ink on the stamp's next frame.
	hud.show_round_end("Winner", "", 20)
	hud.round_message.hide()
	stamp._process(0.016)
	_check(not stamp.active() and not stamp.visible, "ink follows a card hidden elsewhere")
	# A freed target cannot leave a dangling border or an error.
	var orphan: Label = Label.new()
	orphan.text = "TEMPORARY"
	hud.add_child(orphan)
	stamp.trigger_stamp(orphan, MenuTheme.DANGER, true)
	orphan.free()
	stamp._process(0.016)
	_check(not stamp.active() and not stamp.visible, "a freed card retires its ink")
	stamp.trigger_stamp(null, MenuTheme.EMBER)
	_check(not stamp.active() and not stamp.visible, "a null card is never stamped")
	# A transform left by any earlier writer is cleared when the card is stamped.
	hud.round_message.show()
	hud.round_message.rotation = 0.3
	hud.round_message.scale = Vector2(1.2, 1.2)
	stamp.trigger_stamp(hud.round_message, Color(0.65, 0.1, 0.6), false)
	_upright("stamping clears a stale transform")
	_check(stamp.stamp_color == MenuTheme.DANGER, "magenta ink becomes danger red")
	hud.round_message.hide()
	stamp._process(0.016)

func _test_card_placement() -> void:
	hud.hud_style = HudStyle.new(1.5, FragrSettings.TEXT_LARGE, false, hud.hud_style.revision + 1)
	hud.call("_apply_hud_style")
	hud.set_mode("SPECTATING")
	hud.set_map_name("Arena Duel")
	var podium: Array = [{"name": "Extremely Long Callsign Of Record", "score": 30}, {"name": "Aunt Linda", "score": 29}, {"name": "Static Kid", "score": 12}]
	hud.show_round_end("Extremely Long Callsign Of Record", "frag limit", 30, "", podium, "free")
	await _settle()
	var context: VBoxContainer = hud.regions.context
	var copy: Rect2 = HudRegions.text_bounds(hud.round_message)
	var corner: Rect2 = hud.get_node("Panel").get_global_rect()
	_check(copy.position.y >= corner.end.y, "a tall card stays below the corner facts")
	_check(not context.visible or copy.end.y <= context.get_global_rect().position.y, "a tall card never sits on the context stack")
	var offsets: Vector2 = Vector2(hud.round_message.offset_top, hud.round_message.offset_bottom)
	hud.regions.place_card(hud.get_viewport().get_visible_rect().size, hud.regions.reserved_regions())
	hud.regions.place_card(hud.get_viewport().get_visible_rect().size, hud.regions.reserved_regions())
	_check(Vector2(hud.round_message.offset_top, hud.round_message.offset_bottom).is_equal_approx(offsets), "repeated placement does not accumulate a shift")
	hud.round_banner_remaining = 0.01
	hud._process(0.1)
	await _settle()
	_check(context.visible, "context returns with the card gone")
	# A tall backed card grows upward from its anchor; it is brought below the
	# corner, and the next backed card starts from clean backing offsets.
	var tall: String = "\n".join(PackedStringArray(["UNION TAKES ROUND 9", "CHARGE DETONATED", "SITE B DESTROYED", "EXTREMELY LONG CALLSIGN", "OF RECORD PLANTED", "THE HOST OBJECTS"]))
	hud.show_sabotage_result(tall, "")
	await _settle()
	var backing: Rect2 = hud.round_backdrop.get_global_rect()
	_check(backing.position.y >= hud.get_node("Panel").get_global_rect().end.y, "a tall backed card stays below the corner: %s" % backing)
	_check(not hud.regions.context.visible or backing.end.y <= hud.regions.context.get_global_rect().position.y, "a tall backed card never covers the context")
	hud.show_sabotage_result("UNION TAKES ROUND 1", "")
	await _settle()
	_check(is_equal_approx(hud.round_backdrop.offset_bottom, -25.0) and is_zero_approx(hud.regions.card_shift), "the next backed card does not inherit the earlier shift")
	hud.round_message.hide()
	await _settle()
	hud.hud_style = HudStyle.new(1.0, FragrSettings.TEXT_STANDARD, false, hud.hud_style.revision + 1)
	hud.call("_apply_hud_style")
	hud.show_round_end("Winner", "", 20)
	await _settle()
	_check(is_zero_approx(hud.regions.card_shift) and context.visible, "a short card at 100 percent keeps its place and the context")
	hud.round_message.hide()
	await _settle()
