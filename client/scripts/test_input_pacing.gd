extends SceneTree

## A tap shorter than one frame must reach the server exactly once, and a fast
## display must not send more actions than the server's inbound budget admits.
class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: String = "self"
	var mission: Dictionary = {}
	var sent: Array[Dictionary] = []
	func send_action(action: Dictionary) -> void:
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
	manager.free()
	network.free()
	if _failures == 0:
		print("test_input_pacing: PASS sub-frame taps delivered once, sends paced under the inbound budget")
	quit(0 if _failures == 0 else 1)
