class_name BenchmarkResults
extends CanvasLayer

## The end of a benchmark. A finished run leads with COMPLETE, one card per
## preset with four figures (average FPS, 1% low, 99th percentile frame time,
## frames at or above 33 ms) and one frame-time timeline. Everything else
## (percentiles, hitches, hardware, settings, definitions, the saved files and
## the last compatible run) sits under Details. A stopped run says so and has
## no figures. The actions stay on screen without scrolling.

signal dismissed
signal again_requested

## Widest the stopped card grows; narrower windows keep a side margin.
const STOPPED_WIDTH: float = 1100.0

var report: Dictionary = {}
var directory: String = ""
var saved_basename: String = ""
var previous: Dictionary = {}
var _details: VBoxContainer
var _details_button: Button
var _scroll: ScrollContainer
var _notice: Label

func _ready() -> void:
	name = "BenchmarkScoreLayer"
	layer = 120
	# One focus target across mouse, keyboard and pad, as on every menu.
	MenuFocus.attach(self)
	var screen: Control = Control.new()
	screen.name = "Screen"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.theme = MenuTheme.build(MenuTheme.Context.FRONT_END)
	add_child(screen)
	var dim: ColorRect = ColorRect.new()
	dim.color = MenuTheme.INK
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	screen.add_child(margin)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	var complete: bool = str(report.get("state", "")) == "complete" and report.get("runs") is Array and not (report["runs"] as Array).is_empty()
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	page.add_child(header)
	var title: Label = _label(header, "BENCHMARK COMPLETE" if complete else "BENCHMARK STOPPED", MenuTheme.DISPLAY_MEDIUM, MenuTheme.BONE, true)
	title.name = "Outcome"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var mark: ColorRect = ColorRect.new()
	mark.color = MenuTheme.SUCCESS if complete else MenuTheme.DANGER
	mark.custom_minimum_size = Vector2(0.0, 6.0)
	page.add_child(mark)
	page.move_child(mark, 1)
	if complete:
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.follow_focus = true
		page.add_child(_scroll)
		var body: VBoxContainer = VBoxContainer.new()
		body.name = "Body"
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 12)
		_scroll.add_child(body)
		if previous.is_empty() and not directory.is_empty():
			previous = BenchmarkRun.previous_compatible(directory, report, saved_basename)
		_summary(body)
	else:
		var center: CenterContainer = CenterContainer.new()
		center.name = "Body"
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.add_child(center)
		_stopped(center)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	page.add_child(actions)
	_notice = _label(page, _save_line() if complete else "", MenuTheme.BODY, MenuTheme.MUTED)
	_notice.name = "Notice"
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var again: Button = _button(actions, "Run again", func() -> void: again_requested.emit())
	again.name = "BenchmarkAgain"
	if complete:
		_button(actions, "Copy summary", _copy_summary).name = "BenchmarkCopy"
		if str(report.get("save_error", "")).is_empty() and not directory.is_empty():
			_button(actions, "Open results folder", func() -> void: OS.shell_open(directory)).name = "BenchmarkFolder"
		_details_button = _button(actions, "Details", _toggle_details)
		_details_button.name = "BenchmarkDetails"
	var back: Button = _button(actions, "Back to menu", func() -> void: dismissed.emit())
	back.name = "BenchmarkBack"
	back.grab_focus.call_deferred()

func _summary(body: VBoxContainer) -> void:
	var runs: Array = report["runs"]
	var first: Dictionary = runs[0]
	var size_text: String = "%d x %d" % [int(first["output_size"][0]), int(first["output_size"][1])]
	# One line each at 1080p, so the cards, the whole timeline and the actions
	# share one screen there; smaller windows scroll the body, never the actions.
	_label(body, "One recorded Arena Duel fight per preset. %d s scored after %d s warm-up. %s." % [
		int(report.get("score_seconds", BenchmarkRun.SCORE_SECONDS)), int(report.get("warmup_seconds", BenchmarkRun.PRIME_SECONDS)), size_text], MenuTheme.BODY, MenuTheme.BONE).name = "Scope"
	var cards: HFlowContainer = HFlowContainer.new()
	cards.name = "Presets"
	cards.alignment = FlowContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("h_separation", 20)
	cards.add_theme_constant_override("v_separation", 16)
	body.add_child(cards)
	for index: int in runs.size():
		_card(cards, runs[index], index)
	_label(body, "Higher FPS is better. Lower MS is better. Definitions are under Details.", MenuTheme.BODY, MenuTheme.MUTED).name = "Direction"
	var heading: Label = _label(body, "", MenuTheme.BODY, MenuTheme.EMBER)
	heading.name = "TimelineHeading"
	var chart: BenchmarkChart = BenchmarkChart.new()
	chart.name = "Timeline"
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Rows shrink with the window so the timeline fits beside the cards at 1080p.
	chart.row_height = clampf(roundf(_view_height() * 0.075), BenchmarkChart.MIN_ROW_HEIGHT, BenchmarkChart.ROW_HEIGHT)
	chart.set_runs(runs, float(report.get("score_seconds", BenchmarkRun.SCORE_SECONDS)))
	body.add_child(chart)
	# The scale is named once, in the heading, where no guide label can meet it.
	heading.text = "FRAME TIME, EVERY SCORED FRAME // EACH ROW 0 TO %d MS" % int(chart.ceiling_ms)
	_details = VBoxContainer.new()
	_details.name = "DetailsPanel"
	_details.visible = false
	_details.add_theme_constant_override("separation", 12)
	body.add_child(_details)
	_build_details(_details, runs)

func _card(parent: Container, row: Dictionary, index: int) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.name = "Preset%d" % index
	card.custom_minimum_size = Vector2(440.0, 0.0)
	var plate: StyleBoxFlat = MenuTheme.panel(MenuTheme.SURFACE, MenuTheme.EDGE)
	plate.content_margin_left = 24
	plate.content_margin_right = 24
	plate.content_margin_top = 14
	plate.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", plate)
	parent.add_child(card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var stripe: ColorRect = ColorRect.new()
	stripe.color = BenchmarkChart.series_color(index)
	stripe.custom_minimum_size = Vector2(0.0, 8.0)
	column.add_child(stripe)
	_label(column, str(row["preset"]).to_upper(), MenuTheme.BODY, MenuTheme.BONE)
	# The headline figure carries its own caption on its baseline row.
	var lead: HBoxContainer = HBoxContainer.new()
	lead.add_theme_constant_override("separation", 16)
	column.add_child(lead)
	var average: Label = _label(lead, "%d FPS" % roundi(float(row["fps"])), MenuTheme.DISPLAY_MEDIUM, MenuTheme.BONE, true)
	average.name = "Average"
	var caption: Label = _label(lead, "AVERAGE", MenuTheme.BODY, MenuTheme.MUTED)
	caption.size_flags_vertical = Control.SIZE_SHRINK_END
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for pair: Array in [["1% LOW", "%d FPS" % roundi(float(row["low_1_count_fps"]))],
			["P99 FRAME", "%.1f MS" % float(row["p99_ms"])],
			["33 MS+ FRAMES", str(int(row["over_33_count"]))]]:
		var key: Label = _label(grid, pair[0], MenuTheme.BODY, MenuTheme.MUTED)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var value: Label = _label(grid, pair[1], MenuTheme.BODY, MenuTheme.BONE)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var earlier: Dictionary = _previous_row(int(row.get("quality", -1)))
	if not earlier.is_empty() and float(earlier.get("fps", 0.0)) > 0.0:
		var change: float = (float(row["fps"]) - float(earlier["fps"])) / float(earlier["fps"]) * 100.0
		_label(column, "%+.0f%% VS LAST RUN" % change, MenuTheme.BODY, MenuTheme.CYAN).name = "VersusLast"

func _previous_row(quality: int) -> Dictionary:
	for row: Variant in previous.get("runs", []):
		if row is Dictionary and int(row.get("quality", -2)) == quality:
			return row
	return {}

func _build_details(panel: VBoxContainer, runs: Array) -> void:
	_label(panel, "DETAILS", MenuTheme.BODY, MenuTheme.EMBER)
	var table: GridContainer = GridContainer.new()
	table.name = "Figures"
	table.columns = runs.size() + 1
	table.add_theme_constant_override("h_separation", 32)
	table.add_theme_constant_override("v_separation", 6)
	panel.add_child(table)
	_label(table, "", MenuTheme.BODY, MenuTheme.MUTED)
	for row: Dictionary in runs:
		_label(table, str(row["preset"]).to_upper(), MenuTheme.BODY, MenuTheme.EMBER).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var figures: Array = [
		["Average frame time", "%.2f ms", "mean_ms"], ["Median frame (p50)", "%.2f ms", "median_ms"],
		["95th percentile frame", "%.2f ms", "p95_ms"], ["99th percentile frame", "%.2f ms", "p99_ms"],
		["99.9th percentile frame", "%.2f ms", "p999_ms"], ["Slowest frame", "%.2f ms", "max_ms"],
		["1% low, slowest frames", "%.1f fps", "low_1_count_fps"], ["0.1% low, slowest frames", "%.1f fps", "low_01_count_fps"],
		["Frames at 33 ms or more", "%d", "over_33_count"], ["Frames at 50 ms or more", "%d", "over_50_count"],
		["Hitches against the last second", "%d", "stutter_count"], ["Frames scored", "%d", "count"], ["Seconds scored", "%.2f s", "elapsed_s"],
		["3D render size", "", "world_size"]]
	for figure: Array in figures:
		_label(table, figure[0], MenuTheme.BODY, MenuTheme.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		for row: Dictionary in runs:
			var text: String
			if figure[2] == "world_size":
				text = "%d x %d" % [int(row["world_size"][0]), int(row["world_size"][1])]
			elif str(figure[1]) == "%d":
				text = _thousands(int(row.get(figure[2], 0)))
			else:
				text = str(figure[1]) % float(row.get(figure[2], 0.0))
			_label(table, text, MenuTheme.BODY, MenuTheme.BONE).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var lines: PackedStringArray = PackedStringArray()
	var renderer: String = str(report.get("renderer", ""))
	lines.append("Graphics: %s. %s renderer, %s, API %s." % [report.get("adapter", ""), RenderQuality.renderer_name(renderer), report.get("driver", ""), report.get("graphics_api", "")])
	lines.append("Engine %s, %s build, %s, %s display server." % [report.get("engine", ""), report.get("build", ""), report.get("os", ""), str(report.get("display_server", "unknown"))])
	# The Display settings are the same for every preset; what each preset
	# changes is named from the rules that applied it.
	lines.append("Display settings for every preset: %s." % _settings_text(runs[0].get("settings", {})))
	for row: Dictionary in runs:
		var settings: Dictionary = row.get("settings", {}) if row.get("settings") is Dictionary else {}
		var output: Vector2i = Vector2i(int(row["output_size"][0]), int(row["output_size"][1])) if row.get("output_size") is Array and (row["output_size"] as Array).size() == 2 else Vector2i.ZERO
		lines.append("%s preset: %s." % [row["preset"], RenderQuality.preset_features(int(row.get("quality", 1)), renderer, settings, output)])
	lines.append("Measured: the interval between drawn frames with V-sync and the frame cap off. It is not GPU time, display latency or input latency, and it is not a server or player-capacity test.")
	lines.append("1% low: the average of the slowest 1% of frames, as FPS. 33 MS+ counts frames that took 33 ms or longer.")
	lines.append("Formulas: 1%% low %s. Percentiles: %s." % [report.get("low_1_definition", ""), report.get("percentile_definition", "")])
	var capture: Dictionary = report.get("capture", {}) if report.get("capture") is Dictionary else {}
	lines.append("Recorded fight: %d snapshots, SHA-256 %s. Every preset replayed it. A new run records a new fight." % [int(capture.get("snapshots", 0)), str(capture.get("sha256", "")).left(16)])
	if previous.is_empty():
		lines.append("No earlier compatible run in the results folder. Runs compare only with the same build, display, graphics adapter, renderer, output size and preset settings.")
	else:
		var changes: PackedStringArray = PackedStringArray()
		for row: Dictionary in runs:
			var earlier: Dictionary = _previous_row(int(row.get("quality", -1)))
			if not earlier.is_empty():
				changes.append("%s %d to %d FPS" % [row["preset"], roundi(float(earlier.get("fps", 0.0))), roundi(float(row["fps"]))])
		lines.append("Last compatible run, %s UTC: %s. It recorded its own fight; repeat runs before trusting a small difference." % [str(previous.get("created_utc", "")).replace("T", " "), ", ".join(changes)])
	if not directory.is_empty() and not saved_basename.is_empty():
		lines.append("Saved: %s (.json with every frame interval, .csv summary)." % directory.path_join(saved_basename))
	for line: String in lines:
		var label: Label = _label(panel, line, MenuTheme.BODY, MenuTheme.BONE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

## The settings that shape the rendered frame, in the words the Display page
## uses. Pacing (V-sync, frame cap) is stated once elsewhere; the window mode
## and frame counter do not change what is drawn in the scene.
static func _settings_text(settings: Variant) -> String:
	if not settings is Dictionary:
		return ""
	var values: Dictionary = settings
	var height: int = int(values.get("resolution_height", 0))
	var parts: PackedStringArray = PackedStringArray()
	parts.append("render height %s" % ("native" if height <= 0 else "%d" % height))
	parts.append("upscaling %s" % (["standard", "FSR 1", "FSR 2"] as Array)[clampi(int(values.get("upscaling", 0)), 0, 2)])
	parts.append("world pixels %s" % (["off", "fine", "medium", "chunky"] as Array)[clampi(int(values.get("pixel_scale", 0)), 0, 3)])
	parts.append("dither %s" % ("on" if bool(values.get("dither", false)) else "off"))
	parts.append("field of view %d" % roundi(float(values.get("vertical_fov", 75.0))))
	return ", ".join(parts)

## A stopped run: why, where, what finished, and that nothing was kept, in
## one card in the middle of the page with the actions under it.
func _stopped(parent: Container) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.name = "StoppedCard"
	card.custom_minimum_size = Vector2(minf(STOPPED_WIDTH, _view_width() - 112.0), 0.0)
	var plate: StyleBoxFlat = MenuTheme.panel(MenuTheme.SURFACE, MenuTheme.EDGE)
	plate.content_margin_left = 32
	plate.content_margin_right = 32
	plate.content_margin_top = 20
	plate.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", plate)
	parent.add_child(card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	var stripe: ColorRect = ColorRect.new()
	stripe.color = MenuTheme.DANGER
	stripe.custom_minimum_size = Vector2(0.0, 8.0)
	column.add_child(stripe)
	_label(column, str(report.get("error", "The benchmark stopped.")), MenuTheme.BODY, MenuTheme.BONE).name = "Reason"
	var grid: GridContainer = GridContainer.new()
	grid.name = "Facts"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	var finished: Array = report.get("finished_presets", []) if report.get("finished_presets") is Array else []
	var finished_names: PackedStringArray = PackedStringArray()
	for preset: Variant in finished:
		finished_names.append(str(preset))
	for fact: Array in [["STOPPED DURING", stopped_during(report)],
			["FINISHED", ", ".join(finished_names) + ". Its figures are not kept." if not finished_names.is_empty() else "No preset finished."],
			["SAVED", "Nothing. A stopped run keeps no result."],
			["SETTINGS", "Restored to what you had before the run."]]:
		_label(grid, fact[0], MenuTheme.BODY, MenuTheme.EMBER)
		var value: Label = _label(grid, fact[1], MenuTheme.BODY, MenuTheme.BONE)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(column, "Run again records a new fight. Keep the game window visible and the same size until it finishes.", MenuTheme.BODY, MenuTheme.MUTED).name = "Next"

## The step a stopped run was on, in the words the live readout used.
static func stopped_during(document: Dictionary) -> String:
	var preset: String = str(document.get("interrupted_preset", ""))
	match str(document.get("interrupted", "")):
		"capturing":
			return "Recording the fight."
		"preparing":
			return "Loading %s." % preset if not preset.is_empty() else "Loading a preset."
		"priming":
			return "Warming up %s." % preset if not preset.is_empty() else "Warming up."
		"scoring":
			return "Measuring %s." % preset if not preset.is_empty() else "Measuring."
		_:
			return "Starting."

## The body holds no focusable rows, so focus stays on the actions. Up and
## down (arrows, D-pad, stick) scroll the figures and Details instead, and
## page up and down move a screen, so a keyboard or pad reads everything a
## mouse wheel can.
func _unhandled_input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return
	var step: float = 0.0
	var line: float = float(MenuTheme.BODY) * 3.0
	if event.is_action_pressed("ui_down", true):
		step = line
	elif event.is_action_pressed("ui_up", true):
		step = -line
	elif event.is_action_pressed("ui_page_down", true):
		step = _scroll.size.y * 0.8
	elif event.is_action_pressed("ui_page_up", true):
		step = -_scroll.size.y * 0.8
	if step == 0.0:
		return
	_scroll.scroll_vertical = int(_scroll.scroll_vertical + step)
	get_viewport().set_input_as_handled()

func _toggle_details() -> void:
	_details.visible = not _details.visible
	_details_button.text = "Hide details" if _details.visible else "Details"
	if _details.visible:
		_reveal_details.call_deferred()

func _reveal_details() -> void:
	await get_tree().process_frame
	_scroll.ensure_control_visible(_details)

func _save_line() -> String:
	var save_error: String = str(report.get("save_error", ""))
	if not save_error.is_empty():
		return save_error + " The figures above are still correct for this run."
	return "Saved as JSON and CSV in your benchmark folder. Your settings are restored."

## Plain text for the clipboard: the run, the system and each preset's four figures.
func summary_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("fragr benchmark, %s UTC" % str(report.get("created_utc", "")).replace("T", " "))
	lines.append("Arena Duel, ten bots, recorded fight, %d s scored per preset after %d s warm-up" % [int(report.get("score_seconds", 0)), int(report.get("warmup_seconds", 0))])
	var first: Dictionary = report["runs"][0]
	lines.append("%s, %s, %s, %d x %d, engine %s %s" % [report.get("adapter", ""), RenderQuality.renderer_name(str(report.get("renderer", ""))), report.get("os", ""),
		int(first["output_size"][0]), int(first["output_size"][1]), report.get("engine", ""), report.get("build", "")])
	for row: Dictionary in report["runs"]:
		lines.append("%s: %d fps average, 1%% low %d fps, p99 %.1f ms, %d frames at 33 ms or more" % [row["preset"], roundi(float(row["fps"])),
			roundi(float(row["low_1_count_fps"])), float(row["p99_ms"]), int(row["over_33_count"])])
	return "\n".join(lines)

func _copy_summary() -> void:
	DisplayServer.clipboard_set(summary_text())
	_notice.text = "Summary copied."

func _view_width() -> float:
	return get_viewport().get_visible_rect().size.x if is_inside_tree() else STOPPED_WIDTH + 112.0

## Canvas height the page lays out in (the stretched view, not the window).
func _view_height() -> float:
	return get_viewport().get_visible_rect().size.y if is_inside_tree() else float(BenchmarkChart.ROW_HEIGHT) / 0.075

static func _thousands(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out

static func _label(parent: Node, text: String, size: int, colour: Color, display: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_override("font", MenuTheme.DISPLAY_FONT if display else MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	if not parent is GridContainer and not parent is HBoxContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

static func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text.to_upper()
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.add_theme_font_size_override("font_size", MenuTheme.BODY)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
