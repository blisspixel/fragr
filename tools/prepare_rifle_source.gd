extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const Geometry = preload("res://scripts/model_geometry.gd")
const SOURCE_SHA256: String = "5d53e8995a825b4e594c9b812759dcb070342bfddc73bd64ba351ea9a0576394"
const METRES: float = 0.94

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
	if counts.size() != 55 or counts.get(5149) != 100 or counts.get(6173) != 116 or counts.get(5719) != 88:
		_fail("reviewed bolt, handle or trigger topology changed")
		return
	var groups: Dictionary[int, String] = {}
	for key: int in counts:
		groups[key] = "Bolt" if key in [5149, 6173] else "Body"
	groups[5719] = "Trigger"
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
	gun.name = "Rifle"
	root.add_child(gun)
	var basis: Basis = Basis(Vector3.UP, PI * 0.5)
	var origin: Vector3 = Vector3(0, 0.065, -0.0125)
	var group_counts: Dictionary[String, int] = {}
	for group: String in ["Body", "Bolt", "Trigger"]:
		var pivot: Vector3 = origin
		if group == "Trigger":
			pivot = Vector3(-0.12, 0.010, -0.0125)
		var holder: Node3D = Node3D.new()
		holder.name = group
		holder.position = basis * (pivot - origin) * METRES
		gun.add_child(holder)
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for face: int in range(0, indices.size(), 3):
			var island: int = _root(parents, indices[face])
			if groups[island] != group:
				continue
			group_counts[group] = group_counts.get(group, 0) + 1
			var face_normal: Vector3 = Vector3.ZERO
			for offset: int in range(3):
				face_normal += basis * normals[indices[face + offset]] / 3.0
			var plane: Color = Color.WHITE
			if group == "Bolt":
				plane = Color(1.20, 1.20, 1.16) if face_normal.y > 0.55 else Color(0.63, 0.65, 0.65)
			elif group == "Body" and island not in [5655, 5669, 5461]:
				plane = Color(1.22, 1.22, 1.18) if face_normal.y > 0.55 else Color(0.82, 0.84, 0.82)
				if island in [6055, 5585, 6035]:
					plane = Color(0.53, 0.55, 0.53) if face_normal.y < 0.55 else Color(1.08, 1.08, 1.02)
				if island == 5901:
					var center: Vector3 = (vertices[indices[face]] + vertices[indices[face + 1]] + vertices[indices[face + 2]]) / 3.0
					var radial: Vector2 = Vector2(center.y - 0.060, center.z + 0.015) * METRES
					if center.x > 0.445 and center.x < 0.470 and radial.length() < 0.008:
						plane = Color(0.12, 0.14, 0.14)
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
	var additions: Dictionary[String, int] = {}
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = basis * (Vector3(0.5, 0.060, -0.015) - origin) * METRES
	gun.add_child(muzzle)
	var geometry: RefCounted = Geometry.new()
	for label: String in ["BoreLip", "BoreLiner"]:
		var finish: StandardMaterial3D = StandardMaterial3D.new()
		finish.albedo_color = Color("303a37") if label == "BoreLip" else Color("121a18")
		finish.roughness = 0.96
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		var profile: PackedVector2Array = PackedVector2Array([
			Vector2(0.0012, 0.0068), Vector2(0.0012, 0.0105),
			Vector2(0.0040, 0.0105), Vector2(0.0040, 0.0068)]) if label == "BoreLip" else PackedVector2Array([
			Vector2(0.003, 0.0067), Vector2(0.003, 0.0080),
			Vector2(0.031, 0.0080), Vector2(0.031, 0.0067)])
		var piece: MeshInstance3D = geometry.lathe(gun, label, profile, finish, muzzle.position, 24)
		additions[label] = piece.mesh.get_faces().size() / 3
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
		"prepared_sha256": FileAccess.get_sha256(args[1]), "prepare_sha256": FileAccess.get_sha256(get_script().resource_path),
		"original_triangles": 6122, "original_groups": group_counts, "authored_triangles": additions,
		"metres_per_raw_unit": METRES, "maps_max_pixels": 1024,
		"material_policy": {"albedo_cluster_pixels":4, "metallic":0.06, "roughness":0.96,
			"normal_scale":0.20, "roughness_map":false, "metallic_map":false},
		"mechanism": {"moving_bolt_islands": [5149, 6173], "trigger_island": 5719, "fixed_guard_island": 5343, "bolt_travel_m": 0.030},
		"runtime_selected": false}, "\t") + "\n")
	receipt.close()
	original.free()
	gun.free()
	await process_frame
	print("prepare_rifle_source: PASS (6122 preserved triangles, groups ", group_counts, ", additions ", additions, ", embedded 1K maps; visual acceptance open)")
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
	push_error("prepare_rifle_source: " + message)
	quit(1)
