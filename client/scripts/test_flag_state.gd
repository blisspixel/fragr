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
	_check(is_equal_approx(carried_label.position.x, ArenaFlags.CARRIED_CLOTH_AT.x), "carried words stay on the cloth")
	_check(is_equal_approx(carried_label.position.z, ArenaFlags.CARRIED_LABEL_AT.z), "carried label sits out on the cloth")
	_check(carried_label.position.y > ArenaFlags.CARRIED_CLOTH_AT.y, "carried words sit above the cloth")
	_check(is_equal_approx(ArenaFlags.CARRIED_HAND_Y, EnemyAnimation.CENTRE_HEIGHT - EnemyView.CAMERA.FP_SERVER_REFERENCE_Y), "carried flag uses the weapon hand height")
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	holder.position = Vector3(4.0, 1.5, 2.0)
	holder.rotation.y = 0.4
	renderer.apply(flags, {"fighter-1": holder})
	var mounted: Node3D = renderer.get_child(1) as Node3D
	var side: Vector3 = -holder.global_transform.basis.z
	var front: Vector3 = holder.global_transform.basis.x
	side.y = 0.0
	front.y = 0.0
	side = side.normalized()
	front = front.normalized()
	var expected_hand: Vector3 = holder.global_position + Vector3(0.0, ArenaFlags.CARRIED_HAND_Y, 0.0) + side * ArenaFlags.CARRIED_SIDE + front * ArenaFlags.CARRIED_FRONT
	_check(mounted.global_position.distance_to(expected_hand) < 0.02, "carried flag sits in the carrier's hand")
	_check(mounted.global_transform.basis.y.dot(Vector3.UP) > 0.98, "carried banner stays upright")
	_check(mounted.global_transform.basis.x.dot(side) > 0.98, "carried cloth reaches out from the grip")
	var grip: MeshInstance3D = mounted.get_node("Pole") as MeshInstance3D
	_check(grip.visible, "a carried flag keeps a short grip")
	_check(is_equal_approx((grip.mesh as BoxMesh).size.y, ArenaFlags.CARRIED_POLE_SIZE.y), "the carried pole is short enough to stay off the face")
	_check((mounted.get_node("Cloth") as MeshInstance3D).position.is_equal_approx(ArenaFlags.CARRIED_CLOTH_AT), "carried cloth hangs from the grip")
	var union_pad: StandardMaterial3D = (renderer.get_child(0).get_node("Pad") as MeshInstance3D).material_override as StandardMaterial3D
	_check(union_pad.albedo_color.get_luminance() < MatchRules.team_label_color("union").get_luminance() * 0.75, "an empty stand is dimmer than the flag")
	var other: Node3D = Node3D.new()
	root.add_child(other)
	other.position = Vector3(-6.0, 1.5, 1.0)
	renderer.set_first_person_carrier("fighter-1")
	renderer.apply(flags, {"fighter-1": holder, "fighter-2": other})
	_check(not mounted.visible, "first person hides the carrier's world grip")
	_check(mounted.global_position.distance_to(expected_hand) < 0.02, "a hidden grip stays seated")
	var other_flag: Node3D = renderer.get_child(3) as Node3D
	_check(other_flag.visible, "another carrier's flag stays in the world")
	_check(other_flag.global_position.distance_to(other.global_position) < 2.0, "the other carrier still holds a grip")
	other.queue_free()
	renderer._process(0.05)
	_check(not mounted.visible, "seating the grip does not reveal it in first person")
	renderer.set_first_person_carrier("")
	renderer.apply(flags, {"fighter-1": holder})
	_check((renderer.get_child(1) as Node3D).visible, "leaving first person restores the world grip")
	holder.queue_free()
	var other_label: Label3D = renderer.get_child(3).get_node("FlagLabel")
	_check(other_label.text == "FREE FLAG CARRIED", "coalition carried label names the carry")
	flags[1]["status"] = "home"
	flags[1].erase("carrier")
	flags[1]["position"] = [70.0, 0.0, 0.0]
	flags[0].erase("carrier")
	flags[0]["status"] = "dropped"
	flags[0]["return_ticks"] = 399
	_check(FlagState.snapshot_error(snap).is_empty(), "drop clock parses")
	renderer.set_first_person_carrier("fighter-1")
	renderer.apply(flags)
	renderer.set_first_person_carrier("")
	var dropped_marker: Node3D = renderer.get_child(1)
	_check(dropped_marker.visible, "a dropped flag stays in the world for the fighter who carried it")
	_check(dropped_marker.get_node("DropMark").visible, "dropped flag has a floor marker")
	var dropped_label: Label3D = dropped_marker.get_node("FlagLabel")
	_check(dropped_label.text == "UNION FLAG DOWN", "dropped label says it is down")
	_check(is_equal_approx(dropped_label.position.x, 0.0), "dropped label returns to the pole")
	var dropped_pole: MeshInstance3D = dropped_marker.get_node("Pole") as MeshInstance3D
	_check(is_equal_approx((dropped_pole.mesh as BoxMesh).size.y, ArenaFlags.HOME_POLE_SIZE.y), "a dropped flag restores the stand pole")
	var home_pad_mesh: MeshInstance3D = renderer.get_child(2).get_node("Pad") as MeshInstance3D
	var home_pad: StandardMaterial3D = home_pad_mesh.material_override as StandardMaterial3D
	_check(home_pad.albedo_color.is_equal_approx(MatchRules.team_label_color("coalition")), "a flag at home restores the stand")
	_check(is_equal_approx((home_pad_mesh.mesh as BoxMesh).size.x, ArenaFlags.HOME_PAD_SIZE.x), "a flag at home uses the full stand")
	var empty_pad: MeshInstance3D = renderer.get_child(0).get_node("Pad") as MeshInstance3D
	_check(is_equal_approx((empty_pad.mesh as BoxMesh).size.x, ArenaFlags.EMPTY_PAD_SIZE.x), "an empty stand shrinks to a socket")
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.global_position = Vector3(11.0, 2.4, 10.0)
	camera.look_at(Vector3(11.0, 1.6, 3.0))
	var blockers: Array[Rect2] = renderer.blocker_rects(camera)
	_check(blockers.size() >= 2, "a flag in view reserves its words and cloth")
	var covered: Array[Dictionary] = [
		{"id": "carrier", "rect": blockers[0], "priority": 0, "distance": 4.0},
		{"id": "wing", "rect": Rect2(-4000, -4000, 20, 20), "priority": 2, "distance": 8.0},
	]
	_check(NameplateLayout.choose(covered, blockers) == ["wing"], "a plate on the flag yields and a clear plate stays")
	camera.free()
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
	_check_return_bearings()
	if _failures == 0:
		print("test_flag_state: PASS")
	quit(0 if _failures == 0 else 1)


func _check_return_bearings() -> void:
	var names: Dictionary = {"a1": "Dead Air Dan", "b2": "Nightfall"}
	var carried: Dictionary = {
		"team": "union", "status": "carried", "carrier": "a1",
		"stand": [-70.0, 0.0, 0.0], "position": [0.0, 0.0, 0.0],
	}
	var home: Dictionary = {
		"team": "coalition", "status": "home",
		"stand": [70.0, 0.0, 0.0], "position": [70.0, 0.0, 0.0],
	}
	_check(FlagState.status_text(home, "a1", "coalition", [0.0, 0.0, 0.0], names, true) == "HOME 70M E",
		"a carrier is pointed at their own stand")
	_check(FlagState.status_text(carried, "a1", "coalition", [0.0, 0.0, 0.0], names, true) == "CARRIED BY Dead Air Dan",
		"a carrier is not given a distance to themselves")
	_check(FlagState.status_text(carried, "b2", "union", [0.0, 0.0, -14.0], names, false) == "CARRIED BY Dead Air Dan, 14M S",
		"everyone else is pointed at a stolen flag")
	_check(FlagState.status_text(home, "b2", "union", [0.0, 0.0, -14.0], names, false) == "HOME",
		"a flag at home stays home for someone who is not carrying")
	carried["position"] = [0.2, 0.0, 0.0]
	_check(FlagState.status_text(carried, "b2", "union", [0.0, 0.0, 0.0], names, false) == "CARRIED BY Dead Air Dan",
		"under a metre the compass is omitted")
	carried.erase("position")
	_check(FlagState.status_text(carried, "b2", "union", [0.0, 0.0, 0.0], names, false) == "CARRIED BY Dead Air Dan",
		"a carried flag with no position keeps the name")
	var dropped: Dictionary = {
		"team": "coalition", "status": "dropped", "return_ticks": 39,
		"stand": [70.0, 0.0, 0.0], "position": [10.0, 0.0, -10.0],
	}
	_check(FlagState.status_text(dropped, "a1", "coalition", [0.0, 0.0, 0.0], names, true) == "DOWN 2S, 14M NE",
		"a dropped own flag still points at the flag")
	_check(FlagState.status_text(home, "a1", "", [0.0, 0.0, 0.0], names, true) == "HOME",
		"a carrier with no side is not pointed at a stand")
	_check(FlagState.status_text(home, "a1", "coalition", [70.0, 0.0, 0.0], names, true) == "HOME",
		"standing on the stand does not add a zero-metre compass")
