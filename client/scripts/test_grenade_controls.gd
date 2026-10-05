extends SceneTree

class NetworkProbe extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	var succeed: bool = true
	func send_json(value: Dictionary) -> void:
		last_send_ok = succeed
		if succeed:
			sent.append(value.duplicate(true))

class ManagerProbe extends "res://scripts/game_manager.gd":
	var blocked: bool = false
	func controls_blocked() -> bool:
		return blocked
	func _mission_controls_blocked() -> bool:
		return blocked

var failures: int = 0
var path: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error("test_grenade_controls: " + description)

func _key(pressed: bool, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_G
	event.pressed = pressed
	event.echo = echo
	return event

func _remote_key(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func _remote_control(action: String, key: Key, pending: String) -> void:
	var network: NetworkProbe = NetworkProbe.new()
	var manager: ManagerProbe = ManagerProbe.new()
	manager.is_human_player = true
	manager.net_client = network
	manager._input(_remote_key(key, true))
	manager._input(_remote_key(key, false))
	_check(bool(manager.get(pending)), action + " short genuine press survives to flush")
	manager._send_local_action(100000)
	_check(network.sent.back().get(action) == true and not bool(manager.get(pending)),
		action + " serializes its own discrete command once")
	_check(not network.sent.back().has("throw_grenade") and not network.sent.back().has("place_mine"),
		action + " does not throw or place the other devices")
	manager._send_local_action(150000)
	_check(not network.sent.back().has(action), action + " is not replayed")
	manager._input(_remote_key(key, true, true))
	_check(not bool(manager.get(pending)), action + " ignores keyboard repeats")
	manager._input(_remote_key(key, true))
	network.succeed = false
	manager._send_local_action(200000)
	_check(bool(manager.get(pending)), action + " failed transport preserves the genuine tap")
	network.succeed = true
	manager._send_local_action(250000)
	_check(network.sent.back().get(action) == true and not bool(manager.get(pending)), action + " retries exactly once")
	manager._input(_remote_key(key, true))
	manager.blocked = true
	manager._send_local_action(300000)
	_check(not bool(manager.get(pending)) and not network.sent.back().has(action), action + " blocked handoff discards pending commands")
	Input.action_press(action)
	manager.blocked = false
	manager._send_local_action(350000)
	_check(not network.sent.back().has(action), action + " held input remains disarmed after handoff")
	_check(not manager._opening_input_released(), action + " keeps readiness closed while held")
	manager._on_loading_dismissed()
	manager._send_local_action(400000)
	_check(not network.sent.back().has(action), action + " held input through loading cannot trigger")
	Input.action_release(action)
	manager._input(_remote_key(key, false))
	manager._input(_remote_key(key, true))
	manager._send_local_action(450000)
	_check(network.sent.back().get(action) == true, action + " release/fresh press rearms")
	manager._input(_remote_key(key, true))
	manager._clear_story_input()
	_check(not bool(manager.get(pending)), action + " story transition discards the tap")
	manager.free()
	network.free()

func _run() -> void:
	path = "user://grenade-controls-%d.cfg" % OS.get_process_id()
	var prefs: FragrSettings = FragrSettings.new(path)
	_check(InputBindings.default_slots("throw_grenade") == (["key:71", "mouse:3", "pad:a4+"] as Array[String]), "independent throw defaults to G, middle mouse and left trigger")
	_check(InputBindings.conflicts(prefs).is_empty(), "fresh defaults do not conflict")
	_check(InputBindings.default_slots("place_remote_mine") == (["key:86", "", "pad:b5"] as Array[String]), "remote placement uses V/right shoulder without changing other devices")
	_check(InputBindings.default_slots("trigger_remote_mines") == (["key:72", "", "pad:b14"] as Array[String]), "deliberate trigger uses H/right D-pad")
	var old: ConfigFile = ConfigFile.new()
	old.set_value("bindings", "move_forward", "key:71|mouse:3|pad:a4+")
	_check(old.save(path) == OK, "historical custom controls fixture saved")
	prefs.load_from_disk()
	_check(InputBindings.slots_for(prefs, "move_forward") == (["key:71", "mouse:3", "pad:a4+"] as Array[String])
		and InputBindings.slots_for(prefs, "throw_grenade") == (["", "", ""] as Array[String]), "new defaults never steal existing custom keys, mouse or trigger")
	_check(InputBindings.conflicts(prefs).is_empty(), "historical binding migration introduces no conflict")
	_check(prefs.save_to_disk() == OK, "adopted unbound grenade slots persist normally")
	var again: FragrSettings = FragrSettings.new(path)
	again.load_from_disk()
	_check(InputBindings.slots_for(again, "throw_grenade") == (["", "", ""] as Array[String]), "explicit unbound slots survive reload")
	InputBindings.reset(prefs)
	prefs.apply_controls()
	_check(InputGlyphs.plain("{grenade}: THROW") == "G: THROW", "throw prompts use live keyboard bindings")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	_check(InputGlyphs.plain("{grenade}: THROW") == "LT: THROW", "throw prompts use live left-trigger glyph")
	InputDevice.reset()
	var network: NetworkProbe = NetworkProbe.new()
	var manager: ManagerProbe = ManagerProbe.new()
	manager.is_human_player = true
	manager.net_client = network
	manager._input(_key(true))
	manager._input(_key(false))
	_check(manager.pending_throw, "a sub-flush press/release stays pending")
	manager._send_local_action(100000)
	_check(network.sent.back().get("throw_grenade") == true and not manager.pending_throw, "successful send carries pending tap through actual NetClient serializer")
	manager._send_local_action(150000)
	_check(not network.sent.back().has("throw_grenade"), "tap is not replayed on the next action")
	manager._input(_key(true, true))
	_check(not manager.pending_throw, "keyboard repeats do not create throws")
	manager._input(_key(true))
	network.succeed = false
	manager._send_local_action(200000)
	_check(manager.pending_throw, "a failed transport keeps the tap until successful send")
	network.succeed = true
	manager._send_local_action(250000)
	_check(not manager.pending_throw and network.sent.back().get("throw_grenade") == true, "retry sends one retained tap")
	manager._input(_key(true))
	manager.blocked = true
	manager._send_local_action(300000)
	_check(not manager.pending_throw and not network.sent.back().has("throw_grenade"), "blocked menus/story/readiness discard pending throws")
	Input.action_press("throw_grenade")
	manager.blocked = false
	manager._send_local_action(350000)
	_check(not network.sent.back().has("throw_grenade"), "held input across a blocked handoff stays disarmed")
	Input.action_release("throw_grenade")
	manager._input(_key(false))
	manager._input(_key(true))
	manager._send_local_action(400000)
	_check(network.sent.back().get("throw_grenade") == true, "release followed by fresh press rearms throw")
	manager.free()
	network.free()
	_remote_control("place_remote_mine", KEY_V, "pending_remote_place")
	_remote_control("trigger_remote_mines", KEY_H, "pending_remote_trigger")
	var old_remote: ConfigFile = ConfigFile.new()
	old_remote.set_value("bindings", "move_left", "key:86||pad:b5")
	old_remote.set_value("bindings", "move_right", "key:72||pad:b14")
	_check(old_remote.save(path) == OK, "historical remote default ownership fixture saved")
	var remote_prefs: FragrSettings = FragrSettings.new(path)
	remote_prefs.load_from_disk()
	for remote_action: String in ["place_remote_mine", "trigger_remote_mines"]:
		_check(InputBindings.slots_for(remote_prefs, remote_action) == (["", "", ""] as Array[String]),
			remote_action + " new defaults cannot steal historical custom controls")
	_check(InputBindings.slots_for(remote_prefs, "move_left")[0] == "key:86" and InputBindings.slots_for(remote_prefs, "move_right")[0] == "key:72", "historical movement controls survive")
	_check(InputBindings.conflicts(remote_prefs).is_empty(), "remote default migration has no conflicting controls")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures == 0:
		print("test_grenade_controls: PASS historical ownership, glyphs, brief taps, failed send, repeat and blocked handoff")
	quit(0 if failures == 0 else 1)
