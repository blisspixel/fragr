extends SceneTree

var failures: Array[String] = []

class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: String = "self"
	var equipment: Dictionary = {}
	var mission: Dictionary = {}
	var last_send_ok: bool = false
	var fail_next: bool = false
	var sent: Array[Dictionary] = []
	func send_action(action: Dictionary) -> void:
		last_send_ok = not fail_next
		fail_next = false
		if last_send_ok:
			sent.append(action.duplicate(true))

class PawnProbe extends Node3D:
	var hp: int = 100
	var weapon: String = "Flechette"
	var fired: Array[String] = []
	var cancelled: int = 0
	func get_weapon_name() -> String:
		return weapon
	func show_muzzle_flash(value: String) -> void:
		fired.append(value)
	func cancel_fire_feedback() -> void:
		cancelled += 1
	func play_mounted_fire() -> void:
		fired.append("Mounted")

class CameraProbe extends Node3D:
	var fp_mode: bool = true
	var fp_target: Node = null
	func get_followed_target() -> Node:
		return fp_target
	func is_observing_first_person() -> bool:
		return true

class HudProbe extends Node:
	var fired: Array[String] = []
	var hits: Array[int] = []
	var cancelled: int = 0
	func show_fire_juice(weapon: String) -> void:
		fired.append(weapon)
	func show_hit_marker(damage: int, _weapon: String) -> void:
		hits.append(damage)
	func cancel_fire_juice() -> void:
		cancelled += 1

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func _equipment(weapon: String = "flechette", rounds: int = 20, tick: int = 100) -> Dictionary:
	return {"tick": tick, "selected": weapon, "weapons": ["fists", "shiv", "tack", "flechette", "scatter", "rail", "sniper", "repeater"],
		"ammo": [{"pool": "bullets", "rounds": 80}, {"pool": "shells", "rounds": 24}, {"pool": "cells", "rounds": 16}],
		"loaded": [{"weapon": weapon, "rounds": rounds}]}

func _action(seq: int, held: bool = true) -> Dictionary:
	return {"seq": seq, "fire": held}

func _shot(weapon: String = "flechette", damage: int = 20) -> Dictionary:
	return {"shooter_id": "self", "hit": damage > 0, "damage": damage,
		"trace": {"weapon": weapon, "origin": [0.0, 1.6, 0.0], "end": [4.0, 1.6, 0.0], "impact": {"kind": "range"}}}

func _cadence_and_inventory() -> void:
	var source: String = FileAccess.get_file_as_string("res://../server/src/protocol.rs")
	var cooldown: String = source.get_slice("pub fn cooldown_ticks(self) -> u32 {", 1).get_slice("///", 0)
	var mirror: RegEx = RegEx.new()
	_check(mirror.compile("WeaponType::([A-Za-z]+) => ([0-9]+),") == OK, "cadence regex compiles")
	var checked: int = 0
	for entry: RegExMatch in mirror.search_all(cooldown):
		_check(int(LocalFireFeedback.COOLDOWN_TICKS.get(entry.get_string(1).to_lower(), -1)) == int(entry.get_string(2)), "presentation cadence matches server " + entry.get_string(1))
		checked += 1
	_check(checked == EquipmentState.WEAPONS.size(), "every weapon has a verified cadence")
	for weapon: String in EquipmentState.WEAPONS:
		var cue: LocalFireFeedback = LocalFireFeedback.new()
		var inventory: Dictionary = _equipment(weapon)
		var now: int = 1000000
		if weapon == "repeater":
			_check(not cue.sent(_action(1), inventory, weapon, 100, now, true), "Repeater does not skip warmup")
			now += LocalFireFeedback.WARMUP_USEC
		_check(cue.sent(_action(2), inventory, weapon, 100, now, true), weapon + " starts without server confirmation")
		var interval: int = int(LocalFireFeedback.COOLDOWN_TICKS[weapon]) * 50000
		_check(not cue.sent(_action(3), inventory, weapon, 100, now + interval - 1, true), weapon + " cannot outrun cadence")
		_check(cue.confirm(weapon, 101, now + 50000), weapon + " consumes one speculative cue")
		inventory["tick"] = 101
		cue.observe_equipment(inventory)
		_check(cue.sent(_action(4), inventory, weapon, 101, now + interval, true), weapon + " held fire follows cadence")
		_check(inventory["loaded"][0]["rounds"] == 20, "prediction cannot modify inventory")
	var empty: LocalFireFeedback = LocalFireFeedback.new()
	_check(not empty.sent(_action(1), _equipment("flechette", 0), "flechette", 100, 0, true), "empty magazine stays silent")
	var loaded: Dictionary = _equipment("flechette", 1)
	_check(empty.sent(_action(2), loaded, "flechette", 100, 0, true), "last round predicts once")
	_check(not empty.sent(_action(3), loaded, "flechette", 100, 200000, true), "outstanding round reserves the last round")
	_check(empty.confirm("flechette", 101, 200000), "last round confirms")
	_check(not empty.sent(_action(4), loaded, "flechette", 101, 200001, true), "confirmation cannot release ammo before loadout")
	empty.observe_equipment(_equipment("flechette", 0, 101))
	_check(empty.pending.is_empty(), "loadout retires confirmed reservation")
	var reloading: Dictionary = _equipment()
	reloading["loaded"][0]["ready_at"] = 120
	_check(not empty.sent(_action(5), reloading, "flechette", 105, 500000, true), "known reload blocks local gun")
	var reload_action: Dictionary = _action(6)
	reload_action["reload"] = true
	_check(not empty.sent(reload_action, loaded, "flechette", 105, 500000, true), "reload input suppresses speculation before receipt")
	for key: String in ["throw_grenade", "place_mine"]:
		var suppressed: Dictionary = _action(7)
		suppressed[key] = true
		_check(not empty.sent(suppressed, loaded, "flechette", 105, 500000, true), key + " suppresses gun cue")
	_check(not empty.sent(_action(8), {}, "flechette", 105, 500000, true), "unknown inventory uses authoritative fallback")

func _reconciliation() -> void:
	var cue: LocalFireFeedback = LocalFireFeedback.new()
	var inventory: Dictionary = _equipment()
	_check(cue.sent(_action(10), inventory, "flechette", 100, 0, true), "first pending receipt")
	_check(not cue.confirm("rail", 101, 0), "another weapon cannot consume receipt")
	cue.acknowledge(9, 101)
	_check(not cue.reconcile(105) and cue.pending.size() == 1, "old ACK cannot reject new input")
	cue.acknowledge(10, 105)
	_check(not cue.reconcile(106), "rejection allows a following tick of cadence drift")
	# A fallback above became the latest visible shot; rejecting an older cue
	# must not cancel its remaining effect.
	_check(not cue.reconcile(107) and cue.rejected_count == 1, "old rejection cannot cancel newer authoritative effect")
	cue.reset()
	_check(cue.sent(_action(11), inventory, "flechette", 110, 0, true), "new receipt after reset")
	cue.acknowledge(11, 111)
	_check(cue.reconcile(113) and cue.pending.is_empty(), "applied action without a shot cancels remaining local cue")
	_check(not cue.reconcile(114), "rejection happens once")
	cue.reset()
	_check(cue.sent(_action(4294967295), inventory, "flechette", 120, 0, true), "last u32 action predicts")
	cue.acknowledge(1, 121)
	_check(cue.reconcile(123), "ACK retirement follows wrapped input sequence")
	cue.reset()
	_check(cue.sent(_action(1), inventory, "flechette", 100, 0, true), "bounded backlog first shot")
	_check(cue.sent(_action(2), inventory, "flechette", 100, 200000, true), "second outstanding shot")
	_check(cue.sent(_action(3), inventory, "flechette", 100, 400000, true), "third outstanding shot")
	_check(not cue.sent(_action(4), inventory, "flechette", 100, 600000, true), "stalled server stops speculative automatic fire")
	_check(cue.confirm("flechette", 101, 900000) and cue.confirm("flechette", 105, 900000) and cue.confirm("flechette", 109, 900000), "late confirmations each consume exactly one cue")
	cue.reset()
	_check(cue.pending.is_empty() and cue.next_fire_usec == 0, "new life drops old reservations and cadence")

func _switch_and_warmup() -> void:
	var cue: LocalFireFeedback = LocalFireFeedback.new()
	_check(cue.sent(_action(1), _equipment("rail"), "rail", 100, 0, true), "Rail starts shared cooldown")
	var switch: Dictionary = _action(2)
	switch["weapon_swap"] = "flechette"
	_check(not cue.sent(switch, _equipment("rail"), "rail", 100, 20000, true), "switch does not fire old weapon")
	_check(not cue.sent(_action(3), _equipment("rail"), "rail", 100, 1000000, true), "in-flight switch waits for selected weapon")
	cue.observe_equipment(_equipment("flechette", 20, 101))
	_check(not cue.sent(_action(4), _equipment(), "flechette", 101, 200000, true), "switch cannot erase Rail cooldown")
	_check(cue.confirm("rail", 101, 300000), "old weapon's late confirmation finds its own cue")
	cue.observe_equipment(_equipment("flechette", 20, 101))
	_check(cue.sent(_action(5), _equipment(), "flechette", 101, 1000000, true), "new weapon predicts when shared cooldown ends")
	cue.reset()
	var repeater: Dictionary = _equipment("repeater", 30)
	_check(not cue.sent(_action(1), repeater, "repeater", 100, 0, true), "Repeater begins warmup")
	_check(not cue.sent(_action(2), repeater, "repeater", 100, 299999, true), "Repeater waits six complete ticks")
	_check(not cue.sent(_action(3, false), repeater, "repeater", 100, 300000, true), "release cancels warmup")
	_check(not cue.sent(_action(4), repeater, "repeater", 100, 400000, true), "repress starts a fresh warmup")
	_check(not cue.sent(_action(5), repeater, "repeater", 100, 700000, false), "blocked controls cancel warmed gun")
	_check(not cue.sent(_action(6), repeater, "repeater", 100, 800000, true), "unblocked Repeater starts fresh")
	_check(cue.sent(_action(7), repeater, "repeater", 100, 1100000, true), "Repeater resumes after full warmup")

func _live_seams() -> void:
	var game: Node = load("res://scripts/game_manager.gd").new()
	var network: CaptureNetwork = CaptureNetwork.new()
	var pawn: PawnProbe = PawnProbe.new()
	var camera: CameraProbe = CameraProbe.new()
	var hud: HudProbe = HudProbe.new()
	game.net_client = network
	game.hud = hud
	game.camera = camera
	game.is_human_player = true
	game.local_fp_pawn_id = "self"
	game.players["self"] = pawn
	game.latest_snapshot = {"tick": 100, "round_state": "Active"}
	camera.fp_target = pawn
	network.equipment = _equipment()
	Input.action_press("fire")
	network.fail_next = true
	game._send_local_action(1000000)
	_check(hud.fired.is_empty() and pawn.fired.is_empty(), "failed actual send produces no feedback")
	game._send_local_action(1010000)
	_check(hud.fired == ["Flechette"] and pawn.fired == ["Flechette"] and hud.hits.is_empty(), "successful input gives immediate cue and no invented hit")
	game._process_shot_results([_shot()], 101)
	_check(hud.fired.size() == 1 and pawn.fired.size() == 1 and hud.hits == [20], "real confirmation gives one marker and no duplicate gun cue")
	game._process_shot_results([_shot()], 101)
	_check(hud.hits.size() == 1, "duplicate snapshot cannot duplicate marker")
	game.local_fire.observe_equipment(_equipment("flechette", 19, 101))
	game._send_local_action(1210000)
	_check(hud.fired.size() == 2, "actual automatic input continues at cadence")
	game.local_fire.acknowledge(game.input_seq, 105)
	game._process_shot_results([], 107)
	_check(hud.cancelled == 1 and pawn.cancelled == 1 and hud.hits.size() == 1, "real rejection cancels gun only")
	game._reset_local_fire()
	for phase: String in ["Warmup", "Ended"]:
		game.latest_snapshot["round_state"] = phase
		game._send_local_action(1400000 if phase == "Warmup" else 1600000)
	_check(hud.fired.size() == 2, "warmup and ended rounds cannot predict")
	game.latest_snapshot["round_state"] = "Active"
	game.latest_snapshot["sabotage"] = {"phase": "muster"}
	game._send_local_action(1800000)
	_check(hud.fired.size() == 2, "Sabotage muster cannot predict")
	game.latest_snapshot.erase("sabotage")
	pawn.hp = 0
	game._send_local_action(2000000)
	_check(hud.fired.size() == 2, "dead local fighter cannot predict")
	pawn.hp = 100
	game._send_local_action(2200000)
	_check(hud.fired.size() == 3, "new life can fire after reset")
	game._receiving_snapshot = true
	game._reset_local_fire()
	game._process_shot_results([_shot()], 110)
	_check(hud.fired.size() == 3 and hud.hits.size() == 2, "death snapshot consumes trade receipt before lifecycle reset")
	game._receiving_snapshot = false
	game._reset_local_fire()
	game.is_human_player = false
	game._process_shot_results([_shot()], 111)
	_check(pawn.fired.size() == 4, "spectator world shot stays authoritative")
	Input.action_release("fire")
	game.is_human_player = true
	game._reset_local_fire()
	var press: InputEventAction = InputEventAction.new()
	press.action = "fire"
	press.pressed = true
	game._input(press)
	press.pressed = false
	game._input(press)
	network.fail_next = true
	game._send_local_action(2400000)
	_check(game.pending_fire, "failed send retains a sub-frame trigger tap")
	game._send_local_action(2410000)
	_check(not game.pending_fire and pawn.fired.size() == 5, "sub-frame trigger tap produces one cue on successful send")
	game._send_local_action(2420000)
	_check(not network.sent.back()["fire"] and pawn.fired.size() == 5, "sub-frame trigger does not remain held")
	game.latest_snapshot["vehicles"] = [{"id": 1, "driver": "self", "gunner": null}]
	Input.action_press("fire")
	Input.action_press("throw_grenade")
	game.pending_seat = "gunner"
	game._send_local_action(2500000)
	_check(not network.sent.back()["fire"] and not network.sent.back()["throw_grenade"] and network.sent.back()["seat"] == "gunner", "driver input suppresses handheld and sends existing seat action")
	_check(pawn.fired.size() == 5, "driver input has no invented mounted cue")
	game.latest_snapshot["vehicles"][0]["driver"] = null
	game.latest_snapshot["vehicles"][0]["gunner"] = "self"
	game._send_local_action(2600000)
	_check(network.sent.back()["fire"] and not network.sent.back().has("seat"), "gunner fire uses ordinary action and seat request is one shot")
	_check(pawn.fired.size() == 5, "gunner waits for authoritative mounted result")
	var mounted: Dictionary = _shot()
	mounted["trace"]["vehicle_id"] = 1
	game._process_shot_results([mounted], 120)
	_check(pawn.fired.back() == "Mounted" and hud.fired.size() == 4, "resolved mounted fire has mounted audio without handheld viewmodel")
	Input.action_release("fire")
	Input.action_release("throw_grenade")
	game.free()
	network.free()
	pawn.free()
	camera.free()
	hud.free()

func _run() -> void:
	root.set_meta("fragr_automated", true)
	root.set_meta("fragr_settings_path", "user://test_local_fire_feedback_settings.cfg")
	if DisplayServer.get_name() != "headless":
		await _rendered_sequence()
		_finish()
		return
	_cadence_and_inventory()
	_reconciliation()
	_switch_and_warmup()
	_live_seams()
	_finish()

func _finish() -> void:
	for failure: String in failures:
		push_error("test_local_fire_feedback: " + failure)
	if failures.is_empty():
		print("test_local_fire_feedback: PASS cadence, input latency, ammunition, ACK reconciliation, switches, warmup, lifecycle and authority")
	quit(0 if failures.is_empty() else 1)

## Real HUD and pawn presentation with a held-back server confirmation. The
## seam is driven with synthetic wire facts; this is not a network latency test.
func _rendered_sequence() -> void:
	root.size = Vector2i(960, 540)
	var packed: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = packed.get_node("HUD")
	var arena: Node3D = packed.get_node("Arena")
	packed.remove_child(hud)
	packed.remove_child(arena)
	packed.free()
	root.add_child(arena)
	root.add_child(hud)
	var eye: Camera3D = Camera3D.new()
	root.add_child(eye)
	eye.position = Vector3(0.0, 2.2, 7.0)
	eye.look_at(Vector3(0.0, 1.8, -4.0))
	eye.current = true
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	pawn.current_weapon = "Flechette"
	pawn.position = eye.position
	pawn.set_local_fp(true)
	var network: CaptureNetwork = CaptureNetwork.new()
	network.equipment = _equipment()
	var camera: CameraProbe = CameraProbe.new()
	camera.fp_target = pawn
	var game: Node = load("res://scripts/game_manager.gd").new()
	game.net_client = network
	game.hud = hud
	game.camera = camera
	game.is_human_player = true
	game.local_fp_pawn_id = "self"
	game.players["self"] = pawn
	game.latest_snapshot = {"tick": 100, "round_state": "Active"}
	hud.set_fp_juice(true)
	hud.set_fp_weapon("Flechette")
	hud.set_vitals(100, 0)
	hud.set_mode("PLAYING")
	hud.set_status("Local fire feedback check")
	hud.set_round_info("Active", 30, 10)
	hud.set_followed_weapon("Flechette", "Nick Seal", "")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/local-fire-rendered").simplify_path()
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "prepare rendered evidence directory")
	await process_frame
	await _save_frame(directory.path_join("01-idle.png"))
	# PNG encoding can consume the next frame's delta. Hold presentation time
	# at the input edge while the transient is captured, then resume real time.
	hud.set_process(false)
	Input.action_press("fire")
	game._send_local_action(Time.get_ticks_usec())
	Input.action_release("fire")
	_check(game.local_fire.predicted_count == 1 and hud.fp_shot_age == 0.0,
		"actual gun begins in input frame before any result")
	_check(pawn.fire_sound.playing and hud.hit_marker_timer == 0.0,
		"actual local sound starts without invented hit marker")
	hud._process(0.0)
	await _save_frame(directory.path_join("02-predicted.png"))
	hud.set_process(true)
	await create_timer(0.3).timeout
	await _save_frame(directory.path_join("03-awaiting-server.png"))
	var settled_age: float = hud.fp_shot_age
	game._process_shot_results([_shot()], 101)
	_check(game.local_fire.confirmed_count == 1 and hud.fp_shot_age >= settled_age,
		"late actual confirmation leaves the settled gun alone")
	_check(hud.hit_marker_timer > 0.0, "actual hit marker waits for server damage")
	await _save_frame(directory.path_join("04-confirmed.png"))
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "rendered automation never captures the desktop pointer")
	print("test_local_fire_feedback: rendered evidence " + directory)
	game.free()
	network.free()
	camera.free()
	pawn.queue_free()
	hud.queue_free()
	arena.queue_free()
	eye.queue_free()
	await process_frame
	await create_timer(0.15).timeout

func _save_frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(path)
	_check(result == OK, "write rendered frame %s (status %d)" % [path.get_file(), result])
