extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_actor_state: " + message)

func _actor() -> Dictionary:
	return {"id": "guard", "name": "Clerk", "hp": 60,
		"campaign": {"side": "union", "kind": "clerk", "phase": "windup", "phase_started": 10, "phase_ends": 22}}

func _run() -> void:
	var actor: Dictionary = _actor()
	var snapshot: Dictionary = {"type": "snapshot", "tick": 12, "players": [
		{"id": "human", "campaign": {"side": "participant"}},
		{"id": "agent", "campaign": {"side": "participant"}}, actor.duplicate(true)]}
	_check(ActorState.validation_error(snapshot).is_empty(), "valid campaign identity accepted")
	var participants: Array[Dictionary] = ActorState.participants(snapshot["players"])
	_check(participants.size() == 2 and participants[0]["id"] == "human" and participants[1]["id"] == "agent", "only participants belong to the scoreboard and camera roster")
	_check(ActorState.is_participant({"id": "arcade"}), "legacy arcade roster preserved")
	for patch: Dictionary in [{"side": "unknown"}, {"kind": "crawler"}, {"phase": "attacking"},
		{"phase_started": -1}, {"phase_started": 13}, {"phase_started": "10"}, {"phase_ends": 9},
		{"phase_ends": 111}, {"phase_ends": NAN}, {"phase_ends": 22.5}, {"unknown": 1}, {"kind": []}, {"phase": "dead"}]:
		var bad: Dictionary = _actor()
		bad["campaign"].merge(patch, true)
		_check(not ActorState.validation_error({"tick": 12, "players": [bad]}).is_empty(), "reject invalid identity: " + str(patch))
	for invalid: Variant in [[], "union", {"side": "participant", "kind": "clerk"}]:
		var bad: Dictionary = _actor()
		bad["campaign"] = invalid
		_check(not ActorState.validation_error({"tick": 12, "players": [bad]}).is_empty(), "reject invalid campaign shape")
	actor["hp"] = 0
	actor["campaign"]["phase"] = "dead"
	_check(ActorState.validation_error({"tick": 12, "players": [actor]}).is_empty(), "dead actor remains available for bounded death presentation")
	for invalid: Variant in ["60", INF, 12.5]:
		actor["hp"] = invalid
		_check(not ActorState.validation_error({"tick": 12, "players": [actor]}).is_empty(), "non-integer health rejected")
	var network: Node = load("res://scripts/net_client.gd").new()
	var received: Array[Dictionary] = []
	network.snapshot_received.connect(func(data: Dictionary) -> void: received.append(data))
	network.player_id = "self"
	network._handle_message(JSON.stringify(snapshot))
	_check(received.size() == 1, "validated actors reach the game")
	snapshot["players"][2]["campaign"]["phase"] = "unknown"
	network._handle_message(JSON.stringify(snapshot))
	_check(received.size() == 1 and network.player_id == null, "malformed actor closes the session before presentation")
	network.free()
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	pawn.set_process(false)
	pawn.set_player_data("guard", "Intake Clerk")
	var appearance: Dictionary = _actor()
	appearance.merge({"x": 0.0, "y": 1.5, "z": 4.0, "yaw": 0.0, "weapon": "Tack"})
	pawn.update_state(appearance)
	_check(pawn.is_campaign_enemy and pawn.campaign_actor["kind"] == "clerk", "real pawn retains typed identity")
	_check(is_zero_approx(pawn.hit_flash_timer), "a lower initial HP is not a wound on arrival")
	appearance["hp"] = 40
	pawn.update_state(appearance)
	_check(pawn.hit_flash_timer > 0.0, "actual subsequent damage still produces feedback")
	pawn.free()
	if _failures == 0:
		print("test_actor_state: PASS")
	quit(0 if _failures == 0 else 1)
