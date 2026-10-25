extends SceneTree

## Prepare bounded native-reduced candidates as opaque, periodic palette tiles.
const SIZE: int = 128
const EDGE: int = 8

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 5 and args[4].begins_with("recipe="):
		_recipe(args, args[4].trim_prefix("recipe="))
		return
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

## Class recipe mode (`recipe=<res path>`): one tile per surface class at the
## recipe's size, each from one native-reduced seed. The seed is made periodic
## by blending it with its own half-period roll toward the edges, one axis at
## a time, then locked to its class ramp of palette keys by luminance rank:
## each step takes its recipe share, darkest first, so every class keeps broad
## clusters at a known value whatever the generator's exposure. The most
## saturated warm pixels become the class's accent keys (rust bleed, dust),
## and isolated pixels fold into their neighbours, so the tile reads as
## clusters rather than speckle.
func _recipe(args: PackedStringArray, recipe_path: String) -> void:
	var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	if not recipe is Dictionary or not (recipe as Dictionary).get("classes") is Array:
		_fail("unreadable recipe " + recipe_path)
		return
	var size: int = int(recipe.get("size", 0))
	if size not in [32, 64, 128]:
		_fail("recipe size must be 32, 64 or 128")
		return
	var palette: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	if not palette is Dictionary:
		_fail("unreadable palette")
		return
	# Every seed run shares one model, style and negative; each frame keeps
	# its own subject, recorded beside the tile it became.
	var spec: Dictionary = {}
	var subjects: Dictionary[String, String] = {}
	var spec_hashes: Dictionary[String, String] = {}
	for path: Variant in recipe.get("specs", []):
		var spec_path: String = "res://../" + str(path)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
		if not parsed is Dictionary or not (parsed as Dictionary).get("frames") is Array:
			_fail("unreadable seed spec " + spec_path)
			return
		if not spec.is_empty() and (parsed["model"] != spec["model"] or parsed["style"] != spec["style"] or parsed["negative"] != spec["negative"]):
			_fail("seed specs disagree on model, style or negative")
			return
		spec = parsed
		spec_hashes[str(path)] = FileAccess.get_sha256(spec_path)
		for frame: Variant in parsed["frames"]:
			subjects[str(frame["id"])] = str(frame["subject"])
	if spec.is_empty():
		_fail("the recipe names no seed spec")
		return
	for folder: String in [args[2], args[3]]:
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			_fail("cannot create destination")
			return
	var entries: Array[Dictionary] = []
	for entry: Variant in recipe["classes"]:
		var id: String = str(entry.get("id", ""))
		var source: String = str(entry.get("source", ""))
		var reduced_path: String = args[1].path_join(source + "_0.png")
		var raw_path: String = args[0].path_join(source + "_0.png")
		var reduced: Image = Image.load_from_file(reduced_path)
		if id.is_empty() or reduced == null or reduced.get_size() != Vector2i(size * 2, size * 2) or not FileAccess.file_exists(raw_path) or not subjects.has(source):
			_fail("invalid class %s from %s (seeds are native-reduced to twice the tile)" % [id, source])
			return
		reduced.convert(Image.FORMAT_RGBA8)
		# Whole seed: an exact two-by-two area average. Crop: the seed's central
		# half at one to one, for a pattern (tread lugs) that must stay a few
		# pixels across rather than alias into grain.
		var seed: Image = reduced.get_region(Rect2i(size / 2, size / 2, size, size)) if bool(entry.get("crop", false)) else _halve(reduced)
		for pass_index: int in range(int(entry.get("soften", 0))):
			seed = _soften(seed)
		var ramp: Array[Color] = _steps(entry.get("ramp", []), palette)
		var accents: Array[Color] = _steps(entry.get("accents", []), palette)
		var shares: Array = entry.get("shares", [])
		var total: float = 0.0
		for share: Variant in shares:
			total += float(share)
		if ramp.is_empty() or ramp.size() != shares.size() or absf(total - 1.0) > 0.001 or ramp.has(Color(0, 0, 0, 0)) or accents.has(Color(0, 0, 0, 0)):
			_fail("class %s needs palette steps with shares summing to one" % id)
			return
		# A class drawn in deck bands (kerbs) never repeats vertically, so it
		# keeps its seed's top-to-bottom order: tyre rub stays at the base.
		var tile: Image = _periodic(seed, true)
		if bool(entry.get("periodic_y", true)):
			tile = _periodic(tile, false)
		var locked: Image = _lock(tile, ramp, shares, accents, float(entry.get("accent_share", 0.0)))
		for pass_index: int in range(int(recipe.get("despeckle_passes", 1))):
			locked = _despeckle(locked)
		var allowed: Dictionary = {}
		for color: Color in ramp + accents:
			allowed[color.to_rgba32()] = true
		var used: Dictionary = {}
		for y: int in range(size):
			for x: int in range(size):
				var pixel: Color = locked.get_pixel(x, y)
				if not allowed.has(pixel.to_rgba32()):
					_fail("class %s left an unlisted colour" % id)
					return
				used[pixel.to_rgba32()] = true
		var seam: float = _seam_ratio(locked, bool(entry.get("periodic_y", true)))
		if seam > 2.0:
			_fail("class %s wraps with a visible seam (ratio %.2f)" % [id, seam])
			return
		var runtime_path: String = args[2].path_join(id + ".png")
		if locked.save_png(runtime_path) != OK:
			_fail("cannot write runtime tile")
			return
		var repeated: Image = Image.create(size * 3, size * 3, false, Image.FORMAT_RGBA8)
		for row: int in range(3):
			for column: int in range(3):
				repeated.blit_rect(locked, Rect2i(0, 0, size, size), Vector2i(column * size, row * size))
		repeated.resize(size * 12, size * 12, Image.INTERPOLATE_NEAREST)
		repeated.save_png(args[3].path_join(id + "-repeat.png"))
		entries.append({"id": id, "source": source, "use": str(entry.get("use", "")), "subject": subjects[source],
			"raw_sha256": FileAccess.get_sha256(raw_path), "reduced_sha256": FileAccess.get_sha256(reduced_path),
			"runtime_sha256": FileAccess.get_sha256(runtime_path), "palette_colors": used.size(), "seam_ratio": snappedf(seam, 0.01)})
	var file: FileAccess = FileAccess.open(args[2].path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 1, "size": [size, size], "texels_per_metre": int(recipe.get("texels_per_metre", 16)),
		"repeat_metres": float(size) / float(recipe.get("texels_per_metre", 16)), "filter": "nearest", "mipmaps": false,
		"color_model": "class ramps of docs/palette.json keys and two-key blends (lore-gate P10 extension, pending)",
		"specs": spec_hashes, "model": str(spec.get("model", "")), "params": spec.get("params", {}),
		"style": str(spec.get("style", "")), "view": str(spec.get("view", "")), "technical": str(spec.get("technical", "")),
		"negative": str(spec.get("negative", "")), "recipe": recipe_path.trim_prefix("res://../"),
		"recipe_sha256": FileAccess.get_sha256(recipe_path), "palette_sha256": FileAccess.get_sha256("res://../docs/palette.json"),
		"preparation_sha256": FileAccess.get_sha256("res://../tools/prepare_surface_tiles.gd"), "entries": entries}, "\t") + "\n")
	file.close()
	print("surface_tiles: PASS %d class tiles at %d px locked to palette ramps" % [entries.size(), size])
	quit(0)

## Palette steps: a key, or [a, b, t] for a blend of two keys. A missing key
## yields a transparent step, which the caller refuses.
func _steps(list: Variant, palette: Dictionary) -> Array[Color]:
	var steps: Array[Color] = []
	if not list is Array:
		return steps
	for step: Variant in list:
		if not step is Array or step.is_empty() or not palette.has(str(step[0])):
			steps.append(Color(0, 0, 0, 0))
			continue
		var a: Array = palette[str(step[0])]
		var color: Color = Color8(int(a[0]), int(a[1]), int(a[2]))
		if step.size() == 3:
			if not palette.has(str(step[1])):
				steps.append(Color(0, 0, 0, 0))
				continue
			var b: Array = palette[str(step[1])]
			color = color.lerp(Color8(int(b[0]), int(b[1]), int(b[2])), float(step[2]))
		# Stored as 8-bit, so the lock and the check agree on the exact value.
		steps.append(Color8(color.r8, color.g8, color.b8))
	return steps

## Periodic along one axis: near the two edges the tile shows its own centre,
## rolled half a period, which is continuous across the wrap; the centre keeps
## the seed, which hides the roll's own seam.
func _periodic(image: Image, along_x: bool) -> Image:
	var size: int = image.get_width()
	var out: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var t: int = x if along_x else y
			var edge: float = minf(float(t) + 0.5, float(size) - float(t) - 0.5) / (float(size) * 0.5)
			var keep: float = smoothstep(0.15, 0.55, edge)
			var rolled: Color = image.get_pixel((x + size / 2) % size, y) if along_x else image.get_pixel(x, (y + size / 2) % size)
			out.set_pixel(x, y, rolled.lerp(image.get_pixel(x, y), keep))
	return out

func _halve(image: Image) -> Image:
	var size: int = image.get_width() / 2
	var out: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var sum: Color = image.get_pixel(x * 2, y * 2) + image.get_pixel(x * 2 + 1, y * 2) + image.get_pixel(x * 2, y * 2 + 1) + image.get_pixel(x * 2 + 1, y * 2 + 1)
			out.set_pixel(x, y, sum / 4.0)
	return out

## A wrapping three-by-three box blur, so the lock finds broad shapes rather
## than the seed's grain.
func _soften(image: Image) -> Image:
	var size: int = image.get_width()
	var out: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var sum: Color = Color(0, 0, 0, 0)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					sum += image.get_pixel(posmod(x + dx, size), posmod(y + dy, size))
			out.set_pixel(x, y, sum / 9.0)
	return out

func _luma(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b

func _lock(tile: Image, ramp: Array[Color], shares: Array, accents: Array[Color], accent_share: float) -> Image:
	var size: int = tile.get_width()
	var count: int = size * size
	var out: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var taken: Dictionary = {}
	if not accents.is_empty() and accent_share > 0.0:
		# Warm stains: hue up to about 50 degrees, ranked by saturation.
		var warm: Array = []
		for y: int in range(size):
			for x: int in range(size):
				var c: Color = tile.get_pixel(x, y)
				if c.s > 0.12 and (c.h < 0.14 or c.h > 0.97) and c.v > 0.12:
					warm.append([c.s, x, y])
		warm.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for index: int in range(mini(warm.size(), int(round(accent_share * float(count))))):
			var x: int = warm[index][1]
			var y: int = warm[index][2]
			var luma: float = _luma(tile.get_pixel(x, y))
			var best: Color = accents[0]
			for accent: Color in accents:
				if absf(_luma(accent) - luma) < absf(_luma(best) - luma):
					best = accent
			out.set_pixel(x, y, best)
			taken[Vector2i(x, y)] = true
	var order: Array = []
	for y: int in range(size):
		for x: int in range(size):
			if not taken.has(Vector2i(x, y)):
				order.append([_luma(tile.get_pixel(x, y)), x, y])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var step: int = 0
	var bound: float = float(shares[0]) * float(order.size())
	for rank: int in range(order.size()):
		while step < ramp.size() - 1 and float(rank) >= bound:
			step += 1
			bound += float(shares[step]) * float(order.size())
		out.set_pixel(order[rank][1], order[rank][2], ramp[step])
	return out

## A pixel none of whose four neighbours (wrapping) shares its colour takes
## the colour most of them share.
func _despeckle(image: Image) -> Image:
	var size: int = image.get_width()
	var out: Image = image.duplicate() as Image
	for y: int in range(size):
		for x: int in range(size):
			var own: Color = image.get_pixel(x, y)
			var votes: Dictionary = {}
			var alone: bool = true
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var other: Color = image.get_pixel(posmod(x + offset.x, size), posmod(y + offset.y, size))
				if other == own:
					alone = false
				votes[other.to_rgba32()] = int(votes.get(other.to_rgba32(), 0)) + 1
			if alone:
				var best: int = -1
				var pick: int = 0
				for key: int in votes:
					if int(votes[key]) > best:
						best = int(votes[key])
						pick = key
				out.set_pixel(x, y, Color.hex(pick))
	return out

## Mean colour step across the wrap, against the mean step between interior
## neighbours. Near one means the repeat has no seam a player can find.
func _seam_ratio(image: Image, vertical: bool) -> float:
	var size: int = image.get_width()
	var wrap: float = 0.0
	var inner: float = 0.0
	var axes: float = 2.0 if vertical else 1.0
	for index: int in range(size):
		wrap += _step(image.get_pixel(size - 1, index), image.get_pixel(0, index))
		if vertical:
			wrap += _step(image.get_pixel(index, size - 1), image.get_pixel(index, 0))
		for t: int in range(size - 1):
			inner += _step(image.get_pixel(t, index), image.get_pixel(t + 1, index))
			if vertical:
				inner += _step(image.get_pixel(index, t), image.get_pixel(index, t + 1))
	return (wrap / (float(size) * axes)) / maxf(inner / (float(size * (size - 1)) * axes), 0.0001)

func _step(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
