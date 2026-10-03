extends SceneTree
## Offline edge preparation, before the existing palette reducer's final pass.
## godot --headless --path client --script ../tools/prepare_earth_tiles.gd -- --input=DIR --out=DIR

const SIZE: int = 128
const BAND: int = 8

func _initialize() -> void:
	var input: String = ""
	var output: String = ""
	var verify: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="):
			input = argument.trim_prefix("--input=")
		elif argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		elif argument == "--verify":
			verify = true
		else:
			_fail("unknown argument")
			return
	if input.is_empty() or output.is_empty() or input == output:
		_fail("distinct input and output directories are required")
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("cannot create output directory")
		return
	var directory: DirAccess = DirAccess.open(input)
	if directory == null:
		_fail("cannot open input directory")
		return
	var prepared: Array[Dictionary] = []
	for filename: String in directory.get_files():
		if not filename.ends_with(".png") or filename.contains("preview") or filename.ends_with("_repeat.png"):
			continue
		var source: String = input.path_join(filename)
		var image: Image = Image.load_from_file(source)
		if image == null or image.get_width() != SIZE or image.get_height() != SIZE:
			_fail("expected a 128-square source: " + filename)
			return
		image.convert(Image.FORMAT_RGBA8)
		for y: int in SIZE:
			for x: int in SIZE:
				if image.get_pixel(x, y).a != 1.0:
					_fail("source is not fully opaque: " + filename)
					return
		var before: Dictionary = metrics(image)
		var horizontal: Image = image.duplicate()
		for y: int in SIZE:
			for x: int in BAND:
				var other: int = SIZE - 1 - x
				var weight: float = 1.0 - float(x) / float(BAND)
				var average: Color = image.get_pixel(x, y).lerp(image.get_pixel(other, y), 0.5)
				horizontal.set_pixel(x, y, average if x == 0 else image.get_pixel(x, y).lerp(average, weight))
				horizontal.set_pixel(other, y, average if x == 0 else image.get_pixel(other, y).lerp(average, weight))
		var tile: Image = horizontal.duplicate()
		for x: int in SIZE:
			for y: int in BAND:
				var other: int = SIZE - 1 - y
				var weight: float = 1.0 - float(y) / float(BAND)
				var average: Color = horizontal.get_pixel(x, y).lerp(horizontal.get_pixel(x, other), 0.5)
				tile.set_pixel(x, y, average if y == 0 else horizontal.get_pixel(x, y).lerp(average, weight))
				tile.set_pixel(x, other, average if y == 0 else horizontal.get_pixel(x, other).lerp(average, weight))
		if verify:
			tile = image
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
			if not parsed is Dictionary:
				_fail("cannot read canonical palette")
				return
			var colors: Dictionary[int, bool] = {}
			for channels: Variant in parsed.values():
				if not channels is Array or channels.size() != 4:
					_fail("invalid palette entry")
					return
				colors[Color8(int(channels[0]), int(channels[1]), int(channels[2]), int(channels[3])).to_rgba32()] = true
			for y: int in SIZE:
				for x: int in SIZE:
					if not colors.has(tile.get_pixel(x, y).to_rgba32()):
						_fail("final tile has a non-palette color")
						return
		var destination: String = output.path_join(filename)
		if tile.save_png(destination) != OK:
			_fail("cannot save prepared tile")
			return
		var after: Dictionary = metrics(tile)
		if after["edge_max"] > 0.00001:
			_fail("opposing prepared edges differ")
			return
		var repeat: Image = Image.create_empty(SIZE * 3, SIZE * 3, false, Image.FORMAT_RGBA8)
		for row: int in 3:
			for column: int in 3:
				repeat.blit_rect(tile, Rect2i(0, 0, SIZE, SIZE), Vector2i(column * SIZE, row * SIZE))
		repeat.save_png(output.path_join(filename.get_basename() + "_repeat.png"))
		prepared.append({"file": filename, "source_sha256": FileAccess.get_sha256(source), "before": before, "after": after})
	if prepared.is_empty():
		_fail("no source tiles")
		return
	var receipt: FileAccess = FileAccess.open(output.path_join("edge-preparation.json"), FileAccess.WRITE)
	if receipt == null:
		_fail("cannot write preparation receipt")
		return
	receipt.store_string(JSON.stringify({"format": 1, "size": SIZE, "edge_band": BAND, "method": "unchanged final palette verification" if verify else "symmetric opposite-edge blend, horizontal then vertical; final palette reduction follows", "files": prepared}, "\t") + "\n")
	receipt.close()
	print("earth tile preparation: PASS, " + str(prepared.size()) + " opaque tiles with matching opposite edges")
	quit()

static func difference(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0

static func metrics(image: Image) -> Dictionary:
	var edge_total: float = 0.0
	var edge_max: float = 0.0
	var interior: float = 0.0
	for index: int in SIZE:
		var horizontal: float = difference(image.get_pixel(0, index), image.get_pixel(SIZE - 1, index))
		var vertical: float = difference(image.get_pixel(index, 0), image.get_pixel(index, SIZE - 1))
		edge_total += horizontal + vertical
		edge_max = maxf(edge_max, maxf(horizontal, vertical))
	for y: int in SIZE:
		for x: int in range(SIZE - 1):
			interior += difference(image.get_pixel(x, y), image.get_pixel(x + 1, y))
	for x: int in SIZE:
		for y: int in range(SIZE - 1):
			interior += difference(image.get_pixel(x, y), image.get_pixel(x, y + 1))
	return {"edge_mean": edge_total / float(SIZE * 2), "edge_max": edge_max, "interior_mean": interior / float(SIZE * (SIZE - 1) * 2)}

func _fail(message: String) -> void:
	push_error("earth tile preparation: " + message)
	quit(1)
