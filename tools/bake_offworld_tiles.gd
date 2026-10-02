extends SceneTree

## Offline seam preparation and inspection for the bounded offworld batch.
## Run from client with --script ../tools/bake_offworld_tiles.gd.
## Existing local reducer supplies palette reduction before and after blending.
const IDS: Array[String] = ["mars_basalt", "mars_regolith", "offworld_pressure_habitat", "offworld_mining_deck", "offworld_thermal_ceramic"]
const SIZE: int = 128
const BAND: int = 8
const SOURCE: String = "res://art/environment/offworld-batch-20261001/reduced"
const INTERMEDIATE: String = "res://../.agents/m06-buildout-20261001/offworld-seamed"
const OUTPUT: String = "res://assets/environment/offworld"
const PROOFS: String = "res://../.agents/m06-buildout-20261001/offworld-preview"

func _initialize() -> void:
	if "--verify" in OS.get_cmdline_user_args():
		_verify()
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INTERMEDIATE)) != OK:
		_fail("cannot create intermediate directory")
		return
	for id: String in IDS:
		var image: Image = Image.load_from_file(SOURCE.path_join(id + "_0.png"))
		if image == null or image.get_size() != Vector2i(SIZE, SIZE):
			_fail("missing or wrong-size reduced source: " + id)
			return
		image.convert(Image.FORMAT_RGBA8)
		# Symmetric opposing edge blends are limited to eight pixels. Interior
		# material forms remain intact; the repeated preview decides acceptance.
		var horizontal: Image = image.duplicate() as Image
		for y: int in range(SIZE):
			for offset: int in range(BAND):
				var left: Color = image.get_pixel(offset, y)
				var right: Color = image.get_pixel(SIZE - 1 - offset, y)
				var average: Color = left.lerp(right, 0.5)
				var weight: float = 1.0 - float(offset) / float(BAND)
				horizontal.set_pixel(offset, y, left.lerp(average, weight))
				horizontal.set_pixel(SIZE - 1 - offset, y, right.lerp(average, weight))
		var seamless: Image = horizontal.duplicate() as Image
		for x: int in range(SIZE):
			for offset: int in range(BAND):
				var top: Color = horizontal.get_pixel(x, offset)
				var bottom: Color = horizontal.get_pixel(x, SIZE - 1 - offset)
				var average: Color = top.lerp(bottom, 0.5)
				var weight: float = 1.0 - float(offset) / float(BAND)
				seamless.set_pixel(x, offset, top.lerp(average, weight))
				seamless.set_pixel(x, SIZE - 1 - offset, bottom.lerp(average, weight))
		if seamless.save_png(ProjectSettings.globalize_path(INTERMEDIATE.path_join(id + ".png"))) != OK:
			_fail("cannot save intermediate: " + id)
			return
	print("offworld seam preparation: PASS five 128px intermediates, palette reduction still required")
	quit()

func _verify() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	if not parsed is Dictionary:
		_fail("invalid palette")
		return
	var palette: Array[Color] = []
	for name: Variant in parsed:
		var channels: Variant = parsed[name]
		if not channels is Array or channels.size() != 4:
			_fail("invalid palette channels")
			return
		palette.append(Color8(int(channels[0]), int(channels[1]), int(channels[2]), int(channels[3])))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROOFS)) != OK:
		_fail("cannot create preview directory")
		return
	var report: Array[Dictionary] = []
	var board: Image = Image.create_empty(SIZE * 6, SIZE * 6, false, Image.FORMAT_RGBA8)
	board.fill(Color("1e1e22"))
	for index: int in range(IDS.size()):
		var id: String = IDS[index]
		var image: Image = Image.load_from_file(OUTPUT.path_join(id + ".png"))
		if image == null or image.get_size() != Vector2i(SIZE, SIZE):
			_fail("missing or wrong-size keeper: " + id)
			return
		image.convert(Image.FORMAT_RGBA8)
		var colors: Dictionary[String, int] = {}
		var minimum: float = 1.0
		var maximum: float = 0.0
		var sum: float = 0.0
		for y: int in range(SIZE):
			for x: int in range(SIZE):
				var color: Color = image.get_pixel(x, y)
				if color.a != 1.0 or not palette.has(color):
					_fail("nonopaque or off-palette keeper: " + id)
					return
				var key: String = color.to_html(false)
				colors[key] = int(colors.get(key, 0)) + 1
				var value: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
				minimum = minf(minimum, value)
				maximum = maxf(maximum, value)
				sum += value
		for position: int in range(SIZE):
			if image.get_pixel(0, position) != image.get_pixel(SIZE - 1, position) or image.get_pixel(position, 0) != image.get_pixel(position, SIZE - 1):
				_fail("opposing boundary mismatch: " + id)
				return
		var repeated: Image = Image.create_empty(SIZE * 3, SIZE * 3, false, Image.FORMAT_RGBA8)
		for row: int in range(3):
			for column: int in range(3):
				repeated.blit_rect(image, Rect2i(0, 0, SIZE, SIZE), Vector2i(column * SIZE, row * SIZE))
		repeated.resize(SIZE * 6, SIZE * 6, Image.INTERPOLATE_NEAREST)
		if repeated.save_png(ProjectSettings.globalize_path(PROOFS.path_join(id + "_repeat.png"))) != OK:
			_fail("cannot save repeated preview")
			return
		var native: Image = image.duplicate() as Image
		native.resize(SIZE * 2, SIZE * 2, Image.INTERPOLATE_NEAREST)
		board.blit_rect(native, Rect2i(0, 0, SIZE * 2, SIZE * 2), Vector2i((index % 3) * SIZE * 2, floori(float(index) / 3.0) * SIZE * 2))
		report.append({"id": id, "size": [SIZE, SIZE], "opaque": true, "palette_colors": colors, "boundary_match": true,
			"value_min": minimum, "value_max": maximum, "value_mean": sum / float(SIZE * SIZE), "sha256": FileAccess.get_sha256(OUTPUT.path_join(id + ".png"))})
	if board.save_png(ProjectSettings.globalize_path(PROOFS.path_join("material_board.png"))) != OK:
		_fail("cannot save material board")
		return
	var file: FileAccess = FileAccess.open(PROOFS.path_join("verification.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write verification receipt")
		return
	file.store_string(JSON.stringify({"tiles": report, "note": "Exact opposite boundaries and palette membership are measured; repeated visual inspection remains required."}, "  ") + "\n")
	file.close()
	print("offworld tile verification: PASS five opaque palette tiles with exact opposing boundaries and repeated previews")
	quit()

func _fail(message: String) -> void:
	push_error("offworld tiles: " + message)
	quit(1)
