extends SceneTree

## Original deterministic pixel surfaces, with no external asset request.
const OUTPUT: String = "res://assets/environment/moon"
const SIZE: int = 128

func _initialize() -> void:
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("moon_bake: cannot create output directory")
		quit(1)
		return
	var files: Array[Dictionary] = []
	for kind: String in ["dust", "pressure_shell", "earth", "drawing"]:
		var image: Image = _image(kind)
		var path: String = OUTPUT + "/" + kind + ".png"
		if image.save_png(ProjectSettings.globalize_path(path)) != OK:
			push_error("moon_bake: cannot write " + path)
			quit(1)
			return
		files.append({"file": kind + ".png", "sha256": FileAccess.get_sha256(path)})
	var manifest: Dictionary = {"format": 1, "size": [SIZE, SIZE], "spend_usd": 0,
		"source": "res://../tools/bake_moon_details.gd", "source_sha256": FileAccess.get_sha256("res://../tools/bake_moon_details.gd"),
		"method": "original deterministic pixel placement", "files": files}
	var receipt: FileAccess = FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	if receipt == null:
		push_error("moon_bake: cannot write manifest")
		quit(1)
		return
	receipt.store_string(JSON.stringify(manifest, "  ") + "\n")
	receipt.close()
	print("moon_bake: PASS four original pixel surfaces and source receipt")
	quit()

static func _image(kind: String) -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT if kind == "earth" else Color("d6d0be"))
	var continents: Array[PackedVector2Array] = []
	if kind == "earth":
		continents = _continents()
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var grain: int = posmod(x * 73 + y * 151 + (x * y) * 13, 97)
			var color: Color = Color("b5b4a8")
			match kind:
				"dust":
					color = Color("c1beb0") if grain < 66 else (Color("a3a499") if grain < 93 else Color("777b72"))
					if posmod(x + y / 3, 37) < 2 and posmod(y, 19) < 8:
						color = Color("94988c")
				"pressure_shell":
					color = Color("d1cbbb") if grain < 90 else Color("b0b0a2")
					if x % 64 < 3 or y % 64 < 3:
						color = Color("64716b")
					if (x % 64 in [7, 8, 55, 56]) and (y % 64 in [7, 8, 55, 56]):
						color = Color("555c59")
					if x > 16 and x < 44 and y > 86 and y < 102:
						color = Color("b8b49e")
				"earth":
					color = _earth_pixel(Vector2(float(x - 64), float(y - 62)) / 49.0, continents)
				"drawing":
					var dx: float = float(x - 64) / (49.0 if kind == "earth" else 38.0)
					var dy: float = float(y - 62) / (49.0 if kind == "earth" else 38.0)
					var radius: float = dx * dx + dy * dy
					if radius > 1.0:
						color = Color.TRANSPARENT if kind == "earth" else Color("e5decb")
					else:
						var land: float = sin(dx * 8.0 + dy * 3.0) + cos(dy * 9.0 - dx * 2.0)
						color = Color("7c9b86") if land > 0.35 else Color("537b91")
						if land < -1.15 or absf(dy) > 0.82:
							color = Color("c7d4c6")
						if kind == "earth":
							color = color.darkened(clampf((dx + 0.45) * 0.62 + radius * 0.15, 0.0, 0.88))
			image.set_pixel(x, y, color)
	if kind == "drawing":
		for x: int in range(18, 110):
			image.set_pixel(x, 112 + posmod(x, 3), Color("926e57"))
	return image

static func _continents() -> Array[PackedVector2Array]:
	# Original Atlantic-facing silhouettes, deliberately reduced to pixel scale.
	return [
		PackedVector2Array([Vector2(-0.88, -0.48), Vector2(-0.76, -0.64), Vector2(-0.54, -0.68),
			Vector2(-0.24, -0.57), Vector2(-0.19, -0.34), Vector2(-0.31, -0.24),
			Vector2(-0.28, -0.13), Vector2(-0.41, -0.09), Vector2(-0.50, -0.25),
			Vector2(-0.67, -0.25), Vector2(-0.76, -0.39)]),
		PackedVector2Array([Vector2(-0.42, -0.17), Vector2(-0.30, -0.10), Vector2(-0.29, 0.03),
			Vector2(-0.17, 0.12), Vector2(-0.02, 0.28), Vector2(-0.10, 0.48),
			Vector2(-0.25, 0.78), Vector2(-0.34, 0.61), Vector2(-0.39, 0.28), Vector2(-0.35, 0.08)]),
		PackedVector2Array([Vector2(0.12, -0.24), Vector2(0.43, -0.25), Vector2(0.60, -0.06),
			Vector2(0.49, 0.05), Vector2(0.47, 0.26), Vector2(0.35, 0.46),
			Vector2(0.23, 0.25), Vector2(0.13, 0.02), Vector2(0.10, -0.10)]),
		PackedVector2Array([Vector2(0.15, -0.30), Vector2(0.26, -0.48), Vector2(0.45, -0.54),
			Vector2(0.70, -0.43), Vector2(0.61, -0.24), Vector2(0.45, -0.29),
			Vector2(0.33, -0.38), Vector2(0.26, -0.28)]),
		PackedVector2Array([Vector2(0.46, -0.54), Vector2(0.76, -0.62), Vector2(0.93, -0.44),
			Vector2(0.96, -0.18), Vector2(0.83, -0.06), Vector2(0.70, -0.12),
			Vector2(0.60, -0.03), Vector2(0.54, -0.20), Vector2(0.43, -0.30)]),
		PackedVector2Array([Vector2(-0.22, -0.79), Vector2(-0.06, -0.87), Vector2(0.03, -0.73),
			Vector2(-0.06, -0.58), Vector2(-0.16, -0.63)])
	]

static func _earth_pixel(point: Vector2, continents: Array[PackedVector2Array]) -> Color:
	var radius: float = point.length_squared()
	if radius > 1.0:
		return Color.TRANSPARENT
	var color: Color = Color("477fa4")
	for continent: PackedVector2Array in continents:
		if Geometry2D.is_point_in_polygon(point, continent):
			color = Color("86a77d") if point.y < 0.14 else Color("a4aa78")
			break
	if absf(point.y) > 0.87:
		color = Color("d9e3da")
	# Broken curved cloud belts leave the continental edges readable.
	var cloud: float = absf(point.y + 0.35 - 0.11 * sin(point.x * 6.0))
	var lower_cloud: float = absf(point.y - 0.43 - 0.09 * sin(point.x * 7.0 + 1.2))
	if (cloud < 0.033 and point.x > -0.72 and point.x < 0.28) \
		or (lower_cloud < 0.026 and point.x > -0.83 and point.x < 0.04) \
		or (absf(point.y + 0.65 - 0.07 * cos(point.x * 9.0)) < 0.025 and point.x > -0.25):
		color = Color("dce6e1")
	return color.darkened(clampf((point.x + 0.45) * 0.62 + radius * 0.15, 0.0, 0.88))
