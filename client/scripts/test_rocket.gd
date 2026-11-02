extends SceneTree

const OWNER: String = "00000000-0000-4000-8000-0000000000aa"
var _failures: int = 0

class NetworkProbe extends Node:
	var player_id: String = OWNER

class HudProbe extends Node:
	var launches: int = 0
	func show_fire_juice(weapon: String) -> void:
		if weapon == "Rocket": launches += 1

class CameraProbe extends Node:
	var target: Node
	var first_person: bool = true
	func get_followed_target() -> Node:
		return target
	func is_observing_first_person() -> bool:
		return first_person

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_rocket: " + message)

func _flight(id: int, age: int, velocity: Array) -> Dictionary:
	return {"id": id, "owner_id": OWNER, "position": [1.0, 1.6, 0.0], "velocity": velocity, "age_ticks": age}

func _snapshot(rockets: Array, tick: int = 4) -> Dictionary:
	return {"tick": tick, "players": [{"id": OWNER}], "rockets": rockets}

func _run() -> void:
	_check(preload("res://scripts/net_client.gd").GAMEPLAY_VERSION >= 49, "the client speaks the current gameplay contract including Rocket and connected Launch Authority")
	var flying: Dictionary = _snapshot([_flight(7, 0, [18.0, 0.0, 0.0])])
	_check(RocketFacts.validation_error(flying).is_empty(), "a fresh rocket in flight is accepted")
	var orphan: Dictionary = _snapshot([_flight(7, 43, [-17.6, 2.0, -3.1])], 875)
	orphan["players"] = []
	_check(RocketFacts.validation_error(orphan).is_empty(), "a rocket stays in flight after its owner dies")
	for patch: Dictionary in [{"id": 0}, {"owner_id": "00000000-0000-0000-0000-000000000000"}, {"age_ticks": 80}, {"velocity": [21.0, 0.0, 0.0]}, {"position": [1025.0, 0.0, 0.0]}, {"extra": true}]:
		var bad: Dictionary = _snapshot([_flight(7, 0, [18.0, 0.0, 0.0])])
		bad["rockets"][0].merge(patch, true)
		_check(not RocketFacts.validation_error(bad).is_empty(), "malformed rocket refused: " + str(patch))
	var shared: Dictionary = _snapshot([_flight(7, 0, [18.0, 0.0, 0.0])])
	shared["grenades"] = [{"id": 7, "owner_id": OWNER, "position": [0, 0, 0], "fuse_ticks": 10, "bounce_count": 0}]
	_check(not RocketFacts.validation_error(shared).is_empty(), "a rocket cannot reuse another device id")
	var crowd: Array = []
	for index: int in range(1, 10):
		crowd.append(_flight(index, 0, [18.0, 0.0, 0.0]))
	_check(not RocketFacts.validation_error(_snapshot(crowd)).is_empty(), "one owner cannot have a ninth live rocket")
	var effects: GrenadeEffects = GrenadeEffects.new()
	root.add_child(effects)
	effects.apply(flying, Vector3.ZERO)
	var body: Node3D = effects.rockets[7]
	var hull: MeshInstance3D = body.get_node("Body") as MeshInstance3D
	var shape: CylinderMesh = hull.mesh as CylinderMesh
	_check(shape.height > shape.top_radius * 4.0 and body.get_node_or_null("Nose") != null
		and body.get_node_or_null("Flame") != null, "the rocket is a long modelled round with a nose and a flame")
	_check((-body.basis.z).dot(Vector3.RIGHT) > 0.9, "the long axis follows server velocity")
	effects._process(0.05)
	_check(body.position.x > 1.0 + 18.0 * 0.04 and body.position.x < 1.0 + 18.0 * GrenadeEffects.ROCKET_LEAD_SECONDS + 0.01,
		"between snapshots the round flies on along its server velocity, bounded")
	_check(effects.blast.smoke.active_count() > 0, "a rocket in flight lays smoke behind it")
	effects._process(1.0)
	_check(body.position.x <= 1.0 + 18.0 * GrenadeEffects.ROCKET_LEAD_SECONDS + 0.01, "a late snapshot never carries the round past its lead")
	var gone: Dictionary = flying.duplicate(true)
	gone["tick"] = 5
	gone["rockets"] = []
	effects.apply(gone, Vector3.ZERO)
	_check(effects.rockets.is_empty(), "a resolved rocket leaves the flight mesh")
	effects.reset()
	effects.free()
	var hud: EquipmentHud = EquipmentHud.new()
	root.add_child(hud)
	hud.apply({"tick": 1, "selected": "rocket", "weapons": ["fists", "rocket"], "ammo": [{"pool": "rockets", "rounds": 4}], "loaded": [{"weapon": "rocket", "rounds": 1}], "grenades": 0, "dry_fire_count": 0})
	_check(hud.glyph_pool == "rockets" and hud.counts.text == "1|3", "the held launcher draws its rocket count")
	hud.free()
	_check_reload_motion()
	await _check_launch_audio()
	print("test_rocket: %s" % ("PASS" if _failures == 0 else "FAIL %d" % _failures))
	quit(0 if _failures == 0 else 1)

func _check_reload_motion() -> void:
	var motion := WeaponArt.ReloadMotion.new()
	var loadout: Dictionary = {"selected":"rocket", "loaded":[{"weapon":"rocket", "rounds":0, "ready_at":116}]}
	motion.update("Rocket", loadout, 100, 0.1, true)
	motion.update("Rocket", loadout, 106, 0.1, true)
	_check(motion.depth > 0.9, "an accepted pending reload lowers the actual held tube")
	motion.update("Rocket", loadout, 115, 0.1, true)
	_check(motion.depth < 0.1, "the tube returns toward aim as the received deadline approaches")
	motion.update("Rocket", loadout, 116, 0.1, true)
	_check(motion.depth == 0.0, "an expired reload cannot retain the lowered pose")
	for reason: String in ["cancelled", "swapped", "motion_off", "disconnected"]:
		motion.update("Rocket", loadout, 100, 0.1, true)
		motion.update("Rocket", loadout, 106, 0.1, true)
		var state: Dictionary = loadout.duplicate(true)
		if reason == "cancelled":
			state["loaded"][0].erase("ready_at")
		if reason == "disconnected":
			state = {}
		motion.update("Rail" if reason == "swapped" else "Rocket", state, 107, 0.1, reason != "motion_off")
		_check(motion.depth == 0.0, reason + " clears the reload pose immediately")
		motion.clear()
	motion.update("Rocket", loadout, 100, 0.1, false)
	motion.update("Rocket", loadout, 106, 0.1, true)
	_check(motion.depth == 0.0, "reenabling motion cannot restart a reload observed while muted")
	loadout.loaded[0].ready_at = 136
	motion.update("Rocket", loadout, 120, 0.1, true)
	motion.update("Rocket", loadout, 126, 0.1, true)
	_check(motion.depth > 0.9, "a fresh accepted deadline can move after reenable")
	motion.clear()
	loadout.loaded[0].ready_at = 116
	# A late first observation uses the remaining received interval; a longer
	# future rule does not inherit today's sixteen-tick duration in this client.
	loadout["loaded"][0]["ready_at"] = 240
	motion.update("Rocket", loadout, 200, 0.1, true)
	motion.update("Rocket", loadout, 220, 0.1, true)
	_check(motion.depth > 0.9, "motion follows a received deadline without a fixed local reload duration")
	motion.clear()
	_check(motion.depth == 0.0, "hiding the held weapon clears retained motion")

func _check_launch_audio() -> void:
	var game: Node = load("res://scripts/game_manager.gd").new()
	var network: NetworkProbe = NetworkProbe.new()
	var hud_probe := HudProbe.new()
	var camera_probe := CameraProbe.new()
	var effects: GrenadeEffects = GrenadeEffects.new()
	var pawn: Node3D = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	root.add_child(pawn)
	root.add_child(effects)
	await process_frame
	var fire: AudioStreamPlayer3D = pawn.get_node("FireSound")
	game.net_client = network
	game.hud = hud_probe
	game.grenade_effects = effects
	game.players[OWNER] = pawn
	effects.apply(_snapshot([_flight(1, 0, [18.0, 0.0, 0.0])], 1), Vector3.INF)
	game._present_rocket_launches()
	_check(not fire.playing, "initial synchronization does not replay a Rocket launch")
	effects.apply(_snapshot([_flight(1, 1, [18.0, 0.0, 0.0]), _flight(2, 0, [18.0, 0.0, 0.0])], 2), Vector3.INF)
	game._present_rocket_launches()
	_check(fire.playing and fire.stream == pawn.fire_streams["Rocket"], "an accepted new projectile gives a spectator spatial launch sound")
	fire.stop()
	game._present_rocket_launches()
	effects.apply(_snapshot([_flight(2, 0, [18.0, 0.0, 0.0])], 2), Vector3.INF)
	game._present_rocket_launches()
	_check(not fire.playing, "draining and duplicate snapshots cannot replay the launch")
	effects.apply(_snapshot([_flight(2, 1, [18.0, 0.0, 0.0]), _flight(3, 2, [18.0, 0.0, 0.0])], 3), Vector3.INF)
	game._present_rocket_launches()
	_check(not fire.playing, "an older first-seen projectile is not a new launch")
	game.is_human_player = true
	var equipment: Dictionary = {"tick": 3, "selected": "rocket", "weapons": ["fists", "rocket"],
		"ammo": [{"pool": "rockets", "rounds": 2}], "loaded": [{"weapon": "rocket", "rounds": 1}]}
	_check(game.local_fire.sent({"seq": 1, "fire": true}, equipment, "rocket", 3, 1000000, true), "local Rocket cue obtains a prediction receipt")
	pawn.show_muzzle_flash("Rocket")
	fire.stop()
	game.local_fire.acknowledge(1, 4)
	effects.apply(_snapshot([_flight(4, 0, [18.0, 0.0, 0.0])], 4), Vector3.INF)
	game._present_rocket_launches()
	_check(not fire.playing and game.local_fire.confirmed_count == 1, "accepted local projectile confirms without doubling its predicted cue")
	_check(hud_probe.launches == 0, "the accepted local launch never doubles the predicted first-person cue")
	_check(not game.local_fire.reconcile(8), "confirmed Rocket is not cancelled as a denied ray shot")
	var invalid: Dictionary = _snapshot([_flight(5, 0, [21.0, 0.0, 0.0])], 5)
	effects.apply(invalid, Vector3.INF)
	game._present_rocket_launches()
	_check(not fire.playing, "invalid projectile facts cannot start a launch cue")
	effects.reset()
	effects.apply(_snapshot([_flight(6, 0, [18.0, 0.0, 0.0])], 6), Vector3.INF)
	game._present_rocket_launches()
	_check(not fire.playing, "map reset restores silent initial synchronization")
	effects.apply(_snapshot([_flight(7, 0, [18.0, 0.0, 0.0])], 7), Vector3.INF)
	game._present_rocket_launches()
	_check(hud_probe.launches == 1, "an unpredicted accepted local launch presents its first-person cue")
	game.is_human_player = false
	pawn.player_id = OWNER
	camera_probe.target = pawn
	game.camera = camera_probe
	effects.apply(_snapshot([_flight(8, 0, [18.0, 0.0, 0.0])], 8), Vector3.INF)
	game._present_rocket_launches()
	_check(hud_probe.launches == 2, "a followed first-person launch presents its own launcher cue")
	camera_probe.first_person = false
	effects.apply(_snapshot([_flight(9, 0, [18.0, 0.0, 0.0])], 9), Vector3.INF)
	game._present_rocket_launches()
	_check(hud_probe.launches == 2, "third-person observation does not flash a held launcher")
	effects.reset()
	effects.free()
	network.free()
	hud_probe.free()
	camera_probe.free()
	game.free()
	pawn.queue_free()
	await process_frame
