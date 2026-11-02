extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_notary_animation: " + reason)

func _tile(atlas: Image, frame: int) -> Image:
	var at: Vector2i = Vector2i(frame % NotaryAnimation.COLUMNS,
		floori(float(frame) / NotaryAnimation.COLUMNS)) * NotaryAnimation.TILE
	return atlas.get_region(Rect2i(at, Vector2i.ONE * NotaryAnimation.TILE))

func _run() -> void:
	var path: String = "res://assets/characters/union/notary.png"
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/characters/union/notary-manifest.json"))
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
	_check(atlas.get_width() == NotaryAnimation.COLUMNS * NotaryAnimation.TILE \
		and atlas.get_height() == NotaryAnimation.rows() * NotaryAnimation.TILE \
		and atlas.get_width() <= 4096 and atlas.get_height() <= 4096,
		"atlas follows the portable layout")
	_check(not atlas.has_mipmaps(), "nearest pixel atlas has no mipmaps")
	for frame: int in range(NotaryAnimation.poses() * NotaryAnimation.DIRECTIONS):
		var used: Rect2i = _tile(atlas, frame).get_used_rect()
		_check(used.size != Vector2i.ZERO and used.position.x > 0 and used.position.y > 0 \
			and used.end.x < NotaryAnimation.TILE and used.end.y < NotaryAnimation.TILE,
			"all facing and phase frames are visible and unclipped: %d" % frame)
	var idle: Image = _tile(atlas, NotaryAnimation.pose_frame("hover", 0.0))
	var tell: Image = _tile(atlas, NotaryAnimation.pose_frame("windup", 1.0))
	var dead: Image = _tile(atlas, NotaryAnimation.pose_frame("wreck", 1.0))
	_check(tell.get_data() != idle.get_data(), "windup has a distinct bright and wider optic")
	_check(dead.get_data() != idle.get_data(), "settled wreck has its own supported pose")
	var actor: Dictionary = {"side":"union", "kind":"notary", "phase":"windup",
		"phase_started":100, "phase_ends":124}
	_check(NotaryAnimation.frame(actor, 124, 100.0, 0, false) == NotaryAnimation.pose_frame("windup", 1.0),
		"a stale windup holds its last tell instead of predicting a launch")
	actor["phase"] = "dead"
	_check(NotaryAnimation.frame(actor, 500, 100.0, 0, false) < NotaryAnimation.pose_frame("wreck", 0.0),
		"a long fall cannot turn into a wreck before authoritative support")
	_check(NotaryAnimation.frame(actor, 120, 0.0, 7, true) == 7 * NotaryAnimation.poses() \
		+ NotaryAnimation.pose_frame("wreck", 1.0), "corpse settles and respects facing")
	var body: Sprite3D = Sprite3D.new()
	NotaryAnimation.configure_map({"solids":[{"min_x":-1.0,"max_x":1.0,"min_z":-1.0,"max_z":1.0,"bottom":0.0,"top":2.0}]})
	_check(is_equal_approx(NotaryAnimation.support(Vector3(0, 3, 0)), 2.0)
		and is_equal_approx(NotaryAnimation.support(Vector3(0, 1, 0)), 0.0)
		and is_equal_approx(NotaryAnimation.support(Vector3(2, 3, 0)), 0.0),
		"shadow and wreck registration use the actual floor below")
	var view: EnemyView = EnemyView.new()
	actor["phase"] = "windup"
	view.update({"campaign":actor, "weapon":"Tack", "x":0.0, "y":4.5, "z":0.0}, 108, body)
	view.render(body, 0.0, Vector3.RIGHT)
	_check(body.texture.resource_path.ends_with("union/notary.png") \
		and body.hframes == NotaryAnimation.COLUMNS and body.vframes == NotaryAnimation.rows() \
		and is_equal_approx(body.position.y, NotaryAnimation.CENTRE_HEIGHT - EnemyView.CAMERA.FP_SERVER_REFERENCE_Y),
		"the Notary uses its own directional rig at authoritative underside")
	view.advance(0.1, 0.0)
	view.update({"campaign":actor, "weapon":"Tack", "x":0.0, "y":4.5, "z":0.0}, 108, body)
	_check(is_equal_approx(view.elapsed, 0.1), "duplicate snapshots preserve phase presentation time")
	body.free()
	if _failures == 0:
		print("test_notary_animation: PASS")
	quit(0 if _failures == 0 else 1)
