extends SceneTree

## Bakes the combat effects from code, in palette colours with hard alpha:
## the third-person muzzle flashes, the impact strips by surface, the surface
## marks a shot leaves, and the blast set (fireball, smoke, debris, scorch)
## plus the rocket and grenade skins. Deterministic: every ragged edge, chip
## and droplet comes from a fixed seed. Run from the repository root:
##   godot --headless --path client --script ../tools/bake_shot_vfx.gd
##
## Flashes are 32 pixel squares drawn as radial bursts, because a fighter's
## flash is a billboard and must read from any side. Impacts are one atlas of
## six 32 pixel frames per row, one row per surface, played over the effect's
## lifetime by `ShotVfx`. The fireball is ten 64 pixel frames at about twenty
## texels a metre, close to the world's sixteen, so a blast keeps the same
## chunky pixel scale as the walls it lights.
##
## Colour law: explosions and muzzle fire stay in the ember-to-bone range and
## never use Union red, which is the Union attack tell; muted signal cyan is
## the Inheritance working light, so the Railgun keeps a near-white core with
## only a pale cyan edge.

const CELL: int = 32
const SHOTS_DIR: String = "assets/vfx/shots"
const BLAST_DIR: String = "assets/vfx/blast"

const INK: Color = Color8(10, 10, 12)
const BONE: Color = Color8(232, 226, 214)
const WHITE_HOT: Color = Color8(246, 242, 228)
const GUNMETAL_DARK: Color = Color8(58, 56, 54)
const GUNMETAL: Color = Color8(90, 85, 79)
const GUNMETAL_LIGHT: Color = Color8(140, 132, 122)
const DUST: Color = Color8(176, 166, 150)
const SOOT: Color = Color8(34, 32, 32)
const RUST: Color = Color8(122, 58, 34)
const BLOOD: Color = Color8(110, 18, 24)
const BLOOD_DARK: Color = Color8(72, 14, 18)
const EMBER: Color = Color8(196, 90, 32)
const EMBER_HOT: Color = Color8(220, 140, 60)
const AMBER: Color = Color8(240, 184, 96)
const PURPLE: Color = Color8(58, 42, 72)
const PURPLE_LIGHT: Color = Color8(124, 96, 142)
const RAIL_EDGE: Color = Color8(184, 222, 226)
const RAIL_RIM: Color = Color8(150, 190, 196)
const OLIVE: Color = Color8(102, 108, 77)
const OLIVE_DARK: Color = Color8(72, 78, 56)
const STEEL_UNION: Color = Color8(44, 45, 50)

## Row order in `impacts.png`; `ShotVfx.IMPACT_ROWS` reads the same order.
const IMPACT_KINDS: Array[String] = ["concrete", "metal", "flesh", "synthetic", "rail", "melee", "fabric"]
const IMPACT_FRAMES: int = 6
## Cell order in `marks.png`; `ShotVfx.MARKS` reads the same order.
const MARK_KINDS: Array[String] = ["concrete", "concrete_b", "metal", "metal_b", "rail", "melee"]
const MARK_CELL: int = 16
const FIREBALL_FRAMES: int = 10
const FIREBALL_CELL: int = 64
const SMOKE_FRAMES: int = 6
const DEBRIS_CELL: int = 8

const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

func _initialize() -> void:
	var shots_dir: String = ProjectSettings.globalize_path("res://").path_join(SHOTS_DIR)
	var blast_dir: String = ProjectSettings.globalize_path("res://").path_join(BLAST_DIR)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	DirAccess.make_dir_recursive_absolute(blast_dir)
	var flashes: Dictionary[String, Image] = {
		"tack": _flash_tack(),
		"flechette": _flash_flechette(),
		"repeater": _flash_repeater(),
		"scatter": _flash_scatter(),
		"rail": _flash_rail(),
		"sniper": _flash_sniper(),
		"rocket": _flash_rocket(),
	}
	for weapon: String in flashes:
		if not _save(flashes[weapon], shots_dir.path_join("muzzle_%s.png" % weapon)):
			return
	var atlas: Image = Image.create_empty(CELL * IMPACT_FRAMES, CELL * IMPACT_KINDS.size(), false, Image.FORMAT_RGBA8)
	for row: int in range(IMPACT_KINDS.size()):
		for frame: int in range(IMPACT_FRAMES):
			var cell: Image = _impact(IMPACT_KINDS[row], frame)
			atlas.blit_rect(cell, Rect2i(0, 0, CELL, CELL), Vector2i(frame * CELL, row * CELL))
	if not _save(atlas, shots_dir.path_join("impacts.png")):
		return
	var marks: Image = Image.create_empty(MARK_CELL * MARK_KINDS.size(), MARK_CELL, false, Image.FORMAT_RGBA8)
	for index: int in range(MARK_KINDS.size()):
		marks.blit_rect(_mark(MARK_KINDS[index]), Rect2i(0, 0, MARK_CELL, MARK_CELL), Vector2i(index * MARK_CELL, 0))
	if not _save(marks, shots_dir.path_join("marks.png")):
		return
	var fireball: Image = Image.create_empty(FIREBALL_CELL * FIREBALL_FRAMES, FIREBALL_CELL, false, Image.FORMAT_RGBA8)
	for frame: int in range(FIREBALL_FRAMES):
		fireball.blit_rect(_fireball(frame), Rect2i(0, 0, FIREBALL_CELL, FIREBALL_CELL), Vector2i(frame * FIREBALL_CELL, 0))
	var smoke: Image = Image.create_empty(CELL * SMOKE_FRAMES, CELL, false, Image.FORMAT_RGBA8)
	for frame: int in range(SMOKE_FRAMES):
		smoke.blit_rect(_smoke(frame), Rect2i(0, 0, CELL, CELL), Vector2i(frame * CELL, 0))
	var scorch: Image = Image.create_empty(64 * 2, 64, false, Image.FORMAT_RGBA8)
	for variant: int in range(2):
		scorch.blit_rect(_scorch(variant), Rect2i(0, 0, 64, 64), Vector2i(variant * 64, 0))
	var blast: Dictionary[String, Image] = {
		"fireball": fireball,
		"smoke": smoke,
		"debris": _debris(),
		"scorch": scorch,
		"rocket_skin": _rocket_skin(),
		"rocket_flame": _rocket_flame(),
		"grenade_skin": _grenade_skin(),
		"canister_skin": _canister_skin(),
		"wear": _wear(),
	}
	for name: String in blast:
		if not _save(blast[name], blast_dir.path_join(name + ".png")):
			return
	print("bake_shot_vfx: PASS ", SHOTS_DIR, " ", BLAST_DIR)
	quit(0)

func _save(image: Image, path: String) -> bool:
	if image.save_png(path) != OK:
		push_error("bake_shot_vfx: could not write " + path)
		quit(1)
		return false
	return true

func _blank(size: int = CELL) -> Image:
	var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image

func _put(image: Image, x: int, y: int, colour: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, colour)

## Smooth value noise in [0, 1] from a fixed integer lattice and seed.
func _hash(x: int, y: int, salt: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + salt * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0

func _noise(x: float, y: float, salt: int) -> float:
	var ix: int = floori(x)
	var iy: int = floori(y)
	var fx: float = x - ix
	var fy: float = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = lerpf(_hash(ix, iy, salt), _hash(ix + 1, iy, salt), fx)
	var b: float = lerpf(_hash(ix, iy + 1, salt), _hash(ix + 1, iy + 1, salt), fx)
	return lerpf(a, b, fy)

## A ragged outline offset in [-1, 1] round the circle: noise sampled on a
## ring, so the edge closes on itself with no seam and no star symmetry.
func _rag(angle: float, salt: int, phase: float) -> float:
	return (_noise(cos(angle) * 1.7 + 3.0, sin(angle) * 1.7 + phase, salt) - 0.5) * 2.0

func _bayer(x: int, y: int) -> float:
	return (float(BAYER[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0

## Fills a radial shape: `radius(angle)` gives the edge, and the colour steps
## from core to rim by the fraction of that edge a pixel sits at.
func _burst(image: Image, centre: Vector2, radius: Callable, ramp: Array[Color], steps: Array[float]) -> void:
	var size: int = image.get_width()
	for y: int in range(size):
		for x: int in range(size):
			var offset: Vector2 = Vector2(x + 0.5, y + 0.5) - centre
			var edge: float = radius.call(offset.angle())
			var at: float = offset.length() / maxf(edge, 0.001)
			if at > 1.0:
				continue
			var colour: Color = ramp[ramp.size() - 1]
			for index: int in range(steps.size()):
				if at <= steps[index]:
					colour = ramp[index]
					break
			image.set_pixel(x, y, colour)

## A spike of `length` pixels along `angle`, `width` wide at its root and one
## pixel at its tip, core colour inside and rim colour on its edge.
func _ray(image: Image, centre: Vector2, angle: float, length: float, width: float, core: Color, rim: Color) -> void:
	var direction: Vector2 = Vector2.from_angle(angle)
	var side: Vector2 = direction.orthogonal()
	var step: float = 0.0
	while step <= length:
		var half: float = lerpf(width * 0.5, 0.5, step / length)
		var across: float = -half
		while across <= half:
			var point: Vector2 = centre + direction * step + side * across
			var inner: bool = absf(across) < half - 0.75 and step < length * 0.8
			_put(image, floori(point.x), floori(point.y), core if inner else rim)
			across += 0.5
		step += 0.5

func _disc(image: Image, at: Vector2, radius: float, colour: Color) -> void:
	for y: int in range(floori(at.y - radius - 1), ceili(at.y + radius + 1)):
		for x: int in range(floori(at.x - radius - 1), ceili(at.x + radius + 1)):
			if (Vector2(x + 0.5, y + 0.5) - at).length() <= radius:
				_put(image, x, y, colour)

## Ordered dither: keep a pixel only where `density` beats its Bayer cell.
func _dithered(image: Image, density: float) -> void:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a == 0.0:
				continue
			if density < _bayer(x, y):
				image.set_pixel(x, y, Color(0, 0, 0, 0))

## A streak from `from` to `to`, `head` at the leading end and `tail` behind.
func _streak(image: Image, from: Vector2, to: Vector2, head: Color, tail: Color) -> void:
	var steps: int = maxi(ceili(from.distance_to(to) * 2.0), 1)
	for index: int in range(steps + 1):
		var t: float = float(index) / steps
		var point: Vector2 = from.lerp(to, t)
		_put(image, floori(point.x), floori(point.y), head if t > 0.6 else tail)

# Muzzle flashes ---------------------------------------------------------

func _flash_tack() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	for quarter: int in range(4):
		_ray(image, centre, quarter * PI * 0.5, 9.0, 5.0, EMBER_HOT, EMBER)
		_ray(image, centre, quarter * PI * 0.5 + PI * 0.25, 4.5, 3.0, EMBER_HOT, EMBER)
	_burst(image, centre, func(_a: float) -> float: return 4.2, [BONE, EMBER_HOT, EMBER], [0.55, 0.85, 1.0])
	return image

func _flash_flechette() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	# Eight thin needles, the horizontal pair longest: a narrow, sharp flash.
	for index: int in range(8):
		var angle: float = index * PI * 0.25
		var long: bool = index % 4 == 0
		var length: float = 14.0 if long else (8.0 if index % 2 == 0 else 6.0)
		_ray(image, centre, angle, length, 3.0 if long else 2.0, BONE if long else EMBER_HOT, EMBER)
	_burst(image, centre, func(_a: float) -> float: return 3.6, [BONE, EMBER_HOT], [0.6, 1.0])
	return image

## A three-lobed rotary flash: the barrel cluster throws fire in a trefoil.
func _flash_repeater() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	for lobe: int in range(3):
		var angle: float = lobe * TAU / 3.0 - PI * 0.5
		_ray(image, centre, angle, 12.0, 6.0, EMBER_HOT, EMBER)
		_ray(image, centre, angle + PI / 3.0, 6.0, 3.0, EMBER_HOT, EMBER)
	_burst(image, centre, func(a: float) -> float: return 5.0 + 1.2 * cos(a * 3.0 + PI * 0.5),
		[BONE, EMBER_HOT, EMBER], [0.5, 0.82, 1.0])
	return image

func _flash_scatter() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7301
	# Smoke first, so the fire covers it: dark puffs around the rim.
	for puff: int in range(6):
		var angle: float = puff * TAU / 6.0 + 0.4
		var at: Vector2 = centre + Vector2.from_angle(angle) * 12.0
		_disc(image, at, 2.6, GUNMETAL)
		_disc(image, at + Vector2(-0.8, -0.8), 1.4, GUNMETAL_LIGHT)
	# A wide ragged fireball: lobes from a few summed waves.
	var lobes: Callable = func(angle: float) -> float:
		return 10.5 + 2.2 * sin(angle * 5.0 + 0.6) + 1.4 * sin(angle * 9.0 + 1.9)
	_burst(image, centre, lobes, [BONE, EMBER_HOT, EMBER, RUST], [0.28, 0.58, 0.86, 1.0])
	# Pellet sparks flung clear of the ball.
	for spark: int in range(7):
		var angle: float = rng.randf() * TAU
		var at: Vector2 = centre + Vector2.from_angle(angle) * rng.randf_range(13.0, 15.0)
		_put(image, floori(at.x), floori(at.y), EMBER_HOT)
	return image

## A cold discharge, no fire: a near-white core with four short spokes and a
## thin pale ring. The edge stays pale so it never reads as a cyan lamp.
func _flash_rail() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	for y: int in range(CELL):
		for x: int in range(CELL):
			var distance: float = (Vector2(x + 0.5, y + 0.5) - centre).length()
			if distance >= 10.4 and distance <= 12.0:
				image.set_pixel(x, y, RAIL_EDGE if distance < 11.4 else RAIL_RIM)
	for quarter: int in range(4):
		var angle: float = quarter * PI * 0.5 + PI * 0.25
		_ray(image, centre + Vector2.from_angle(angle) * 7.0, angle, 7.0, 3.0, WHITE_HOT, RAIL_EDGE)
	_burst(image, centre, func(_a: float) -> float: return 6.5, [WHITE_HOT, BONE, RAIL_EDGE], [0.5, 0.82, 1.0])
	return image

func _flash_sniper() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	# A long level jet with two short brake jets: hot, thin and loud.
	_ray(image, centre, 0.0, 15.0, 5.0, BONE, EMBER_HOT)
	_ray(image, centre, PI, 15.0, 5.0, BONE, EMBER_HOT)
	for side: float in [-1.0, 1.0]:
		_ray(image, centre + Vector2(4.0, 0), side * PI * 0.5, 7.0, 3.0, EMBER_HOT, EMBER)
		_ray(image, centre + Vector2(-4.0, 0), side * PI * 0.5, 5.0, 2.0, EMBER_HOT, EMBER)
	_burst(image, centre, func(_a: float) -> float: return 4.0, [BONE, EMBER_HOT, EMBER], [0.6, 0.9, 1.0])
	return image

## A launch: a fat ragged ember ball in a ring of grey backblast smoke.
func _flash_rocket() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	for puff: int in range(8):
		var angle: float = puff * TAU / 8.0 + 0.2
		var at: Vector2 = centre + Vector2.from_angle(angle) * 11.5
		_disc(image, at, 3.2, GUNMETAL)
		_disc(image, at + Vector2(-0.9, -0.9), 1.8, GUNMETAL_LIGHT)
	var lobes: Callable = func(angle: float) -> float:
		return 9.0 + 1.8 * sin(angle * 4.0 + 0.3) + 1.0 * sin(angle * 7.0 + 1.1)
	_burst(image, centre, lobes, [WHITE_HOT, AMBER, EMBER_HOT, EMBER], [0.3, 0.55, 0.8, 1.0])
	return image

# Impacts ----------------------------------------------------------------

func _impact(kind: String, frame: int) -> Image:
	match kind:
		"concrete":
			return _impact_concrete(frame)
		"metal":
			return _impact_metal(frame)
		"flesh":
			return _impact_flesh(frame)
		"synthetic":
			return _impact_synthetic(frame)
		"rail":
			return _impact_rail(frame)
		"fabric":
			return _impact_fabric(frame)
	return _impact_melee(frame)

## Chips flung on a fixed seed: unit directions biased away from the wall
## (up the cell) with a speed spread.
func _chips(salt: int, count: int, spread: float) -> Array[Vector2]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = salt
	var chips: Array[Vector2] = []
	for chip: int in range(count):
		chips.append(Vector2.from_angle(rng.randf_range(-PI * 0.5 - spread, -PI * 0.5 + spread)) * rng.randf_range(0.55, 1.0))
	return chips

## Concrete: a brief pale spark, then a dust plume with grit thrown clear
## that falls and thins out.
func _impact_concrete(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 18)
	var chips: Array[Vector2] = _chips(4410, 9, PI * 0.45)
	if frame == 0:
		for index: int in range(5):
			_ray(image, centre, -PI * 0.5 + (index - 2) * 0.55, 6.0, 2.5, BONE, DUST)
		_disc(image, centre, 2.6, BONE)
		return image
	var radius: float = [0.0, 5.0, 7.5, 9.5, 10.5, 11.0][frame]
	var rise: float = frame * 1.2
	var dust: Callable = func(angle: float) -> float:
		return radius * (1.0 + 0.32 * _rag(angle, 4411, frame * 0.4))
	_burst(image, centre - Vector2(0, rise), dust, [BONE, DUST, GUNMETAL_LIGHT, GUNMETAL],
		[0.2 if frame == 1 else 0.0, 0.5, 0.82, 1.0])
	for chip: Vector2 in chips:
		var at: Vector2 = centre + chip * (5.0 + frame * 3.2) + Vector2(0, frame * frame * 0.55)
		_put(image, floori(at.x), floori(at.y), GUNMETAL_DARK)
		_put(image, floori(at.x) + 1, floori(at.y), DUST if frame < 3 else GUNMETAL)
	if frame >= 3:
		_dithered(image, [1.0, 1.0, 1.0, 0.75, 0.5, 0.28][frame])
	return image

## Metal: a white-hot star, then a fan of sparks with short streaks that arc
## down and burn out, over a thin smoke wisp.
func _impact_metal(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 17)
	var sparks: Array[Vector2] = _chips(6122, 11, PI * 0.7)
	if frame == 0:
		for index: int in range(6):
			var angle: float = index * TAU / 6.0 + 0.26
			_ray(image, centre, angle, 8.0 if index % 2 == 0 else 5.0, 2.5, WHITE_HOT, AMBER)
		_disc(image, centre, 2.4, WHITE_HOT)
		return image
	if frame >= 2:
		var wisp: Callable = func(angle: float) -> float:
			return 2.0 + frame * 1.1 + 0.8 * sin(angle * 4.0 + frame)
		var smoke: Image = _blank()
		_burst(smoke, centre - Vector2(0, frame * 1.5), wisp, [GUNMETAL_LIGHT, GUNMETAL], [0.5, 1.0])
		_dithered(smoke, [0.0, 0.0, 0.6, 0.5, 0.35, 0.2][frame])
		image.blend_rect(smoke, Rect2i(0, 0, CELL, CELL), Vector2i.ZERO)
	if frame == 1:
		_disc(image, centre, 3.0, WHITE_HOT)
		_disc(image, centre, 1.5, BONE)
	for spark: Vector2 in sparks:
		var travel: float = 4.0 + frame * 3.0
		var head: Vector2 = centre + spark * travel + Vector2(0, frame * frame * 0.45)
		var tail: Vector2 = centre + spark * maxf(travel - 3.5, 0.0) + Vector2(0, maxf(frame - 1, 0) * maxf(frame - 1, 0) * 0.45)
		if frame >= 5 and spark.length() < 0.75:
			continue
		var hot: Color = WHITE_HOT if frame <= 2 else (AMBER if frame <= 3 else EMBER_HOT)
		var cool: Color = AMBER if frame <= 2 else EMBER
		_streak(image, tail, head, hot, cool)
	return image

## Flesh: a warm hit flash, then a dark spray of blood and droplets that fall
## and thin into mist. Dried-blood tones only: a body hit never flashes the
## Union's bright red.
func _impact_flesh(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 15)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9127
	var drops: Array[Vector2] = []
	for drop: int in range(12):
		drops.append(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.55, 1.0))
	if frame == 0:
		var splash: Callable = func(angle: float) -> float:
			return 5.5 * (1.0 + 0.35 * _rag(angle, 9128, 0.0))
		_burst(image, centre, splash, [AMBER, EMBER, RUST, BLOOD], [0.25, 0.5, 0.78, 1.0])
		return image
	var core: float = [0.0, 7.0, 7.5, 6.5, 5.0, 3.5][frame]
	var lobes: Callable = func(angle: float) -> float:
		return core * (1.0 + 0.4 * _rag(angle, 9129, frame * 0.3))
	_burst(image, centre + Vector2(0, frame * 0.8), lobes, [RUST, BLOOD, BLOOD_DARK],
		[0.3 if frame <= 2 else 0.0, 0.7, 1.0])
	if frame >= 3:
		_dithered(image, [1.0, 1.0, 1.0, 0.7, 0.5, 0.3][frame])
	for drop: Vector2 in drops:
		var at: Vector2 = centre + drop * (6.5 + frame * 2.8) + Vector2(0, frame * frame * 0.6)
		_put(image, floori(at.x), floori(at.y), RUST if frame <= 2 else BLOOD)
		if frame < 4:
			_put(image, floori(at.x), floori(at.y) + 1, BLOOD_DARK)
	if frame == 1:
		_disc(image, centre, 2.0, EMBER)
	return image

## Fabric: a body hit with Blood off. The same warm hit flash as flesh, then
## a round puff of grey-beige cloth dust and pale lint flung all ways, which
## falls and thins. No red at any frame, and no cyan.
func _impact_fabric(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 15)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7311
	var lint: Array[Vector2] = []
	for fibre: int in range(10):
		lint.append(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.55, 1.0))
	if frame == 0:
		var splash: Callable = func(angle: float) -> float:
			return 5.0 * (1.0 + 0.35 * _rag(angle, 7312, 0.0))
		_burst(image, centre, splash, [WHITE_HOT, AMBER, BONE, DUST], [0.25, 0.5, 0.78, 1.0])
		return image
	var radius: float = [0.0, 6.0, 7.5, 8.5, 9.0, 9.5][frame]
	var puff: Callable = func(angle: float) -> float:
		return radius * (1.0 + 0.3 * _rag(angle, 7313, frame * 0.35))
	_burst(image, centre - Vector2(0, frame * 0.6), puff, [BONE, DUST, GUNMETAL_LIGHT, GUNMETAL],
		[0.25 if frame <= 2 else 0.0, 0.6, 0.86, 1.0])
	if frame >= 2:
		_dithered(image, [1.0, 1.0, 0.9, 0.7, 0.48, 0.26][frame])
	for fibre: Vector2 in lint:
		var at: Vector2 = centre + fibre * (6.0 + frame * 2.6) + Vector2(0, frame * frame * 0.45)
		_put(image, floori(at.x), floori(at.y), BONE if frame <= 2 else DUST)
		if frame < 4:
			_put(image, floori(at.x) + 1, floori(at.y), GUNMETAL_LIGHT)
	if frame == 1:
		_disc(image, centre, 2.0, BONE)
	return image

## Synthetic: an electric white spark burst, plate chips, then dark purple
## oil droplets and a soot puff. No cyan: that light belongs to the
## Inheritance, and a free agent's body does not carry it.
func _impact_synthetic(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	var chips: Array[Vector2] = _chips(5531, 7, PI)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2207
	if frame == 0:
		for index: int in range(8):
			var angle: float = index * PI * 0.25 + 0.2
			_ray(image, centre, angle, 9.0 if index % 2 == 0 else 5.0, 2.0, WHITE_HOT, AMBER)
		_disc(image, centre, 2.8, WHITE_HOT)
		return image
	if frame >= 2:
		var soot: Callable = func(angle: float) -> float:
			return (3.0 + frame * 1.2) * (1.0 + 0.3 * _rag(angle, 5532, frame * 0.4))
		_burst(image, centre - Vector2(0, frame), soot, [GUNMETAL, GUNMETAL_DARK, SOOT], [0.35, 0.75, 1.0])
		_dithered(image, [1.0, 1.0, 0.95, 0.75, 0.5, 0.3][frame])
	else:
		# A crackle: short jagged bolts around a hot core.
		for bolt: int in range(5):
			var angle: float = bolt * TAU / 5.0 + 0.4
			var point: Vector2 = centre
			for step: int in range(4):
				var next: Vector2 = point + Vector2.from_angle(angle + rng.randf_range(-0.7, 0.7)) * 2.4
				_streak(image, point, next, WHITE_HOT, AMBER)
				point = next
		_disc(image, centre, 2.2, BONE)
	for chip: Vector2 in chips:
		var at: Vector2 = centre + chip * (5.0 + frame * 3.0) + Vector2(0, frame * frame * 0.5)
		_put(image, floori(at.x), floori(at.y), GUNMETAL_LIGHT)
		_put(image, floori(at.x) + 1, floori(at.y), GUNMETAL_DARK)
	for drop: int in range(6):
		var direction: Vector2 = Vector2.from_angle(drop * TAU / 6.0 + 0.7)
		var at: Vector2 = centre + direction * (4.0 + frame * 2.2) + Vector2(0, frame * frame * 0.7)
		_put(image, floori(at.x), floori(at.y), PURPLE_LIGHT if frame <= 2 else PURPLE)
		_put(image, floori(at.x), floori(at.y) + 1, PURPLE)
	if frame <= 3:
		for spark: int in range(3):
			var at: Vector2 = centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 11.0)
			_put(image, floori(at.x), floori(at.y), AMBER)
	return image

## The Railgun on any surface: a near-white core in a pale cross, then a thin
## pale ring that widens and breaks up.
func _impact_rail(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	if frame == 0:
		for quarter: int in range(4):
			_ray(image, centre, quarter * PI * 0.5, 11.0, 3.0, WHITE_HOT, RAIL_EDGE)
		_disc(image, centre, 4.5, BONE)
		_disc(image, centre, 2.5, WHITE_HOT)
		return image
	var radius: float = [0.0, 6.0, 8.5, 10.5, 12.5, 14.0][frame]
	var thickness: float = [0.0, 2.8, 2.2, 1.8, 1.4, 1.2][frame]
	for y: int in range(CELL):
		for x: int in range(CELL):
			var distance: float = (Vector2(x + 0.5, y + 0.5) - centre).length()
			if absf(distance - radius) <= thickness * 0.5:
				image.set_pixel(x, y, RAIL_EDGE if frame <= 2 else RAIL_RIM)
	if frame <= 2:
		_disc(image, centre, [0.0, 3.5, 2.0][frame], WHITE_HOT)
	if frame >= 3:
		_disc(image, centre, 1.5, BONE)
		_dithered(image, [1.0, 1.0, 1.0, 0.75, 0.5, 0.3][frame])
	return image

## A short bone smack with speed lines, then a dust puff.
func _impact_melee(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	if frame == 0:
		for index: int in range(6):
			var angle: float = index * TAU / 6.0 + 0.25
			_ray(image, centre + Vector2.from_angle(angle) * 4.0, angle, 6.0, 2.0, BONE, GUNMETAL_LIGHT)
		_disc(image, centre, 2.5, BONE)
		return image
	var radius: float = [0.0, 5.0, 6.5, 7.5, 8.5, 9.0][frame]
	var dust: Callable = func(angle: float) -> float:
		return radius + sin(angle * 3.0 + frame) + 0.6 * sin(angle * 5.0 + 1.0)
	_burst(image, centre, dust, [BONE, GUNMETAL_LIGHT, GUNMETAL], [0.3 if frame == 1 else 0.0, 0.75, 1.0])
	if frame >= 2:
		_dithered(image, [1.0, 1.0, 0.85, 0.65, 0.45, 0.25][frame])
	return image

# Marks ------------------------------------------------------------------

## What a shot leaves on a wall: a chipped pock in concrete, a bright dent
## in steel, a scorched ring from the Railgun. 16 pixels at a quarter metre.
func _mark(kind: String) -> Image:
	var image: Image = _blank(MARK_CELL)
	var centre: Vector2 = Vector2(8, 8)
	var salt: int = 31 + MARK_KINDS.find(kind) * 97
	match kind:
		"concrete", "concrete_b":
			var edge: Callable = func(angle: float) -> float:
				return 4.2 + 1.6 * _noise(angle * 1.6 + 3.0, 0.5, salt)
			_burst(image, centre, edge, [INK, SOOT, GUNMETAL_DARK, DUST], [0.25, 0.45, 0.75, 1.0])
			for chip: int in range(5):
				var at: Vector2 = centre + Vector2.from_angle(_hash(chip, 1, salt) * TAU) * (5.0 + _hash(chip, 2, salt) * 2.0)
				_put(image, floori(at.x), floori(at.y), DUST if chip % 2 == 0 else GUNMETAL_DARK)
		"metal", "metal_b":
			_disc(image, centre, 2.6, SOOT)
			_disc(image, centre, 1.4, INK)
			# A bright scraped crescent on the side the round came from.
			var start: float = _hash(3, 3, salt) * TAU
			for step: int in range(9):
				var angle: float = start + step * 0.24
				var at: Vector2 = centre + Vector2.from_angle(angle) * 3.6
				_put(image, floori(at.x), floori(at.y), BONE if step % 3 != 0 else GUNMETAL_LIGHT)
		"rail":
			for y: int in range(MARK_CELL):
				for x: int in range(MARK_CELL):
					var distance: float = (Vector2(x + 0.5, y + 0.5) - centre).length()
					if distance <= 6.5 and _bayer(x, y) < 1.0 - distance / 7.0:
						image.set_pixel(x, y, SOOT if distance > 2.5 else INK)
			_disc(image, centre, 1.2, GUNMETAL_LIGHT)
		_:
			var scuff: Callable = func(angle: float) -> float:
				return 4.0 + 1.2 * sin(angle * 3.0)
			_burst(image, centre, scuff, [GUNMETAL_DARK, GUNMETAL], [0.6, 1.0])
			_dithered(image, 0.5)
	return image

# Blast ------------------------------------------------------------------

## One fireball frame: a ragged ball whose heat field breaks into lobes as it
## grows, burning from white-hot through amber and ember into rust and smoke,
## then thinning to dithered soot. It rises a little as it cools.
func _fireball(frame: int) -> Image:
	var size: int = FIREBALL_CELL
	var image: Image = _blank(size)
	var t: float = float(frame) / float(FIREBALL_FRAMES - 1)
	var radius: float = [8.0, 15.0, 21.0, 25.0, 27.0, 28.5, 29.0, 29.0, 28.5, 28.0][frame]
	var heat: float = [1.25, 1.2, 1.1, 0.95, 0.8, 0.64, 0.5, 0.36, 0.24, 0.14][frame]
	var density: float = [1.0, 1.0, 1.0, 1.0, 1.0, 0.95, 0.85, 0.7, 0.52, 0.34][frame]
	var centre: Vector2 = Vector2(32, 34 - frame * 0.9)
	for y: int in range(size):
		for x: int in range(size):
			var offset: Vector2 = Vector2(x + 0.5, y + 0.5) - centre
			var angle: float = offset.angle()
			var edge_noise: float = _noise(cos(angle) * 2.2 + 5.0, sin(angle) * 2.2 + frame * 0.35, 77)
			var edge: float = radius * (0.72 + 0.5 * edge_noise)
			var distance: float = offset.length()
			if distance > edge:
				continue
			var turbulence: float = _noise(x * 0.16 + frame * 0.5, y * 0.16 - frame * 0.7, 91)
			var fine: float = _noise(x * 0.4, y * 0.4 + frame, 13)
			var value: float = (1.0 - distance / edge) * heat + (turbulence - 0.5) * 0.55 + (fine - 0.5) * 0.18
			# Hot gas climbs: the lower half cools to smoke first late on.
			value -= maxf(offset.y, 0.0) / radius * t * 0.35
			var colour: Color
			if value > 0.95:
				colour = WHITE_HOT
			elif value > 0.74:
				colour = AMBER
			elif value > 0.54:
				colour = EMBER_HOT
			elif value > 0.36:
				colour = EMBER
			elif value > 0.22:
				colour = RUST
			var smoke: bool = value <= 0.22
			if smoke:
				if frame <= 1:
					colour = EMBER if value > 0.1 else RUST
				else:
					# Lumpy smoke, lit from above: no even grey halo round the fire.
					if frame <= 3 and turbulence > 0.56 - frame * 0.03:
						continue
					var lit: float = offset.normalized().dot(Vector2(-0.55, -0.83)) * distance / edge
					colour = GUNMETAL
					if lit > 0.45:
						colour = GUNMETAL_LIGHT
					elif lit < -0.3 or fine < 0.3:
						colour = GUNMETAL_DARK
					if value < -0.05 and fine < 0.42:
						colour = SOOT
			if smoke and density < 1.0 and density < _bayer(x, y) + (1.0 - distance / edge) * 0.25 * (1.0 - t):
				continue
			if not smoke and frame >= 8 and _bayer(x, y) > 0.75:
				continue
			image.set_pixel(x, y, colour)
	# The first frames throw hot sparks clear of the ball.
	if frame <= 3:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 5150
		for spark: int in range(10):
			var direction: Vector2 = Vector2.from_angle(rng.randf() * TAU)
			var reach: float = radius + 2.0 + rng.randf_range(0.0, 4.0) + frame * 2.0
			var head: Vector2 = Vector2(32, 34) + direction * minf(reach, 31.0)
			var tail: Vector2 = Vector2(32, 34) + direction * minf(reach - 3.0, 30.0)
			_streak(image, tail, head, WHITE_HOT if frame <= 1 else AMBER, EMBER_HOT)
	return image

## One smoke puff frame: a lumpy cluster of billows, each lit on its upper
## side and dark beneath, with soot pockets where billows meet; growing and
## thinning through an ordered dither. No single round ball.
func _smoke(frame: int) -> Image:
	var image: Image = _blank()
	var grow: float = [0.45, 0.62, 0.78, 0.9, 0.97, 1.0][frame]
	var density: float = [1.0, 1.0, 1.0, 0.86, 0.66, 0.44][frame]
	# Billow centres and radii at full size, round the cell's middle.
	var lobes: Array[Vector3] = [Vector3(16, 17, 8.0), Vector3(10.5, 19, 5.5), Vector3(21.5, 19.5, 5.8),
		Vector3(13, 11.5, 5.6), Vector3(20, 12, 5.0)]
	for y: int in range(CELL):
		for x: int in range(CELL):
			var pixel: Vector2 = Vector2(x + 0.5, y + 0.5)
			var best: float = INF
			var shade: float = 0.0
			for index: int in range(lobes.size()):
				var lobe: Vector3 = lobes[index]
				var centre: Vector2 = Vector2(16, 16) + (Vector2(lobe.x, lobe.y) - Vector2(16, 16)) * grow
				var offset: Vector2 = pixel - centre
				var edge: float = lobe.z * grow * (0.85 + 0.3 * _noise(cos(offset.angle()) * 1.5 + index, sin(offset.angle()) * 1.5 + frame * 0.3, 404 + index))
				var at: float = offset.length() / edge
				if at < best:
					best = at
					shade = offset.normalized().dot(Vector2(-0.5, -0.86)) * at
			if best > 1.0:
				continue
			if density < _bayer(x, y) + 0.1 * best:
				continue
			var colour: Color = GUNMETAL
			if shade > 0.35:
				colour = GUNMETAL_LIGHT
			elif shade < -0.4:
				colour = GUNMETAL_DARK
			if best > 0.82 and shade < 0.0:
				colour = SOOT
			image.set_pixel(x, y, colour)
	return image

## Four 8 pixel chunks: concrete, a steel shard, an ember and a soot clot.
func _debris() -> Image:
	var image: Image = Image.create_empty(DEBRIS_CELL * 4, DEBRIS_CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var concrete: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3),
		Vector2i(4, 3), Vector2i(5, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(3, 5)]
	for pixel: Vector2i in concrete:
		image.set_pixelv(pixel, DUST if pixel.y <= 2 or pixel.x <= 2 else GUNMETAL)
	for pixel: Vector2i in [Vector2i(9, 5), Vector2i(10, 4), Vector2i(11, 4), Vector2i(12, 3), Vector2i(13, 2), Vector2i(11, 5), Vector2i(12, 4)]:
		image.set_pixelv(pixel, BONE if pixel.y <= 3 else GUNMETAL_LIGHT)
	for pixel: Vector2i in [Vector2i(19, 3), Vector2i(20, 3), Vector2i(19, 4), Vector2i(20, 4)]:
		image.set_pixelv(pixel, AMBER)
	image.set_pixel(19, 3, WHITE_HOT)
	image.set_pixel(21, 4, EMBER)
	image.set_pixel(18, 4, EMBER)
	for pixel: Vector2i in [Vector2i(26, 2), Vector2i(27, 2), Vector2i(26, 3), Vector2i(27, 3), Vector2i(28, 3), Vector2i(27, 4), Vector2i(28, 4)]:
		image.set_pixelv(pixel, SOOT if pixel.y > 2 else GUNMETAL_DARK)
	return image

## A blast scorch, 64 pixels for about three metres: a soot core, a ragged
## burnt ring with radial streaks dithered out, and ember cracks the decal
## shader cools from hot to rust.
func _scorch(variant: int) -> Image:
	var image: Image = _blank(64)
	var centre: Vector2 = Vector2(32, 32)
	var salt: int = 600 + variant * 41
	for y: int in range(64):
		for x: int in range(64):
			var offset: Vector2 = Vector2(x + 0.5, y + 0.5) - centre
			var distance: float = offset.length()
			var angle: float = offset.angle()
			var streak: float = _noise(angle * 5.0 + 10.0, 0.5, salt)
			var edge: float = 15.0 + 7.0 * _noise(cos(angle) * 2.0 + 4.0, sin(angle) * 2.0, salt) + 9.0 * maxf(streak - 0.55, 0.0) * 2.2
			if distance > edge + 3.0:
				continue
			var at: float = distance / edge
			var density: float = clampf(1.25 - at * 0.95, 0.0, 1.0)
			if density < _bayer(x, y):
				continue
			var colour: Color = SOOT if at < 0.55 else (GUNMETAL_DARK if at < 0.85 else GUNMETAL)
			if at < 0.3:
				colour = INK
			var crack: float = _noise(x * 0.35, y * 0.35, salt + 5)
			if at > 0.12 and at < 0.62 and crack > 0.74:
				colour = EMBER_HOT if crack > 0.82 else EMBER
			image.set_pixel(x, y, colour)
	return image

## The rocket's skin, wrapped once round its body: worn olive drab with a
## bone stencil band, a dark tail ring and a scuffed seam.
func _rocket_skin() -> Image:
	var image: Image = _blank()
	for y: int in range(CELL):
		for x: int in range(CELL):
			var colour: Color = OLIVE if (x / 4) % 2 == 0 else OLIVE.darkened(0.06)
			if x % 8 == 7:
				colour = OLIVE_DARK
			if y >= 6 and y <= 8:
				colour = BONE if (x % 6) != 0 else GUNMETAL_LIGHT
			if y >= 26:
				colour = GUNMETAL_DARK if y < 30 else SOOT
			if _hash(x, y, 71) > 0.93 and y < 26:
				colour = OLIVE_DARK.darkened(0.2)
			image.set_pixel(x, y, colour)
	# Stencil dashes under the band.
	for x: int in range(2, CELL, 8):
		for dx: int in range(3):
			image.set_pixel(x + dx, 12, SOOT)
	return image

## The rocket's exhaust, two flicker frames of 16 pixels.
func _rocket_flame() -> Image:
	var image: Image = Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for frame: int in range(2):
		var cell: Image = _blank(16)
		var lobes: Callable = func(angle: float) -> float:
			return 5.0 + 1.4 * sin(angle * 5.0 + frame * 1.7) + 0.6 * sin(angle * 9.0)
		_burst(cell, Vector2(8, 8), lobes, [WHITE_HOT, AMBER, EMBER_HOT, EMBER], [0.3, 0.55, 0.8, 1.0])
		image.blit_rect(cell, Rect2i(0, 0, 16, 16), Vector2i(frame * 16, 0))
	return image

## A thrown grenade: olive segmented body with a dark band and a bone stripe.
func _grenade_skin() -> Image:
	var image: Image = _blank(16)
	for y: int in range(16):
		for x: int in range(16):
			var colour: Color = Color8(86, 124, 104) if (x + (y / 3)) % 4 != 0 else Color8(64, 96, 80)
			if y % 4 == 3:
				colour = Color8(52, 78, 66)
			if y >= 13:
				colour = GUNMETAL_DARK
			if y == 1:
				colour = BONE
			image.set_pixel(x, y, colour)
	return image

## A neutral wear mask that multiplies a modelled part's colour: near white
## with a darker rim, scattered pits and one scratch.
func _wear() -> Image:
	var image: Image = _blank(16)
	for y: int in range(16):
		for x: int in range(16):
			var value: float = 0.9 + 0.1 * _noise(x * 0.5, y * 0.5, 808)
			if x == 0 or y == 0 or x == 15 or y == 15:
				value = 0.72
			if _hash(x, y, 809) > 0.92:
				value = 0.62
			if x == y + 3 and x > 5 and x < 13:
				value = 1.0
			image.set_pixel(x, y, Color(value, value, value))
	return image

## The Assessor canister: issued khaki shell with its Union seal band.
func _canister_skin() -> Image:
	var image: Image = _blank(16)
	for y: int in range(16):
		for x: int in range(16):
			var colour: Color = Color8(164, 147, 102) if x % 5 != 0 else Color8(136, 122, 84)
			if y >= 7 and y <= 8:
				colour = Color8(140, 26, 30)
			if y == 0 or y == 15:
				colour = STEEL_UNION
			image.set_pixel(x, y, colour)
	return image
