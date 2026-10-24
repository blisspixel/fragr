extends RefCounted
class_name MenuTheme

## Canonical UI materials and type. World signs own their separate materials.
## Context is explicit even while both presentations use the dark cabinet.
enum Context { FRONT_END, GAMEPLAY }

const DISPLAY_FONT: Font = preload("res://assets/fonts/BlackOpsOne-Regular.ttf")
const INK: Color = Color("0a0a0c")
const BONE: Color = Color("e8e2d6")
const EMBER: Color = Color("dc8c3c")
const MUTED: Color = Color("8c847a")
const DANGER: Color = Color("e23430")
const SUCCESS: Color = Color("74884e")
const SURFACE: Color = Color("2c2d32")
const INSET: Color = Color("1e1e22")
const BORDER: Color = Color("5a554f")
const EDGE: Color = Color("3a3836")
const RUST: Color = Color("7a3a22")
const CYAN: Color = Color("8cbec6")
const CYAN_DARK: Color = Color("4a8a92")
## Identity modulation preserves the original pixels of weapon and body art.
const UNTINTED: Color = Color.WHITE
const CLEAR: Color = Color.TRANSPARENT
const BODY: int = 24
const LARGE: int = 48
const DISPLAY_SMALL: int = 48
const DISPLAY_MEDIUM: int = 64
const DISPLAY_LARGE: int = 96
const PIXEL_SIZES: Array[int] = [16, 24, 32, 48]
## Focus is the one selected look: a plate framed on all four edges plus a
## heavy left rail, so it reads by shape as well as colour (#435). Hover is a
## thin neutral frame that never resembles it.
const FOCUS_FRAME: int = 4
const FOCUS_RAIL: int = 14
const HOVER_FRAME: int = 2
## Theme type variation for the front menu's borderless list rows.
const MENU_ITEM: StringName = &"MenuItem"
const DISPLAY_SIZES: Array[int] = [48, 64, 96]
const SWATCHES: Dictionary = {
	"ink": INK, "bone": BONE, "ember_hot": EMBER,
	"gunmetal_light": MUTED, "union_red_glow": DANGER,
	"leaf_muted": SUCCESS, "union_steel": SURFACE,
	"union_black": INSET, "gunmetal": BORDER, "gunmetal_dark": EDGE,
	"rust": RUST, "cyan_light": CYAN, "cyan_muted": CYAN_DARK,
}
const GAMEPLAY_COLORS: Dictionary = {
	"text": BONE, "muted": MUTED, "accent": EMBER,
	"danger": DANGER, "success": SUCCESS, "surface": SURFACE,
	"ink": INK, "border": BORDER,
	"inset": INSET, "edge": EDGE, "rust": RUST,
}
const FRONT_END_COLORS: Dictionary = GAMEPLAY_COLORS

static var FONT: Font = _pixel_font()
static var _themes: Dictionary = {}

static func _pixel_font() -> FontFile:
	var source: FontFile = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
	var font: FontFile = source.duplicate() as FontFile
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NONE
	font.oversampling = 1.0
	# Keep fallback glyphs for player-authored Unicode names and chat.
	return font

## Gameplay type rules (#411). Every word on the match HUD is Silkscreen,
## upper case, on the pixel sizes. Black Ops One draws numerals only: the
## vitals, ammunition and countdown digits. A HUD label that sets its own font
## goes through one of these two, so no screen carries a third look.
static func pixel_text(label: Label, size: int = BODY, colour: Color = BONE, outline: int = 3) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", outline)
	label.uppercase = true

static func numeral(label: Label, size: int) -> void:
	label.add_theme_font_override("font", DISPLAY_FONT)
	label.add_theme_font_size_override("font_size", size)

## True when text is only digits and the readout separators the display face
## is allowed to draw.
static func is_numeral_text(text: String) -> bool:
	var stripped: String = text.strip_edges()
	if stripped.is_empty():
		return false
	for character: String in stripped:
		if not character in "0123456789|/:%.+- ":
			return false
	return true

## The backing every HUD text block sits on over the world: the corner voice,
## the bottom-left context and the controls hint. Light crates and sky never
## decide whether small text is readable.
const BACKING_ALPHA: float = 0.8

static func backing(fill: Color = INK) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = alpha(fill, BACKING_ALPHA)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.anti_aliasing = false
	return style

## World text (nameplates, pickup tags, flag and objective marks) uses the
## same pixel face as the HUD, never the engine's smooth fallback.
static func world_text(label: Label3D) -> void:
	label.font = FONT
	label.uppercase = true
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

static func colors(context: Context) -> Dictionary:
	return FRONT_END_COLORS if context == Context.FRONT_END else GAMEPLAY_COLORS

static func alpha(color: Color, opacity: float) -> Color:
	return Color(color, opacity)

## UI relation marks are independent of world faction albedo.
static func team_color(team: String) -> Color:
	match team:
		"union": return DANGER
		"coalition": return EMBER
	return MUTED

static func readable_text(color: Color) -> Color:
	# Small text sits on ink or its outline. Red remains a mark, not body copy.
	for swatch: Color in [BONE, EMBER, MUTED, SUCCESS, CYAN]:
		if color.is_equal_approx(swatch):
			return swatch
	return BONE

static func panel(fill: Color = SURFACE, edge: Color = BORDER) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(3)
	style.shadow_color = INK
	style.shadow_size = 6
	style.shadow_offset = Vector2(3, 6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

## The selected plate. Drawn by Godot over the state style, so the frame sits
## inside the control's own rect: scroll clips, neighbours and shadows cannot
## cut an edge off it. `fill` should contrast with the normal fill.
static func focus_plate(fill: Color, accent: Color = EMBER) -> StyleBoxFlat:
	var style: StyleBoxFlat = panel(fill, accent)
	style.set_border_width_all(FOCUS_FRAME)
	style.border_width_left = FOCUS_RAIL
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	style.anti_aliasing = false
	return style

## Pointer hover without focus: a quiet frame, never the accent.
static func hover_frame(fill: Color, edge: Color = MUTED) -> StyleBoxFlat:
	var style: StyleBoxFlat = panel(fill, edge)
	style.set_border_width_all(HOVER_FRAME)
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	style.anti_aliasing = false
	return style

static func build(context: Context) -> Theme:
	if _themes.has(context):
		return _themes[context]
	var palette: Dictionary = colors(context)
	var theme: Theme = Theme.new()
	theme.default_font = FONT
	theme.default_font_size = BODY
	for type: String in ["Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "PopupMenu", "Label", "TooltipLabel"]:
		theme.set_color("font_color", type, palette.text)
		# Hover text stays plain. Godot draws a focused, hovered button with
		# the hover colour, so focus text matches it and the plate carries focus.
		theme.set_color("font_hover_color", type, palette.text)
		theme.set_color("font_focus_color", type, palette.text)
		theme.set_color("font_pressed_color", type, palette.text)
		theme.set_color("font_hover_pressed_color", type, palette.text)
		theme.set_color("font_disabled_color", type, palette.muted)
		theme.set_color("font_outline_color", type, palette.ink)
		theme.set_constant("outline_size", type, 2)
	for type: String in ["Button", "OptionButton", "LineEdit", "CheckButton", "CheckBox"]:
		theme.set_stylebox("normal", type, panel(palette.surface, palette.border))
		theme.set_stylebox("hover", type, hover_frame(palette.surface, palette.muted))
		theme.set_stylebox("pressed", type, panel(palette.ink, palette.accent))
		theme.set_stylebox("hover_pressed", type, panel(palette.ink, palette.accent))
		theme.set_stylebox("focus", type, focus_plate(palette.ink, palette.accent))
		theme.set_stylebox("disabled", type, panel(palette.ink, palette.border))
	# A switched-on toggle is a value, shown by its switch icon. Drawing it in
	# the accent frame made every enabled option look selected.
	for type: String in ["CheckButton", "CheckBox"]:
		theme.set_stylebox("pressed", type, panel(palette.surface, palette.border))
		theme.set_stylebox("hover_pressed", type, hover_frame(palette.surface, palette.muted))
	theme.set_stylebox("normal", "LineEdit", panel(palette.ink, palette.border))
	theme.set_stylebox("read_only", "LineEdit", panel(palette.ink, palette.border))
	theme.set_color("font_uneditable_color", "LineEdit", palette.muted)
	theme.set_color("font_placeholder_color", "LineEdit", palette.muted)
	theme.set_color("caret_color", "LineEdit", palette.text)
	theme.set_color("selection_color", "LineEdit", palette.text)
	theme.set_color("font_selected_color", "LineEdit", palette.ink)
	theme.set_color("default_color", "RichTextLabel", palette.text)
	theme.set_color("font_outline_color", "RichTextLabel", palette.ink)
	theme.set_color("selection_color", "RichTextLabel", palette.text)
	theme.set_color("font_selected_color", "RichTextLabel", palette.ink)
	for name: String in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
		theme.set_font(name, "RichTextLabel", FONT)
		theme.set_font_size(name.replace("_font", "_font_size"), "RichTextLabel", BODY)
	for type: String in ["PopupMenu", "TooltipPanel", "PanelContainer"]:
		theme.set_stylebox("panel", type, panel(palette.ink, palette.border))
	theme.set_stylebox("background", "ProgressBar", panel(palette.ink, palette.border))
	theme.set_stylebox("fill", "ProgressBar", panel(palette.accent, palette.accent))
	theme.set_color("font_color", "ProgressBar", palette.text)
	theme.set_color("font_outline_color", "ProgressBar", palette.ink)
	theme.set_constant("outline_size", "ProgressBar", 2)
	# A popup has no separate focus: its highlighted item is the selection.
	theme.set_stylebox("hover", "PopupMenu", focus_plate(palette.surface, palette.accent))
	theme.set_color("font_hover_color", "PopupMenu", palette.accent)
	theme.set_color("font_accelerator_color", "PopupMenu", palette.text)
	for type: String in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", type, panel(palette.ink, palette.border))
		theme.set_stylebox("grabber_area", type, panel(palette.accent, palette.accent))
		theme.set_stylebox("grabber_area_highlight", type, panel(palette.text, palette.accent))
		var focus: StyleBoxFlat = focus_plate(CLEAR, palette.accent)
		theme.set_stylebox("focus", type, focus)
		for state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
			var mark: Color = palette.muted if state == "grabber_disabled" else palette.accent if state == "grabber_highlight" else palette.text
			theme.set_icon(state, type, _block(mark, palette.ink))
	for type: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, panel(palette.ink, palette.ink))
		theme.set_stylebox("scroll_focus", type, panel(palette.ink, palette.accent))
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			theme.set_stylebox(state, type, panel(palette.border if state == "grabber" else palette.accent, palette.ink))
	for checked: bool in [false, true]:
		for disabled: bool in [false, true]:
			var mark: Color = palette.muted if disabled else palette.accent if checked else palette.text
			for type: String in ["CheckBox", "PopupMenu"]:
				var suffix: String = "_disabled" if disabled else ""
				theme.set_icon(("checked" if checked else "unchecked") + suffix, type, _check(checked, mark, palette))
				theme.set_icon(("radio_checked" if checked else "radio_unchecked") + suffix, type, _check(checked, mark, palette))
			for mirrored: bool in [false, true]:
				var key: String = ("checked" if checked else "unchecked") + ("_disabled" if disabled else "") + ("_mirrored" if mirrored else "")
				theme.set_icon(key, "CheckButton", _toggle(checked, disabled, mirrored, palette))
	theme.set_color("button_checked_color", "CheckButton", UNTINTED)
	theme.set_color("button_unchecked_color", "CheckButton", UNTINTED)
	theme.set_icon("arrow", "OptionButton", _arrow(false, palette.text))
	theme.set_constant("modulate_arrow", "OptionButton", 0)
	for direction: String in ["up", "down"]:
		for state: String in ["", "_hover", "_pressed", "_disabled"]:
			var mark: Color = palette.muted if state == "_disabled" else palette.text if state.is_empty() else palette.accent
			theme.set_icon(direction + state, "SpinBox", _arrow(direction == "up", mark))
			theme.set_color(direction + state + "_icon_modulate", "SpinBox", UNTINTED)
	_menu_item(theme, palette)
	_themes[context] = theme
	return theme

## Borderless front-menu rows: plain text at rest, the same focus plate as
## every other control when selected.
static func _menu_item(theme: Theme, palette: Dictionary) -> void:
	theme.set_type_variation(MENU_ITEM, "Button")
	var rest: StyleBoxEmpty = StyleBoxEmpty.new()
	rest.content_margin_left = 18
	rest.content_margin_right = 18
	rest.content_margin_top = 6
	rest.content_margin_bottom = 6
	theme.set_stylebox("normal", MENU_ITEM, rest)
	# Unavailable rows keep a dim frame, so they read as buttons that are off.
	theme.set_stylebox("disabled", MENU_ITEM, hover_frame(CLEAR, palette.edge))
	theme.set_stylebox("hover", MENU_ITEM, hover_frame(CLEAR, palette.muted))
	theme.set_stylebox("pressed", MENU_ITEM, focus_plate(palette.surface, palette.accent))
	theme.set_stylebox("hover_pressed", MENU_ITEM, focus_plate(palette.surface, palette.accent))
	theme.set_stylebox("focus", MENU_ITEM, focus_plate(palette.surface, palette.accent))

static func _block(mark: Color, backing: Color) -> Texture2D:
	var image: Image = Image.create(18, 24, false, Image.FORMAT_RGBA8)
	image.fill(backing)
	image.fill_rect(Rect2i(3, 3, 12, 18), mark)
	return ImageTexture.create_from_image(image)

static func _arrow(up: bool, mark: Color) -> Texture2D:
	var image: Image = Image.create(18, 12, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	for step: int in range(3):
		image.fill_rect(Rect2i(step * 3, step * 3, 18 - step * 6, 3), mark)
	if up:
		image.flip_y()
	return ImageTexture.create_from_image(image)

static func _toggle(checked: bool, disabled: bool, mirrored: bool, palette: Dictionary) -> Texture2D:
	var image: Image = Image.create(48, 24, false, Image.FORMAT_RGBA8)
	image.fill(palette.border)
	image.fill_rect(Rect2i(3, 3, 42, 18), palette.ink)
	var mark: Color = palette.muted if disabled else palette.accent if checked else palette.text
	image.fill_rect(Rect2i(27 if checked else 3, 3, 18, 18), mark)
	if mirrored:
		image.flip_x()
	return ImageTexture.create_from_image(image)

static func _check(checked: bool, mark: Color, palette: Dictionary) -> Texture2D:
	var image: Image = Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(mark)
	image.fill_rect(Rect2i(3, 3, 18, 18), palette.ink)
	if checked:
		image.fill_rect(Rect2i(6, 6, 12, 12), mark)
	return ImageTexture.create_from_image(image)
