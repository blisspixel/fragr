extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const SOURCE_SHA256: String = "6f7078f594262c23de7d599868285ac7e62046a100dace5c934a53c0f1a96f22"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.get_sha256(args[0]) != SOURCE_SHA256:
		_fail("require reviewed topology GLB and output path")
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[0])
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	var copyright: String = str(parsed["asset"].get("copyright", ""))
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(args[0], state) != OK:
		_fail("cannot import reviewed source")
		return
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		_fail("reviewed source no longer has one mesh")
		return
	var imported: MeshInstance3D = meshes[0] as MeshInstance3D
	if imported.mesh.get_surface_count() != 1:
		_fail("reviewed source surface changed")
		return
	var arrays: Array = imported.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var parents: PackedInt32Array = _islands(vertices, indices)
	var counts: Dictionary[int, int] = {}
	var bounds: Dictionary[int, AABB] = {}
	for face: int in range(0, indices.size(), 3):
		var key: int = _root(parents, indices[face])
		counts[key] = counts.get(key, 0) + 1
		if not bounds.has(key):
			bounds[key] = AABB(vertices[indices[face]], Vector3.ZERO)
		for offset: int in range(3):
			bounds[key] = bounds[key].expand(vertices[indices[face + offset]])
	var pump_id: int = -1
	for key: int in counts:
		if counts[key] == 1496 and bounds[key].position.x > 0.10 and bounds[key].end.x < 0.45 \
			and bounds[key].size.y < 0.05 and bounds[key].size.z > 0.05:
			if pump_id >= 0:
				_fail("ambiguous independent fore-end")
				return
			pump_id = key
	if pump_id < 0:
		_fail("reviewed independent fore-end missing")
		return
	var material: StandardMaterial3D = (imported.get_active_material(0) as StandardMaterial3D).duplicate()
	var cache: Dictionary[int, ImageTexture] = {}
	for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS]:
		var texture: Texture2D = material.get_texture(slot)
		if texture == null:
			continue
		var key: int = texture.get_instance_id()
		if not cache.has(key):
			var image: Image = texture.get_image()
			if image.is_compressed() and image.decompress() != OK:
				_fail("cannot decode source maps")
				return
			image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
			cache[key] = ImageTexture.create_from_image(image)
		material.set_texture(slot, cache[key])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var gun: Node3D = Node3D.new()
	gun.name = "Shotgun"
	root.add_child(gun)
	var body: MeshInstance3D = _piece(arrays, parents, pump_id, false)
	body.name = "Body"
	body.rotation.y = PI * 0.5
	body.position = Vector3(0, -0.07, -0.15)
	body.material_override = material
	gun.add_child(body)
	var center: Vector3 = bounds[pump_id].get_center()
	var pump: Node3D = Node3D.new()
	pump.name = "Pump"
	pump.position = Basis(Vector3.UP, PI * 0.5) * center + body.position
	gun.add_child(pump)
	var fore_end: MeshInstance3D = _piece(arrays, parents, pump_id, true)
	fore_end.name = "ForeEnd"
	fore_end.rotation.y = PI * 0.5
	fore_end.position = -(Basis(Vector3.UP, PI * 0.5) * center)
	fore_end.material_override = material
	pump.add_child(fore_end)
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.048, -0.65)
	gun.add_child(muzzle)
	var output: GLTFDocument = GLTFDocument.new()
	output.image_format = "PNG"
	var export_state: GLTFState = GLTFState.new()
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK \
		or output.append_from_scene(gun, export_state) != OK \
		or output.write_to_filesystem(export_state, args[1]) != OK \
		or not Metadata.clean(args[1], copyright):
		_fail("cannot export prepared source")
		return
	original.free()
	gun.free()
	await process_frame
	print("prepare_shotgun_source: PASS (", counts.size(), " islands, 1496-triangle independent pump, embedded 1K maps)")
	quit()

func _piece(arrays: Array, parents: PackedInt32Array, pump_id: int, pump: bool) -> MeshInstance3D:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: int in range(0, indices.size(), 3):
		if (_root(parents, indices[face]) == pump_id) != pump:
			continue
		for offset: int in range(3):
			var index: int = indices[face + offset]
			surface.set_normal(normals[index])
			surface.set_uv(uv[index])
			if tangents.size() == vertices.size() * 4:
				surface.set_tangent(Plane(Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2]), tangents[index * 4 + 3]))
			surface.add_vertex(vertices[index])
	surface.index()
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = surface.commit()
	return instance

func _islands(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedInt32Array:
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
	return parents

func _root(parents: PackedInt32Array, index: int) -> int:
	var result: int = index
	while parents[result] != result:
		result = parents[result]
	return result

func _fail(message: String) -> void:
	push_error("prepare_shotgun_source: " + message)
	quit(1)
