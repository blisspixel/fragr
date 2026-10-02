extends SceneTree

## Checks the Ranged Sweeper atlas without a renderer: the bake receipt is
## fresh, the layout matches EnemyAnimation, every pose is visible and
## unclipped, feet share the Sweeper's registration, the mast rises above the
## Sweeper's head, and the windup glint grows and holds.

const ATLAS: String = "res://assets/characters/union/ranged_sweeper.png"
const MANIFEST: String = "res://assets/characters/union/ranged_sweeper-manifest.json"
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_ranged_sweeper: " + message)

func _tile(atlas: Image, frame: int) -> Image:
	var at: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
		floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
	return atlas.get_region(Rect2i(at, Vector2i.ONE * EnemyAnimation.TILE))

## Pixels the Union shader treats as full-bright red: the glint and optics.
func _glow_pixels(tile: Image) -> int:
	var count: int = 0
	for y: int in range(tile.get_height()):
		for x: int in range(tile.get_width()):
			var c: Color = tile.get_pixel(x, y)
			if c.a > 0.5 and c.r8 > 200 and c.g8 < 90 and c.b8 < 90:
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
	var texture: Texture2D = load(ATLAS)
	var atlas: Image = texture.get_image()
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
	var sweeper: Image = (load("res://assets/characters/union/sweeper.png") as Texture2D).get_image()
	var idle: int = EnemyAnimation.pose_frame("idle", false, 0.0)
	for direction: int in [0, 2, 4]:
		var frame: int = direction * EnemyAnimation.poses() + idle
		var mine: Rect2i = _tile(atlas, frame).get_used_rect()
		var theirs: Rect2i = _tile(sweeper, frame).get_used_rect()
		_check(mine.end.y == theirs.end.y, "feet share the Sweeper's registration in direction %d" % direction)
		_check(mine.position.y < theirs.position.y - 12, "the mast rises above the Sweeper's head in direction %d" % direction)
	var standing: Rect2i = _tile(atlas, idle).get_used_rect()
	var corpse: Rect2i = _tile(atlas, EnemyAnimation.pose_frame("death", false, 1.0)).get_used_rect()
	_check(corpse.position.y > standing.position.y + 45, "death pixels reach the floor")
	var side: int = 2 * EnemyAnimation.poses()
	var aim: Image = _tile(atlas, side + EnemyAnimation.pose_frame("raise", false, 1.0))
	var carbine: Image = _tile(sweeper, side + EnemyAnimation.pose_frame("raise", false, 1.0))
	_check(aim.get_used_rect().end.x > carbine.get_used_rect().end.x + 12, "the precision rifle reaches past the carbine in profile")
	# The rifle rises through the windup, so the star can cross the red visor;
	# count the whole tell and require the held final pose to be the largest.
	var counts: Array[int] = []
	for step: int in range(4):
		counts.append(_glow_pixels(_tile(atlas, EnemyAnimation.pose_frame("raise", false, float(step) / 3.0))))
	_check(counts[3] > counts[0] + 10 and counts[3] == counts.max(),
		"the windup glint grows to its held size: %s" % [counts])
	var held: int = _glow_pixels(_tile(atlas, EnemyAnimation.pose_frame("raise", false, 1.0)))
	var resting: int = _glow_pixels(_tile(atlas, idle))
	_check(held > resting + 20, "a full glint is unmistakable against the idle optics")
	if failures == 0:
		print("test_ranged_sweeper: PASS fresh receipt, layout, unclipped poses, feet, mast, rifle, growing glint")
	quit(0 if failures == 0 else 1)
