extends SceneTree

const TOUR = preload("res://scripts/qa_tour.gd")

class TurretObserverProbe extends RefCounted:
	var calls: int = 0
	func observe(_snapshot: Dictionary) -> void:
		calls += 1

class ApproachProbe extends QaCombat:
	var defenses: int = 0
	var fired: bool = false
	func engage(_manager: Node, _me: Dictionary, _target: Dictionary, _solids: Array, _anchor: Vector2, _evade: bool, allow_fire: bool) -> void:
		defenses += 1
		fired = fired or allow_fire

class PitchNetwork extends Node:
	var player_id: String = "local-human"

class PitchManager extends Node:
	var is_human_player: bool = true
	var latest_snapshot: Dictionary = {}
	var net_client: Node

class PitchTour extends TOUR:
	var manager: Node
	var camera: Node
	func _initialize() -> void:
		pass
	func _game_manager() -> Node:
		return manager
	func _spectator_camera() -> Node:
		return camera

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	await _check_aim_pitch()
	_check_engagement_distance()
	_check_focused_route()
	_check_m06_gallery_contact()
	_check_m06_contact_dodge()
	_check_approach_arrival()
	_check_turret_peek()
	_check_resolved_shots()
	var caller: QaCombat = QaCombat.new()
	var observer: TurretObserverProbe = TurretObserverProbe.new()
	caller._turret_observer = observer
	caller._recording = true
	var evidence: Dictionary = {"tick": 1, "players": [], "shot_results": []}
	caller._observe(evidence)
	caller._observe(evidence)
	evidence["tick"] = 0
	caller._observe(evidence)
	_check(observer.calls == 1, "cover proof receives only fresh actual snapshots through the combat observer")
	caller._recording = false
	evidence["tick"] = 2
	caller._observe(evidence)
	caller.finish()
	_check(observer.calls == 1 and caller._turret_observer == null, "inactive/finished combat stops and releases the bounded cover observer")
	_check(QaCombat.valid_turret_cancel({}) and QaCombat.valid_turret_cancel({"expect_turret_cover_cancel": false}), "cancellation proof is optional and defaults unchanged")
	var cancel: Dictionary = {"expect_turret_cover_cancel": true, "kind": "union", "phase_kind": "turret", "required": ["intro_turret"]}
	_check(QaCombat.valid_turret_cancel(cancel), "real cancellation proof binds to exactly one named Turret")
	for patch: Dictionary in [{"expect_turret_cover_cancel": "true"}, {"expect_turret_cover_cancel": 1}, {"phase_kind": "clerk"}, {"required": []}, {"required": ["intro_turret", "exit_turret"]}, {"required": [42]}]:
		var invalid_cancel: Dictionary = cancel.duplicate(true)
		invalid_cancel.merge(patch, true)
		_check(not QaCombat.valid_turret_cancel(invalid_cancel), "untyped or ambiguous fight cannot claim named charge cancellation")
	var focused: Dictionary = {"required": ["intro_turret"], "approach_focus": "intro_turret", "approach_route": [[0, 0, 10]]}
	_check(QaCombat.valid_approach_focus({}) and QaCombat.valid_approach_focus(focused), "focus is optional and bound to a required actor on a real route")
	for invalid_focus: Variant in [true, 1, "", "other_turret"]:
		var invalid_spec: Dictionary = focused.duplicate(true)
		invalid_spec["approach_focus"] = invalid_focus
		_check(not QaCombat.valid_approach_focus(invalid_spec), "malformed or unrelated focus refused")
	var empty_route: Dictionary = focused.duplicate(true)
	empty_route["approach_route"] = []
	_check(not QaCombat.valid_approach_focus(empty_route), "focused approach cannot bypass ordinary route validation")
	var turret: Dictionary = {"name": "intro_turret", "hp": 120, "x": 2.0, "y": 2.65, "z": 18.0,
		"campaign": {"side": "union", "kind": "turret", "phase": "windup"}}
	_check(QaCombat.approach_focus_point({"players": [turret]}, "intro_turret") != Vector3.INF, "focus uses an actual living Union body")
	turret["hp"] = 0
	_check(QaCombat.approach_focus_point({"players": [turret]}, "intro_turret") == Vector3.INF
		and QaCombat.approach_focus_point({"players": []}, "intro_turret") == Vector3.INF, "missing or defeated actor cannot invent a capture target")
	_check(TOUR.valid_walks([{"expect_m06_completed": ["freight_cleared"], "expect_m06_prisoner_route_marked": false}]), "M06 expectations accept an exact prefix and typed marker")
	_check(TOUR.valid_walks([{"expect_m09_completed": ["loading_cleared"], "expect_m09_crew_released": false, "expect_m09_charge_falls": 0}]), "M09 expectations retain actual ordered facts")
	for prefix_size: int in range(M10MissionState.OBJECTIVES.size() + 2):
		var ship_order: Array[String] = M10MissionState.OBJECTIVES.duplicate()
		ship_order.append(M10MissionState.DEPARTURE)
		_check(TOUR.valid_walks([{"expect_m10_completed": ship_order.slice(0, prefix_size)}]), "M10 accepts every actual ordered completion prefix")
	for invalid_m10: Variant in ["forward_secured", {}, ["service_secured"], ["forward_secured", "forward_secured"], ["forward_secured", "service_secured", "aft_secured", "passengers_secured", "party_departed", "party_departed"]]:
		_check(not TOUR.valid_walks([{"expect_m10_completed": invalid_m10}]), "malformed or reordered ship acceptance is refused")
	_check_m10_route()
	for invalid_m09: Dictionary in [{"expect_m09_completed": ["lesson_cleared"]}, {"expect_m09_hatch_open": "true"}, {"expect_m09_charge_falls": 8}, {"expect_m09_charge_falls": 0.5}]:
		_check(not TOUR.valid_walks([invalid_m09]), "malformed berth acceptance requirement is refused")
	for invalid_m06: Dictionary in [{"expect_m06_completed": ["rail_lane_cleared"]}, {"expect_m06_prisoner_route_marked": "false"}, {"expect_m06_carried_photos": -1}, {"expect_m06_carried_patients": ["edda", "edda"]}]:
		_check(not TOUR.valid_walks([invalid_m06]), "malformed M06 capture requirement cannot become an untested assertion")
	var declared_false: Dictionary = {"combat_travel": false}
	var scoped_true: Dictionary = {"combat_travel": true, "combat_travel_targets": ["lesson_heavy"]}
	_check(TOUR.combat_travel_enabled(declared_false, scoped_true)
		and not TOUR.combat_travel_enabled(declared_false, {}),
		"scoped travel defense cannot leak into an unspecified stage with unrestricted targets")
	var declared_true: Dictionary = {"combat_travel": true}
	_check(not TOUR.combat_travel_enabled(declared_true, {"combat_travel": false})
		and TOUR.combat_travel_enabled(declared_true, {}),
		"a scoped quiet stage preserves globally enabled defense for later unspecified stages")
	_check(TOUR.valid_combat_travel({}) and TOUR.valid_combat_travel(declared_false)
		and TOUR.valid_combat_travel(declared_true), "optional global travel flag accepts only declared booleans")
	for invalid_flag: Variant in ["false", "true", 0, 1, null, [], {}]:
		_check(not TOUR.valid_combat_travel({"combat_travel": invalid_flag})
			and not TOUR.combat_travel_enabled({"combat_travel": invalid_flag}, {}),
			"global string, number or other nonboolean cannot enable unrestricted travel defense")
	_check(TOUR.valid_walks([{"trigger": "throw_grenade", "grenade_follow": true}])
		and TOUR.valid_walks([{"grenade_follow": false}]), "projectile-follow capture is an explicit grenade-only option")
	for invalid_follow: Variant in ["true", 1, null]:
		_check(not TOUR.valid_walks([{"trigger": "throw_grenade", "grenade_follow": invalid_follow}]), "nonboolean camera-follow option rejected")
	_check(not TOUR.valid_walks([{"trigger": "fire", "grenade_follow": true}]), "gun or unrelated camera state cannot request grenade-follow")
	var live_capture: Dictionary = {"id": 1, "owner_id": "owner", "position": [1, 2, 3]}
	_check(not TOUR.fresh_grenade_capture("owner", {}, {}, live_capture)
		and TOUR.fresh_grenade_capture("owner", {}, {1: true}, live_capture), "capture camera waits for actual recorded launch before accepting a point")
	_check(not TOUR.fresh_grenade_capture("other", {}, {1: true}, live_capture)
		and not TOUR.fresh_grenade_capture("owner", {1: true}, {1: true}, live_capture), "other-owner and pre-existing grenades cannot steal the capture camera")
	live_capture["position"] = [1, INF, 3]
	_check(not TOUR.fresh_grenade_capture("owner", {}, {1: true}, live_capture), "nonfinite projectile or explosion points never drive the camera")
	_check_jammer_launch()
	_check(QaCombat.approach_evade_enabled({}) and QaCombat.approach_evade_enabled({"evade_tells": true}),
		"ordinary approach keeps its historical tell evasion unless explicitly disabled")
	_check(not QaCombat.approach_evade_enabled({"evade_tells": false}),
		"explicit standing observation does not acquire movement through a committed approach tell")
	for invalid_evade: Variant in ["false", 0, null, []]:
		_check(not QaCombat.valid_evade_tells({"evade_tells": invalid_evade})
			and not QaCombat.approach_evade_enabled({"evade_tells": invalid_evade}),
			"nonboolean approach policy is rejected instead of enabling unexpected movement")
	var roof: Array = [{"min_x": -3.0, "max_x": 3.0, "min_z": -3.0, "max_z": 3.0, "bottom": 2.5, "top": 3.0}]
	var edge: Dictionary = {"x": 0.0, "y": 3.0 + QaCombat.CAMERA.FP_SERVER_REFERENCE_Y, "z": 2.6}
	_check(not QaCombat.safe_strafe(edge, roof, 20.0, 0.0, false) and QaCombat.safe_strafe(edge, roof, 20.0, 0.0, true),
		"a rooftop dodge rejects the exposed edge and keeps its inward alternative")
	_check(QaCombat.safe_strafe({"x": 0.0, "y": QaCombat.CAMERA.FP_SERVER_REFERENCE_Y, "z": 0.0}, [], 20.0, 0.0, false),
		"ordinary open-ground evasion remains available")
	_check(not QaCombat.safe_strafe({"x": 0.0, "y": QaCombat.CAMERA.FP_SERVER_REFERENCE_Y, "z": 0.0},
		[{"min_x": -3.0, "max_x": 3.0, "min_z": 0.6, "max_z": 3.0, "top": 4.0}], 20.0, 0.0, false),
		"a blocked dodge does not pretend to escape through cover")
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
	_check(TOUR.valid_radio_comparison("", [{"radio_off":true}])
		and TOUR.valid_radio_comparison("on", [{"radio_off":true}]),
		"radio comparison leaves the default route alone and accepts explicit opt-in")
	_check(not TOUR.valid_radio_comparison("on", [{"camera":"first_person"}])
		and not TOUR.valid_radio_comparison("yes", [{"radio_off":true}]),
		"radio comparison rejects unsupported and inapplicable overrides")
	_check(TOUR.valid_walks([{"scene":"res://scenes/main.tscn", "record_audio_start":true},
		{"record_audio_stop":true}]), "bounded live audio state pair accepted")
	for invalid_audio: Array in [
		[{"record_audio_start":true}],
		[{"record_audio_stop":true}],
		[{"record_audio_start":true}, {"record_audio_start":true}, {"record_audio_stop":true}],
		[{"record_audio_start":true}, {"scene":"res://scenes/boot_menu.tscn", "record_audio_stop":true}],
		[{"record_audio_start":true, "record_audio_seconds":1.0, "record_audio_stop":true}],
		[{"record_audio_start":"yes", "record_audio_stop":true}],
	]:
		_check(not TOUR.valid_walks(invalid_audio), "invalid live audio span rejected before play")
	var pack_snapshot: Dictionary = {"players":[
		{"name":"crawler", "hp":20, "campaign":{"side":"union", "phase":"moving"}},
		{"name":"sweeper", "hp":0, "campaign":{"side":"union", "phase":"dead"}},
	]}
	_check(TOUR.active_named_enemies(pack_snapshot, ["crawler", "sweeper"]) == {"crawler":"moving"},
		"spectator proof counts only named living enemies")
	for invalid_seconds: Variant in [0, 121, INF, "60"]:
		_check(not TOUR.valid_walks([{"join": "human", "ack_probe_seconds": invalid_seconds}]),
			"Ack probe duration must be finite and bounded")
		_check(not TOUR.valid_walks([{"join": "human", "moving_combat_seconds": invalid_seconds}]),
			"moving combat duration must be finite and bounded")
	_check(not TOUR.valid_walks([{"ack_probe_seconds": 60}]),
		"Ack probe cannot run without a human join")
	_check(not TOUR.valid_walks([{"moving_combat_seconds": 20}]),
		"moving combat cannot run without a human join")
	_check(TOUR.valid_walks([{"join": "human", "moving_combat_seconds": 20}]),
		"moving combat accepts a bounded joined window")
	_check(TOUR.valid_walks([{"walk_to": [[70, 0, 2]], "stop_on_round_state": "Ended"}]),
		"a walk may stop when the round ends")
	_check(not TOUR.valid_walks([{"stop_on_round_state": "ended"}]),
		"a round stop must name a server round state")
	_check(TOUR.valid_walks([{"combat_travel": false}, {"combat_travel": true}]),
		"a later stage can defend through ordinary travel without firing during the earlier lesson")
	for value: Variant in [null, "true", 1, {}]:
		_check(not TOUR.valid_walks([{"combat_travel": value}]),
			"stage travel control requires an explicit boolean")
	_check(TOUR.valid_walks([{"combat_travel_targets": ["advance_notary_a", "advance_sweeper_a"]}]),
		"travel can limit fire to the current authored encounter")
	for value: Variant in [null, "advance", [], [1], [""], ["same", "same"], ["x".repeat(65)]]:
		_check(not TOUR.valid_walks([{"combat_travel_targets": value}]),
			"travel target lists reject malformed, duplicate and oversized names")
	_check(not TOUR.valid_walks([{"join": "human", "moving_combat_seconds": 20, "ack_probe_seconds": 20}]),
		"one state cannot start two Ack probes")
	var healthy: Dictionary = {"interrupted": false, "failed_sends": 0,
		"invalid_acks": 0, "invalid_snapshots": 0, "duration_seconds": 60.1,
		"sent": 3600, "matched_acks": 1100, "snapshots": 1100,
		"first_matched_ack_ms": 50, "last_matched_ack_ms": 59950,
		"first_snapshot_ms": 50, "last_snapshot_ms": 59950,
		"max_matched_ack_gap_ms": 75, "max_snapshot_gap_ms": 75}
	_check(TOUR.valid_ack_capture(healthy, 60.0), "full-window Ack capture accepted")
	var stalled: Dictionary = healthy.duplicate()
	stalled["last_snapshot_ms"] = 30000
	_check(not TOUR.valid_ack_capture(stalled, 60.0), "capture cannot pass after a late snapshot stall")
	stalled = healthy.duplicate()
	stalled["max_matched_ack_gap_ms"] = 1000
	_check(not TOUR.valid_ack_capture(stalled, 60.0), "capture cannot hide a one-second Ack gap")
	var combat: Dictionary = {"interruption": "", "ack_probe": healthy, "server_snapshot_distance_m": 30.0,
		"server_shots": 10, "shots_while_moving": 8, "snapshots_with_live_opponents": 300,
		"snapshots_observed": 1100, "correction_m": {"samples": 900}, "prediction_active_at_end": true}
	_check(TOUR.valid_moving_combat_capture(combat, 60.0), "live moving combat window accepted")
	for missing: String in ["server_snapshot_distance_m", "server_shots", "shots_while_moving"]:
		var idle: Dictionary = combat.duplicate(true)
		idle[missing] = 0
		_check(not TOUR.valid_moving_combat_capture(idle, 60.0), "no movement or shot evidence cannot pass")
	for filename: String in DirAccess.get_files_at("res://qa"):
		if filename.get_extension() != "json":
			continue
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/" + filename))
		_check(manifest is Dictionary and TOUR.valid_walks(manifest.get("states")), filename + " has valid walking routes")
		if manifest is Dictionary:
			for state: Variant in manifest.get("states", []):
				if state is Dictionary and state.get("combat") is Dictionary:
					_check(QaCombat.valid_engagement_distance(state["combat"]), filename + " has a valid optional engagement distance")
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
	guard["name"] = "ward_clerk"
	_check(QaCombat.visible_target(snapshot, "player", [], false, INF, ["ward_clerk"]).get("id") == "guard",
		"named ward target remains eligible")
	_check(QaCombat.visible_target(snapshot, "player", [], false, INF, ["stair_crawler_pack_a"]).is_empty(),
		"named combat stage does not shoot a dormant optional pack")
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") != "latch",
		"the nearby companion is never an automated combat target")
	_check(not QaCombat.visible_target(snapshot, "player", [], true).is_empty(), "visible windup permits evasive input")
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0).get("id") == "guard", "travel engages a nearby threat")
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0, ["market_wave_b"]).is_empty(),
		"travel leaves unrelated newly eligible guards for their later encounter")
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0, ["ward_clerk"]).get("id") == "guard",
		"scoped travel still defends against its nearby required guard")
	guard["z"] = 34.0
	_check(QaCombat.visible_target(snapshot, "player", [], false, 24.0).is_empty(), "travel continues past a distant sightline")
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") == "guard", "combat can still resolve a distant required guard")
	guard["z"] = 5.0
	var solid: Dictionary = {"min_x":-1.0, "max_x":1.0, "min_z":2.0, "max_z":3.0, "bottom":0.0, "top":3.0}
	_check(QaCombat.visible_target(snapshot, "player", [solid]).is_empty(), "wall prevents automated fire")
	_check(QaCombat.visible_target(snapshot, "player", [solid], true).is_empty(), "hidden windup cannot drive evasion")
	var loadout: Dictionary = {"selected": "scatter", "ammo": [0, 0, 90, 6, 0]}
	var distant: Dictionary = QaCombat.engagement_evidence(snapshot, "player", loadout, [], ["ward_clerk"], 4.0)
	_check(distant["participant"]["id"] == "player" and distant["loadout"] == loadout
		and distant["guards"].size() == 1 and distant["guards"][0]["line_of_sight"] == true
		and distant["guards"][0]["within_engagement_distance"] == false,
		"failed combat evidence separates actual loadout, visible guard and rejected distance")
	var hidden: Dictionary = QaCombat.engagement_evidence(snapshot, "player", loadout, [solid], ["ward_clerk"], 10.0)
	_check(hidden["guards"][0]["line_of_sight"] == false and hidden["guards"][0]["within_engagement_distance"] == false,
		"failed combat evidence distinguishes solid cover from an exposed target")
	loadout["selected"] = "flechette"
	guard["x"] = 6.0
	_check(distant["loadout"]["selected"] == "scatter" and distant["guards"][0]["actor"]["x"] == 0.0,
		"preserved evidence does not follow subsequent mutable snapshots")
	guard["x"] = 0.0
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
	var drone: Dictionary = guard.duplicate(true)
	drone["y"] = 5.5
	drone["campaign"]["kind"] = "notary"
	_check(is_equal_approx(QaCombat.exposed_point(drone, Vector3(0, 1.6, 0), []).y, 4.35),
		"ordinary tour shots aim inside the real raised drone box")
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

func _check_aim_pitch() -> void:
	var tour: PitchTour = PitchTour.new()
	var manager: PitchManager = PitchManager.new()
	var network: PitchNetwork = PitchNetwork.new()
	var camera: Node3D = preload("res://scripts/spectator_cam.gd").new()
	manager.net_client = network
	tour.manager = manager
	tour.camera = camera
	var relay: Callable = _relay_pitch_frame.bind(tour)
	process_frame.connect(relay)
	var requests: Array[float] = [-PI * 0.5, PI * 0.5, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT, -0.7, 0.0, 0.45]
	var accepted: Array[float] = [-ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT, -0.7, 0.0, 0.45]
	for index: int in range(requests.size()):
		manager.latest_snapshot = {"players": [
			{"id": "another-human", "pitch": requests[index]},
			{"id": network.player_id, "pitch": accepted[index]}]}
		await tour._set_aim_pitch(requests[index])
		_check(not tour._failed, "real pitch helper acknowledges the local human's bounded or ordinary snapshot")
		_check(is_equal_approx(float(camera.get("fp_pitch")), accepted[index]),
			"real pitch helper sets the camera to the attainable target")
		_check(is_equal_approx(float(camera.call("consume_pitch")), accepted[index]),
			"ordinary camera action input agrees with the acknowledged target")
	process_frame.disconnect(relay)
	await process_frame
	tour.free()
	camera.free()
	network.free()
	manager.free()

func _relay_pitch_frame(tour: PitchTour) -> void:
	tour.process_frame.emit()

func _check_engagement_distance() -> void:
	_check(QaCombat.valid_engagement_distance({}) and QaCombat.valid_engagement_distance({"engagement_distance": 10})
		and QaCombat.valid_engagement_distance({"engagement_distance": 90.0}), "distance-bounded combat is optional and accepts finite positive limits")
	for invalid: Variant in [null, true, "10", [], {}, NAN, INF, -INF, 0, -1, 90.1]:
		_check(not QaCombat.valid_engagement_distance({"engagement_distance": invalid}), "malformed or unbounded combat distance is refused")
	var me: Dictionary = {"id": "player", "hp": 100, "x": 0.0, "y": 1.5, "z": 0.0, "campaign": {"side": "participant"}}
	var guard: Dictionary = {"id": "guard", "name": "held_sweeper", "hp": 80, "x": 20.0, "y": 1.5, "z": 0.0,
		"campaign": {"side": "union", "kind": "sweeper", "phase": "windup"}}
	var snapshot: Dictionary = {"players": [me, guard]}
	_check(QaCombat.visible_target(snapshot, "player", []).get("id") == "guard"
		and QaCombat.visible_target(snapshot, "player", [], false, 10.0).is_empty(), "a visible distant guard keeps ordinary search movement eligible in a short-range stage")
	var body: Dictionary = MoveStep.make_state(0.0, 0.0, 0.0)
	body["y"] = 0.0
	for _tick: int in range(45):
		body = MoveStep.live_step(body, MoveStep.make_input(true, false, false, false, 0.0),
			MoveStep.TOP_SPEED, MoveStep.DT_LIVE, {"half": 40.0, "solids": []})
	me["x"] = body["x"]
	me["z"] = body["z"]
	_check(QaCombat.visible_target(snapshot, "player", [], false, 10.0, ["held_sweeper"]).get("id") == "guard", "ordinary movement brings the same actual guard inside the engagement limit")
	_check(QaCombat.visible_target(snapshot, "player", [], false, 10.0, ["other_guard"]).is_empty(), "distance does not bypass the named encounter boundary")

func _check_focused_route() -> void:
	var course: Vector2 = Vector2.from_angle(deg_to_rad(14.0))
	var buttons: Dictionary = QaCombat.route_buttons(course, 0.0)
	_check(buttons["move_forward"] and not buttons["move_right"] and not buttons["move_left"],
		"near-forward focused movement does not oversteer into a diagonal")
	buttons = QaCombat.route_buttons(Vector2(1, 1), 0.0)
	_check(buttons["move_forward"] and buttons["move_right"] and not buttons["move_back"],
		"diagonal and cardinal input retain ordinary eight-direction movement")
	buttons = QaCombat.route_buttons(Vector2(-1, 0), 0.0)
	_check(buttons["move_back"] and not buttons["move_left"] and not buttons["move_right"],
		"opposite course uses the actual backward action")
	var body: Dictionary = MoveStep.make_state(-19.526575, 7.954943, 0.0)
	body["y"] = 3.0
	var arena: Dictionary = {"half": 48.0, "solids": [{"min_x": -21.0, "max_x": -16.0,
		"min_z": 6.0, "max_z": 36.0, "bottom": 2.5, "top": 3.0}]}
	var reached: bool = false
	var grounded: bool = true
	for _tick: int in range(160):
		var delta: Vector2 = Vector2(-20.0 - float(body["x"]), 16.0 - float(body["z"]))
		if delta.length() < 0.5:
			reached = true
			break
		var focus: Vector2 = Vector2(-18.5 - float(body["x"]), 16.0 - float(body["z"]))
		var yaw: float = atan2(focus.y, focus.x)
		buttons = QaCombat.route_buttons(delta, yaw)
		var action: Dictionary = MoveStep.make_input(buttons["move_forward"], buttons["move_back"],
			buttons["move_left"], buttons["move_right"], yaw)
		body = MoveStep.live_step(body, action, MoveStep.TOP_SPEED, MoveStep.DT_LIVE, arena)
		grounded = grounded and absf(float(body["y"]) - 3.0) < 0.01
	_check(reached and grounded, "ordinary focused inputs reach the rear waypoint without walking off the real gallery footprint")

func _check_approach_arrival() -> void:
	var at_origin: Dictionary = {"id": "human", "x": 0.0, "y": 1.5, "z": 0.0, "hp": 100}
	_check(QaCombat.waypoint_arrived(at_origin, [0.49999, 0.19999, 0]), "strictly inside both legacy arrival distances is reached")
	_check(not QaCombat.waypoint_arrived(at_origin, [0.5, 0, 0])
		and not QaCombat.waypoint_arrived(at_origin, [0.50001, 0, 0]), "exact horizontal boundary and outside remain unreached")
	_check(not QaCombat.waypoint_arrived(at_origin, [0, 0.2, 0])
		and not QaCombat.waypoint_arrived(at_origin, [0, 0.20001, 0])
		and not QaCombat.waypoint_arrived(at_origin, [0, -0.2, 0]), "exact positive/negative height boundary and outside remain unreached")
	_check(not QaCombat.waypoint_arrived(at_origin, [0.4, 0, 0.4]), "arrival uses horizontal length rather than independent axis tolerances")
	var raised: Dictionary = at_origin.duplicate()
	raised["y"] = 4.5
	_check(QaCombat.waypoint_arrived(raised, [0, 3, 0])
		and not QaCombat.waypoint_arrived(raised, [0, 0, 0]), "arrival compares actual feet height instead of pawn reference height")
	var me: Dictionary = at_origin.duplicate()
	me["x"] = 0.2
	me["z"] = 0.1
	var guard: Dictionary = {"id": "guard", "name": "guard", "hp": 60, "x": 0.0, "y": 1.5, "z": 5.0,
		"campaign": {"side": "union", "kind": "clerk", "phase": "windup"}}
	var snapshot: Dictionary = {"tick": 1, "players": [me, guard]}
	_check(not QaCombat.visible_target(snapshot, "human", [], true).is_empty(), "arrival ordering fixture includes a real visible committed attack")
	var manager: Node = Node.new()
	var camera: Node3D = QaCombat.CAMERA.new()
	camera.name = "SpectatorCamera"
	manager.add_child(camera)
	var driver: ApproachProbe = ApproachProbe.new()
	driver._player_id = "human"
	var anchor: Vector2 = Vector2(-2, -3)
	var focus: Dictionary = {"approach_focus": "guard"}
	QaCombat.release_inputs()
	var arrived: Dictionary = driver.approach_step(manager, me, snapshot, focus, [], anchor, [[0, 0, 0]], 0)
	_check(arrived["index"] == 1 and arrived["anchor"] == Vector2(me.x, me.z)
		and driver.defenses == 0 and not driver.fired, "actually reached final point advances before committed defense and refreshes its anchor")
	_check(is_equal_approx(float(camera.get("fp_yaw")), atan2(4.9, -0.2))
		and float(camera.get("fp_pitch")) < 0.0, "reached focused approach preserves actual camera aim without movement")
	_check(not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("fire"), "arrival acknowledgement grants no movement or premature shot")
	var queued: Dictionary = driver.approach_step(manager, me, snapshot, {}, [], anchor, [[0, 0, 0], [0, 0, 0]], 0)
	_check(queued["index"] == 1 and driver.defenses == 0 and not driver.fired, "only one actually reached waypoint advances per frame")
	var unfinished: Dictionary = driver.approach_step(manager, me, snapshot, {}, [], anchor, [[0, 0, 2]], 0)
	_check(unfinished["index"] == 0 and unfinished["anchor"] == anchor
		and driver.defenses == 1 and not driver.fired, "unfinished committed approach retains defense and cannot fire")
	var searching: Dictionary = driver.search_step(manager, me, snapshot, {"engagement_distance": 3.0}, [], anchor, [[0, 0, 2]], 0)
	_check(searching["index"] == 0 and searching["anchor"] == anchor
		and driver.defenses == 2 and not driver.fired, "a distant committed guard cannot strip tell defense or cause premature search fire")
	QaCombat.release_inputs()
	searching = driver.search_step(manager, me, snapshot, {}, [], anchor, [[0, 0, 2]], 0)
	_check(searching["index"] == 0 and driver.defenses == 2 and Input.is_action_pressed("move_forward")
		and not Input.is_action_pressed("fire"), "an unspecified search retains its existing ordinary walking behavior")
	driver.defenses = 1
	guard["campaign"]["phase"] = "idle"
	QaCombat.release_inputs()
	var walking: Dictionary = driver.approach_step(manager, me, snapshot, focus, [], anchor, [[0, 0, 2]], 0)
	_check(walking["index"] == 0 and walking["anchor"] == anchor and driver.defenses == 1
		and Input.is_action_pressed("move_forward") and not Input.is_action_pressed("fire"), "open unfinished approach retains ordinary focused walking and no-fire gate")
	guard["campaign"]["phase"] = "windup"
	QaCombat.release_inputs()
	var standing: Dictionary = driver.approach_step(manager, me, snapshot, {"evade_tells": false}, [], anchor, [[0, 0, 2]], 0)
	_check(standing["index"] == 0 and driver.defenses == 1 and Input.is_action_pressed("move_forward")
		and not driver.fired, "explicitly disabled tell evasion preserves unfinished ordinary route behavior")
	QaCombat.release_inputs()
	var ended: Dictionary = driver.approach_step(manager, me, snapshot, {}, [], anchor, [[0, 0, 2]], 1)
	var empty: Dictionary = driver.approach_step(manager, me, snapshot, {}, [], anchor, [], 0)
	_check(ended["index"] == 1 and empty["index"] == 0 and ended["anchor"] == anchor
		and empty["anchor"] == anchor and driver.defenses == 1, "route end and empty approach do not create advancement or defense")
	manager.free()

static func _peek_snapshot(tick: int, feet: Vector3, phase: String = "windup",
		started: int = 101, ends: int = 127) -> Dictionary:
	return {"tick": tick, "players": [
		{"id": "00000000-0000-0000-0000-000000000001", "name": "Viewer", "hp": 100,
			"x": feet.x, "y": feet.y + QaCombat.CAMERA.FP_SERVER_REFERENCE_Y, "z": feet.z,
			"campaign": {"side": "participant"}},
		{"id": "00000000-0000-0000-0000-000000000002", "name": "intro_turret", "hp": 100,
			"x": -18.5, "y": 4.5, "z": 16.0, "campaign": {"side": "union", "kind": "turret",
				"phase": phase, "phase_started": started, "phase_ends": ends}}]}

func _check_turret_peek() -> void:
	var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m06_port_of_entry.json"))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m06_port_of_entry.json"))
	_check(authored is Dictionary and manifest is Dictionary, "peek regression loads actual M06 map and capture specimen")
	if not authored is Dictionary or not manifest is Dictionary:
		return
	var spec: Dictionary = {}
	for stage: Dictionary in manifest["states"]:
		if stage["name"] == "turret_front_cover_rear_lesson":
			spec = stage["combat"]
	_check(not spec.is_empty() and QaCombat.valid_turret_peek(spec), "actual specimen declares a strict bounded peek")
	if spec.is_empty():
		return
	_check(QaCombat.valid_turret_peek({}), "optional peek preserves every ordinary route")
	for selected: Variant in [null, true, [], {}, {"peek_index": 4},
		{"peek_index": 4, "cover_index": 5, "deadline": 500},
		{"peek_index": -1, "cover_index": 0}, {"peek_index": 4.5, "cover_index": 5},
		{"peek_index": "4", "cover_index": 5}, {"peek_index": true, "cover_index": 5},
		{"peek_index": 4, "cover_index": 4}, {"peek_index": 5, "cover_index": 4},
		{"peek_index": 4, "cover_index": 6}, {"peek_index": 31, "cover_index": 32},
		{"peek_index": 20, "cover_index": 21}]:
		var invalid: Dictionary = spec.duplicate(true)
		invalid["turret_peek"] = selected
		_check(not QaCombat.valid_turret_peek(invalid), "malformed, unbounded or nonadjacent peek refused")
	for patch: Dictionary in [{"expect_turret_cover_cancel": false}, {"expect_turret_cover_cancel": 1},
		{"approach_focus": "another_turret"}, {"approach_focus": null},
		{"approach_route": []}, {"approach_route": [[0, 0, INF]]}, {"phase_kind": "clerk"}]:
		var invalid: Dictionary = spec.duplicate(true)
		invalid.merge(patch, true)
		_check(not QaCombat.valid_turret_peek(invalid), "peek cannot bypass typed observer, named focus or route boundary")
	var solids: Array[Dictionary] = []
	for solid: Dictionary in authored["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2],
			"max_z": solid["max"][2], "bottom": solid["min"][1], "top": solid["max"][1]})
	var route: Array = spec["approach_route"]
	var peek_index: int = int(spec["turret_peek"]["peek_index"])
	var cover_index: int = int(spec["turret_peek"]["cover_index"])
	var peek: Vector3 = Vector3(route[peek_index][0], route[peek_index][1], route[peek_index][2])
	var cover: Vector3 = Vector3(route[cover_index][0], route[cover_index][1], route[cover_index][2])
	_check(peek == Vector3(0, 0, 12) and cover == Vector3(0, 0, 10),
		"clear peek follows first-shot sweep and precedes ordinary covered retreat")
	var first_sweep: Array[Vector3] = [Vector3(0, 0, 10), Vector3(4, 0, 16), Vector3(-4, 0, 16), Vector3(0, 0, 10)]
	for index: int in range(first_sweep.size()):
		_check(Vector3(route[index][0], route[index][1], route[index][2]) == first_sweep[index],
			"original first-shot front sweep waypoint remains unchanged")
	var observer: QaTurret = QaTurret.new()
	_check(observer.begin("00000000-0000-0000-0000-000000000001", "intro_turret", solids), "actual registered geometry accepted")
	var eye: Vector3 = Vector3(-18.5, 3.0 + MoveStep.EYE_HEIGHT, 16.0)
	_check(observer._cover(eye, peek + Vector3(0, MoveStep.BODY_HEIGHT * 0.5, 0)).is_empty(),
		"peek is actually clear against every authoritative solid")
	var blocker: Dictionary = observer._cover(eye, cover + Vector3(0, MoveStep.BODY_HEIGHT * 0.5, 0))
	_check(not blocker.is_empty() and blocker["solid_index"] == 62,
		"covered stance is blocked by the actual registered charge cover")
	var arena: Dictionary = {"half": authored["half_extent"], "solids": solids}
	var turret: Dictionary = ActorContact.stationary("turret", Vector3(-18.5, 3, 16))
	for offset: Vector2 in [Vector2.ZERO, Vector2(-0.49, 0), Vector2(0.49, 0), Vector2(0, -0.49), Vector2(0, 0.49)]:
		var body: Dictionary = MoveStep.make_state(peek.x + offset.x, peek.z + offset.y, 0.0)
		_check(observer._cover(eye, Vector3(body["x"], MoveStep.BODY_HEIGHT * 0.5, body["z"])).is_empty(),
			"strict peek arrival offsets all retain actual clear center sight")
		var ticks: int = 0
		while ticks < 12 and not QaCombat.waypoint_arrived({"x": body["x"], "y": body["y"] + 1.5, "z": body["z"]}, route[cover_index]):
			var delta: Vector2 = Vector2(cover.x - float(body["x"]), cover.z - float(body["z"]))
			var facing: Vector2 = Vector2(-18.5 - float(body["x"]), 16.0 - float(body["z"]))
			var yaw: float = atan2(facing.y, facing.x)
			var buttons: Dictionary[String, bool] = QaCombat.route_buttons(delta, yaw)
			var action: Dictionary = MoveStep.make_input(buttons["move_forward"], buttons["move_back"],
				buttons["move_left"], buttons["move_right"], yaw)
			var proposed: Dictionary = MoveStep.live_step(body, action, MoveStep.TOP_SPEED, MoveStep.DT_LIVE, arena)
			var bodies: Array[Dictionary] = [{"key": "human", "from": body, "proposed": proposed,
				"height": MoveStep.BODY_HEIGHT, "radius": MoveStep.RADIUS, "jump": false}, turret]
			body = ActorContact.resolve(bodies, MoveStep.DT_LIVE, arena)[0]
			ticks += 1
			_check(absf(float(body["y"])) < 0.01, "focused ordinary retreat remains on actual ground with actor contact")
		var feet: Vector3 = Vector3(body["x"], body["y"], body["z"])
		_check(ticks <= 9 and QaCombat.waypoint_arrived({"x": body["x"], "y": body["y"] + 1.5, "z": body["z"]}, route[cover_index])
			and not observer._cover(eye, feet + Vector3(0, MoveStep.BODY_HEIGHT * 0.5, 0)).is_empty(),
			"actual strict-arrival starting offsets reach real cover with at least three ticks of retreat margin")
	var manager: Node = Node.new()
	var camera: Node3D = QaCombat.CAMERA.new()
	camera.name = "SpectatorCamera"
	manager.add_child(camera)
	var driver: ApproachProbe = ApproachProbe.new()
	driver._player_id = "00000000-0000-0000-0000-000000000001"
	driver._turret_observer = observer
	var anchor: Vector2 = Vector2(0, 10)
	var snapshot: Dictionary = _peek_snapshot(100, peek, "idle", 100, 100)
	observer.observe(snapshot)
	QaCombat.release_inputs()
	var held: Dictionary = driver.approach_step(manager, snapshot["players"][0], snapshot, spec, solids, anchor, route, peek_index)
	_check(held["index"] == peek_index and held["anchor"] == anchor and driver.defenses == 0
		and not Input.is_action_pressed("fire") and not Input.is_action_pressed("move_forward"),
		"production reached peek holds without a charge, route advance, shot or forced movement")
	_check(is_equal_approx(float(camera.get("fp_yaw")), atan2(4.0, -18.5)), "held peek still aims at the actual named Turret")
	snapshot = _peek_snapshot(101, peek)
	observer.observe(snapshot)
	var retreat: Dictionary = driver.approach_step(manager, snapshot["players"][0], snapshot, spec, solids, anchor, route, peek_index)
	_check(retreat["index"] == cover_index and retreat["anchor"] == Vector2(peek.x, peek.z)
		and not driver.fired, "accepted live clear charge unlocks only the next ordinary retreat waypoint")
	var not_yet: Dictionary = driver.approach_step(manager, snapshot["players"][0], snapshot, spec, solids, anchor, route, cover_index)
	_check(not_yet["index"] == cover_index and not driver.fired and Input.is_action_pressed("move_forward") == false
		and (Input.is_action_pressed("move_right") or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_back")),
		"unreached covered point keeps ordinary focused walking and no-fire behavior")
	QaCombat.release_inputs()
	for tick: int in range(102, 129):
		snapshot = _peek_snapshot(tick, cover, "windup" if tick == 102 else ("recovery" if tick < 115 else "idle"),
			101 if tick == 102 else (103 if tick < 115 else 115), 127 if tick == 102 else 115)
		observer.observe(snapshot)
		held = driver.approach_step(manager, snapshot["players"][0], snapshot, spec, solids, anchor, route, cover_index)
		_check(held["index"] == (cover_index + 1 if tick == 128 else cover_index)
			and not driver.fired and not Input.is_action_pressed("fire"),
			"production cover holds through original deadline and releases only on genuine proof")
	_check(observer.cancellation_proven() and driver.turret_peek_allows(spec, peek_index, 128),
		"already proven cancellation retains normal progression without waiting for another charge")
	_check(driver.turret_peek_allows(spec, 0, 128) and driver.turret_peek_allows({}, peek_index, 128),
		"initial front sweep and every unspecified ordinary route keep their existing progression")
	manager.free()

func _check_m06_contact_dodge() -> void:
	var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m06_port_of_entry.json"))
	_check(authored is Dictionary, "contact dodge loads the actual M06 world")
	if not authored is Dictionary:
		return
	var solids: Array[Dictionary] = []
	for solid: Dictionary in authored["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2],
			"max_z": solid["max"][2], "bottom": solid["min"][1], "top": solid["max"][1]})
	var arena: Dictionary = {"half": authored["half_extent"], "solids": solids}
	var me: Dictionary = {"id": "human", "x": -8.0, "y": 4.5, "z": 30.05, "hp": 100}
	var peer: Dictionary = ActorContact.stationary("peer", Vector3(-8.9, 3.0, 30.65))
	_check(QaCombat.safe_strafe(me, solids, 48.0, PI * 0.5, false),
		"without a peer the same ordinary sideways path stays on the real crossing")
	var body: Dictionary = MoveStep.make_state(-8.0, 30.05, PI * 0.5)
	body["y"] = 3.0
	for _tick: int in range(3):
		var proposed: Dictionary = MoveStep.live_step(body, MoveStep.make_input(false, false, false, true, PI * 0.5),
			MoveStep.TOP_SPEED, MoveStep.DT_LIVE, arena)
		body = ActorContact.resolve([{"key": "human", "from": body, "proposed": proposed,
			"height": MoveStep.BODY_HEIGHT, "radius": MoveStep.RADIUS, "jump": false}, peer], MoveStep.DT_LIVE, arena)[0]
	_check(float(body["y"]) < 2.8 and float(body["z"]) < 30.0,
		"shared physical contact redirects the formerly world-safe dodge off the actual crossing")
	_check(not QaCombat.safe_strafe(me, solids, 48.0, PI * 0.5, false, [peer]),
		"contact-aware dodge refuses the real gallery fall instead of granting world-only safety")
	_check(QaCombat.safe_strafe(me, solids, 48.0, PI * 0.5, true, [peer]),
		"opposite safe gallery direction remains available with the same living peer")
	var snapshot: Dictionary = {"tick": 1, "players": [me, {"id": "peer", "x": -8.9, "y": 4.5, "z": 30.65, "hp": 100}]}
	var contacts: Dictionary = QaCombat.strafe_contacts(snapshot, {}, "human")
	_check(contacts["error"].is_empty() and contacts["peers"].size() == 1
		and not QaCombat.safe_strafe(me, solids, 48.0, PI * 0.5, false, contacts["peers"]),
		"actual validated snapshot peers reach the contact-aware forecast")
	snapshot["players"][1]["hp"] = 0
	contacts = QaCombat.strafe_contacts(snapshot, {}, "human")
	_check(contacts["error"].is_empty() and contacts["peers"].is_empty(), "dead peers do not invent a physical obstacle")
	snapshot["players"] = [me]
	_check(QaCombat.strafe_contacts(snapshot, {}, "human")["peers"].is_empty(), "absent peers preserve the world-only path")
	_check(not QaCombat.strafe_contacts(snapshot, {}, "detached")["error"].is_empty(), "detached local body cannot drive evasion")
	snapshot["players"] = [me.duplicate()]
	snapshot["players"][0]["hp"] = 0
	_check(not QaCombat.strafe_contacts(snapshot, {}, "human")["error"].is_empty(), "dead local body cannot drive evasion")
	snapshot["players"][0]["hp"] = 100
	snapshot["players"][0]["x"] = INF
	_check(not QaCombat.strafe_contacts(snapshot, {}, "human")["error"].is_empty(), "invalid snapshot coordinate refuses speculative movement")

func _check_m06_gallery_contact() -> void:
	var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m06_port_of_entry.json"))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m06_port_of_entry.json"))
	_check(authored is Dictionary and manifest is Dictionary, "actual M06 map and capture route load")
	if not authored is Dictionary or not manifest is Dictionary:
		return
	var solids: Array[Dictionary] = []
	for solid: Dictionary in authored["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2],
			"max_z": solid["max"][2], "bottom": solid["min"][1], "top": solid["max"][1]})
	var arena: Dictionary = {"half": authored["half_extent"], "solids": solids}
	var turret: Dictionary = {}
	for encounter: Dictionary in authored["encounters"]:
		for enemy: Dictionary in encounter["enemies"]:
			if enemy["id"] == "exit_turret":
				turret = ActorContact.stationary("exit_turret", Vector3(enemy["feet"][0], enemy["feet"][1], enemy["feet"][2]))
	var route: Array = []
	for stage: Dictionary in manifest["states"]:
		if stage["name"] == "impound_and_depot_windows":
			route = stage["walk_to"]
	_check(not turret.is_empty() and route.size() >= 15, "gallery regression binds to the actual dormant body and ordinary capture route")
	if turret.is_empty() or route.size() < 15:
		return
	var body: Dictionary = MoveStep.make_state(route[10][0], route[10][2], 0.0)
	body["y"] = route[10][1]
	for index: int in range(11, 15):
		var goal: Vector3 = Vector3(route[index][0], route[index][1], route[index][2])
		body = _walk_gallery_contact(body, goal, turret, arena)
		_check(Vector3(body["x"], body["y"], body["z"]).distance_to(goal) < 0.3,
			"actual supported gallery waypoint remains reachable with the living exit Turret " + str(index))
	var old_start: Dictionary = MoveStep.make_state(18.5, 28.0, 0.0)
	old_start["y"] = 3.0
	var old_end: Dictionary = _walk_gallery_contact(old_start, Vector3(18.5, 3.0, 31.5), turret, arena)
	_check(absf(float(old_end["z"]) - 31.0) < 0.001,
		"the former endpoint is refused at the real summed body radius rather than granting overlap")

func _walk_gallery_contact(start: Dictionary, goal: Vector3, turret: Dictionary, arena: Dictionary) -> Dictionary:
	var body: Dictionary = start.duplicate()
	for _tick: int in range(300):
		var delta: Vector2 = Vector2(goal.x - float(body["x"]), goal.z - float(body["z"]))
		if delta.length() < 0.2:
			break
		var action: Dictionary = MoveStep.make_input(true, false, false, false, atan2(delta.y, delta.x))
		var proposed: Dictionary = MoveStep.live_step(body, action, MoveStep.TOP_SPEED, MoveStep.DT_LIVE, arena)
		var bodies: Array[Dictionary] = [{"key": "human", "from": body, "proposed": proposed,
			"height": MoveStep.BODY_HEIGHT, "radius": MoveStep.RADIUS, "jump": false}, turret]
		body = ActorContact.resolve(bodies, MoveStep.DT_LIVE, arena)[0]
		_check(absf(float(body["y"]) - 3.0) < 0.01,
			"ordinary gallery detour preserves actual support with the shared contact solver")
	return body

func _check_resolved_shots() -> void:
	var observer: QaCombat = QaCombat.new()
	observer._player_id = "self"
	observer._recording = true
	var result: Dictionary = {"shooter_id": "self", "target_id": "removed_target", "hit": true,
		"damage": 100, "killed": true, "trace": {"weapon": "rail", "origin": [-29, 1.6, -11],
		"end": [28.75, 1.6, -11], "impact": {"kind": "fighter", "normal": [-1, 0, 0]}}}
	var snapshot: Dictionary = {"tick": 1, "players": [], "shot_results": [result]}
	observer._observe(snapshot)
	observer._observe(snapshot)
	snapshot["tick"] = 0
	observer._observe(snapshot)
	_check(observer.shots == 1 and observer.resolved_shots.size() == 1
		and observer.resolved_shots[0]["result"] == result,
		"actual resolved trace survives absent shooter/target roster and duplicate or stale ticks")
	result["trace"]["origin"][0] = 0
	_check(observer.resolved_shots[0]["result"]["trace"]["origin"][0] == -29,
		"retained shot evidence cannot be mutated by a later packet")
	for tick: int in range(2, 71):
		snapshot["tick"] = tick
		observer._observe(snapshot)
	_check(observer.shots == 70 and observer.resolved_shots.size() == 64
		and observer.resolved_shots_omitted == 6, "shot retention stays bounded while overflow remains observable")
	observer._recording = false
	snapshot["tick"] = 71
	observer._observe(snapshot)
	_check(observer.shots == 70, "inactive probe cannot collect unrelated later fire")

func _check_jammer_launch() -> void:
	var observer: QaCombat = QaCombat.new()
	observer._player_id = "self"
	observer._kind = "jammer"
	observer._recording = true
	var launch: Dictionary = {"tick":10, "players":[
		{"id":"self", "hp":100},
		{"id":"emitter", "name":"range_jammer", "hp":90, "just_fired":true,
			"campaign":{"side":"union", "kind":"jammer", "phase":"firing"}}
	], "shot_results":[]}
	observer._observe(launch)
	observer._observe(launch)
	_check(observer.enemy_shots == 1 and observer.shots == 0,
		"a server Jammer launch satisfies shot observation once without inventing a gun trace")
	launch["tick"] = 11
	launch["players"][1]["just_fired"] = false
	observer._observe(launch)
	_check(observer.enemy_shots == 1, "a firing pose without a committed launch does not count")
	launch["tick"] = 12
	launch["players"][1]["just_fired"] = true
	observer._observe(launch)
	_check(observer.enemy_shots == 2, "a later pulse remains independently observable")

func _check_m10_route() -> void:
	var tour: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m10_common_carrier.json"))
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m10_common_carrier.json"))
	if not tour is Dictionary or not tour.get("states") is Array or not map is Dictionary or not map.get("encounters") is Array:
		_check(false, "owning M10 route and actual native source must parse")
		return
	_check(TOUR.valid_walks(tour["states"]), "actual M10 route retains strict walking and fact expectations")
	var authored: Array[String] = []
	for group: Dictionary in map["encounters"]:
		for enemy: Dictionary in group["enemies"]:
			authored.append(enemy["id"])
	var required: Array[String] = []
	for state: Dictionary in tour["states"]:
		if state.get("combat") is Dictionary:
			var combat: Dictionary = state["combat"]
			_check(combat.get("target_required_only") == true and combat.get("evade_tells") == true, "ship fights retain bounded targets and real tell defense")
			for guard: String in combat["required"]:
				_check(not required.has(guard), "a guard cannot satisfy two ship probes")
				required.append(guard)
			_check(combat.get("engagement_distance") == (12 if state.get("weapon") == "Scatter" else 35), "ship probes use the actual owned weapon range")
	authored.sort()
	required.sort()
	_check(required == authored and required.size() == 17, "all seventeen original native ship guards remain required exactly once")
	_check(tour["states"].back().get("expect_m10_completed") == ["forward_secured", "service_secured", "aft_secured", "passengers_secured", "party_departed"], "played acceptance still ends with real shared departure")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_qa_combat: " + message)
