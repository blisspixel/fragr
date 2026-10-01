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

func _run() -> void:
	path = "user://grenade-controls-%d.cfg" % OS.get_process_id()
	var prefs: FragrSettings = FragrSettings.new(path)
	_check(InputBindings.default_slots("throw_grenade") == (["key:71", "mouse:3", "pad:a4+"] as Array[String]), "independent throw defaults to G, middle mouse and left trigger")
	_check(InputBindings.conflicts(prefs).is_empty(), "fresh defaults do not conflict")
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures == 0:
		print("test_grenade_controls: PASS historical ownership, glyphs, brief taps, failed send, repeat and blocked handoff")
	quit(0 if failures == 0 else 1)
