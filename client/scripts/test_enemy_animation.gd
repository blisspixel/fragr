extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("run")

func run() -> void:
	# Cardinal views prove both the server convention and the baked rotation order.
	_check(EnemyAnimation.direction(0.0, Vector3.RIGHT) == 0, "front view")
	_check(EnemyAnimation.direction(0.0, Vector3.BACK) == 2, "left profile")
	_check(EnemyAnimation.direction(0.0, Vector3.LEFT) == 4, "back view")
	_check(EnemyAnimation.direction(0.0, Vector3.FORWARD) == 6, "right profile")
	_check(EnemyAnimation.direction(PI * 0.5, Vector3.BACK) == 0, "rotated actor front")
	_check(EnemyAnimation.direction(TAU * 3.0, Vector3.RIGHT) == 0, "wrapped yaw")
	_check(EnemyAnimation.direction(0.0, Vector3.UP) == 0, "overhead fallback")
	var actor: Dictionary = {"side":"union", "kind":"clerk", "phase":"windup", "phase_started":100, "phase_ends":112}
	var initial: int = EnemyAnimation.frame(actor, "Tack", 100, 0, 0, INF, 0)
	var raised: int = EnemyAnimation.frame(actor, "Tack", 111, 0.05, 0, INF, 0)
	_check(initial != raised, "windup actually raises the weapon")
	_check(EnemyAnimation.frame(actor, "Tack", 112, 50, 0, INF, 0) == raised,
		"stale windup cannot locally turn into a shot")
	_check(EnemyAnimation.frame(actor, "Tack", 100, 50, 0, INF, 0) ==
		EnemyAnimation.frame(actor, "Tack", 100, 0.1, 0, INF, 0), "bounded extrapolation")
	actor["phase"] = "firing"
	var fire: int = EnemyAnimation.frame(actor, "Tack", 112, 0, 0, 0, 0)
	_check(fire != EnemyAnimation.frame(actor, "Tack", 112, 0, 0, INF, 0),
		"only a resolved shot starts recoil")
	_check(fire != EnemyAnimation.frame(actor, "Fists", 112, 0, 0, 0, 0),
		"melee has its own unarmed strike")
	actor["phase"] = "hit"
	_check(EnemyAnimation.frame(actor, "Tack", 112, 0, 0, 0, 0) ==
		EnemyAnimation.frame(actor, "Tack", 112, 0, 0, INF, 0), "pain overrides a concurrent shot")
	actor["phase"] = "dead"
	actor["phase_started"] = 112
	actor["phase_ends"] = 152
	var collapsed: int = EnemyAnimation.frame(actor, "Tack", 127, 0, 0, INF, 0)
	_check(collapsed != EnemyAnimation.frame(actor, "Tack", 112, 0, 0, INF, 0), "death collapses")
	_check(collapsed == EnemyAnimation.frame(actor, "Tack", 149, 0, 0, 0, 0), "late corpse stays down")
	_check(collapsed != EnemyAnimation.frame(actor, "Fists", 149, 0, 0, 0, 0), "unarmed corpse has no gun")

	var body: Sprite3D = Sprite3D.new()
	var view: EnemyView = EnemyView.new()
	actor["phase"] = "moving"
	var state: Dictionary = {"campaign":actor, "weapon":"Tack"}
	view.update(state, 200, body)
	view.advance(0.05, 0.2)
	_check(is_equal_approx(view.travel, 0.2), "gait follows actual movement")
	view.update(state, 200, body)
	_check(is_equal_approx(view.elapsed, 0.05), "duplicate snapshot does not reset presentation time")
	view.advance(0.1, 20.0)
	_check(is_equal_approx(view.travel, 0.2), "teleport does not walk")
	actor["phase"] = "dead"
	view.advance(0.1, 0.2)
	_check(is_equal_approx(view.travel, 0.2), "corpse correction does not walk")
	_check(is_equal_approx(body.position.y, -0.6) and is_equal_approx(body.pixel_size, 3.0/160.0),
		"body is registered to server feet with fixed physical scale")
	body.free()
	await _check_pawn()
	_check_atlases()
	if _failures == 0:
		print("test_enemy_animation: PASS")
	quit(0 if _failures == 0 else 1)

func _check_pawn() -> void:
	var scene: PackedScene = load("res://scenes/player.tscn")
	var pawn: Node3D = scene.instantiate()
	root.add_child(pawn)
	pawn.set_process(false)
	pawn.set_player_data("guard", "Unrelated callsign")
	var state: Dictionary = {"id":"guard", "x":0.0, "y":1.5, "z":0.0,
		"yaw":0.0, "hp":60, "weapon":"Tack", "campaign":{
			"side":"union", "kind":"clerk", "phase":"windup", "phase_started":100, "phase_ends":112}}
	pawn.update_state(state, 111)
	pawn._process(0.05)
	var body: Sprite3D = pawn.get_node("Body")
	_check(body.texture.resource_path.ends_with("union/clerk.png"), "typed identity chooses the body")
	_check(body.frame == EnemyAnimation.pose_frame("raise", false, 1.0), "pawn actually renders the tell")
	_check(not pawn.get_node("Body/WeaponSprite").visible, "no duplicate floating inventory icon")
	pawn.broadcast_scale_enabled = true
	pawn.hit_flash_timer = 0.2
	pawn._process(0.05)
	_check(body.scale == Vector3.ONE, "damage and broadcast modes cannot inflate campaign hit silhouettes")
	state["hp"] = 0
	state["campaign"]["phase"] = "dead"
	state["campaign"]["phase_started"] = 112
	state["campaign"]["phase_ends"] = 152
	pawn.update_state(state, 128)
	pawn._process(0.05)
	_check(body.frame == EnemyAnimation.pose_frame("death", false, 1.0), "pawn actually settles a late corpse")
	pawn.queue_free()
	await process_frame

func _check_atlases() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/union/manifest.json"))
	if not manifest is Dictionary or not manifest.get("sources") is Dictionary or not manifest.get("entries") is Array:
		_check(false, "bake manifest must describe its sources and outputs")
		return
	for source: String in manifest["sources"]:
		_check(FileAccess.get_sha256(source) == manifest["sources"][source], "rebake changed source " + source)
	for entry: Dictionary in manifest["entries"]:
		_check(FileAccess.get_sha256("res://assets/characters/union/" + str(entry["file"])) == entry["sha256"],
			"atlas matches its bake receipt")
	_check(int(manifest["poses"]) == EnemyAnimation.poses() and int(manifest["directions"]) == EnemyAnimation.DIRECTIONS,
		"baked layout matches playback")
	for kind: String in ["clerk", "sweeper"]:
		var texture: Texture2D = load("res://assets/characters/union/%s.png" % kind)
		var atlas: Image = texture.get_image()
		_check(atlas.get_width() == EnemyAnimation.COLUMNS * EnemyAnimation.TILE \
			and atlas.get_height() == EnemyAnimation.rows() * EnemyAnimation.TILE, kind + " atlas dimensions")
		_check(atlas.get_width() <= 4096 and atlas.get_height() <= 4096, "portable texture bounds")
		_check(not atlas.has_mipmaps(), "pixel art has no mipmaps")
		for direction: int in range(EnemyAnimation.DIRECTIONS):
			for pose: int in range(EnemyAnimation.poses()):
				var frame: int = direction * EnemyAnimation.poses() + pose
				var at: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
					floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
				var tile: Image = atlas.get_region(Rect2i(at, Vector2i.ONE * EnemyAnimation.TILE))
				var used: Rect2i = tile.get_used_rect()
				_check(used.size != Vector2i.ZERO and used.position.x > 0 and used.position.y > 0 \
					and used.end.x < EnemyAnimation.TILE and used.end.y < EnemyAnimation.TILE,
					"nonempty, unclipped pose %s/%d" % [kind, frame])
		# Check content, not merely atlas indices: collapsed and walking tiles must
		# differ in pixels, and a corpse must actually sit lower in its fixed cell.
		var standing: Image = _tile(atlas, EnemyAnimation.pose_frame("idle", false, 0))
		var corpse: Image = _tile(atlas, EnemyAnimation.pose_frame("death", false, 1))
		_check(corpse.get_used_rect().position.y > standing.get_used_rect().position.y + 45,
			kind + " death pixels reach the floor")
		var step_a: Image = _tile(atlas, EnemyAnimation.pose_frame("walk", false, 0))
		var step_b: Image = _tile(atlas, EnemyAnimation.pose_frame("walk", false, 0.5))
		_check(step_a.get_data() != step_b.get_data(), kind + " has distinct gait poses")

func _tile(atlas: Image, frame: int) -> Image:
	var at: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
		floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
	return atlas.get_region(Rect2i(at, Vector2i.ONE * EnemyAnimation.TILE))

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_enemy_animation: " + message)
