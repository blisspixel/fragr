extends SceneTree

## Prepares the reviewed Meshy jetpack candidate for JetpackRig.MODEL_PATH:
## a compact pixel-painted pack at wearer scale, its harness facing the
## wearer (+X) and two named nozzle anchors for the flames. Makes no service
## request. Usage, from the repository root:
##   godot --headless --path client --script ../tools/prepare_jetpack_source.gd -- \
##     <raw jetpack-20261023-v1-0.glb> client/assets/models/jetpack.glb
const Metadata = preload("res://art/models/glb_metadata.gd")
const SOURCE_SHA: String = "366a824428995cc4aed42682590b134850ec27a8635767b324eb817844667dd1"
const SOURCE_VERTICES: int = 19113
const SOURCE_TRIANGLES: int = 10330
## Pack height on a 1.8 m fighter, matching the placeholder frame.
const HEIGHT: float = 0.62
## The nozzle mouths sit here in the rig's pack space; JetpackRig lights the
## flames from this height.
const NOZZLE_Y: float = -0.32
## Source yaw that turns the harness side toward the wearer's +X.
const SOURCE_YAW: float = -PI * 0.5
const PAINT_PIXELS: int = 128
const MAP_PIXELS: int = 512

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.get_sha256(args[0]) != SOURCE_SHA:
		_fail("require the exact reviewed jetpack source and an output path")
		return
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK:
		_fail("output needs a writable parent")
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[0])
	var metadata: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	if not metadata is Dictionary or not metadata.get("asset") is Dictionary:
		_fail("invalid source metadata")
		return
	var copyright: String = str(metadata["asset"].get("copyright", ""))
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(args[0], state) != OK:
		_fail("cannot import the reviewed source")
		return
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		original.free()
		_fail("one source mesh required")
		return
	var source: MeshInstance3D = meshes[0] as MeshInstance3D
	var arrays: Array = source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if source.mesh.get_surface_count() != 1 or vertices.size() != SOURCE_VERTICES or indices.size() != SOURCE_TRIANGLES * 3 \
		or normals.size() != vertices.size() or uv.size() != vertices.size():
		original.free()
		_fail("measured source arrays changed")
		return
	var material: StandardMaterial3D = source.get_active_material(0) as StandardMaterial3D
	if material == null or material.albedo_texture == null or material.normal_texture == null:
		original.free()
		_fail("embedded paint and normal maps required")
		return
	var bounds: AABB = source.mesh.get_aabb()
	var scale: float = HEIGHT / bounds.size.y
	var pivot: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var basis: Basis = Basis(Vector3.UP, SOURCE_YAW)
	var lift: Vector3 = Vector3(0.0, NOZZLE_Y - 0.02, 0.0)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed: PackedVector3Array = PackedVector3Array()
	placed.resize(vertices.size())
	for index: int in range(vertices.size()):
		if not vertices[index].is_finite() or not normals[index].is_finite() or not uv[index].is_finite():
			original.free()
			_fail("invalid source attributes")
			return
		placed[index] = basis * (vertices[index] - pivot) * scale + lift
	for index: int in indices:
		surface.set_normal(basis * normals[index])
		surface.set_uv(uv[index])
		surface.add_vertex(placed[index])
	surface.index()
	surface.generate_tangents()
	# The nozzle mouths: the lowest band of geometry, split either side of the
	# pack's centre line.
	var floor_band: float = placed[0].y
	for point: Vector3 in placed:
		floor_band = minf(floor_band, point.y)
	floor_band += HEIGHT * 0.06
	var sums: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var counts: Array[int] = [0, 0]
	for point: Vector3 in placed:
		if point.y <= floor_band:
			var side: int = 0 if point.z < 0.0 else 1
			sums[side] += point
			counts[side] += 1
	if counts[0] < 8 or counts[1] < 8:
		original.free()
		_fail("two nozzle mouths required at the base")
		return
	var paint: Image = material.albedo_texture.get_image()
	var normal: Image = material.normal_texture.get_image()
	if (paint.is_compressed() and paint.decompress() != OK) or (normal.is_compressed() and normal.decompress() != OK):
		original.free()
		_fail("cannot decode maps")
		return
	_paint(paint)
	normal.resize(MAP_PIXELS, MAP_PIXELS, Image.INTERPOLATE_LANCZOS)
	var finish: StandardMaterial3D = StandardMaterial3D.new()
	finish.albedo_texture = ImageTexture.create_from_image(paint)
	finish.normal_enabled = true
	finish.normal_texture = ImageTexture.create_from_image(normal)
	finish.normal_scale = 0.2
	finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	finish.metallic = 0.1
	finish.roughness = 0.9
	var result: Node3D = Node3D.new()
	result.name = "Jetpack"
	root.add_child(result)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = surface.commit()
	body.material_override = finish
	result.add_child(body)
	var anchors: Array = []
	for side: int in range(2):
		var anchor: Node3D = Node3D.new()
		anchor.name = ["NozzleLeft", "NozzleRight"][side]
		var mouth: Vector3 = sums[side] / float(counts[side])
		anchor.position = Vector3(mouth.x, NOZZLE_Y, mouth.z)
		result.add_child(anchor)
		anchors.append([anchor.position.x, anchor.position.y, anchor.position.z])
	var exporter: GLTFDocument = GLTFDocument.new()
	exporter.image_format = "PNG"
	var exported: GLTFState = GLTFState.new()
	var output: String = args[1]
	var written: bool = exporter.append_from_scene(result, exported) == OK and exporter.write_to_filesystem(exported, output) == OK \
		and Metadata.clean(output, copyright)
	var extent: AABB = body.mesh.get_aabb()
	original.free()
	result.free()
	if not written:
		_fail("cannot export the prepared pack")
		return
	var receipt: FileAccess = FileAccess.open(output + ".json", FileAccess.WRITE)
	if receipt == null:
		_fail("cannot write the preparation receipt")
		return
	receipt.store_string(JSON.stringify({"schema": 1, "id": "jetpack", "raw_sha256": SOURCE_SHA, "prepared_sha256": FileAccess.get_sha256(output),
		"raw_triangles": SOURCE_TRIANGLES, "retained_triangles": SOURCE_TRIANGLES, "height_m": HEIGHT, "metres_per_source_unit": scale,
		"source_yaw": SOURCE_YAW, "bounds_m": {"position": [extent.position.x, extent.position.y, extent.position.z], "size": [extent.size.x, extent.size.y, extent.size.z]},
		"nozzles": anchors, "paint_pixels": PAINT_PIXELS, "map_pixels": MAP_PIXELS}, "\t") + "\n")
	receipt.close()
	print("prepare_jetpack_source: PASS (%d triangles, %.2f m tall)" % [SOURCE_TRIANGLES, extent.size.y])
	quit(0)

## Coarse painted clusters: the generated paint is averaged down to a small
## grid, its value stepped and its saturation eased, then blown back up with
## nearest sampling so the pack reads as the same pixel surface as the world.
func _paint(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	image.resize(PAINT_PIXELS, PAINT_PIXELS, Image.INTERPOLATE_LANCZOS)
	for y: int in range(PAINT_PIXELS):
		for x: int in range(PAINT_PIXELS):
			var colour: Color = image.get_pixel(x, y)
			var value: float = clampf(snappedf(colour.v, 1.0 / 6.0), 0.12, 0.92)
			image.set_pixel(x, y, Color.from_hsv(colour.h, colour.s * 0.82, value, 1.0))
	image.resize(MAP_PIXELS, MAP_PIXELS, Image.INTERPOLATE_NEAREST)

func _fail(message: String) -> void:
	push_error("prepare_jetpack_source: " + message)
	quit(1)
