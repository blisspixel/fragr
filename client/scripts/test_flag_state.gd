extends SceneTree

## The CTF wire boundary and scene marker must agree on all three states.
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_flag_state: " + reason)

func _flag(team: String, x: float) -> Dictionary:
	return {"team": team, "stand": [x, 0.0, 0.0], "position": [x, 0.0, 0.0], "status": "home"}

func _run() -> void:
	_check(FlagState.distance_m([0.0, 0.0, 0.0], [10.0, 0.0, -10.0]) == 14, "flag distance rounds to metres")
	_check(FlagState.bearing([0.0, 0.0, 0.0], [0.0, 0.0, -10.0]) == "N", "north is negative Z")
	_check(FlagState.bearing([0.0, 0.0, 0.0], [10.0, 0.0, -10.0]) == "NE", "diagonal bearing")
	_check(FlagState.bearing([0.0, 0.0, 0.0], [-10.0, 0.0, 0.0]) == "W", "west is negative X")
	var flags: Array = [_flag("union", -70.0), _flag("coalition", 70.0)]
	var snap: Dictionary = {"flags": flags, "capture_scores": {"union": 0, "coalition": 0}, "capture_limit": 3}
	_check(FlagState.snapshot_error(snap).is_empty(), "home flags parse")
	var renderer: ArenaFlags = ArenaFlags.new()
	root.add_child(renderer)
	renderer.apply(flags)
	_check(renderer.get_child_count() == 4, "two stands and two flags render")
	var home_label: Label3D = renderer.get_child(1).get_node("FlagLabel")
	_check(home_label.text == "UNION FLAG", "home label uses the stand words")
	_check(is_equal_approx(home_label.position.x, 0.0), "home label stays on the pole")
	flags[0]["status"] = "carried"
	flags[0]["carrier"] = "fighter-1"
	flags[0]["position"] = [11.0, 0.0, 3.0]
	flags[1]["status"] = "carried"
	flags[1]["carrier"] = "fighter-2"
	flags[1]["position"] = [-11.0, 0.0, 0.0]
	_check(FlagState.snapshot_error(snap).is_empty(), "carrier parses")
	renderer.apply(flags)
	_check((renderer.get_child(1) as Node3D).position.x == 11.0, "marker follows server carrier")
	var carried_label: Label3D = renderer.get_child(1).get_node("FlagLabel")
	_check(carried_label.text == "UNION FLAG CARRIED", "carried label names the carry")
	_check(not carried_label.text.contains("fighter-1"), "carried world label omits the callsign")
	_check(is_equal_approx(carried_label.position.x, 0.66), "carried label uses the cloth offset")
	var other_label: Label3D = renderer.get_child(3).get_node("FlagLabel")
	_check(other_label.text == "FREE FLAG CARRIED", "coalition carried label names the carry")
	flags[1]["status"] = "home"
	flags[1].erase("carrier")
	flags[1]["position"] = [70.0, 0.0, 0.0]
	flags[0].erase("carrier")
	flags[0]["status"] = "dropped"
	flags[0]["return_ticks"] = 399
	_check(FlagState.snapshot_error(snap).is_empty(), "drop clock parses")
	renderer.apply(flags)
	var dropped_marker: Node3D = renderer.get_child(1)
	_check(dropped_marker.get_node("DropMark").visible, "dropped flag has a floor marker")
	var dropped_label: Label3D = dropped_marker.get_node("FlagLabel")
	_check(dropped_label.text == "UNION FLAG DOWN", "dropped label says it is down")
	_check(is_equal_approx(dropped_label.position.x, 0.0), "dropped label returns to the pole")
	flags[0]["return_ticks"] = 401
	_check(not FlagState.snapshot_error(snap).is_empty(), "overlong drop clock refuses")
	flags[0]["return_ticks"] = 399
	flags[1]["team"] = "union"
	_check(not FlagState.snapshot_error(snap).is_empty(), "duplicate side refuses")
	flags[1]["team"] = "coalition"
	snap["capture_scores"]["union"] = -1
	_check(not FlagState.snapshot_error(snap).is_empty(), "negative capture count refuses")
	renderer.clear_flags()
	_check(renderer.get("_markers").is_empty(), "round cleanup clears markers")
	renderer.queue_free()
	if _failures == 0:
		print("test_flag_state: PASS")
	quit(0 if _failures == 0 else 1)
