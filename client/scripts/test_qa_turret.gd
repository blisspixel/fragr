extends SceneTree

const OBSERVER = preload("res://scripts/qa_turret.gd")
const PLAYER: String = "00000000-0000-0000-0000-000000000001"
const TURRET: String = "00000000-0000-0000-0000-000000000002"
const OTHER: String = "00000000-0000-0000-0000-000000000003"
const COVER: Array[Dictionary] = [{"min_x": -10.0, "max_x": -7.0,
	"min_z": 10.0, "max_z": 13.0, "top": 3.0}]
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_qa_turret: " + message)

static func _snapshot(tick: int) -> Dictionary:
	var phase: String = "windup" if tick < 19 else ("recovery" if tick < 31 else "idle")
	var started: int = 10 if tick < 19 else (19 if tick < 31 else 31)
	var ends: int = 36 if tick < 19 else 31
	return {"tick": tick, "players": [
		{"id": PLAYER, "name": "Viewer", "hp": 100,
			"x": 4.0 if tick < 18 else 0.0, "y": 1.5, "z": 16.0 if tick < 18 else 10.0,
			"campaign": {"side": "participant"}},
		{"id": TURRET, "name": "intro_turret", "hp": 100, "x": -18.5, "y": 4.5, "z": 16.0,
			"campaign": {"side": "union", "kind": "turret", "phase": phase,
				"phase_started": started, "phase_ends": ends}}]}

static func _shot(shooter: String) -> Dictionary:
	return {"shooter_id": shooter, "hit": false, "damage": 0, "killed": false}

func _observer(solids: Array = COVER) -> QaTurret:
	var observer: QaTurret = OBSERVER.new()
	_check(observer.begin(PLAYER, "intro_turret", solids), "bounded observer configuration accepted")
	return observer

func _run() -> void:
	var observer: QaTurret = _observer()
	for tick: int in range(10, 37):
		observer.observe(_snapshot(tick))
	_check(not observer.report()["passed"], "early recovery alone cannot prove the absence of the original shot")
	observer.observe(_snapshot(37))
	var result: Dictionary = observer.report()
	_check(result["passed"] and result["cancellations"].size() == 1,
		"visible charge, real blocked cover, twelve-tick early recovery and full deadline prove cancellation")
	var receipt: Dictionary = result["cancellations"][0]
	_check(receipt["windup"]["phase_started"] == 10 and receipt["cancel"]["tick"] == 19
		and receipt["verified_through_tick"] == 37 and receipt["original_deadline"] == 36
		and receipt["before_cancel"]["tick"] == 18 and receipt["before_cancel"]["phase"] == "windup"
		and receipt["before_cancel"]["cover"]["solid"] == COVER[0]
		and receipt["before_cancel"]["player_feet"] == [0.0, 0.0, 10.0]
		and receipt["cancel"]["cover"]["solid"] == COVER[0]
		and receipt["cancel"]["player_feet"] == [0.0, 0.0, 10.0],
		"receipt retains exact cycle, grounded participant, registered blocker and negative-shot observation window")
	result["cancellations"].clear()
	_check(observer.report()["cancellations"].size() == 1, "receipt mutation cannot rewrite retained evidence")
	_check_rejections()
	_check_identity_and_wire()
	_check_dedup_and_unrelated_facts()
	if failures == 0:
		print("test_qa_turret: PASS actual cover cycle, deadline, named shots, interrupted and incomplete observations")
	quit(0 if failures == 0 else 1)

func _check_rejections() -> void:
	for scenario: String in ["fired", "normal_firing", "ordinary_recovery", "no_cover", "recovery_only_cover", "prior_out_of_range", "stagger", "dead_player", "out_of_range", "gap", "missing_start", "changed_cycle", "missing_target", "ambiguous_party", "dead_peer"]:
		var observer: QaTurret = _observer([] if scenario == "no_cover" else COVER)
		for tick: int in range(11 if scenario == "missing_start" else 10, 38):
			if scenario == "gap" and tick == 22:
				continue
			var snapshot: Dictionary = _snapshot(tick)
			var turret: Dictionary = snapshot["players"][1]
			if scenario == "fired" and tick == 36:
				snapshot["shot_results"] = [_shot(TURRET)]
			if scenario == "normal_firing":
				snapshot["players"][0]["x"] = 4.0
				snapshot["players"][0]["z"] = 16.0
				turret["campaign"] = {"side": "union", "kind": "turret",
					"phase": "windup" if tick < 36 else ("firing" if tick == 36 else "recovery"),
					"phase_started": 10 if tick < 36 else (36 if tick == 36 else 37),
					"phase_ends": 36 if tick < 36 else (37 if tick == 36 else 67)}
				if tick == 36:
					snapshot["shot_results"] = [_shot(TURRET)]
			if scenario == "ordinary_recovery" and tick >= 19 and tick < 31:
				turret["campaign"]["phase_ends"] = 49
			if scenario == "recovery_only_cover" and tick == 18:
				snapshot["players"][0]["x"] = 4.0
				snapshot["players"][0]["z"] = 16.0
			if scenario == "prior_out_of_range" and tick == 18:
				snapshot["players"][0]["x"] = 40.0
			if scenario == "stagger" and tick >= 18:
				turret["hp"] = 20
			if scenario == "dead_player" and tick >= 20:
				snapshot["players"][0]["hp"] = 0
			if scenario == "out_of_range" and tick >= 19:
				snapshot["players"][0]["x"] = 40.0
			if scenario == "changed_cycle" and tick >= 16 and tick < 19:
				turret["campaign"]["phase_started"] = 16
				turret["campaign"]["phase_ends"] = 42
			if scenario == "missing_target" and tick == 20:
				snapshot["players"].remove_at(1)
			if scenario in ["ambiguous_party", "dead_peer"]:
				var peer: Dictionary = snapshot["players"][0].duplicate(true)
				peer["id"] = OTHER
				if scenario == "dead_peer":
					peer["hp"] = -20
				snapshot["players"].append(peer)
			observer.observe(snapshot)
		_check(not observer.report()["passed"], scenario + " cannot stand in for a covered cancellation")

func _check_identity_and_wire() -> void:
	for scenario: String in ["different_actor", "wrong_faction", "duplicate_actor", "bad_coordinate", "bad_tick", "bad_shots", "bad_health"]:
		var observer: QaTurret = _observer()
		for tick: int in range(10, 38):
			var snapshot: Dictionary = _snapshot(tick)
			if tick == 20:
				match scenario:
					"different_actor": snapshot["players"][1]["id"] = OTHER
					"wrong_faction": snapshot["players"][1]["campaign"] = {"side": "participant"}
					"duplicate_actor": snapshot["players"].append(snapshot["players"][1].duplicate(true))
					"bad_coordinate": snapshot["players"][0]["x"] = INF
					"bad_tick": snapshot["tick"] = 20.5
					"bad_shots": snapshot["shot_results"] = "none"
					"bad_health": snapshot["players"][1]["hp"] = 2147483648.0
			observer.observe(snapshot)
		_check(not observer.report()["passed"], scenario + " refused without coercing untrusted evidence")
	var invalid: QaTurret = OBSERVER.new()
	_check(not invalid.begin("Viewer", "intro_turret", COVER), "callsign cannot replace actual player identity")
	_check(not invalid.begin(PLAYER, "", COVER), "a target must have a bounded registered name")
	_check(not invalid.begin(PLAYER, "intro_turret", [{"min_x": 1.0}]), "malformed cover cannot manufacture a blocked ray")

func _check_dedup_and_unrelated_facts() -> void:
	var observer: QaTurret = _observer()
	for tick: int in range(10, 38):
		var snapshot: Dictionary = _snapshot(tick)
		var heavy: Dictionary = snapshot["players"][1].duplicate(true)
		heavy["id"] = OTHER
		heavy["name"] = "unrelated_heavy"
		heavy["hp"] = 160 if tick < 20 else -25
		heavy["campaign"] = {"side": "union", "kind": "heavy_sweeper", "phase": "idle" if tick < 20 else "dead",
			"phase_started": 10, "phase_ends": 10}
		snapshot["players"].append(heavy)
		if tick == 22:
			snapshot["shot_results"] = [_shot(OTHER)]
		observer.observe(snapshot)
		observer.observe(snapshot)
		if tick > 10:
			observer.observe(_snapshot(tick - 1))
	var result: Dictionary = observer.report()
	_check(result["passed"] and result["trace"].size() == 28,
		"duplicates and stale snapshots deduplicate; unrelated Heavy health, corpses and shots retain exact target evidence")
	var death: Dictionary = _snapshot(38)
	death["players"][1]["hp"] = -60
	death["players"][1]["campaign"] = {"side": "union", "kind": "turret", "phase": "dead", "phase_started": 38, "phase_ends": 38}
	observer.observe(death)
	_check(observer.report()["passed"], "ordinary later Turret overkill cannot erase an already proved charge cancellation")
	observer = _observer()
	for _index: int in range(40):
		observer.observe(_snapshot(10))
	_check(not observer.report()["passed"] and observer.report()["trace"].size() == 1,
		"repeated old tick cannot advance the no-shot deadline")
