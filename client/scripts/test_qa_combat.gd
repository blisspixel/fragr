extends SceneTree

const TOUR = preload("res://scripts/qa_tour.gd")

var _failures: int = 0

func _initialize() -> void:
	var facing_route: Dictionary[String, bool] = QaCombat.route_buttons(Vector2(1, 0), PI * 0.5)
	_check(facing_route["move_left"] and not facing_route["move_forward"] and not facing_route["move_right"],
		"turning toward a windup preserves the escape route through a strafe")
	var retreat_route: Dictionary[String, bool] = QaCombat.route_buttons(Vector2(-1, 0), 0.0)
	_check(retreat_route["move_back"] and not retreat_route["move_forward"],
		"retreating while watching the Crawler preserves the world-space course")
	var route_camera: Node3D = preload("res://scripts/spectator_cam.gd").new()
	var near_waypoint: Dictionary = {"x": 0.0, "y": 2.0, "z": 0.0}
	_check(QaCombat.follow_route(near_waypoint, route_camera, [[0.2, 0.5, 0.1]], 0,
		Vector3(-1.0, 0.4, 2.0)) == 1 and \
		is_equal_approx(float(route_camera.get("fp_yaw")), atan2(2.0, -1.0)) and \
		float(route_camera.get("fp_pitch")) < -0.1,
		"a first windup at a waypoint boundary still turns the live camera down toward the low body")
	route_camera.free()
	_check(QaCombat.valid_waypoints([[1, 2.0, 3]]), "finite route accepted")
	for invalid: Variant in [null, {}, [1, 2, 3], [[1, 2]], [[1, INF, 3]], [[1, "2", 3]]]:
		_check(not QaCombat.valid_waypoints(invalid), "invalid route rejected")
	var cadence: Dictionary = {"period_ticks": 24, "fire_ticks": 4, "duration_ticks": 160}
	_check(QaCombat.valid_fire_cadence(cadence), "bounded server-tick fire cadence accepted")
	var parsed_cadence: Variant = JSON.parse_string('{"period_ticks":24,"fire_ticks":4,"duration_ticks":160}')
	_check(QaCombat.valid_fire_cadence(parsed_cadence), "JSON numeric cadence accepted at the manifest boundary")
	for invalid: Variant in [null, {}, {"period_ticks": 24, "fire_ticks": 4},
		{"period_ticks": true, "fire_ticks": 4, "duration_ticks": 160},
		{"period_ticks": 24.5, "fire_ticks": 4, "duration_ticks": 160},
		{"period_ticks": 0, "fire_ticks": 4, "duration_ticks": 160},
		{"period_ticks": 24, "fire_ticks": 24, "duration_ticks": 160},
		{"period_ticks": 24, "fire_ticks": 4, "duration_ticks": 401},
		{"period_ticks": 24, "fire_ticks": 4, "duration_ticks": 160, "extra": 1}]:
		_check(not QaCombat.valid_fire_cadence(invalid), "invalid or unbounded fire cadence rejected")
	_check(QaCombat.cadence_allows_fire(cadence, 0) and QaCombat.cadence_allows_fire(cadence, 3)
		and not QaCombat.cadence_allows_fire(cadence, 4)
		and QaCombat.cadence_allows_fire(cadence, 24)
		and not QaCombat.cadence_allows_fire(cadence, 159)
		and QaCombat.cadence_allows_fire(cadence, 160),
		"fire pulses resume on server ticks and stop throttling after the bounded window")
	for invalid: Variant in [null, [], [1], [{"walk_to": [1, 2, 3]}]]:
		_check(not TOUR.valid_walks(invalid), "invalid manifest walking shape rejected before play")
	_check(not TOUR.valid_walks([{"camera":"overview", "camera_position":[0, INF, 0],
		"camera_look_at":[0, 0, 0]}]), "invalid spectator framing rejected before play")
	var pack_snapshot: Dictionary = {"players":[
		{"name":"crawler", "hp":20, "campaign":{"side":"union", "phase":"moving"}},
		{"name":"sweeper", "hp":0, "campaign":{"side":"union", "phase":"dead"}},
	]}
	_check(TOUR.active_named_enemies(pack_snapshot, ["crawler", "sweeper"]) == {"crawler":"moving"},
		"spectator proof counts only named living enemies")
	for filename: String in DirAccess.get_files_at("res://qa"):
		if filename.get_extension() != "json":
			continue
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/" + filename))
		_check(manifest is Dictionary and TOUR.valid_walks(manifest.get("states")), filename + " has valid walking routes")
		if manifest is Dictionary:
			for state: Variant in manifest.get("states", []):
				if state is Dictionary and state.get("combat") is Dictionary and state["combat"].has("fire_cadence"):
					_check(QaCombat.valid_fire_cadence(state["combat"]["fire_cadence"]),
						filename + " has a valid bounded fire cadence")
	var me: Dictionary = {"id":"player", "hp":100, "x":0.0, "y":1.5, "z":0.0, "campaign":{"side":"participant"}}
	var friend: Dictionary = me.duplicate(true)
	friend["id"] = "friend"
	friend["z"] = 1.0
	var guard: Dictionary = {"id":"guard", "hp":60, "x":0.0, "y":1.5, "z":5.0,
		"campaign":{"side":"union", "kind":"clerk", "phase":"windup"}}
	var latch: Dictionary = {"id":"latch", "name":"Latch", "hp":100, "x":0.0, "y":1.5, "z":2.0,
		"campaign":{"side":"companion", "kind":"latch", "phase":"following", "phase_started":0}}
	var snapshot: Dictionary = {"tick":1, "players":[me, friend, latch, guard]}
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") == "guard", "closer participant is never a target")
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") != "latch",
		"the nearby companion is never an automated combat target")
	_check(not QaCombat.visible_target(snapshot, "player", [], true).is_empty(), "visible windup permits evasive input")
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0).get("id") == "guard", "travel engages a nearby threat")
	guard["z"] = 34.0
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0).is_empty(), "travel continues past a distant sightline")
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") == "guard", "combat can still resolve a distant required guard")
	guard["z"] = 5.0
	var solid: Dictionary = {"min_x":-1.0, "max_x":1.0, "min_z":2.0, "max_z":3.0, "bottom":0.0, "top":3.0}
	_check(QaCombat.visible_target(snapshot, "player", [solid]).is_empty(), "wall prevents automated fire")
	_check(QaCombat.visible_target(snapshot, "player", [solid], true).is_empty(), "hidden windup cannot drive evasion")
	var low_cover: Dictionary = {"min_x":-1.0, "max_x":1.0, "min_z":3.0, "max_z":4.0, "bottom":0.0, "top":1.3}
	var exposed: Vector3 = QaCombat.exposed_point(guard, Vector3(0, 1.6, 0), [low_cover])
	_check(exposed.y > 1.3 and exposed.y < MoveStep.BODY_HEIGHT, "low cover permits an exposed upper-body shot within the real hit volume")
	_check(QaCombat.visible_target(snapshot, "player", [low_cover], true).get("id") == "guard", "visible upper-body tell permits evasion")
	guard["campaign"]["kind"] = "crawler"
	guard["campaign"]["phase"] = "leaping"
	var crawler_point: Vector3 = QaCombat.exposed_point(guard, Vector3(0, 1.6, 0), [])
	_check(is_equal_approx(crawler_point.y, 0.4), "tour aims inside Crawler's short body")
	_check(QaCombat.visible_target(snapshot, "player", [low_cover]).is_empty(),
		"a waist-high counter hides the whole low Crawler")
	_check(QaCombat.visible_target(snapshot, "player", [], true).get("id") == "guard",
		"committed leap drives dodge input")
	_check(QaCombat.required_phases_proven({"crawler_windup":true, "crawler_leaping":true},
		{"crawler_windup":true, "crawler_leaping":true}, "crawler", ["windup", "leaping"]),
		"Crawler phase proof requires both observed and rendered states")
	_check(not QaCombat.required_phases_proven({"sweeper_windup":true, "crawler_leaping":true},
		{"sweeper_windup":true, "crawler_leaping":true}, "crawler", ["windup", "leaping"]),
		"mixed Union phase proof cannot borrow a Sweeper tell")
	var windup_identity: Dictionary = {"kind":"crawler", "phase":"windup", "phase_started":10}
	_check(not QaCombat.phase_ready_for_capture(windup_identity, 14) and \
		QaCombat.phase_ready_for_capture(windup_identity, 15),
		"named Crawler windup still waits for a rendered crouch within the twelve-tick tell")
	windup_identity["phase"] = "leaping"
	_check(QaCombat.phase_ready_for_capture(windup_identity, 10),
		"short leap phase remains eligible for immediate capture")
	guard["campaign"]["kind"] = "clerk"
	guard["campaign"]["phase"] = "windup"
	solid["bottom"] = 2.4
	_check(QaCombat.visible_target(snapshot, "player", [solid]).get("id") == "guard", "raised deck leaves a real underpass")
	guard["campaign"]["phase"] = "idle"
	_check(QaCombat.visible_target(snapshot, "player", [], true).is_empty(), "idle guard has no committed tell")
	guard["hp"] = 0
	guard["campaign"]["phase"] = "dead"
	_check(QaCombat.visible_target(snapshot, "player", []).is_empty(), "corpse is not a target")
	var probe: QaCombat = QaCombat.new()
	probe.set("_player_id", "player")
	probe.set("_kind", "clerk")
	probe.set("_recording", true)
	snapshot["shot_results"] = [{"shooter_id":"player"}, {"shooter_id":"friend"},
		{"shooter_id":"guard"}, {"shooter_id":"latch", "trace":{"weapon":"Tack"},
		"target_id":"guard", "target":"Clerk", "hit":true, "damage":6, "killed":false}]
	probe._observe(snapshot)
	probe._observe(snapshot)
	_check(probe.shots == 1 and probe.defeated.size() == 1, "repeated snapshot cannot inflate evidence")
	_check(probe.enemy_shots == 1, "a friend's shot cannot stand in for an enemy tell")
	_check(probe.companion_shots.size() == 1 and probe.companion_shots[0]["weapon"] == "Tack"
		and probe.companion_shots[0]["damage"] == 6 and probe.companion_shots[0]["target_id"] == "guard",
		"the ally's resolved shot is recorded separately from hostile fire and participant shots")
	var next_room: QaCombat = QaCombat.new()
	next_room.set("_player_id", "player")
	next_room.set("_kind", "union")
	next_room.set("_recording", true)
	var old_corpses: Dictionary[String, bool] = {"guard": true}
	next_room.set("_initial_dead", old_corpses)
	next_room._observe(snapshot)
	_check(next_room.defeated.is_empty(), "preceding room's corpse cannot satisfy a new encounter")
	var second: Dictionary = guard.duplicate(true)
	second["id"] = "second"
	second["campaign"]["kind"] = "sweeper"
	snapshot["players"].append(second)
	me["hp"] = 0
	snapshot["tick"] = 2
	probe._observe(snapshot)
	next_room._observe(snapshot)
	_check(next_room.defeated.size() == 1 and next_room.defeated.has("second"), "mixed encounter counts a new bot defeat")
	me["hp"] = 100
	snapshot["tick"] = 3
	probe._observe(snapshot)
	_check(probe.participant_died, "respawn cannot hide a failed combat run")
	var history: QaCombat = QaCombat.new()
	guard["name"] = "early_guard"
	second["name"] = "other_guard"
	history._observe(snapshot)
	_check(history.confirmed(["early_guard", "missing_guard"]).size() == 1, "an unrelated guard cannot satisfy a named encounter")
	snapshot["tick"] = 4
	history._observe(snapshot)
	_check(history.confirmed(["early_guard"])["early_guard"] == 3, "later corpse snapshots preserve the first observed death tick")
	snapshot["tick"] = 5
	snapshot["players"] = [me]
	history._observe(snapshot)
	_check(history.confirmed(["early_guard"]).has("early_guard"), "a verified earlier death survives corpse cleanup")
	_check(history.defeated.is_empty(), "between-fight history cannot inflate per-fight defeats")
	var absence: QaCombat = QaCombat.new()
	absence.set("_player_id", "player")
	absence._observe(snapshot)
	snapshot["players"] = []
	snapshot["tick"] = 6
	absence._observe(snapshot)
	snapshot["players"] = [me]
	snapshot["tick"] = 7
	absence._observe(snapshot)
	_check(absence.participant_died, "omitted respawning participant cannot hide a death between fights")
	var leap_player: Dictionary = me.duplicate(true)
	leap_player["hp"] = 100
	var leap_enemy: Dictionary = guard.duplicate(true)
	leap_enemy["name"] = "stair_crawler_first"
	leap_enemy["hp"] = 60
	leap_enemy["campaign"]["kind"] = "crawler"
	leap_enemy["campaign"]["phase"] = "windup"
	var leap_snapshot: Dictionary = {"tick": 1, "players": [leap_player, leap_enemy]}
	var before_activation: QaCombat = QaCombat.new()
	before_activation.set("_player_id", "player")
	leap_enemy["campaign"]["phase"] = "idle"
	before_activation._observe(leap_snapshot)
	leap_snapshot["tick"] = 2
	leap_player["hp"] = 90
	before_activation._observe(leap_snapshot)
	leap_snapshot["tick"] = 3
	leap_enemy["campaign"]["phase"] = "moving"
	before_activation._observe(leap_snapshot)
	_check(before_activation.first_crawler_encounter_start_hp == 90,
		"guard-room damage before Crawler activation does not contaminate its proof")
	leap_player["hp"] = 100
	leap_snapshot["tick"] = 1
	leap_enemy["campaign"]["phase"] = "windup"
	var safe_leap: QaCombat = QaCombat.new()
	safe_leap.set("_player_id", "player")
	safe_leap._observe(leap_snapshot)
	leap_snapshot["tick"] = 2
	leap_enemy["campaign"]["phase"] = "leaping"
	safe_leap._observe(leap_snapshot)
	leap_snapshot["tick"] = 3
	leap_enemy["campaign"]["phase"] = "recovery"
	safe_leap._observe(leap_snapshot)
	_check(safe_leap.first_crawler_leap_no_contact_proven() and safe_leap.first_crawler_leap_start_hp == 100,
		"first Crawler leap leaves authoritative HP unchanged through landing")
	leap_snapshot["tick"] = 4
	leap_enemy["hp"] = 0
	leap_enemy["campaign"]["phase"] = "dead"
	safe_leap._observe(leap_snapshot)
	_check(safe_leap.first_crawler_encounter_no_damage_proven(),
		"first Crawler encounter remains free of damage through its defeat")
	var later_contact: QaCombat = QaCombat.new()
	later_contact.set("_player_id", "player")
	leap_player["hp"] = 100
	leap_enemy["hp"] = 60
	leap_snapshot["tick"] = 1
	leap_enemy["campaign"]["phase"] = "windup"
	later_contact._observe(leap_snapshot)
	leap_snapshot["tick"] = 2
	leap_enemy["campaign"]["phase"] = "leaping"
	later_contact._observe(leap_snapshot)
	leap_snapshot["tick"] = 3
	leap_enemy["campaign"]["phase"] = "recovery"
	later_contact._observe(leap_snapshot)
	leap_snapshot["tick"] = 4
	leap_enemy["campaign"]["phase"] = "windup"
	later_contact._observe(leap_snapshot)
	leap_snapshot["tick"] = 5
	leap_enemy["campaign"]["phase"] = "leaping"
	leap_player["hp"] = 80
	later_contact._observe(leap_snapshot)
	leap_snapshot["tick"] = 6
	leap_enemy["hp"] = 0
	leap_enemy["campaign"]["phase"] = "dead"
	later_contact._observe(leap_snapshot)
	_check(later_contact.first_crawler_leap_no_contact_proven() and
		not later_contact.first_crawler_encounter_no_damage_proven(),
		"a safe first leap cannot hide damage from a later visible leap")
	var contact: QaCombat = QaCombat.new()
	contact.set("_player_id", "player")
	leap_player["hp"] = 100
	leap_snapshot["tick"] = 1
	leap_enemy["hp"] = 60
	leap_enemy["campaign"]["phase"] = "windup"
	contact._observe(leap_snapshot)
	leap_snapshot["tick"] = 2
	leap_enemy["campaign"]["phase"] = "leaping"
	leap_player["hp"] = 88
	contact._observe(leap_snapshot)
	leap_snapshot["tick"] = 3
	leap_enemy["campaign"]["phase"] = "recovery"
	contact._observe(leap_snapshot)
	_check(not contact.first_crawler_leap_no_contact_proven() and contact.first_crawler_leap_low_hp == 88,
		"contact on the first leaping tick cannot masquerade as a dodge")
	if _failures == 0:
		print("test_qa_combat: PASS")
	quit(0 if _failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_qa_combat: " + message)
