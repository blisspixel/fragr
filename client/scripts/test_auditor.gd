extends SceneTree

## Checks the Auditor atlas without a renderer: the bake receipt is fresh, the
## layout matches EnemyAnimation, every pose is visible and unclipped, feet
## share the Clerk's registration, the cap rises above the Clerk's helmet, the
## shield plate faces front and not back, and the seated cell holds a lit
## repair emitter at Level 8's beam height.

const ATLAS: String = "res://assets/characters/union/auditor.png"
const MANIFEST: String = "res://assets/characters/union/auditor-manifest.json"
const AuditorRig = preload("res://art/characters/auditor_rig.gd")
## The plate's inner face colour, STEEL lightened by 0.08 in the rig.
const PLATE_FACE: Color = Color8(61, 62, 66)
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_auditor: " + message)

func _tile(atlas: Image, frame: int) -> Image:
	var at: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
		floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
	return atlas.get_region(Rect2i(at, Vector2i.ONE * EnemyAnimation.TILE))

## Pixels the Union shader keeps full-bright red: here only the emitter.
func _glow(tile: Image) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y: int in range(tile.get_height()):
		for x: int in range(tile.get_width()):
			var c: Color = tile.get_pixel(x, y)
			if c.a > 0.5 and c.r8 > 200 and c.g8 < 90 and c.b8 < 90:
				found.append(Vector2i(x, y))
	return found

func _count(tile: Image, colour: Color) -> int:
	var count: int = 0
	for y: int in range(tile.get_height()):
		for x: int in range(tile.get_width()):
			var c: Color = tile.get_pixel(x, y)
			if c.a > 0.5 and absi(c.r8 - colour.r8) <= 3 and absi(c.g8 - colour.g8) <= 3 and absi(c.b8 - colour.b8) <= 3:
				count += 1
	return count

func _run() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or not manifest.get("sources") is Dictionary:
		_check(false, "bake receipt exists")
		quit(1)
		return
	for source: String in manifest["sources"]:
		_check(FileAccess.get_sha256(source) == manifest["sources"][source], "source matches bake receipt " + source)
	_check(FileAccess.get_sha256(ATLAS) == manifest["sha256"], "atlas matches its bake receipt")
	_check(int(manifest["poses"]) == EnemyAnimation.poses() and int(manifest["directions"]) == EnemyAnimation.DIRECTIONS \
		and int(manifest["columns"]) == EnemyAnimation.COLUMNS and int(manifest["rows"]) == EnemyAnimation.rows(),
		"baked layout matches playback")
	var atlas: Image = (load(ATLAS) as Texture2D).get_image()
	_check(atlas.get_width() == EnemyAnimation.COLUMNS * EnemyAnimation.TILE \
		and atlas.get_height() == EnemyAnimation.rows() * EnemyAnimation.TILE \
		and atlas.get_width() <= 4096 and atlas.get_height() <= 4096, "atlas portable bounds")
	_check(not atlas.has_mipmaps(), "pixel art has no mipmaps")
	for direction: int in range(EnemyAnimation.DIRECTIONS):
		for pose: int in range(EnemyAnimation.poses()):
			var used: Rect2i = _tile(atlas, direction * EnemyAnimation.poses() + pose).get_used_rect()
			_check(used.size != Vector2i.ZERO and used.position.x > 0 and used.position.y > 0 \
				and used.end.x < EnemyAnimation.TILE and used.end.y < EnemyAnimation.TILE,
				"nonempty, unclipped pose %d/%d" % [direction, pose])
	var clerk: Image = (load("res://assets/characters/union/clerk.png") as Texture2D).get_image()
	var idle: int = EnemyAnimation.pose_frame("idle", false, 0.0)
	for direction: int in [0, 2, 4]:
		var frame: int = direction * EnemyAnimation.poses() + idle
		var mine: Rect2i = _tile(atlas, frame).get_used_rect()
		var theirs: Rect2i = _tile(clerk, frame).get_used_rect()
		_check(mine.end.y == theirs.end.y, "feet share the Clerk's registration in direction %d" % direction)
		_check(mine.position.y < theirs.position.y, "the cap rises above the Clerk's helmet in direction %d" % direction)
	var front: int = _count(_tile(atlas, idle), PLATE_FACE)
	var back: int = _count(_tile(atlas, 4 * EnemyAnimation.poses() + idle), PLATE_FACE)
	_check(front > 300 and front > back * 4, "the shield plate faces front and not back: %d front, %d back" % [front, back])
	var channel: int = EnemyAnimation.pose_frame("seated", false, 0.0)
	_check(_glow(_tile(atlas, idle)).is_empty(), "an idle Auditor shows no lit emitter")
	var side: Array[Vector2i] = _glow(_tile(atlas, 2 * EnemyAnimation.poses() + channel))
	_check(side.size() > 6, "the channel lights the emitter in profile")
	if not side.is_empty():
		var mean: float = 0.0
		for point: Vector2i in side:
			mean += point.y
		mean /= side.size()
		var pixels_per_metre: float = EnemyAnimation.TILE / EnemyAnimation.VIEW_SIZE
		var expected: float = EnemyAnimation.TILE * 0.5 - (AuditorRig.EMITTER_HEIGHT - EnemyAnimation.CENTRE_HEIGHT) * pixels_per_metre
		_check(absf(mean - expected) < 8.0, "the emitter sits at the beam's hand height: row %.1f, expected %.1f" % [mean, expected])
	_check(not _glow(_tile(atlas, channel)).is_empty(), "the channel's emitter reads from the front")
	var standing: Rect2i = _tile(atlas, idle).get_used_rect()
	var corpse: Rect2i = _tile(atlas, EnemyAnimation.pose_frame("death", false, 1.0)).get_used_rect()
	_check(corpse.position.y > standing.position.y + 45, "death pixels reach the floor")
	if failures == 0:
		print("test_auditor: PASS fresh receipt, layout, unclipped poses, feet, cap, front plate, channel emitter")
	quit(0 if failures == 0 else 1)
