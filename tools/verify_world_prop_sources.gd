extends SceneTree

const SPECS: Array[Dictionary] = [
	{"id":"air-scrubber","name":"AirScrubber","sha":"c6e435c6bf06f2dde238f5f3ee7fc20dc389fc6fab9319e5504a6ce45fe72997","triangles":11910,"axis":1,"metres":1.65},
	{"id":"water-pump","name":"WaterPump","sha":"631dabc2bb87b34a386e52434dfc0e46cdda079c323b789944d84302420d7e30","triangles":11880,"axis":0,"metres":1.20},
	{"id":"community-radio","name":"CommunityRadio","sha":"aac13efc917e53540911bba5cefa9fedd6f08086eb181ea579d37e44d78b2412","triangles":11646,"axis":0,"metres":0.38}]
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated",true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3:
		_check(false,"require raw/prepared directories and receipt")
		quit(1)
		return
	var rows: Array[Dictionary] = []
	for spec: Dictionary in SPECS:
		var raw_path: String = args[0].path_join(spec["id"] + "-stylized-v1-ultra-0.glb")
		var prepared_path: String = args[1].path_join(spec["id"] + ".glb")
		_check(FileAccess.get_sha256(raw_path) == spec["sha"],"raw fingerprint")
		var raw: Node3D = _load(raw_path)
		var prepared: Node3D = _load(prepared_path)
		if raw == null or prepared == null:
			if raw != null: raw.free()
			if prepared != null: prepared.free()
			continue
		var source_meshes: Array[Node] = raw.find_children("*","MeshInstance3D",true,false)
		var result_meshes: Array[Node] = prepared.find_children("*","MeshInstance3D",true,false)
		var pump: bool = spec["id"] == "water-pump"
		if source_meshes.size() != 1 or result_meshes.size() != (5 if pump else 1):
			_check(false,"actual fixed body and optional four mounting pads")
			raw.free()
			prepared.free()
			continue
		var original: MeshInstance3D = source_meshes[0] as MeshInstance3D
		var result: MeshInstance3D = prepared.find_child("Body",true,false) as MeshInstance3D
		if result == null:
			_check(false,"named retained Body")
			raw.free()
			prepared.free()
			continue
		var a: Array = original.mesh.surface_get_arrays(0)
		var b: Array = result.mesh.surface_get_arrays(0)
		var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bv: PackedVector3Array = _vertices(result)
		var au: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var bu: PackedVector2Array = b[Mesh.ARRAY_TEX_UV]
		var ai: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var bi: PackedInt32Array = b[Mesh.ARRAY_INDEX]
		_check(ai.size() == spec["triangles"] * 3 and bi.size() == ai.size(),"actual retained triangle count")
		var raw_bounds: AABB = original.mesh.get_aabb()
		var origin: Vector3 = Vector3(raw_bounds.get_center().x,raw_bounds.position.y,raw_bounds.get_center().z)
		var scale: float = float(spec["metres"]) / raw_bounds.size[int(spec["axis"])]
		var offset: Vector3 = Vector3(0.0,0.012,0.0) if pump else Vector3.ZERO
		var rotated: PackedVector3Array = PackedVector3Array()
		for vertex: Vector3 in av:
			rotated.append(Basis(Vector3.UP,PI) * (vertex - origin) * scale + offset)
		var expected: Dictionary = _triangles(rotated,au,ai)
		var actual: Dictionary = _triangles(bv,bu,bi)
		_check(actual == expected,"independent export/reimport retains actual positions/UV/winding")
		var shifted: PackedVector2Array = bu.duplicate()
		for index: int in range(shifted.size()): shifted[index] += Vector2(0.01,0.0)
		_check(_triangles(bv,shifted,bi) != expected,"negative UV displacement rejected")
		var reversed: PackedInt32Array = bi.duplicate()
		for index: int in range(0,reversed.size(),3):
			var value: int = reversed[index + 1]
			reversed[index + 1] = reversed[index + 2]
			reversed[index + 2] = value
		_check(_triangles(bv,bu,reversed) != expected,"negative reversed winding rejected")
		var material: StandardMaterial3D = result.get_active_material(0) as StandardMaterial3D
		_check(material != null and material.albedo_texture != null and material.normal_texture != null and material.albedo_texture.get_width() == 1024 and material.albedo_texture.get_height() == 1024 and material.normal_texture.get_width() == 1024 and material.normal_texture.get_height() == 1024 and material.metallic_texture == null and material.roughness_texture == null,"actual compact paint and normal without ORM maps")
		_check(material != null and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,"actual imported nearest filtering")
		var all_vertices: PackedVector3Array = PackedVector3Array()
		var authored: int = 0
		var supports: Array[Dictionary] = []
		for node: Node in result_meshes:
			var mesh: MeshInstance3D = node as MeshInstance3D
			var vertices: PackedVector3Array = _vertices(mesh)
			all_vertices.append_array(vertices)
			if mesh == result: continue
			var arrays: Array = mesh.mesh.surface_get_arrays(0)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			_check(indices.size() == 36,"actual twelve-triangle mounting pad")
			authored += indices.size() / 3
			var bounds: AABB = _bounds(vertices)
			var joined: bool = _supported(bounds,bv,bi)
			_check(joined,"actual floor pad joins retained source underside")
			var detached: AABB = bounds
			detached.position.x += 10.0
			_check(not _supported(detached,bv,bi),"negative detached support rejected")
			var raised: AABB = bounds
			raised.position.y += 0.08
			_check(not _supported(raised,bv,bi),"negative hovering support rejected")
			supports.append({"name":mesh.name,"bounds_min_m":[bounds.position.x,bounds.position.y,bounds.position.z],"size_m":[bounds.size.x,bounds.size.y,bounds.size.z],"joined_source":joined})
		_check(authored == (48 if pump else 0),"actual authored mounting geometry count")
		var result_bounds: AABB = _bounds(all_vertices)
		_check(absf(result_bounds.position.y) < 0.00001 and absf(result_bounds.size[int(spec["axis"])] - float(spec["metres"])) < 0.00001,"actual provisional dimension and floor pivot")
		var floor_quadrants: Dictionary = {}
		for vertex: Vector3 in all_vertices:
			if vertex.y <= 0.002:
				floor_quadrants[Vector2i(1 if vertex.x >= 0.0 else -1,1 if vertex.z >= 0.0 else -1)] = true
		_check(floor_quadrants.size() == 4,"real bottom surfaces reach four support quadrants")
		rows.append({"id":spec["id"],"raw_sha256":spec["sha"],"prepared_sha256":FileAccess.get_sha256(prepared_path),"retained_triangles":bi.size()/3,"authored_triangles":authored,"orientation_preserving_multiset_matches":expected==actual,"position_and_uv_quantization":0.00001,"floor_support_quadrants":floor_quadrants.size(),"actual_bounds_m":[result_bounds.size.x,result_bounds.size.y,result_bounds.size.z],"supports":supports,"provisional_scale":true,"runtime_selected":false})
		raw.free()
		prepared.free()
	var file: FileAccess = FileAccess.open(args[2],FileAccess.WRITE)
	_check(file != null,"proof receipt writable")
	if file != null:
		file.store_string(JSON.stringify({"schema":1,"models":rows,"failures":_failures},"\t")+"\n")
		file.close()
	await process_frame
	if _failures == 0:
		print("verify_world_prop_sources: PASS (actual retained UV/winding, compact maps, dimensions, four grounded supports and detached/hovering negative controls)")
	quit(0 if _failures == 0 else 1)

func _supported(bounds: AABB,vertices: PackedVector3Array,indices: PackedInt32Array) -> bool:
	if absf(bounds.position.y) > 0.00001 or absf(bounds.size.x - 0.10) > 0.00001 or absf(bounds.size.z - 0.06) > 0.00001:
		return false
	var point: Vector3 = bounds.get_center()
	var hit: Vector3 = _first_hit(vertices,indices,Vector3(point.x,-0.01,point.z),Vector3(point.x,0.08,point.z))
	if not hit.is_finite() or hit.y < 0.008 or hit.y > 0.06:
		return false
	return absf(bounds.end.y - hit.y - 0.003) < 0.00001

func _first_hit(vertices: PackedVector3Array,indices: PackedInt32Array,start: Vector3,end: Vector3) -> Vector3:
	var best: Vector3 = Vector3(INF,INF,INF)
	var distance: float = INF
	for slot: int in range(0,indices.size(),3):
		var value: Variant = Geometry3D.segment_intersects_triangle(start,end,vertices[indices[slot]],vertices[indices[slot+1]],vertices[indices[slot+2]])
		if value != null:
			var hit: Vector3 = value
			if start.distance_to(hit) < distance:
				best = hit
				distance = start.distance_to(hit)
	return best

func _vertices(mesh: MeshInstance3D) -> PackedVector3Array:
	_check(mesh.mesh.get_surface_count() == 1,"one surface per physical part")
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var result: PackedVector3Array = PackedVector3Array()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices: result.append(mesh.global_transform * vertex)
	return result

func _bounds(vertices: PackedVector3Array) -> AABB:
	var result: AABB = AABB(vertices[0],Vector3.ZERO)
	for vertex: Vector3 in vertices: result = result.expand(vertex)
	return result

func _load(path: String) -> Node3D:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path,state) != OK:
		_check(false,"model import")
		return null
	var model: Node3D = document.generate_scene(state)
	root.add_child(model)
	var meshes: Array[Node] = model.find_children("*","MeshInstance3D",true,false)
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null or mesh.mesh.get_surface_count() != 1 or mesh.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
			_check(false,"one triangle surface per physical part")
			model.free()
			return null
	return model

func _triangles(vertices: PackedVector3Array,uv: PackedVector2Array,indices: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {}
	for slot: int in range(0,indices.size(),3):
		var corners: PackedStringArray = PackedStringArray()
		for offset: int in range(3):
			var index: int = indices[slot+offset]
			var p: Vector3 = vertices[index]
			var t: Vector2 = uv[index]
			corners.append("%d,%d,%d,%d,%d" % [roundi(p.x*100000.0),roundi(p.y*100000.0),roundi(p.z*100000.0),roundi(t.x*100000.0),roundi(t.y*100000.0)])
		var rotations: PackedStringArray = PackedStringArray([corners[0]+";"+corners[1]+";"+corners[2],corners[1]+";"+corners[2]+";"+corners[0],corners[2]+";"+corners[0]+";"+corners[1]])
		rotations.sort()
		var key: String = rotations[0]
		result[key] = int(result.get(key,0))+1
	return result

func _check(condition: bool,message: String) -> void:
	if not condition:
		_failures += 1
		push_error("verify_world_prop_sources: "+message)
