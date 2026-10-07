class_name BenchmarkResults
extends CanvasLayer

signal dismissed
var report: Dictionary = {}
var directory: String = ""

func _ready() -> void:
	name = "BenchmarkScoreLayer"
	layer = 120
	var dim: ColorRect = ColorRect.new()
	dim.color = Color("101514e8")
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	margin.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 18)
	scroll.add_child(column)
	_label(column, "BENCHMARK", 40)
	if report.has("error"):
		_label(column, str(report["error"]), 26)
	else:
		_label(column, "Arena Duel, ten bots. The same recorded match and camera for every preset.", 24)
		_label(column, "Average and 1% low: higher is better. Frame times and slow frames: lower is better.", 22)
		var grid: GridContainer = GridContainer.new()
		grid.columns = 8
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 20)
		column.add_child(grid)
		for heading: String in ["PRESET", "AVG FPS", "1% LOW", "P50 MS", "P95 MS", "P99 MS", "MAX MS", "33 MS+"]:
			_label(grid, heading, 22, MenuTheme.AMBER)
		for row: Dictionary in report["runs"]:
			for value: String in [str(row["preset"]), "%.1f" % row["fps"], "%.1f" % row["low_1_count_fps"], "%.2f" % row["median_ms"], "%.2f" % row["p95_ms"], "%.2f" % row["p99_ms"], "%.2f" % row["max_ms"], str(row["over_33_count"])]:
				_label(grid, value, 27)
		_label(column, "1% low averages the slowest 1% of frames. 33 MS+ counts frames taking at least33 ms.\nEach preset scores20 seconds after8 seconds of warm-up. Your settings have been restored.", 21)
		_label(column, str(report["adapter"]) + "  |  " + str(report["renderer"]), 21)
		var first: Dictionary = report["runs"][0]
		_label(column, "Output %d x %d  |  World %d x %d  |  V-sync and frame cap off during the test" % [first["output_size"][0], first["output_size"][1], first["world_size"][0], first["world_size"][1]], 21)
		_label(column, "A new run records a new fight. This result measures this scene on this computer.", 20)
		var save_error: String = str(report.get("save_error", ""))
		_label(column, "JSON and CSV saved in your local benchmark folder." if save_error.is_empty() else save_error, 21)
		if save_error.is_empty() and not directory.is_empty():
			_button(column, "Open results folder", func() -> void: OS.shell_open(directory))
	_button(column, "Back to menu", func() -> void: dismissed.emit()).name = "BenchmarkBack"

static func _label(parent: Node, text: String, size: int, color: Color = MenuTheme.BONE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if not parent is GridContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

static func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme = MenuTheme.build()
	button.custom_minimum_size = Vector2(300, 50)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
