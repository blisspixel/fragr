extends RefCounted
class_name InputGlyphs

## Prompt text and small pixel glyphs for whatever the player last used.
## Keyboard prompts are keycaps drawn as text. Gamepad prompts are 16 pixel
## sprites generated here from tiny bitmaps: a round face button with a letter,
## a shape or a positional dot, bumpers, triggers, a d-pad arm, sticks, and the
## two small centre buttons. They are original pixel art, not any maker's
## logo, and read on any pad: the positional set is the fallback when the
## driver does not say which layout it has.
##
## A prompt template names actions in braces: "{use}: READ TRANSFER RECORD".

const SIZE: int = 16
const INK: Color = Color("0c1010")
const BODY: Color = Color("2b2721")
const RIM: Color = Color("d2bc96")
const MARK: Color = Color("efb56e")
const DIM: Color = Color("6b6960")
const KEYCAP_BACK: Color = Color("3a2d22")

## Template names to InputMap actions.
const TOKENS: Dictionary = {
	"use": "interact",
	"accept": "ui_accept",
	"back": "ui_cancel",
	"pause": "pause",
	"fire": "fire",
	"jump": "jump",
	"join": "join_as_human",
	"leave": "leave_match",
	"weapon": "weapon_next",
	"speak": "speak",
	"scores": "scoreboard",
	"cycle": "cycle_cam",
	"view": "toggle_follow",
	"radio": "radio_next_station",
}

## 5x7 bitmaps for the few letters a glyph carries.
const FONT: Dictionary = {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"?": ["01110", "10001", "00001", "00110", "00100", "00000", "00100"],
}

static var _cache: Dictionary = {}

## --- Names --------------------------------------------------------------------

static func pad_name(token: String, layout: String) -> String:
	if token.begins_with("pad:a"):
		var left: bool = token.substr(5, 1) == str(JOY_AXIS_TRIGGER_LEFT)
		match layout:
			"shapes": return "L2" if left else "R2"
			_: return "LT" if left else "RT"
	if not token.begins_with("pad:b"):
		return "?"
	var button: int = int(token.substr(5))
	match button:
		JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y:
			var names: Dictionary = {
				"letters": ["A", "B", "X", "Y"],
				"shapes": ["CROSS", "CIRCLE", "SQUARE", "TRIANGLE"],
				"generic": ["SOUTH", "EAST", "WEST", "NORTH"],
			}
			return names.get(layout, names["generic"])[button]
		JOY_BUTTON_LEFT_SHOULDER: return "L1" if layout == "shapes" else "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1" if layout == "shapes" else "RB"
		JOY_BUTTON_LEFT_STICK: return "L3" if layout == "shapes" else "LS"
		JOY_BUTTON_RIGHT_STICK: return "R3" if layout == "shapes" else "RS"
		JOY_BUTTON_BACK: return "SELECT" if layout != "letters" else "VIEW"
		JOY_BUTTON_START: return "START" if layout != "letters" else "MENU"
		JOY_BUTTON_GUIDE: return "HOME"
		JOY_BUTTON_DPAD_UP: return "D-UP"
		JOY_BUTTON_DPAD_DOWN: return "D-DOWN"
		JOY_BUTTON_DPAD_LEFT: return "D-LEFT"
		JOY_BUTTON_DPAD_RIGHT: return "D-RIGHT"
	return "PAD %d" % button

static func key_name(token: String) -> String:
	if token.begins_with("mouse:"):
		match int(token.substr(6)):
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_WHEEL_UP: return "WHEEL UP"
			MOUSE_BUTTON_WHEEL_DOWN: return "WHEEL DOWN"
			MOUSE_BUTTON_WHEEL_LEFT: return "WHEEL LEFT"
			MOUSE_BUTTON_WHEEL_RIGHT: return "WHEEL RIGHT"
			MOUSE_BUTTON_XBUTTON1: return "MOUSE 4"
			MOUSE_BUTTON_XBUTTON2: return "MOUSE 5"
		return "MOUSE"
	if not token.begins_with("key:"):
		return "?"
	var body: String = token.substr(4)
	var side: String = ""
	if body.ends_with("@l") or body.ends_with("@r"):
		side = "L-" if body.ends_with("@l") else "R-"
		body = body.substr(0, body.length() - 2)
	var physical: int = int(body)
	var short: Dictionary = {
		KEY_COMMA: ",", KEY_PERIOD: ".", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
		KEY_PAGEUP: "PGUP", KEY_PAGEDOWN: "PGDN", KEY_ESCAPE: "ESC", KEY_CTRL: "CTRL",
		KEY_UP: "UP", KEY_DOWN: "DOWN", KEY_LEFT: "LEFT", KEY_RIGHT: "RIGHT",
		KEY_ENTER: "ENTER", KEY_KP_ENTER: "ENTER", KEY_SPACE: "SPACE", KEY_QUOTELEFT: "~",
	}
	if short.has(physical):
		return side + str(short[physical])
	# The headless display server has no keyboard layout to ask.
	var logical: Key = KEY_NONE
	if DisplayServer.get_name() != "headless":
		logical = DisplayServer.keyboard_get_keycode_from_physical(physical as Key)
	var name: String = OS.get_keycode_string(logical if logical != KEY_NONE else physical as Key)
	return side + (name.to_upper() if not name.is_empty() else "KEY %d" % physical)

static func token_name(token: String, layout: String) -> String:
	if token.is_empty():
		return "-"
	return pad_name(token, layout) if InputBindings.is_pad_token(token) else key_name(token)

## The label a prompt would use for an action on the active device.
static func action_name(action: String) -> String:
	var pad: bool = InputDevice.is_gamepad()
	var token: String = InputBindings.live_token(action, pad, InputDevice.kind == InputDevice.Kind.MOUSE)
	if token.is_empty() and pad:
		token = InputBindings.live_token(action, false)
		pad = false
	return token_name(token, InputDevice.pad_layout) if not token.is_empty() else "?"

## --- Templates ----------------------------------------------------------------

## Split a template into literal text and action names.
static func parts(template: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rest: String = template
	while not rest.is_empty():
		var open: int = rest.find("{")
		var close: int = rest.find("}", open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			out.append({"text": rest})
			break
		var name: String = rest.substr(open + 1, close - open - 1)
		if open > 0:
			out.append({"text": rest.substr(0, open)})
		if TOKENS.has(name):
			out.append({"action": TOKENS[name]})
		elif InputMap.has_action(name):
			out.append({"action": name})
		else:
			out.append({"text": rest.substr(open, close - open + 1)})
		rest = rest.substr(close + 1)
	return out

## Plain text for a template: "{use}: USE" reads "F: USE" or "B: USE".
static func plain(template: String) -> String:
	var text: String = ""
	for part: Dictionary in parts(template):
		text += str(part["text"]) if part.has("text") else action_name(str(part["action"]))
	return text

## Draw a template into a RichTextLabel: keycaps on keyboard, pixel glyphs
## on a gamepad. Returns the plain text, for tests and accessibility.
static func render(label: RichTextLabel, template: String, glyph_size: int = 32, centre: bool = false) -> String:
	label.clear()
	if centre:
		label.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	var pad: bool = InputDevice.is_gamepad()
	for part: Dictionary in parts(template):
		if part.has("text"):
			label.add_text(str(part["text"]))
			continue
		var action: String = str(part["action"])
		var token: String = InputBindings.live_token(action, pad, InputDevice.kind == InputDevice.Kind.MOUSE)
		if pad and not token.is_empty():
			label.add_image(glyph(token, InputDevice.pad_layout), glyph_size, glyph_size, Color.WHITE, INLINE_ALIGNMENT_CENTER)
			continue
		if token.is_empty():
			token = InputBindings.live_token(action, false)
		label.push_bgcolor(KEYCAP_BACK)
		label.push_color(MARK)
		label.add_text(" %s " % token_name(token, InputDevice.pad_layout))
		label.pop()
		label.pop()
	if centre:
		label.pop()
	return plain(template)

## --- Pixel glyphs -------------------------------------------------------------

## A 16 by 16 texture for a gamepad token, cached per layout.
static func glyph(token: String, layout: String) -> Texture2D:
	var key: String = token + "#" + layout
	if _cache.has(key):
		return _cache[key]
	var image: Image = glyph_image(token, layout)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func glyph_image(token: String, layout: String) -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if token.begins_with("pad:a"):
		var left: bool = token.substr(5, 1) == str(JOY_AXIS_TRIGGER_LEFT)
		_trigger(image)
		_text(image, ("L" if left else "R") + ("2" if layout == "shapes" else "T"), 8, 7, MARK)
		return image
	var button: int = int(token.substr(5)) if token.begins_with("pad:b") else -1
	match button:
		JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y:
			_disc(image, 7.5, 7.5, 7.4, INK)
			_disc(image, 7.5, 7.5, 6.4, RIM)
			_disc(image, 7.5, 7.5, 5.4, BODY)
			_face_mark(image, button, layout)
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			_rounded(image, Rect2i(0, 3, 16, 10), INK)
			_rounded(image, Rect2i(1, 4, 14, 8), RIM)
			_rounded(image, Rect2i(2, 5, 12, 6), BODY)
			var left: bool = button == JOY_BUTTON_LEFT_SHOULDER
			_text(image, ("L" if left else "R") + ("1" if layout == "shapes" else "B"), 8, 4, MARK)
		JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK:
			_disc(image, 7.5, 7.5, 7.4, INK)
			_disc(image, 7.5, 7.5, 6.4, DIM)
			_disc(image, 7.5, 7.5, 5.0, BODY)
			_text(image, "L" if button == JOY_BUTTON_LEFT_STICK else "R", 8, 4, MARK)
		JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_GUIDE:
			_rounded(image, Rect2i(1, 4, 14, 8), INK)
			_rounded(image, Rect2i(2, 5, 12, 6), RIM)
			if button == JOY_BUTTON_START:
				for row: int in [6, 8, 10]:
					for x: int in range(5, 11):
						image.set_pixel(x, row - 0, INK)
			elif button == JOY_BUTTON_BACK:
				_box(image, Rect2i(4, 6, 4, 3), INK)
				_box(image, Rect2i(8, 8, 4, 3), INK)
			else:
				_disc(image, 7.5, 8.0, 2.0, INK)
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			_dpad(image, button)
		_:
			_disc(image, 7.5, 7.5, 7.4, INK)
			_disc(image, 7.5, 7.5, 6.4, DIM)
			_text(image, "?", 8, 4, RIM)
	return image

## Left stick and right stick, for the move and look lines of a legend.
static func stick_glyph(left: bool) -> Texture2D:
	return glyph("pad:b%d" % (JOY_BUTTON_LEFT_STICK if left else JOY_BUTTON_RIGHT_STICK), InputDevice.pad_layout)

static func _face_mark(image: Image, button: int, layout: String) -> void:
	match layout:
		"letters":
			_text(image, ["A", "B", "X", "Y"][button], 8, 4, MARK)
		"shapes":
			match button:
				JOY_BUTTON_A:
					for i: int in range(7):
						image.set_pixel(4 + i, 4 + i, MARK)
						image.set_pixel(10 - i, 4 + i, MARK)
				JOY_BUTTON_B:
					_ring(image, 7.5, 7.5, 3.4, 2.4, MARK)
				JOY_BUTTON_X:
					for i: int in range(6):
						for edge: Vector2i in [Vector2i(5 + i, 5), Vector2i(5 + i, 10), Vector2i(5, 5 + i), Vector2i(10, 5 + i)]:
							image.set_pixelv(edge, MARK)
				JOY_BUTTON_Y:
					for y: int in range(6):
						image.set_pixel(7 - y / 2, 4 + y + 1, MARK)
						image.set_pixel(8 + y / 2, 4 + y + 1, MARK)
					for x: int in range(4, 12):
						image.set_pixel(x, 10, MARK)
		_:
			var spots: Array[Vector2i] = [Vector2i(7, 10), Vector2i(10, 7), Vector2i(4, 7), Vector2i(7, 4)]
			for index: int in range(4):
				_box(image, Rect2i(spots[index], Vector2i(2, 2)), MARK if index == button else DIM)

static func _dpad(image: Image, button: int) -> void:
	_box(image, Rect2i(5, 0, 6, 16), INK)
	_box(image, Rect2i(0, 5, 16, 6), INK)
	_box(image, Rect2i(6, 1, 4, 14), DIM)
	_box(image, Rect2i(1, 6, 14, 4), DIM)
	var arms: Dictionary = {
		JOY_BUTTON_DPAD_UP: Rect2i(6, 1, 4, 5),
		JOY_BUTTON_DPAD_DOWN: Rect2i(6, 10, 4, 5),
		JOY_BUTTON_DPAD_LEFT: Rect2i(1, 6, 5, 4),
		JOY_BUTTON_DPAD_RIGHT: Rect2i(10, 6, 5, 4),
	}
	_box(image, arms[button], MARK)

static func _trigger(image: Image) -> void:
	_rounded(image, Rect2i(2, 0, 12, 16), INK)
	_rounded(image, Rect2i(3, 1, 10, 14), RIM)
	_rounded(image, Rect2i(4, 2, 8, 12), BODY)

static func _box(image: Image, rect: Rect2i, colour: Color) -> void:
	image.fill_rect(rect, colour)

static func _rounded(image: Image, rect: Rect2i, colour: Color) -> void:
	image.fill_rect(Rect2i(rect.position + Vector2i(1, 0), rect.size - Vector2i(2, 0)), colour)
	image.fill_rect(Rect2i(rect.position + Vector2i(0, 1), rect.size - Vector2i(0, 2)), colour)

static func _disc(image: Image, cx: float, cy: float, radius: float, colour: Color) -> void:
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			if Vector2(x - cx, y - cy).length() <= radius:
				image.set_pixel(x, y, colour)

static func _ring(image: Image, cx: float, cy: float, outer: float, inner: float, colour: Color) -> void:
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var d: float = Vector2(x - cx, y - cy).length()
			if d <= outer and d >= inner:
				image.set_pixel(x, y, colour)

## Centred text from the 5x7 font, `top` is the first row.
static func _text(image: Image, text: String, centre_x: int, top: int, colour: Color) -> void:
	var width: int = text.length() * 6 - 1
	var x0: int = centre_x - (width + 1) / 2
	for index: int in range(text.length()):
		var rows: Array = FONT.get(text[index], FONT["?"])
		for row: int in range(rows.size()):
			var line: String = rows[row]
			for column: int in range(line.length()):
				if line[column] == "1":
					var x: int = x0 + index * 6 + column
					var y: int = top + row
					if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
						image.set_pixel(x, y, colour)
