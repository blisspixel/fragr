extends SceneTree

## Bakes the third-person muzzle flashes and the world impact strips from code,
## in palette colours with hard alpha, so every gun reads by the shape of its
## flash and a hit on a fighter reads apart from a hit on a wall. Deterministic:
## the chips and droplets come from fixed seeds. Run from the repository root:
##   godot --headless --path client --script ../tools/bake_shot_vfx.gd
##
## Flashes are 32 pixel squares drawn as radial bursts, because a fighter's
## flash is a billboard and must read from any side. Impacts are one atlas of
## four 32 pixel frames per row, one row per kind, played over the effect's
## lifetime by `ShotVfx`.

const CELL: int = 32
const OUT_DIR: String = "assets/vfx/shots"

const INK: Color = Color8(10, 10, 12)
const BONE: Color = Color8(232, 226, 214)
const GUNMETAL_DARK: Color = Color8(58, 56, 54)
const GUNMETAL: Color = Color8(90, 85, 79)
const GUNMETAL_LIGHT: Color = Color8(140, 132, 122)
const RUST: Color = Color8(122, 58, 34)
const BLOOD: Color = Color8(110, 18, 24)
const EMBER: Color = Color8(196, 90, 32)
const EMBER_HOT: Color = Color8(220, 140, 60)
const CYAN_MUTED: Color = Color8(74, 138, 146)
const CYAN_LIGHT: Color = Color8(140, 190, 198)
const ON_AIR: Color = Color8(139, 30, 30)
const RED_GLOW: Color = Color8(226, 52, 48)

## Row order in `impacts.png`; `ShotVfx.IMPACT_ROWS` reads the same order.
const IMPACT_KINDS: Array[String] = ["solid", "fighter", "rail", "melee"]
const IMPACT_FRAMES: int = 4

const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

func _initialize() -> void:
	var root_dir: String = ProjectSettings.globalize_path("res://").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(root_dir)
	var flashes: Dictionary[String, Image] = {
		"tack": _flash_tack(),
		"flechette": _flash_flechette(),
		"scatter": _flash_scatter(),
		"rail": _flash_rail(),
		"sniper": _flash_sniper(),
	}
	for weapon: String in flashes:
		if not _save(flashes[weapon], root_dir.path_join("muzzle_%s.png" % weapon)):
			return
	var atlas: Image = Image.create_empty(CELL * IMPACT_FRAMES, CELL * IMPACT_KINDS.size(), false, Image.FORMAT_RGBA8)
	for row: int in range(IMPACT_KINDS.size()):
		for frame: int in range(IMPACT_FRAMES):
			var cell: Image = _impact(IMPACT_KINDS[row], frame)
			atlas.blit_rect(cell, Rect2i(0, 0, CELL, CELL), Vector2i(frame * CELL, row * CELL))
	if not _save(atlas, root_dir.path_join("impacts.png")):
		return
	print("bake_shot_vfx: PASS ", OUT_DIR)
	quit(0)

func _save(image: Image, path: String) -> bool:
	if image.save_png(path) != OK:
		push_error("bake_shot_vfx: could not write " + path)
		quit(1)
		return false
	return true

func _blank() -> Image:
	var image: Image = Image.create_empty(CELL, CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image

func _put(image: Image, x: int, y: int, colour: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, colour)

## Fills a radial shape: `radius(angle)` gives the edge, and the colour steps
## from core to rim by the fraction of that edge a pixel sits at.
func _burst(image: Image, centre: Vector2, radius: Callable, ramp: Array[Color], steps: Array[float]) -> void:
	for y: int in range(CELL):
		for x: int in range(CELL):
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

func _flash_rail() -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	# A cold ring with four spokes, no orange: the discharge, not a fire.
	for y: int in range(CELL):
		for x: int in range(CELL):
			var distance: float = (Vector2(x + 0.5, y + 0.5) - centre).length()
			if distance >= 10.0 and distance <= 12.4:
				image.set_pixel(x, y, CYAN_LIGHT if distance < 11.4 else CYAN_MUTED)
	for quarter: int in range(4):
		var angle: float = quarter * PI * 0.5 + PI * 0.25
		_ray(image, centre + Vector2.from_angle(angle) * 11.5, angle, 4.5, 3.0, CYAN_LIGHT, CYAN_MUTED)
	_burst(image, centre, func(_a: float) -> float: return 6.0, [BONE, CYAN_LIGHT, CYAN_MUTED], [0.45, 0.8, 1.0])
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

func _disc(image: Image, at: Vector2, radius: float, colour: Color) -> void:
	for y: int in range(floori(at.y - radius - 1), ceili(at.y + radius + 1)):
		for x: int in range(floori(at.x - radius - 1), ceili(at.x + radius + 1)):
			if (Vector2(x + 0.5, y + 0.5) - at).length() <= radius:
				_put(image, x, y, colour)

## Ordered dither: keep a pixel only where `density` beats its Bayer cell.
func _dithered(image: Image, density: float) -> void:
	for y: int in range(CELL):
		for x: int in range(CELL):
			if image.get_pixel(x, y).a == 0.0:
				continue
			var threshold: float = (float(BAYER[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0
			if density < threshold:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

func _impact(kind: String, frame: int) -> Image:
	match kind:
		"solid":
			return _impact_solid(frame)
		"fighter":
			return _impact_fighter(frame)
		"rail":
			return _impact_rail(frame)
	return _impact_melee(frame)

## A spark, then a dust puff with chips thrown clear, thinning out.
func _impact_solid(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 17)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4410
	var chips: Array[Vector2] = []
	for chip: int in range(6):
		chips.append(Vector2.from_angle(rng.randf_range(-PI * 0.95, -PI * 0.05)) * rng.randf_range(0.7, 1.0))
	if frame == 0:
		for quarter: int in range(4):
			_ray(image, centre, quarter * PI * 0.5 + 0.3, 7.0, 3.0, BONE, EMBER_HOT)
		_disc(image, centre, 2.5, BONE)
		return image
	var radius: float = [0.0, 6.0, 8.5, 10.5][frame]
	var dust: Callable = func(angle: float) -> float:
		return radius + 1.0 * sin(angle * 5.0 + frame) + 0.8 * sin(angle * 3.0 + 2.0)
	_burst(image, centre, dust, [BONE, GUNMETAL_LIGHT, GUNMETAL], [0.25 if frame == 1 else 0.0, 0.72, 1.0])
	for chip: Vector2 in chips:
		var at: Vector2 = centre + chip * (6.0 + frame * 4.0) + Vector2(0, frame * frame * 0.5)
		_put(image, floori(at.x), floori(at.y), GUNMETAL_DARK)
		_put(image, floori(at.x) + 1, floori(at.y), GUNMETAL)
	if frame == 3:
		_dithered(image, 0.45)
	return image

## A hot red splash, then spray and droplets that fall and thin out.
func _impact_fighter(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 15)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9127
	var drops: Array[Vector2] = []
	for drop: int in range(10):
		drops.append(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.55, 1.0))
	if frame == 0:
		var splash: Callable = func(angle: float) -> float:
			return 6.5 + 1.8 * sin(angle * 6.0)
		_burst(image, centre, splash, [BONE, EMBER_HOT, RED_GLOW, ON_AIR], [0.3, 0.55, 0.82, 1.0])
		return image
	var core: float = [0.0, 6.0, 4.5, 2.5][frame]
	var lobes: Callable = func(angle: float) -> float:
		return core + 1.3 * sin(angle * 5.0 + 1.0)
	_burst(image, centre + Vector2(0, frame), lobes, [RED_GLOW, ON_AIR, BLOOD], [0.35 if frame == 1 else 0.0, 0.7, 1.0])
	for drop: Vector2 in drops:
		var at: Vector2 = centre + drop * (7.0 + frame * 3.5) + Vector2(0, frame * frame * 0.8)
		var colour: Color = RED_GLOW if frame == 1 else (ON_AIR if frame == 2 else BLOOD)
		_put(image, floori(at.x), floori(at.y), colour)
		if frame < 3:
			_put(image, floori(at.x), floori(at.y) + 1, BLOOD)
	if frame == 1:
		for spark: int in range(5):
			var angle: float = spark * TAU / 5.0 + 0.5
			_ray(image, centre + Vector2.from_angle(angle) * 7.0, angle, 4.0, 1.5, EMBER_HOT, EMBER_HOT)
	if frame == 3:
		_dithered(image, 0.55)
	return image

## A bone core in a cyan cross, then a ring that widens and breaks up.
func _impact_rail(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	if frame == 0:
		for quarter: int in range(4):
			_ray(image, centre, quarter * PI * 0.5, 11.0, 3.0, CYAN_LIGHT, CYAN_MUTED)
		_disc(image, centre, 4.0, BONE)
		_disc(image, centre, 2.0, BONE)
		return image
	var radius: float = [0.0, 7.0, 10.5, 13.0][frame]
	var thickness: float = [0.0, 2.6, 1.9, 1.4][frame]
	for y: int in range(CELL):
		for x: int in range(CELL):
			var distance: float = (Vector2(x + 0.5, y + 0.5) - centre).length()
			if absf(distance - radius) <= thickness * 0.5:
				image.set_pixel(x, y, CYAN_LIGHT if frame == 1 else CYAN_MUTED)
	if frame == 1:
		_disc(image, centre, 3.0, BONE)
	elif frame == 2:
		_disc(image, centre, 1.5, CYAN_LIGHT)
	if frame == 3:
		_dithered(image, 0.5)
	return image

## A short bone smack with three speed lines, then a dust puff.
func _impact_melee(frame: int) -> Image:
	var image: Image = _blank()
	var centre: Vector2 = Vector2(16, 16)
	if frame == 0:
		for index: int in range(6):
			var angle: float = index * TAU / 6.0 + 0.25
			_ray(image, centre + Vector2.from_angle(angle) * 4.0, angle, 6.0, 2.0, BONE, GUNMETAL_LIGHT)
		_disc(image, centre, 2.5, BONE)
		return image
	var radius: float = [0.0, 5.0, 7.0, 8.5][frame]
	var dust: Callable = func(angle: float) -> float:
		return radius + sin(angle * 3.0 + frame) + 0.6 * sin(angle * 5.0 + 1.0)
	_burst(image, centre, dust, [BONE, GUNMETAL_LIGHT, GUNMETAL], [0.3 if frame == 1 else 0.0, 0.75, 1.0])
	if frame >= 2:
		_dithered(image, 0.75 if frame == 2 else 0.4)
	return image
