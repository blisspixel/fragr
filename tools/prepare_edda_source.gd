extends SceneTree

const GlbContainer = preload("res://../tools/tern_glb.gd")
const Repair = preload("res://../tools/edda_skin_repair.gd")
const SOURCE_SHA: String = "bb5511f280147bb3f4fa81db6ce1b42a58cb10daebdf486def6a807d3286693f"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or FileAccess.get_sha256(args[0]) != SOURCE_SHA:
		_fail("require pinned original walking rig, candidate output and receipt directory")
		return
	var raw_directory: String = ProjectSettings.globalize_path("res://../art/raw").simplify_path().to_lower() + "/"
	if args[1].simplify_path().to_lower().begins_with(raw_directory) \
		or args[2].simplify_path().to_lower().begins_with(raw_directory) \
		or args[0].simplify_path().to_lower() == args[1].simplify_path().to_lower():
		_fail("raw sources and their directory are read-only preparation inputs")
		return
	var input: Dictionary = GlbContainer.read(args[0])
	if input.is_empty():
		_fail("invalid embedded source container")
		return
	var document: Dictionary = input.document
	var pinned: Dictionary = Repair.read(args[0])
	var importer: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if pinned.is_empty() or importer.append_from_file(args[0], state) != OK:
		_fail("pinned source import failed")
		return
	var model: Node3D = importer.generate_scene(state)
	root.add_child(model)
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source_material: StandardMaterial3D = mesh.get_active_material(0)
	var repair: Dictionary = Repair.corrected_bytes(pinned, source_material.albedo_texture.get_image())
	model.free()
	if repair.is_empty():
		_fail("source repair failed")
		return
	var source_binary: PackedByteArray = repair.bytes.slice(int(pinned.bin_start))
	var views: Array = document.get("bufferViews", [])
	var images: Array = document.get("images", [])
	if images.size() != 3 or document.get("materials", []).size() != 1 \
		or document.get("skins", []).size() != 1 or document.skins[0].joints.size() != 24:
		_fail("source structure changed")
		return
	var image_views: Dictionary = {}
	var rows: Array[Dictionary] = []
	if DirAccess.make_dir_recursive_absolute(args[2]) != OK:
		_fail("cannot create receipt directory")
		return
	for index: int in range(images.size()):
		var spec: Dictionary = images[index]
		var view_index: int = int(spec.get("bufferView", -1))
		if view_index < 0 or view_index >= views.size() or image_views.has(view_index):
			_fail("source images must use distinct embedded views")
			return
		var view: Dictionary = views[view_index]
		var offset: int = int(view.get("byteOffset", 0))
		var length: int = int(view.get("byteLength", 0))
		if offset < 0 or length <= 0 or offset + length > source_binary.size():
			_fail("image view outside source buffer")
			return
		var image: Image = Image.new()
		var image_bytes: PackedByteArray = source_binary.slice(offset, offset + length)
		var error: Error = image.load_png_from_buffer(image_bytes) if spec.mimeType == "image/png" else image.load_jpg_from_buffer(image_bytes)
		if error != OK:
			_fail("cannot decode source map")
			return
		var original_size: Vector2i = image.get_size()
		image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		# Preserve original paint. Matte response belongs to material factors.
		image_views[view_index] = image.save_png_to_buffer()
		spec.mimeType = "image/png"
		var map_path: String = args[2].path_join("map_%d.png" % index)
		if image.save_png(map_path) != OK:
			_fail("cannot retain compact map control")
			return
		rows.append({"image": index, "original_size": [original_size.x, original_size.y],
			"prepared_size": [1024, 1024], "sha256": FileAccess.get_sha256(map_path)})
	var binary: PackedByteArray = []
	for index: int in range(views.size()):
		var view: Dictionary = views[index]
		var offset: int = int(view.get("byteOffset", 0))
		var length: int = int(view.get("byteLength", 0))
		if int(view.get("buffer", -1)) != 0 or offset < 0 or length < 0 or offset + length > source_binary.size():
			_fail("buffer view outside embedded source")
			return
		while binary.size() % 4 != 0:
			binary.append(0)
		var payload: PackedByteArray = image_views[index] if image_views.has(index) else source_binary.slice(offset, offset + length)
		view.byteOffset = binary.size()
		view.byteLength = payload.size()
		binary.append_array(payload)
	var material: Dictionary = document.materials[0]
	material.pbrMetallicRoughness.metallicFactor = 0.08
	material.pbrMetallicRoughness.roughnessFactor = 1.0
	# Existing packed roughness can contain low values. Bound only its green
	# channel; leave the source albedo, metal variation and normal map intact.
	var roughness_view: int = int(images[2].bufferView)
	var roughness: Image = Image.new()
	if roughness.load_png_from_buffer(image_views[roughness_view]) != OK:
		_fail("cannot decode compact roughness")
		return
	for y: int in range(1024):
		for x: int in range(1024):
			var color: Color = roughness.get_pixel(x, y)
			color.g = maxf(0.88, color.g)
			roughness.set_pixel(x, y, color)
	var replacement: PackedByteArray = roughness.save_png_to_buffer()
	# Rebuild once because PNG encoding changes the view length.
	var final_binary: PackedByteArray = []
	for index: int in range(views.size()):
		var view: Dictionary = views[index]
		var payload: PackedByteArray = replacement if index == roughness_view else binary.slice(int(view.byteOffset), int(view.byteOffset) + int(view.byteLength))
		while final_binary.size() % 4 != 0:
			final_binary.append(0)
		view.byteOffset = final_binary.size()
		view.byteLength = payload.size()
		final_binary.append_array(payload)
	document.buffers[0].byteLength = final_binary.size()
	document.asset.erase("generator")
	if not GlbContainer.write(args[1], document, final_binary, input.original_json):
		_fail("candidate write failed")
		return
	if roughness.save_png(args[2].path_join("map_2.png")) != OK:
		_fail("cannot retain compact roughness control")
		return
	rows[2].sha256 = FileAccess.get_sha256(args[2].path_join("map_2.png"))
	var file: FileAccess = FileAccess.open(args[2].path_join("preparation.json"), FileAccess.WRITE)
	if file == null:
		_fail("receipt write failed")
		return
	file.store_string(JSON.stringify({"schema": 1, "runtime_selected": false, "new_credits": 0,
		"source_sha256": SOURCE_SHA, "prepared_sha256": FileAccess.get_sha256(args[1]),
		"maps": rows, "metallic_factor": 0.08, "roughness_floor": 0.88,
		"geometry_bind_uv_animation_preserved": true, "skin_vertices": Array(repair.edited_vertices), "skin_free_groups": repair.free_groups, "skin_welded_groups": repair.welded_groups, "skin_only_sha256": _hash(repair.bytes), "skin_repair": "continuous welded attachment/forearm field; source masks and boundaries independently checked"}, "\t") + "\n")
	file.close()
	await process_frame
	print("prepare_edda_source: PASS (pinned retained rig, bounded skin repair, compact matte maps; candidate only)")
	quit(0)

func _fail(message: String) -> void:
	push_error("prepare_edda_source: " + message)
	quit(1)

static func _hash(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
