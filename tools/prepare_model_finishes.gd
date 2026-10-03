extends SceneTree

## Extract quiet physical finish detail from reviewed material references.
const OUTPUT: String = "res://assets/models/finishes"

func _initialize() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) != OK:
		quit(1)
		return
	var sources: Dictionary[String, String] = {
		"wood": "res://art/production-20261003/weapon_material_shotgun.png",
		"metal": "res://art/production-20261003/archive_steel.png",
		"enamel": "res://art/production-20261003/archive_enamel.png",
	}
	var manifest: Dictionary[String, Dictionary] = {}
	for kind: String in sources:
		var input: Image = Image.load_from_file(ProjectSettings.globalize_path(sources[kind]))
		if input == null:
			push_error("model_finishes: missing reviewed source " + kind)
			quit(1)
			return
		if kind == "wood":
			# Only the atlas's top walnut strip, excluding neighboring metal.
			input = input.get_region(Rect2i(32, 8, 704, 65))
		input.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		input.convert(Image.FORMAT_RGB8)
		var low: float = 1.0
		var high: float = 0.0
		for y: int in range(256):
			for x: int in range(256):
				var value: float = input.get_pixel(x, y).get_luminance()
				low = minf(low, value)
				high = maxf(high, value)
		for y: int in range(256):
			for x: int in range(256):
				var value: float = input.get_pixel(x, y).get_luminance()
				var shade: float = snappedf(lerpf(0.6 if kind == "enamel" else 0.72, 1.0,
					clampf((value - low) / maxf(0.001, high - low), 0.0, 1.0)), 1.0 / 32.0)
				input.set_pixel(x, y, Color(shade, shade, shade))
		var path: String = OUTPUT.path_join(kind + ".png")
		if input.save_png(path) != OK:
			quit(1)
			return
		manifest[kind] = {"source": sources[kind], "source_sha256": FileAccess.get_sha256(sources[kind]),
			"file": kind + ".png", "sha256": FileAccess.get_sha256(path)}
	var file: FileAccess = FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify({"schema": 1, "pixels": [256, 256], "purpose": "grayscale finish variation, authored tints remain authoritative", "finishes": manifest}, "\t") + "\n")
	file.close()
	print("model_finishes: PASS reviewed wood, metal and enamel detail")
	quit()
