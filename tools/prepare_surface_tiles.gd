extends SceneTree

## Prepare bounded native-reduced candidates as opaque, periodic palette tiles.
const SIZE: int = 128
const EDGE: int = 8

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() not in [4, 5] or (args.size() == 5 and args[4] != "material-ramps"):
		_fail("require raw directory, reduced directory, runtime directory and review directory")
		return
	var material_ramps: bool = args.size() == 5
	var names: PackedStringArray = DirAccess.get_files_at(args[1])
	var inputs: Array[String] = []
	for name: String in names:
		if name.ends_with("_0.png"):
			inputs.append(name)
	inputs.sort()
	if inputs.is_empty() or inputs.size() > 16:
		_fail("require one to sixteen reduced candidates")
		return
	var colors: Array[Color] = []
	var palette: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	for value: Array in palette.values():
		colors.append(Color8(value[0], value[1], value[2], value[3]))
	for folder: String in [args[2], args[3]]:
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			_fail("cannot create destination")
			return
	var entries: Array[Dictionary] = []
	for name: String in inputs:
		var reduced_path: String = args[1].path_join(name)
		var raw_path: String = args[0].path_join(name)
		var tile: Image = Image.load_from_file(reduced_path)
		if tile == null or tile.get_size() != Vector2i(SIZE, SIZE) or not FileAccess.file_exists(raw_path):
			_fail("invalid source pair: " + name)
			return
		tile.convert(Image.FORMAT_RGBA8)
		for y: int in range(SIZE):
			for distance: int in range(EDGE):
				var a: Color = tile.get_pixel(distance, y)
				var b: Color = tile.get_pixel(SIZE - 1 - distance, y)
				var weight: float = 0.5 * pow(1.0 - float(distance) / EDGE, 2.0)
				tile.set_pixel(distance, y, a.lerp(b, weight))
				tile.set_pixel(SIZE - 1 - distance, y, a.lerp(b, weight) if distance == 0 else b.lerp(a, weight))
		for x: int in range(SIZE):
			for distance: int in range(EDGE):
				var a: Color = tile.get_pixel(x, distance)
				var b: Color = tile.get_pixel(x, SIZE - 1 - distance)
				var weight: float = 0.5 * pow(1.0 - float(distance) / EDGE, 2.0)
				tile.set_pixel(x, distance, a.lerp(b, weight))
				tile.set_pixel(x, SIZE - 1 - distance, a.lerp(b, weight) if distance == 0 else b.lerp(a, weight))
		var used: Dictionary = {}
		for y: int in range(SIZE):
			for x: int in range(SIZE):
				var original: Color = tile.get_pixel(x, y)
				var best: Color = colors[0]
				var minimum: float = INF
				if material_ramps:
					best = Color(roundf(original.r * 24.0) / 24.0, roundf(original.g * 24.0) / 24.0, roundf(original.b * 24.0) / 24.0, 1.0)
				else:
					for candidate: Color in colors:
						var difference: Vector3 = Vector3(original.r - candidate.r, original.g - candidate.g, original.b - candidate.b)
						if difference.length_squared() < minimum:
							minimum = difference.length_squared()
							best = candidate
				tile.set_pixel(x, y, best)
				used[best.to_rgba32()] = true
		for index: int in range(SIZE):
			if tile.get_pixel(0, index) != tile.get_pixel(SIZE - 1, index) or tile.get_pixel(index, 0) != tile.get_pixel(index, SIZE - 1):
				_fail("periodic edge mismatch")
				return
		var id: String = name.trim_suffix("_0.png")
		var runtime_path: String = args[2].path_join(id + ".png")
		if tile.save_png(runtime_path) != OK:
			_fail("cannot write runtime tile")
			return
		var repeated: Image = Image.create(SIZE * 3, SIZE * 3, false, Image.FORMAT_RGBA8)
		for row: int in range(3):
			for column: int in range(3):
				repeated.blit_rect(tile, Rect2i(0, 0, SIZE, SIZE), Vector2i(column * SIZE, row * SIZE))
		repeated.resize(768, 768, Image.INTERPOLATE_NEAREST)
		repeated.save_png(args[3].path_join(id + "-repeat.png"))
		entries.append({"id": id, "raw_sha256": FileAccess.get_sha256(raw_path), "reduced_sha256": FileAccess.get_sha256(reduced_path), "runtime_sha256": FileAccess.get_sha256(runtime_path), "palette_colors": used.size(), "edge_mismatches": 0})
	var file: FileAccess = FileAccess.open(args[2].path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 1, "size": [SIZE, SIZE], "filter": "nearest", "mipmaps": false, "color_model": "24-step venue material ramps" if material_ramps else "exact project palette", "palette_sha256": FileAccess.get_sha256("res://../docs/palette.json"), "preparation_sha256": FileAccess.get_sha256("res://../tools/prepare_surface_tiles.gd"), "entries": entries}, "\t") + "\n")
	file.close()
	print("surface_tiles: PASS %d opaque periodic palette tiles" % entries.size())
	quit(0)

func _fail(message: String) -> void:
	push_error("surface_tiles: " + message)
	quit(1)
