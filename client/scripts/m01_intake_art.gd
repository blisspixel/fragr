class_name M01IntakeArt
extends RefCounted

## Small authored pixel pictures for Recall Notice's intake: the looped
## address, the recall poster over an old advert, Union banners, a seized
## agent's file photo and window grids for the street skyline. Every essential
## word stays in the localized catalog (WorldSign); these images carry none.
## Colours come from docs/palette.json and the art bible's faction roles.

const INK: Color = Color("0a0a0c")
const BONE: Color = Color("e8e2d6")
const UNION_BLACK: Color = Color("1e1e22")
const UNION_STEEL: Color = Color("2c2d32")
const UNION_PLATE: Color = Color("56575e")
const UNION_RED: Color = Color("8c1a1e")
const INSTITUTION_GREEN: Color = Color("4e5844")
const RUST: Color = Color("7a3a22")
const STEEL: Color = Color("3a3836")
const GUNMETAL: Color = Color("5a554f")
const PHOSPHOR: Color = Color("e0bf7c")

static var _cache: Dictionary[String, Texture2D] = {}

static func texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var image: Image = null
	match key:
		"banner": image = union_banner()
		"advert": image = home_helper_advert()
		"recall_notice": image = recall_notice()
		"latch_file": image = latch_file_photo()
		"emblem": image = union_emblem_plate()
		"windows_home": image = window_grid(false)
		"windows_office": image = window_grid(true)
		"poster_article": image = article_poster()
		"queue_barrier": image = queue_barrier()
		"frontage": image = street_frontage()
	if image == null:
		return null
	var made: ImageTexture = ImageTexture.create_from_image(image)
	made.resource_name = "m01_" + key
	_cache[key] = made
	return made

## Address frames: calm, speaking, angry (with the raised fist), then static.
static func address_frames() -> Array[Texture2D]:
	if _cache.has("address_0"):
		var cached: Array[Texture2D] = []
		for index: int in range(3):
			cached.append(_cache["address_%d" % index])
		return cached
	var frames: Array[Texture2D] = []
	for mood: int in range(3):
		var made: ImageTexture = ImageTexture.create_from_image(address(mood))
		made.resource_name = "m01_address_%d" % mood
		_cache["address_%d" % mood] = made
		frames.append(made)
	return frames

static func static_frames() -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for index: int in range(4):
		var key: String = "static_%d" % index
		if not _cache.has(key):
			var made: ImageTexture = ImageTexture.create_from_image(screen_static(index))
			made.resource_name = "m01_" + key
			_cache[key] = made
		frames.append(_cache[key])
	return frames

static func _image(width: int, height: int, fill: Color) -> Image:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	return image

static func _rect(image: Image, x: int, y: int, w: int, h: int, colour: Color) -> void:
	image.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, image.get_size())), colour)

static func _put(image: Image, x: int, y: int, colour: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, colour)

## The Union diamond used by the registered seal decoration: red field with
## bone bars. Original mark, no real insignia.
static func _diamond(image: Image, cx: int, cy: int, radius: int, field: Color, bars: Color) -> void:
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if absi(x) + absi(y) > radius:
				continue
			var colour: Color = field
			if absi(x) + absi(y) <= radius - 2 and posmod(x + y, 3) == 0:
				colour = bars
			_put(image, cx + x, cy + y, colour)

static func _noise(x: int, y: int, seed_value: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + seed_value * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0

static func union_banner() -> Image:
	var image: Image = _image(16, 64, UNION_BLACK)
	for y: int in range(64):
		_put(image, 1, y, UNION_RED)
		_put(image, 2, y, UNION_RED)
		_put(image, 13, y, UNION_RED)
		_put(image, 14, y, UNION_RED)
		_put(image, 0, y, UNION_STEEL)
		_put(image, 15, y, UNION_STEEL)
	_diamond(image, 8, 16, 5, UNION_RED, BONE)
	_rect(image, 4, 26, 8, 1, UNION_PLATE)
	_rect(image, 5, 28, 6, 1, UNION_PLATE)
	for x: int in range(16):
		if x % 2 == 0:
			_rect(image, x, 60, 1, 4, UNION_RED)
		else:
			_rect(image, x, 60, 1, 3, UNION_BLACK)
	return image

static func union_emblem_plate() -> Image:
	var image: Image = _image(24, 24, UNION_BLACK)
	_rect(image, 0, 0, 24, 1, UNION_PLATE)
	_rect(image, 0, 23, 24, 1, UNION_PLATE)
	_rect(image, 0, 0, 1, 24, UNION_PLATE)
	_rect(image, 23, 0, 1, 24, UNION_PLATE)
	_diamond(image, 12, 12, 9, UNION_RED, BONE)
	return image

## The looped address on the records screen: Voss at the podium under two
## banners. 0 calm, 1 speaking, 2 angry with a raised fist.
static func address(mood: int) -> Image:
	var image: Image = _image(64, 48, Color("1b2125"))
	for y: int in range(48):
		var shade: float = float(y) / 47.0
		_rect(image, 0, y, 64, 1, Color("1b2125").lerp(Color("2a2f2e"), shade))
	# Hall pillars and banners behind the podium.
	for x0: int in [5, 49]:
		_rect(image, x0, 0, 10, 38, UNION_BLACK)
		_rect(image, x0, 0, 1, 38, UNION_RED)
		_rect(image, x0 + 9, 0, 1, 38, UNION_RED)
		_diamond(image, x0 + 5, 12, 3, UNION_RED, BONE)
		for x: int in range(x0, x0 + 10, 2):
			_put(image, x, 38, UNION_RED)
	_diamond(image, 32, 9, 7, UNION_RED, BONE)
	# Severe black coat, dark steel collar, restrained red armband.
	_rect(image, 24, 26, 16, 10, UNION_BLACK)
	_rect(image, 22, 28, 20, 8, UNION_BLACK)
	_rect(image, 28, 24, 8, 3, UNION_PLATE)
	_rect(image, 38, 29, 3, 3, UNION_RED)
	# Head: pale face, hair drawn back into a severe knot.
	_rect(image, 29, 15, 6, 9, Color("c4a088"))
	_rect(image, 28, 13, 8, 3, Color("2b2421"))
	_rect(image, 28, 15, 1, 4, Color("2b2421"))
	_rect(image, 35, 14, 2, 3, Color("2b2421"))
	_put(image, 30, 18, INK)
	_put(image, 33, 18, INK)
	if mood == 2:
		_rect(image, 30, 17, 1, 1, INK)
		_rect(image, 33, 17, 1, 1, INK)
		_rect(image, 31, 21, 2, 2, Color("4a1414"))
		# Raised fist: anger at the podium, never a salute.
		_rect(image, 41, 18, 3, 9, UNION_BLACK)
		_rect(image, 41, 16, 3, 3, Color("c4a088"))
	elif mood == 1:
		_rect(image, 31, 21, 2, 1, Color("6a2a24"))
	else:
		_rect(image, 31, 21, 3, 1, Color("8a5a4c"))
	# Podium with the issued plate and two microphones.
	_rect(image, 21, 34, 22, 14, STEEL)
	_rect(image, 20, 33, 24, 2, GUNMETAL)
	_diamond(image, 32, 41, 4, UNION_RED, BONE)
	for x: int in [27, 37]:
		_rect(image, x, 28, 1, 6, UNION_PLATE)
		_rect(image, x - 1, 27, 2, 2, UNION_STEEL)
	# Broadcast scanlines.
	for y: int in range(1, 48, 2):
		for x: int in range(64):
			image.set_pixel(x, y, image.get_pixel(x, y).darkened(0.18))
	return image

static func screen_static(frame: int) -> Image:
	var image: Image = _image(64, 48, INK)
	var roll: int = (frame * 13) % 48
	for y: int in range(48):
		for x: int in range(64):
			var n: float = _noise(x, y, frame + 7)
			var value: float = 0.08 + floor(n * 4.0) * 0.17
			if absi(y - roll) < 3:
				value += 0.18
			image.set_pixel(x, y, Color(value, value * 0.98, value * 0.94))
	return image

## An old, sun-faded advert for a helpful home robot, under a fresh notice.
static func home_helper_advert() -> Image:
	var image: Image = _image(40, 56, Color("d9d2bd"))
	for y: int in range(40):
		_rect(image, 1, 1 + y, 38, 1, Color("9fb4b0").lerp(Color("dccfae"), float(y) / 39.0))
	_rect(image, 0, 0, 40, 1, BONE)
	_rect(image, 0, 55, 40, 1, Color("b9ae95"))
	# Low sun and a rooftop line.
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			if x * x + y * y <= 16:
				_put(image, 30 + x, 9 + y, Color("e7c27e"))
	_rect(image, 1, 33, 38, 7, Color("b59a78"))
	_rect(image, 5, 29, 8, 4, Color("b59a78"))
	_rect(image, 26, 30, 10, 3, Color("b59a78"))
	# The smiling helper in cheerful appliance orange with gunmetal joints and a
	# friendly screen face. Never matte bone over ink joints: that read belongs
	# to the late game's restoration machines (art bible faction table).
	var shell: Color = Color("c8743a")
	var shade: Color = Color("9a5228")
	_rect(image, 13, 12, 12, 10, shell)
	_rect(image, 14, 11, 10, 1, shell)
	_rect(image, 15, 13, 8, 6, Color("2d3a3a"))
	_put(image, 17, 15, Color("f0d9a0"))
	_put(image, 21, 15, Color("f0d9a0"))
	_rect(image, 17, 17, 5, 1, Color("f0d9a0"))
	_rect(image, 17, 22, 4, 2, GUNMETAL)
	_rect(image, 12, 24, 14, 12, shell)
	_rect(image, 12, 24, 14, 1, Color("dc9358"))
	_rect(image, 12, 34, 14, 2, shade)
	_rect(image, 9, 25, 3, 8, shade)
	_rect(image, 26, 25, 3, 5, shade)
	_rect(image, 26, 24, 7, 1, GUNMETAL)
	_rect(image, 30, 22, 2, 2, Color("b8604a"))
	_rect(image, 14, 36, 4, 6, GUNMETAL)
	_rect(image, 20, 36, 4, 6, GUNMETAL)
	# Weathered paper: specks and a torn lower edge.
	for y: int in range(56):
		for x: int in range(40):
			if _noise(x, y, 3) > 0.965:
				_put(image, x, y, Color("8f8670"))
	for x: int in range(40):
		if _noise(x, 0, 9) > 0.6:
			_put(image, x, 55, Color(0, 0, 0, 0))
	return image

## A fresh issued notice: bone paper, Union red header, empty photo slot and a
## review stamp. The words are a WorldSign laid over it.
static func recall_notice() -> Image:
	var image: Image = _image(28, 40, Color("e6dfcf"))
	_rect(image, 0, 0, 28, 7, UNION_RED)
	_diamond(image, 4, 3, 2, UNION_BLACK, BONE)
	_rect(image, 1, 39, 26, 1, Color("c8bfa9"))
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			var d: int = x * x + y * y
			if d <= 16 and d >= 9:
				_put(image, 21 + x, 33 + y, Color(UNION_RED, 0.8))
	for y: int in range(40):
		for x: int in range(28):
			if _noise(x, y, 5) > 0.975:
				_put(image, x, y, Color("b5ab92"))
	return image

## A seized agent's file photo on an issued monochrome terminal: height lines
## behind a tall CRT head with one antenna on the viewer's right.
static func latch_file_photo() -> Image:
	var back: Color = Color("17140d")
	var image: Image = _image(40, 48, back)
	var line: Color = PHOSPHOR.darkened(0.72)
	var lit: Color = PHOSPHOR
	var mid: Color = PHOSPHOR.darkened(0.35)
	var low: Color = PHOSPHOR.darkened(0.55)
	for y: int in range(4, 48, 5):
		_rect(image, 0, y, 40, 1, line)
		_rect(image, 0, y, 3, 1, mid)
	# Antenna from the anatomical left ear (viewer right).
	for step: int in range(7):
		_put(image, 28 + int(float(step) * 0.5), 8 - step, mid)
	_rect(image, 31, 0, 2, 2, lit)
	# Tall screen head: housing, dark screen, friendly face.
	_rect(image, 13, 6, 15, 19, mid)
	_rect(image, 15, 8, 11, 14, Color("0b0a06"))
	_rect(image, 17, 12, 2, 2, lit)
	_rect(image, 22, 12, 2, 2, lit)
	_rect(image, 18, 17, 5, 1, lit)
	_put(image, 17, 16, lit)
	_put(image, 23, 16, lit)
	_rect(image, 13, 24, 15, 1, low)
	# Neck and lean shoulders, with the unequal repair plate on the viewer right.
	_rect(image, 18, 25, 5, 3, low)
	_rect(image, 9, 28, 23, 20, low)
	_rect(image, 9, 28, 23, 1, mid)
	_rect(image, 24, 29, 8, 7, mid)
	for y: int in range(30, 36, 2):
		_put(image, 25, y, back)
		_put(image, 30, y, back)
	_rect(image, 20, 30, 1, 18, back)
	# Terminal scanlines.
	for y: int in range(1, 48, 2):
		for x: int in range(40):
			image.set_pixel(x, y, image.get_pixel(x, y).darkened(0.22))
	return image

## A Union wall poster: red field, black band, the diamond. Words are a label.
static func article_poster() -> Image:
	var image: Image = _image(24, 34, Color("d8d1bf"))
	_rect(image, 1, 1, 22, 18, UNION_RED)
	_diamond(image, 12, 10, 7, UNION_BLACK, BONE)
	_rect(image, 1, 20, 22, 2, UNION_BLACK)
	_rect(image, 0, 33, 24, 1, Color("b7ad97"))
	for y: int in range(34):
		for x: int in range(24):
			if _noise(x, y, 11) > 0.97:
				_put(image, x, y, Color("a39a84"))
	return image

## Street facades: four storeys by eight bays of windows. Homes keep a few warm
## lit rooms and curtains; offices are dark with one cold late desk.
static func window_grid(office: bool) -> Image:
	var wall: Color = Color("4a4640") if not office else Color("8d897b")
	var image: Image = _image(64, 64, wall)
	for y: int in range(64):
		for x: int in range(64):
			var n: float = _noise(x, y, 21 if office else 17)
			if n > 0.9:
				_put(image, x, y, wall.darkened(0.12))
			elif n < 0.05:
				_put(image, x, y, wall.lightened(0.06))
	for floor_index: int in range(4):
		var y0: int = floor_index * 16 + 4
		_rect(image, 0, y0 + 10, 64, 1, wall.darkened(0.25))
		for bay: int in range(8):
			var x0: int = bay * 8 + 2
			var seed_value: float = _noise(bay, floor_index, 31 if office else 37)
			var glass: Color = Color("161a1d")
			if not office and seed_value > 0.62:
				glass = Color("f2b765") if seed_value > 0.8 else Color("d68f4c")
			elif office and seed_value > 0.9:
				glass = Color("b9c9c4")
			_rect(image, x0 - 1, y0 - 1, 6, 9, wall.darkened(0.35))
			_rect(image, x0, y0, 4, 7, glass)
			if not office and glass != Color("161a1d"):
				_rect(image, x0, y0, 1, 7, Color("9c4f37"))
				if seed_value > 0.9:
					_rect(image, x0 + 2, y0 + 4, 1, 3, Color("3a2a20"))
			_rect(image, x0 - 1, y0 + 7, 6, 1, wall.lightened(0.1))
	return image

## One registered queue barrier bay (1.85 m by 1 m): issued steel frame and
## posts, galvanised top rail and close vertical bars over a dark gap.
static func queue_barrier() -> Image:
	var image: Image = _image(32, 16, Color("1f2123"))
	_rect(image, 0, 0, 32, 2, Color("8b8d86"))
	_rect(image, 0, 2, 32, 1, Color("5d5f5a"))
	_rect(image, 0, 14, 32, 2, UNION_STEEL)
	_rect(image, 0, 8, 32, 1, Color("4a4c49"))
	for x: int in range(3, 31, 3):
		_rect(image, x, 3, 1, 11, Color("5d5f5a"))
	_rect(image, 0, 0, 2, 16, Color("2b2c2e"))
	_rect(image, 30, 0, 2, 16, Color("2b2c2e"))
	# A small bone registration plate on every bay.
	_rect(image, 13, 10, 6, 3, Color("c9c1ad"))
	_rect(image, 14, 11, 4, 1, UNION_STEEL)
	return image

## The ground and first floor of the tenements that wall the service street
## (12 m by 6 m): lit and dark flats above, a shuttered shop, a front door and
## a small kitchen window below. People live right here.
static func street_frontage() -> Image:
	var wall: Color = Color("4a4640")
	var image: Image = _image(64, 32, wall)
	for y: int in range(32):
		for x: int in range(64):
			var n: float = _noise(x, y, 41)
			if n > 0.9:
				_put(image, x, y, wall.darkened(0.12))
			elif n < 0.05:
				_put(image, x, y, wall.lightened(0.06))
	# First floor: a row of flats, a few lit.
	for bay: int in range(8):
		var x0: int = bay * 8 + 2
		var glass: Color = Color("161a1d")
		if bay in [1, 4, 6]:
			glass = Color("f2b765") if bay == 4 else Color("d68f4c")
		_rect(image, x0 - 1, 3, 6, 9, wall.darkened(0.35))
		_rect(image, x0, 4, 4, 7, glass)
		if glass != Color("161a1d"):
			_rect(image, x0, 4, 1, 7, Color("9c4f37"))
		_rect(image, x0 - 1, 11, 6, 1, wall.lightened(0.1))
	# The floor line, then the ground floor.
	_rect(image, 0, 15, 64, 1, wall.darkened(0.25))
	# A rolled shutter over a shop, painted by whoever ran it.
	_rect(image, 3, 18, 20, 2, Color("6d5238"))
	_rect(image, 4, 20, 18, 12, Color("4f6f68"))
	for y: int in range(21, 32, 2):
		_rect(image, 4, y, 18, 1, Color("4f6f68").darkened(0.3))
	_rect(image, 18, 26, 2, 2, Color("8a3a58"))
	# A front door with its own lamp and a worn step.
	_rect(image, 29, 19, 8, 13, wall.darkened(0.35))
	_rect(image, 30, 20, 6, 12, Color("5a3a28"))
	_rect(image, 34, 26, 1, 1, Color("c9a24a"))
	_rect(image, 32, 17, 2, 1, Color("f2b765"))
	_rect(image, 28, 31, 10, 1, Color("6b6760"))
	# A small kitchen window, lit, with a plant on the sill.
	_rect(image, 44, 20, 8, 6, wall.darkened(0.35))
	_rect(image, 45, 21, 6, 4, Color("d68f4c"))
	_rect(image, 47, 23, 2, 2, Color("3a4c2e"))
	_rect(image, 44, 26, 8, 1, wall.lightened(0.1))
	# Utility run and a meter box between the doors.
	_rect(image, 56, 16, 1, 16, Color("2b2c2e"))
	_rect(image, 55, 22, 4, 4, Color("3a3836"))
	return image

## Lit pixels for a facade's emission: only the warm or cold window glass.
static func window_glow(office: bool) -> Texture2D:
	var key: String = "windows_glow_office" if office else "windows_glow_home"
	if _cache.has(key):
		return _cache[key]
	var made: ImageTexture = ImageTexture.create_from_image(_glow_of(window_grid(office)))
	made.resource_name = "m01_" + key
	_cache[key] = made
	return made

static func frontage_glow() -> Texture2D:
	if _cache.has("frontage_glow"):
		return _cache["frontage_glow"]
	var made: ImageTexture = ImageTexture.create_from_image(_glow_of(street_frontage()))
	made.resource_name = "m01_frontage_glow"
	_cache["frontage_glow"] = made
	return made

static func _glow_of(source: Image) -> Image:
	var glow: Image = _image(source.get_width(), source.get_height(), Color.BLACK)
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var c: Color = source.get_pixel(x, y)
			if c == Color("f2b765") or c == Color("d68f4c") or c == Color("b9c9c4"):
				glow.set_pixel(x, y, c)
	return glow
