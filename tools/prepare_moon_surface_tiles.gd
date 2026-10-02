extends SceneTree

## Offline periodic edge repair and palette validation for the lunar tile batch.
const SOURCE: String = "res://art/environment/moon-surfaces-20261001"
const OUTPUT: String = "res://assets/environment/moon/surfaces"
const SIZE: int = 128
const EDGE: int = 8
const FLOOR_KEEPERS: Dictionary[String, String] = {
	"moon_worn_deck": "moon_flat_traction_deck",
	"moon_regolith": "moon_quiet_regolith",
}

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	if not parsed is Dictionary:
		push_error("moon_tiles: missing palette")
		quit(1)
		return
	var colors: Array[Color] = []
	for value: Variant in parsed.values():
		if not value is Array or value.size() != 4:
			quit(1)
			return
		colors.append(Color8(value[0], value[1], value[2], value[3]))
	for folder: String in [OUTPUT, SOURCE + "/processed", SOURCE + "/review"]:
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
			quit(1)
			return
	var entries: Array[Dictionary] = []
	for id: String in ["moon_pressure_bone", "moon_worn_deck", "moon_basalt", "moon_regolith", "moon_union_service", "moon_seal_rubber", "moon_civilian_fabric", "moon_repair_plate"]:
		var selected_id: String = FLOOR_KEEPERS.get(id, id)
		var archive: String = "moon-floor-alternatives-20261001" if FLOOR_KEEPERS.has(id) else "moon-surfaces-20261001"
		var raw_path: String = "res://../.agents/" + archive + "/raw/" + selected_id + "_0.png"
		var reduced_path: String = SOURCE + "/reduced/" + selected_id + "_0.png"
		var raw: Image = Image.load_from_file(ProjectSettings.globalize_path(raw_path))
		var tile: Image = Image.load_from_file(ProjectSettings.globalize_path(reduced_path))
		if raw == null or tile == null or tile.get_size() != Vector2i(SIZE, SIZE):
			push_error("moon_tiles: missing reduced tile " + id)
			quit(1)
			return
		tile.convert(Image.FORMAT_RGBA8)
		# Blend paired opposite strips. The outer samples match exactly; the
		# inner strip remains predominantly original, preserving pixel clusters.
		for y: int in range(SIZE):
			for distance: int in range(EDGE):
				var a: Color = tile.get_pixel(distance, y)
				var b: Color = tile.get_pixel(SIZE - 1 - distance, y)
				var weight: float = 0.5 * pow(1.0 - float(distance) / float(EDGE), 2.0)
				var paired: Color = a.lerp(b, weight)
				tile.set_pixel(distance, y, paired)
				tile.set_pixel(SIZE - 1 - distance, y, paired if distance == 0 else b.lerp(a, weight))
		for x: int in range(SIZE):
			for distance: int in range(EDGE):
				var a: Color = tile.get_pixel(x, distance)
				var b: Color = tile.get_pixel(x, SIZE - 1 - distance)
				var weight: float = 0.5 * pow(1.0 - float(distance) / float(EDGE), 2.0)
				var paired: Color = a.lerp(b, weight)
				tile.set_pixel(x, distance, paired)
				tile.set_pixel(x, SIZE - 1 - distance, paired if distance == 0 else b.lerp(a, weight))
		var used: Dictionary[int, bool] = {}
		for y: int in range(SIZE):
			for x: int in range(SIZE):
				var source: Color = tile.get_pixel(x, y)
				var best: Color = colors[0]
				var minimum: float = INF
				for candidate: Color in colors:
					var delta: Vector3 = Vector3(source.r - candidate.r, source.g - candidate.g, source.b - candidate.b)
					if delta.length_squared() < minimum:
						minimum = delta.length_squared()
						best = candidate
				tile.set_pixel(x, y, best)
				used[best.to_rgba32()] = true
		for index: int in range(SIZE):
			if tile.get_pixel(0, index) != tile.get_pixel(SIZE - 1, index) or tile.get_pixel(index, 0) != tile.get_pixel(index, SIZE - 1):
				push_error("moon_tiles: edge mismatch " + id)
				quit(1)
				return
		var processed_path: String = SOURCE + "/processed/" + id + ".png"
		var runtime_path: String = OUTPUT + "/" + id + ".png"
		if tile.save_png(ProjectSettings.globalize_path(processed_path)) != OK or tile.save_png(ProjectSettings.globalize_path(runtime_path)) != OK:
			quit(1)
			return
		var preview: Image = Image.create(SIZE * 3, SIZE * 3, false, Image.FORMAT_RGBA8)
		for row: int in range(3):
			for column: int in range(3):
				preview.blit_rect(tile, Rect2i(0, 0, SIZE, SIZE), Vector2i(column * SIZE, row * SIZE))
		preview.save_png(ProjectSettings.globalize_path(SOURCE + "/review/" + id + "_tiled.png"))
		entries.append({"id": id, "selected_id": selected_id, "raw_size": [raw.get_width(), raw.get_height()], "raw_sha256": FileAccess.get_sha256(raw_path), "reduced_sha256": FileAccess.get_sha256(reduced_path), "runtime_sha256": FileAccess.get_sha256(runtime_path), "palette_colors": used.size(), "opposite_edge_mismatches": 0})
	var manifest: Dictionary = {"format": 1, "size": [SIZE, SIZE], "opaque": true, "filter": "nearest", "mipmaps": false, "method": "Rust area reduction and Lab palette mapping, paired 8-pixel periodic edge repair, exact palette remap; explicit approved floor keeper aliases", "source": "tools/prepare_moon_surface_tiles.gd", "source_sha256": FileAccess.get_sha256("res://../tools/prepare_moon_surface_tiles.gd"), "palette_sha256": FileAccess.get_sha256("res://../docs/palette.json"), "files": entries}
	var file: FileAccess = FileAccess.open(SOURCE + "/tile-preparation.json", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	print("moon_tiles: PASS eight opaque palette tiles, matching opposite edges")
	quit()
