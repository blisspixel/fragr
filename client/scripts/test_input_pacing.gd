extends SceneTree

## A tap shorter than one frame must reach the server exactly once, and a fast
## display must not send more actions than the server's inbound budget admits.
class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: String = "self"
	var mission: Dictionary = {}
	var sent: Array[Dictionary] = []
	var last_send_ok: bool = true
	var fail_next: bool = false
	func send_action(action: Dictionary) -> void:
		last_send_ok = not fail_next
		fail_next = false
		if last_send_ok:
			sent.append(action.duplicate())

## Mirror of net.rs InboundBudget: 256 messages per second, burst 64.
const BUDGET_PER_SEC: float = 256.0
const BUDGET_BURST: float = 64.0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_input_pacing: " + message)

func _tap(manager: Node) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	manager.call("_input", key)
	var release: InputEventKey = key.duplicate()
	release.pressed = false
	manager.call("_input", release)

func _run() -> void:
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var network: CaptureNetwork = CaptureNetwork.new()
	manager.set("net_client", network)
	manager.set("is_human_player", true)
	var probe: InputEventKey = InputEventKey.new()
	probe.physical_keycode = KEY_F
	probe.pressed = true
	_check(probe.is_action_pressed("interact"), "F must be bound to interact")
	var interval: int = int(manager.get("ACTION_SEND_INTERVAL_USEC"))
	_check(interval * 256 > 1000000, "paced sends stay under the server budget")
	# 500 fps for two seconds with one tap between sends, then a tap on a send frame.
	var now: int = 1000000
	var tokens: float = BUDGET_BURST
	var dropped: int = 0
	var last: int = now
	var tapped: bool = false
	for frame: int in range(1000):
		now += 2000
		if frame == 301:
			_tap(manager)
			tapped = true
		var before: int = network.sent.size()
		manager.call("_send_local_action", now)
		if network.sent.size() > before:
			tokens = minf(BUDGET_BURST, tokens + float(now - last) / 1000000.0 * BUDGET_PER_SEC)
			last = now
			if tokens >= 1.0:
				tokens -= 1.0
			else:
				dropped += 1
	var interacts: int = 0
	for action: Dictionary in network.sent:
		if action.get("interact", false):
			interacts += 1
	_check(tapped and interacts == 1, "a sub-frame tap is delivered exactly once, got %d" % interacts)
	_check(network.sent.size() <= 241 and network.sent.size() >= 200, "500 fps sends about 120 actions per second, sent %d in 2 s" % network.sent.size())
	_check(dropped == 0, "the server budget drops no paced action, dropped %d" % dropped)
	var seqs: Array[int] = []
	for action: Dictionary in network.sent:
		seqs.append(int(action["seq"]))
	_check(seqs == range(seqs[0], seqs[0] + seqs.size()), "every paced send takes the next input number")
	# A skipped frame keeps the latch: the tap rides the next due send.
	network.sent.clear()
	manager.set("_last_action_usec", now)
	_tap(manager)
	_check(not manager.call("_send_local_action", now + 1000) and network.sent.is_empty(), "an early frame sends nothing")
	_check(manager.call("_send_local_action", now + interval) and network.sent.size() == 1 and network.sent[0].get("interact", false), "the latched tap is carried by the next send")
	manager.call("_send_local_action", now + interval * 2)
	_check(network.sent.size() == 2 and not network.sent[1].get("interact", false), "the tap is consumed once")
	network.sent.clear()
	manager.set("input_seq", manager.get("MAX_ACTION_SEQ") - 1)
	manager.call("_send_local_action", now + interval * 3)
	manager.call("_send_local_action", now + interval * 4)
	_check(network.sent.size() == 2 and network.sent[0]["seq"] == 4294967295 and
		network.sent[1]["seq"] == 1,
		"the live sender wraps within the u32 sequence range")
	# A failed WebSocket send cannot consume a one-shot press or weapon choice.
	network.sent.clear()
	manager.set("pending_jump", true)
	manager.set("pending_interact", true)
	manager.set("pending_weapon_swap", "scatter")
	network.fail_next = true
	manager.call("_send_local_action", now + interval * 5)
	_check(network.sent.is_empty() and not network.last_send_ok, "failed action was not delivered")
	_check(manager.get("pending_jump") and manager.get("pending_interact") and manager.get("pending_weapon_swap") == "scatter",
		"failed send keeps all one-shot inputs")
	manager.call("_send_local_action", now + interval * 6)
	_check(network.sent.size() == 1 and network.sent[0].get("jump", false) and
		network.sent[0].get("interact", false) and network.sent[0].get("weapon_swap") == "scatter",
		"next successful action carries the retained one-shot inputs")
	manager.call("_send_local_action", now + interval * 7)
	_check(network.sent.size() == 2 and not network.sent[1].get("jump", false) and
		not network.sent[1].get("interact", false) and network.sent[1].get("weapon_swap") == null,
		"one-shot inputs clear after a successful send")
	# The server reads fire once per tick. A tap released before that tick
	# stays held until an Ack shows a tick consumed it, never longer than the
	# bound, so a quick click cannot vanish between two server ticks.
	network.sent.clear()
	var fire_down: InputEventAction = InputEventAction.new()
	fire_down.action = "fire"
	fire_down.pressed = true
	manager.call("_input", fire_down)
	var fire_up: InputEventAction = fire_down.duplicate()
	fire_up.pressed = false
	manager.call("_input", fire_up)
	manager.call("_send_local_action", now + interval * 8)
	var tap_seq: int = int(network.sent[0]["seq"])
	manager.call("_send_local_action", now + interval * 9)
	_check(network.sent.size() == 2 and network.sent[0].get("fire", false) and network.sent[1].get("fire", false),
		"a released tap stays held until a tick consumes it")
	manager.call("_on_ack_received", {"seq": tap_seq - 1, "tick": 7})
	manager.call("_send_local_action", now + interval * 10)
	_check(network.sent[2].get("fire", false), "an Ack for an older input does not release the tap")
	manager.call("_on_ack_received", {"seq": tap_seq + 1, "tick": 8})
	manager.call("_send_local_action", now + interval * 11)
	_check(not network.sent[3].get("fire", false), "the Ack covering the tap releases it")
	manager.call("_input", fire_down)
	manager.call("_input", fire_up)
	manager.call("_send_local_action", now + interval * 12)
	manager.call("_send_local_action", now + interval * 12 + int(manager.get("FIRE_TAP_HOLD_USEC")) + 1)
	_check(network.sent[4].get("fire", false) and not network.sent[5].get("fire", false),
		"without an Ack the tap is released after its bound")
	manager.free()
	network.free()
	if _failures == 0:
		print("test_input_pacing: PASS sub-frame taps delivered once, fire taps held until a tick consumes them, sends paced under the inbound budget")
	quit(0 if _failures == 0 else 1)
