extends RefCounted
class_name InputBindings

## Rebindable player actions over Godot's InputMap. `project.godot` holds the
## defaults; `settings.gd` stores only the actions a player changed, one string
## per action, and `apply` rebuilds the InputMap from both. Every device still
## produces the same discrete actions, so the wire and the server never learn
## which key or button was pressed.
##
## Each action has three slots: two keyboard or mouse slots and one gamepad
## slot. A slot is a token:
##   key:<physical keycode>[@l|@r]   a key, optionally one side only
##   mouse:<button index>             a mouse button or wheel step
##   pad:b<button index>              a gamepad button
##   pad:a<axis><+|->                 a trigger pulled past its deadzone
## An empty token is an empty slot. Sticks are not bindable: the left stick
## moves and the right stick looks (`look_input.gd`), so nothing can be bound to
## half an axis that already has a job.

## Controls page order.
const ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "strafe", "jump",
	"turn_left", "turn_right", "look_up", "look_down", "center_view",
	"fire", "interact", "weapon_next", "weapon_prev",
	"weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_5",
	"scoreboard", "speak", "pause", "leave_match",
	"join_as_human", "cycle_cam", "toggle_follow",
	"radio_next_station", "radio_next_track", "radio_toggle",
]

## Where an action does anything. Two actions conflict only when their
## contexts overlap, so F can use a console while playing and change the
## watched fighter while spectating.
const SPECTATE: Array[String] = ["join_as_human", "cycle_cam", "toggle_follow"]
const EVERYWHERE: Array[String] = ["pause", "radio_next_station", "radio_next_track", "radio_toggle"]

const SLOTS: int = 3
const PAD_SLOT: int = 2
## Triggers only. Sticks keep their fixed jobs.
const PAD_AXES: Array[int] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
const MAX_KEYCODE: int = 0x7FFFFFFF

static func context(action: String) -> String:
	if action in SPECTATE:
		return "spectate"
	if action in EVERYWHERE:
		return "everywhere"
	return "play"

static func contexts_overlap(a: String, b: String) -> bool:
	var ca: String = context(a)
	var cb: String = context(b)
	return ca == cb or ca == "everywhere" or cb == "everywhere"

## --- Tokens -----------------------------------------------------------------

static func token_from_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key: InputEventKey = event
		var code: int = int(key.physical_keycode)
		if code == 0:
			code = int(key.keycode)
		if code <= 0:
			return ""
		var side: String = ""
		if key.location == KEY_LOCATION_LEFT:
			side = "@l"
		elif key.location == KEY_LOCATION_RIGHT:
			side = "@r"
		return "key:%d%s" % [code, side]
	if event is InputEventMouseButton:
		return "mouse:%d" % int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return "pad:b%d" % int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		if int(motion.axis) not in PAD_AXES or is_zero_approx(motion.axis_value):
			return ""
		return "pad:a%d%s" % [int(motion.axis), "+" if motion.axis_value > 0.0 else "-"]
	return ""

static func is_pad_token(token: String) -> bool:
	return token.begins_with("pad:")

static func valid_token(token: String) -> bool:
	return token.is_empty() or event_from_token(token) != null

## Strict parse: a malformed token is rejected, never guessed at.
static func event_from_token(token: String) -> InputEvent:
	if token.begins_with("key:"):
		var body: String = token.substr(4)
		var location: KeyLocation = KEY_LOCATION_UNSPECIFIED
		if body.ends_with("@l") or body.ends_with("@r"):
			location = KEY_LOCATION_LEFT if body.ends_with("@l") else KEY_LOCATION_RIGHT
			body = body.substr(0, body.length() - 2)
		if not body.is_valid_int() or int(body) <= 0 or int(body) > MAX_KEYCODE or str(int(body)) != body:
			return null
		var key: InputEventKey = InputEventKey.new()
		key.device = -1
		key.physical_keycode = int(body) as Key
		key.location = location
		return key
	if token.begins_with("mouse:"):
		var body: String = token.substr(6)
		if not body.is_valid_int() or str(int(body)) != body or int(body) < 1 or int(body) > 9:
			return null
		var button: InputEventMouseButton = InputEventMouseButton.new()
		button.device = -1
		button.button_index = int(body) as MouseButton
		button.pressed = true
		return button
	if token.begins_with("pad:b"):
		var body: String = token.substr(5)
		if not body.is_valid_int() or str(int(body)) != body or int(body) < 0 or int(body) >= JOY_BUTTON_SDL_MAX:
			return null
		var pad: InputEventJoypadButton = InputEventJoypadButton.new()
		pad.device = -1
		pad.button_index = int(body) as JoyButton
		return pad
	if token.begins_with("pad:a") and token.length() == 7:
		var axis: String = token.substr(5, 1)
		var sign: String = token.substr(6, 1)
		if not axis.is_valid_int() or int(axis) not in PAD_AXES or sign not in ["+", "-"]:
			return null
		var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
		motion.device = -1
		motion.axis = int(axis) as JoyAxis
		motion.axis_value = 1.0 if sign == "+" else -1.0
		return motion
	return null

## --- Slots ------------------------------------------------------------------

## A stored override: exactly three slots, keyboard or mouse in the first two
## and a gamepad token in the third. Anything else is not an override.
static func parse(value: Variant) -> Array[String]:
	var slots: Array[String] = []
	if not value is String or (value as String).is_empty():
		return slots
	var parts: PackedStringArray = (value as String).split("|")
	if parts.size() != SLOTS:
		return slots
	for index: int in range(SLOTS):
		var token: String = parts[index]
		if not valid_token(token) or (not token.is_empty() and is_pad_token(token) != (index == PAD_SLOT)):
			return [] as Array[String]
		slots.append(token)
	return slots

static func encode(slots: Array[String]) -> String:
	return "|".join(slots)

## Project defaults, read from project settings so a runtime InputMap change
## can never become the new default.
static func default_slots(action: String) -> Array[String]:
	var slots: Array[String] = ["", "", ""]
	var entry: Variant = ProjectSettings.get_setting("input/" + action)
	if not entry is Dictionary:
		return slots
	var keyboard: int = 0
	for event: Variant in (entry as Dictionary).get("events", []):
		if not event is InputEvent:
			continue
		var token: String = token_from_event(event as InputEvent)
		if token.is_empty():
			continue
		if is_pad_token(token):
			if slots[PAD_SLOT].is_empty():
				slots[PAD_SLOT] = token
		elif keyboard < PAD_SLOT:
			slots[keyboard] = token
			keyboard += 1
	return slots

static func slots_for(preferences: FragrSettings, action: String) -> Array[String]:
	var stored: Array[String] = parse(preferences.get_value("bindings", action))
	return stored if stored.size() == SLOTS else default_slots(action)

static func _deadzone(action: String) -> float:
	var entry: Variant = ProjectSettings.get_setting("input/" + action)
	if entry is Dictionary and ((entry as Dictionary).get("deadzone") is float or (entry as Dictionary).get("deadzone") is int):
		return clampf(float((entry as Dictionary)["deadzone"]), 0.05, 0.95)
	return 0.5

## Rebuild every rebindable action. Safe to call repeatedly.
static func apply(preferences: FragrSettings) -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, _deadzone(action))
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, _deadzone(action))
		for token: String in slots_for(preferences, action):
			if not token.is_empty():
				InputMap.action_add_event(action, event_from_token(token))

## Store an action's slots, keeping the file to real changes only.
static func store(preferences: FragrSettings, action: String, slots: Array[String]) -> void:
	preferences.set_value("bindings", action, "" if slots == default_slots(action) else encode(slots))

## Put `token` in one slot. The same input leaves any other action whose
## context overlaps, and the other keyboard slot of this action. Returns the
## actions that lost it, so the page can say where it came from.
static func assign(preferences: FragrSettings, action: String, slot: int, token: String) -> Array[String]:
	var displaced: Array[String] = []
	if action not in ACTIONS or slot < 0 or slot >= SLOTS or not valid_token(token):
		return displaced
	if not token.is_empty() and is_pad_token(token) != (slot == PAD_SLOT):
		return displaced
	if not token.is_empty():
		for other: String in ACTIONS:
			if not contexts_overlap(action, other):
				continue
			var slots: Array[String] = slots_for(preferences, other)
			var index: int = slots.find(token)
			if index < 0 or (other == action and index == slot):
				continue
			slots[index] = ""
			store(preferences, other, slots)
			if other != action:
				displaced.append(other)
	var mine: Array[String] = slots_for(preferences, action)
	mine[slot] = token
	store(preferences, action, mine)
	return displaced

## Pairs of actions that share an input in an overlapping context. `assign`
## never creates one; a hand-edited settings file can.
static func conflicts(preferences: FragrSettings) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var owners: Dictionary = {}
	for action: String in ACTIONS:
		for token: String in slots_for(preferences, action):
			if token.is_empty():
				continue
			for other: String in owners.get(token, []):
				if contexts_overlap(action, other):
					found.append({"token": token, "actions": [other, action]})
			if not owners.has(token):
				owners[token] = []
			(owners[token] as Array).append(action)
	return found

static func reset(preferences: FragrSettings) -> void:
	preferences.reset_section("bindings")

## First live token for an action on one device family, read from the InputMap
## so prompts always show what the player actually bound.
static func live_token(action: String, pad: bool, prefer_mouse: bool = false) -> String:
	if not InputMap.has_action(action):
		return ""
	var fallback: String = ""
	for event: InputEvent in InputMap.action_get_events(action):
		var token: String = token_from_event(event)
		if token.is_empty() or is_pad_token(token) != pad:
			continue
		if pad or token.begins_with("mouse:") == prefer_mouse:
			return token
		if fallback.is_empty():
			fallback = token
	return fallback
