extends SceneTree

var failures: int = 0
const HOST: Dictionary = {"min_x": -3.0, "max_x": 3.0, "bottom": 2.0,
	"top": 6.0, "min_z": -5.0, "max_z": 5.0}
const DETAIL: Dictionary = {"solid": 0, "face": "north", "center": [0.0, 0.0],
	"size": [2.0, 1.0], "kind": "property_sign"}

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_map_decoration: " + message)

func _run() -> void:
	_contract()
	_placement()
	await _presentation()
	if failures == 0:
		print("test_map_decoration: PASS boundary, six faces, map rebuild, localized text bounds")
	quit(0 if failures == 0 else 1)

func _contract() -> void:
	_expect(MapDecoration.validation_error([DETAIL], [HOST]) == "", "valid panel rejected")
	for bad: Variant in [null, {}, 1, true, "panel"]:
		_expect(MapDecoration.validation_error(bad, [HOST]) != "", "non-array accepted")
		_expect(MapDecoration.validation_error([bad], [HOST]) != "", "non-panel accepted")
	for field: String in DETAIL:
		var missing: Dictionary = DETAIL.duplicate(true)
		missing.erase(field)
		_expect(MapDecoration.validation_error([missing], [HOST]) != "", "missing field accepted")
		for value: Variant in [null, true, {}, NAN, INF]:
			var bad: Dictionary = DETAIL.duplicate(true)
			bad[field] = value
			_expect(MapDecoration.validation_error([bad], [HOST]) != "", "untyped field accepted")
	for change: Dictionary in [{"solid": -1}, {"solid": 1}, {"solid": 0.5},
		{"face": "res://anything"}, {"kind": "res://anything"}, {"extra": 1},
		{"center": [0]}, {"center": [0, 0, 0]}, {"size": [1]},
		{"size": [0.124, 1]}, {"size": [17, 1]}, {"center": [3, 0]}]:
		var bad: Dictionary = DETAIL.duplicate(true)
		bad.merge(change, true)
		_expect(MapDecoration.validation_error([bad], [HOST]) != "", "invalid panel accepted")
	for field: String in ["center", "size"]:
		for axis: int in range(2):
			for value: Variant in [NAN, INF, "1", true, null]:
				var bad: Dictionary = DETAIL.duplicate(true)
				bad[field][axis] = value
				_expect(MapDecoration.validation_error([bad], [HOST]) != "", "invalid axis accepted")
	_expect(MapDecoration.validation_error([DETAIL], []) != "", "missing host accepted")
	var panels: Array = []
	for index: int in range(MapDecoration.MAX_DETAILS):
		panels.append(DETAIL)
	_expect(MapDecoration.validation_error(panels, [HOST]) == "", "panel budget rejected")
	panels.append(DETAIL)
	_expect(MapDecoration.validation_error(panels, [HOST]) != "", "excess panels accepted")
	var light: Dictionary = DETAIL.duplicate(true)
	light["kind"] = "strip_light"
	panels.clear()
	for index: int in range(MapDecoration.MAX_LIGHTS):
		panels.append(light)
	_expect(MapDecoration.validation_error(panels, [HOST]) == "", "light budget rejected")
	panels.append(light)
	_expect(MapDecoration.validation_error(panels, [HOST]) != "", "excess lights accepted")

func _placement() -> void:
	var normals: Array[Vector3] = [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN,
		Vector3.UP, Vector3.FORWARD, Vector3.BACK]
	for index: int in range(MapDecoration.FACES.size()):
		var face: String = MapDecoration.FACES[index]
		var basis: Basis = MapDecoration.face_basis(face)
		_expect(basis.z == normals[index] and is_equal_approx(basis.determinant(), 1.0),
			"incorrect normal or mirrored basis: " + face)
		var detail: Dictionary = DETAIL.duplicate(true)
		detail["face"] = face
		var extent: Vector2 = MapDecoration.dimensions(HOST, face)
		detail["size"] = [extent.x, extent.y]
		_expect(MapDecoration.validation_error([detail], [HOST]) == "", "exact face rejected")
		var transform: Transform3D = MapDecoration.placement(HOST, detail)
		for x: float in [-0.5, 0.5]:
			for y: float in [-0.5, 0.5]:
				var corner: Vector3 = transform * Vector3(x * extent.x, y * extent.y, 0.0)
				corner -= normals[index] * MapDecoration.OFFSET
				_expect(corner.x >= -3.001 and corner.x <= 3.001
					and corner.y >= 1.999 and corner.y <= 6.001
					and corner.z >= -5.001 and corner.z <= 5.001, "face corner outside host")
		detail["center"] = [0.01, 0.0]
		_expect(MapDecoration.validation_error([detail], [HOST]) != "", "off-face panel accepted")
		detail["size"] = [1.0, 1.0]
		detail["center"] = [0.5, -0.5]
		var shifted: Transform3D = MapDecoration.placement(HOST, detail)
		_expect(shifted.origin.is_equal_approx(transform.origin + basis.x * 0.5 - basis.y * 0.5),
			"authoring offsets do not follow the face axes")

func _presentation() -> void:
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	var info: Dictionary = {"map_id": 1001, "half_extent": 20.0, "geometry_version": 2,
		"solids": [HOST], "presentation": {"ground": "concrete", "solids": ["enamel"]}}
	cover.apply_map_info(info)
	var base_count: int = cover.get_child_count()
	var details: Array = []
	for kind: String in MapDecoration.KINDS:
		var detail: Dictionary = DETAIL.duplicate(true)
		detail["kind"] = kind
		details.append(detail)
	info["presentation"]["decorations"] = details
	cover.apply_map_info(info)
	await process_frame
	_expect(cover.get_child_count() == base_count + details.size(), "details not built from MapInfo")
	cover.apply_map_info(info)
	_expect(cover.get_child_count() == base_count + details.size(), "duplicate map rebuilt twice")
	for index: int in range(details.size()):
		var kind: String = details[index]["kind"]
		var panel: MeshInstance3D = cover.get_node("Detail_%d_%s" % [index, kind])
		_expect(panel.transform == MapDecoration.placement(HOST, details[index]), "builder moved panel")
		if ArenaDecoration.SIGN_KEYS.has(kind):
			var label: WorldSign = panel.get_node("Copy")
			_expect(label.text != label.message_key and not label.text.is_empty(), "missing English catalog key")
			_check_label(label)
		if kind == "strip_light":
			_expect(panel.get_node("Practical") is OmniLight3D, "missing practical light")
	# A runtime locale change must relayout expanded copy, not retain English metrics.
	var expanded: Translation = Translation.new()
	expanded.locale = "de"
	expanded.add_message("WORLD_PROPERTY_INTAKE", "A MUCH LONGER TEST TRANSLATION\n".repeat(5))
	TranslationServer.add_translation(expanded)
	TranslationServer.set_locale("de")
	await process_frame
	var sign: WorldSign = cover.get_node("Detail_0_property_sign/Copy")
	_expect(sign.text.begins_with("A MUCH LONGER"), "runtime translation did not refresh")
	_check_label(sign)
	TranslationServer.set_locale("en")
	TranslationServer.remove_translation(expanded)
	await process_frame
	info["presentation"].erase("decorations")
	cover.apply_map_info(info)
	_expect(cover.get_child_count() == base_count, "map rotation retained details")
	info["presentation"]["decorations"] = [{"kind": "invalid"}]
	_expect(MapGeometry.validation_error(info) != "", "map boundary ignored bad detail")
	cover.free()

func _check_label(label: WorldSign) -> void:
	var triangles: TriangleMesh = label.generate_triangle_mesh()
	_expect(triangles != null, "label produced no geometry")
	if triangles != null:
		for vertex: Vector3 in triangles.get_faces():
			_expect(absf(vertex.x) <= label.bounds.x * 0.5 + 0.005
				and absf(vertex.y) <= label.bounds.y * 0.5 + 0.005, "translated text exceeds panel")
