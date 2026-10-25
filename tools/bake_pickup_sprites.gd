extends SceneTree

## Hand-placed pixel sprites for two arena pickups that had no art: the
## Rocket Launcher's side profile and the Custody Plate. Both are drawn from
## the shapes below, so the files can be rebuilt and the drawing reviewed as
## code. No generation service is involved.
##
##   godot --headless --path client --script res://../tools/bake_pickup_sprites.gd
##
## Style follows the existing pickups (`assets/weapons/pickups/railgun.png`,
## `assets/pickups/armor.png`): a dark one-pixel outline inside the
## silhouette, light from the upper left, and a little grit. The Rocket is a
## freed launcher in the olive of its first-person sprite, its approval plate
## ground to bare metal and a round in the tube. The Plate is Union custody
## armour in issued black and steel with the narrow red band, its seal cut
## through by a league blade and the custody lock still on it.

const OUTLINE := Color("141410")
const OLIVE_DARK := Color("2e3424")
const OLIVE_MID := Color("4a5537")
const OLIVE_LIGHT := Color("6b7650")
const OLIVE_HIGHLIGHT := Color("8a9466")
const STEEL_DARK := Color("2a2b2f")
const STEEL_MID := Color("4a4b52")
const STEEL_LIGHT := Color("6e6f76")
const RUST := Color("8a3a22")
const RUST_LIGHT := Color("a85a36")
const RUST_DARK := Color("5a2416")
const WOOD := Color("4a3426")
const WOOD_LIGHT := Color("6a4a32")
const BARE := Color("9c988c")
const BARE_SCRATCH := Color("76736a")

const UNION_BLACK := Color("1e1e22")
const UNION_STEEL := Color("2c2d32")
const UNION_PLATE := Color("3a3b41")
const UNION_EDGE := Color("56575e")
const UNION_RIVET := Color("7d7e86")
const UNION_RED := Color("7a1c18")
const UNION_RED_DARK := Color("561410")
const PLATE_OUTLINE := Color("0c0c0e")
const CUT := Color("b9b5aa")


func _initialize() -> void:
	var root: String = ProjectSettings.globalize_path("res://")
	var jobs: Array = [
		[_rocket(), "assets/weapons/pickups/rocket.png"],
		[_plate(), "assets/pickups/plate.png"],
	]
	for job: Array in jobs:
		var image: Image = job[0]
		var output: String = root.path_join(job[1])
		if image.is_invisible() or image.save_png(output) != OK:
			push_error("bake_pickup_sprites: could not save " + output)
			quit(1)
			return
	print("bake_pickup_sprites: PASS rocket plate")
	quit(0)


func _blank(width: int, height: int) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


func _rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


func _opaque(image: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() \
		and image.get_pixel(x, y).a > 0.5


## Every opaque pixel touching transparency becomes the outline.
func _outline(image: Image, ink: Color) -> void:
	var edge: Array[Vector2i] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if not _opaque(image, x, y):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not _opaque(image, x + d.x, y + d.y):
					edge.append(Vector2i(x, y))
					break
	for p: Vector2i in edge:
		image.set_pixelv(p, ink)


## Deterministic grit: a few interior pixels a shade darker.
func _grit(image: Image, ink: Color, share: int) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c: Color = image.get_pixel(x, y)
			if c.a < 0.5 or c == ink:
				continue
			if absi((x * 73856093) ^ (y * 19349663)) % 100 < share:
				image.set_pixel(x, y, c.darkened(0.18))


func _rocket() -> Image:
	var image := _blank(84, 20)
	# The tube, lit from above: highlight, two light rows, mid, then shadow.
	var rows: Array[Color] = [OLIVE_HIGHLIGHT, OLIVE_LIGHT, OLIVE_LIGHT, OLIVE_MID, OLIVE_MID, OLIVE_MID, OLIVE_DARK, OLIVE_DARK]
	for i in range(rows.size()):
		_rect(image, 8, 6 + i, 76, 6 + i, rows[i])
	# Rear venturi, flaring out past the tube.
	_rect(image, 4, 5, 8, 14, STEEL_MID)
	_rect(image, 1, 4, 3, 15, STEEL_DARK)
	_rect(image, 4, 5, 8, 5, STEEL_LIGHT)
	_rect(image, 1, 4, 3, 4, STEEL_MID)
	# Two clamp bands and the muzzle ring.
	for x: int in [18, 66]:
		_rect(image, x, 5, x + 1, 14, STEEL_DARK)
		_rect(image, x, 5, x + 1, 5, STEEL_MID)
	_rect(image, 76, 5, 79, 14, STEEL_MID)
	_rect(image, 76, 5, 79, 6, STEEL_LIGHT)
	_rect(image, 76, 13, 79, 14, STEEL_DARK)
	# The round in the tube: a rust-red nose cone.
	var nose: Array = [[80, 6, 13], [81, 7, 12], [82, 8, 11], [83, 9, 10]]
	for column: Array in nose:
		_rect(image, column[0], column[1], column[0], column[2], RUST)
		image.set_pixel(column[0], column[1], RUST_LIGHT)
		image.set_pixel(column[0], column[2], RUST_DARK)
	# The approval plate, ground to bare scarred metal.
	_rect(image, 26, 8, 33, 10, BARE)
	for p: Vector2i in [Vector2i(27, 9), Vector2i(29, 8), Vector2i(30, 9), Vector2i(32, 10)]:
		image.set_pixelv(p, BARE_SCRATCH)
	# Shoulder pad, receiver, sight, grips and trigger guard.
	_rect(image, 21, 14, 32, 16, WOOD)
	_rect(image, 22, 14, 31, 14, WOOD_LIGHT)
	_rect(image, 36, 14, 58, 16, STEEL_MID)
	_rect(image, 37, 14, 57, 14, STEEL_LIGHT)
	_rect(image, 49, 4, 56, 5, STEEL_DARK)
	_rect(image, 51, 0, 54, 4, STEEL_MID)
	_rect(image, 52, 1, 53, 1, STEEL_LIGHT)
	var grip: Array = [[45, 50, 17], [44, 49, 18], [44, 49, 19]]
	for row: Array in grip:
		_rect(image, row[0], row[2], row[1], row[2], WOOD)
		image.set_pixel(row[0] + 2, row[2], WOOD_LIGHT)
	_rect(image, 51, 17, 51, 18, STEEL_DARK)
	_rect(image, 55, 17, 55, 18, STEEL_DARK)
	_rect(image, 52, 18, 54, 18, STEEL_DARK)
	_rect(image, 61, 14, 65, 18, WOOD)
	_rect(image, 62, 15, 62, 17, WOOD_LIGHT)
	_outline(image, OUTLINE)
	_grit(image, OUTLINE, 9)
	return image


## Left edge of the cuirass on row `y`, or -1 where the row is empty.
static func _plate_left(y: int) -> int:
	if y < 2 or y > 33:
		return -1
	if y <= 7:
		return 6
	if y <= 15:
		return 9
	if y <= 26:
		return 5
	return [6, 7, 9, 11, 13, 15, 17][y - 27]


## Columns cut away for the neck on row `y` (inclusive), or an empty range.
static func _neck(y: int) -> Vector2i:
	match y:
		2: return Vector2i(14, 27)
		3, 4: return Vector2i(15, 26)
		5: return Vector2i(16, 25)
		6: return Vector2i(17, 24)
		7: return Vector2i(18, 23)
		8: return Vector2i(19, 22)
	return Vector2i(1, 0)


func _plate() -> Image:
	var width := 42
	var image := _blank(width, 36)
	for y in range(image.get_height()):
		var left: int = _plate_left(y)
		if left < 0:
			continue
		var right: int = width - 1 - left
		_rect(image, left, y, right, y, UNION_STEEL)
		var neck: Vector2i = _neck(y)
		for x in range(neck.x, neck.y + 1):
			image.set_pixel(x, y, Color(0, 0, 0, 0))
	# Two pressed panels either side of a raised centre ridge, lit from the
	# upper left, with black shadow on the lower right of each.
	for y in range(9, 31):
		for x in range(width):
			if image.get_pixel(x, y).a < 0.5:
				continue
			var c: Color = UNION_PLATE if x < 20 else UNION_STEEL
			if x >= 22 and y > 20:
				c = UNION_BLACK
			image.set_pixel(x, y, c)
	_rect(image, 20, 8, 21, 31, UNION_EDGE)
	_rect(image, 21, 8, 21, 31, UNION_PLATE)
	# Shoulder straps catch the light.
	_rect(image, 6, 2, 13, 3, UNION_EDGE)
	_rect(image, 28, 2, 35, 3, UNION_PLATE)
	# The narrow red band across the chest.
	for x in range(width):
		if image.get_pixel(x, 18).a > 0.5:
			image.set_pixel(x, 18, UNION_RED)
		if image.get_pixel(x, 19).a > 0.5:
			image.set_pixel(x, 19, UNION_RED_DARK)
	# The registration seal over the heart, cut through by a league blade.
	var seal := Vector2(21.0, 12.5)
	for y in range(7, 19):
		for x in range(15, 28):
			var d: float = Vector2(x, y).distance_to(seal)
			if d <= 4.6 and d > 3.4:
				image.set_pixel(x, y, UNION_RIVET)
			elif d <= 3.4:
				image.set_pixel(x, y, UNION_BLACK)
	for i in range(9):
		image.set_pixel(17 + i, 8 + i, CUT)
		if i % 2 == 0:
			image.set_pixel(18 + i, 8 + i, BARE_SCRATCH)
	# Rivets down both edges and along the straps.
	for y in [4, 11, 15, 22, 26]:
		var left: int = _plate_left(y)
		image.set_pixel(left + 2, y, UNION_RIVET)
		image.set_pixel(width - 3 - left, y, UNION_RIVET)
	# The custody lock, still on: a steel padlock low on the plate.
	_rect(image, 19, 28, 23, 31, UNION_EDGE)
	_rect(image, 19, 28, 23, 28, UNION_RIVET)
	image.set_pixel(21, 30, UNION_BLACK)
	_rect(image, 20, 26, 20, 27, UNION_RIVET)
	_rect(image, 22, 26, 22, 27, UNION_RIVET)
	image.set_pixel(21, 25, UNION_RIVET)
	_outline(image, PLATE_OUTLINE)
	_grit(image, PLATE_OUTLINE, 7)
	return image
