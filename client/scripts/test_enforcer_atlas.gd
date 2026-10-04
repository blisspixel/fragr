extends SceneTree

const ATLAS: String = "res://assets/characters/union/enforcer.png"
const NORMALS: String = "res://assets/characters/union/enforcer_normals.png"
const RECEIPT: String = "res://assets/characters/union/enforcer-manifest.json"
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
	if not receipt is Dictionary or not receipt.get("sources") is Dictionary:
		_check(false, "the independent bake receipt exists")
		quit(1)
		return
	for source: String in receipt["sources"]:
		_check(FileAccess.get_sha256(source) == receipt["sources"][source],
			"source matches actual bake " + source)
	_check(FileAccess.get_sha256(ATLAS) == receipt.get("sha256") and
		FileAccess.get_sha256(NORMALS) == receipt.get("normals_sha256"), "paired outputs match the receipt")
	_check(receipt.get("poses") == EnemyAnimation.poses() and
		receipt.get("directions") == EnemyAnimation.DIRECTIONS, "the existing shared layout stays exact")
	var texture: Texture2D = load(ATLAS) as Texture2D
	var normal_texture: Texture2D = load(NORMALS) as Texture2D
	if texture == null or normal_texture == null:
		_check(false, "both packaged texture resources import")
		quit(1)
		return
	_check(not texture.get_image().has_mipmaps() and not normal_texture.get_image().has_mipmaps(),
		"paired pixel surfaces retain no mipmaps")
	var atlas: Image = texture.get_image()
	var normals: Image = normal_texture.get_image()
	_check(atlas.get_size() == Vector2i(EnemyAnimation.COLUMNS * EnemyAnimation.TILE,
		EnemyAnimation.rows() * EnemyAnimation.TILE) and normals.get_size() == atlas.get_size(),
		"portable paired atlas dimensions match")
	for frame: int in range(EnemyAnimation.poses() * EnemyAnimation.DIRECTIONS):
		var tile: Image = _tile(atlas, frame)
		var normal_tile: Image = _tile(normals, frame)
		var used: Rect2i = tile.get_used_rect()
		_check(used.size != Vector2i.ZERO and used.position.x > 0 and used.position.y > 0 and
			used.end.x < EnemyAnimation.TILE and used.end.y < EnemyAnimation.TILE,
			"actual body cell is visible and unclipped " + str(frame))
		var opaque: int = 0
		var missing: int = 0
		for y: int in range(used.position.y, used.end.y):
			for x: int in range(used.position.x, used.end.x):
				if tile.get_pixel(x, y).a > 0.5:
					opaque += 1
					missing += 1 if normal_tile.get_pixel(x, y).a < 0.5 else 0
		_check(opaque > 20 and missing <= maxi(2, int(opaque * 0.01)),
			"view normals cover the actual posed skin " + str(frame))
	var idle: int = EnemyAnimation.pose_frame("idle", true, 0.0)
	var tell: int = EnemyAnimation.pose_frame("raise", true, 1.0)
	_check(_red(_tile(atlas, tell)) > _red(_tile(atlas, idle)) + 10,
		"the windup visibly lights issued vent slits")
	var moving_normals: int = 0
	var a: Image = _tile(normals, idle)
	var b: Image = _tile(normals, EnemyView.enforcer_charge_frame(0.4, 0))
	for y: int in range(EnemyAnimation.TILE):
		for x: int in range(EnemyAnimation.TILE):
			var c: Color = a.get_pixel(x, y)
			var d: Color = b.get_pixel(x, y)
			if c.a > 0.5 and d.a > 0.5 and Vector3(c.r, c.g, c.b).distance_to(Vector3(d.r, d.g, d.b)) > 0.04:
				moving_normals += 1
	_check(moving_normals > 100, "charge deforms actual view normals")
	var body: Sprite3D = Sprite3D.new()
	var view: EnemyView = EnemyView.new()
	var actor: Dictionary = {"side":"union", "kind":"enforcer", "phase":"charging",
		"phase_started":100, "phase_ends":114}
	view.update({"campaign":actor, "weapon":"Fists"}, 108, body)
	view.advance(0.05, 0.4)
	view.render(body, 0.0, Vector3.RIGHT)
	var material: ShaderMaterial = body.material_override as ShaderMaterial
	_check(body.texture.resource_path == ATLAS and body.frame == EnemyView.enforcer_charge_frame(0.4, 0),
		"actual view uses this role's charge cells, never a Clerk stand-in")
	_check(material != null and material.get_shader_parameter("normals_enabled") == true and
		(material.get_shader_parameter("sprite_normals") as Texture2D).resource_path == NORMALS,
		"actual view supplies paired normals to the shared sprite shader")
	var charge_frame: int = body.frame
	view.advance(50.0, 0.0)
	view.render(body, 0.0, Vector3.RIGHT)
	_check(body.frame == charge_frame, "stale charge cannot locally end or apply contact")
	actor["phase"] = "recovery"
	actor["phase_started"] = 114
	actor["phase_ends"] = 150
	view.update({"campaign":actor, "weapon":"Fists"}, 114, body)
	view.render(body, 0.0, Vector3.RIGHT)
	_check(body.frame == EnemyAnimation.pose_frame("recover", true, 0.0),
		"only accepted recovery facts switch the pose")
	body.free()
	await process_frame
	if _failures == 0:
		print("test_enforcer_atlas: PASS 440 unclipped cells, tell, moving normals and authoritative playback")
	quit(0 if _failures == 0 else 1)

func _tile(atlas: Image, frame: int) -> Image:
	return atlas.get_region(Rect2i(Vector2i(frame % EnemyAnimation.COLUMNS,
		floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE,
		Vector2i.ONE * EnemyAnimation.TILE))

func _red(tile: Image) -> int:
	var count: int = 0
	for y: int in range(tile.get_height()):
		for x: int in range(tile.get_width()):
			var c: Color = tile.get_pixel(x, y)
			count += 1 if c.a > 0.5 and c.r8 > 200 and c.g8 < 90 and c.b8 < 90 else 0
	return count

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_enforcer_atlas: " + message)
