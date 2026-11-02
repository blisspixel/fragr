extends SceneTree

## Offline compact container. Original geometry buffers are copied, never exported.
const Rig = preload("res://../tools/splice_mechanical_rig.gd")
const GlbContainer = preload("res://../tools/tern_glb.gd")
const CANDIDATE_SHA: String = "f2191a008a44537b821b80da5bdf181958f69890bf6b9d388a51e1d75ebeb7a8"
const KEYS: int = 129
var _document: Dictionary
var _binary: PackedByteArray

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var ignored: String = ProjectSettings.globalize_path("res://../.agents/").simplify_path().to_lower() + "/"
	if args.size() != 3 or not args[0].is_absolute_path() or args[1] != CANDIDATE_SHA or not args[2].is_absolute_path() or not (args[2].simplify_path().to_lower() + "/").begins_with(ignored):
		_fail("pinned candidate and ignored absolute output required")
		return
	var out: String = args[2]
	if FileAccess.file_exists(out.path_join("splice-prepared.glb")) or DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("refuse existing prepared artifact")
		return
	var rig: Dictionary = Rig.build(args[0], CANDIDATE_SHA)
	if rig.is_empty():
		_fail("accepted original region source failed")
		return
	root.add_child(rig.root)
	var original: Dictionary = GlbContainer.read(Rig.RawAudit.SOURCE)
	var candidate: Dictionary = GlbContainer.read(args[0].path_join("labels.glb"))
	_document = candidate.document.duplicate(true)
	var maps: Array[Dictionary] = _compact_maps(original, candidate.binary, out)
	if maps.is_empty():
		rig.root.free()
		_fail("compact original maps failed")
		return
	var source_view_count: int = _document.bufferViews.size()
	var preserved: bool = true
	for index: int in source_view_count:
		if index in _image_view_ids(original.document):
			continue
		var a: Dictionary = candidate.document.bufferViews[index]
		var b: Dictionary = _document.bufferViews[index]
		preserved = preserved and candidate.binary.slice(int(a.get("byteOffset", 0)), int(a.get("byteOffset", 0)) + int(a.byteLength)) == _binary.slice(int(b.byteOffset), int(b.byteOffset) + int(b.byteLength))
	if not preserved:
		rig.root.free()
		_fail("non-image source buffer changed")
		return
	Rig.pose(rig, 0.0, false)
	_document.nodes = [{"name":"SplicePrepared", "scale":_vec(Vector3.ONE * float(rig.scale)), "translation":_vec(rig.root.position), "children":[4]}]
	for part: int in Rig.Regions.PARTS.size():
		var parent: int = Rig.PARENTS[part]
		var position: Vector3 = Vector3.ZERO if parent < 0 else rig.pivots[part] - rig.pivots[parent]
		_document.nodes.append({"name":Rig.Regions.PARTS[part], "translation":_vec(position), "children":[18 + part]})
	for part: int in Rig.Regions.PARTS.size():
		if Rig.PARENTS[part] >= 0:
			_document.nodes[1 + Rig.PARENTS[part]].children.append(1 + part)
		_document.nodes.append({"name":Rig.Regions.PARTS[part] + "_surface", "translation":_vec(-rig.pivots[part]), "mesh":part})
		_document.meshes[part].primitives[0].material = 0
	_document.scenes = [{"name":"SplicePreparedScene", "nodes":[0]}]
	_document.scene = 0
	_document.erase("animations")
	_document.erase("skins")
	var cap_material: Dictionary = {"name":"MechanicalJointCaps", "doubleSided":true, "pbrMetallicRoughness":{"baseColorFactor":[0.14117647,0.15294118,0.15686275,1.0],"metallicFactor":0.0,"roughnessFactor":1.0}}
	_document.materials.append(cap_material)
	var cap_rows: Array[Dictionary] = []
	for child: int in rig.closures:
		for cap: Dictionary in rig.closures[child]:
			var node: MeshInstance3D = cap.node
			var arrays: Array = node.mesh.surface_get_arrays(0)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var position_accessor: int = _vectors3(positions, true, 34962)
			var normal_accessor: int = _vectors3(normals, false, 34962)
			var mesh_index: int = _document.meshes.size()
			_document.meshes.append({"name":String(node.name),"primitives":[{"attributes":{"POSITION":position_accessor,"NORMAL":normal_accessor},"material":1,"mode":4}]})
			var node_index: int = _document.nodes.size()
			_document.nodes.append({"name":String(node.name),"translation":_vec(-rig.pivots[int(cap.owner)]),"mesh":mesh_index})
			_document.nodes[1 + int(cap.owner)].children.append(node_index)
			cap_rows.append({"node":String(node.name),"child":child,"owner":cap.owner,"triangles":positions.size() / 3})
	_document.animations = []
	var support: Array[Dictionary] = []
	for clip: String in ["calm", "walk"]:
		var duration: float = 4.0 if clip == "calm" else 2.0
		var times: PackedFloat32Array = []
		var roots: PackedVector3Array = []
		var rotations: Array[PackedFloat32Array] = []
		for _part: String in Rig.Regions.PARTS:
			rotations.append(PackedFloat32Array())
		for sample: int in KEYS:
			var phase: float = float(sample) / float(KEYS - 1)
			Rig.pose(rig, phase, clip == "walk")
			times.append(phase * duration)
			roots.append(rig.root.position)
			for part: int in Rig.Regions.PARTS.size():
				var quaternion: Quaternion = rig.parts[part].quaternion
				rotations[part].append_array(PackedFloat32Array([quaternion.x,quaternion.y,quaternion.z,quaternion.w]))
			support.append({"clip":clip,"phase":phase,"measured_root_y_m":rig.root.position.y,"original_sole_y_m":Rig.measure(rig).original_floor_y})
		var time_accessor: int = _floats(times, "SCALAR", KEYS, [0.0], [duration])
		var animation: Dictionary = {"name":clip,"samplers":[],"channels":[]}
		var translation_accessor: int = _vectors3(roots, false)
		animation.samplers.append({"input":time_accessor,"output":translation_accessor,"interpolation":"LINEAR"})
		animation.channels.append({"sampler":0,"target":{"node":0,"path":"translation"}})
		for part: int in Rig.Regions.PARTS.size():
			var accessor: int = _floats(rotations[part], "VEC4", KEYS)
			animation.samplers.append({"input":time_accessor,"output":accessor,"interpolation":"LINEAR"})
			animation.channels.append({"sampler":animation.samplers.size() - 1,"target":{"node":1 + part,"path":"rotation"}})
		_document.animations.append(animation)
	Rig.pose(rig, 0.0, false)
	var limbs: Array[Dictionary] = []
	for pair: Vector2i in [Vector2i(4,5),Vector2i(5,6),Vector2i(7,8),Vector2i(8,9),Vector2i(10,11),Vector2i(11,12),Vector2i(13,14),Vector2i(14,15)]:
		limbs.append({"from":Rig.Regions.PARTS[pair.x],"to":Rig.Regions.PARTS[pair.y],"joint_distance_m":rig.pivots[pair.x].distance_to(rig.pivots[pair.y]) * float(rig.scale)})
	_document.buffers = [{"byteLength":_binary.size()}]
	_document.asset.erase("generator")
	var path: String = out.path_join("splice-prepared.glb")
	if not GlbContainer.write(path, _document, _binary):
		rig.root.free()
		_fail("prepared container write failed")
		return
	var prepared: Dictionary = GlbContainer.read(path)
	var projection: Dictionary = prepared.duplicate(true)
	projection.document.meshes = prepared.document.meshes.slice(0, Rig.Regions.PARTS.size())
	projection.document.nodes = candidate.document.nodes.duplicate(true)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0].path_join("partition.json")))
	var faces: Array[PackedInt32Array] = []
	for row: Dictionary in manifest.rows:
		faces.append(PackedInt32Array(row.original_triangle_ids))
	var coverage: bool = Rig.Regions.verify_coverage(original, projection, faces)
	var legal: bool = prepared.document.asset.get("copyright", "") == original.document.asset.get("copyright", "") and not prepared.document.asset.has("generator")
	var loaded: Node3D = Rig._load(path)
	if not coverage or not legal or loaded == null:
		if loaded != null:
			loaded.free()
		rig.root.free()
		_fail("exported source coverage, legal metadata or native reload failed")
		return
	loaded.free()
	var report: Dictionary = {"schema":1,"scope":"ignored compact exported candidate; native motion and renderer review pending", "source_sha256":Rig.RawAudit.SHA,"regions_sha256":CANDIDATE_SHA,"prepared_sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size(),"original_triangles":rig.original_triangles,"added_cap_triangles":rig.added_closure_triangles,"non_image_payloads_unchanged":preserved,"exact_original_surface_coverage":coverage,"legal_metadata_preserved":legal,"native_reload":true,"maps":maps,"uniform_scale":rig.scale,"clips":[{"name":"calm","seconds":4.0,"keys":KEYS},{"name":"walk","seconds":2.0,"keys":KEYS}],"limb_joint_distances":limbs,"stored_attachment":"Complete original rack/tool surfaces share right upper-leg transform; independent tools and grip sockets are not established.","caps":cap_rows,"support_samples":support,"runtime_selected":false,"new_credits":0}
	var file: FileAccess = FileAccess.open(out.path_join("preparation.json"), FileAccess.WRITE)
	if file == null:
		rig.root.free()
		_fail("preparation receipt unavailable")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	rig.root.free()
	await process_frame
	print("prepare_splice_source: PASS (exact original buffers, compact maps, measured hierarchy/caps and clips; candidate only)")
	quit(0)

func _compact_maps(original: Dictionary, source_binary: PackedByteArray, out: String) -> Array[Dictionary]:
	var material: Dictionary = original.document.materials[0].duplicate(true)
	var roughness_texture: int = int(material.pbrMetallicRoughness.metallicRoughnessTexture.index)
	var roughness_image: int = int(original.document.textures[roughness_texture].source)
	var replacements: Dictionary[int, PackedByteArray] = {}
	var rows: Array[Dictionary] = []
	for index: int in _document.images.size():
		var image_spec: Dictionary = _document.images[index]
		var view_index: int = int(image_spec.bufferView)
		var view: Dictionary = _document.bufferViews[view_index]
		var encoded: PackedByteArray = source_binary.slice(int(view.get("byteOffset",0)),int(view.get("byteOffset",0)) + int(view.byteLength))
		var image: Image = Image.new()
		var error: Error = image.load_png_from_buffer(encoded) if image_spec.mimeType == "image/png" else image.load_jpg_from_buffer(encoded)
		if error != OK or image.get_size() != (Vector2i(2048,2048) if index == roughness_image else Vector2i(4096,4096)):
			return []
		var source_size: Vector2i = image.get_size()
		image.resize(1024,1024,Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		if index == roughness_image:
			for y: int in 1024:
				for x: int in 1024:
					var color: Color = image.get_pixel(x,y)
					color.g = maxf(color.g,0.88)
					image.set_pixel(x,y,color)
		var path: String = out.path_join("map_%d.png" % index)
		if image.save_png(path) != OK:
			return []
		replacements[view_index] = image.save_png_to_buffer()
		image_spec.mimeType = "image/png"
		rows.append({"image":index,"name":image_spec.get("name",""),"source_size":[source_size.x,source_size.y],"prepared_size":[1024,1024],"sha256":FileAccess.get_sha256(path),"roughness_floor_applied":index == roughness_image})
	_binary = []
	for index: int in _document.bufferViews.size():
		var view: Dictionary = _document.bufferViews[index]
		var start: int = int(view.get("byteOffset",0))
		var length: int = int(view.byteLength)
		if start < 0 or length <= 0 or start + length > source_binary.size() or int(view.buffer) != 0:
			return []
		var payload: PackedByteArray = replacements[index] if replacements.has(index) else source_binary.slice(start,start + length)
		while _binary.size() % 4 != 0:
			_binary.append(0)
		view.byteOffset = _binary.size()
		view.byteLength = payload.size()
		_binary.append_array(payload)
	material.pbrMetallicRoughness.metallicFactor = 0.08
	material.pbrMetallicRoughness.roughnessFactor = 1.0
	_document.materials = [material]
	for sampler: Dictionary in _document.get("samplers",[]):
		sampler.magFilter = 9728
		sampler.minFilter = 9984
	return rows

func _image_view_ids(document: Dictionary) -> PackedInt32Array:
	var ids: PackedInt32Array = []
	for image: Dictionary in document.images:
		ids.append(int(image.bufferView))
	return ids

func _vectors3(points: PackedVector3Array, bounds: bool, target: int = 0) -> int:
	var values: PackedFloat32Array = []
	var low: Vector3 = Vector3(INF,INF,INF)
	var high: Vector3 = -low
	for point: Vector3 in points:
		values.append_array(PackedFloat32Array([point.x,point.y,point.z]))
		low = low.min(point)
		high = high.max(point)
	return _floats(values,"VEC3",points.size(),_vec(low) if bounds else [],_vec(high) if bounds else [],target)

func _floats(values: PackedFloat32Array, type: String, count: int, low: Array = [], high: Array = [], target: int = 0) -> int:
	while _binary.size() % 4 != 0:
		_binary.append(0)
	var offset: int = _binary.size()
	var payload: PackedByteArray = values.to_byte_array()
	_binary.append_array(payload)
	var view: Dictionary = {"buffer":0,"byteOffset":offset,"byteLength":payload.size()}
	if target != 0:
		view.target = target
	var accessor: Dictionary = {"bufferView":_document.bufferViews.size(),"componentType":5126,"count":count,"type":type}
	_document.bufferViews.append(view)
	if not low.is_empty():
		accessor.min = low
		accessor.max = high
	_document.accessors.append(accessor)
	return _document.accessors.size() - 1

func _vec(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _fail(reason: String) -> void:
	push_error("prepare_splice_source: " + reason)
	quit(1)
