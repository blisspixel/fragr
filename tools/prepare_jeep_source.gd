extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const SOURCE_SHA: String = "18943cef37bc341b3f2ef5672e1a0777e200bd83749f27ab02005d7827f91200"
const OUTPUT: String = "res://assets/vehicles"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.get_sha256(args[0]) != SOURCE_SHA:
		_fail("require the reviewed jeep source")
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[0])
	var metadata: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	if not metadata is Dictionary or not metadata.get("asset") is Dictionary:
		_fail("invalid source metadata")
		return
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(args[0], state) != OK:
		_fail("source import failed")
		return
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		_fail("source mesh count changed")
		return
	var source: MeshInstance3D = meshes[0] as MeshInstance3D
	var arrays: Array = source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != 21998 or indices.size() != 11962 * 3:
		_fail("source geometry changed")
		return
	var bounds: AABB = source.global_transform * source.mesh.get_aabb()
	var pivot: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var shape: Basis = Basis(Vector3.UP, PI).scaled(Vector3(3.8 / bounds.size.x, 3.8 / bounds.size.x, 1.9 / bounds.size.z))
	var normal_basis: Basis = shape.inverse().transposed()
	var paint_material: StandardMaterial3D = source.get_active_material(0).duplicate() as StandardMaterial3D
	var paint: Image = paint_material.albedo_texture.get_image()
	if paint.is_compressed() and paint.decompress() != OK:
		_fail("paint decode failed")
		return
	paint.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	paint.convert(Image.FORMAT_RGBA8)
	# Keep the source's material regions, quiet subpixel photographic noise and
	# use discrete values. Directional lighting supplies the final form.
	for y: int in range(512):
		for x: int in range(512):
			var color: Color = paint.get_pixel(x, y)
			color.r = snappedf(color.r, 1.0 / 24.0)
			color.g = snappedf(color.g, 1.0 / 24.0)
			color.b = snappedf(color.b, 1.0 / 24.0)
			paint.set_pixel(x, y, color)
	paint_material.albedo_texture = ImageTexture.create_from_image(paint)
	paint_material.normal_enabled = false
	paint_material.normal_texture = null
	paint_material.metallic_texture = null
	paint_material.roughness_texture = null
	paint_material.metallic = 0.08
	paint_material.roughness = 0.92
	paint_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var centres: Array[Vector3] = [Vector3(1.13, 0.43, -0.75), Vector3(1.13, 0.43, 0.75), Vector3(-1.19, 0.43, -0.75), Vector3(-1.19, 0.43, 0.75)]
	var surfaces: Array[SurfaceTool] = []
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for index: int in range(5):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces.append(surface)
	for triangle: int in range(0, indices.size(), 3):
		var positions: Array[Vector3] = []
		for corner: int in range(3):
			positions.append(shape * (source.global_transform * vertices[indices[triangle + corner]] - pivot))
		var centre: Vector3 = (positions[0] + positions[1] + positions[2]) / 3.0
		var slot: int = 0
		for wheel: int in range(centres.size()):
			var hub: Vector3 = centres[wheel]
			if signf(centre.z) == signf(hub.z) and absf(centre.z) > 0.57 and Vector2(centre.x - hub.x, centre.y - hub.y).length() < 0.445:
				slot = wheel + 1
				break
		counts[slot] += 1
		for corner: int in range(3):
			var vertex_index: int = indices[triangle + corner]
			surfaces[slot].set_normal((normal_basis * source.global_basis * normals[vertex_index]).normalized())
			surfaces[slot].set_uv(uv[vertex_index])
			surfaces[slot].add_vertex(positions[corner] - (centres[slot - 1] if slot > 0 else Vector3.ZERO))
	var result: Node3D = Node3D.new()
	result.name = "UtilityJeep"
	root.add_child(result)
	for index: int in range(5):
		if counts[index] < 80:
			_fail("wheel partition has too little geometry")
			return
		surfaces[index].index()
		surfaces[index].generate_tangents()
		var part: MeshInstance3D = MeshInstance3D.new()
		part.name = "Chassis" if index == 0 else "Wheel%d" % (index - 1)
		part.mesh = surfaces[index].commit()
		part.material_override = paint_material
		part.position = Vector3.ZERO if index == 0 else centres[index - 1]
		result.add_child(part)
	var output: String = ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("cannot create output")
		return
	var exporter: GLTFDocument = GLTFDocument.new()
	exporter.image_format = "PNG"
	var exported: GLTFState = GLTFState.new()
	var path: String = output.path_join("jeep.glb")
	if exporter.append_from_scene(result, exported) != OK or exporter.write_to_filesystem(exported, path) != OK or not Metadata.clean(path, str(metadata["asset"].get("copyright", ""))):
		_fail("cannot export legal source")
		return
	var receipt: FileAccess = FileAccess.open(output.path_join("jeep.json"), FileAccess.WRITE)
	if receipt == null:
		_fail("cannot write receipt")
		return
	receipt.store_string(JSON.stringify({"schema": 1, "source_sha256": SOURCE_SHA, "prepared_sha256": FileAccess.get_sha256(path), "triangles": 11962, "part_triangles": counts, "length_m": 3.8, "width_m": 1.9, "albedo_pixels": 512, "source_geometry_retained": true, "motion_acceptance": false}, "\t") + "\n")
	receipt.close()
	original.free()
	result.free()
	print("prepare_jeep_source: PASS (retained geometry, four wheel pivots; motion acceptance remains open)")
	quit(0)

func _fail(message: String) -> void:
	push_error("prepare_jeep_source: " + message)
	quit(1)
