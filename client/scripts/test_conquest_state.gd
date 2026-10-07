extends SceneTree

var failures: Array[String] = []
var accepted: int = 0
var refused: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

static func snapshot() -> Dictionary:
	var points: Array = []
	var positions: Array = [[-105, 0, 65], [-100, 0, -35], [0, 0, -70], [100, 0, -35], [105, 0, 65]]
	for index: int in range(5):
		points.append({"id": ConquestState.SITES[index], "position": positions[index], "radius": 8.0,
			"owner": null, "capturing": null, "progress": 0, "contested": false})
	return {"type": "snapshot", "tick": 100, "players": [], "conquest": {"tickets": {"union": 200, "coalition": 200},
		"initial_tickets": 200, "capture_ticks": 160, "points": points}}

func _run() -> void:
	_check(ConquestState.validation_error({}).is_empty(), "ordinary snapshots remain compatible")
	_check(ConquestState.validation_error(snapshot()).is_empty(), "five neutral sites valid")
	_check(MatchRules.teams(MatchRules.parse({"mode": "conquest"})), "conquest assigns teams")
	for invalid: Array in [["radius", NAN], ["position", [0, INF, 0]], ["progress", 161],
		["owner", "other"], ["capturing", "other"], ["contested", 1], ["extra", true]]:
		var sample: Dictionary = snapshot()
		sample.conquest.points[0][invalid[0]] = invalid[1]
		_check(not ConquestState.validation_error(sample).is_empty(), "refuse malformed site " + str(invalid[0]))
	for key: String in ["tickets", "initial_tickets", "capture_ticks", "points"]:
		var sample: Dictionary = snapshot()
		sample.conquest.erase(key)
		_check(not ConquestState.validation_error(sample).is_empty(), "require " + key)
	var sample: Dictionary = snapshot()
	sample.conquest.points[1].id = "harbour"
	_check(not ConquestState.validation_error(sample).is_empty(), "duplicate site refused")
	sample = snapshot()
	sample.conquest.tickets.union = 201
	_check(not ConquestState.validation_error(sample).is_empty(), "ticket overflow refused")
	sample = snapshot()
	sample.conquest.points[0].progress = 1
	_check(not ConquestState.validation_error(sample).is_empty(), "progress requires capturing side")
	var network: Node = load("res://scripts/net_client.gd").new()
	network.snapshot_received.connect(func(_data: Dictionary) -> void: accepted += 1)
	network.server_error.connect(func(_problem: String) -> void: refused += 1)
	network._requires_conquest = true
	network._handle_message(JSON.stringify(snapshot()))
	_check(accepted == 1, "native boundary delivers complete conquest state")
	var absent: Dictionary = snapshot()
	absent.erase("conquest")
	network._handle_message(JSON.stringify(absent))
	_check(refused == 1 and accepted == 1, "conquest match refuses missing state")
	network.free()
	var markers: ArenaConquest = ArenaConquest.new()
	root.add_child(markers)
	var hud: ConquestHud = ConquestHud.new()
	root.add_child(hud)
	sample = snapshot()
	markers.apply(sample)
	hud.apply(sample)
	_check(markers.markers.size() == 5 and hud.visible, "five markers and HUD presented")
	sample.conquest.points[0].owner = "union"
	sample.conquest.points[0].capturing = "coalition"
	sample.conquest.points[0].progress = 80
	sample.conquest.points[0].contested = true
	markers.apply(sample)
	hud.apply(sample)
	_check(hud.state.points[0].progress == 80 and hud.state.points[0].contested, "contest retains exact server progress")
	hud.apply({})
	markers.apply({})
	_check(not hud.visible and markers.markers.is_empty(), "leave removes state and markers")
	markers.queue_free()
	hud.queue_free()
	await process_frame
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "automated scene never captures pointer")
	if failures.is_empty():
		print("test_conquest_state: PASS")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
