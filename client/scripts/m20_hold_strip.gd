class_name M20HoldStrip
extends Control

## The pier clock and the refuge line, top centre while the hold runs. Both
## are derived from accepted server facts and the snapshot tick: the clock is
## never sent per tick and the HUD never decides when it ends. Upright text
## only; the line reads as a row of blocks so it scans in a glance.
const SEGMENTS: int = 10
var state: Dictionary = {}
var geometry: Dictionary = {}
var server_tick: int = -1
var clock_text: String = ""
var line_text: String = ""
var _panel: PanelContainer
var _row: HBoxContainer
var _clock: Label
var _line: Label
var _blocks: Array[ColorRect] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", MenuTheme.panel(MenuTheme.INK, MenuTheme.BORDER))
	add_child(_panel)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 10)
	_panel.add_child(_row)
	_line = _label()
	_row.add_child(_line)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 3)
	_row.add_child(bar)
	for index: int in range(SEGMENTS):
		var block: ColorRect = ColorRect.new()
		block.custom_minimum_size = Vector2(12, 14)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(block)
		_blocks.append(block)
	_clock = _label()
	_row.add_child(_clock)
	visible = false

func _label() -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", MenuTheme.BODY)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	return label

func apply(value: Dictionary, accepted: Dictionary) -> void:
	state = value if value.get("id") == MissionState.M20_ID and value.get("m20") is Dictionary else {}
	geometry = accepted if accepted.get("id") == MissionState.M20_ID else {}
	_refresh()

func set_tick(tick: int) -> void:
	if tick == server_tick:
		return
	server_tick = tick
	_refresh()

## Seconds as a stable mm:ss, the way the harbour display counts.
static func format_clock(seconds: int) -> String:
	var value: int = maxi(0, seconds)
	return "%02d:%02d" % [value / 60, value % 60]

func _refresh() -> void:
	if _panel == null:
		return
	# The strip leaves at the reprieve: the harbour display, the tower and the
	# machines walking on carry that moment, never a stopped HUD timer.
	var showing: bool = not state.is_empty() and not geometry.is_empty() \
		and state.get("phase") == "in_progress" and state["m20"].has("pier_reached_at") \
		and not state["m20"].has("reprieve_at")
	visible = showing
	if not showing:
		clock_text = ""
		line_text = ""
		return
	var facts: Dictionary = state["m20"]
	var left: int = M20MissionState.seconds_left(geometry, facts, server_tick)
	if left < 0:
		clock_text = tr("M20_HOLD_BREATH")
	else:
		clock_text = format_clock(left)
	_clock.text = clock_text
	var integrity: int = int(facts["refuge_integrity"])
	line_text = tr("M20_HOLD_LINE")
	_line.text = line_text
	var lit: int = ceili(float(integrity) * float(SEGMENTS) / float(M20MissionState.REFUGE_INTEGRITY))
	for index: int in range(_blocks.size()):
		var on: bool = index < lit
		_blocks[index].color = (MenuTheme.EMBER if integrity <= 30 else MenuTheme.BONE) if on else Color(MenuTheme.BORDER, 0.55)
	# The last minute and a worn line take the warning colour; nothing flashes.
	_clock.add_theme_color_override("font_color", MenuTheme.EMBER if left >= 0 and left <= 60 else MenuTheme.BONE)

func _process(_delta: float) -> void:
	if not visible or _panel == null:
		return
	var viewport: Vector2 = get_viewport_rect().size
	_panel.reset_size()
	var size: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = size
	# Top centre, shifted left of the mission card (540 wide, 24 from the
	# right edge, as MissionHud lays it) so a narrow window never stacks the
	# strip over the objective, and above the spectator chrome's second line.
	var card_left: float = viewport.x - minf(540.0, viewport.x - 48.0) - 24.0
	var x: float = minf((viewport.x - size.x) * 0.5, card_left - 12.0 - size.x)
	_panel.position = Vector2(maxf(16.0, x), 14.0)
