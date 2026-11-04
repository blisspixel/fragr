extends SceneTree

const Capture = preload("res://scripts/qa_aim_cone.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var rest: Dictionary = {"weapon": "flechette", "cone_microradians": 0,
		"ring_radius_pixels": 0.0, "reticle_visible": true, "ring_visible": false,
		"pip_position": [640.0, 360.0]}
	var open: Dictionary = rest.duplicate(true)
	open["cone_microradians"] = 45000
	open["ring_radius_pixels"] = 20.0
	open["ring_visible"] = true
	var burst: Dictionary = {"weapon": "Flechette", "aim_open": true}
	var resting: Dictionary = {"weapon": "Flechette", "aim_rest": true}
	_check(Capture.sample_error([rest, open], burst, 2).is_empty(), "burst onset may start exact")
	_check(Capture.sample_error([rest], resting, 1).is_empty(), "rest keeps a visible pip without a ring")
	var tiny: Dictionary = open.duplicate(true)
	tiny["ring_radius_pixels"] = 3.0
	tiny["ring_visible"] = false
	_check(Capture.sample_error([tiny], burst, 1).is_empty(), "a sub-pip cone does not invent a ring")
	for patch: Dictionary in [{"weapon": "rail"}, {"reticle_visible": false},
		{"ring_visible": false}, {"ring_radius_pixels": 0.0, "ring_visible": false},
		{"ring_radius_pixels": NAN}, {"pip_position": [INF, 360.0]}, {"cone_microradians": null}]:
		var bad: Dictionary = open.duplicate(true)
		bad.merge(patch, true)
		_check(not Capture.sample_error([bad], burst, 1).is_empty(), "bad presentation refused: " + str(patch))
	var moved: Dictionary = open.duplicate(true)
	moved["pip_position"] = [641.0, 360.0]
	_check(not Capture.sample_error([rest, moved], burst, 2).is_empty(), "movement within strip refused")
	_check(not Capture.sample_error([moved], burst, 1, Vector2(640, 360)).is_empty(), "movement between states refused")
	_check(not Capture.sample_error([rest], burst, 1).is_empty(), "closed burst refused")
	_check(not Capture.sample_error([open], resting, 1).is_empty(), "open rest refused")
	var raising: Dictionary = rest.duplicate(true)
	raising["raise_ready_at"] = 10
	_check(not Capture.sample_error([raising], resting, 1).is_empty(), "raising rest refused")
	_check(not Capture.sample_error([rest], resting, 2).is_empty(), "missing frames refused")
	for failure: String in failures:
		push_error("test_qa_aim_cone: " + failure)
	if failures.is_empty():
		print("test_qa_aim_cone: PASS live capture rejects missing or mismatched presentation")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
