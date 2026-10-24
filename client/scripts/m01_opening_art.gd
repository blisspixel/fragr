class_name M01OpeningArt
extends RefCounted

## Authored pixel stills for the Recall Notice opening's ADDRESS and RECALL
## pages, in the game's own pixel style and the intake's palette. They are
## baked to client/assets/story/stills/opening/ by tools/bake_opening_stills.gd;
## nothing here runs in play. No words are drawn: every line on screen stays a
## catalog key in client/i18n/story.en.po.
##
## The scene player covers the screen with the still and lays the text panel
## over its lower middle, so each composition keeps its subject in the top
## band and the side columns (docs/campaign/m01-recall-notice.md, storyboard).

const WIDTH: int = 160
const HEIGHT: int = 90
const Art = preload("res://scripts/m01_intake_art.gd")

## ADDRESS: Voss at the podium on the broadcast, the Union seal behind her,
## one fist raised as she turns angry, the crowd's fists up in the foreground.
## Anger at a podium, never a salute.
static func address() -> Image:
	var image: Image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(HEIGHT):
		var shade: float = float(y) / float(HEIGHT - 1)
		Art._rect(image, 0, y, WIDTH, 1, Color("12171a").lerp(Color("252a2a"), shade))
	# A cold spotlight falls on the podium from above.
	for y: int in range(0, 44):
		var half: int = 8 + y / 2
		for x: int in range(80 - half, 80 + half):
			var c: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, c.lerp(Color("4a5154"), 0.35 * (1.0 - float(y) / 44.0)))
	# Stone pillars and the hall's issued banners.
	for x0: int in [30, 122]:
		Art._rect(image, x0, 0, 8, 64, Color("2c3131"))
		Art._rect(image, x0, 0, 1, 64, Color("3e4444"))
		Art._rect(image, x0 + 7, 0, 1, 64, Color("1d2121"))
	for x0: int in [6, 138]:
		Art._rect(image, x0, 0, 16, 62, Art.UNION_BLACK)
		Art._rect(image, x0 + 1, 0, 2, 62, Art.UNION_RED)
		Art._rect(image, x0 + 13, 0, 2, 62, Art.UNION_RED)
		Art._diamond(image, x0 + 8, 16, 5, Art.UNION_RED, Art.BONE)
		Art._rect(image, x0 + 4, 26, 8, 1, Art.UNION_PLATE)
		for x: int in range(x0, x0 + 16, 2):
			Art._rect(image, x, 62, 1, 2, Art.UNION_RED)
	# The balcony rail and its hanging banner.
	Art._rect(image, 40, 34, 80, 3, Art.UNION_STEEL)
	Art._rect(image, 40, 34, 80, 1, Color("45464c"))
	Art._rect(image, 71, 37, 18, 18, Art.UNION_BLACK)
	Art._rect(image, 71, 37, 1, 18, Art.UNION_RED)
	Art._rect(image, 88, 37, 1, 18, Art.UNION_RED)
	Art._diamond(image, 80, 45, 4, Art.UNION_RED, Art.BONE)
	# The seal behind her head.
	Art._diamond(image, 80, 13, 12, Art.UNION_RED, Art.BONE)
	# Podium, plate and microphones.
	Art._rect(image, 69, 29, 22, 6, Art.STEEL)
	Art._rect(image, 68, 28, 24, 1, Art.GUNMETAL)
	Art._diamond(image, 80, 31, 2, Art.UNION_RED, Art.BONE)
	for x: int in [74, 86]:
		Art._rect(image, x, 23, 1, 5, Art.UNION_PLATE)
		Art._rect(image, x - 1, 22, 2, 2, Art.UNION_STEEL)
	# Voss: severe black coat, dark steel collar, restrained red armband.
	var skin: Color = Color("c4a088")
	var hair: Color = Color("2b2421")
	var coat_rim: Color = Color("4a4e57")
	Art._rect(image, 70, 21, 20, 8, Art.UNION_BLACK)
	Art._rect(image, 72, 20, 16, 1, Art.UNION_BLACK)
	Art._rect(image, 72, 20, 16, 1, coat_rim)
	Art._rect(image, 70, 21, 2, 1, coat_rim)
	Art._rect(image, 88, 21, 2, 1, coat_rim)
	Art._rect(image, 89, 22, 1, 6, coat_rim)
	Art._rect(image, 80, 22, 1, 6, Art.UNION_STEEL)
	Art._rect(image, 76, 19, 8, 2, Art.UNION_PLATE)
	Art._rect(image, 87, 23, 2, 3, Art.UNION_RED)
	Art._rect(image, 77, 11, 6, 8, skin)
	Art._rect(image, 76, 9, 8, 3, hair)
	Art._rect(image, 76, 12, 1, 3, hair)
	Art._rect(image, 83, 10, 2, 3, hair)
	Art._rect(image, 78, 13, 2, 1, Art.INK)
	Art._rect(image, 81, 13, 2, 1, Art.INK)
	Art._put(image, 78, 14, Art.INK)
	Art._put(image, 82, 14, Art.INK)
	Art._rect(image, 79, 16, 2, 2, Color("4a1414"))
	# The raised fist on the viewer's left.
	Art._rect(image, 67, 12, 4, 10, Art.UNION_BLACK)
	Art._rect(image, 67, 12, 1, 10, coat_rim)
	Art._rect(image, 67, 8, 4, 4, skin)
	Art._put(image, 69, 9, skin.darkened(0.2))
	# The crowd: heads and raised fists dark against the stage light.
	var crowd: Color = Color("0d0f11")
	var rim: Color = Color("3a4044")
	for index: int in range(26):
		var x: int = -2 + index * 6 + int(Art._noise(index, 1, 71) * 4.0)
		var y: int = 70 + int(Art._noise(index, 2, 71) * 8.0)
		Art._rect(image, x, y, 5, 5, crowd)
		Art._rect(image, x - 2, y + 5, 9, 20, crowd)
		Art._rect(image, x + 1, y, 3, 1, rim)
		if Art._noise(index, 3, 71) > 0.5:
			var arm: int = x + (5 if index % 2 == 0 else -3)
			var reach: int = 9 + int(Art._noise(index, 4, 71) * 8.0)
			Art._rect(image, arm, y - reach, 3, reach + 4, crowd)
			Art._rect(image, arm, y - reach, 1, reach, rim.darkened(0.3))
			Art._rect(image, arm - 1, y - reach - 4, 5, 4, crowd)
			Art._rect(image, arm - 1, y - reach - 4, 5, 1, rim)
			if Art._noise(index, 5, 71) > 0.6:
				Art._rect(image, arm, y - reach + 3, 3, 2, Art.UNION_RED)
	_scanlines(image, 0.16)
	return image

## RECALL: the workshop door at night, sealed and posted with a recall notice,
## a dropped mug and wrench on the step, and the custody van pulling away with
## Latch's warm screen face behind its barred rear window.
static func recall() -> Image:
	var image: Image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	var wall: Color = Color("3a3631")
	image.fill(wall)
	for y: int in range(HEIGHT):
		for x: int in range(WIDTH):
			var n: float = Art._noise(x, y, 83)
			if n > 0.92:
				Art._put(image, x, y, wall.darkened(0.15))
			elif n < 0.04:
				Art._put(image, x, y, wall.lightened(0.07))
	Art._rect(image, 0, 0, WIDTH, 5, Color("131820"))
	Art._rect(image, 0, 5, WIDTH, 1, Color("2a2724"))
	# Their workshop window, lit warm: hanging tools and a plant.
	var lit: Color = Color("e0a860")
	Art._rect(image, 3, 13, 25, 23, wall.darkened(0.4))
	Art._rect(image, 4, 14, 23, 21, lit)
	Art._rect(image, 15, 14, 1, 21, wall.darkened(0.4))
	Art._rect(image, 4, 24, 23, 1, wall.darkened(0.4))
	for x: int in [6, 9, 12]:
		Art._rect(image, x, 15, 1, 6, Color("5a3a28"))
		Art._rect(image, x - 1, 20, 3, 2, Color("3a3836"))
	Art._rect(image, 19, 30, 4, 4, Color("6d5238"))
	Art._rect(image, 18, 26, 6, 4, Color("3a4c2e"))
	Art._rect(image, 3, 35, 25, 1, wall.lightened(0.12))
	# Their hand-painted shop board: a gear and a bolt, no words.
	Art._rect(image, 2, 6, 27, 6, Color("6d5238"))
	Art._rect(image, 6, 7, 4, 4, Color("c45a20"))
	Art._put(image, 7, 8, Color("6d5238"))
	Art._put(image, 8, 9, Color("6d5238"))
	Art._rect(image, 14, 8, 10, 2, Color("d8c08a"))
	# The door: patched planks with personal stickers.
	var plank: Color = Color("5a3a28")
	Art._rect(image, 42, 6, 36, 76, wall.darkened(0.45))
	Art._rect(image, 44, 8, 32, 74, plank)
	for x: int in range(48, 76, 5):
		Art._rect(image, x, 8, 1, 74, plank.darkened(0.3))
	Art._rect(image, 64, 44, 8, 6, Color("6f6a5c"))
	Art._rect(image, 46, 52, 4, 3, Color("8a3a58"))
	Art._rect(image, 69, 60, 4, 4, Color("4f6f68"))
	Art._rect(image, 72, 38, 2, 3, Color("c9a24a"))
	# A new Union seal plate bolted over the door.
	Art._rect(image, 54, 0, 12, 7, Art.UNION_BLACK)
	Art._diamond(image, 60, 3, 3, Art.UNION_RED, Art.BONE)
	# Seal tapes crossing the door, and the recall notice where they meet.
	for step: int in range(36):
		var y: int = 12 + step
		Art._rect(image, 44 + int(float(step) * 0.88), y, 3, 2, Art.UNION_RED)
		Art._rect(image, 73 - int(float(step) * 0.88), y, 3, 2, Art.UNION_RED.darkened(0.12))
	var paper: Color = Color("e6dfcf")
	Art._rect(image, 53, 18, 14, 19, paper)
	Art._rect(image, 53, 18, 14, 4, Art.UNION_RED)
	Art._diamond(image, 56, 19, 1, Art.UNION_BLACK, Art.BONE)
	for row: int in range(4):
		Art._rect(image, 55, 24 + row * 3, 10 - (row % 2) * 3, 1, Color("8f8670"))
	Art._rect(image, 61, 32, 4, 4, Color(Art.UNION_RED, 0.75))
	Art._rect(image, 62, 33, 2, 2, paper)
	# The street, wet, with the window's warm reflection.
	var road: Color = Color("1d1f22")
	Art._rect(image, 0, 82, WIDTH, 8, road)
	Art._rect(image, 0, 81, WIDTH, 1, Color("4a4640"))
	for x: int in range(4, 27, 3):
		Art._rect(image, x, 84 + (x % 2), 2, 1, lit.darkened(0.45))
	# A dropped mug and a wrench on the step.
	Art._rect(image, 18, 78, 4, 3, Color("c4a46a"))
	Art._put(image, 22, 79, Color("c4a46a"))
	Art._rect(image, 6, 80, 8, 1, Color("7c7f7a"))
	Art._rect(image, 5, 79, 2, 3, Color("7c7f7a"))
	# The custody van pulling away, seen from behind. It keeps clear of the
	# frame edge so the shot's slow pan never crops it, and the issued seal,
	# a red tail light and the barred window sit right of the text panel.
	var v: int = 92
	var body: Color = Art.UNION_BLACK
	Art._rect(image, v, 14, 58, 62, body)
	Art._rect(image, v + 2, 12, 54, 2, body)
	Art._rect(image, v, 14, 58, 1, Color("34353b"))
	Art._rect(image, v + 28, 16, 1, 58, Art.UNION_STEEL)
	Art._rect(image, v, 56, 58, 2, Art.UNION_PLATE)
	Art._rect(image, v + 4, 60, 50, 6, Art.UNION_STEEL)
	Art._diamond(image, v + 43, 47, 4, Art.UNION_RED, Art.BONE)
	Art._rect(image, v + 8, 44, 8, 4, Art.UNION_PLATE)
	# Latch behind the barred rear window: tall CRT head, warm phosphor face,
	# the antenna bent against the roof on the viewer's right.
	Art._rect(image, v + 32, 20, 22, 18, Color("0b0c0e"))
	var bone: Color = Color("a48d68")
	Art._rect(image, v + 37, 22, 11, 14, bone)
	Art._rect(image, v + 37, 22, 2, 3, Art.RUST.lightened(0.1))
	Art._rect(image, v + 45, 32, 3, 3, Art.RUST)
	Art._rect(image, v + 39, 24, 7, 8, Color("0b0a06"))
	Art._rect(image, v + 40, 26, 1, 2, Art.PHOSPHOR)
	Art._rect(image, v + 44, 26, 1, 2, Art.PHOSPHOR)
	Art._rect(image, v + 41, 30, 3, 1, Art.PHOSPHOR.darkened(0.25))
	Art._rect(image, v + 48, 21, 1, 2, Color("776349"))
	Art._rect(image, v + 49, 20, 3, 1, Color("776349"))
	for x: int in range(v + 33, v + 54, 3):
		Art._rect(image, x, 20, 1, 18, Art.UNION_PLATE)
	Art._rect(image, v + 32, 28, 22, 1, Art.UNION_PLATE)
	# Tail lights: red on Union hardware, mirrored on the wet road.
	for x: int in [v + 1, v + 53]:
		Art._rect(image, x, 50, 4, 4, Color("d83a2c"))
		Art._rect(image, x, 50, 4, 1, Color("ff7a5a"))
		for y: int in range(83, 90, 2):
			Art._rect(image, x, y, 4, 1, Color("6a1d18"))
	Art._rect(image, v + 4, 76, 10, 6, Color("0b0b0c"))
	Art._rect(image, v + 44, 76, 10, 6, Color("0b0b0c"))
	_scanlines(image, 0.08)
	return image

static func _scanlines(image: Image, amount: float) -> void:
	for y: int in range(1, image.get_height(), 2):
		for x: int in range(image.get_width()):
			image.set_pixel(x, y, image.get_pixel(x, y).darkened(amount))
