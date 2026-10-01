extends SceneTree

## A traveling point is a server position. Missing and empty lists draw nothing.
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_traveling_shot: " + reason)

func _run() -> void:
	var markers := TravelingShots.new()
	root.add_child(markers)
	markers.apply(null)
	_check(markers.get_child_count() == 0, "a missing list draws nothing")
	markers.apply([{"id": 1, "x": 2.0, "y": 1.6, "z": -0.5}, {"id": "nope", "x": 0, "y": 0, "z": 0}])
	_check(markers.get_child_count() == 1, "a bad entry is skipped")
	var marker := markers.get_child(0) as MeshInstance3D
	_check(marker != null and marker.name == "Shot1", "the marker keeps the server id")
	_check(is_equal_approx(marker.position.x, 2.0) and is_equal_approx(marker.position.y, 1.6) and is_equal_approx(marker.position.z, -0.5), "the marker uses the server position")
	markers.apply([{"id": 1, "x": 2.125, "y": 1.6, "z": -0.5}])
	_check(markers.get_child(0) == marker and is_equal_approx(marker.position.x, 2.125),
		"the same traveling point updates its existing marker without reallocating")
	for invalid: Variant in [NAN, INF, -1, 1.5, "2", null]:
		markers.apply([{"id": invalid, "x": 0, "y": 0, "z": 0}])
		_check(markers.get_child_count() == 0, "invalid shot identifiers never reach integer conversion")
	for invalid: Variant in [NAN, INF, 8193.0, "0", null]:
		markers.apply([{"id": 1, "x": invalid, "y": 0, "z": 0}])
		_check(markers.get_child_count() == 0, "invalid shot positions are rejected")
	markers.apply([{"id": 1, "x": 1, "y": 0, "z": 0}, {"id": 1, "x": 9, "y": 0, "z": 0}])
	_check(markers.get_child_count() == 1 and is_equal_approx((markers.get_child(0) as Node3D).position.x, 1.0),
		"duplicate identifiers preserve one authoritative marker")
	markers.apply([{"id": 4, "x": 1.0, "y": 1.6, "z": 0.0}, {"id": 5, "x": -1.0, "y": 1.6, "z": 3.0}])
	_check(markers.get_child_count() == 2, "two points in flight draw two markers")
	_check(markers.get_child(0).name == "Shot4" and markers.get_child(1).name == "Shot5", "markers stay in server order")
	_check((markers.get_child(0) as MeshInstance3D).mesh == (markers.get_child(1) as MeshInstance3D).mesh,
		"traveling markers share their immutable mesh")
	markers.apply([])
	_check(markers.get_child_count() == 0, "an empty list clears the markers")
	markers.free()
	if _failures == 0:
		print("test_traveling_shot: PASS")
	quit(0 if _failures == 0 else 1)
