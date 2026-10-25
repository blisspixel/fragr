extends SceneTree

## The Rifle (Flechette) keeps its drawn rest and shot; its recovery frames are
## derived from that same rest so they register exactly: a thin smoke wisp
## at the muzzle and the spent case kicking out to the right, then the wisp
## gone and the case falling clear. Also writes the drawn muzzle flash on its
## own (`flash.png`), cut from the Rifle's shot, which `tools/bake_viewmodels.gd`
## stamps on each modelled gun's shot so the whole set shares one flash.
##
##   godot --headless --path client --script res://../tools/bake_flechette_frames.gd

const IDLE: String = "res://assets/weapons/viewmodels/rifle_idle.png"
const FIRE: String = "res://assets/weapons/viewmodels/rifle_fire.png"
const OUT: String = "res://assets/weapons/flechette"
## Only the region above the receiver holds the painted flash.
const FLASH_ROWS: int = 56
const SMOKE: Array[Color] = [Color("5a554f"), Color("8c847a")]
const CASE: Array[Color] = [Color("7a3a22"), Color("c45a20"), Color("dc8c3c")]

func _initialize() -> void:
	var idle: Image = _load(IDLE)
	var fire: Image = _load(FIRE)
	if idle == null or fire == null or idle.get_size() != fire.get_size():
		push_error("bake_flechette_frames: drawn Rifle pair missing or unregistered")
		quit(1)
		return
	# The flash: every texel of the shot that differs from rest above the gun.
	var bounds: Rect2i = Rect2i()
	var found: bool = false
	for y: int in range(FLASH_ROWS):
		for x: int in range(idle.get_width()):
			if fire.get_pixel(x, y) != idle.get_pixel(x, y) and _is_flash(fire.get_pixel(x, y)):
				bounds = Rect2i(x, y, 1, 1) if not found else bounds.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
				found = true
	if not found:
		push_error("bake_flechette_frames: no flash in the drawn shot")
		quit(1)
		return
	var flash: Image = Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	for y: int in range(bounds.size.y):
		for x: int in range(bounds.size.x):
			var at: Vector2i = bounds.position + Vector2i(x, y)
			if fire.get_pixelv(at) != idle.get_pixelv(at) and _is_flash(fire.get_pixelv(at)):
				flash.set_pixel(x, y, fire.get_pixelv(at))
	var muzzle: Vector2i = bounds.get_center()
	var directory: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var first: Image = idle.duplicate()
	_puff(first, muzzle + Vector2i(0, -5), 0)
	_case(first, muzzle + Vector2i(26, 46), 2)
	var second: Image = idle.duplicate()
	_puff(second, muzzle + Vector2i(1, -10), 1)
	_case(second, muzzle + Vector2i(40, 70), 1)
	for pair: Array in [["recover_0", first], ["recover_1", second], ["flash", flash]]:
		if (pair[1] as Image).save_png(directory.path_join(str(pair[0]) + ".png")) != OK:
			push_error("bake_flechette_frames: cannot write " + str(pair[0]))
			quit(1)
			return
	print("bake_flechette_frames: PASS recovery pair and the %dx%d flash" % [bounds.size.x, bounds.size.y])
	quit(0)

## Flame and its white core, not the gun texels the shot frame redrew.
func _is_flash(colour: Color) -> bool:
	return colour.a > 0.5 and (colour.get_luminance() > 0.7 or colour.r > colour.b + 0.25)

func _load(path: String) -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image != null:
		image.convert(Image.FORMAT_RGBA8)
	return image

## A small smoke wisp over the muzzle, thinning as it rises.
func _puff(image: Image, at: Vector2i, stage: int) -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(0, -3), Vector2i(1, -4), Vector2i(-1, 0)]
	for index: int in range(cells.size() - stage * 2):
		var p: Vector2i = at + cells[index]
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(p):
			image.set_pixelv(p, SMOKE[(index + stage) % SMOKE.size()])

## The spent case: a three-texel brass bar with a dark outline, `tilt` 0 to 2.
func _case(image: Image, at: Vector2i, tilt: int) -> void:
	var body: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	if tilt != 2:
		body = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 2)]
	for index: int in range(body.size()):
		var p: Vector2i = at + body[index]
		for edge: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var q: Vector2i = p + edge
			if Rect2i(Vector2i.ZERO, image.get_size()).has_point(q) and image.get_pixelv(q).a < 0.5:
				image.set_pixelv(q, Color("1e1e22"))
	for index: int in range(body.size()):
		var p: Vector2i = at + body[index]
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(p):
			image.set_pixelv(p, CASE[mini(index + 1, CASE.size() - 1)])
