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
	var report: Dictionary = {"schema": 2, "first_kill_review": valid, "review": null, "teaching_reviews": []}
	_check(_valid_report(report), "current report preserves the M01 scene slots")
	report["schema"] = 1
	_check(not _valid_report(report), "old report schema is refused")
	report["schema"] = 2
	report["review"] = valid
	_check(not _valid_report(report), "legacy slots cannot overwrite one scene directory")
	_check(_review_directory(valid, 4) == "first_kill", "M01 directory names stay stable")
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
	var overlong: Dictionary = valid.duplicate(true)
	for index: int in range(2, 81):
		var frame: Dictionary = valid["frames"][0].duplicate(true)
		frame["tick"] = 100 + index
		overlong["frames"].append(frame)
	_check(not _valid_review(overlong), "M01 retains its 80-frame bound")

## Native server receipts supply the actual map, body and work wire shapes.
## Reusing them here is a presentation fixture, not a new played trial.
static func _teaching(event: String) -> Dictionary:
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m19_native.json"))
	for sample: Dictionary in native["snapshots"]:
		var frame: Dictionary = sample["message"]
		var packs: Array = frame.get("jetpacks", [])
		var strips: Array = frame.get("paver_strips", [])
		var matches_event: bool = not packs.is_empty() and packs[0]["thrusting"] if event == "jetpack_flight" else \
			not strips.is_empty() and strips[0]["working"] == (event == "paver_work")
		if not matches_event:
			continue
		for player: Dictionary in frame["players"]:
			if player["id"] == packs[0]["player_id"]:
				return {"event": event, "profile": "fixture", "difficulty": "standard", "attempt": 1,
					"view": player, "map_info": native["maps"][sample["map_index"]], "frames": [frame]}
	return {}

func _teaching_validation() -> void:
	for event: String in ["jetpack_flight", "paver_tell", "paver_work"]:
		var valid: Dictionary = _teaching(event)
		_check(_valid_review(valid), event + " accepts native work facts")
		_check(_valid_report({"schema": 2, "teaching_reviews": [valid]}), event + " enters the current report")
		_check(_review_directory(valid, 0) != _review_directory(valid, 1), "repeated " + event + " keeps both windows")
		var missing: Dictionary = valid.duplicate(true)
		missing["frames"][0].erase("jetpacks" if event == "jetpack_flight" else "paver_strips")
		_check(not _valid_review(missing), "teaching frames cannot omit the claimed mechanic")
		var wrong_map: Dictionary = valid.duplicate(true)
		wrong_map["map_info"]["m19"]["jetpack_ceiling"] = 40.0
		_check(not _valid_review(wrong_map), "teaching uses the M19 map boundary")
		var absent: Dictionary = valid.duplicate(true)
		absent["frames"][0]["paver_strips"] = []
		for pack: Dictionary in absent["frames"][0]["jetpacks"]:
			pack["thrusting"] = false
		_check(not _valid_review(absent), event + " cannot claim a missing mechanic")
		var forged: Dictionary = valid.duplicate(true)
		if event == "jetpack_flight":
			forged["frames"][0]["jetpacks"][0]["fuel"] = JetMovement.FUEL_MAX + 1
		else:
			forged["frames"][0]["paver_strips"][0]["half_width"] = 4.0
		_check(not _valid_review(forged), "invalid " + event + " facts fail before rendering")
	var extended: Dictionary = _teaching("jetpack_flight").duplicate(true)
	var first: Dictionary = extended["frames"][0]
	for index: int in range(1, 160):
		var frame: Dictionary = first.duplicate(true)
		frame["tick"] = int(first["tick"]) + index
		extended["frames"].append(frame)
	_check(_valid_review(extended), "teaching permits 160 consecutive snapshots")
	var extra: Dictionary = first.duplicate(true)
	extra["tick"] = int(first["tick"]) + 160
	extended["frames"].append(extra)
	_check(not _valid_review(extended), "teaching refuses more than 160 snapshots")

func _stall_validation() -> void:
	var valid: Dictionary = _teaching("jetpack_flight").duplicate(true)
	valid["event"] = "active_stall"
	valid["active_stall_seconds"] = 10.0
	valid["frames"][0].erase("jetpacks")
	valid["frames"][0].erase("paver_strips")
	_check(_valid_review(valid), "a 10-second active stall needs no invented work mechanic")
	_check(_valid_report({"schema": 2, "teaching_reviews": [valid]}), "active stalls enter the current report")
	_check(_review_directory(valid, 0) != _review_directory(valid, 1), "repeated stalls retain separate windows")
	var missing: Dictionary = valid.duplicate(true)
	missing.erase("active_stall_seconds")
	_check(not _valid_review(missing), "a stall without its active duration is refused")
	for seconds: Variant in [9.99, 0, -1, "10", null, true, NAN, INF]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid["active_stall_seconds"] = seconds
		_check(not _valid_review(invalid), "invalid or below-threshold active stall duration is refused")
	var wrong_map: Dictionary = valid.duplicate(true)
	wrong_map["map_info"] = _review()["map_info"]
	_check(not _valid_review(wrong_map), "active stalls still require an M19 map")
	var missing_viewer: Dictionary = valid.duplicate(true)
	missing_viewer["view"]["id"] = "absent"
	_check(not _valid_review(missing_viewer), "active stall windows require their viewer")
	var discontinuous: Dictionary = valid.duplicate(true)
	var later: Dictionary = valid["frames"][0].duplicate(true)
	later["tick"] = int(later["tick"]) + 2
	discontinuous["frames"].append(later)
	_check(not _valid_review(discontinuous), "active stall windows must remain consecutive")

func _teaching_presentation(arena: Node3D) -> void:
	var fixture: Dictionary = _teaching("paver_tell")
	var works: M19Works = M19Works.new()
	arena.add_child(works)
	works.configure_map(fixture["map_info"])
	_check(works.active(), "native M19 world configures its existing presenter")
	var pawns: Dictionary[String, Node3D] = {}
	var viewer: String = fixture["view"]["id"]
	_step_recorded_work(works, pawns, fixture["frames"][0], viewer)
	_check(works.strips._strips.size() == 1, "recorded preparation actually creates its strip")
	var strip: Dictionary = works.strips._strips.values()[0]
	var material: ShaderMaterial = (strip["bed"] as MeshInstance3D).material_override as ShaderMaterial
	_check(float(material.get_shader_parameter("working")) == 0.0, "preparation retains its non-working shader phase")
	_check((strip["fan"] as MeshInstance3D).mesh.get_surface_count() == 1, "recorded projector fan reaches its bounded strip")
	# A fresh presenter is used because the native work sample is an isolated
	# earlier tick, not a contiguous sequel to the preparation fixture.
	works.clear_map()
	works.configure_map(fixture["map_info"])
	var working: Dictionary = _teaching("paver_work")["frames"][0]
	_step_recorded_work(works, pawns, working, viewer)
	strip = works.strips._strips.values()[0]
	material = (strip["bed"] as MeshInstance3D).material_override as ShaderMaterial
	_check(float(material.get_shader_parameter("working")) == 1.0, "recorded work actually changes the existing strip material")
	var ended: Dictionary = working.duplicate(true)
	ended["tick"] = int(ended["tick"]) + 1
	ended["paver_strips"] = []
	_step_recorded_work(works, pawns, ended, viewer)
	_check(works.strips._strips.is_empty(), "a retired recorded strip is removed")
	works.clear_map()
	works.configure_map(fixture["map_info"])
	var flight: Dictionary = _teaching("jetpack_flight")["frames"][0]
	viewer = str(flight["jetpacks"][0]["player_id"])
	var wearer: Node3D = PAWN.instantiate()
	arena.add_child(wearer)
	pawns[viewer] = wearer
	_step_recorded_work(works, pawns, flight, viewer)
	_check(works._gauge.visible and works._gauge._thrusting, "the recorded local fuel gauge shows actual thrust")
	_check(is_equal_approx(works._gauge._fuel, float(flight["jetpacks"][0]["fuel"]) / JetMovement.FUEL_MAX), "the gauge uses recorded finite fuel")
	var pack: JetpackRig = works._packs[viewer]
	_check(pack.thrusting and pack._flames[0].visible, "the recorded wearer has ordinary thrust flames")
	var clock: float = works.strips._clock
	var heat: float = pack._heat
	for index: int in range(5):
		await process_frame
	_check(works.strips._clock == clock and pack._heat == heat, "render frames cannot advance work or thrust clocks")
	works.queue_free()
	wearer.queue_free()

func _run() -> void:
	_validation()
	_teaching_validation()
	_stall_validation()
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
	await _teaching_presentation(arena)
	arena.queue_free()
	for index: int in range(4):
		await process_frame
	Engine.time_scale = 1.0
	await create_timer(0.1).timeout
	if _failures == 0:
		print("test_review_campaign: PASS")
	quit(0 if _failures == 0 else 1)
