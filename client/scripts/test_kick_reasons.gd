extends SceneTree

## Covers the v0.46 server close codes a live session can receive:
## idle_timeout, rate_limited, malformed, address_banned, address_not_allowed.
## Each must map to its own localized message (no hardcoded English), and
## only idle_timeout may still make the client's one automatic resume
## attempt; the other four remove the pawn server-side, so the client must
## not attempt one either. See client/scripts/net_client.gd _close_message
## and _admission_error, and docs/protocol.md's close-code table.

const KICK_KEYS: Dictionary = {
	"match_full": "SABOTAGE_MATCH_FULL",
	"bot_fill_next_round": "BOT_FILL_NEXT_ROUND",
	"bot_fill_cancelled": "BOT_FILL_CANCELLED",
	"rate_limited": "NET_RATE_LIMITED",
	"malformed": "NET_MALFORMED",
	"address_banned": "NET_ADDRESS_BANNED",
	"address_not_allowed": "NET_ADDRESS_NOT_ALLOWED",
}

class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		sent.append(data.duplicate(true))

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("test_kick_reasons: " + message)
	quit(1)

func _new_client() -> Node:
	return load("res://scripts/net_client.gd").new()

func _run() -> void:
	if not _check_message_mapping():
		return
	if not _check_kicks_block_resume():
		return
	if not _check_full_match_can_watch():
		return
	if not _check_idle_timeout_keeps_resume():
		return
	print("test_kick_reasons: PASS")
	quit(0)

## Message mapping: every close code resolves to its own real, localized
## string, distinct from every other one and from its own bare msgid key.
func _check_message_mapping() -> bool:
	var network: Node = _new_client()
	var seen_messages: Array[String] = []
	var all_keys: Dictionary = KICK_KEYS.duplicate()
	all_keys["idle_timeout"] = "NET_IDLE_TIMEOUT"
	for code in all_keys:
		var key: String = str(all_keys[code])
		var expected: String = tr(key)
		var actual: String = str(network.call("_close_message", code))
		if actual.is_empty() or actual == key:
			_fail("%s did not resolve to localized text (got %s)" % [code, actual])
			network.free()
			return false
		if actual != expected:
			_fail("%s mapped to %s, expected %s" % [code, actual, expected])
			network.free()
			return false
		if actual in seen_messages:
			_fail("%s reused another code's message" % code)
			network.free()
			return false
		seen_messages.append(actual)
	network.free()
	return true

func _check_full_match_can_watch() -> bool:
	for code: String in ["match_full", "bot_fill_next_round", "bot_fill_cancelled"]:
		for role: String in ["human", "agent"]:
			if not _check_refusal_can_watch(code, role):
				return false
	return true

func _check_refusal_can_watch(code: String, role: String) -> bool:
	var network: CaptureNetwork = CaptureNetwork.new()
	network.role = role
	network._handle_message(JSON.stringify({"type": "welcome", "role": role,
		"player_id": "previous", "body": "human", "resume": "v1.previous"}))
	if network.player_id != "previous" or network._resume_token != "v1.previous":
		_fail("refusal fixture did not receive its actual Welcome token")
		network.free()
		return false
	var seen: Array[String] = []
	network.server_error.connect(func(message: String) -> void: seen.append(message))
	network._handle_message(JSON.stringify({"type": "error", "code": code, "message": "untrusted remote text"}))
	if seen != [tr(str(KICK_KEYS[code]))] or network.player_id != null or not network._leaving or network.is_processing():
		_fail(code + " packet did not retire the fighter and show localized refusal")
		network.free()
		return false
	if network._try_resume():
		_fail(code + " packet silently retried the fighter")
		network.free()
		return false
	network.set_server_host("127.0.0.1:1")
	if not network.connect_to_server("spectator", "Watch probe"):
		_fail("a deliberate spectator reconnect remained blocked")
		network.free()
		return false
	network.send_hello()
	if network._leaving or network.sent.size() != 1 or network.sent[0].get("role") != "spectator" or network.sent[0].has("resume"):
		_fail("spectator reconnect reused the refused fighter seat")
		network.disconnect_from_server()
		network.free()
		return false
	network.disconnect_from_server()
	network.free()
	return true

## rate_limited, malformed, address_banned and address_not_allowed are hard
## stops: the client shows the message, disconnects, and its one automatic
## resume attempt (_try_resume) must not fire afterward.
func _check_kicks_block_resume() -> bool:
	for code in KICK_KEYS:
		var kicked: Node = _new_client()
		kicked.set("role", "human")
		kicked.set("_resume_token", "v1.kept")
		var seen: Array[String] = []
		kicked.connect("server_error", func(message: String) -> void: seen.append(message))
		if not bool(kicked.call("_admission_error", code)):
			_fail(code + " was not treated as a hard stop")
			kicked.free()
			return false
		if seen != [tr(str(KICK_KEYS[code]))]:
			_fail(code + " message was " + str(seen))
			kicked.free()
			return false
		if bool(kicked.call("_try_resume")):
			_fail(code + " made an automatic resume attempt")
			kicked.free()
			return false
		kicked.free()
	return true

## idle_timeout is not a hard stop from _admission_error: no message from
## that path (the STATE_CLOSED branch in _process shows it instead) and the
## same resume path a plain ten-second drop uses stays open.
func _check_idle_timeout_keeps_resume() -> bool:
	var idle: Node = _new_client()
	idle.set("role", "human")
	idle.set("_resume_token", "v1.kept")
	var seen: Array[String] = []
	idle.connect("server_error", func(message: String) -> void: seen.append(message))
	if bool(idle.call("_admission_error", "idle_timeout")):
		_fail("idle_timeout was treated as a hard stop")
		idle.free()
		return false
	if not seen.is_empty():
		_fail("idle_timeout emitted a message from _admission_error: " + str(seen))
		idle.free()
		return false
	if not bool(idle.call("_try_resume")):
		_fail("idle_timeout lost its one automatic resume attempt")
		idle.free()
		return false
	idle.free()
	return true
