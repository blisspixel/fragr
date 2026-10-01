extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_jammer_animation: " + reason)

func _tile(atlas: Image, frame: int) -> Image:
	var at: Vector2i = Vector2i(frame % JammerAnimation.COLUMNS,
		floori(float(frame) / JammerAnimation.COLUMNS)) * JammerAnimation.TILE
	return atlas.get_region(Rect2i(at, Vector2i.ONE * JammerAnimation.TILE))

func _run() -> void:
	var path: String = "res://assets/characters/union/jammer.png"
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/characters/union/jammer-manifest.json"))
	if not receipt is Dictionary or not receipt.get("sources") is Dictionary:
		_check(false, "the original rig has a bake receipt")
		quit(1)
		return
	for source: String in receipt["sources"]:
		_check(FileAccess.get_sha256(source) == receipt["sources"][source],
			"baked source is current: " + source)
	_check(FileAccess.get_sha256(path) == receipt.get("sha256"), "atlas matches its receipt")
	var atlas: Image = Image.new()
	_check(atlas.load(ProjectSettings.globalize_path(path)) == OK, "atlas loads")
	_check(atlas.get_width() == JammerAnimation.COLUMNS * JammerAnimation.TILE \
		and atlas.get_height() == JammerAnimation.rows() * JammerAnimation.TILE \
		and atlas.get_width() <= 4096 and atlas.get_height() <= 4096,
		"atlas follows the portable layout")
	_check(not atlas.has_mipmaps(), "nearest pixel atlas has no mipmaps")
	for frame: int in range(JammerAnimation.poses() * JammerAnimation.DIRECTIONS):
		var used: Rect2i = _tile(atlas, frame).get_used_rect()
		_check(used.size != Vector2i.ZERO and used.position.x > 0 and used.position.y > 0 \
			and used.end.x < JammerAnimation.TILE and used.end.y < JammerAnimation.TILE,
			"all facing and phase frames are visible and unclipped: %d" % frame)
	var idle: Image = _tile(atlas, JammerAnimation.pose_frame("idle", 0.0))
	var tell: Image = _tile(atlas, JammerAnimation.pose_frame("unfold", 1.0))
	var dead: Image = _tile(atlas, JammerAnimation.pose_frame("death", 1.0))
	_check(tell.get_used_rect().size.x > idle.get_used_rect().size.x + 12,
		"the unfolding dish changes its silhouette beyond optic color")
	_check(dead.get_used_rect().position.y > idle.get_used_rect().position.y + 25,
		"the broken transmitter settles toward its fixed feet")
	var actor: Dictionary = {"side":"union", "kind":"jammer", "phase":"windup",
		"phase_started":100, "phase_ends":124}
	_check(JammerAnimation.frame(actor, 124, 100.0, 0) == JammerAnimation.pose_frame("unfold", 1.0),
		"a stale windup holds its last tell instead of predicting a launch")
	actor["phase"] = "dead"
	_check(JammerAnimation.frame(actor, 120, 0.0, 7) == 7 * JammerAnimation.poses() \
		+ JammerAnimation.pose_frame("death", 1.0), "corpse settles and respects facing")
	var body: Sprite3D = Sprite3D.new()
	var view: EnemyView = EnemyView.new()
	actor["phase"] = "windup"
	view.update({"campaign":actor, "weapon":"Fists"}, 108, body)
	view.render(body, 0.0, Vector3.RIGHT)
	_check(body.texture.resource_path.ends_with("union/jammer.png") \
		and body.hframes == JammerAnimation.COLUMNS and body.vframes == JammerAnimation.rows() \
		and is_equal_approx(body.position.y, JammerAnimation.CENTRE_HEIGHT - EnemyView.CAMERA.FP_SERVER_REFERENCE_Y),
		"the Jammer uses its own directional rig at authoritative feet")
	view.advance(0.1, 0.0)
	view.update({"campaign":actor, "weapon":"Fists"}, 108, body)
	_check(is_equal_approx(view.elapsed, 0.1), "duplicate snapshots preserve phase presentation time")
	body.free()
	if _failures == 0:
		print("test_jammer_animation: PASS")
	quit(0 if _failures == 0 else 1)
