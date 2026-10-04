extends SceneTree

const Source = preload("res://art/models/rifle_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_rifle_source: " + message)

func _run() -> void:
	var source: RefCounted = Source.new()
	var gun: Node3D = source.build(true)
	root.add_child(gun)
	var counts: Dictionary[String, int] = {"Body":5818, "Bolt":216, "Trigger":88}
	var bounds: AABB
	var bounded: bool = false
	for name: String in counts:
		var mesh: MeshInstance3D = gun.get_node(name + "/" + name + "Mesh") as MeshInstance3D
		_check(mesh.mesh.get_faces().size() / 3 == counts[name], "raw " + name + " triangles remain intact")
		var finish: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
		_check(finish.albedo_texture.get_width() == 1024 and finish.normal_texture.get_width() == 1024
			and finish.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
			"original surface embeds bounded nearest-sampled 1K maps")
		_check(finish.metallic_texture == null and finish.roughness_texture == null
			and finish.metallic < 0.10 and finish.roughness > 0.90 and finish.normal_scale < 0.21,
			"quiet metal finish avoids photographic specular scratches")
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if bounded else box
		bounded = true
	_check(absf(bounds.size.z - 0.94) < 0.0001 and bounds.size.y > 0.25
		and bounds.size.y < 0.32 and bounds.size.x < 0.10,
		"rifle has measured 94 cm length and bounded civilian proportions")
	var body: Node3D = gun.get_node("Body") as Node3D
	var bolt: Node3D = gun.get_node("Bolt") as Node3D
	var trigger: Node3D = gun.get_node("Trigger") as Node3D
	var muzzle: Node3D = gun.get_node("Muzzle") as Node3D
	var trigger_hand: Node3D = gun.get_node("TriggerHand") as Node3D
	var support_hand: Node3D = gun.get_node("SupportHand") as Node3D
	var body_rest: Transform3D = body.transform
	var bolt_rest: Transform3D = bolt.transform
	var trigger_rest: Transform3D = trigger.transform
	var muzzle_rest: Transform3D = muzzle.transform
	var trigger_hand_rest: Transform3D = trigger_hand.transform
	var support_hand_rest: Transform3D = support_hand.transform
	var index_tip: MeshInstance3D = trigger_hand.get_node("IndexTip") as MeshInstance3D
	var support_tip: MeshInstance3D = support_hand.get_node("Finger0Tip") as MeshInstance3D
	var index_end: Vector3 = index_tip.to_global(Vector3(0, 0, index_tip.mesh.get_aabb().end.z))
	var support_end: Vector3 = support_tip.to_global(Vector3(0, 0, support_tip.mesh.get_aabb().end.z))
	_check(_distance_to_surface(index_end, trigger.get_node("TriggerMesh") as MeshInstance3D) < 0.008,
		"actual index fingertip radius reaches the source trigger surface")
	_check(_distance_to_surface(support_end, body.get_node("BodyMesh") as MeshInstance3D) < 0.010,
		"actual support fingertip radius reaches the source handguard surface")
	for hand: Node3D in [trigger_hand, support_hand]:
		var wrist: MeshInstance3D = hand.get_node("Wrist") as MeshInstance3D
		var palm: MeshInstance3D = hand.get_node("Palm") as MeshInstance3D
		var wrist_start: Vector3 = wrist.to_global(Vector3(0, 0, wrist.mesh.get_aabb().position.z))
		_check(_distance_to_surface(wrist_start, palm) < 0.026,
			"actual wrist radius joins its glove palm without a floating assembly")
		_check(_distance_to_surface(wrist_start + Vector3(0, -0.08, 0), palm) > 0.026,
			"a visibly separated wrist fails the same actual glove surface test")
	_check(muzzle.position.z < -0.46 and absf(muzzle.position.x) < 0.003 and absf(muzzle.position.y) < 0.006,
		"marker retains source bore direction and physical muzzle endpoint")
	var bolt_finish: StandardMaterial3D = (bolt.get_node("BoltMesh") as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	_check(bolt_finish.vertex_color_use_as_albedo, "actual imported bolt enables retained per-face plane paint")
	var maximum: float = 0.0
	for index: int in range(41):
		source.pose(gun, index * 0.005)
		maximum = maxf(maximum, bolt.position.distance_to(bolt_rest.origin))
		_check(body.transform == body_rest and muzzle.transform == muzzle_rest,
			"stock, guard, barrel and bore stay fixed within the recoiling rifle")
		_check(trigger_hand.transform == trigger_hand_rest and support_hand.transform == support_hand_rest,
			"both gloves retain receiver and handguard contact through the independent mechanism")
	_check(is_equal_approx(maximum, 0.03), "bolt and actual handle achieve a measured thirty-millimetre stroke")
	source.pose(gun, 0.070)
	_check(not trigger.transform.is_equal_approx(trigger_rest), "source trigger pivots independently inside the fixed guard")
	for invalid: float in [-1.0, INF, NAN, 0.20, 1.0]:
		source.pose(gun, invalid)
		_check(gun.transform.is_equal_approx(Transform3D.IDENTITY)
			and bolt.transform.is_equal_approx(bolt_rest) and trigger.transform.is_equal_approx(trigger_rest),
			"mechanism settles without accumulated offsets for invalid and completed timings")
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(Source.SOURCE + ".json"))
	var import_settings: String = FileAccess.get_file_as_string(Source.SOURCE + ".import")
	_check(import_settings.contains("meshes/generate_lods=false")
		and import_settings.contains("gltf/embedded_image_handling=3"),
		"offline import retains full geometry and uncompressed embedded maps")
	var body_finish: StandardMaterial3D = (body.get_node("BodyMesh") as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	_check(body_finish.vertex_color_use_as_albedo, "actual receiver and sights retain painted face contrast")
	_check(body_finish.albedo_texture.resource_path.begins_with(Source.SOURCE + "::")
		and body_finish.normal_texture.resource_path.begins_with(Source.SOURCE + "::"),
		"actual loaded source uses embedded maps without extracted sidecar dependence")
	_check(receipt is Dictionary and receipt.get("prepared_sha256") == FileAccess.get_sha256(Source.SOURCE)
		and receipt.get("prepare_sha256") == FileAccess.get_sha256("res://../tools/prepare_rifle_source.gd")
		and receipt.get("raw_sha256") == "5d53e8995a825b4e594c9b812759dcb070342bfddc73bd64ba351ea9a0576394"
		and receipt.get("runtime_selected") == false, "exact source and preparation receipts stay offline")
	_check(WeaponArt.IDLE["Flechette"].resource_path == "res://assets/weapons/viewmodels/rifle_idle.png",
		"runtime Rifle stays unchanged while source review remains open")
	gun.free()
	await process_frame
	if _failures == 0:
		print("test_rifle_source: PASS preserved topology, compact maps, measured bounds and independent offline mechanism")
	quit(0 if _failures == 0 else 1)

func _distance_to_surface(point: Vector3, mesh: MeshInstance3D) -> float:
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	var nearest: float = INF
	for face: int in range(0, faces.size(), 3):
		var a: Vector3 = mesh.to_global(faces[face])
		var b: Vector3 = mesh.to_global(faces[face + 1])
		var c: Vector3 = mesh.to_global(faces[face + 2])
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
		if (b - a).cross(projected - a).dot(normal) >= 0.0 \
			and (c - b).cross(projected - b).dot(normal) >= 0.0 \
			and (a - c).cross(projected - c).dot(normal) >= 0.0:
			nearest = minf(nearest, point.distance_to(projected))
	return nearest
