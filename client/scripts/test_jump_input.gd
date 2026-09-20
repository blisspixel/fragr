extends SceneTree

class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: String = "self"
	var mission: Dictionary = {}
	var sent: Array[Dictionary] = []
	func send_action(action: Dictionary) -> void:
		sent.append(action.duplicate())

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_jump_input: " + message)

func _run() -> void:
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var network: CaptureNetwork = CaptureNetwork.new()
	manager.set("net_client", network)
	manager.set("is_human_player", true)
	var pawn: Node3D = Node3D.new()
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	camera.fp_mode = true
	camera.fp_target = pawn
	manager.camera = camera
	manager.players["self"] = pawn
	manager.local_fp_pawn_id = "self"
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	_check(key.is_action_pressed("jump"), "Space must be bound to jump")
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	_check(button.is_action_pressed("jump") and not button.is_action_pressed("fire"), "controller A jumps without firing")
	manager.call("_input", key)
	key.pressed = false
	manager.call("_input", key)
	manager.call("_process", 1.0 / 240.0)
	_check(network.sent.size() == 1 and network.sent[0].jump, "press and release in one render frame must send a jump")
	manager.call("_process", 1.0 / 240.0)
	_check(not network.sent[1].jump, "released press must be consumed once")
	key.pressed = true
	manager.call("_input", key)
	manager.set("role_transition", true)
	manager.call("_process", 1.0 / 60.0)
	_check(network.sent.size() == 2, "role transitions must not send actions")
	manager.free()
	network.free()
	camera.free()
	pawn.free()
	if _failures == 0:
		print("test_jump_input: PASS short taps, release, bindings, transition guard")
	quit(0 if _failures == 0 else 1)
