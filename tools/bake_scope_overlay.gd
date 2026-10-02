extends SceneTree

## Bakes the Sniper Rifle scope overlay from code: a square 360 pixel plate in
## palette colours with a transparent circular aperture, a stepped steel ring,
## a dithered lens edge and a duplex reticle with a red centre chevron. Drawn
## centred over the view at the window height with nearest sampling; the HUD
## fills the remaining width with ink. Run from the repository root:
##   godot --headless --path client --script ../tools/bake_scope_overlay.gd

const SIZE: int = 360
const APERTURE: float = 150.0
const RING: float = 14.0
const OUTPUT: String = "assets/weapons/sniper/scope_overlay.png"

const INK: Color = Color8(10, 10, 12)
const GUNMETAL_DARK: Color = Color8(58, 56, 54)
const GUNMETAL: Color = Color8(90, 85, 79)
const GUNMETAL_LIGHT: Color = Color8(140, 132, 122)
const UNION_RED_GLOW: Color = Color8(226, 52, 48)
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

func _initialize() -> void:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre: Vector2 = Vector2(SIZE, SIZE) * 0.5
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var offset: Vector2 = Vector2(x + 0.5, y + 0.5) - centre
			image.set_pixel(x, y, _shade(offset, x, y))
	_reticle(image)
	var path: String = ProjectSettings.globalize_path("res://").path_join(OUTPUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		push_error("bake_scope_overlay: could not write " + OUTPUT)
		quit(1)
		return
	print("bake_scope_overlay: PASS ", OUTPUT)
	quit(0)

func _shade(offset: Vector2, x: int, y: int) -> Color:
	var distance: float = offset.length()
	if distance >= APERTURE + RING:
		return INK
	if distance >= APERTURE:
		# Light catches the upper left of the bevel, the lower right falls away.
		var facing: float = offset.normalized().dot(Vector2(-0.7071, -0.7071))
		var depth: float = (distance - APERTURE) / RING
		if depth < 0.22:
			return GUNMETAL_LIGHT if facing > 0.35 else (GUNMETAL if facing > -0.35 else GUNMETAL_DARK)
		if depth > 0.78:
			return INK
		return GUNMETAL_DARK if facing > -0.2 else INK
	# Ordered-dither vignette at the lens edge: denser toward the ring.
	var edge: float = clampf((distance - (APERTURE - 16.0)) / 16.0, 0.0, 1.0)
	var threshold: float = (float(BAYER[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0
	if edge > threshold:
		return INK
	return Color(0, 0, 0, 0)

func _reticle(image: Image) -> void:
	var mid: int = SIZE / 2
	var reach: int = int(APERTURE)
	for along: int in range(-reach, reach):
		var gap: int = absi(along)
		if gap < 6:
			continue
		# Thin crosshair near the centre, heavy posts toward the ring.
		var half: int = 0 if gap < 72 else 2
		for across: int in range(-half, half + 1):
			_ink(image, mid + along, mid + across)
			_ink(image, mid + across, mid + along)
	# Range ticks below the centre, one every twelve pixels.
	for tick: int in range(1, 5):
		var y: int = mid + 12 * tick
		for x: int in range(mid - 4 + tick, mid + 5 - tick):
			_ink(image, x, y)
	# A small red chevron points up at the aim point.
	for step: int in range(7):
		for thick: int in range(2):
			image.set_pixel(mid - step, mid + 2 + step + thick, UNION_RED_GLOW)
			image.set_pixel(mid + step, mid + 2 + step + thick, UNION_RED_GLOW)

func _ink(image: Image, x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE and image.get_pixel(x, y).a < 0.5:
		image.set_pixel(x, y, INK)
