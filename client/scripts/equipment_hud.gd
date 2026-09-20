class_name EquipmentHud
extends Control

## Presentation of the local participant's last authoritative inventory only.
var state: Dictionary = {}
var tick: int = 0
var counts: Label
var caption: Label
var bar: ColorRect
var dry_seconds: float = 0.0
var _dry_count: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	counts = _label(40, Vector2(0, 24))
	caption = _label(16, Vector2.ZERO)
	bar = ColorRect.new()
	bar.position = Vector2(0, 84)
	bar.size = Vector2(0, 4)
	bar.color = MenuTheme.EMBER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	visible = false

func _label(font_size: int, offset: Vector2) -> Label:
	var label: Label = Label.new()
	label.position = offset
	label.size = Vector2(236, 56)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func apply(state_value: Dictionary) -> void:
	var dry: int = int(state_value.get("dry_fire_count", 0))
	if dry > _dry_count:
		dry_seconds = 0.24
	_dry_count = dry
	state = state_value
	if state.is_empty():
		tick = 0
		dry_seconds = 0.0
		visible = false
	else:
		tick = maxi(tick, int(state["tick"]))
		_refresh()

func _process(delta: float) -> void:
	dry_seconds = maxf(0.0, dry_seconds - delta)
	if visible:
		position = get_viewport_rect().size - Vector2(260, 128)
		_refresh()

func _refresh() -> void:
	if state.is_empty() or counts == null:
		return
	var weapon: String = state["selected"]
	var rounds: int = EquipmentState.magazine(state, weapon)
	var reserve: int = EquipmentState.reserve(state, weapon)
	counts.text = "" if weapon == "fists" else "%02d / %02d" % [rounds, reserve]
	caption.text = weapon.to_upper()
	bar.visible = state["reload"] != null
	if bar.visible:
		caption.text = "RELOADING"
		bar.size.x = 236.0 * EquipmentState.reload_progress(state, tick)
	elif weapon != "fists" and rounds == 0:
		caption.text = "R / X: RELOAD" if reserve >= (4 if weapon == "scatter" else 1) else "EMPTY"
	counts.modulate = Color("ec7048") if dry_seconds > 0.0 else Color.WHITE

func lowering() -> float:
	return sin(PI * EquipmentState.reload_progress(state, tick)) * 64.0
