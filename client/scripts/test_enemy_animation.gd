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
	var turret: Dictionary = {"side":"union", "kind":"turret", "phase":"moving", "phase_started":100, "phase_ends":100}
	_check(EnemyAnimation.frame(turret, "Rail", 100, 0, 0, INF, 0) != EnemyAnimation.frame(turret, "Rail", 108, 0, 0, INF, 0),
		"a fixed turret traverses on phase time without travel")
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
	for kind: String in ActorState.KINDS:
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
	_check_readable_pair()
	_check_heavy_and_turret_outlines()

func _check_readable_pair() -> void:
	var clerk: Image = _atlas("clerk")
	var sweeper: Image = _atlas("sweeper")
	var clerk_idle: Dictionary = _occupancy(_tile(clerk, EnemyAnimation.pose_frame("idle", false, 0.0)))
	var sweeper_idle: Dictionary = _occupancy(_tile(sweeper, EnemyAnimation.pose_frame("idle", false, 0.0)))
	var clerk_raise: Dictionary = _occupancy(_tile(clerk, EnemyAnimation.pose_frame("raise", false, 1.0)))
	var sweeper_raise: Dictionary = _occupancy(_tile(sweeper, EnemyAnimation.pose_frame("raise", false, 1.0)))
	_check(sweeper_idle["width"] >= int(clerk_idle["width"]) + 10, "the sweeper is wider than the clerk at rest")
	_check(_difference(clerk_idle, sweeper_idle) >= 0.22, "resting outlines do not share one shape")
	_check(_difference(clerk_raise, sweeper_raise) >= 0.22, "attack poses do not share one shape")
	_check(int(clerk_raise["width"]) >= int(clerk_idle["width"]) + 6, "the clerk's aim clears the shoulder")
	_check(absi(int(sweeper_raise["width"]) - int(sweeper_idle["width"])) <= 2, "the sweeper's rifle stays inside the shoulders")
	_check(int(sweeper_raise["width"]) >= int(clerk_raise["width"]) + 8, "the sweeper stays broader while firing")

## At 30 metres, a 720p view with the default 75 degree vertical field of view
## draws about 15.6 pixels per metre. A 160 pixel, three metre tile is then
## about 47 pixels. Outlines must still differ at that size.
const FAR_TILE: int = 47

func _check_heavy_and_turret_outlines() -> void:
	var outlines: Dictionary[String, Dictionary] = {}
	var far: Dictionary[String, Dictionary] = {}
	for kind: String in ActorState.KINDS:
		var atlas: Image = _atlas(kind)
		for action: String in ["idle", "raise"]:
			var tile: Image = _tile(atlas, EnemyAnimation.pose_frame(action, false, 1.0))
			outlines[kind + "_" + action] = _occupancy(tile)
			var small: Image = tile.duplicate()
			small.resize(FAR_TILE, FAR_TILE, Image.INTERPOLATE_BILINEAR)
			far[kind + "_" + action] = _occupancy(small, FAR_TILE)
	var heavy: Dictionary = outlines["heavy_sweeper_idle"]
	print("test_enemy_animation: widths clerk %d sweeper %d heavy %d turret %d" % [
		outlines["clerk_idle"]["width"], outlines["sweeper_idle"]["width"], heavy["width"], outlines["turret_idle"]["width"]])
	_check(int(heavy["width"]) >= int(outlines["sweeper_idle"]["width"]) + 10, "the heavy is broader than the sweeper")
	_check(int(heavy["top"]) <= int(outlines["sweeper_idle"]["top"]) + 6, "the heavy is not a shorter sweeper")
	var tell: float = _difference(heavy, outlines["heavy_sweeper_raise"])
	print("test_enemy_animation: heavy tell changes %.3f of its outline" % tell)
	_check(tell >= 0.15, "the heavy's tell changes its outline, not only its lamps")
	for kind: String in ["heavy_sweeper", "turret"]:
		for other: String in ActorState.KINDS:
			if other == kind or (kind == "turret" and other == "heavy_sweeper"):
				continue
			for action: String in ["idle", "raise"]:
				var near_difference: float = _difference(outlines[kind + "_" + action], outlines[other + "_" + action])
				var far_difference: float = _difference(far[kind + "_" + action], far[other + "_" + action])
				print("test_enemy_animation: %s vs %s %s near %.3f far %.3f" % [kind, other, action, near_difference, far_difference])
				_check(near_difference >= 0.22, "%s and %s %s outlines differ" % [kind, other, action])
				_check(far_difference >= 0.22, "%s and %s %s outlines differ at 30 metres" % [kind, other, action])

func _atlas(kind: String) -> Image:
	var image: Image = Image.new()
	var path: String = ProjectSettings.globalize_path("res://assets/characters/union/%s.png" % kind)
	if image.load(path) != OK:
		_check(false, "could not read " + kind + " atlas")
	return image

func _occupancy(tile: Image, size: int = EnemyAnimation.TILE) -> Dictionary:
	var count: int = size * size
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(count)
	var min_x: int = size
	var min_y: int = size
	var max_x: int = 0
	var max_y: int = 0
	var filled: int = 0
	for y: int in range(size):
		for x: int in range(size):
			if tile.get_pixel(x, y).a <= 0.2:
				continue
			mask[y * size + x] = 1
			filled += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return {"mask": mask, "filled": filled, "width": max_x - min_x, "top": min_y}

func _difference(left: Dictionary, right: Dictionary) -> float:
	var either: int = 0
	var both: int = 0
	var a: PackedByteArray = left["mask"]
	var b: PackedByteArray = right["mask"]
	for index: int in range(a.size()):
		var on_a: bool = a[index] == 1
		var on_b: bool = b[index] == 1
		if on_a or on_b:
			either += 1
		if on_a and on_b:
			both += 1
	if either == 0:
		return 0.0
	return 1.0 - float(both) / float(either)

func _tile(atlas: Image, frame: int) -> Image:
	var at: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
		floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
	return atlas.get_region(Rect2i(at, Vector2i.ONE * EnemyAnimation.TILE))

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_enemy_animation: " + message)
