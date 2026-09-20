extends SceneTree

var failures: int = 0
var received: int = 0
var rejected: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_map_geometry: " + message)

func _run() -> void:
	var legacy: Dictionary = {"map_id": 1, "half_extent": 20.0, "solids": [
		{"min_x": -3.0, "max_x": 3.0, "min_z": -3.0, "max_z": 3.0}]}
	_expect(MapGeometry.validation_error(legacy) == "", "legacy default bounds rejected")
	var raised: Dictionary = legacy.duplicate(true)
	raised["geometry_version"] = 2
	raised["solids"][0]["bottom"] = 2.4
	raised["solids"][0]["top"] = 3.0
	_expect(MapGeometry.validation_error(raised) == "", "raised volume rejected")
	var surfaced: Dictionary = raised.duplicate(true)
	surfaced["presentation"] = {"ground": "concrete", "solids": ["enamel"]}
	_expect(MapGeometry.validation_error(surfaced) == "", "registered surfaces rejected")
	for bad_surface: Variant in ["res://untrusted.gd", {}, {"ground": "concrete", "solids": []}, {"ground": "concrete", "solids": ["unregistered"]}]:
		surfaced["presentation"] = bad_surface
		_expect(MapGeometry.validation_error(surfaced) != "", "invalid surfaces accepted")
	for invalid: Variant in [null, true, 3, {}, []]:
		for where: String in ["ground", "solid"]:
			surfaced["presentation"] = {"ground": invalid if where == "ground" else "concrete", "solids": [invalid if where == "solid" else "enamel"]}
			_expect(MapGeometry.validation_error(surfaced) != "", "untyped surface accepted")
	for field: String in ["map_id", "half_extent", "geometry_version", "solids"]:
		for value: Variant in [null, "2", true, NAN, INF, -1.0]:
			var bad: Dictionary = raised.duplicate(true)
			bad[field] = value
			_expect(MapGeometry.validation_error(bad) != "", "invalid " + field + " accepted")
	for field: String in ["min_x", "max_x", "min_z", "max_z", "bottom", "top"]:
		for value: Variant in [null, "2", true, NAN, INF, 513.0]:
			var bad: Dictionary = raised.duplicate(true)
			bad["solids"][0][field] = value
			_expect(MapGeometry.validation_error(bad) != "", "invalid solid " + field + " accepted")
	for change: Dictionary in [{"bottom": -1.0}, {"bottom": 3.0}, {"min_x": 3.0}, {"min_z": 4.0}]:
		var bad: Dictionary = raised.duplicate(true)
		bad["solids"][0].merge(change, true)
		_expect(MapGeometry.validation_error(bad) != "", "inverted or empty volume accepted")
	var large: Dictionary = raised.duplicate(true)
	large["solids"].resize(MapGeometry.MAX_SOLIDS + 1)
	_expect(MapGeometry.validation_error(large) != "", "unbounded solid list accepted")
	for version: int in [0, 1, 3]:
		var bad: Dictionary = raised.duplicate(true)
		bad["geometry_version"] = version
		_expect(MapGeometry.validation_error(bad) != "", "invalid raised geometry version accepted")
	var net: Node = load("res://scripts/net_client.gd").new()
	root.add_child(net)
	net.map_info_received.connect(func(_info: Dictionary) -> void: received += 1)
	net.server_error.connect(func(_message: String) -> void: rejected += 1)
	raised["type"] = "map_info"
	net._handle_message(JSON.stringify(raised))
	_expect(received == 1 and rejected == 0, "valid network map not delivered")
	raised["geometry_version"] = 3
	net._handle_message(JSON.stringify(raised))
	_expect(received == 1 and rejected == 1, "unsupported network map reached presenter")
	_expect(not net.is_processing(), "rejected map left network processing active")
	net._handle_message('{"type":"error","code":"unsupported_geometry"}')
	_expect(rejected == 2, "server compatibility rejection not visible")
	for malformed: String in ['{"type":"map_info",', '[]', 'null']:
		var before: int = rejected
		net.set_process(true)
		net._handle_message(malformed)
		_expect(rejected == before + 1 and received == 1, "malformed message retained a usable stale map")
		_expect(not net.is_processing(), "malformed message left network processing active")
	net.free()
	if failures == 0:
		print("test_map_geometry: PASS finite volumes, bounds, versions, network rejection")
	quit(0 if failures == 0 else 1)
