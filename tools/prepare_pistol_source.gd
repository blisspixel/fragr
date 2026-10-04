extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const Workshop = preload("res://scripts/model_geometry.gd")
const SOURCE_SHA256: String = "9c097088ab52e63730d6ec4494180c4663b812016035c490a06a19bf51a51318"
const METRES: float = 0.24

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.get_sha256(args[0]) != SOURCE_SHA256:
		_fail("require reviewed source and output")
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[0])
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	var copyright: String = str(parsed["asset"].get("copyright", ""))
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(args[0], state) != OK:
		_fail("cannot import source")
		return
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		_fail("source mesh count changed")
		return
	var imported: MeshInstance3D = meshes[0] as MeshInstance3D
	if imported.mesh.get_surface_count() != 1:
		_fail("source surface count changed")
		return
	var arrays: Array = imported.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var canonical: Dictionary[Vector3i, int] = {}
	var parents: PackedInt32Array = []
	parents.resize(vertices.size())
	for index: int in range(vertices.size()):
		var v: Vector3 = vertices[index] * 100000.0
		var key: Vector3i = Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))
		parents[index] = canonical.get(key, index)
		canonical[key] = parents[index]
	for face: int in range(0, indices.size(), 3):
		for offset: int in [1, 2]:
			parents[_root(parents, indices[face + offset])] = _root(parents, indices[face])
	var counts: Dictionary[int, int] = {}
	var bounds: Dictionary[int, AABB] = {}
	for face: int in range(0, indices.size(), 3):
		var key: int = _root(parents, indices[face])
		counts[key] = counts.get(key, 0) + 1
		if not bounds.has(key):
			bounds[key] = AABB(vertices[indices[face]], Vector3.ZERO)
		for offset: int in range(3):
			bounds[key] = bounds[key].expand(vertices[indices[face + offset]])
	if counts.size() != 61 or counts.get(4556) != 805 or counts.get(3443) != 176 or counts.get(4783) != 308:
		_fail("reviewed slide, trigger or hammer topology changed")
		return
	var groups: Dictionary[int, String] = {}
	for key: int in counts:
		var b: AABB = bounds[key]
		var serration: bool = b.position.y > 0.24 and b.end.y < 0.35 and (b.position.x > 0.058 or b.end.x < -0.065)
		groups[key] = "Slide" if key in [4556, 4542, 4135, 4711, 4816, 1478] or serration else "Body"
	groups[3443] = "Trigger"
	groups[4783] = "Hammer"
	var material: StandardMaterial3D = (imported.get_active_material(0) as StandardMaterial3D).duplicate()
	var textures: Dictionary[int, ImageTexture] = {}
	for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS]:
		var texture: Texture2D = material.get_texture(slot)
		if texture == null:
			continue
		var key: int = texture.get_instance_id()
		if not textures.has(key):
			var image: Image = texture.get_image()
			if image.is_compressed() and image.decompress() != OK:
				_fail("cannot decode embedded map")
				return
			image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
			if slot == BaseMaterial3D.TEXTURE_ALBEDO:
				_quiet_albedo(image)
			textures[key] = ImageTexture.create_from_image(image)
		material.set_texture(slot, textures[key])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.metallic_texture = null
	material.roughness_texture = null
	material.metallic = 0.06
	material.roughness = 0.96
	material.normal_scale = 0.20
	material.vertex_color_use_as_albedo = true
	var gun: Node3D = Node3D.new()
	gun.name = "Pistol"
	root.add_child(gun)
	var basis: Basis = Basis(Vector3.UP, PI)
	var origin: Vector3 = Vector3(0, 0.30, -0.26)
	var group_counts: Dictionary[String, int] = {}
	for group: String in ["Body", "Slide", "Trigger", "Hammer"]:
		var pivot: Vector3 = origin
		if group == "Trigger":
			pivot = Vector3(0, 0.196, -0.017)
		elif group == "Hammer":
			pivot = Vector3(0, 0.25, -0.30)
		var holder: Node3D = Node3D.new()
		holder.name = group
		holder.position = basis * (pivot - origin) * METRES
		gun.add_child(holder)
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for face: int in range(0, indices.size(), 3):
			if groups[_root(parents, indices[face])] != group:
				continue
			group_counts[group] = group_counts.get(group, 0) + 1
			var face_center: Vector3 = Vector3.ZERO
			var face_normal: Vector3 = Vector3.ZERO
			for offset: int in range(3):
				face_center += basis * (vertices[indices[face + offset]] - origin) * METRES / 3.0
				face_normal += basis * normals[indices[face + offset]] / 3.0
			var plane: Color = Color.WHITE
			if group == "Slide":
				plane = Color(1.20, 1.20, 1.16) if face_normal.y > 0.55 else Color(0.63, 0.65, 0.65)
				if face_center.y > 0.023:
					plane = Color(0.27, 0.29, 0.29)
			for offset: int in range(3):
				var index: int = indices[face + offset]
				surface.set_color(plane)
				surface.set_normal(basis * normals[index])
				surface.set_uv(uv[index])
				surface.add_vertex(basis * (vertices[index] - pivot) * METRES)
		surface.index()
		surface.generate_tangents()
		var piece: MeshInstance3D = MeshInstance3D.new()
		piece.name = group + "Mesh"
		piece.mesh = surface.commit()
		piece.material_override = material
		holder.add_child(piece)
	var g: RefCounted = Workshop.new()
	var edge: StandardMaterial3D = g.material("pistol_machined_trigger", Color("626b65"), 0.10, 0.91)
	var guide: StandardMaterial3D = g.material("pistol_spring_guide", Color("525951"), 0.06, 0.95)
	var trim: StandardMaterial3D = g.material("pistol_sight_and_seam", Color("202725"), 0.0, 0.98)
	trim.albedo_texture = null
	for side: float in [-1.0, 1.0]:
		g.block(gun.get_node("Slide"), "SlideSeamLeft" if side < 0.0 else "SlideSeamRight",
			Vector3(0.001, 0.003, 0.140), trim, Vector3(side * 0.0167, -0.011, -0.088))
		g.block(gun.get_node("Slide"), "RearSightLeft" if side < 0.0 else "RearSightRight",
			Vector3(0.004, 0.003, 0.006), trim, Vector3(side * 0.006, 0.026, -0.003))
	g.block(gun.get_node("Slide"), "FrontSight", Vector3(0.003, 0.003, 0.009), trim, Vector3(0, 0.025, -0.168))
	# The reviewed front recoil plug follows the slide. Its guide stays on the
	# receiver, independently from the fixed barrel and open muzzle bore.
	g.cylinder(gun.get_node("Body"), "SpringGuide", 0.0018, 0.032, guide, Vector3(0.0012, -0.016, -0.166), 10)
	# A deliberate curved blade reads inside the intact guard. The original
	# thin trigger geometry stays in its own moving group and is preserved.
	g.prism(gun.get_node("Trigger"), "CurvedBlade", PackedVector2Array([
		Vector2(-0.003, -0.002), Vector2(0.001, -0.005), Vector2(0.003, -0.017),
		Vector2(0.000, -0.026), Vector2(-0.003, -0.025), Vector2(-0.001, -0.016),
		Vector2(-0.003, -0.010), Vector2(-0.005, -0.004)]), 0.0042, edge)
	var additions: Dictionary[String, int] = {}
	for name: String in ["SpringGuide", "CurvedBlade", "SlideSeamLeft", "SlideSeamRight", "RearSightLeft", "RearSightRight", "FrontSight"]:
		var piece: MeshInstance3D = gun.find_child(name, true, false) as MeshInstance3D
		additions[name] = piece.mesh.get_faces().size() / 3
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = basis * (Vector3(-0.0045, 0.313, 0.501) - origin) * METRES
	gun.add_child(muzzle)
	var output: GLTFDocument = GLTFDocument.new()
	output.image_format = "PNG"
	var export_state: GLTFState = GLTFState.new()
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK or output.append_from_scene(gun, export_state) != OK or output.write_to_filesystem(export_state, args[1]) != OK or not Metadata.clean(args[1], copyright):
		_fail("cannot export candidate")
		return
	var receipt: FileAccess = FileAccess.open(args[1] + ".json", FileAccess.WRITE)
	if receipt == null:
		_fail("cannot write source receipt")
		return
	receipt.store_string(JSON.stringify({"schema": 1, "raw_sha256": SOURCE_SHA256,
		"material_finish_sha256": FileAccess.get_sha256("res://assets/models/finishes/metal.png"),
		"prepared_sha256": FileAccess.get_sha256(args[1]), "prepare_sha256": FileAccess.get_sha256(get_script().resource_path),
		"original_triangles": 5154, "original_groups": group_counts, "authored_triangles": additions,
		"metres_per_raw_unit": METRES, "maps_max_pixels": 1024,
		"material_policy": {"albedo_cluster_pixels":4, "metallic":0.06, "roughness":0.96,
			"normal_scale":0.20, "roughness_map":false, "metallic_map":false},
		"mechanism": {"moving_recoil_plug_island": 1478, "fixed_barrel_island": 4991, "slide_travel_m": 0.012},
		"runtime_selected": false}, "\t") + "\n")
	receipt.close()
	original.free()
	gun.free()
	await process_frame
	print("prepare_pistol_source: PASS (5154 preserved triangles, groups ", group_counts, ", additions ", additions, ", embedded 1K maps; visual acceptance open)")
	quit(0)

func _quiet_albedo(image: Image) -> void:
	# Broad paint and walnut value groups. Mechanical edges come from retained
	# geometry, rather than white scratch specks baked into the source atlas.
	image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			var value: float = clampf(pixel.get_luminance(), 0.0, 1.0)
			var wood: bool = pixel.r > pixel.g * 1.20 and pixel.g > pixel.b * 1.03 and pixel.r - pixel.g > 0.035
			var finish: Color
			if wood:
				finish = Color("62432d").lerp(Color("946239"), snappedf(value, 1.0 / 8.0))
			elif pixel.g > pixel.r * 1.12 and pixel.g > pixel.b * 1.06:
				finish = Color("4c594a").lerp(Color("65745a"), snappedf(value, 1.0 / 8.0))
			else:
				finish = Color("323b3b").lerp(Color("4b5451"), snappedf(value, 1.0 / 8.0))
			finish.a = pixel.a
			image.set_pixel(x, y, finish)
	image.resize(1024, 1024, Image.INTERPOLATE_NEAREST)

func _root(parents: PackedInt32Array, index: int) -> int:
	var result: int = index
	while parents[result] != result:
		result = parents[result]
	return result

func _fail(message: String) -> void:
	push_error("prepare_pistol_source: " + message)
	quit(1)
