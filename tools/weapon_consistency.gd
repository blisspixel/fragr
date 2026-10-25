extends SceneTree

## The whole held set side by side at its true display size: every rest
## frame in `WeaponArt.IDLE` at two reference pixels a texel, bottom centred in
## a cell the size of the largest held canvas, the way the HUD places it. Use
## it to judge scale, glove family and composition across guns.
##
##   godot --headless --path client --script res://../tools/weapon_consistency.gd -- --out=<dir>

const TEXEL: int = 2
const COLUMNS: int = 4

func _initialize() -> void:
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty():
		push_error("weapon_consistency: --out=<absolute-directory> required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var names: Array[String] = []
	var cell: Vector2i = Vector2i.ZERO
	for weapon: String in WeaponArt.IDLE:
		if weapon == "ArticleBlade":
			continue
		names.append(weapon)
		cell = cell.max(Vector2i(WeaponArt.IDLE[weapon].get_size()) * TEXEL)
	var rows: int = ceili(float(names.size()) / COLUMNS)
	var sheet: Image = Image.create_empty(cell.x * COLUMNS, cell.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("24282b"))
	var facts: Array[Dictionary] = []
	for index: int in names.size():
		var source: Image = WeaponArt.IDLE[names[index]].get_image()
		source.convert(Image.FORMAT_RGBA8)
		var used: Rect2i = source.get_used_rect()
		var shown: Image = source.duplicate()
		shown.resize(source.get_width() * TEXEL, source.get_height() * TEXEL, Image.INTERPOLATE_NEAREST)
		var origin: Vector2i = Vector2i((index % COLUMNS) * cell.x, (index / COLUMNS) * cell.y)
		sheet.blend_rect(shown, Rect2i(Vector2i.ZERO, shown.get_size()), origin + Vector2i((cell.x - shown.get_width()) / 2, cell.y - shown.get_height()))
		facts.append({"weapon": names[index], "canvas": [source.get_width(), source.get_height()],
			"opaque_bounds": [used.position.x, used.position.y, used.size.x, used.size.y],
			"modelled": WeaponArt.BAKED.has(names[index])})
	sheet.save_png(output.path_join("whole-held-table.png"))
	var report: FileAccess = FileAccess.open(output.path_join("comparison.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"texel_pixels": TEXEL, "cell": [cell.x, cell.y], "entries": facts,
		"limit": "Rest frames only, at display size. Motion, the shot and the reload need the live captures."}, "\t") + "\n")
	print("weapon_consistency: PASS %d held rest frames at display size" % names.size())
	quit(0)
