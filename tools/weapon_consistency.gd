extends SceneTree

const CELL: Vector2i = Vector2i(482, 360)
const ENTRIES: Array[Array] = [
	["Fists", "res://assets/weapons/viewmodels/fists_idle.png"],
	["Shiv", "res://assets/weapons/viewmodels/shiv_idle.png"],
	["Pistol", "res://assets/weapons/pistol-sprite-20261005/pistol_idle.png"],
	["Rifle", "res://assets/weapons/viewmodels/rifle_idle.png"],
	["Shotgun", "res://assets/weapons/viewmodels/shotgun_idle.png"],
	["Railgun", "res://assets/weapons/viewmodels/railgun_idle.png"],
	["Sniper", "res://assets/weapons/sniper-sprite-20261005/sniper_idle.png"],
	["Repeater", ""],
	["Arc", "res://assets/weapons/arc/arc_idle.png"],
]

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
	var sheet: Image = _blank(CELL * Vector2i(3, 3))
	var facts: Array[Dictionary] = []
	for index: int in ENTRIES.size():
		var offset: Vector2i = Vector2i((index % 3) * CELL.x, (index / 3) * CELL.y)
		var fact: Dictionary = {"label":ENTRIES[index][0], "cell":[index % 3, index / 3], "runtime_source":ENTRIES[index][1]}
		if ENTRIES[index][1].is_empty():
			fact["status"] = "CPU foundation only, no held or pickup art; live presenter intentionally shows no borrowed gun"
		else:
			var source: Image = Image.load_from_file(ProjectSettings.globalize_path(ENTRIES[index][1]))
			var used: Rect2i = source.get_used_rect()
			fact["source_size"] = [source.get_width(), source.get_height()]
			fact["opaque_bounds"] = [used.position.x, used.position.y, used.size.x, used.size.y]
			_draw(sheet, source, offset)
		facts.append(fact)
	sheet.save_png(output.path_join("whole-held-table.png"))
	var arc: Image = Image.load_from_file(ProjectSettings.globalize_path(ENTRIES[8][1]))
	for index: int in [3, 4, 5]:
		var pair: Image = _blank(CELL * Vector2i(2, 1))
		_draw(pair, Image.load_from_file(ProjectSettings.globalize_path(ENTRIES[index][1])), Vector2i.ZERO)
		_draw(pair, arc, Vector2i(CELL.x, 0))
		pair.save_png(output.path_join("arc-vs-" + str(ENTRIES[index][0]).to_lower() + ".png"))
	var poses: Image = _blank(CELL * Vector2i(4, 1))
	for index: int in 4:
		var pose: String = ["idle", "fire", "settle", "reload"][index]
		_draw(poses, Image.load_from_file(ProjectSettings.globalize_path("res://assets/weapons/arc/arc_" + pose + ".png")), Vector2i(index * CELL.x, 0))
	poses.save_png(output.path_join("arc-four-held-poses.png"))
	var report: FileAccess = FileAccess.open(output.path_join("comparison.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"canvas":[CELL.x,CELL.y], "fit":"actual shared aspect-preserving centered HUD rectangle", "entries":facts, "limit":"Static shared fit comparison. Fists use independent live arms and Shiv uses a live thrust; this sheet does not replace their animation or ordinary-input captures."}, "\t") + "\n")
	print("weapon_consistency: PASS actual shared fit table and Arc reference pairs")
	quit(0)

func _blank(size_value: Vector2i) -> Image:
	var image: Image = Image.create_empty(size_value.x, size_value.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("24282b"))
	return image

func _draw(target: Image, source: Image, offset: Vector2i) -> void:
	var copy: Image = source.duplicate()
	var fit: float = minf(float(CELL.x) / source.get_width(), float(CELL.y) / source.get_height())
	copy.resize(roundi(source.get_width() * fit), roundi(source.get_height() * fit), Image.INTERPOLATE_NEAREST)
	target.blend_rect(copy, Rect2i(Vector2i.ZERO, copy.get_size()), offset + (CELL - copy.get_size()) / 2)
