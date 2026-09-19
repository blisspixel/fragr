extends SceneTree

class CapturingClient extends "res://scripts/net_client.gd":
	var sent: Dictionary = {}
	func send_json(data: Dictionary) -> void:
		sent = data.duplicate(true)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var network: CapturingClient = CapturingClient.new()
	var camera: Node3D = game.get_node("SpectatorCamera")
	game.net_client = network
	game.camera = camera
	game.is_human_player = true
	network.connection_state = WebSocketPeer.STATE_OPEN
	camera.fp_yaw = 1.2
	camera.fp_pitch = -0.6
	game._process(0.0)
	var ok: bool = network.sent.get("type") == "action"
	ok = ok and is_equal_approx(float(network.sent.get("yaw", 99.0)), 1.2)
	ok = ok and is_equal_approx(float(network.sent.get("pitch", 99.0)), -0.6)
	ok = ok and int(network.sent.get("seq", 0)) == 1
	camera.fp_pitch = 10.0
	game._process(0.0)
	ok = ok and is_equal_approx(float(network.sent.get("pitch", 99.0)), ServerYaw.PITCH_LIMIT)
	var legacy: Dictionary = {"fire": true}
	network.send_action(legacy)
	ok = ok and not network.sent.has("pitch") and bool(network.sent.get("fire", false))
	game.free()
	network.free()
	if ok:
		print("test_vertical_aim: PASS real match input builder, pitch clamp, legacy omission")
	else:
		push_error("test_vertical_aim: action builder lost or changed the camera aim")
	quit(0 if ok else 1)
