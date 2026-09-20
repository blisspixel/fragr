class_name WorldSign
extends Label3D

## World copy stays in the catalog. Fit the translated glyphs inside the panel.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
const BREAKS: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
var message_key: String = ""
var bounds: Vector2 = Vector2.ONE

func configure(key: String, size: Vector2, ink: Color) -> void:
	message_key = key
	bounds = size
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

func _refresh() -> void:
	text = tr(message_key)
	var measured: Vector2 = font.get_multiline_string_size(text,
		HORIZONTAL_ALIGNMENT_CENTER, width, font_size, -1, BREAKS)
	pixel_size = minf(bounds.x / width, bounds.y / maxf(measured.y, 1.0))
