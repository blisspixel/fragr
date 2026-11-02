extends "res://qa/still_here_review.gd"

## Exercise the review driver's real prerequisite and failure flow without a
## renderer or server. Only capture and camera posing are replaced; movement
## completion, state waiting and input release use the production helper.
class Probe extends Node:
	var net_client: Dictionary = {"player_id": "walker", "mission": {"state": {"phase": "in_progress", "epilogue": {"later": false}}}}
	var players: Dictionary[String, Node3D] = {}
	var is_human_player: bool = true
	var opening: Node
	var still_here_page: Node
	func _mission_controls_blocked() -> bool:
		return false

class Camera extends Node3D:
	var fp_yaw: float = 0.0
	var fp_pitch: float = 0.0

var failures: int = 0
var probe: Probe
var capture_calls: Array[String] = []
var capture_error: Error = OK

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_tests.call_deferred()

func _manager() -> Node:
	return probe

func _pose(_manager_node: Node, _state: Dictionary) -> void:
	pass

func _capture(_manager_node: Node, state: Dictionary) -> Error:
	capture_calls.append(state["name"])
	return capture_error

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_still_here_review: " + message)

func _tests() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/still-here-review.json"))
	_check(manifest is Dictionary and valid_states(manifest.get("states")), "the current review manifest remains valid")
	for value: Variant in [null, {}, [], [null], [{"name": ""}], [{"name": "../escape"}], [{"name": "same"}, {"name": "same"}], [{"name": "bad", "walk_to": [[0, NAN, 0]]}], [{"name": "bad", "await_seconds": -1}], [{"name": "bad", "walk_seconds": "0"}], [{"name": "bad", "camera": "overview"}], [{"name": "bad", "dismiss": "typo"}], [{"name": "bad", "await": "refuge"}], [{"name": "bad", "camera": "overveiw"}], [{"name": "bad", "walk_too": [[0, 0, 0]]}]]:
		_check(not valid_states(value), "invalid manifest cannot enter the review loop: " + str(value))
	probe = Probe.new()
	root.add_child(probe)
	var camera: Camera = Camera.new()
	camera.name = "SpectatorCamera"
	probe.add_child(camera)
	var pawn: Node3D = Node3D.new()
	probe.add_child(pawn)
	pawn.position = Vector3(0.0, 1.5, 0.0)
	probe.players["walker"] = pawn
	await process_frame

	_check(await _walk(probe, Vector3.ZERO, 0.0), "a reached point succeeds even with no remaining wait")
	_check(not await _walk(probe, Vector3(0, 2, 0), 0.0), "the wrong floor never counts as arrival")
	_check(not await _walk(probe, Vector3(10, 0, 0), 0.01), "a stationary walker times out")
	_check(not Input.is_action_pressed("move_forward"), "failed walking releases held input")
	create_timer(0.05).timeout.connect(func() -> void: pawn.position = Vector3(4, 1.5, 0))
	_check(not await _walk(probe, Vector3.ZERO, 0.1), "passing the goal and drifting away before release settles is not arrival")
	pawn.position = Vector3(0, 1.5, 0)
	probe.players.clear()
	_check(not await _walk(probe, Vector3.ZERO, 0.0), "a lost pawn fails the walk")
	_check(not Input.is_action_pressed("move_forward"), "lost pawn releases held input")
	probe.players["walker"] = pawn

	var failed_wait: String = await _review_states([
		{"name": "never-departed", "await": "phase:departed", "await_seconds": 0.0},
		{"name": "must-not-follow", "settle_seconds": 0.0},
	])
	_check("never happened" in failed_wait and capture_calls.is_empty(), "a failed named state produces no capture and stops the route")
	var failed_walk: String = await _review_states([
		{"name": "unreachable", "walk_to": [[10, 0, 0]], "walk_seconds": 0.0},
		{"name": "must-not-follow", "settle_seconds": 0.0},
	])
	_check("walk never reached" in failed_walk and capture_calls.is_empty(), "a failed walk cannot be labelled as a successful scene")
	var missing_page: String = await _review_states([{"name": "missing-page", "dismiss": "page"}])
	_check("page is absent" in missing_page and capture_calls.is_empty(), "missing pages are not silently dismissed")
	_check((await _review_states([{"name": "ready", "await": "phase:in_progress", "await_seconds": 0.0, "walk_to": [[0, 0, 0]], "walk_seconds": 0.0, "settle_seconds": 0.0}])).is_empty(), "a fulfilled state can be captured")
	_check(capture_calls == ["ready"], "one successful state makes exactly one capture")
	capture_error = ERR_CANT_CREATE
	var unwritable: String = await _review_states([
		{"name": "unwritable", "settle_seconds": 0.0},
		{"name": "must-not-follow", "settle_seconds": 0.0},
	])
	_check("could not save" in unwritable and capture_calls == ["ready", "unwritable"], "capture failure stops the route and reaches the caller")
	probe.queue_free()
	probe = null
	await process_frame
	_check((await _review_states([{"name": "missing-manager"}])) == "no GameManager", "missing client fails without a capture")
	if failures == 0:
		print("test_still_here_review: PASS prerequisite, arrival, capture and cleanup failures")
	quit(1 if failures > 0 else 0)
