extends SceneTree

class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		sent.append(data.duplicate(true))

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("test_resume: " + message)
	quit(1)

func _run() -> void:
	var network: CaptureNetwork = CaptureNetwork.new()
	network.role = "human"
	network.player_name = "Patch"
	network.send_hello()
	if str(network.sent[0].get("resume", "missing")) != "":
		_fail("a new human hello must ask for a resume token")
		return
	network._resume_token = "v1.kept"
	network._resume_audience = network.audience_for(network.server_url)
	network.sent.clear()
	network.send_hello()
	if network.sent[0].get("resume") != "v1.kept":
		_fail("a drop hello must present the resume token")
		return
	network._resume_audience = ""
	network.sent.clear()
	network.send_hello()
	if network.sent[0].get("resume") != "":
		_fail("a resume token with no issuing server must stay off the hello")
		return
	network._resume_audience = network.audience_for(network.server_url)
	network.role = "spectator"
	network.sent.clear()
	network.send_hello()
	if network.sent[0].has("resume"):
		_fail("a spectator hello must not ask to keep a pawn")
		return
	network.role = "human"
	network.connection_state = WebSocketPeer.STATE_OPEN
	network.sent.clear()
	network.leave_match()
	if network.sent.is_empty() or network.sent[0].get("type") != "leave":
		_fail("leave must be explicit before the socket closes")
		return
	if network._resume_token != "" or network._resume_audience != "":
		_fail("leave kept a resume token")
		return
	network.server_url = "ws://203.0.113.8:6767"
	network._handle_message(JSON.stringify({"type": "welcome", "role": "human", "player_id": "pawn", "body": "human", "resume": "v1.issued"}))
	if network._resume_token != "v1.issued" or network._resume_audience != "ws://203.0.113.8:6767":
		_fail("welcome did not bind the resume token to its server")
		return
	network.server_url = "ws://198.51.100.8:6767"
	network.sent.clear()
	network.send_hello()
	if network.sent[0].get("resume") != "" or network._resume_token != "v1.issued":
		_fail("a different server received the previous resume token")
		return
	network.server_url = "ws://203.0.113.8:6767"
	network.sent.clear()
	network.send_hello()
	if network.sent[0].get("resume") != "v1.issued":
		_fail("the issuing server did not receive its resume token")
		return
	var seen: Array[String] = []
	network._leaving = false
	network.connect("server_error", func(message: String) -> void: seen.append(message))
	if not bool(network.call("_admission_error", "resume_rejected")) or seen != ["The previous pawn is gone."]:
		_fail("resume refusal was " + str(seen))
		return
	network.free()
	print("test_resume: PASS")
	quit(0)
