extends SceneTree

## Ranged Sweeper and Sniper Rifle presentation: the server windup drives the
## glint and its cue, and the scope stays presentation over the delivered
## plate. The marksman atlas has its own harness.
var _failures: int = 0

func _initialize() -> void:
	root.set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_ranged_sweeper_tell: " + message)

func _actor(id: String, kind: String, phase: String, started: float, ends: float, x: float = 0.0) -> Dictionary:
	return {"id": id, "name": "Rim", "x": x, "y": 4.5, "z": 0.0, "yaw": 0.0, "hp": 70,
		"weapon": "Sniper", "just_fired": false,
		"campaign": {"side": "union", "kind": kind, "phase": phase, "phase_started": started, "phase_ends": ends}}

func _run() -> void:
	_check_tell()
	await _check_audio()
	_check_scope()
	_check_assets()
	if _failures == 0:
		print("test_ranged_sweeper_tell: PASS glint from windup, one cue per windup, presentation scope over the delivered plate and the level 7 table")
	quit(0 if _failures == 0 else 1)

func _check_tell() -> void:
	var windup: Dictionary = _actor("a", "ranged_sweeper", "windup", 100.0, 130.0)["campaign"]
	_check(RangedSweeperTell.windup_age(windup, 99, 0.0) < 0.0, "no glint before the server starts the windup")
	_check(is_equal_approx(RangedSweeperTell.windup_age(windup, 100, 0.0), 0.0), "the glint starts on the first windup tick")
	_check(is_equal_approx(RangedSweeperTell.windup_age(windup, 110, 0.5), 0.5 + RangedSweeperTell.MAX_EXTRAPOLATION), "extrapolation is bounded")
	for phase: String in ["idle", "recovery", "firing", "hit", "dead"]:
		var other: Dictionary = windup.duplicate(true)
		other["phase"] = phase
		_check(RangedSweeperTell.windup_age(other, 110, 0.0) < 0.0, "no glint during " + phase)
	var malformed: Dictionary = windup.duplicate(true)
	malformed["phase_started"] = "100"
	_check(RangedSweeperTell.windup_age(malformed, 110, 0.0) < 0.0, "a malformed start is not a glint")
	var tell: RangedSweeperTell = RangedSweeperTell.new()
	root.add_child(tell)
	tell.present(windup, 100, 0.0)
	_check(tell.sprite.visible and not tell.holding and is_equal_approx(tell.sprite.pixel_size, RangedSweeperTell.FLASH_SIZE), "the opening flash is the largest frame")
	tell.present(windup, 110, 0.0)
	_check(tell.sprite.visible and tell.holding and tell.sprite.pixel_size < RangedSweeperTell.FLASH_SIZE, "the hold keeps a smaller steady shine")
	var recovered: Dictionary = windup.duplicate(true)
	recovered["phase"] = "recovery"
	tell.present(recovered, 131, 0.0)
	_check(not tell.sprite.visible, "the glint ends with the windup")
	_check(tell.sprite.fixed_size and tell.sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "the glint keeps a readable screen size across the cut")
	tell.queue_free()

func _check_audio() -> void:
	var audio: RangedSweeperAudio = RangedSweeperAudio.new()
	root.add_child(audio)
	await process_frame
	var listener: Vector3 = Vector3(0, 1.6, 0)
	var first: Dictionary = {"tick": 101, "players": [_actor("a", "ranged_sweeper", "windup", 100.0, 130.0, 70.0),
		_actor("b", "sweeper", "windup", 100.0, 114.0, 10.0)]}
	_check(audio.apply(first, listener) == 1, "one cue for one marksman windup, none for a Sweeper")
	var again: Dictionary = first.duplicate(true)
	again["tick"] = 102
	_check(audio.apply(again, listener) == 0, "a held windup is not cued twice")
	_check(audio.apply(first, listener) == 0, "stale snapshots are ignored")
	var next: Dictionary = {"tick": 160, "players": [_actor("a", "ranged_sweeper", "windup", 155.0, 185.0, 70.0)]}
	_check(audio.apply(next, listener) == 1, "the next windup is cued again")
	var far: Dictionary = {"tick": 200, "players": [_actor("c", "ranged_sweeper", "windup", 199.0, 229.0, RangedSweeperAudio.DISTANCE + 5.0)]}
	_check(audio.apply(far, listener) == 0 and audio.cue_count == 2, "beyond hearing distance nothing plays")
	var bad: Dictionary = {"tick": 300, "players": [_actor("", "ranged_sweeper", "windup", 299.0, 329.0)]}
	_check(audio.apply(bad, listener) == 0, "an empty identity is ignored")
	audio.reset()
	_check(audio.apply(first, listener) == 1, "map changes reset cue memory")
	audio.queue_free()

func _check_scope() -> void:
	var scope: SniperScope = SniperScope.new()
	root.add_child(scope)
	_check(is_equal_approx(scope.update_scope(1.0, "sniper", false, true), 1.0) and not scope.visible, "unheld scope keeps the open view")
	var factor: float = scope.update_scope(1.0, "sniper", true, true)
	_check(is_equal_approx(factor, L07Assets.SCOPE_FOV_FACTOR) and scope.visible and scope.scoped(), "held with the Sniper Rifle, the view narrows behind the overlay")
	_check(is_equal_approx(scope.update_scope(1.0, "rail", true, true), 1.0), "the Railgun has no scope")
	scope.update_scope(1.0, "sniper", true, true)
	_check(is_equal_approx(scope.update_scope(0.0, "sniper", true, false), 1.0) and not scope.visible, "death or a lost view closes the scope at once")
	scope.update_scope(1.0, "sniper", true, true)
	var halfway: float = scope.update_scope(L07Assets.SCOPE_SETTLE_SECONDS * 0.25, "sniper", false, true)
	_check(halfway > L07Assets.SCOPE_FOV_FACTOR and halfway < 1.0, "the scope settles out over a short time")
	scope.layout(Vector2(1280, 720))
	_check(scope.aperture.size == Vector2(720, 720) and is_equal_approx(scope.aperture.position.x, 280.0), "the aperture is a centred square as tall as the view")
	scope.queue_free()

func _check_assets() -> void:
	for path: String in [L07Assets.SNIPER_FIRE_SOUND, L07Assets.SNIPER_HIT_SOUND, L07Assets.RANGED_SWEEPER_ATLAS,
			L07Assets.RANGED_SWEEPER_TELL_SOUND]:
		_check(ResourceLoader.exists(path), "level 7 table entry loads: " + path)
	_check(EnemyView.atlas_path("ranged_sweeper") == L07Assets.RANGED_SWEEPER_ATLAS, "the marksman atlas comes from the level 7 table")
	_check(EnemyView.atlas_path("sweeper") == "res://assets/characters/union/sweeper.png", "other kinds keep their paths")
	for table: Dictionary in [WeaponArt.IDLE, WeaponArt.FIRE, WeaponArt.PROFILE]:
		_check(table.has("Sniper"), "the Sniper Rifle has its delivered frames and profile")
	var plate: Image = WeaponArt.SCOPE_OVERLAY.get_image()
	_check(plate != null and plate.get_width() == plate.get_height(), "the scope plate is square")
	if plate != null and not plate.is_empty():
		var centre: int = plate.get_width() / 2
		_check(plate.get_pixel(2, 2).a > 0.99 and plate.get_pixel(centre + 30, centre + 60).a < 0.01, "an opaque surround around a clear aperture")
