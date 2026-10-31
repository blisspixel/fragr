extends SceneTree
## #441 death lifecycle and #437 result-stamp residue. Drives the real game
## manager, camera and HUD through death, the server countdown and respawn
## with movement and the trigger held, in both event orders, and repeats it.

const LocalLifeScript = preload("res://scripts/local_life.gd")
const SELF: String = "00000000-0000-4000-8000-000000000001"
const RIVAL: String = "00000000-0000-4000-8000-000000000002"
const MATE_NEAR: String = "00000000-0000-4000-8000-000000000003"
const MATE_FAR: String = "00000000-0000-4000-8000-000000000004"

class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: String = SELF
	var player_name: String = "Meat"
	var mission: Dictionary = {}
	var equipment: Dictionary = {}
	var sent: Array[Dictionary] = []
	var last_send_ok: bool = true
	func send_action(action: Dictionary) -> void:
		last_send_ok = true
		sent.append(action.duplicate())

var _failures: int = 0
var _ack_tick: int = 100

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_death_lifecycle: " + message)

func _run() -> void:
	_life_transitions()
	_countdown_edges()
	await _manager_sequences()
	await _team_seat()
	await _clutch_card()
	await _stamp_residue()
	Input.action_release("move_forward")
	Input.action_release("fire")
	if _failures == 0:
		print("test_death_lifecycle: PASS life phases, countdown, input fence, death view, team seat, clutch stamp, respawn, stamp retire")
	quit(0 if _failures == 0 else 1)


func _life_transitions() -> void:
	var life: LocalLife = LocalLifeScript.new()
	_check(life.alive() and life.card_lines(0, "").is_empty(), "a new life is alive with no card")
	# Snapshot first, frag second.
	life.body_gone(10)
	_check(life.phase == LocalLife.Phase.DOWN and life.cause == "unknown", "an absent body is down before the frag fact")
	_check(life.chase_id() == "", "no killer known yet holds the view")
	life.record_frag("self", "rival", "Rival", 10)
	_check(life.phase == LocalLife.Phase.DOWN and life.cause == "killer" and life.chase_id() == "rival", "a late frag names the killer")
	var lines: PackedStringArray = life.card_lines(0, "Rival")
	_check(lines.size() == 3 and lines[0] == "FRAGGED BY Rival", "headline names the killer: %s" % [lines])
	_check(lines.size() == 3 and lines[1] == "WATCHING Rival" and lines[2] == "RESPAWNING", "lines label the view before a countdown: %s" % [lines])
	life.respawned()
	_check(life.alive() and life.killer_id == "", "respawn starts clean")
	# Frag first; suicide.
	life.record_frag("self", "self", "Meat", 20)
	_check(life.cause == "self" and life.chase_id() == "", "suicide never chases yourself")
	_check(life.card_lines(0, "")[0] == "SELF-INFLICTED" and life.card_lines(0, "")[1] == "YOUR LAST VIEW", "suicide holds the last view, labelled")
	life.body_gone(20)
	_check(life.cause == "self", "the snapshot after a frag keeps its cause")
	life.reset()
	# A killer without a name (left before the fact was read).
	life.record_frag("self", "ghost", "", 30)
	_check(life.card_lines(0, "")[0] == "FRAGGED BY AN UNNAMED FIGHTER", "missing killer name is still legible")
	life.reset()
	# World death with neither id nor name.
	life.record_frag("self", "", "", 40)
	_check(life.cause == "unknown" and life.card_lines(0, "")[0] == "YOU WENT DOWN", "no killer fact reads as down")
	var lost: Array[String] = ["flechette", "rail"]
	var costed: PackedStringArray = life.card_lines(0, "", lost)
	_check(costed.size() == 4 and costed[3] == "LOST RIFLE + RAILGUN", "a fourth line names the found guns lost: %s" % [costed])
	_check(life.card_lines(0, "", [] as Array[String]).size() == 3, "nothing lost, no fourth line")
	var card: DeathCard = DeathCard.new()
	root.add_child(card)
	card.present(costed)
	_check(card.loss() == "LOST RIFLE + RAILGUN" and card.visible, "the card shows the loss line")
	card.present(PackedStringArray(["A", "B", "C"]))
	_check(card.loss() == "", "a three-line card hides the loss line")
	card.queue_free()


func _countdown_edges() -> void:
	var life: LocalLife = LocalLifeScript.new()
	life.observe_ack({"tick": 5, "respawn_ticks": 40}, 0)
	_check(life.alive(), "an Ack never kills a living player")
	life.body_gone(50)
	life.observe_ack({"tick": 50, "respawn_ticks": 60}, 0)
	_check(life.phase == LocalLife.Phase.AWAITING and life.seconds_left(0) == 3, "60 ticks show 3 seconds")
	_check(life.seconds_left(2000001) == 1, "ceil keeps 1 until the last tick")
	life.observe_ack({"tick": 49, "respawn_ticks": 200}, 0)
	_check(life.seconds_left(0) == 3, "an older Ack cannot rewind the countdown")
	life.observe_ack({"tick": 70, "respawn_ticks": 40}, 1000000)
	_check(life.seconds_left(1000000) == 2, "each Ack re-anchors on the server's number")
	life.observe_ack({"tick": 71, "respawn_ticks": -3}, 0)
	life.observe_ack({"tick": 72, "respawn_ticks": 1.5}, 0)
	life.observe_ack({"tick": 73, "respawn_ticks": 1000000}, 0)
	_check(life.phase == LocalLife.Phase.AWAITING and life.seconds_left(1000000) == 2, "invalid countdowns are ignored")
	life.observe_ack({"tick": 80, "respawn_ticks": 0}, 5000000)
	_check(life.seconds_left(5000000) == 0 and life.card_lines(5000000, "")[2] == "RESPAWNING", "zero waits on the server, never admits")
	var out: LocalLife = LocalLifeScript.new()
	out.body_gone(90)
	out.observe_ack({"tick": 90}, 0)
	_check(out.phase == LocalLife.Phase.DOWN, "the death-tick Ack alone is not elimination")
	out.observe_ack({"tick": 91}, 0)
	_check(out.phase == LocalLife.Phase.OUT and out.card_lines(0, "")[2] == "OUT UNTIL THE NEXT ROUND", "no countdown after death is out")
	_check(MovementAck.validation_error({"seq": 1, "tick": 2, "x": 0, "z": 0, "yaw": 0, "respawn_ticks": 12}).is_empty(), "a countdown Ack validates")
	_check(not MovementAck.validation_error({"seq": 1, "tick": 2, "x": 0, "z": 0, "yaw": 0, "respawn_ticks": -1}).is_empty(), "a negative countdown is rejected at the boundary")
	_check(not MovementAck.validation_error({"seq": 1, "tick": 2, "x": 0, "z": 0, "yaw": 0, "respawn_ticks": "3"}).is_empty(), "a text countdown is rejected at the boundary")


func _send(manager: Node) -> void:
	manager.set("_last_action_usec", -1000000000)
	manager.call("_process", 1.0 / 120.0)


func _ack(manager: Node, respawn_ticks: Variant) -> void:
	_ack_tick += 1
	var data: Dictionary = {"seq": 1, "tick": _ack_tick, "x": 0.0, "z": 0.0, "yaw": 0.0}
	if respawn_ticks != null:
		data["respawn_ticks"] = respawn_ticks
	manager.call("_on_ack_received", data)


func _pawn(id: String, display: String, at: Vector3) -> Node3D:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	pawn.set("player_id", id)
	pawn.set("player_name", display)
	pawn.set("hp", 100)
	root.add_child(pawn)
	pawn.global_position = at
	return pawn


func _key(action: String, pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _manager_sequences() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var network: CaptureNetwork = CaptureNetwork.new()
	manager.set("net_client", network)
	manager.set("is_human_player", true)
	manager.set("hud", hud)
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	root.add_child(camera)
	camera.set_process(false)
	manager.camera = camera
	var rival: Node3D = _pawn(RIVAL, "Rival", Vector3(20, 0, 0))
	camera.set_available_targets([rival])
	# Two consecutive lives, alternating which fact arrives first.
	for frag_first: bool in [true, false, true]:
		await _one_life(manager, network, camera, hud, rival, frag_first)
	manager.call("_reset_local_life")
	_check(not camera.death_view and not hud.death_card.visible, "leaving clears the death view and card")
	manager.free()
	network.free()
	camera.free()
	rival.free()
	hud.queue_free()
	await process_frame


func _one_life(manager: Node, network: CaptureNetwork, camera: Node3D, hud: CanvasLayer, rival: Node3D, frag_first: bool) -> void:
	var me: Node3D = _pawn(SELF, "Meat", Vector3(0, 0, 0))
	manager.players[SELF] = me
	camera.set_available_targets([rival, me])
	manager.call("_refresh_fp_target")
	_check(camera.fp_mode and camera.fp_target == me and manager.local_life.alive(), "joined body is in first person")
	Input.action_press("move_forward")
	Input.action_press("fire")
	_send(manager)
	var last: Dictionary = network.sent.back()
	_check(last.forward and last.fire, "held W and fire reach the live body")
	var sent_alive: int = network.sent.size()
	var frag: Dictionary = {"event": "frag", "killer": "Rival", "victim": "Meat", "killer_score": 1, "killer_id": RIVAL, "victim_id": SELF}
	if frag_first:
		manager.call("_on_event_received", frag)
		_check(not manager.local_life.alive(), "the frag fact ends the life at once")
		_send(manager)
		_check(network.sent.size() == sent_alive, "no input is sent for a dead life, even before the snapshot")
	# The death snapshot omits the body.
	manager.players.erase(SELF)
	me.free()
	camera.set_available_targets([rival])
	manager.call("_update_local_fp_hud", [])
	if not frag_first:
		manager.call("_on_event_received", frag)
	_check(not camera.fp_mode and camera.death_view, "death leaves first person for the death view")
	_check(camera.death_chase_id == RIVAL, "the killer is chased in either fact order")
	# Held W and a deflected stick never fly the dead camera.
	var held_at: Vector3 = camera.global_position
	camera.stick_source = func(_right: bool) -> Vector2: return Vector2(0.0, -1.0)
	camera.death_chase_id = ""
	for i in range(30):
		camera._process(1.0 / 30.0)
	_check(camera.global_position.is_equal_approx(held_at), "held W and stick are not free flight while down")
	camera.death_chase_id = RIVAL
	for i in range(60):
		camera._process(1.0 / 30.0)
	var chase: Vector3 = rival.global_position + Vector3(0, 5.5, 10.5)
	_check(camera.global_position.distance_to(chase) < 1.0, "the death view chases the killer, labelled")
	_check(camera.get_followed_target() == rival and not camera.is_observing_first_person(), "the death view never takes another fighter's eyes")
	camera.stick_source = LookInput.read_stick
	# Killer disconnects: the view holds where it is.
	camera.set_available_targets([])
	var at_disconnect: Vector3 = camera.global_position
	camera._process(0.5)
	_check(camera.global_position.is_equal_approx(at_disconnect) and camera.get_followed_target() == null, "a vanished killer leaves a held view")
	camera.set_available_targets([rival])
	# The server says how long; the card says it.
	_ack(manager, 60)
	_send(manager)
	_check(manager.local_life.phase == LocalLife.Phase.AWAITING, "the countdown Ack moves down to awaiting")
	_check(hud.death_card.visible and hud.death_card.headline() == "FRAGGED BY Rival", "death card names the killer: " + hud.death_card.headline())
	_check(hud.death_card.detail() == "WATCHING Rival" and hud.death_card.timing() == "RESPAWN IN 3", "death card labels view and server countdown: %s / %s" % [hud.death_card.detail(), hud.death_card.timing()])
	_check(hud.death_card.loss() == "", "a life that found nothing loses nothing")
	# A free-for-all life that took the Railgun loses it: the private loadout
	# still names it while down, the rules name the kit the next life gets.
	network.equipment = {"weapons": ["fists", "tack", "rail"], "selected": "rail"}
	hud.set_match_rules(MatchRules.parse({"mode": "ffa", "start_kit": ["fists", "tack"]}), false)
	manager.call("_update_death_presentation", Time.get_ticks_usec())
	_check(hud.death_card.loss() == "LOST RAILGUN", "the death card names what death cost: " + hud.death_card.loss())
	_check(hud.death_card.plate_rect().size.y > 0.0, "the loss line sits inside the plate")
	network.equipment = {}
	hud.set_match_rules({}, false)
	manager.call("_update_death_presentation", Time.get_ticks_usec())
	_check(hud.death_card.loss() == "", "no kit named, no loss line")
	# Presses while down are dropped, not queued.
	manager.call("_input", _key("jump", true))
	manager.call("_input", _key("interact", true))
	manager.call("_input", _key("fire", true))
	_check(not manager.pending_jump and not manager.pending_interact and not manager.pending_fire, "presses while down are not queued")
	_check(network.sent.size() == sent_alive, "still nothing sent while down")
	# Respawn with W and fire still held.
	var back: Node3D = _pawn(SELF, "Meat", Vector3(-8, 0, 4))
	back.set("target_yaw", 1.25)
	manager.players[SELF] = back
	camera.set_available_targets([rival, back])
	manager.call("_refresh_fp_target")
	_check(manager.local_life.alive() and camera.fp_mode and not camera.death_view, "the returned body ends the death view")
	_check(is_equal_approx(camera.fp_yaw, 1.25) and camera.global_position.distance_to(back.global_position) < 2.0, "the new life adopts the server body and facing, no interpolation")
	_check(not hud.death_card.visible, "the death card leaves with the death")
	_send(manager)
	last = network.sent.back()
	_check(last.forward, "held movement resumes from the live key state")
	_check(not last.fire, "a trigger held through death does not fire the new life")
	_check(not last.jump and not last.get("interact", false), "presses made while down did not ride into the new life")
	Input.action_release("fire")
	manager.call("_input", _key("fire", false))
	_send(manager)
	_check(not network.sent.back().fire, "release sends no shot")
	Input.action_press("fire")
	manager.call("_input", _key("fire", true))
	_send(manager)
	_check(network.sent.back().fire, "a fresh press fires")
	Input.action_release("move_forward")
	Input.action_release("fire")
	manager.call("_input", _key("fire", false))
	_send(manager)
	manager.players.erase(SELF)
	manager.call("_clear_fp_state")
	manager.call("_reset_local_life")
	back.free()
	await process_frame


func _row(id: String, team: String, at: Vector3) -> Dictionary:
	return {"id": id, "team": team, "x": at.x, "y": at.y, "z": at.z, "hp": 100}


## #510: a fallen fighter in a respawning team mode watches the killer for a
## beat, then rides the eyes of the living teammate nearest where they fell,
## cycles living teammates only, never flies free, reads the teammate's
## vitals, and gets their own eyes back with the body. Free-for-all keeps
## the killer view.
func _team_seat() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var network: CaptureNetwork = CaptureNetwork.new()
	manager.set("net_client", network)
	manager.set("is_human_player", true)
	manager.set("hud", hud)
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	root.add_child(camera)
	camera.set_process(false)
	manager.camera = camera
	hud.set_match_rules(MatchRules.parse({"mode": "tdm"}), false)
	var rival: Node3D = _pawn(RIVAL, "Rival", Vector3(20, 0, 0))
	rival.set("team", "union")
	var near: Node3D = _pawn(MATE_NEAR, "Near", Vector3(4, 0, 2))
	near.set("team", "coalition")
	near.set("hp", 37)
	near.set("armor", 25)
	var far: Node3D = _pawn(MATE_FAR, "Far", Vector3(-40, 0, -30))
	far.set("team", "coalition")
	var me: Node3D = _pawn(SELF, "Meat", Vector3(0, 0, 0))
	me.set("team", "coalition")
	manager.players[SELF] = me
	var living: Array = [far, rival, near, me]
	var rows: Array = [_row(MATE_FAR, "coalition", far.global_position), _row(RIVAL, "union", rival.global_position),
		_row(MATE_NEAR, "coalition", near.global_position), _row(SELF, "coalition", Vector3.ZERO)]
	camera.set_available_targets(manager.call("_watch_targets", living, rows, "Active"))
	manager.call("_refresh_fp_target")
	_check(camera.available_targets.size() == 4 and not manager.get("_team_seat"), "a living fighter's camera is unrestricted")
	# Fragged: the body leaves the snapshot and the killer is chased first.
	manager.call("_on_event_received", {"event": "frag", "killer": "Rival", "victim": "Meat", "killer_score": 1, "killer_id": RIVAL, "victim_id": SELF})
	manager.players.erase(SELF)
	me.free()
	var down: Array = [far, rival, near]
	rows.pop_back()
	manager.call("_update_local_fp_hud", rows)
	var shown: Array = manager.call("_watch_targets", down, rows, "Active")
	camera.set_available_targets(shown)
	_check(camera.death_view and camera.death_chase_id == RIVAL and shown.size() == 3, "the killer is shown first")
	# The beat passes: the seat moves into the nearest teammate's eyes.
	manager.set("_seat_down_usec", Time.get_ticks_usec() - 2000000)
	shown = manager.call("_watch_targets", down, rows, "Active")
	camera.set_available_targets(shown)
	var pick: Node3D = manager.get("_seat_pick")
	camera.follow_target_index = camera.available_targets.find(pick)
	manager.call("_present_seat_hud")
	_check(manager.get("_team_seat") and not camera.death_view and camera.seat_locked, "after the beat the death is a seat")
	_check(shown.size() == 2 and not shown.has(rival), "the seat follows living teammates only: %s" % [shown])
	_check(camera.get_followed_target() == near and camera.is_observing_first_person(), "the seat starts in the nearest teammate's eyes")
	camera._follow_target(1.0 / 60.0)
	_check(camera.global_position.distance_to(near.global_position) < 2.0, "the camera is at the teammate's eye")
	_ack(manager, 60)
	manager.call("_update_death_presentation", Time.get_ticks_usec())
	_check(hud.death_card.detail().begins_with("WATCHING Near") and hud.death_card.detail().contains("NEXT TEAMMATE"), "the card names the seat and how to move it: " + hud.death_card.detail())
	_check(hud.death_card.seated(), "a seated card sits low, out of the teammate's aim")
	_check(hud.fp_juice_enabled, "the teammate's gun is in hand")
	camera.cycle_next_target()
	_check(camera.get_followed_target() == far, "F moves to the next living teammate")
	camera.cycle_next_target()
	_check(camera.get_followed_target() == near, "and wraps among teammates, never the enemy")
	camera.toggle_follow_mode()
	_check(camera.follow_mode and not camera.spectator_first_person, "V trades the eyes for the chase view")
	camera.toggle_follow_mode()
	_check(camera.follow_mode and camera.spectator_first_person, "and never into a free camera")
	# The last teammate falls: nothing to watch, and still no free flight.
	camera.set_available_targets(manager.call("_watch_targets", [rival], [_row(RIVAL, "union", rival.global_position)], "Active"))
	_check(camera.available_targets.is_empty() and camera.seat_locked, "no living teammate leaves an empty seat, not the enemy")
	var held: Vector3 = camera.global_position
	camera.stick_source = func(_right: bool) -> Vector2: return Vector2(0.0, -1.0)
	for i in range(20):
		camera._process(1.0 / 30.0)
	camera.stick_source = LookInput.read_stick
	_check(camera.global_position.is_equal_approx(held), "a seat with nobody to watch holds still")
	# The body returns: own eyes, the seat ends.
	var back: Node3D = _pawn(SELF, "Meat", Vector3(-8, 0, 4))
	back.set("team", "coalition")
	manager.players[SELF] = back
	rows = [_row(SELF, "coalition", back.global_position), _row(RIVAL, "union", rival.global_position)]
	camera.set_available_targets(manager.call("_watch_targets", [rival, back], rows, "Active"))
	manager.call("_refresh_fp_target")
	_check(not manager.get("_team_seat") and not camera.seat_locked and camera.fp_mode and camera.fp_target == back, "the returned body ends the seat")
	_check(not hud.death_card.visible, "and the card with it")
	manager.players.erase(SELF)
	manager.call("_clear_fp_state")
	manager.call("_reset_local_life")
	# Free-for-all keeps the killer view and never takes a seat.
	hud.set_match_rules(MatchRules.parse({"mode": "ffa"}), false)
	var solo: Node3D = _pawn(SELF, "Meat", Vector3.ZERO)
	manager.players[SELF] = solo
	manager.call("_refresh_fp_target")
	manager.call("_on_event_received", {"event": "frag", "killer": "Rival", "victim": "Meat", "killer_score": 1, "killer_id": RIVAL, "victim_id": SELF})
	manager.players.erase(SELF)
	solo.free()
	manager.call("_update_local_fp_hud", [_row(RIVAL, "", rival.global_position)])
	manager.set("_seat_down_usec", Time.get_ticks_usec() - 5000000)
	var ffa: Array = manager.call("_watch_targets", [rival, near], [_row(RIVAL, "", rival.global_position)], "Active")
	_check(ffa.size() == 2 and camera.death_view and camera.death_chase_id == RIVAL and not manager.get("_team_seat"), "free-for-all still chases the killer")
	manager.call("_reset_local_life")
	manager.free()
	network.free()
	camera.free()
	for pawn: Node in [rival, near, far, back]:
		pawn.free()
	hud.queue_free()
	await process_frame


## #510: the clutch card stamps two upright lines for each viewer and retires.
func _clutch_card() -> void:
	var state: Dictionary = {"phase": "live", "round": 3, "alive": {"union": 1, "coalition": 3}, "clutch": SELF}
	_check(SabotageState.snapshot_error({"sabotage": {"format": "short", "phase": "live", "round": 1, "period": 0, "half": 1, "half_rounds": 4, "rounds_to_win": 5,
		"score": {"union": 0, "coalition": 0}, "alive": {"union": 1, "coalition": 3}, "clock_ticks": 10, "clutch": "", "resupply": {"union": 0, "coalition": 0}}}) == "invalid sabotage clutch", "an empty clutch id is refused")
	_check(SabotageState.snapshot_error({"sabotage": {"format": "short", "phase": "live", "round": 1, "period": 0, "half": 1, "half_rounds": 4, "rounds_to_win": 5,
		"score": {"union": 0, "coalition": 0}, "alive": {"union": 1, "coalition": 3}, "clock_ticks": 10, "resupply": {"union": 4, "coalition": 0}}}) == "invalid sabotage resupply", "a rung past the ladder is refused")
	var own: PackedStringArray = SabotageState.clutch_lines(state, SELF, "union", "Meat", "union")
	_check(own == PackedStringArray(["LAST ONE STANDING", "1 V 3"]), "the clutch fighter's own stamp: %s" % [own])
	var mate: PackedStringArray = SabotageState.clutch_lines(state, RIVAL, "union", "Meat", "union")
	_check(mate[0] == "MEAT IS THE LAST ONE" and mate[1] == "1 V 3", "a teammate's stamp: %s" % [mate])
	var foe: PackedStringArray = SabotageState.clutch_lines(state, RIVAL, "coalition", "Meat", "union")
	_check(foe[0] == "ONE LEFT: MEAT" and foe[1] == "3 V 1", "the other side's stamp: %s" % [foe])
	var muster: Dictionary = {"phase": "muster", "resupply": {"union": 0, "coalition": 2}}
	var spares: PackedStringArray = SabotageState.resupply_lines(muster, "coalition")
	_check(spares.size() == 1 and spares[0] == "SPARES 2/3: RIFLE + HALF ARMOR", "the free side hears its spares: %s" % [spares])
	_check(SabotageState.resupply_lines(muster, "union").is_empty(), "the Union hears nothing it was not issued")
	_check(SabotageState.resupply_lines({"phase": "live", "resupply": {"union": 0, "coalition": 2}}, "coalition").is_empty(), "the call belongs to the muster")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	# The muster call survives a round start that clears the lane after it.
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.set("hud", hud)
	var call_state: Dictionary = {"phase": "muster", "round": 2, "resupply": {"union": 1, "coalition": 0}}
	manager.call("_present_sabotage_moments", call_state, "")
	_check(hud.objective_call.notices.pending.size() == 1, "the resupply call is queued")
	hud.objective_call.clear()
	manager.call("_present_sabotage_moments", call_state, "")
	manager.call("_present_sabotage_moments", call_state, "")
	_check(hud.objective_call.notices.pending.size() == 1, "a cleared call is queued again, once")
	hud.objective_call.notices.advance(0.1)
	manager.call("_present_sabotage_moments", call_state, "")
	_check(int(manager.get("_sabotage_resupply_round")) != 2, "a call just shown can still be cleared")
	hud.objective_call.notices.advance(1.0)
	manager.call("_present_sabotage_moments", call_state, "")
	_check(int(manager.get("_sabotage_resupply_round")) == 2, "a call read for a second is done for its round")
	_check(str(hud.objective_call.notices.active[0].payload.text).begins_with("REPLACEMENT ISSUE 1/3"), "the Union files a replacement issue")
	manager.free()
	for reduced: bool in [false, true]:
		hud.reduced_motion = reduced
		hud.show_clutch(own, "union")
		await process_frame
		var card: ClutchCard = hud.clutch_card
		_check(card.visible and card.stamped() and card.title() == "LAST ONE STANDING", "the clutch is stamped")
		for label: Node in card.find_children("*", "Label", true, false):
			_check(is_zero_approx((label as Label).rotation) and (label as Label).scale == Vector2.ONE, "clutch text stays upright")
		var view: Rect2 = hud.get_viewport().get_visible_rect()
		var rect: Rect2 = card.card_rect()
		_check(rect.size.y < 200.0 and rect.end.y < card.size.y * 0.45, "the clutch sits above the aim point: %s in %s" % [rect, card.size])
		card._process(ClutchCard.HOLD_SECONDS + 0.1)
		_check(not card.visible and not card.stamped(), "the clutch stamp retires")
	hud.queue_free()
	await process_frame


func _stamp_residue() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	var stamp: StampCard = hud.stamp_card
	for reduced: bool in [false, true]:
		hud.reduced_motion = reduced
		for round_number in range(3):
			hud.show_round_end("Rival", "frag limit", 10)
			await process_frame
			_check(stamp.visible and stamp.target_label == hud.round_message, "a result card is stamped")
			# The banner expires.
			hud._process(6.0)
			await process_frame
			_check(not hud.round_message.visible, "the result banner expires")
			_check(not stamp.visible and stamp.target_label == null, "the stamp retires with its banner (round %d)" % round_number)
			_check(is_zero_approx(hud.round_message.rotation) and hud.round_message.scale == Vector2.ONE, "the retired stamp leaves no transform")
			hud.show_round_end("Rival", "frag limit", 10)
			hud.show_round_start(round_number + 2)
			_check(not stamp.visible, "a following unstamped banner retires the stamp at once")
			hud._process(2.0)
			# Death and respawn after a result never revive it.
			hud.set_fp_juice(false)
			hud.show_death_card(PackedStringArray(["FRAGGED BY Rival", "WATCHING Rival", "RESPAWN IN 3"]))
			hud.hide_death_card()
			hud.set_fp_juice(true)
			await process_frame
			_check(not stamp.visible and not hud.death_card.visible, "no stamp or death card after respawn")
	# A death during a result card: both stay readable, neither covers the other.
	hud.show_round_end("Rival", "frag limit", 10)
	hud.show_death_card(PackedStringArray(["FRAGGED BY A VERY LONG CALLSIGN INDEED", "WATCHING A VERY LONG CALLSIGN INDEED", "RESPAWN IN 3"]))
	await process_frame
	await process_frame
	var view: Rect2 = hud.get_viewport().get_visible_rect()
	var plate: Rect2 = hud.death_card.plate_rect()
	_check(view.encloses(plate) and plate.size.y > 0.0, "the death card stays on screen: %s in %s" % [plate, view])
	_check(not plate.intersects(hud.round_message.get_global_rect()), "the death card never covers the result card: %s vs %s" % [plate, hud.round_message.get_global_rect()])
	hud.hide_death_card()
	hud.show_episode_fail("HOST: fail")
	_check(stamp.visible, "episode fail is still stamped")
	hud.round_message.visible = false
	await process_frame
	_check(not stamp.visible, "hiding the episode card retires its stamp")
	hud.queue_free()
	await process_frame
