extends SceneTree

## Kill-feed glyphs, 48x16, one per weapon: a flat bone silhouette with
## gunmetal detail and a one-texel ink edge, so it reads on the feed's dark
## rows and on the bone row of the viewer's own frag. The modelled guns get
## theirs from `tools/bake_viewmodels.gd` (the same `glyph` below, from the
## model's side view); this headless pass derives the rest from each weapon's
## world profile, or from a hand picture for the Fists. Writes
## `res://assets/weapons/kill/<weapon>.png`.
##
##   godot --headless --path client --script ../tools/bake_kill_icons.gd

const SIZE: Vector2i = Vector2i(48, 16)
const BONE: Color = Color("e8e2d6")
const DETAIL: Color = Color("8c847a")
const INK: Color = Color("0a0a0c")
## Weapons without a model, by file name, and the picture each comes from.
const SOURCES: Dictionary[String, String] = {
	"flechette": "res://assets/weapons/pickups/rifle.png",
	"sniper": "res://assets/weapons/sniper-source-20261004/sniper.png",
	"shiv": "res://assets/weapons/48/shiv.png",
	"arc": "res://assets/weapons/arc/arc_profile.png",
	"rocket": "res://assets/weapons/pickups/rocket.png",
	"article_blade": "res://assets/weapons/pickups/article_blade.png",
	"fists": "res://assets/weapons/viewmodels/fists_idle.png",
}

## Fit a picture's opaque pixels into the glyph's inner box and paint it flat.
static func glyph(source: Image) -> Image:
	var picture: Image = source.duplicate()
	picture.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = picture.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	picture = picture.get_region(used)
	var inner: Vector2i = SIZE - Vector2i(2, 2)
	var scale: float = minf(float(inner.x) / used.size.x, float(inner.y) / used.size.y)
	var fitted: Vector2i = Vector2i(maxi(1, roundi(used.size.x * scale)), maxi(1, roundi(used.size.y * scale)))
	if fitted != used.size:
		picture.resize(fitted.x, fitted.y, Image.INTERPOLATE_NEAREST)
	var icon: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var offset: Vector2i = (SIZE - fitted) / 2
	for y: int in range(fitted.y):
		for x: int in range(fitted.x):
			var colour: Color = picture.get_pixel(x, y)
			if colour.a < 0.5:
				continue
			icon.set_pixel(x + offset.x, y + offset.y, BONE if colour.get_luminance() > 0.13 else DETAIL)
	var edged: Image = icon.duplicate()
	for y: int in range(SIZE.y):
		for x: int in range(SIZE.x):
			if icon.get_pixel(x, y).a > 0.5:
				continue
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + step
				if q.x >= 0 and q.y >= 0 and q.x < SIZE.x and q.y < SIZE.y and icon.get_pixel(q.x, q.y).a > 0.5:
					edged.set_pixel(x, y, INK)
					break
	return edged

## Nearest-sampled rotation about the centre onto a canvas large enough.
static func _rotated(source: Image, angle: float) -> Image:
	var side: int = ceili(Vector2(source.get_size()).length())
	var result: Image = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var centre: Vector2 = Vector2(source.get_size()) * 0.5
	for y: int in range(side):
		for x: int in range(side):
			var from: Vector2 = (Vector2(x, y) - Vector2(side, side) * 0.5).rotated(-angle) + centre
			var at: Vector2i = Vector2i(floori(from.x), floori(from.y))
			if at.x >= 0 and at.y >= 0 and at.x < source.get_width() and at.y < source.get_height():
				result.set_pixel(x, y, source.get_pixelv(at))
	return result

func _initialize() -> void:
	var directory: String = ProjectSettings.globalize_path("res://assets/weapons/kill")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("bake_kill_icons: cannot create " + directory)
		quit(1)
		return
	for weapon: String in SOURCES:
		var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCES[weapon]))
		if source == null:
			push_error("bake_kill_icons: missing " + SOURCES[weapon])
			quit(1)
			return
		match weapon:
			"fists":
				# One fist from the pair: the right glove, knuckles up.
				source = source.get_region(Rect2i(121, 0, 120, 112))
			"article_blade":
				# The blade without its plinth.
				source = source.get_region(Rect2i(0, 0, source.get_width(), source.get_height() / 2))
			"shiv":
				# Laid flat so it reads along the row like the guns.
				source = _rotated(source, deg_to_rad(-48.0))
		if glyph(source).save_png(directory.path_join(weapon + ".png")) != OK:
			push_error("bake_kill_icons: cannot write " + weapon)
			quit(1)
			return
	print("bake_kill_icons: PASS %d glyphs" % SOURCES.size())
	quit(0)
