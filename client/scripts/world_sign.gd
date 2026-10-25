class_name WorldSign
extends Label3D

## World copy stays in the catalog. Fit the translated glyphs inside the panel.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
## Retain the authored sign inks independently of menu palette changes.
const PANEL_TEXT: Color = Color("d2bc96")
const PANEL_INK: Color = Color("0c1010")
const BREAKS: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
var message_key: String = ""
var bounds: Vector2 = Vector2.ONE
## Short copy on a small panel (a paper notice, a name card) sizes to its own
## longest line instead of a 512-pixel wrap box, so it fills the panel.
var fitted: bool = false

func configure(key: String, size: Vector2, ink: Color, fit_copy: bool = false) -> void:
	message_key = key
	bounds = size
	fitted = fit_copy
	font = FONT
	font_size = 32
	outline_size = 0
	width = 512.0
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = Label3D.ALPHA_CUT_DISCARD
	double_sided = false
	modulate = ink
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and font != null and message_key != "":
		_refresh()

## Catalog copy, or empty when the key is missing. A raw key never reaches the world.
static func localized(key: String) -> String:
	var copy: String = TranslationServer.translate(key)
	return "" if copy == key else copy

func _refresh() -> void:
	text = localized(message_key)
	if text.is_empty():
		push_error("world_sign: missing localized key " + message_key)
	if fitted:
		# Explicit line breaks only: the copy's own widest line is the box.
		var natural: Vector2 = font.get_multiline_string_size(text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		width = maxf(natural.x + 4.0, 1.0)
	var measured: Vector2 = font.get_multiline_string_size(text,
		HORIZONTAL_ALIGNMENT_CENTER, width, font_size, -1, BREAKS)
	pixel_size = minf(bounds.x / width, bounds.y / maxf(measured.y, 1.0))
