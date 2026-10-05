extends SceneTree

const Source = preload("res://art/models/sniper_source.gd")
const Surfaces = preload("res://art/models/sniper_surface_contract.gd")
const Art = preload("res://scripts/weapon_art.gd")
const SELECTED: String = "res://assets/weapons/sniper-source-20261004/"
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_sniper_source: " + message)

func _run() -> void:
	_check_selection()
	var source: RefCounted = Source.new()
	var gun: Node3D = source.build(true)
	root.add_child(gun)
	var counts: Dictionary[String, int] = {"Body":9514, "MuzzleCap":38}
	var total: int = 0
	var bounds: AABB
	var first: bool = true
	for label: String in counts:
		var mesh: MeshInstance3D = gun.get_node(label + "/" + label + "Mesh") as MeshInstance3D
		var count: int = mesh.mesh.get_faces().size() / 3
		total += count
		_check(count == counts[label], "raw " + label + " face count remains accounted for")
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		var finish: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
		_check(finish.albedo_texture.get_width() == 1024 and finish.normal_texture.get_width() == 1024
			and finish.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
			and finish.vertex_color_use_as_albedo, "actual source retains bounded nearest 1K maps and broad face paint")
		_check(finish.roughness > 0.90 and finish.metallic < 0.10 and finish.normal_scale < 0.20
			and finish.roughness_texture == null and finish.metallic_texture == null,
			"actual quiet finish removes reflective source maps")
		_check(finish.albedo_texture.resource_path.begins_with(Source.SOURCE + "::")
			and finish.normal_texture.resource_path.begins_with(Source.SOURCE + "::"),
			"loaded source maps stay embedded without sidecar dependence")
	_check(total == 9552, "retained original and clipped fragment triangles remain fully accounted for")
	var muzzle: Node3D = gun.get_node("MuzzleAxis") as Node3D
	_check(absf(bounds.end.z - muzzle.position.z - 1.18) < 0.0001 and bounds.size.x < 0.10 and bounds.size.y > 0.27 and bounds.size.y < 0.30,
		"actual muzzle registration to retained butt preserves provisional 1.18 metre proportions")
	var optic_front: Node3D = gun.get_node("OpticFrontAxis") as Node3D
	var optic_back: Node3D = gun.get_node("OpticBackAxis") as Node3D
	_check(absf(muzzle.position.x) < 0.0001 and absf(optic_front.position.x) < 0.0001
		and absf(optic_back.position.x) < 0.0001 and optic_front.position.y == optic_back.position.y
		and optic_front.position.z < optic_back.position.z and muzzle.position.z < optic_front.position.z,
		"actual barrel and optical tube axes are parallel and correctly face forward")
	for axis: Node3D in [muzzle, optic_front, optic_back]:
		var depth: float = 0.020 if axis == muzzle else 0.0045
		var start: Vector3 = axis.to_global(Vector3(0, 0, -0.003))
		var end: Vector3 = axis.to_global(Vector3(0, 0, depth))
		_check(not _segment_hits(gun, start, end), "actual " + axis.name + " central ray reaches its physical recess")
		var rim: Vector3 = Vector3(0.008 if axis == muzzle else 0.019, 0, 0)
		_check(_segment_hits(gun, axis.to_global(rim + Vector3(0, 0, -0.003)), axis.to_global(rim + Vector3(0, 0, depth))),
			"same real triangle query hits " + axis.name + " rim instead of a painted opening")
		if axis != muzzle:
			var lens: MeshInstance3D = axis.get_node(String(axis.name).trim_suffix("Axis") + "Lens") as MeshInstance3D
			var housing: MeshInstance3D = axis.get_node(String(axis.name).trim_suffix("Axis") + "Housing") as MeshInstance3D
			var liner: MeshInstance3D = axis.get_node(String(axis.name).trim_suffix("Axis") + "Liner") as MeshInstance3D
			for radial: Vector3 in [Vector3.ZERO, Vector3(0.010, 0, 0), Vector3(-0.010, 0, 0), Vector3(0, 0.010, 0), Vector3(0, -0.010, 0)]:
				var near: Vector3 = axis.to_global(radial + Vector3(0, 0, 0.0064))
				_check(not _segment_hits(gun, start + axis.global_basis * radial, near)
					and _segment_hits_mesh(lens, near, axis.to_global(radial + Vector3(0, 0, 0.0066))),
					"actual optical disk is uniformly flat and recessed rather than folded inward facets")
			_check(_distance_to_surface(axis.to_global(Vector3(0.0173, 0, 0.007)), liner) < 0.0008,
				"actual lens perimeter joins its supporting hollow liner")
			var lens_rest: Vector3 = lens.position
			lens.position.z += 0.003
			_check(not _segment_hits_mesh(lens, axis.to_global(Vector3(0, 0, 0.0064)), axis.to_global(Vector3(0, 0, 0.0066))),
				"the same fixed optical depth query rejects a displaced glass disk")
			lens.position = lens_rest
			var join: Vector3 = axis.to_global(Vector3(0.021, 0, housing.mesh.get_aabb().end.z - 0.001))
			var body_mesh_at_join: MeshInstance3D = gun.get_node("Body/BodyMesh") as MeshInstance3D
			_check(_distance_to_surface(join, body_mesh_at_join) < 0.004,
				"actual hollow optical housing reaches the retained scope tube")
	var body: Node3D = gun.get_node("Body") as Node3D
	var bolt: Node3D = gun.get_node("Bolt") as Node3D
	var bolt_rest: Transform3D = bolt.transform
	var stationary: Dictionary[String, Transform3D] = {}
	for label: String in ["Body", "Chamber", "MuzzleCap", "MuzzleAxis", "OpticFrontAxis", "OpticBackAxis", "TriggerHand", "SupportHand"]:
		stationary[label] = (gun.get_node(label) as Node3D).transform
	var maximum: float = 0.0
	var maximum_lift: float = 0.0
	for frame: int in range(111):
		source.pose(gun, frame * 0.01)
		maximum = maxf(maximum, bolt.position.distance_to(bolt_rest.origin))
		maximum_lift = maxf(maximum_lift, absf(bolt.rotation.z))
		for label: String in stationary:
			_check((gun.get_node(label) as Node3D).transform == stationary[label],
				"the real " + label + " stays fixed while only the bolt cycles")
	_check(is_equal_approx(maximum, 0.065) and is_equal_approx(maximum_lift, PI / 3.0),
		"independent retained bolt achieves 65 mm travel and sixty-degree unlocking")
	for invalid: float in [-1.0, NAN, INF, 1.10, 1.60]:
		source.pose(gun, invalid)
		_check(bolt.transform.is_equal_approx(bolt_rest) and gun.transform.is_equal_approx(Transform3D.IDENTITY),
			"completed or invalid poses settle fully before existing server cooldown")
	var body_mesh: MeshInstance3D = body.get_node("BodyMesh") as MeshInstance3D
	var axial_start: Vector3 = bolt.to_global(Vector3(0, 0, 0.006))
	var axial_end: Vector3 = bolt.to_global(Vector3(0, 0, 0.450))
	_check(not _segment_hits_mesh(body_mesh, axial_start, axial_end), "real fixed receiver has open longitudinal space behind the bolt shaft")
	_check(_segment_hits_mesh(body_mesh, axial_start + Vector3(0, -0.040, 0), axial_end + Vector3(0, -0.040, 0)),
		"same actual longitudinal query hits walnut boundary after downward displacement")
	var swept: Dictionary = _measure_bolt_sweeps(source, gun, bolt, Vector3.ZERO)
	print("actual bolt surface-sample sweeps: ", swept)
	_check(swept["crossings"] == 0, "actual bolt vertices, edge midpoints and face centres remain clear along the sampled stroke")
	var displaced: Dictionary = _measure_bolt_sweeps(source, gun, bolt, Vector3(0, -0.040, 0))
	print("displaced bolt surface-sample sweeps: ", displaced)
	_check(displaced["crossings"] > 0, "same full actual-vertex sweep rejects downward bolt displacement into fixed furniture")
	source.pose(gun, 1.60)
	for label: String in ["TriggerHand", "SupportHand"]:
		var hand: Node3D = gun.get_node(label) as Node3D
		var wrist: MeshInstance3D = hand.get_node("Wrist") as MeshInstance3D
		var palm: MeshInstance3D = hand.get_node("Palm") as MeshInstance3D
		var wrist_start: Vector3 = wrist.to_global(Vector3(0, 0, wrist.mesh.get_aabb().position.z))
		_check(_distance_to_surface(wrist_start, palm) < 0.026, "actual glove wrist joins " + label + " palm")
		_check(_distance_to_surface(wrist_start + Vector3(0, -0.08, 0), palm) > 0.026, "separated glove fails the same real surface contact query")
	var index: MeshInstance3D = gun.get_node("TriggerHand/IndexTip") as MeshInstance3D
	var support: MeshInstance3D = gun.get_node("SupportHand/Finger0Tip") as MeshInstance3D
	var index_end: Vector3 = index.to_global(Vector3(0, 0, index.mesh.get_aabb().end.z))
	var support_end: Vector3 = support.to_global(Vector3(0, 0, support.mesh.get_aabb().end.z))
	_check(_distance_to_surface(index_end, body_mesh) < 0.008 and _distance_to_trigger(index_end, body_mesh) > 0.015,
		"idle index supports upper guard/receiver and stays away from the actual blade")
	var index_base: MeshInstance3D = gun.get_node("TriggerHand/IndexBase") as MeshInstance3D
	var base_rest: Transform3D = index_base.transform
	var tip_rest: Transform3D = index.transform
	for elapsed: float in [0.0, 0.070]:
		source.pose(gun, elapsed)
		var firing_end: Vector3 = index.to_global(Vector3(0, 0, index.mesh.get_aabb().end.z))
		_check(_distance_to_trigger(firing_end, body_mesh) < 0.008,
			"real firing index reaches the specifically measured retained trigger blade")
		_check(_distance_to_trigger(firing_end + gun.global_basis * Vector3(0, 0.035, 0), body_mesh) > 0.015,
			"same actual blade contact query rejects an index displaced onto the receiver")
		_check(index_base.scale.is_equal_approx(Vector3.ONE) and index.scale.is_equal_approx(Vector3.ONE),
			"actual two finger segments rotate without stretching or changing mesh lengths")
		var joint_end: Vector3 = index_base.to_global(Vector3(0, 0, index_base.mesh.get_aabb().end.z))
		var joint_start: Vector3 = index.to_global(Vector3(0, 0, index.mesh.get_aabb().position.z))
		_check(joint_end.distance_to(joint_start) < 0.00001,
			"actual unchanged segment endpoints stay connected throughout firing articulation")
	source.pose(gun, 0.18)
	_check(index_base.transform.is_equal_approx(base_rest) and index.transform.is_equal_approx(tip_rest),
		"index releases to original trigger discipline after the bounded fire pose")
	source.pose(gun, 1.60)
	_check(_distance_to_surface(support_end, body_mesh) < 0.010, "real support fingertip reaches retained fore-end")
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(Source.SOURCE + ".json"))
	var raw_points: PackedVector3Array = []
	var raw_uv: PackedVector2Array = []
	var body_arrays: Array = body_mesh.mesh.surface_get_arrays(0)
	var body_vertices: PackedVector3Array = body_arrays[Mesh.ARRAY_VERTEX]
	var body_uv: PackedVector2Array = body_arrays[Mesh.ARRAY_TEX_UV]
	var body_indices: PackedInt32Array = body_arrays[Mesh.ARRAY_INDEX]
	for vertex: int in body_indices:
		raw_points.append(Vector3(0.30, 0.085, 0.015) + Basis(Vector3.UP, PI * 0.5) * body_vertices[vertex] / (1.18 / 1.90225195884705))
		raw_uv.append(body_uv[vertex])
	var original_faces: Variant = JSON.parse_string(FileAccess.get_file_as_string(Source.SOURCE + ".retained.json"))
	var original_hashes: Array[String] = []
	var valid_original: bool = original_faces is Dictionary and original_faces.get("schema") == 1.0
	if valid_original:
		var hashes: Variant = original_faces.get("triangle_position_uv_winding_hashes")
		valid_original = hashes is Array and hashes.size() == 8955
		if valid_original:
			for hash: Variant in hashes:
				valid_original = valid_original and hash is String and hash.length() == 64
				if hash is String:
					original_hashes.append(hash)
	_check(valid_original and receipt is Dictionary
		and receipt.get("retained_triangle_receipt_sha256") == FileAccess.get_sha256(Source.SOURCE + ".retained.json"),
		"hashed retained-original multiset binds exact source proof instead of conflating clipped fragments")
	var retained: Dictionary = Surfaces.match_retained(raw_points, raw_uv, original_hashes)
	print("retained position/UV/winding fingerprint: ", retained)
	var recorded_surface: Variant = receipt.get("retained_surface_contract") if receipt is Dictionary else null
	_check(recorded_surface is Dictionary and recorded_surface.get("triangles") is float
		and retained["missing"] == 0
		and recorded_surface.get("triangles") == float(retained["triangles"])
		and recorded_surface.get("grid") == retained["grid"]
		and recorded_surface.get("position_uv_winding_sha256") == retained["position_uv_winding_sha256"]
		and receipt.get("surface_contract_sha256") == FileAccess.get_sha256("res://art/models/sniper_surface_contract.gd"),
		"actual exported source retains original positions, UVs and clockwise winding outside measured joint masks")
	_check(Surfaces.match_retained(raw_points, raw_uv, original_hashes, Vector2(0.125, 0)).get("missing") > 0
		and Surfaces.match_retained(raw_points, raw_uv, original_hashes, Vector2.ZERO, true).get("missing") > 0,
		"the same retained-source fingerprint rejects actual UV drift and reversed winding")
	_check(receipt is Dictionary and receipt.get("prepared_sha256") == FileAccess.get_sha256(Source.SOURCE)
		and receipt.get("prepare_sha256") == FileAccess.get_sha256("res://../tools/prepare_sniper_source.gd")
		and receipt.get("raw_sha256") == "4a1d5a0e405410feb385514a6878cf0b9476c298fbcf3456d8674e4797998bcb"
		and receipt.get("runtime_selected") == false, "offline receipt binds exact raw, tool and compact source")
	_check(receipt is Dictionary and receipt.get("joint_audit", {}).get("outside_joint_original_triangles") == 8993
		and receipt.get("joint_audit", {}).get("fully_replaced_original_triangles") == 2501
		and receipt.get("joint_audit", {}).get("clipped_original_triangles") == 341
		and receipt.get("joint_audit", {}).get("retained_clipped_fragment_triangles") == 559,
		"retopology preserves an explicit original/removed/clipped ledger without raw-triangle preservation claims")
	var actual_authored: Dictionary[String, int] = {}
	for node: Node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if (gun.get_node("Bolt") as Node3D).is_ancestor_of(mesh) or (gun.get_node("Chamber") as Node3D).is_ancestor_of(mesh):
			actual_authored[str(mesh.get_parent().name) + "/" + str(mesh.name)] = mesh.mesh.get_faces().size() / 3
		elif mesh.get_parent().name in ["MuzzleAxis", "OpticFrontAxis", "OpticBackAxis"]:
			actual_authored[str(mesh.name)] = mesh.mesh.get_faces().size() / 3
	var accounted: bool = receipt is Dictionary and receipt.get("authored_triangles") is Dictionary
	if accounted:
		var recorded: Dictionary = receipt["authored_triangles"]
		accounted = recorded.size() == actual_authored.size()
		for label: String in actual_authored:
			var count: Variant = recorded.get(label)
			accounted = accounted and count is float and is_finite(count) and count == float(actual_authored[label])
	_check(accounted, "every actual local bolt/chamber/recess triangle matches the separately counted receipt")
	var settings: String = FileAccess.get_file_as_string(Source.SOURCE + ".import")
	_check(settings.contains("meshes/generate_lods=false") and settings.contains("gltf/embedded_image_handling=3")
		and settings.contains("meshes/force_disable_compression=true"),
		"offline import preserves geometry and embedded uncompressed maps")
	gun.free()
	await process_frame
	if _failures == 0:
		print("test_sniper_source: PASS accounted geometry, compact matte maps, real recesses, fixed axes, independent bolt and actual contact queries; visual acceptance separate")
	quit(0 if _failures == 0 else 1)

func _check_selection() -> void:
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(SELECTED + "selection.json"))
	_check(receipt is Dictionary and receipt.get("schema") == 1.0 and receipt.get("runtime_selected") == true,
		"selected pictures have a distinct runtime receipt")
	if not receipt is Dictionary:
		return
	_check(receipt.get("source_sha256") == FileAccess.get_sha256(Source.SOURCE)
		and receipt.get("presenter_sha256") == FileAccess.get_sha256("res://art/models/sniper_source.gd")
		and receipt.get("bake_sha256") == FileAccess.get_sha256("res://../tools/preview_sniper_source.gd"),
		"selection binds the actual accepted source, presenter and baker")
	var textures: Dictionary[String, Texture2D] = {
		"sniper_idle.png": Art.IDLE["Sniper"], "sniper_fire.png": Art.FIRE["Sniper"], "sniper.png": Art.PROFILE["Sniper"]}
	for label: String in textures:
		var texture: Texture2D = textures[label]
		_check(texture.resource_path == SELECTED + label and not texture.get_image().has_mipmaps()
			and receipt.get("frames", {}).get(label) == FileAccess.get_sha256(SELECTED + label)
			and FileAccess.get_sha256(SELECTED + label) == FileAccess.get_sha256("res://art/models/candidates/sniper_views/" + label),
			"live " + label + " uses the exact reviewed pixel picture without mipmaps")
	_check(Art.frame_after_shot("Sniper", 0.0) == Art.FIRE["Sniper"]
		and Art.frame_after_shot("Sniper", 0.079) == Art.FIRE["Sniper"]
		and Art.frame_after_shot("Sniper", 0.080) == Art.IDLE["Sniper"]
		and Art.frame_after_shot("Sniper", 0.30) == Art.IDLE["Sniper"]
		and Art.pickup_texture("weapon", "Sniper", "Cells") == Art.PROFILE["Sniper"],
		"actual runtime frame and pickup routing preserves existing fire duration without adding a cycle")
	_check(Art.SCOPE_OVERLAY.resource_path == "res://assets/weapons/sniper/scope_overlay.png"
		and is_equal_approx(Art.PICKUP_TEXEL_METRES, 1.0 / 72.0)
		and FileAccess.file_exists("res://assets/weapons/viewmodels/sniper_idle.png")
		and FileAccess.file_exists("res://assets/weapons/viewmodels/sniper_fire.png")
		and FileAccess.file_exists("res://assets/weapons/pickups/sniper.png"),
		"scope, physical density and original artwork remain retained")

func _segment_hits(gun: Node3D, start: Vector3, end: Vector3) -> bool:
	for node: Node in gun.find_children("*", "MeshInstance3D", true, false):
		if _segment_hits_mesh(node as MeshInstance3D, start, end):
			return true
	return false

func _measure_bolt_sweeps(source: RefCounted, gun: Node3D, bolt: Node3D, offset: Vector3) -> Dictionary:
	# Index the retained fixed triangles in metre cells. Only actual segment /
	# triangle intersections count; broad bounds merely limit the CPU work.
	var faces: PackedVector3Array = []
	for node: Node in gun.find_children("*", "MeshInstance3D", true, false):
		var fixed: MeshInstance3D = node as MeshInstance3D
		if bolt.is_ancestor_of(fixed) or fixed.name in ["IndexBase", "IndexTip"]:
			continue
		var transform: Transform3D = gun.global_transform.affine_inverse() * fixed.global_transform
		for point: Vector3 in fixed.mesh.get_faces():
			faces.append(transform * point)
	# The firing finger has its own two rigid segments. Include every sampled
	# posed surface in the fixed clearance envelope, preserving conservative
	# clearance without pretending these meshes remain at their idle transform.
	for frame: int in range(19):
		source.pose(gun, frame * 0.01)
		for label: String in ["IndexBase", "IndexTip"]:
			var finger: MeshInstance3D = gun.get_node("TriggerHand/" + label) as MeshInstance3D
			var transform: Transform3D = gun.global_transform.affine_inverse() * finger.global_transform
			for point: Vector3 in finger.mesh.get_faces():
				faces.append(transform * point)
	source.pose(gun, 1.60)
	var grid: Dictionary[Vector3i, Array] = {}
	for face: int in range(0, faces.size(), 3):
		var box: AABB = AABB(faces[face], Vector3.ZERO).expand(faces[face + 1]).expand(faces[face + 2])
		for cell: Vector3i in _cells(box.grow(0.00001)):
			if not grid.has(cell):
				grid[cell] = []
			grid[cell].append(face)
	var unique: Dictionary[Vector3i, Vector3] = {}
	for node: Node in bolt.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var transform: Transform3D = bolt.global_transform.affine_inverse() * mesh.global_transform
		var moving_faces: PackedVector3Array = mesh.mesh.get_faces()
		for face: int in range(0, moving_faces.size(), 3):
			var a: Vector3 = transform * moving_faces[face]
			var b: Vector3 = transform * moving_faces[face + 1]
			var c: Vector3 = transform * moving_faces[face + 2]
			for point: Vector3 in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) / 3.0]:
				var quantized: Vector3 = point * 100000.0
				unique[Vector3i(roundi(quantized.x), roundi(quantized.y), roundi(quantized.z))] = point
	var previous: Dictionary[Vector3i, Vector3] = {}
	var crossings: int = 0
	var first_crossings: Array[Dictionary] = []
	var samples: int = 0
	for frame: int in range(111):
		source.pose(gun, frame * 0.01)
		for key: Vector3i in unique:
			var point: Vector3 = bolt.transform * unique[key] + offset
			if previous.has(key) and previous[key].distance_squared_to(point) > 0.000000001:
				var start: Vector3 = previous[key]
				var tested: Dictionary[int, bool] = {}
				for cell: Vector3i in _cells(AABB(start, Vector3.ZERO).expand(point).grow(0.00001)):
					for face: int in grid.get(cell, []):
						if tested.has(face):
							continue
						tested[face] = true
						var hit: Variant = Geometry3D.segment_intersects_triangle(start * 100.0, point * 100.0,
							faces[face] * 100.0, faces[face + 1] * 100.0, faces[face + 2] * 100.0)
						if hit is Vector3:
							crossings += 1
							if first_crossings.size() < 8:
								first_crossings.append({"frame":frame, "moving":key, "fixed_face":face / 3, "point":hit / 100.0})
				samples += 1
			previous[key] = point
	return {"crossings":crossings, "surface_sample_points":unique.size(), "segments":samples, "interval_seconds":0.01, "first_crossings":first_crossings}

func _cells(box: AABB) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var lower: Vector3 = (box.position / 0.020).floor()
	var upper: Vector3 = (box.end / 0.020).floor()
	for x: int in range(int(lower.x), int(upper.x) + 1):
		for y: int in range(int(lower.y), int(upper.y) + 1):
			for z: int in range(int(lower.z), int(upper.z) + 1):
				result.append(Vector3i(x, y, z))
	return result

func _segment_hits_mesh(mesh: MeshInstance3D, start: Vector3, end: Vector3) -> bool:
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	for face: int in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(start * 100.0, end * 100.0,
			mesh.to_global(faces[face]) * 100.0, mesh.to_global(faces[face + 1]) * 100.0, mesh.to_global(faces[face + 2]) * 100.0)
		if hit is Vector3:
			return true
	return false

func _distance_to_surface(point: Vector3, mesh: MeshInstance3D) -> float:
	return _distance_to_faces(point, mesh.mesh.get_faces(), mesh.global_transform)

func _distance_to_trigger(point: Vector3, body: MeshInstance3D) -> float:
	var faces: PackedVector3Array = body.mesh.get_faces()
	var blade: PackedVector3Array = []
	var measured_region: AABB = AABB(Vector3(-0.012, -0.104, 0.049), Vector3(0.025, 0.023, 0.022))
	for face: int in range(0, faces.size(), 3):
		if measured_region.has_point((faces[face] + faces[face + 1] + faces[face + 2]) / 3.0):
			blade.append(faces[face])
			blade.append(faces[face + 1])
			blade.append(faces[face + 2])
	return _distance_to_faces(point, blade, body.global_transform)

func _distance_to_faces(point: Vector3, faces: PackedVector3Array, transform: Transform3D) -> float:
	var nearest: float = INF
	for face: int in range(0, faces.size(), 3):
		var a: Vector3 = transform * faces[face]
		var b: Vector3 = transform * faces[face + 1]
		var c: Vector3 = transform * faces[face + 2]
		var corners: PackedVector3Array = PackedVector3Array([a, b, c])
		for edge: int in range(3):
			var first: Vector3 = corners[edge]
			var segment: Vector3 = corners[(edge + 1) % 3] - first
			var along: float = clampf((point - first).dot(segment) / maxf(segment.length_squared(), 0.00000001), 0.0, 1.0)
			nearest = minf(nearest, point.distance_to(first + segment * along))
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		if normal.length_squared() < 0.5:
			continue
		var projected: Vector3 = point - normal * (point - a).dot(normal)
		if (b - a).cross(projected - a).dot(normal) >= 0.0 and (c - b).cross(projected - b).dot(normal) >= 0.0 and (a - c).cross(projected - c).dot(normal) >= 0.0:
			nearest = minf(nearest, point.distance_to(projected))
	return nearest
