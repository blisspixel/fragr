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
	var charge: Dictionary = _actor()
	charge["hp"] = 140
	charge["campaign"]["kind"] = "enforcer"
	charge["campaign"]["phase"] = "charging"
	_check(ActorState.validation_error({"tick":12, "players":[charge]}).is_empty(),
		"authoritative human Enforcer charging accepted")
	for wrong_role: String in ["clerk", "sweeper", "crawler", "auditor"]:
		var wrong_charge: Dictionary = charge.duplicate(true)
		wrong_charge["campaign"]["kind"] = wrong_role
		_check(not ActorState.validation_error({"tick":12, "players":[wrong_charge]}).is_empty(),
			"charging phase cannot rename another role: " + wrong_role)
	var seated: Dictionary = _actor()
	seated["campaign"]["phase"] = "idle"
	seated["campaign"]["seated"] = true
	_check(ActorState.validation_error({"tick":12, "players":[seated]}).is_empty(),
		"seated Clerk is accepted before activation")
	for patch: Dictionary in [{"seated":false}, {"seated":1}, {"kind":"sweeper"}, {"phase":"windup"}]:
		var invalid_seat: Dictionary = seated.duplicate(true)
		invalid_seat["campaign"].merge(patch, true)
		_check(not ActorState.validation_error({"tick":12, "players":[invalid_seat]}).is_empty(),
			"reject invalid seated guard: " + str(patch))
	for kind: String in ["sweeper", "heavy_sweeper", "turret", "crawler", "jammer", "ranged_sweeper"]:
		var other: Dictionary = _actor()
		other["campaign"]["kind"] = kind
		_check(ActorState.validation_error({"tick": 12, "players": [other]}).is_empty(), "accept Union kind " + kind)
	var participants: Array[Dictionary] = ActorState.participants(snapshot["players"])
	_check(participants.size() == 2 and participants[0]["id"] == "human" and participants[1]["id"] == "agent", "only participants belong to the scoreboard and camera roster")
	_check(ActorState.is_participant({"id": "arcade"}), "legacy arcade roster preserved")
	var latch: Dictionary = {"id": "ally", "name": "Latch", "x": 7.55, "y": 1.5, "z": -14.8,
		"yaw": 0.0, "hp": 100, "weapon": "Tack", "just_fired": false,
		"campaign": {"side": "companion", "kind": "latch", "phase": "releasing", "phase_started": 10}}
	snapshot["players"].append(latch)
	_check(ActorState.validation_error(snapshot).is_empty() and ActorState.is_companion(latch) and not ActorState.is_union(latch),
		"one server-owned Latch identity and spatial pawn are accepted")
	_check(ActorState.participants(snapshot["players"]).size() == 2, "Latch never enters participant roster")
	_check(not ActorState.validation_error({"tick": 12, "players": [latch, latch.duplicate(true)]}).is_empty(),
		"a snapshot cannot present two Latches")
	for patch: Dictionary in [{"side": "union"}, {"kind": "unknown"}, {"phase": "dead"},
		{"phase_started": 13}, {"phase_started": -1}, {"phase_started": 1.5}, {"phase_ends": 20}]:
		var invalid_latch: Dictionary = latch.duplicate(true)
		invalid_latch["campaign"].merge(patch, true)
		_check(not ActorState.validation_error({"tick": 12, "players": [invalid_latch]}).is_empty(),
			"reject malformed companion identity: " + str(patch))
	for patch: Dictionary in [{"body": "synthetic"}, {"hp": 0}, {"hp": 101}, {"weapon": "Rail"},
		{"just_fired": 1}, {"just_fired": true}, {"x": NAN}, {"yaw": INF}]:
		var invalid_latch: Dictionary = latch.duplicate(true)
		invalid_latch.merge(patch, true)
		_check(not ActorState.validation_error({"tick": 12, "players": [invalid_latch]}).is_empty(),
			"reject contradictory releasing companion pawn: " + str(patch))
	var fighting_latch: Dictionary = latch.duplicate(true)
	fighting_latch["campaign"]["phase"] = "firing"
	fighting_latch["just_fired"] = true
	_check(ActorState.validation_error({"tick": 12, "players": [fighting_latch]}).is_empty(),
		"authoritative supporting fire is accepted after release")
	snapshot["players"].pop_back()
	var leap: Dictionary = _actor()
	leap["campaign"]["kind"] = "crawler"
	leap["campaign"]["phase"] = "leaping"
	_check(ActorState.validation_error({"tick": 12, "players": [leap]}).is_empty(),
		"typed Crawler leap accepted")
	for patch: Dictionary in [{"side": "unknown"}, {"kind": "crawling"}, {"kind": "heavy"}, {"kind": "Turret"}, {"phase": "attacking"},
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
	var ally: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(ally)
	ally.set_process(false)
	ally.set_player_data("ally", "Latch")
	ally.update_state(latch, 12)
	_check(ally.is_campaign_companion and not ally.is_campaign_enemy and ally.latch_view is LatchView,
		"the companion uses a separate authored chassis")
	for part: Node in ally.latch_view.find_children("*", "VisualInstance3D", true, false):
		_check((part as VisualInstance3D).layers == ArenaSky.ACTOR_LAYERS,
			"the moving Latch uses the same actor lighting layer as the ward figure")
	_check(not ally.body.visible and not ally.weapon_sprite.visible and not ally.latch_view.get_node("RightArm/Tack").visible,
		"releasing Latch shows neither a participant body nor a drawn weapon")
	_check(is_equal_approx(ally.latch_view.position.y, -1.5) and ally.label.text == "LATCH",
		"the companion feet and name register apart from a player body")
	var moving: Dictionary = latch.duplicate(true)
	moving["campaign"]["phase"] = "following"
	moving["x"] = 8.0
	ally.update_state(moving, 13)
	_check(ally.latch_view.get_node("RightArm/Tack").visible and ally.target_position.x == 8.0,
		"following Latch uses the server position and carries a Tack")
	var ally_skin: Skeleton3D = ally.latch_view._source_body.get_node("Armature/Skeleton3D") as Skeleton3D
	var resting_leg: Transform3D = ally_skin.get_bone_global_pose(ally_skin.find_bone("LeftLeg"))
	ally.latch_view.advance(0.1, 0.5, "following")
	_check(not resting_leg.is_equal_approx(ally_skin.get_bone_global_pose(ally_skin.find_bone("LeftLeg"))),
		"rendered travel deforms the actual ally skin")
	ally.show_muzzle_flash("Tack")
	_check(ally.latch_view.get_node("RightArm/Tack/Flash").visible,
		"authoritative supporting fire lights the ally's weapon")
	ally.free()
	if _failures == 0:
		print("test_actor_state: PASS")
	quit(0 if _failures == 0 else 1)
