extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m02_tableau_bodies: " + message)

func _box(value: Dictionary) -> AABB:
	var low: Vector3 = Vector3(value.min_x, value.bottom, value.min_z)
	return AABB(low, Vector3(value.max_x, value.top, value.max_z) - low)

func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m02_tableau_body_vectors.json"))
	_check(parsed is Dictionary and parsed.get("cases") is Array, "shared vectors load")
	if not parsed is Dictionary or not parsed.get("cases") is Array:
		quit(1)
		return
	var info: Dictionary = parsed["map"]
	var bound: Dictionary = M02TableauBodies.layout(info)
	_check(not bound.is_empty(), "actual restraint host accepted")
	var parent: Node3D = Node3D.new()
	root.add_child(parent)
	parent.position = bound["bay"]
	parent.rotation.y = -PI / 2.0
	var finish: StandardMaterial3D = StandardMaterial3D.new()
	var figure: Node3D = M02TableauBodies.figure(finish, finish, finish)
	parent.add_child(figure)
	_check(figure.get_child_count() == 12, "all original figure parts retained")
	for vector: Dictionary in parsed["cases"]:
		var opening: float = vector["opening"]
		var boxes: Array[AABB] = M02TableauBodies.second_boxes(bound, opening)
		figure.position = Vector3(-0.12 + opening * 0.12, 0, -0.21)
		for index: int in range(boxes.size()):
			var expected: AABB = _box(vector["boxes"][index])
			_check(boxes[index].position.distance_to(expected.position) < 0.00001 and boxes[index].end.distance_to(expected.end) < 0.00001, "shared box %d at %s" % [index, opening])
			var part: MeshInstance3D = figure.get_child(index) as MeshInstance3D
			var actual: AABB = part.global_transform * part.mesh.get_aabb()
			_check(actual.position.distance_to(expected.position) < 0.00001 and actual.end.distance_to(expected.end) < 0.00001, "actual rendered box equals shot box %d at %s" % [index, opening])
	var bad: Dictionary = info.duplicate(true)
	bad["solids"][0]["top"] = 2.61
	_check(M02TableauBodies.layout(bad).is_empty(), "changed source frame refused")
	bad = info.duplicate(true)
	bad["solids"].append(bad["solids"][0].duplicate(true))
	_check(M02TableauBodies.layout(bad).is_empty(), "ambiguous frame refused")
	bad = info.duplicate(true)
	bad["map_id"] = 1001
	_check(M02TableauBodies.layout(bad).is_empty(), "other mission refused")
	_check(M02TableauBodies.second_boxes(bound, NAN).is_empty(), "nonfinite placement refused")
	for sample: Array in [[169, 0.0], [181, 0.5], [192, 1.0], [0, 0.0]]:
		_check(is_equal_approx(M02TableauBodies.opening("releasing", 100, sample[0]), sample[1]), "actual snapshot clock %s" % sample[0])
	_check(M02TableauBodies.opening("releasing", -1, 200) == 0.0, "missing snapshot clock cannot animate a shot ghost")
	_check(M02TableauBodies.opening("following", 340, 340) == 1.0, "actual following uses open pose")
	var notary: NotaryView = NotaryView.new()
	root.add_child(notary)
	var radius: float = 0.0
	var low: float = 0.0
	var high: float = 0.0
	for child: Node in notary.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		var relative: Transform3D = notary._body.global_transform.affine_inverse() * mesh.global_transform
		for vertex: Vector3 in mesh.mesh.get_faces():
			var point: Vector3 = relative * vertex
			radius = maxf(radius, Vector2(point.x, point.z).length())
			low = minf(low, point.y)
			high = maxf(high, point.y)
	var source: Dictionary = parsed["notary"]
	_check(absf(radius - source.source_radius) < 0.00001 and absf(low - source.source_low) < 0.00001 and absf(high - source.source_high) < 0.00001, "all actual Notary vertices preserve enclosure proof")
	var centre: Vector3 = bound["notary"]
	var envelope: AABB = AABB(Vector3(centre.x - radius * 1.2, centre.y + (low - 0.055) * 1.2, centre.z - (radius + 0.25) * 1.2), Vector3(radius * 2.4, (high - low + 0.11) * 1.2, (radius + 0.25) * 2.4))
	var expected: AABB = _box(source["envelope"])
	_check(envelope.position.distance_to(expected.position) < 0.00001 and envelope.end.distance_to(expected.end) < 0.00001, "full yaw radius plus entire bob envelope equals server golden")
	notary.free()
	parent.free()
	await process_frame
	if failures == 0:
		print("test_m02_tableau_bodies: PASS actual twelve-part transforms, snapshot clock, strict source frame and full Notary mesh envelope")
	quit(0 if failures == 0 else 1)
