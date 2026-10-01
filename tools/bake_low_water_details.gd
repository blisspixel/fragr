extends SceneTree
## Offline original material overlays. Run from the repository root:
## godot --headless --path client --script ../tools/bake_low_water_details.gd

const OUTPUT: String = "res://assets/environment/low_water"
const SIZE: int = 128
var palette: Dictionary[String, Color] = {}

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	if not parsed is Dictionary:
		_fail("palette is not an object")
		return
	for key: String in ["bone", "gunmetal", "gunmetal_light", "cyan_muted", "rust", "institutional_green"]:
		var channels: Variant = parsed.get(key)
		if not channels is Array or channels.size() != 4:
			_fail("palette entry is missing: " + key)
			return
		palette[key] = Color8(int(channels[0]), int(channels[1]), int(channels[2]), 255)
	var plaster: Image = _plaster()
	var steel: Image = _steel()
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("cannot create asset directory")
		return
	for item: Array in [["plaster_repairs.png", plaster], ["steel_repairs.png", steel]]:
		if (item[1] as Image).save_png(directory.path_join(item[0])) != OK:
			_fail("cannot write " + str(item[0]))
			return
	var manifest: Dictionary = {
		"format": 1, "recipe": "tools/bake_low_water_details.gd", "palette": "docs/palette.json",
		"method": "original deterministic pixel placement", "spend_usd": 0,
		"size": [SIZE, SIZE], "texels_per_metre": 16, "uncompressed_bytes": SIZE * SIZE * 4 * 2,
		"files": [
			{"path": "plaster_repairs.png", "sha256": FileAccess.get_sha256(directory.path_join("plaster_repairs.png")), "subject": "broad civilian plaster repairs and low waterline wear"},
			{"path": "steel_repairs.png", "sha256": FileAccess.get_sha256(directory.path_join("steel_repairs.png")), "subject": "sparse replacement enamel, metal fasteners and removed plate scars"}
		], "integration": "optional lit Low Water vertical surface detail; no collision or emission"
	}
	var receipt: FileAccess = FileAccess.open(OUTPUT + "/manifest.json", FileAccess.WRITE)
	if receipt == null:
		_fail("cannot write manifest")
		return
	receipt.store_string(JSON.stringify(manifest, "\t") + "\n")
	receipt.close()
	var preview: Image = Image.create_empty(SIZE * 2, SIZE, false, Image.FORMAT_RGBA8)
	preview.fill(Color("b7a58d"))
	preview.blend_rect(plaster, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	preview.blend_rect(steel, Rect2i(0, 0, SIZE, SIZE), Vector2i(SIZE, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../.agents/environment"))
	preview.save_png(ProjectSettings.globalize_path("res://../.agents/environment/low_water_native.png"))
	preview.resize(SIZE * 8, SIZE * 4, Image.INTERPOLATE_NEAREST)
	preview.save_png(ProjectSettings.globalize_path("res://../.agents/environment/low_water_zoom.png"))
	print("low_water detail bake: PASS, two original 128px palette overlays and reproducible manifest")
	quit()

func _color(key: String, alpha: float) -> Color:
	var value: Color = palette[key]
	value.a = alpha
	return value

func _rect(image: Image, bounds: Rect2i, color: Color) -> void:
	image.fill_rect(bounds, color)

func _plaster() -> Image:
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# A grounded horizontal waterline, deliberately sparse and not mildew or flora.
	for x: int in SIZE:
		var crest: int = 5 + (floori(float(x) / 11.0) % 3)
		for y: int in range(crest):
			image.set_pixel(x, y, _color("gunmetal", 0.19 if y < 3 else 0.10))
		if x % 19 < 3:
			_rect(image, Rect2i(x, crest, 1, 2), _color("gunmetal_light", 0.12))
	# Unequal hand-applied repair fields, chipped with broad stepped edges.
	_rect(image, Rect2i(19, 23, 26, 20), _color("bone", 0.32))
	_rect(image, Rect2i(22, 21, 19, 24), _color("bone", 0.32))
	_rect(image, Rect2i(71, 54, 31, 16), _color("bone", 0.23))
	_rect(image, Rect2i(74, 52, 23, 20), _color("bone", 0.23))
	_rect(image, Rect2i(21, 23, 2, 12), _color("gunmetal_light", 0.16))
	_rect(image, Rect2i(90, 68, 8, 2), _color("gunmetal_light", 0.15))
	# Small mortar scars, well below the repair fields in occupied area.
	for scar: Rect2i in [Rect2i(54, 18, 5, 2), Rect2i(106, 40, 4, 2), Rect2i(36, 82, 7, 2)]:
		_rect(image, scar, _color("gunmetal", 0.16))
	return image

func _steel() -> Image:
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# Local repairs imply utility work, never another uniform emblem or vent grid.
	_rect(image, Rect2i(22, 24, 25, 18), _color("institutional_green", 0.28))
	_rect(image, Rect2i(24, 26, 21, 14), _color("gunmetal_light", 0.13))
	_rect(image, Rect2i(78, 63, 22, 14), _color("cyan_muted", 0.16))
	_rect(image, Rect2i(81, 65, 16, 10), _color("gunmetal_light", 0.20))
	for point: Vector2i in [Vector2i(24, 26), Vector2i(43, 26), Vector2i(24, 38), Vector2i(43, 38), Vector2i(80, 65), Vector2i(96, 73)]:
		_rect(image, Rect2i(point, Vector2i(2, 2)), _color("gunmetal", 0.35))
	_rect(image, Rect2i(56, 20, 10, 4), _color("gunmetal_light", 0.24))
	_rect(image, Rect2i(58, 21, 6, 2), _color("bone", 0.18))
	_rect(image, Rect2i(22, 42, 9, 2), _color("rust", 0.12))
	return image

func _fail(message: String) -> void:
	push_error("low_water detail bake: " + message)
	quit(1)
