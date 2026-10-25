extends SceneTree

## Audit of readable world text per campaign level: every visible Label3D a
## level's MapInfo builds through ArenaCover and the mission presenters, the
## way game_manager.gd builds them. Levels come from the server's own MapInfo
## (server/src/tests/map_info_writer.rs), one file per level.
##
## Count (headless is fine):
##   "$GODOT_BIN" --headless --path client --script ../tools/audit_world_signs.gd -- count /abs/mapinfo_dir [/abs/out.json]
## Contact sheet per level, one tile per sign seen from in front of it (needs a
## real renderer: --audio-driver Dummy --windowed --resolution 1280x720):
##   "$GODOT_BIN" ... --script ../tools/audit_world_signs.gd -- sheet /abs/mapinfo_dir /abs/out [name_prefix]
## Views from a JSON list {"name": {"map_info": "file.json", "eye": [..], "look": [..]}}:
##   "$GODOT_BIN" ... --script ../tools/audit_world_signs.gd -- views /abs/mapinfo_dir /abs/views.json /abs/out
const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const TILE: Vector2i = Vector2i(400, 240)
const COLUMNS: int = 5

var _shots: int = 0
var _failed: bool = false

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	call_deferred("_run")

func _fail(message: String) -> void:
	_failed = true
	push_error("audit_world_signs: " + message)
	quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() in [2, 3] and args[0] == "count":
		await _count(args[1], args[2] if args.size() == 3 else "")
	elif args.size() in [3, 4] and args[0] == "sheet":
		await _sheets(args[1], args[2], args[3] if args.size() == 4 else "")
	elif args.size() == 4 and args[0] == "views":
		await _views(args[1], args[2], args[3])
	else:
		_fail("usage: count <dir> [out.json] | sheet <dir> <out> [prefix] | views <dir> <views.json> <out>")
		return
	# Audio playback teardown completes on the mixer thread after queued frees.
	await create_timer(0.1).timeout
	quit(1 if _failed else 0)

func _files(dir: String, prefix: String = "") -> PackedStringArray:
	var names: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json") and file.begins_with(prefix):
			names.append(file)
	names.sort()
	return names

## Builds one level the way a match does; returns the arena root.
func _build(info: Dictionary) -> Node3D:
	var arena: Node3D = Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)
	var cover: ArenaCover = ArenaCover.new()
	arena.add_child(cover)
	cover.apply_map_info(info)
	for presenter: Node3D in [M01Intake.new(), M02Ward.new(), M03Yard.new(), M04Town.new(), M05Town.new(),
			M06Port.new(), M07Town.new(), M08Archive.new(), M09Berth.new(), M10Ship.new(), M11Tender.new(),
			M12Habitat.new(), M13Foundry.new(), M14Launch.new(), M15Stadium.new(), M16Avenue.new(),
			M17Office.new(), M18Transit.new(), M19Works.new(), M20Waterworks.new(), StillHereRefuge.new()]:
		arena.add_child(presenter)
		presenter.call("configure_map", info)
	return arena

## Every readable label: visible, non-empty, not a HUD overlay.
static func labels(scene: Node) -> Array[Label3D]:
	var found: Array[Label3D] = []
	for node: Node in scene.find_children("*", "Label3D", true, false):
		var label: Label3D = node as Label3D
		if label.is_visible_in_tree() and not label.text.strip_edges().is_empty():
			found.append(label)
	return found

static func key_of(label: Label3D) -> String:
	if label is WorldSign:
		return (label as WorldSign).message_key
	return "<" + str(label.name) + ">"

func _count(dir: String, out: String) -> void:
	var report: Dictionary = {}
	var files: PackedStringArray = _files(dir)
	if files.is_empty():
		_fail("no map files in " + dir)
		return
	for file: String in files:
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if not info is Dictionary:
			_fail("cannot read " + file)
			return
		var arena: Node3D = _build(info)
		for i: int in range(3):
			await process_frame
		var rows: Array = []
		for label: Label3D in labels(arena):
			var at: Vector3 = label.global_position
			rows.append({"key": key_of(label), "text": label.text.replace("\n", " / "),
				"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]})
		report[file.get_basename()] = {"map_name": str(info.get("map_name", "")), "count": rows.size(), "signs": rows}
		print("%-34s %3d  %s" % [file.get_basename(), rows.size(), str(info.get("map_name", ""))])
		for row: Dictionary in rows:
			print("    %-34s %s" % [row["key"], str(row["text"]).left(90)])
		arena.queue_free()
		for i: int in range(3):
			await process_frame
	if not out.is_empty():
		var handle: FileAccess = FileAccess.open(out, FileAccess.WRITE)
		if handle == null:
			_fail("cannot write " + out)
			return
		handle.store_string(JSON.stringify(report, "  "))

func _setup_view(arena: Node3D, map_name: String) -> Camera3D:
	var settings: FragrSettings = FragrSettings.new("user://audit_world_signs.cfg")
	var layout: Node = ARENA_SCENE.instantiate()
	layout.name = "Layout"
	arena.add_child(layout)
	var world: WorldEnvironment = _world_environment(layout)
	world.environment = ArenaSky.build_environment(map_name)
	RenderQuality.apply(root, settings, world.environment)
	ArenaSky.apply_scene_lights(layout, map_name)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 400.0
	arena.add_child(camera)
	camera.make_current()
	ArenaSky.apply_view_fill(camera, map_name)
	RenderQuality.apply_practicals(arena, settings)
	return camera

func _renderer_ready() -> bool:
	if DisplayServer.get_name() == "headless":
		_fail("sheets need a real renderer")
		return false
	AudioServer.set_bus_mute(0, true)
	root.min_size = Vector2i(1280, 720)
	root.max_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	return true

func _sheets(dir: String, out: String, prefix: String) -> void:
	if not _renderer_ready():
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("cannot create " + out)
		return
	var files: PackedStringArray = _files(dir, prefix)
	if files.is_empty():
		_fail("no matching map files in " + dir)
		return
	for file: String in files:
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if not info is Dictionary:
			_fail("cannot read " + file)
			return
		var arena: Node3D = _build(info)
		var camera: Camera3D = _setup_view(arena, str(info.get("map_name", "")))
		for i: int in range(8):
			await process_frame
		var found: Array[Label3D] = labels(arena)
		var rows: int = maxi(1, ceili(float(found.size()) / COLUMNS))
		var sheet: Image = Image.create(TILE.x * COLUMNS, TILE.y * rows, false, Image.FORMAT_RGBA8)
		sheet.fill(Color("101010"))
		for index: int in range(found.size()):
			var label: Label3D = found[index]
			# A label reads from its local +Z side.
			var facing: Vector3 = label.global_transform.basis.z.normalized()
			var reach: float = clampf(maxf(label.get_aabb().size.x, label.get_aabb().size.y) * 1.6, 2.2, 9.0)
			camera.global_position = label.global_position + facing * reach + Vector3(0, 0.15, 0)
			camera.look_at(label.global_position, Vector3.UP if absf(facing.y) < 0.95 else Vector3.FORWARD)
			for frame: int in range(3):
				await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			image.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, TILE), Vector2i((index % COLUMNS) * TILE.x, (index / COLUMNS) * TILE.y))
		if sheet.save_png(out.path_join(file.get_basename() + "-signs.png")) != OK:
			_fail("cannot save sheet for " + file)
			return
		var legend: PackedStringArray = []
		for index: int in range(found.size()):
			legend.append("%2d %s  %s" % [index, key_of(found[index]), found[index].text.replace("\n", " / ").left(80)])
		var handle: FileAccess = FileAccess.open(out.path_join(file.get_basename() + "-signs.txt"), FileAccess.WRITE)
		if handle == null:
			_fail("cannot write legend for " + file)
			return
		handle.store_string("\n".join(legend) + "\n")
		_shots += 1
		arena.queue_free()
		for i: int in range(3):
			await process_frame
	print("audit_world_signs: wrote %d sheets" % _shots)

func _views(dir: String, views_path: String, out: String) -> void:
	if not _renderer_ready():
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("cannot create " + out)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(views_path))
	if not parsed is Dictionary or parsed.is_empty():
		_fail("views must be a nonempty object")
		return
	var views: Dictionary = parsed
	var by_map: Dictionary = {}
	for name: String in views:
		var value: Variant = views[name]
		if name != name.get_file() or name in [".", ".."] or not value is Dictionary \
				or not value.get("map_info") is String or value["map_info"] != value["map_info"].get_file() \
				or not _vector(value.get("eye")) or not _vector(value.get("look")) \
				or value["eye"] == value["look"]:
			_fail("invalid view " + name)
			return
		var file: String = str(views[name]["map_info"])
		if not by_map.has(file):
			by_map[file] = []
		by_map[file].append(name)
	for file: String in by_map:
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if not info is Dictionary:
			_fail("cannot read " + file)
			return
		var arena: Node3D = _build(info)
		var camera: Camera3D = _setup_view(arena, str(info.get("map_name", "")))
		for i: int in range(8):
			await process_frame
		for name: String in by_map[file]:
			var view: Dictionary = views[name]
			camera.global_position = Vector3(view["eye"][0], view["eye"][1], view["eye"][2])
			camera.look_at(Vector3(view["look"][0], view["look"][1], view["look"][2]), Vector3.UP)
			for frame: int in range(4):
				await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			if image == null or image.save_png(out.path_join(name + ".png")) != OK:
				_fail("cannot save " + name)
				return
			_shots += 1
		arena.queue_free()
		for i: int in range(3):
			await process_frame
	print("audit_world_signs: wrote %d views" % _shots)

static func _vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return false
	return true

static func _world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child: Node in node.get_children():
		var found: WorldEnvironment = _world_environment(child)
		if found != null:
			return found
	return null
