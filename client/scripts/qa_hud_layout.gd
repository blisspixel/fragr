extends SceneTree

## Rendered inspection of the top HUD band and result cards (#437).
##
## Builds the real gameplay HUD from main.tscn beside the real frame counter
## and benchmark HUD layers, walks ordinary, spectator, warm-up, result and
## benchmark states at four window sizes and the supported HUD scale and text
## size extremes, then saves one PNG and one JSON measurement per state. Text
## bounds use each label's font, wrapped lines and full canvas transform, so a
## rotated card or a wrapped banner is measured as drawn, not as its logical box.
##
## Each window size renders into a SubViewport of exactly that many pixels,
## with the project's canvas_items/expand stretch reproduced through
## size_2d_override, so a tiling window manager cannot substitute its own
## window size. Needs a real framebuffer (DISPLAY or WAYLAND_DISPLAY); headless
## stills are blank. Output: FRAGR_HUD_QA_DIR, default .agents/hud-layout/<stamp>.
## Exit 1 if any measured top text overlaps another, leaves the view, or a
## result card is not upright after it settles.

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 1080)]
const BASE: Vector2 = Vector2(1920.0, 1080.0)
const STYLES: Array[Dictionary] = [
	{"name": "s100", "scale": 1.0, "text": FragrSettings.TEXT_STANDARD},
	{"name": "s100-large", "scale": 1.0, "text": FragrSettings.TEXT_LARGE},
	{"name": "s150", "scale": 1.5, "text": FragrSettings.TEXT_STANDARD},
	{"name": "s150-large", "scale": 1.5, "text": FragrSettings.TEXT_LARGE},
	{"name": "s75", "scale": 0.75, "text": FragrSettings.TEXT_STANDARD},
]
## Top-band text must end this far above the crosshair at the canvas center.
const AIM_CLEARANCE: float = 64.0
const LONG_NAME: String = "Extremely Long Callsign Of Record"

var hud: CanvasLayer
var view: SubViewport
var counter: PerformanceOverlay
var bench: BenchmarkHud
var out_dir: String
var report: Array[Dictionary] = []
var problems: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://qa-hud-layout-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("qa_hud_layout: needs a real framebuffer")
		quit(1)
		return
	out_dir = OS.get_environment("FRAGR_HUD_QA_DIR")
	if out_dir.is_empty():
		out_dir = ProjectSettings.globalize_path("res://../.agents/hud-layout/" + Time.get_datetime_string_from_system(true).replace(":", ""))
	DirAccess.make_dir_recursive_absolute(out_dir)
	view = SubViewport.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.size_2d_override_stretch = true
	view.transparent_bg = false
	root.add_child(view)
	var background: ColorRect = ColorRect.new()
	background.color = MenuTheme.SURFACE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(background)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	hud = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	view.add_child(hud)
	counter = PerformanceOverlay.new()
	view.add_child(counter)
	bench = BenchmarkHud.new()
	bench.reserved_query = func() -> Array: return [counter.occupied_region()]
	view.add_child(bench)
	bench.visible = false
	_wire_top_band()
	await process_frame
	for size: Vector2i in SIZES:
		view.size = size
		view.size_2d_override = logical_size(size)
		background.size = Vector2(view.size_2d_override)
		await _frames(4)
		for style: Dictionary in STYLES:
			hud.hud_style = HudStyle.new(style.scale, style.text, false, hud.hud_style.revision + 1)
			hud.call("_apply_hud_style")
			var tag: String = "%dx%d-%s" % [size.x, size.y, style.name]
			for fps: int in [PerformanceOverlay.OFF, PerformanceOverlay.DETAIL]:
				await _scene_ordinary(tag, fps)
				await _scene_benchmark(tag, fps)
			await _scene_warmup(tag)
			await _scene_results(tag)
	var file: FileAccess = FileAccess.open(out_dir.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("qa_hud_layout: %d states, %d problems, output %s" % [report.size(), problems, out_dir])
	if problems == 0:
		print("qa_hud_layout: PASS")
	quit(0 if problems == 0 else 1)

## Production wiring: the match manager supplies the frame counter as a
## reserved top region to the match HUD and to the benchmark HUD.
func _wire_top_band() -> void:
	hud.set("top_region_query", func() -> Array[Rect2]:
		var regions: Array[Rect2] = []
		var rect: Rect2 = counter.occupied_region()
		if rect.has_area():
			regions.append(rect)
		return regions)

## The project stretch: canvas_items with expand keeps 1080 logical rows on a
## wide window and 1920 logical columns on a tall one.
static func logical_size(window: Vector2i) -> Vector2i:
	var aspect: float = float(window.x) / float(window.y)
	if aspect >= BASE.x / BASE.y:
		return Vector2i(roundi(BASE.y * aspect), int(BASE.y))
	return Vector2i(int(BASE.x), roundi(BASE.x / aspect))

func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func _reset_state(fps: int) -> void:
	hud.hide_warmup_tv()
	hud.round_banner_remaining = 0.0
	hud.round_message.visible = false
	hud.reset_event_context(true)
	counter.set_mode(fps)
	if fps != PerformanceOverlay.OFF:
		# A worst-case readout: three-digit rates and a two-digit frame time.
		counter.get_node("FrameCounter").text = PerformanceOverlay.format(fps, {"fps": 999.0, "frame_ms": 16.7, "low_fps": 888.0})
	bench.visible = false
	hud.visible = true

func _busy_match(spectating: bool) -> void:
	hud.set_mode("SPECTATING" if spectating else "PLAYING")
	hud.set_match_rules(MatchRules.parse({"mode": "tdm", "mutators": ["rail-only", "two-lives"], "lives": 2, "friendly_fire": true}))
	hud.set_round_info("Active", 164, 30)
	hud.set_team_scores({"union": 27, "coalition": 29})
	hud.set_score_subject("p1")
	hud.sync_scores_from_players([{"id": "p1", "name": LONG_NAME, "score": 27}, {"id": "p2", "name": "Aunt Linda", "score": 29}])
	for index: int in range(5):
		hud.show_frag_event({"killer": LONG_NAME, "victim": "Static Kid %d" % index, "weapon": "rail", "killer_team": "union", "victim_team": "coalition"}, "p1", "p%d" % (index + 3))
	for index: int in range(3):
		hud.combat_feed.push("HOST: CONTINUANCE COMPLIANCE PING %d. APPROVED LANES ONLY." % index)
	hud.frag_feed._process(0.0)

func _scene_ordinary(tag: String, fps: int) -> void:
	for spectating: bool in [true, false]:
		_reset_state(fps)
		_busy_match(spectating)
		await _capture("%s-%s-fps%d" % [tag, "spectator" if spectating else "player", fps])

func _scene_benchmark(tag: String, fps: int) -> void:
	_reset_state(fps)
	_busy_match(true)
	# A benchmark hides the match HUD; its own plates clear the frame counter.
	hud.visible = false
	bench.visible = true
	bench.apply_style(hud.hud_style)
	for frame: int in range(240):
		bench.push_interval(1.0 / 144.0)
	bench.show_progress({"state": "scoring", "headline": "MEASURING BALANCED", "detail": "Scored. 12 s left for this preset.",
		"overall": 0.62, "marks": PackedFloat32Array([0.25, 0.5, 0.75]), "steps": PackedStringArray(["Record", "Performance", "Balanced", "High"]),
		"step": 2, "elapsed_s": 75.0, "remaining_s": 42.0, "scored_frames": 1150, "scored_s": 8.0})
	await _capture("%s-benchmark-fps%d" % [tag, fps])

func _scene_warmup(tag: String) -> void:
	_reset_state(PerformanceOverlay.FPS)
	hud.set_mode("SPECTATING")
	hud.set_match_rules(MatchRules.parse({"mode": "ffa"}))
	hud.set_round_info("Warmup", 12, 20)
	await _capture("%s-warmup-fps1" % tag)

func _scene_results(tag: String) -> void:
	for reduced: bool in [false, true]:
		_reset_state(PerformanceOverlay.OFF)
		hud.reduced_motion = reduced
		hud.set_mode("SPECTATING")
		hud.set_match_rules(MatchRules.parse({"mode": "ffa"}))
		hud.set_round_info("Ended", 0, 20)
		hud.show_round_end(LONG_NAME, "frag limit", 30, "", [{"name": LONG_NAME, "score": 30}, {"name": "Aunt Linda", "score": 29}, {"name": "Static Kid", "score": 12}], "free")
		await _capture("%s-result-ffa-%s" % [tag, "reduced" if reduced else "standard"], true)
		hud.show_sabotage_result("UNION TAKES ROUND 3\nCHARGE DETONATED // SITE B DESTROYED", "")
		await _capture("%s-result-sabotage-%s" % [tag, "reduced" if reduced else "standard"], true)
		hud.show_sabotage_result("UNION TAKES ROUND 9\nCHARGE DETONATED // SITE B DESTROYED\n%s PLANTED THE CHARGE\nCOALITION 4 : UNION 5\nTHE HOST OBJECTS\nNEXT: SIDES SWAP" % LONG_NAME.to_upper(), "")
		await _capture("%s-result-sabotage-tall-%s" % [tag, "reduced" if reduced else "standard"], true)
		hud.show_episode_fail("HOST: Citizen Handle assigned. Reload.")
		await _capture("%s-result-fail-%s" % [tag, "reduced" if reduced else "standard"], true)
		# A later ordinary card must not inherit a result card's tilt or scale.
		hud.show_round_start(4)
		await _capture("%s-after-result-%s" % [tag, "reduced" if reduced else "standard"], true)
		# The round-start card expires; no ink or card may remain on screen.
		hud._process(1.1)
		await _capture("%s-after-expiry-%s" % [tag, "reduced" if reduced else "standard"], true)
	hud.reduced_motion = false

static func text_bounds(label: Label) -> Rect2:
	return HudRegions.text_bounds(label)

func _top_text() -> Dictionary:
	var named: Dictionary = {}
	named["corner_mode"] = text_bounds(hud.mode_label)
	named["corner_round"] = text_bounds(hud.round_label)
	named["center_facts"] = text_bounds(hud.mode_chip_label)
	named["frame_counter"] = text_bounds(counter.get_node("FrameCounter"))
	if bench.visible:
		var plates: Dictionary = bench.occupied()
		for key: String in plates:
			named["benchmark_" + key] = plates[key]
	var index: int = 0
	for row: Node in hud.frag_feed.get_children():
		if row is Control and (row as Control).is_visible_in_tree():
			named["frag_%d" % index] = (row as Control).get_global_rect()
			index += 1
	index = 0
	for line: Node in hud.combat_feed.get_children():
		if line is Label and (line as Label).is_visible_in_tree():
			named["notice_%d" % index] = text_bounds(line)
			index += 1
	for key: String in named.keys():
		if not (named[key] as Rect2).has_area():
			named.erase(key)
	return named

func _capture(name: String, card: bool = false) -> void:
	hud.regions.layout()
	await _frames(3)
	hud.regions.layout()
	# The stamp settles on its next processed frame; measure the settled card.
	await _frames(2)
	var visible: Rect2 = hud.get_viewport().get_visible_rect()
	var named: Dictionary = _top_text()
	var issues: Array[String] = []
	var keys: Array = named.keys()
	for a: int in range(keys.size()):
		var first: Rect2 = named[keys[a]]
		if not visible.encloses(first.grow(-0.5)):
			issues.append("%s leaves the view %s" % [keys[a], first])
		# Centered top text must not run down into the aiming area.
		if str(keys[a]) == "center_facts" and first.end.y > visible.size.y * 0.5 - AIM_CLEARANCE:
			issues.append("%s reaches the crosshair (bottom %.0f)" % [keys[a], first.end.y])
		for b: int in range(a + 1, keys.size()):
			var second: Rect2 = named[keys[b]]
			# Rows inside one feed are stacked by that feed's own owner.
			if str(keys[a]).get_slice("_", 0) == str(keys[b]).get_slice("_", 0) and str(keys[a]).begins_with("frag"):
				continue
			if first.intersects(second):
				issues.append("%s overlaps %s" % [keys[a], keys[b]])
	var stamp: StampCard = hud.stamp_card
	if stamp.visible and not hud.round_message.is_visible_in_tree():
		issues.append("stamp ink outlives its card")
	var entry: Dictionary = {"state": name, "window": [view.size.x, view.size.y], "logical": [visible.size.x, visible.size.y], "stamp_visible": stamp.visible}
	if card:
		entry["card_rotation_degrees"] = rad_to_deg(hud.round_message.rotation)
		entry["card_scale"] = [hud.round_message.scale.x, hud.round_message.scale.y]
		entry["card_text"] = hud.round_message.text
		if hud.round_message.visible and (not is_zero_approx(hud.round_message.rotation) or not hud.round_message.scale.is_equal_approx(Vector2.ONE)):
			issues.append("result copy not upright at rest: %.2f deg, scale %s" % [rad_to_deg(hud.round_message.rotation), hud.round_message.scale])
		var card_rect: Rect2 = text_bounds(hud.round_message)
		if card_rect.has_area() and not visible.encloses(card_rect):
			issues.append("result copy leaves the view %s" % card_rect)
		entry["card_text_bounds"] = [card_rect.position.x, card_rect.position.y, card_rect.size.x, card_rect.size.y]
		# The card's copy must not sit on any other visible HUD text.
		var others: Dictionary = named.duplicate()
		for label: Node in hud.regions.context.get_children():
			if label is Label:
				others["context_" + str(label.name)] = text_bounds(label)
		for key: String in others:
			var other: Rect2 = others[key]
			if card_rect.has_area() and other.has_area() and card_rect.intersects(other):
				issues.append("result copy overlaps %s" % key)
	var rects: Dictionary = {}
	for key: String in named:
		var rect: Rect2 = named[key]
		rects[key] = [roundf(rect.position.x), roundf(rect.position.y), roundf(rect.size.x), roundf(rect.size.y)]
	entry["top_text"] = rects
	entry["issues"] = issues
	problems += issues.size()
	report.append(entry)
	for issue: String in issues:
		print("qa_hud_layout: %s: %s" % [name, issue])
	var image: Image = view.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(out_dir.path_join(name + ".png"))
