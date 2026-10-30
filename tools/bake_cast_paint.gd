extends SceneTree

## Offline personal paint for campaign people (CastPaint). Paints each
## person's own source art once and records what it came from.
## Run: godot --headless --path client --script res://../tools/bake_cast_paint.gd

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var folder: String = ProjectSettings.globalize_path(CastPaint.BAKED)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("bake_cast_paint: cannot create " + folder)
		quit(1)
		return
	var entries: Array[Dictionary] = []
	var people: Array = CastPaint.SCHEMES.keys()
	people.sort()
	for person: String in people:
		var source: String = CastPaint.source_for(person)
		var scene: PackedScene = load(source) as PackedScene if ResourceLoader.exists(source, "PackedScene") else null
		if scene == null:
			push_error("bake_cast_paint: no source for " + person)
			quit(1)
			return
		var body: Node = scene.instantiate()
		var image: Image = CastPaint.painted(CastPaint.source_texture(body), person)
		body.free()
		if image == null:
			push_error("bake_cast_paint: unreadable source art for " + person)
			quit(1)
			return
		var file: String = person + ".png"
		if image.save_png(folder.path_join(file)) != OK:
			push_error("bake_cast_paint: cannot write " + file)
			quit(1)
			return
		var rules: Array = []
		for rule: Dictionary in CastPaint.SCHEMES[person]:
			var row: Dictionary = rule.duplicate()
			row["to"] = "#" + (rule["to"] as Color).to_html(false)
			rules.append(row)
		entries.append({"person": person, "file": file, "source": source,
			"source_sha256": FileAccess.get_sha256(source), "rules": rules,
			"sha256": FileAccess.get_sha256(CastPaint.BAKED + file)})
	var manifest: Dictionary = {"schema": 1, "format": "RGBA8 PNG, nearest sampling, no mipmaps",
		"method": "Offline recolour of each person's own source atlas by CastPaint rules; no generated or external art.",
		"painter_sha256": FileAccess.get_sha256("res://scripts/cast_paint.gd"), "entries": entries}
	var out: FileAccess = FileAccess.open(CastPaint.BAKED + "manifest.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(manifest, "\t", true) + "\n")
	out.close()
	print("bake_cast_paint: PASS (%d people)" % entries.size())
	quit(0)
