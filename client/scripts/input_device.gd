extends Node
class_name InputDevice

## Which device the player last used, for prompts, and which device last
## steered the view, for aim assist. One watcher node lives in each scene that
## takes input (the boot menu and the match); the state is static so HUD,
## menus and the camera all read the same answer.
##
## Prompts follow the last device pressed: keyboard and mouse share keyboard
## prompts, a gamepad gets gamepad glyphs. The look source changes only on
## look input: mouse motion, a turn or look key, or any gamepad input. That
## keeps aim assist off for a mouse player who presses W, and on for a
## keyboard player who never touches the mouse.

enum Kind { KEYBOARD, MOUSE, GAMEPAD }

signal changed

static var kind: Kind = Kind.KEYBOARD
## "", "mouse", "keyboard" or "gamepad".
static var look_source: String = ""
static var pad_device: int = 0
## "letters" (A B X Y), "shapes" (cross circle square triangle) or "generic"
## (positional: south, east, west, north).
static var pad_layout: String = "generic"
## Bumped on every change, so a presenter can poll one integer per frame.
static var revision: int = 0

## Mouse motion below this many counts in one event is treated as a bump.
const MOUSE_COUNTS: float = 3.0
## Stick deflection that counts as deliberate gamepad use.
const PAD_AXIS: float = 0.5
const LOOK_KEYS: Array[String] = ["turn_left", "turn_right", "look_up", "look_down", "center_view"]

func _input(event: InputEvent) -> void:
	if InputDevice.note(event):
		changed.emit()

static func is_gamepad() -> bool:
	return kind == Kind.GAMEPAD

## Classify one event. Returns true when prompts or the look source changed.
static func note(event: InputEvent) -> bool:
	var next_kind: Kind = kind
	var next_look: String = look_source
	var next_device: int = pad_device
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return false
		next_kind = Kind.KEYBOARD
		for action: String in LOOK_KEYS:
			if InputMap.has_action(action) and key.is_action_pressed(action):
				next_look = "keyboard"
		if next_look.is_empty() and InputMap.has_action("fire") and key.is_action_pressed("fire"):
			next_look = "keyboard"
	elif event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return false
		next_kind = Kind.MOUSE
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if motion.screen_relative.length() < MOUSE_COUNTS:
			return false
		next_kind = Kind.MOUSE
		next_look = "mouse"
	elif event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return false
		next_kind = Kind.GAMEPAD
		next_look = "gamepad"
		next_device = event.device
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < PAD_AXIS:
			return false
		next_kind = Kind.GAMEPAD
		next_look = "gamepad"
		next_device = event.device
	else:
		return false
	var next_layout: String = pad_layout
	if next_kind == Kind.GAMEPAD and (next_device != pad_device or kind != Kind.GAMEPAD):
		next_layout = layout_for(Input.get_joy_name(next_device), Input.get_joy_info(next_device))
	if next_kind == kind and next_look == look_source and next_device == pad_device and next_layout == pad_layout:
		return false
	kind = next_kind
	look_source = next_look
	pad_device = next_device
	pad_layout = next_layout
	revision += 1
	return true

## Face-button layout from what the driver reports. Names vary by platform
## and driver, so this matches loosely and falls back to positional glyphs,
## which are correct on any pad.
static func layout_for(joy_name: String, info: Dictionary = {}) -> String:
	var name: String = joy_name.to_lower()
	var vendor: int = int(info.get("vendor_id", 0)) if info.get("vendor_id") is int else 0
	if vendor == 0x054C:
		return "shapes"
	if vendor == 0x045E or info.has("xinput_index"):
		return "letters"
	for hint: String in ["dualsense", "dualshock", "playstation", "sony", "ps3", "ps4", "ps5", "wireless controller"]:
		if name.contains(hint):
			return "shapes"
	# Nintendo layouts swap A and B, so letters would lie. Positional is honest.
	for hint: String in ["nintendo", "switch", "joy-con", "pro controller"]:
		if name.contains(hint):
			return "generic"
	for hint: String in ["xbox", "xinput", "x-box", "microsoft"]:
		if name.contains(hint):
			return "letters"
	return "generic"

## Test and tour hook: set the state directly.
static func force(next_kind: Kind, next_look: String = "", layout: String = "generic") -> void:
	kind = next_kind
	look_source = next_look
	pad_layout = layout if layout in ["letters", "shapes", "generic"] else "generic"
	revision += 1

static func reset() -> void:
	force(Kind.KEYBOARD, "", "generic")
