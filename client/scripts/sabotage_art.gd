class_name SabotageArt
extends RefCounted

## Placeholder pixel art for Sabotage, drawn once in code from the palette:
## the A and B site plates, the correction frame and the registry server, the
## charge and its floor ring. Nearest filtered, no mipmaps, like every other
## pixel asset. Final art replaces any of them by dropping a PNG at
## `res://assets/sabotage/<key>.png`: plate_a, plate_b, prop_a, prop_b,
## charge, ring and burst. The presenter sizes sprites in metres, so a larger
## image keeps the same world size.

const UNION_RED := Color("e23430")
const BONE := Color("e8e2d6")
const EMBER := Color("dc8c3c")
const STEEL := Color("56575e")
const STEEL_DARK := Color("2a2b31")
const PLATE := Color("1d1d22")
const SHADOW := Color("0a0a0c")
const SCREEN := Color("8a1c1a")
const LIT := Color("ff5a48")
const GREEN := Color("6fbf4a")
const OLIVE := Color("5a5a34")
const TAPE := Color("a39a7c")

## 5 by 7 glyphs for the two site letters.
const GLYPHS: Dictionary = {
	"a": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"b": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
}

const ART_DIR: String = "res://assets/sabotage/"

static var _cache: Dictionary = {}


## True when the key is ready in the cache, loading final art first if a file
## for it exists.
static func _cached(key: String) -> bool:
	if _cache.has(key):
		return true
	var path: String = ART_DIR + key + ".png"
	if ResourceLoader.exists(path):
		var art: Variant = load(path)
		if art is Texture2D:
			_cache[key] = art
			return true
	return false


static func _texture(key: String, image: Image) -> Texture2D:
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func _blank(width: int, height: int) -> Image:
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


static func _rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	image.fill_rect(Rect2i(x, y, w, h), color)


static func _glyph(image: Image, letter: String, x: int, y: int, scale: int, color: Color) -> void:
	var rows: Array = GLYPHS.get(letter, [])
	for row: int in range(rows.size()):
		var line: String = rows[row]
		for column: int in range(line.length()):
			if line[column] == "#":
				_rect(image, x + column * scale, y + row * scale, scale, scale, color)


## The floating site plate: a riveted steel sign with the letter in bone.
static func site_plate(site: String) -> Texture2D:
	var key: String = "plate_" + site
	if _cached(key):
		return _cache[key]
	var image: Image = _blank(32, 32)
	_rect(image, 1, 1, 30, 30, SHADOW)
	_rect(image, 0, 0, 30, 30, UNION_RED)
	_rect(image, 2, 2, 26, 26, PLATE)
	for corner: Vector2i in [Vector2i(3, 3), Vector2i(26, 3), Vector2i(3, 26), Vector2i(26, 26)]:
		_rect(image, corner.x, corner.y, 1, 1, STEEL)
	_glyph(image, site, 8, 5, 3, SHADOW)
	_glyph(image, site, 7, 4, 3, BONE)
	return _texture(key, image)


## The objective a site guards: A is a correction frame, B a registry server.
static func site_prop(site: String, callout: String = "") -> Texture2D:
	var registered: String = callout if callout in ["clinic_steps", "tram_stop"] else ""
	var key: String = "prop_" + site + ("_" + registered if not registered.is_empty() else "")
	if _cached(key):
		return _cache[key]
	var image: Image = _blank(24, 32)
	if not registered.is_empty():
		# Existing civic service controls, distinct from Sector 9's custody props.
		_rect(image, 3, 8, 18, 23, PLATE)
		_rect(image, 4, 9, 16, 20, STEEL)
		_rect(image, 6, 11, 12, 8, STEEL_DARK)
		_rect(image, 7, 12, 10, 6, SCREEN)
		if registered == "clinic_steps":
			_rect(image, 10, 12, 3, 6, BONE)
			_rect(image, 8, 14, 7, 2, BONE)
		else:
			_rect(image, 8, 12, 2, 6, BONE)
			_rect(image, 14, 12, 2, 6, BONE)
			_rect(image, 9, 13, 6, 1, BONE)
			_rect(image, 9, 16, 6, 1, BONE)
		_rect(image, 6, 22, 12, 2, STEEL_DARK)
		_rect(image, 6, 26, 4, 1, LIT)
		_rect(image, 3, 30, 18, 2, SHADOW)
	elif site == "a":
		# A correction frame: an upright gantry with a lit restraint screen.
		_rect(image, 2, 2, 3, 30, STEEL)
		_rect(image, 19, 2, 3, 30, STEEL)
		_rect(image, 2, 2, 20, 3, STEEL)
		_rect(image, 5, 6, 14, 12, STEEL_DARK)
		_rect(image, 6, 7, 12, 10, SCREEN)
		_rect(image, 8, 9, 8, 1, LIT)
		_rect(image, 8, 12, 5, 1, LIT)
		_rect(image, 6, 20, 12, 2, STEEL_DARK)
		_rect(image, 11, 22, 2, 10, STEEL_DARK)
		_rect(image, 1, 30, 22, 2, SHADOW)
	else:
		# A registry server: a rack of drive bays and status lights.
		_rect(image, 3, 1, 18, 31, STEEL_DARK)
		_rect(image, 4, 2, 16, 29, PLATE)
		for bay: int in range(6):
			var y: int = 4 + bay * 4
			_rect(image, 5, y, 14, 3, STEEL)
			_rect(image, 6, y + 1, 8, 1, STEEL_DARK)
			_rect(image, 16, y + 1, 1, 1, GREEN if bay % 2 == 0 else LIT)
		_rect(image, 3, 30, 18, 2, SHADOW)
	return _texture(key, image)


## The charge: a taped satchel with a timer box. The light is drawn apart so
## it can blink without a new texture.
static func charge() -> Texture2D:
	if _cached("charge"):
		return _cache["charge"]
	var image: Image = _blank(16, 12)
	_rect(image, 1, 3, 14, 8, OLIVE)
	_rect(image, 1, 10, 14, 1, SHADOW)
	_rect(image, 4, 3, 2, 8, TAPE)
	_rect(image, 10, 3, 2, 8, TAPE)
	_rect(image, 5, 0, 6, 4, STEEL_DARK)
	_rect(image, 6, 1, 4, 2, PLATE)
	_rect(image, 2, 1, 3, 1, UNION_RED)
	_rect(image, 11, 1, 3, 1, EMBER)
	return _texture("charge", image)


## The charge's timer light, lit or dark.
static func charge_light(color: Color) -> Texture2D:
	var key: String = "light_" + color.to_html()
	if _cached(key):
		return _cache[key]
	var image: Image = _blank(4, 4)
	_rect(image, 1, 0, 2, 4, color)
	_rect(image, 0, 1, 4, 2, color)
	return _texture(key, image)


## A dashed ring for a plant area, laid flat on the floor.
static func plant_ring() -> Texture2D:
	if _cached("ring"):
		return _cache["ring"]
	var size: int = 64
	var image: Image = _blank(size, size)
	var centre: float = (size - 1) / 2.0
	for y: int in range(size):
		for x: int in range(size):
			var dx: float = x - centre
			var dy: float = y - centre
			var distance: float = sqrt(dx * dx + dy * dy)
			if distance >= centre - 2.5 and distance <= centre:
				var angle: float = atan2(dy, dx)
				var dash: bool = int(floor((angle + PI) / (TAU / 24.0))) % 2 == 0
				image.set_pixel(x, y, UNION_RED if dash else Color(UNION_RED, 0.35))
	return _texture("ring", image)


## A blocky burst for the detonation, white hot at the centre.
static func burst() -> Texture2D:
	if _cached("burst"):
		return _cache["burst"]
	var size: int = 32
	var image: Image = _blank(size, size)
	var centre: float = (size - 1) / 2.0
	for y: int in range(size):
		for x: int in range(size):
			var dx: float = x - centre
			var dy: float = y - centre
			var distance: float = sqrt(dx * dx + dy * dy)
			var ragged: float = centre * (0.75 + 0.25 * sin(atan2(dy, dx) * 7.0))
			if distance <= ragged:
				var heat: float = distance / ragged
				var color: Color = Color.WHITE.lerp(EMBER, clampf(heat * 1.4, 0.0, 1.0)).lerp(UNION_RED, clampf(heat * 2.0 - 1.0, 0.0, 1.0))
				image.set_pixel(x, y, color)
	return _texture("burst", image)
