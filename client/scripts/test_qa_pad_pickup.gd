extends "res://scripts/qa_tour.gd"

## Isolated controller fixture. Only a real server can award live equipment.
class Pad extends Node3D:
	var weapon_name: String = "Rail"
	var pickup_id: String = "fixture-rail"
	var available: bool = false

class Network extends Node:
	signal event_received(data: Dictionary)
	var player_id: String = "fixture"

class Manager extends Node:
	var latest_snapshot: Dictionary = {"map_id": 1, "round_state": "Active"}
	var pickups: Dictionary = {}
	var net_client: Node

var _manager: Manager
var _goals: Array[Vector3] = []
var _completion: Array[bool] = []
var _waits: int = 0
var _owns_rail: bool = false

func _game_manager() -> Node:
	return _manager

func _owned_weapons() -> Array:
	return ["tack", "rail"] if _owns_rail else ["tack"]

func _wait_live_joined_fighter(_state_name: String) -> bool:
	_waits += 1
	# A second attempt proves the old cooldown was abandoned. The fixture
	# intentionally declines a new life instead of running another route.
	return _waits == 1

func _local_human_alive(_manager_node: Node) -> bool:
	return true

func _local_feet() -> Vector3:
	return Vector3.ZERO

func _walk_to(goal: Vector3, _look_back: bool = false, _stop_round_state: String = "", _guide_only: bool = false) -> bool:
	_goals.append(goal)
	_walk_results.append({"arrived": true})
	return true

func _finish_pad() -> void:
	_completion.append(await _take_from_pad("Rail"))

func _check(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error("test_qa_pad_pickup: " + message)

func _await_completion() -> void:
	var deadline: int = Time.get_ticks_msec() + 2000
	while _completion.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	_check(not _completion.is_empty(), "fixture completes without a pending cooldown coroutine")

func _run() -> void:
	_manager = Manager.new()
	var network: Network = Network.new()
	_manager.net_client = network
	var pad: Pad = Pad.new()
	pad.position = Vector3(-20.0, 0.9, 6.0)
	_manager.pickups["fixture-rail"] = pad
	_finish_pad()
	await create_timer(0.2).timeout
	_check(_goals.size() == 1 and _goals[0].is_equal_approx(Vector3(-20.0, 0.5, 6.0)) and _completion.is_empty(),
		"cooldown permits the final ordinary approach and then waits at the pad")
	pad.available = true
	await create_timer(0.2).timeout
	_check(_completion.is_empty(), "available pad alone does not prove equipment ownership")
	_owns_rail = true
	Input.action_press("fire")
	Input.action_press("move_right")
	await _await_completion()
	_check(_completion == [true] and _waits == 1, "acknowledged ownership completes the same attempt")
	_check(not Input.is_action_pressed("fire") and not Input.is_action_pressed("move_right"), "pickup return releases held defensive input")
	if _completion.is_empty():
		quit(1)
		return
	_goals.clear()
	_completion.clear()
	_waits = 0
	_owns_rail = false
	pad.available = false
	_finish_pad()
	await create_timer(0.2).timeout
	_check(_goals.size() == 1 and _completion.is_empty(), "second attempt reaches the cooling pad")
	network.event_received.emit({"event": "frag", "victim_id": network.player_id})
	Input.action_press("fire")
	Input.action_press("move_forward")
	await _await_completion()
	_check(_completion == [false] and _waits == 2 and _goals.size() == 1,
		"death cancels the cooldown and requires a fresh living attempt")
	_check(not Input.is_action_pressed("fire") and not Input.is_action_pressed("move_forward"), "interrupted return releases held defensive input")
	_disconnect_pad_network()
	pad.free()
	network.free()
	_manager.free()
	if not _failed:
		print("test_qa_pad_pickup: PASS approach during cooldown, ownership acknowledgement and interrupted wait")
	quit(1 if _failed else 0)
