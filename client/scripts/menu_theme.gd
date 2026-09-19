extends RefCounted
class_name MenuTheme

## Shared pixel type and square, worn-metal controls for every front-end page.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
const INK: Color = Color("0c1010")
const BONE: Color = Color("d2bc96")
const EMBER: Color = Color("efb56e")

static func panel(fill: Color = Color("202320"), edge: Color = Color("68553b")) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(3)
	style.shadow_color = INK
	style.shadow_size = 6
	style.shadow_offset = Vector2(4, 5)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 24
	for type in ["Button", "OptionButton", "CheckButton", "LineEdit", "PopupMenu", "Label"]:
		theme.set_color("font_color", type, BONE)
		theme.set_color("font_hover_color", type, EMBER)
		theme.set_color("font_focus_color", type, EMBER)
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color("6b6960"))
		theme.set_color("font_outline_color", type, INK)
		theme.set_constant("outline_size", type, 2)
	for type in ["Button", "OptionButton", "LineEdit", "CheckButton"]:
		theme.set_stylebox("normal", type, panel())
		theme.set_stylebox("hover", type, panel(Color("362d23"), EMBER))
		theme.set_stylebox("pressed", type, panel(Color("4a241b"), EMBER))
		theme.set_stylebox("focus", type, panel(Color(0, 0, 0, 0), EMBER))
		theme.set_stylebox("disabled", type, panel(Color("191d1c"), Color("393c35")))
	theme.set_stylebox("panel", "PopupMenu", panel())
	theme.set_stylebox("hover", "PopupMenu", panel(Color("4a241b"), EMBER))
	theme.set_stylebox("slider", "HSlider", panel(Color("0e1312")))
	theme.set_stylebox("grabber_area", "HSlider", panel(Color("795130")))
	return theme
