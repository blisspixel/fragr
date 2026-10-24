extends SceneTree
## #441 death lifecycle and #437 result-stamp residue. Drives the real game
## manager, camera and HUD through death, the server countdown and respawn
## with movement and the trigger held, in both event orders, and repeats it.

const LocalLifeScript = preload("res://scripts/local_life.gd")
const SELF: String = "00000000-0000-4000-8000-000000000001"
const RIVAL: String = "00000000-0000-4000-8000-000000000002"

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
	await _stamp_residue()
	Input.action_release("move_forward")
	Input.action_release("fire")
	if _failures == 0:
		print("test_death_lifecycle: PASS life phases, countdown, input fence, death view, respawn, stamp retire")
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
