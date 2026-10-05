extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const SPECS: Array[Dictionary] = [
	{"id":"air-scrubber", "name":"AirScrubber", "sha":"c6e435c6bf06f2dde238f5f3ee7fc20dc389fc6fab9319e5504a6ce45fe72997", "triangles":11910, "vertices":17576, "axis":1, "metres":1.65},
	{"id":"water-pump", "name":"WaterPump", "sha":"631dabc2bb87b34a386e52434dfc0e46cdda079c323b789944d84302420d7e30", "triangles":11880, "vertices":16875, "axis":0, "metres":1.20},
	{"id":"community-radio", "name":"CommunityRadio", "sha":"aac13efc917e53540911bba5cefa9fedd6f08086eb181ea579d37e44d78b2412", "triangles":11646, "vertices":14791, "axis":0, "metres":0.38}]

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not DirAccess.dir_exists_absolute(args[0]) or DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		_fail("require source directory and writable preparation directory")
		return
	for spec: Dictionary in SPECS:
		if not _prepare(args[0], args[1], spec):
			return
	await process_frame
	print("prepare_world_prop_sources: PASS (3 fixed compact sources; physical placement and selection remain open)")
	quit(0)

func _prepare(source_dir: String, output_dir: String, spec: Dictionary) -> bool:
	var path: String = source_dir.path_join(spec["id"] + "-stylized-v1-ultra-0.glb")
	if FileAccess.get_sha256(path) != spec["sha"]:
		_fail("reviewed source fingerprint changed")
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var metadata: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	if not metadata is Dictionary or not metadata.get("asset") is Dictionary or not metadata["asset"].get("copyright", "") is String:
		_fail("invalid legal metadata")
		return false
	var copyright: String = metadata["asset"].get("copyright", "")
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(path, state) != OK:
		_fail("cannot import reviewed source")
		return false
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		original.free()
		_fail("one fixed source mesh required")
		return false
	var mesh: MeshInstance3D = meshes[0] as MeshInstance3D
	if mesh.mesh.get_surface_count() != 1 or mesh.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		original.free()
		_fail("one triangle surface required")
		return false
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != spec["vertices"] or indices.size() != spec["triangles"] * 3 or normals.size() != vertices.size() or uv.size() != vertices.size():
		original.free()
		_fail("measured source arrays changed")
		return false
	var bounds: AABB = mesh.mesh.get_aabb()
	var pivot: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var scale: float = float(spec["metres"]) / bounds.size[int(spec["axis"])]
	var basis: Basis = Basis(Vector3.UP, PI)
	var offset: Vector3 = Vector3(0.0, 0.012, 0.0) if spec["id"] == "water-pump" else Vector3.ZERO
	var material: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
	if material == null or material.albedo_texture == null or material.normal_texture == null:
		original.free()
		_fail("reviewed embedded paint/normal maps required")
		return false
	material = material.duplicate()
	var paint: Image = material.albedo_texture.get_image()
	if paint.is_compressed() and paint.decompress() != OK:
		original.free()
		_fail("cannot decode paint")
		return false
	_quiet(paint, spec["id"])
	var normal: Image = material.normal_texture.get_image()
	if normal.is_compressed() and normal.decompress() != OK:
		original.free()
		_fail("cannot decode normal")
		return false
	normal.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	material.albedo_texture = ImageTexture.create_from_image(paint)
	material.normal_texture = ImageTexture.create_from_image(normal)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.metallic_texture = null
	material.roughness_texture = null
	material.metallic = 0.08
	material.roughness = 0.94
	material.normal_scale = 0.16
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in indices:
		if index < 0 or index >= vertices.size() or not vertices[index].is_finite() or not normals[index].is_finite() or not uv[index].is_finite():
			original.free()
			_fail("invalid source attributes")
			return false
		surface.set_normal(basis * normals[index])
		surface.set_uv(uv[index])
		surface.add_vertex(basis * (vertices[index] - pivot) * scale + offset)
	surface.index()
	surface.generate_tangents()
	var result: Node3D = Node3D.new()
	result.name = spec["name"]
	root.add_child(result)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = surface.commit()
	body.material_override = material
	result.add_child(body)
	var supports: Array[Dictionary] = []
	if spec["id"] == "water-pump":
		var source_arrays: Array = body.mesh.surface_get_arrays(0)
		var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
		for anchor: Vector2 in [Vector2(-0.33846650,-0.17912327),Vector2(-0.35088730,0.17231965),Vector2(0.39781180,-0.20452595),Vector2(0.39796448,0.20965500)]:
			var hit: Vector3 = _find_support(source_vertices,source_indices,anchor.x,anchor.y)
			if not hit.is_finite() or hit.y < 0.008 or hit.y > 0.06:
				original.free()
				result.free()
				_fail("mounting pad has no actual supported underside")
				return false
			var height: float = hit.y + 0.003
			var pad: MeshInstance3D = MeshInstance3D.new()
			pad.name = "MountingPad%d" % supports.size()
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.10,height,0.06)
			pad.mesh = box
			pad.position = Vector3(hit.x,height * 0.5,hit.z)
			var pad_material: StandardMaterial3D = StandardMaterial3D.new()
			pad_material.albedo_color = Color("303535")
			pad_material.roughness = 0.98
			pad.material_override = pad_material
			result.add_child(pad)
			supports.append({"centre_xz_m":[hit.x,hit.z],"source_underside_y_m":hit.y,"pad_top_y_m":height,"intersection_depth_m":0.003})
	var output: String = output_dir.path_join(spec["id"] + ".glb")
	var exporter: GLTFDocument = GLTFDocument.new()
	exporter.image_format = "PNG"
	var exported: GLTFState = GLTFState.new()
	var success: bool = exporter.append_from_scene(result, exported) == OK and exporter.write_to_filesystem(exported, output) == OK and Metadata.clean(output, copyright)
	var receipt: FileAccess = FileAccess.open(output + ".json", FileAccess.WRITE)
	if success and receipt != null:
		receipt.store_string(JSON.stringify({"schema":1, "id":spec["id"], "raw_sha256":spec["sha"], "prepared_sha256":FileAccess.get_sha256(output),
			"raw_triangles":spec["triangles"], "retained_triangles":spec["triangles"], "authored_triangles":supports.size() * 12, "replaced_triangles":0,
			"provisional_dimension_m":spec["metres"], "dimension_axis":spec["axis"], "metres_per_source_unit":scale,
			"source_pivot":[pivot.x,pivot.y,pivot.z], "body_offset_m":[offset.x,offset.y,offset.z], "mounting_supports":supports, "fixed_source":true, "runtime_selected":false,
			"floor_contacts_accepted":false, "independent_uv_winding_proof":false, "maps_max_pixels":1024}, "\t") + "\n")
		receipt.close()
	else:
		success = false
	original.free()
	result.free()
	if not success:
		_fail("cannot export source and receipt")
	return success

func _quiet(image: Image, id: String) -> void:
	image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	var samples: Image = Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, image.get_data())
	for y: int in range(256):
		for x: int in range(256):
			var average: Color = Color(0.0, 0.0, 0.0, 0.0)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					average += samples.get_pixel(clampi(x + dx, 0, 255), clampi(y + dy, 0, 255)) / 9.0
			var value: float = snappedf(clampf(average.get_luminance(),0.0,1.0),0.25)
			var finish: Color
			if id == "air-scrubber":
				if average.r > average.g * 1.10 and average.g > average.b * 1.30:
					finish = Color("75613c").lerp(Color("bfa364"),value)
				elif average.g > average.r * 1.08 and average.g > average.b * 1.08:
					finish = Color("5b6859").lerp(Color("89927a"),value)
				elif average.get_luminance() > 0.45:
					finish = Color("a29c8d").lerp(Color("d8d0bb"),value)
				else:
					finish = Color("303535").lerp(Color("59605d"),value)
			elif id == "water-pump":
				if average.r > average.g * 1.18 and average.g > average.b * 1.12:
					finish = Color("554132").lerp(Color("816349"),value)
				elif average.g > average.r * 0.98 and average.g > average.b * 1.05 and average.get_luminance() > 0.20:
					finish = Color("5b7768").lerp(Color("91ad93"),value)
				else:
					finish = Color("34393a").lerp(Color("7b827b"),value)
			else:
				if average.r > average.g * 1.18 and average.g > average.b * 1.12:
					finish = Color("6b4b34").lerp(Color("aa7a4d"),value)
				elif average.g > average.b * 1.45 and average.get_luminance() > 0.45:
					finish = Color("8e6e42").lerp(Color("caaa69"),value)
				else:
					finish = Color("303b37").lerp(Color("59635a"),value)
			finish.a = samples.get_pixel(x,y).a
			image.set_pixel(x,y,finish)
	image.resize(1024, 1024, Image.INTERPOLATE_NEAREST)

func _fail(message: String) -> void:
	push_error("prepare_world_prop_sources: " + message)
	quit(1)

func _first_hit(vertices: PackedVector3Array, indices: PackedInt32Array, start: Vector3, end: Vector3) -> Vector3:
	var best: Vector3 = Vector3(INF,INF,INF)
	var distance: float = INF
	for face: int in range(0,indices.size(),3):
		var value: Variant = Geometry3D.segment_intersects_triangle(start,end,vertices[indices[face]],vertices[indices[face+1]],vertices[indices[face+2]])
		if value != null:
			var hit: Vector3 = value
			if start.distance_to(hit) < distance:
				best = hit
				distance = start.distance_to(hit)
	return best

func _find_support(vertices: PackedVector3Array,indices: PackedInt32Array,x: float,z: float) -> Vector3:
	return _first_hit(vertices,indices,Vector3(x,-0.01,z),Vector3(x,0.08,z))
