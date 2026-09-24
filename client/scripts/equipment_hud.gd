class_name EquipmentHud
extends Control

## Presentation of the local participant's last authoritative inventory only.
## Quiet HUD: an ammunition glyph and one number for the held weapon, no words.
const WIDTH: float = 236.0
const GLYPH: Vector2 = Vector2(28, 36)
const BRASS: Color = Color("c9a15a")
const SHELL_RED: Color = Color("a8402c")
const CELL_STEEL: Color = Color("7d8c93")
const CELL_GLOW: Color = Color("b4e0e8")
const EMPTY_TINT: Color = Color("ec7048")

var state: Dictionary = {}
var tick: int = 0
var counts: Label
var dry_seconds: float = 0.0
var _dry_count: int = 0
## Pool drawn beside the number: bullets, shells, cells, or empty for fists.
var glyph_pool: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(WIDTH, 96)
	counts = Label.new()
	counts.position = Vector2(0, 24)
	counts.size = Vector2(WIDTH - GLYPH.x - 12.0, 56)
	counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counts.add_theme_font_override("font", MenuTheme.FONT)
	counts.add_theme_font_size_override("font_size", 40)
	counts.add_theme_color_override("font_color", MenuTheme.BONE)
	counts.add_theme_color_override("font_outline_color", MenuTheme.INK)
	counts.add_theme_constant_override("outline_size", 6)
	counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(counts)
	visible = false

func apply(state_value: Dictionary) -> void:
	var dry: int = int(state_value.get("dry_fire_count", 0))
	if dry > _dry_count:
		dry_seconds = 0.24
	_dry_count = dry
	state = state_value
	if state.is_empty():
		tick = 0
		dry_seconds = 0.0
		glyph_pool = ""
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
	var shots: int = EquipmentState.shots(state, weapon)
	glyph_pool = str(EquipmentState.POOLS.get(weapon, ""))
	counts.text = "" if shots < 0 else str(shots)
	var empty: bool = shots == 0
	counts.modulate = EMPTY_TINT if dry_seconds > 0.0 or empty else Color.WHITE
	queue_redraw()

func _draw() -> void:
	if glyph_pool.is_empty():
		return
	var origin: Vector2 = Vector2(WIDTH - GLYPH.x, 34)
	var dim: float = 0.45 if EquipmentState.shots(state, str(state.get("selected", ""))) == 0 else 1.0
	match glyph_pool:
		"bullets":
			_bullet(origin + Vector2(2, 0), dim)
			_bullet(origin + Vector2(14, 4), dim)
		"shells":
			_shell(origin + Vector2(2, 2), dim)
			_shell(origin + Vector2(15, 2), dim)
		"cells":
			_cell(origin, dim)

func _block(rect: Rect2, colour: Color, dim: float) -> void:
	draw_rect(rect.grow(2.0), MenuTheme.INK)
	draw_rect(rect, Color(colour.r * dim, colour.g * dim, colour.b * dim, 1.0))

func _bullet(at: Vector2, dim: float) -> void:
	_block(Rect2(at + Vector2(0, 8), Vector2(8, 20)), BRASS, dim)
	var tip: PackedVector2Array = PackedVector2Array([at + Vector2(0, 8), at + Vector2(4, 0), at + Vector2(8, 8)])
	draw_colored_polygon(tip, Color(BRASS.r * dim * 1.1, BRASS.g * dim * 1.05, BRASS.b * dim, 1.0))

func _shell(at: Vector2, dim: float) -> void:
	_block(Rect2(at, Vector2(9, 22)), SHELL_RED, dim)
	_block(Rect2(at + Vector2(0, 22), Vector2(9, 6)), BRASS, dim)

func _cell(at: Vector2, dim: float) -> void:
	_block(Rect2(at + Vector2(9, 0), Vector2(10, 4)), CELL_STEEL, dim)
	_block(Rect2(at + Vector2(2, 4), Vector2(24, 28)), CELL_STEEL, dim)
	_block(Rect2(at + Vector2(8, 10), Vector2(12, 16)), CELL_GLOW, dim)
