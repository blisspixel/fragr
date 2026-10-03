extends SceneTree

## Bakes the Proximity Mine's lamp states over one generated face-on device, so
## every state registers exactly: dark (flying, or the blink between flashes),
## arming (a steady amber lamp) and live (a lit red lamp with a bone glint).
## The source is `client/art/custody/mine_face.png`, the reduced generated
## device recorded in `client/assets/art-pass-2-20261002-manifest.json`. Run
## from the repository root:
##   godot --headless --path client --script ../tools/bake_custody_art.gd

const SOURCE: String = "art/custody/mine_face.png"
const OUT_DIR: String = "assets/weapons/mine"

const INK: Color = Color8(10, 10, 12)
const BONE: Color = Color8(232, 226, 214)
const BLOOD: Color = Color8(110, 18, 24)
const UNION_BLACK: Color = Color8(30, 30, 34)
const UNION_RED: Color = Color8(140, 26, 30)
const RED_GLOW: Color = Color8(226, 52, 48)
const EMBER: Color = Color8(196, 90, 32)
const EMBER_HOT: Color = Color8(220, 140, 60)

## The lens is the red cluster nearest the centre of the face; this radius
## bounds the search so the rim's red seal stripe is never mistaken for it.
const LENS_RADIUS: float = 5.0
## Radius of the lit lens the states paint, in pixels.
const LENS_DISC: float = 2.6

func _initialize() -> void:
	var root: String = ProjectSettings.globalize_path("res://")
	var face: Image = Image.load_from_file(root.path_join(SOURCE))
	if face == null or face.is_empty():
		push_error("bake_custody_art: cannot read " + SOURCE)
		quit(1)
		return
	face.convert(Image.FORMAT_RGBA8)
	var lens: Array[Vector2i] = []
	var centre: Vector2 = Vector2(face.get_width(), face.get_height()) * 0.5
	for y: int in range(face.get_height()):
		for x: int in range(face.get_width()):
			var colour: Color = face.get_pixel(x, y)
			if colour.a < 0.5 or (Vector2(x + 0.5, y + 0.5) - centre).length() > LENS_RADIUS:
				continue
			if colour.is_equal_approx(UNION_RED):
				lens.append(Vector2i(x, y))
	if lens.size() < 4:
		push_error("bake_custody_art: no lens found near the centre of " + SOURCE)
		quit(1)
		return
	# Read at room distance the generated three pixel lens is too small, so the
	# lit lens grows to a five pixel disc in a one pixel collar, centred where
	# the generated lens was and painted only over the device itself.
	var middle: Vector2 = Vector2.ZERO
	for point: Vector2i in lens:
		middle += Vector2(point) + Vector2(0.5, 0.5)
	middle /= lens.size()
	lens.clear()
	var rim: Array[Vector2i] = []
	for y: int in range(face.get_height()):
		for x: int in range(face.get_width()):
			var distance: float = (Vector2(x + 0.5, y + 0.5) - middle).length()
			if face.get_pixel(x, y).a < 0.5 or distance > LENS_DISC + 1.0:
				continue
			if distance <= LENS_DISC:
				lens.append(Vector2i(x, y))
			else:
				rim.append(Vector2i(x, y))
	var top: Vector2i = Vector2i(floori(middle.x) - 1, floori(middle.y) - 1)
	var states: Dictionary[String, Array] = {
		"mine_dark": [BLOOD, UNION_BLACK, null],
		"mine_arming": [EMBER_HOT, EMBER, BONE],
		"mine_live": [RED_GLOW, UNION_RED, BONE],
	}
	var out_dir: String = root.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for state: String in states:
		var colours: Array = states[state]
		var image: Image = face.duplicate()
		for point: Vector2i in lens:
			image.set_pixelv(point, colours[0])
		for point: Vector2i in rim:
			image.set_pixelv(point, colours[1])
		if colours[2] != null:
			image.set_pixelv(top, colours[2])
		if image.save_png(out_dir.path_join(state + ".png")) != OK:
			push_error("bake_custody_art: could not write " + state)
			quit(1)
			return
	print("bake_custody_art: PASS ", OUT_DIR, " lens ", lens.size(), " rim ", rim.size())
	quit(0)
