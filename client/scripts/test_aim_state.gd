extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var valid: Dictionary = {"type": "aim", "player_id": "self", "tick": 20,
		"weapon": "rail", "cone_microradians": 12000, "raise_ready_at": 27}
	_check(AimState.validation_error(valid, "self").is_empty(), "valid private aim")
	_check(not AimState.validation_error(valid, "other").is_empty(), "owner mismatch")
	for patch: Dictionary in [{"tick": -1}, {"tick": NAN}, {"tick": 1.5}, {"cone_microradians": 190001},
		{"cone_microradians": -1}, {"cone_microradians": "0"}, {"cone_microradians": INF},
		{"weapon": "unknown"}, {"raise_ready_at": null}, {"raise_ready_at": 20}, {"raise_ready_at": 28}, {"extra": true}]:
		var bad: Dictionary = valid.duplicate(true)
		bad.merge(patch, true)
		_check(not AimState.validation_error(bad, "self").is_empty(), "reject " + str(patch))
	var earlier: Dictionary = valid.duplicate(true)
	earlier["tick"] = 19
	earlier.erase("raise_ready_at")
	_check(not AimState.validation_error(earlier, "self", valid).is_empty(), "cannot rewind aim")
	var network: Node = load("res://scripts/net_client.gd").new()
	network.player_id = "self"
	network._handle_message(JSON.stringify(valid))
	_check(network.aim.get("weapon") == "rail" and int(network.aim.get("cone_microradians", -1)) == 12000 \
		and int(network.aim.get("raise_ready_at", -1)) == 27, "network publishes validated aim")
	network._handle_message(JSON.stringify(earlier))
	_check(network.aim.is_empty() and network.player_id == null, "bad aim closes and clears")
	network.free()
	var cue: LocalFireFeedback = LocalFireFeedback.new()
	var equipment: Dictionary = {"tick": 20, "selected": "rail", "weapons": ["fists", "rail"],
		"ammo": [{"pool": "bullets", "rounds": 0}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 10}, {"pool": "rockets", "rounds": 0}]}
	cue.observe_aim(valid)
	_check(not cue.sent({"seq": 1, "fire": true}, equipment, "rail", 26, 1000000, true), "no predicted flash during raise")
	_check(cue.sent({"seq": 2, "fire": true}, equipment, "rail", 27, 1050000, true), "deadline restores local cue")
	cue.reset()
	valid["weapon"] = "flechette"
	valid.erase("raise_ready_at")
	cue.observe_aim(valid)
	_check(not cue.sent({"seq": 3, "fire": true}, equipment, "rail", 27, 1100000, true), "equipment arriving before aim cannot skip raise")
	if failures.is_empty():
		print("test_aim_state: PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
