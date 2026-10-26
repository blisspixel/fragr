extends "review_campaign.gd"

## Isolated presentation fixtures. These do not claim earned campaign progress.
var _failures: int = 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_review_campaign: " + message)

static func _actor() -> Dictionary:
	return {"id": "guard", "name": "Guard", "x": 2.0, "y": 1.5, "z": 3.0,
		"yaw": 0.0, "pitch": 0.0, "hp": 100, "weapon": "Tack",
		"campaign": {"side": "union", "kind": "sweeper", "phase": "moving",
			"phase_started": 100, "phase_ends": 120}}

static func _review() -> Dictionary:
	var viewer: Dictionary = {"id": "viewer", "name": "Viewer", "x": 0.0, "y": 1.5,
		"z": 0.0, "yaw": 0.0, "pitch": 0.0, "hp": 100, "weapon": "Tack"}
	return {"event": "first_kill", "view": viewer,
		"map_info": {"map_id": 1, "geometry_version": 2, "half_extent": 32.0, "solids": []},
		"frames": [{"tick": 100, "players": [viewer, _actor()], "shot_results": []},
			{"tick": 101, "players": [viewer, _actor()], "shot_results": []}]}

func _validation() -> void:
	var valid: Dictionary = _review()
	_check(_valid_review(valid), "a bounded scene window is accepted")
	for field: String in ["weapon", "hp", "pitch", "id"]:
		var incomplete: Dictionary = valid.duplicate(true)
		incomplete["frames"][0]["players"][0].erase(field)
		_check(not _valid_review(incomplete), "missing actor " + field + " is refused")
	var bad_map: Dictionary = valid.duplicate(true)
	bad_map["map_info"] = {}
	_check(not _valid_review(bad_map), "invalid map is refused before presenter setup")
	for tick: float in [99.0, 101.5, NAN, INF]:
		var discontinuous: Dictionary = valid.duplicate(true)
		discontinuous["frames"][1]["tick"] = tick
		_check(not _valid_review(discontinuous), "invalid or discontinuous tick is refused")
	var missing_viewer: Dictionary = valid.duplicate(true)
	missing_viewer["frames"][0]["players"].remove_at(0)
	_check(not _valid_review(missing_viewer), "a missing viewing actor is refused")
	var bad_phase: Dictionary = valid.duplicate(true)
	bad_phase["frames"][0]["players"][1]["campaign"]["phase"] = "invented"
	_check(not _valid_review(bad_phase), "invalid campaign actor facts are refused")

func _run() -> void:
	_validation()
	var arena: Node3D = Node3D.new()
	root.add_child(arena)
	_freeze_stage(arena)
	var camera: Camera3D = Camera3D.new()
	arena.add_child(camera)
	camera.make_current()
	var pawn: Node3D = PAWN.instantiate()
	arena.add_child(pawn)
	var data: Dictionary = _actor()
	pawn.call("set_player_data", data["id"], data["name"])
	pawn.position = Vector3(data["x"], data["y"], data["z"])
	_step_pawn(pawn, data, 100)
	data["x"] += 0.2
	data["yaw"] = 0.7
	_step_pawn(pawn, data, 101)
	_check(pawn.position.is_equal_approx(Vector3(data["x"], data["y"], data["z"])), "recorded position is exact")
	_check(is_equal_approx(float(pawn.get("presentation_yaw")), 0.7), "recorded facing does not depend on render speed")
	var enemy: EnemyView = pawn.get("enemy_view") as EnemyView
	_check(enemy.travel >= 0.19, "recorded movement advances the enemy gait")
	var flash_seconds: float = _start_flash(pawn, "Tack")
	_check(flash_seconds == float(ShotVfx.muzzle_look("Tack")["seconds"]), "the ordinary flash lifetime is retained")
	_check(enemy.shot_age == 0.0, "ordinary shot feedback starts the firing pose")
	_check((pawn.get("muzzle") as Sprite3D).visible, "ordinary shot feedback shows the muzzle immediately")
	var shots: ShotEffects = ShotEffects.new()
	arena.add_child(shots)
	shots.ingest(1, [{"shooter_id": "guard", "hit": false, "damage": 0,
		"trace": {"weapon": "tack", "origin": [0.0, 1.6, 0.0], "end": [5.0, 1.6, 0.0], "impact": {"kind": "range"}}}])
	_check(shots.active_count() == 1, "the recorded shot starts its tracer")
	for index: int in range(20):
		await process_frame
	_check(shots.active_count() == 1, "rendering frames do not consume tracer lifetime")
	_check(enemy.shot_age == 0.0, "rendering frames do not consume the firing pose")
	_check((pawn.get("muzzle") as Sprite3D).visible, "wall-clock muzzle timers remain frozen")
	shots.call("_process", STEP)
	_check(shots.active_count() == 1, "a tracer survives the first recorded tick")
	shots.call("_process", STEP)
	_check(shots.active_count() == 0, "a tracer ends after its recorded lifetime")
	_hide_flash(pawn)
	_check(not (pawn.get("muzzle") as Sprite3D).visible, "the recorded clock can end a muzzle flash")
	_check((pawn.get("muzzle_glow") as OmniLight3D).light_energy == 0.0, "expired flash light is cleared")
	arena.queue_free()
	for index: int in range(4):
		await process_frame
	Engine.time_scale = 1.0
	await create_timer(0.1).timeout
	if _failures == 0:
		print("test_review_campaign: PASS")
	quit(0 if _failures == 0 else 1)
