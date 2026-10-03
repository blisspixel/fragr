extends SceneTree

## Bakes the Sabotage pictures that must register exactly or carry letters:
## the A and B site plates (stencil letters over one generated Union plate),
## the planted charge's timer states (over one generated planted charge) and
## the plant and defuse progress icons (drawn here in palette colours). The
## sources in `client/art/sabotage/` are reduced generated pictures recorded
## in `client/assets/art-pass-2-20261002-manifest.json`. Run from the
## repository root:
##   godot --headless --path client --script ../tools/bake_sabotage_art.gd

const SOURCE_DIR: String = "art/sabotage"
const OUT_DIR: String = "assets/sabotage"

const INK: Color = Color8(10, 10, 12)
const BONE: Color = Color8(232, 226, 214)
const GUNMETAL_DARK: Color = Color8(58, 56, 54)
const GUNMETAL: Color = Color8(90, 85, 79)
const GUNMETAL_LIGHT: Color = Color8(140, 132, 122)
const RUST: Color = Color8(122, 58, 34)
const DUST_RUST: Color = Color8(159, 91, 59)
const EMBER: Color = Color8(196, 90, 32)
const EMBER_HOT: Color = Color8(220, 140, 60)
const ON_AIR: Color = Color8(139, 30, 30)
const BLOOD: Color = Color8(110, 18, 24)
const LEAF: Color = Color8(116, 136, 78)
const UNION_BLACK: Color = Color8(30, 30, 34)
const UNION_STEEL: Color = Color8(44, 45, 50)
const UNION_RED: Color = Color8(140, 26, 30)
const RED_GLOW: Color = Color8(226, 52, 48)

## Bold five by seven letters, drawn four pixels to a cell on the plate.
const LETTERS: Dictionary[String, Array] = {
	"a": [".###.", "##.##", "##.##", "#####", "##.##", "##.##", "##.##"],
	"b": ["####.", "##.##", "##.##", "####.", "##.##", "##.##", "####."],
}
const LETTER_SCALE: int = 4
## The generated plate's blank centre panel, inside its bevel, in pixels.
const PANEL: Rect2i = Rect2i(7, 9, 34, 31)

## The planted charge's timer box: the display window and the status lamp.
const DISPLAY: Rect2i = Rect2i(19, 4, 5, 3)
const LAMP: Rect2i = Rect2i(26, 9, 2, 2)

var _root: String = ""

func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://")
	DirAccess.make_dir_recursive_absolute(_root.path_join(OUT_DIR))
	var plate: Image = _load("site_plate.png")
	var planted: Image = _load("charge_planted.png")
	if plate == null or planted == null:
		quit(1)
		return
	for site: String in LETTERS:
		if not _save(_lettered(plate, site), "plate_%s.png" % site):
			return
	var states: Dictionary[String, Array] = {
		# Armed: a dull red display with a lit bar, the lamp on.
		"charge_planted": [ON_AIR, RED_GLOW, RED_GLOW, true],
		# The blink between flashes: the same display, the lamp off.
		"charge_planted_off": [ON_AIR, RED_GLOW, BLOOD, false],
		# The last seconds: the whole display hot, the lamp on.
		"charge_planted_late": [RED_GLOW, BONE, RED_GLOW, true],
		# Defused: a dead display and a green lamp.
		"charge_planted_defused": [INK, INK, LEAF, false],
	}
	for state: String in states:
		var colours: Array = states[state]
		if not _save(_timer(planted, colours[0], colours[1], colours[2], colours[3]), state + ".png"):
			return
	if not _save(_icon_plant(), "icon_plant.png") or not _save(_icon_defuse(), "icon_defuse.png"):
		return
	print("bake_sabotage_art: PASS ", OUT_DIR)
	quit(0)

func _load(file: String) -> Image:
	var image: Image = Image.load_from_file(_root.path_join(SOURCE_DIR).path_join(file))
	if image == null or image.is_empty():
		push_error("bake_sabotage_art: cannot read " + file)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image

func _save(image: Image, file: String) -> bool:
	if image.save_png(_root.path_join(OUT_DIR).path_join(file)) != OK:
		push_error("bake_sabotage_art: could not write " + file)
		quit(1)
		return false
	return true

## The plate with its speckled panel made one flat colour and a bone letter
## with an ink drop shadow centred on it.
func _lettered(plate: Image, site: String) -> Image:
	var image: Image = plate.duplicate()
	for y: int in range(PANEL.position.y, PANEL.end.y):
		for x: int in range(PANEL.position.x, PANEL.end.x):
			if image.get_pixel(x, y).is_equal_approx(UNION_STEEL):
				image.set_pixel(x, y, UNION_BLACK)
	var rows: Array = LETTERS[site]
	var size: Vector2i = Vector2i(str(rows[0]).length(), rows.size()) * LETTER_SCALE
	var origin: Vector2i = PANEL.position + (PANEL.size - size) / 2
	for pass_index: int in range(2):
		var offset: Vector2i = Vector2i(1, 1) if pass_index == 0 else Vector2i.ZERO
		var colour: Color = INK if pass_index == 0 else BONE
		for row: int in range(rows.size()):
			var line: String = rows[row]
			for column: int in range(line.length()):
				if line[column] == "#":
					image.fill_rect(Rect2i(origin + offset + Vector2i(column, row) * LETTER_SCALE,
						Vector2i.ONE * LETTER_SCALE), colour)
	return image

## The planted charge with its display and lamp in one timer state.
func _timer(planted: Image, display: Color, bar: Color, lamp: Color, glint: bool) -> Image:
	var image: Image = planted.duplicate()
	image.fill_rect(DISPLAY, display)
	image.fill_rect(Rect2i(DISPLAY.position + Vector2i(1, 1), Vector2i(DISPLAY.size.x - 2, 1)), bar)
	image.fill_rect(LAMP, lamp)
	if glint:
		image.set_pixelv(LAMP.position, BONE)
	return image

## A 24 pixel icon from filled shapes, then a one pixel ink outline around
## everything drawn, so it reads over any part of the HUD.
func _blank_icon() -> Image:
	var image: Image = Image.create_empty(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image

func _outline(image: Image) -> void:
	var source: Image = image.duplicate()
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if source.get_pixel(x, y).a > 0.5:
				continue
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var near: Vector2i = Vector2i(x, y) + step
				if near.x >= 0 and near.y >= 0 and near.x < image.get_width() and near.y < image.get_height() \
					and source.get_pixelv(near).a > 0.5:
					image.set_pixel(x, y, INK)
					break

func _line(image: Image, from: Vector2, to: Vector2, width: float, colour: Color) -> void:
	var length: float = from.distance_to(to)
	var steps: int = maxi(1, ceili(length * 2.0))
	for index: int in range(steps + 1):
		var at: Vector2 = from.lerp(to, float(index) / steps)
		for y: int in range(floori(at.y - width * 0.5), ceili(at.y + width * 0.5)):
			for x: int in range(floori(at.x - width * 0.5), ceili(at.x + width * 0.5)):
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					image.set_pixel(x, y, colour)

## Plant: an ember arrow driving down onto the charge.
func _icon_plant() -> Image:
	var image: Image = _blank_icon()
	image.fill_rect(Rect2i(9, 1, 6, 5), EMBER_HOT)
	for row: int in range(5):
		image.fill_rect(Rect2i(5 + row, 6 + row, 14 - row * 2, 1), EMBER_HOT)
	image.fill_rect(Rect2i(10, 1, 2, 7), BONE)
	# The charge: bone blocks, two leather straps and the dark timer box.
	image.fill_rect(Rect2i(2, 14, 20, 8), BONE)
	image.fill_rect(Rect2i(2, 20, 20, 2), GUNMETAL_LIGHT)
	image.fill_rect(Rect2i(2, 17, 20, 1), GUNMETAL_LIGHT)
	for x: int in [5, 16]:
		image.fill_rect(Rect2i(x, 14, 3, 8), RUST)
		image.fill_rect(Rect2i(x, 14, 1, 8), DUST_RUST)
	image.fill_rect(Rect2i(9, 12, 6, 4), GUNMETAL_DARK)
	image.fill_rect(Rect2i(10, 13, 2, 1), ON_AIR)
	image.set_pixel(13, 13, RED_GLOW)
	_outline(image)
	return image

## Defuse: wire cutters closing on one ember wire.
func _icon_defuse() -> Image:
	var image: Image = _blank_icon()
	# The wire, already parted under the jaws.
	_line(image, Vector2(1, 6.5), Vector2(10, 6.5), 2.0, EMBER)
	_line(image, Vector2(14, 6.5), Vector2(23, 6.5), 2.0, EMBER)
	image.set_pixel(10, 6, EMBER_HOT)
	image.set_pixel(13, 6, EMBER_HOT)
	# Jaws and pivot.
	_line(image, Vector2(9, 3), Vector2(12.5, 11), 2.5, GUNMETAL_LIGHT)
	_line(image, Vector2(15, 3), Vector2(11.5, 11), 2.5, GUNMETAL_LIGHT)
	_line(image, Vector2(9, 3), Vector2(10, 5), 1.0, BONE)
	_line(image, Vector2(15, 3), Vector2(14, 5), 1.0, BONE)
	image.fill_rect(Rect2i(10, 9, 4, 4), BONE)
	image.fill_rect(Rect2i(11, 10, 2, 2), GUNMETAL)
	# Union-red handles spread below.
	_line(image, Vector2(11, 13), Vector2(5, 22), 3.0, UNION_RED)
	_line(image, Vector2(13, 13), Vector2(19, 22), 3.0, UNION_RED)
	_line(image, Vector2(11, 14), Vector2(6, 21), 1.0, RED_GLOW)
	_line(image, Vector2(13, 14), Vector2(18, 21), 1.0, RED_GLOW)
	_outline(image)
	return image
