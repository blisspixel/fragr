extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const Geometry = preload("res://scripts/model_geometry.gd")
const Surfaces = preload("res://art/models/sniper_surface_contract.gd")
const RAW_SHA256: String = "4a1d5a0e405410feb385514a6878cf0b9476c298fbcf3456d8674e4797998bcb"
const RAW_TRIANGLES: int = 11835
const SCALE: float = 1.18 / 1.90225195884705
const ORIGIN: Vector3 = Vector3(0.30, 0.085, 0.015)
const MUZZLE_RAW: Vector3 = Vector3(-0.95164, 0.090, 0.015)
const OPTIC_FRONT_RAW: Vector3 = Vector3(0.078, 0.176, 0.015)
const OPTIC_BACK_RAW: Vector3 = Vector3(0.432, 0.176, 0.015)
const BOLT_AXIS_RAW: Vector3 = Vector3(0.37, 0.100, 0.015)
const CAP_RECESS_METRES: float = 0.022
const LENS_RECESS_METRES: float = 0.006
const JOINT_CUT: AABB = AABB(Vector3(0.34, 0.070, -0.075), Vector3(0.205, 0.067, 0.150))
const HANDLE_CUT: AABB = AABB(Vector3(0.33, -0.006, -0.078), Vector3(0.095, 0.129, 0.053))
const OPTIC_FRONT_CUT: AABB = AABB(Vector3(0.055, 0.135, -0.027), Vector3(0.057, 0.090, 0.087))
const OPTIC_BACK_CUT: AABB = AABB(Vector3(0.416, 0.137, -0.025), Vector3(0.029, 0.088, 0.085))

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.get_sha256(args[0]) != RAW_SHA256:
		_fail("require exact reviewed raw source and output path")
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[0])
	var header: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	var copyright: String = str(header["asset"].get("copyright", ""))
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(args[0], state) != OK:
		_fail("cannot import raw source")
		return
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		_fail("raw source mesh count changed")
		return
	var imported: MeshInstance3D = meshes[0] as MeshInstance3D
	if imported.mesh.get_surface_count() != 1:
		_fail("raw source surface count changed")
		return
	var arrays: Array = imported.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.size() != RAW_TRIANGLES * 3:
		_fail("raw source triangle count changed")
		return
	for index: int in range(vertices.size()):
		vertices[index] = imported.global_transform * vertices[index]
		normals[index] = imported.global_transform.basis * normals[index]
	var finish: StandardMaterial3D = (imported.get_active_material(0) as StandardMaterial3D).duplicate()
	for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL]:
		var texture: Texture2D = finish.get_texture(slot)
		if texture == null:
			_fail("required source map missing")
			return
		var image: Image = texture.get_image()
		if image.is_compressed() and image.decompress() != OK:
			_fail("cannot decode embedded source map")
			return
		image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		if slot == BaseMaterial3D.TEXTURE_ALBEDO:
			_quiet_albedo(image)
		finish.set_texture(slot, ImageTexture.create_from_image(image))
	finish.metallic_texture = null
	finish.roughness_texture = null
	finish.metallic = 0.04
	finish.roughness = 0.96
	finish.normal_scale = 0.18
	finish.vertex_color_use_as_albedo = true
	finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var gun: Node3D = Node3D.new()
	gun.name = "Sniper"
	root.add_child(gun)
	var basis: Basis = Basis(Vector3.UP, -PI * 0.5)
	var counts: Dictionary[String, int] = {}
	var reworked: Dictionary[String, int] = {"MuzzleCap":0}
	var audit: Dictionary[String, int] = {"outside_joint_original_triangles":0, "fully_replaced_original_triangles":0, "clipped_original_triangles":0, "retained_clipped_fragment_triangles":0}
	var unchanged_points: PackedVector3Array = []
	var unchanged_uv: PackedVector2Array = []
	var surfaces: Dictionary[String, SurfaceTool] = {}
	for group: String in ["Body", "MuzzleCap"]:
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[group] = surface
	for face: int in range(0, indices.size(), 3):
		var center: Vector3 = Vector3.ZERO
		var normal: Vector3 = Vector3.ZERO
		var polygon: Array[Dictionary] = []
		for offset: int in range(3):
			var index: int = indices[face + offset]
			center += vertices[index] / 3.0
			normal += normals[index] / 3.0
			polygon.append({"point":vertices[index], "normal":normals[index], "uv":uv[index]})
		var group: String = _group(center, normal)
		if group == "Body":
			for corner_data: Dictionary in polygon:
				unchanged_points.append(corner_data["point"])
				unchanged_uv.append(corner_data["uv"])
		var polygons: Array[Array] = [polygon]
		if group == "Body":
			for cut: AABB in [JOINT_CUT, HANDLE_CUT, OPTIC_FRONT_CUT, OPTIC_BACK_CUT]:
				var remaining: Array[Array] = []
				for piece: Array in polygons:
					remaining.append_array(_subtract_box(piece, cut))
				polygons = remaining
		var untouched: bool = polygons.size() == 1 and polygons[0] == polygon
		if untouched:
			audit["outside_joint_original_triangles"] += 1
		elif polygons.is_empty():
			audit["fully_replaced_original_triangles"] += 1
		else:
			audit["clipped_original_triangles"] += 1
		var displacement: Vector3 = Vector3.ZERO
		var plane: Color = Color(1.08, 1.08, 1.04) if normal.y > 0.55 else Color(0.82, 0.84, 0.83)
		if group == "MuzzleCap":
			displacement.x = CAP_RECESS_METRES / SCALE
			plane = Color(0.10, 0.12, 0.12)
		if displacement != Vector3.ZERO:
			reworked[group] += 1
		for piece: Array in polygons:
			for corner: int in range(1, piece.size() - 1):
				var corners: Array[Dictionary] = [piece[0], piece[corner], piece[corner + 1]]
				var cross: Vector3 = (corners[1]["point"] - corners[0]["point"]).cross(corners[2]["point"] - corners[0]["point"])
				if not untouched and cross.length_squared() < 0.00000000000001:
					continue
				counts[group] = counts.get(group, 0) + 1
				if not untouched:
					audit["retained_clipped_fragment_triangles"] += 1
				for corner_data: Dictionary in corners:
					surfaces[group].set_color(plane)
					surfaces[group].set_normal(basis * corner_data["normal"])
					surfaces[group].set_uv(corner_data["uv"])
					surfaces[group].add_vertex(basis * (corner_data["point"] + displacement - ORIGIN) * SCALE)
	for group: String in surfaces:
		var holder: Node3D = Node3D.new()
		holder.name = group
		gun.add_child(holder)
		var surface: SurfaceTool = surfaces[group]
		if counts.get(group, 0) == 0:
			_fail("measured group disappeared: " + group)
			return
		surface.index()
		surface.generate_tangents()
		var piece: MeshInstance3D = MeshInstance3D.new()
		piece.name = group + "Mesh"
		piece.mesh = surface.commit()
		piece.material_override = finish
		holder.add_child(piece)
	var geometry: RefCounted = Geometry.new()
	var added: Dictionary[String, int] = {}
	_author_joint(geometry, gun, basis, added)
	for label: String in ["Muzzle", "OpticFront", "OpticBack"]:
		var point: Vector3 = {"Muzzle":MUZZLE_RAW, "OpticFront":OPTIC_FRONT_RAW, "OpticBack":OPTIC_BACK_RAW}[label]
		var marker: Marker3D = Marker3D.new()
		marker.name = label + "Axis"
		marker.position = basis * (point - ORIGIN) * SCALE
		gun.add_child(marker)
		if label == "OpticBack":
			marker.rotation.y = PI
		var inner: float = 0.0045 if label == "Muzzle" else 0.0172
		var outer: float = 0.012 if label == "Muzzle" else 0.022
		var depth: float = CAP_RECESS_METRES if label == "Muzzle" else LENS_RECESS_METRES + 0.0015
		for part: String in ["Lip", "Liner"]:
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.albedo_color = Color("343e3c") if part == "Lip" else Color("111919")
			material.roughness = 0.96
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			var profile: PackedVector2Array = PackedVector2Array([
				Vector2(-0.0008, inner), Vector2(-0.0008, outer), Vector2(0.0016, outer), Vector2(0.0016, inner)]) if part == "Lip" else PackedVector2Array([
				Vector2(0.0014, inner), Vector2(0.0014, inner + 0.001), Vector2(depth, inner + 0.001), Vector2(depth, inner)])
			var piece: MeshInstance3D = geometry.lathe(marker, label + part, profile, material, Vector3.ZERO, 24)
			added[piece.name] = piece.mesh.get_faces().size() / 3
		if label != "Muzzle":
			var shell: StandardMaterial3D = geometry.material(label + "HousingPaint", Color("343e3c"), 0.04, 0.96)
			var shell_depth: float = 0.024 if label == "OpticFront" else 0.012
			var housing: MeshInstance3D = geometry.lathe(marker, label + "Housing", PackedVector2Array([
				Vector2(0.0015, 0.018), Vector2(0.0015, 0.022), Vector2(shell_depth, 0.022), Vector2(shell_depth, 0.018)]), shell, Vector3.ZERO, 24)
			added[housing.name] = housing.mesh.get_faces().size() / 3
			var lens: StandardMaterial3D = StandardMaterial3D.new()
			lens.albedo_color = Color("293d3e")
			lens.roughness = 0.91
			lens.metallic = 0.02
			var disk: MeshInstance3D = geometry.cylinder(marker, label + "Lens", 0.0173, 0.001, lens, Vector3(0, 0, LENS_RECESS_METRES + 0.001), 24)
			added[disk.name] = disk.mesh.get_faces().size() / 3
	var output: GLTFDocument = GLTFDocument.new()
	output.image_format = "PNG"
	var export_state: GLTFState = GLTFState.new()
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK or output.append_from_scene(gun, export_state) != OK or output.write_to_filesystem(export_state, args[1]) != OK or not Metadata.clean(args[1], copyright):
		_fail("cannot export prepared source")
		return
	var retained_hashes: Array[String] = []
	for signature: String in Surfaces.signature_list(unchanged_points, unchanged_uv):
		retained_hashes.append(signature.sha256_text())
	var triangle_receipt: FileAccess = FileAccess.open(args[1] + ".retained.json", FileAccess.WRITE)
	if triangle_receipt == null:
		_fail("cannot write retained geometry/UV/winding multiset")
		return
	triangle_receipt.store_string(JSON.stringify({"schema":1,"raw_sha256":RAW_SHA256,"triangle_position_uv_winding_hashes":retained_hashes}, "\t") + "\n")
	triangle_receipt.close()
	var receipt: FileAccess = FileAccess.open(args[1] + ".json", FileAccess.WRITE)
	if receipt == null:
		_fail("cannot write preparation receipt")
		return
	receipt.store_string(JSON.stringify({"schema":1, "raw_sha256":RAW_SHA256,
		"prepared_sha256":FileAccess.get_sha256(args[1]), "prepare_sha256":FileAccess.get_sha256(get_script().resource_path),
		"raw_triangles":RAW_TRIANGLES, "retained_source_groups":counts, "joint_audit":audit, "recessed_raw_triangles":reworked,
		"retained_surface_contract":Surfaces.fingerprint(unchanged_points, unchanged_uv),
		"retained_triangle_receipt_sha256":FileAccess.get_sha256(args[1] + ".retained.json"),
		"surface_contract_sha256":FileAccess.get_sha256("res://art/models/sniper_surface_contract.gd"),
		"authored_triangles":added, "raw_connected_components":1, "metres_per_raw_unit":SCALE,
		"provisional_length_m":1.18, "embedded_map_pixels":1024,
		"axes_raw":{"muzzle":_vector(MUZZLE_RAW), "optic_front":_vector(OPTIC_FRONT_RAW), "optic_back":_vector(OPTIC_BACK_RAW), "bolt":_vector(BOLT_AXIS_RAW)},
		"repair_metres":{"muzzle_cap_recess":CAP_RECESS_METRES, "optic_lens_recess":LENS_RECESS_METRES},
		"material_policy":{"metallic":0.04,"roughness":0.96,"normal_scale":0.18,"albedo_cluster_pixels":4},
		"replacement_masks_raw":{"upper_joint":{"min":_vector(JOINT_CUT.position),"max":_vector(JOINT_CUT.end)},"handle":{"min":_vector(HANDLE_CUT.position),"max":_vector(HANDLE_CUT.end)},
			"optic_front":{"min":_vector(OPTIC_FRONT_CUT.position),"max":_vector(OPTIC_FRONT_CUT.end)},"optic_back":{"min":_vector(OPTIC_BACK_CUT.position),"max":_vector(OPTIC_BACK_CUT.end)}},
		"bolt_partition_accepted":false, "runtime_selected":false}, "\t") + "\n")
	receipt.close()
	original.free()
	gun.free()
	await process_frame
	print("prepare_sniper_source: PASS raw ", RAW_TRIANGLES, "; retained ", counts, "; joint audit ", audit, "; recessed ", reworked, "; authored ", added, "; source/partition acceptance open")
	quit()

func _group(center: Vector3, normal: Vector3) -> String:
	if center.x < -0.90 and center.y < 0.125 and normal.x < -0.65:
		return "MuzzleCap"
	return "Body"

func _subtract_box(polygon: Array, box: AABB) -> Array[Array]:
	var bounds: AABB = AABB(polygon[0]["point"], Vector3.ZERO)
	for corner: Dictionary in polygon:
		bounds = bounds.expand(corner["point"])
	if not box.intersects(bounds.grow(0.0000001)):
		return [polygon]
	var outside: Array[Array] = []
	var inside: Array = polygon
	for axis: int in range(3):
		for upper: bool in [false, true]:
			var boundary: float = box.end[axis] if upper else box.position[axis]
			var clipped: Array[Array] = _split_polygon(inside, axis, boundary, upper)
			if clipped[1].size() >= 3:
				outside.append(clipped[1])
			inside = clipped[0]
			if inside.size() < 3:
				return outside
	return outside

func _split_polygon(polygon: Array, axis: int, boundary: float, upper: bool) -> Array[Array]:
	var inside: Array[Dictionary] = []
	var outside: Array[Dictionary] = []
	for index: int in range(polygon.size()):
		var a: Dictionary = polygon[index]
		var b: Dictionary = polygon[(index + 1) % polygon.size()]
		var da: float = (boundary - a["point"][axis]) if upper else (a["point"][axis] - boundary)
		var db: float = (boundary - b["point"][axis]) if upper else (b["point"][axis] - boundary)
		(inside if da >= 0.0 else outside).append(a)
		if (da >= 0.0) != (db >= 0.0):
			var fraction: float = da / (da - db)
			var intersection: Dictionary = {"point":a["point"].lerp(b["point"], fraction),
				"normal":a["normal"].lerp(b["normal"], fraction).normalized(), "uv":a["uv"].lerp(b["uv"], fraction)}
			inside.append(intersection)
			outside.append(intersection)
	return [inside, outside]

func _author_joint(geometry: RefCounted, gun: Node3D, basis: Basis, added: Dictionary[String, int]) -> void:
	var steel: StandardMaterial3D = geometry.material("sniper_joint_charcoal", Color("454f4b"), 0.04, 0.96)
	var dark: StandardMaterial3D = geometry.material("sniper_joint_recess", Color("151e1e"), 0.02, 0.97)
	var edge: StandardMaterial3D = geometry.material("sniper_joint_plane", Color("63716a"), 0.05, 0.94)
	var bolt: Node3D = geometry.group(gun, "Bolt", basis * (BOLT_AXIS_RAW - ORIGIN) * SCALE)
	geometry.cylinder(bolt, "Shaft", 0.0095, 0.122, steel, Vector3(0, 0, 0.0435), 16)
	geometry.lathe(bolt, "Shroud", PackedVector2Array([
		Vector2(0.080, 0), Vector2(0.080, 0.0105), Vector2(0.084, 0.0118),
		Vector2(0.112, 0.0118), Vector2(0.118, 0.0105), Vector2(0.118, 0)]), steel, Vector3.ZERO, 16)
	geometry.cylinder(bolt, "LockingCollar", 0.0107, 0.013, edge, Vector3(0, 0, -0.0095), 12)
	geometry.cylinder(bolt, "RearPin", 0.006, 0.012, dark, Vector3(0, 0, 0.122), 12)
	geometry.rod(bolt, "HandleRoot", Vector3(0.009, 0, 0.058), Vector3(0.035, 0, 0.058), 0.0055, edge, 12)
	geometry.rod(bolt, "HandleElbow", Vector3(0.035, 0, 0.058), Vector3(0.045, -0.012, 0.060), 0.0055, steel, 12)
	geometry.rod(bolt, "HandleStem", Vector3(0.045, -0.012, 0.060), Vector3(0.046, -0.040, 0.062), 0.0055, steel, 12)
	geometry.hull(bolt, "HandleKnob", PackedVector3Array([
		Vector3(-0.011, 0.005, 0.005), Vector3(-0.007, 0.009, 0.010),
		Vector3(0.007, 0.009, 0.010), Vector3(0.011, 0.005, 0.005)]), dark, Vector3(0.046, -0.042, 0.062), 12)
	var chamber: Node3D = geometry.group(gun, "Chamber")
	for side: float in [-1.0, 1.0]:
		geometry.block(chamber, "GuideRail%d" % int(side), Vector3(0.006, 0.022, 0.132), steel, Vector3(side * 0.022, -0.008, 0.090))
		geometry.block(chamber, "ScopePier%d" % int(side), Vector3(0.009, 0.042, 0.032), steel, Vector3(side * 0.030, 0.008, 0.060))
	geometry.block(chamber, "RearScopeBridge", Vector3(0.069, 0.008, 0.032), steel, Vector3(0, 0.032, 0.060))
	var socket: Node3D = geometry.group(chamber, "FrontSocket", Vector3(0, bolt.position.y, 0.028))
	geometry.lathe(socket, "OpenGuide", PackedVector2Array([
		Vector2(-0.003, 0.012), Vector2(-0.003, 0.017), Vector2(0.003, 0.017), Vector2(0.003, 0.012)]), edge, Vector3.ZERO, 16)
	geometry.block(chamber, "SidePlateRepair", Vector3(0.004, 0.043, 0.064), steel, Vector3(0.029, -0.034, 0.050))
	for z: float in [0.027, 0.073]:
		var pin: MeshInstance3D = geometry.cylinder(chamber, "PlatePin%d" % int(z * 1000), 0.004, 0.006, dark, Vector3(0.032, -0.040, z), 8)
		pin.rotation.y = PI * 0.5
	for node: Node in gun.find_children("*", "MeshInstance3D", true, false):
		var piece: MeshInstance3D = node as MeshInstance3D
		if piece.get_parent() == bolt or chamber.is_ancestor_of(piece):
			added[str(piece.get_parent().name) + "/" + str(piece.name)] = piece.mesh.get_faces().size() / 3

func _quiet_albedo(image: Image) -> void:
	image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	for y: int in range(256):
		for x: int in range(256):
			var source: Color = image.get_pixel(x, y)
			var value: float = snappedf(clampf(source.get_luminance(), 0.0, 1.0), 1.0 / 8.0)
			var wood: bool = source.r > source.g * 1.20 and source.g > source.b * 1.04 and source.r - source.g > 0.035
			var finish: Color = Color("553b2d").lerp(Color("936d46"), value) if wood else Color("2d3737").lerp(Color("515b58"), value)
			finish.a = source.a
			image.set_pixel(x, y, finish)
	image.resize(1024, 1024, Image.INTERPOLATE_NEAREST)

func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _fail(message: String) -> void:
	push_error("prepare_sniper_source: " + message)
	quit(1)
