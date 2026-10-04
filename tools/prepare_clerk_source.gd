extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() not in [2, 3]:
		_fail("require walking GLB, output source GLB and optional cast name")
		return
	var cast_name: String = args[2] if args.size() == 3 else "Clerk"
	if cast_name not in ["Clerk", "Sweeper", "Auditor", "FreeHuman", "Latch", "Enforcer"]:
		_fail("unsupported cast name")
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[0])
	if bytes.size() < 20 or bytes.size() > 64 * 1024 * 1024:
		_fail("source size outside bounds")
		return
	var json_length: int = bytes.decode_u32(12)
	if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 \
		or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a \
		or json_length > bytes.size() - 20 or json_length % 4 != 0:
		_fail("invalid source framing")
		return
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("asset") is Dictionary:
		_fail("invalid source document")
		return
	var original_copyright: String = str(parsed["asset"].get("copyright", ""))
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(args[0], state) != OK:
		_fail("source import failed")
		return
	var model: Node3D = document.generate_scene(state)
	if model == null:
		_fail("source scene missing")
		return
	root.add_child(model)
	model.name = cast_name
	var cache: Dictionary[int, ImageTexture] = {}
	for candidate: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = candidate as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if original == null:
				_fail("source material is unsupported")
				return
			var material: StandardMaterial3D = original.duplicate()
			for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var texture: Texture2D = material.get_texture(slot)
				if texture == null:
					continue
				var key: int = texture.get_instance_id()
				if not cache.has(key):
					var image: Image = texture.get_image()
					if image.is_compressed() and image.decompress() != OK:
						_fail("cannot decode source texture")
						return
					image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
					if slot == BaseMaterial3D.TEXTURE_ALBEDO and cast_name == "Clerk":
						_grade_cloth(image)
					cache[key] = ImageTexture.create_from_image(image)
				material.set_texture(slot, cache[key])
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mesh.set_surface_override_material(surface, material)
	for candidate: Node in model.find_children("*", "AnimationPlayer", true, false):
		var player: AnimationPlayer = candidate as AnimationPlayer
		var library: AnimationLibrary = AnimationLibrary.new()
		for clip: StringName in player.get_animation_list():
			if String(clip).contains("walking"):
				var animation: Animation = player.get_animation(clip).duplicate(true)
				animation.loop_mode = Animation.LOOP_LINEAR
				library.add_animation(&"walk", animation)
		for key: StringName in player.get_animation_library_list():
			player.remove_animation_library(key)
		player.add_animation_library(&"", library)
	var export_document: GLTFDocument = GLTFDocument.new()
	export_document.image_format = "PNG"
	var export_state: GLTFState = GLTFState.new()
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK \
		or export_document.append_from_scene(model, export_state) != OK \
		or export_document.write_to_filesystem(export_state, args[1]) != OK \
		or not Metadata.clean(args[1], original_copyright):
		_fail("source export failed")
		return
	model.free()
	await process_frame
	print("prepare_clerk_source: PASS (embedded 1K maps, owned source with preserved skin and walk)")
	quit(0)

func _grade_cloth(image: Image) -> void:
	# Keep face, bone plates, metal and red issue marks. The reference's green
	# fabric becomes the established charcoal Union cloth with its wear intact.
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.g > color.r * 1.06 and color.g > color.b * 1.03 and color.s > 0.15:
				var value: float = color.v * 0.8
				image.set_pixel(x, y, Color(value, value, value * 1.04, color.a))

func _fail(message: String) -> void:
	push_error("prepare_clerk_source: " + message)
	quit(1)
