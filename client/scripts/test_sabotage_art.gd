extends SceneTree

## Checks the Sabotage art at the paths `SabotageArt` loads by key: every file
## imports as a pixel sprite without mipmaps, the two site plates share one
## canvas and differ only in their letter, the planted charge's timer states
## share one canvas and differ only at the timer box, the first-person frames
## share the weapon canvas, and the progress icons are distinct 24 pixel glyphs.

const DIR: String = "res://assets/sabotage/"
const VIEWMODELS: String = "res://assets/weapons/viewmodels/"
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_sabotage_art: " + message)

func _image(path: String) -> Image:
	var texture: Variant = load(path)
	if not texture is Texture2D:
		_check(false, path + " loads as a texture")
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var image: Image = (texture as Texture2D).get_image()
	_check(not image.has_mipmaps(), path + " has no mipmaps")
	return image

## The bounding box of pixels that differ between two same-sized images.
func _difference(first: Image, second: Image) -> Rect2i:
	var changed: Rect2i = Rect2i()
	var any: bool = false
	for y: int in range(first.get_height()):
		for x: int in range(first.get_width()):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				changed = Rect2i(x, y, 1, 1) if not any else changed.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
				any = true
	return changed

func _run() -> void:
	for key: String in ["charge", "prop_a", "prop_b"]:
		var image: Image = _image(DIR + key + ".png")
		_check(image.get_used_rect().size.x > 16 and image.get_used_rect().size.y > 16, key + " is drawn")
	_check(_image(DIR + "prop_a.png").get_height() == _image(DIR + "prop_b.png").get_height(),
		"both site props stand at one pixel height")
	var plate_a: Image = _image(DIR + "plate_a.png")
	var plate_b: Image = _image(DIR + "plate_b.png")
	_check(plate_a.get_size() == plate_b.get_size(), "the site plates share one canvas")
	var letter: Rect2i = _difference(plate_a, plate_b)
	_check(letter.size != Vector2i.ZERO and Rect2i(Vector2i(4, 4), plate_a.get_size() - Vector2i(8, 8)).encloses(letter),
		"A and B differ only inside the plate's panel: %s" % letter)
	var armed: Image = _image(DIR + "charge_planted.png")
	var box: Rect2i = Rect2i()
	for state: String in ["off", "late", "defused"]:
		var image: Image = _image(DIR + "charge_planted_%s.png" % state)
		_check(image.get_size() == armed.get_size(), state + " shares the planted canvas")
		var changed: Rect2i = _difference(armed, image)
		_check(changed.size != Vector2i.ZERO, state + " reads differently from armed")
		box = changed if box.size == Vector2i.ZERO else box.merge(changed)
	_check(box.size.x <= 10 and box.size.y <= 8, "timer states change only the timer box: %s" % box)
	var weapon_canvas: Vector2i = _image(VIEWMODELS + "pistol_idle.png").get_size()
	for frame: String in ["charge_carry", "charge_plant", "charge_defuse"]:
		_check(_image(VIEWMODELS + frame + ".png").get_size() == weapon_canvas, frame + " shares the weapon canvas")
	var plant: Image = _image(DIR + "icon_plant.png")
	var defuse: Image = _image(DIR + "icon_defuse.png")
	_check(plant.get_size() == Vector2i(24, 24) and defuse.get_size() == Vector2i(24, 24), "progress icons are 24 pixels")
	_check(_difference(plant, defuse).size.x > 12, "plant and defuse icons are distinct glyphs")
	if failures == 0:
		print("test_sabotage_art: PASS keyed sprites, letter-only plates, timer-box-only states, hand frames, icons")
	quit(0 if failures == 0 else 1)
