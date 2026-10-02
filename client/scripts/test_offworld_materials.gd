extends SceneTree

const Library = preload("res://scripts/offworld_materials.gd")
var failed: bool = false

func _initialize() -> void:
	_check(Library.describe("unknown").is_empty(), "unknown ID must not imply a venue")
	_check(Library.make("unknown") == null, "unknown ID must not manufacture a material")
	var colors: Dictionary[String, bool] = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	_check(parsed is Dictionary, "palette document must load")
	if not parsed is Dictionary:
		quit(1)
		return
	for name: Variant in parsed:
		var channels: Variant = parsed[name]
		_check(channels is Array and channels.size() == 4, "palette channels must validate")
		if channels is Array and channels.size() == 4:
			colors[Color8(int(channels[0]), int(channels[1]), int(channels[2]), int(channels[3])).to_html()] = true
	for id: String in Library.IDS:
		var descriptor: Dictionary = Library.describe(id)
		_check(str(descriptor.get("venue", "")).begins_with("future "), "library must not claim a playable mission")
		var first: StandardMaterial3D = Library.make(id)
		var second: StandardMaterial3D = Library.make(id)
		_check(first != null and second != null, "keeper material must load: " + id)
		if first == null or second == null:
			continue
		_check(first != second and first.albedo_texture == second.albedo_texture, "independent materials must share one cached tile")
		first.albedo_color = Color.BLACK
		_check(second.albedo_color == Color.WHITE, "preview tint must not mutate other material instances")
		_check(second.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and second.texture_repeat, "pixel sampling must remain nearest and repeated")
		_check(not second.emission_enabled and second.roughness == 1.0, "material must retain real lighting without baked emission")
		var image: Image = second.albedo_texture.get_image()
		_check(image != null and image.get_size() == Vector2i(Library.SIZE, Library.SIZE), "tile must have bounded native dimensions")
		if image == null:
			continue
		image.convert(Image.FORMAT_RGBA8)
		_check(not image.has_mipmaps(), "keeper must not have mipmaps")
		for y: int in range(Library.SIZE):
			for x: int in range(Library.SIZE):
				var color: Color = image.get_pixel(x, y)
				_check(color.a == 1.0 and colors.has(color.to_html()), "every keeper pixel must be opaque and on the shared palette")
		for coordinate: int in range(Library.SIZE):
			_check(image.get_pixel(0, coordinate) == image.get_pixel(Library.SIZE - 1, coordinate), "horizontal repeat boundary must match")
			_check(image.get_pixel(coordinate, 0) == image.get_pixel(coordinate, Library.SIZE - 1), "vertical repeat boundary must match")
	if not failed:
		print("test_offworld_materials: PASS five loaded palette tiles, boundaries, cache and lit material contracts")
	quit(1 if failed else 0)

func _check(ok: bool, message: String) -> void:
	if not ok and not failed:
		push_error("offworld_materials: " + message)
		failed = true
