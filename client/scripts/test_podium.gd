extends SceneTree
## The podium between rounds: the ready-up prompt for one more round, a
## Duel's series line, the `again` key on the wire, and that clearing the
## podium never hides a Sabotage prompt that shares the plate.

class Wire extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary):
		sent.append(data)

const ME: String = "00000000-0000-0000-0000-000000000001"
const RIVAL: String = "00000000-0000-0000-0000-000000000002"

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_podium: " + message)

func _plate_text(hud: CanvasLayer) -> String:
	var label: RichTextLabel = hud.get("_use_label")
	return label.get_parsed_text() if label != null else ""

func _plate_up(hud: CanvasLayer) -> bool:
	var plate: Control = hud.get("_use_plate")
	return plate != null and plate.visible

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	root.add_child(hud)
	hud.set_mode("PLAYING")
	await process_frame

	var duel: Array = [{"id": ME, "name": "Probe", "wins": 2}, {"id": RIVAL, "name": "Nightfall", "wins": 1}]
	hud.show_podium({"voters": 2, "duel": duel}, ME)
	var text: String = _plate_text(hud)
	_check(_plate_up(hud), "the podium shows its plate")
	_check(text.contains("SERIES  PROBE 2 : 1 NIGHTFALL"), "the Duel series reads level and upright: " + text)
	_check(text.contains("ONE MORE") and text.contains("0 OF 2 READY"), "the ready-up names the key and the count: " + text)
	hud.show_podium({"voters": 2, "again": [ME], "duel": duel}, ME)
	text = _plate_text(hud)
	_check(text.contains("WAITING ON 1") and not text.contains("ONE MORE"), "pressed: the plate says who it waits on: " + text)
	hud.show_podium({"voters": 2, "again": [ME, RIVAL]}, ME)
	_check(_plate_text(hud).contains("NEXT ROUND LOADING"), "everyone ready: the next round loads")
	# A spectator sees the series but is never asked to press.
	hud.show_podium({"voters": 2, "duel": duel}, "")
	text = _plate_text(hud)
	_check(text.contains("SERIES") and not text.contains("ONE MORE"), "a spectator reads the series only: " + text)
	hud.show_podium(null, ME)
	_check(not _plate_up(hud), "mid-round the podium plate is gone")
	# A Sabotage prompt on the same plate survives the podium clearing.
	# The Duel line: a watcher sees who is next and their own place; a
	# fighter sees the line only on the podium.
	# Two watchers can share a name; the server's private place says which
	# entry is this one.
	hud.show_podium(null, "", ["Probe", "Probe"], 2, true)
	text = _plate_text(hud)
	_check(text.contains("NEXT UP  PROBE, PROBE") and text.contains("YOU ARE 2 OF 2"), "a queued watcher reads the line: " + text)
	hud.show_podium(null, "", ["Static Kid"], 0, true)
	_check(_plate_text(hud).contains("WAIT FOR THE NEXT SEAT"), "an unqueued watcher is offered the line")
	hud.show_podium(null, ME, ["Static Kid"], 0, true)
	_check(not _plate_up(hud), "mid-round a fighter is not shown the line")
	hud.show_podium({"voters": 2, "duel": duel}, ME, ["Static Kid"], 0, true)
	_check(_plate_text(hud).contains("NEXT UP  STATIC KID"), "the podium shows the line to fighters")
	hud.show_podium(null, "", [], 0, false)
	_check(not _plate_up(hud), "outside a Duel nothing is offered")
	var many: Array = []
	for n: int in range(6):
		many.append("W%d" % n)
	hud.show_podium(null, "", many, 6, true)
	text = _plate_text(hud)
	_check(text.contains("W0, W1, W2  +3") and text.contains("6 OF 6"), "a long line shows three and a count: " + text)
	hud.show_podium(null, ME)
	hud._show_use_plate("{use} PLANT")
	hud.show_podium(null, ME)
	_check(_plate_up(hud) and _plate_text(hud).contains("PLANT"), "clearing the podium leaves a plant prompt alone")
	hud._show_use_plate("")
	# Malformed podiums say nothing rather than guessing.
	for bad: Variant in [[], "ready", {"voters": "two"}, {"voters": 2, "again": "all"}, {"duel": [1, 2]}]:
		hud.show_podium(bad, ME)
		var shown: String = _plate_text(hud) if _plate_up(hud) else ""
		_check(not shown.contains("SERIES"), "a malformed podium shows no series: %s" % str(bad))

	# The key: a press on the podium rides the next Action and nothing else.
	var wire := Wire.new()
	root.add_child(wire)
	wire.send_action({"again": true, "seq": 4})
	wire.send_action({"seq": 5})
	_check(wire.sent.size() == 2 and wire.sent[0].get("again") == true and not wire.sent[1].has("again"),
		"again is sent only when pressed: %s" % str(wire.sent))
	game.latest_snapshot = {"round_state": "Ended", "podium": {"voters": 1}}
	game.net_client = wire
	wire.player_id = ME
	_check(game._podium_waits_on_me(), "an ended round with voters waits on the local fighter")
	# Fragged at the whistle: no body to steer, and the press still goes out.
	wire.sent.clear()
	game.pending_again = true
	game._send_podium_again()
	_check(wire.sent.size() == 1 and wire.sent[0].get("again") == true and wire.sent[0].has("seq"),
		"a bodiless fighter's press is one numbered again: %s" % str(wire.sent))
	game.latest_snapshot = {"round_state": "Active"}
	_check(not game._podium_waits_on_me(), "mid-round nothing waits")
	game.latest_snapshot = {"round_state": "Ended"}
	_check(not game._podium_waits_on_me(), "a bots-only podium never asks")
	# A level Duel ends with nobody named: null mvp and frags are a plain
	# round-over card, never "<null>" or a script error.
	game.hud = hud
	game._on_event_received({"event": "round_end", "mvp": null, "mvp_frags": null, "winner": null,
		"host_line": "HOST: ROUND CLOSED. NO MVP. LEAGUE DENIES THE SCRAP.", "final_scores": [], "reason": "Time limit reached"})
	_check(hud.result_subject == "ROUND OVER" and not hud.round_message.text.contains("null"),
		"a nameless result reads as round over: " + hud.result_subject)
	# The line's key and the seat call: a watcher asks with one message, a
	# called watcher's next fighter Hello carries the token once, and a
	# malformed token is ignored.
	wire.sent.clear()
	wire.role = "spectator"
	wire.connection_state = WebSocketPeer.STATE_OPEN
	wire.send_queue(true)
	_check(wire.sent.size() == 1 and wire.sent[0] == {"type": "queue", "wait": true}, "queue is one message: %s" % str(wire.sent))
	var called: Array[String] = []
	wire.seat_called.connect(func(token: String) -> void: called.append(token))
	wire._handle_message(JSON.stringify({"type": "seat_call", "seat": "0123abcd"}))
	wire._handle_message(JSON.stringify({"type": "seat_call", "seat": "<script>"}))
	wire._handle_message(JSON.stringify({"type": "seat_call", "seat": 4}))
	_check(called == ["0123abcd"], "only a plain token calls: %s" % str(called))
	wire.sent.clear()
	wire.role = "human"
	wire.seat_token = "0123abcd"
	wire.send_hello()
	wire.send_hello()
	_check(wire.sent.size() == 2 and wire.sent[0].get("seat") == "0123abcd" and not wire.sent[1].has("seat"), "the token rides one Hello: %s" % str(wire.sent))
	# The server's private place and a full line's refusal reach the watcher.
	wire.role = "spectator"
	wire._handle_message(JSON.stringify({"type": "queue_place", "place": 3, "of": 4}))
	_check(wire.queue_place == 3 and wire.queue_of == 4, "a watcher learns its own place")
	wire._handle_message(JSON.stringify({"type": "queue_place", "place": 5, "of": 4}))
	_check(wire.queue_place == 3, "a place past the line's end is refused")
	var refusals: Array[String] = []
	wire.queue_refused.connect(func(message: String) -> void: refusals.append(message))
	wire._handle_message(JSON.stringify({"type": "error", "code": "queue_full", "message": "The line for this duel is full."}))
	_check(refusals == ["The line for this duel is full."], "a full line says so without closing")
	var passed: Array[int] = [0]
	wire.seat_passed.connect(func() -> void: passed[0] += 1)
	wire._handle_message(JSON.stringify({"type": "error", "code": "duel_seat_passed", "message": "Winner stays."}))
	_check(passed[0] == 1, "a passed seat is not a hard stop")
	game.net_client = null
	wire.queue_free()
	game.free()
	hud.queue_free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("test_podium: PASS ready-up prompt, Duel series and line, spectator view, shared plate, the again key and the seat call")
	quit(0 if _failures == 0 else 1)
