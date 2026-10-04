class_name M06Workmanship
extends Node3D

## Port fittings describe registered bodies, never introduce playable cover.
const MAX_TRIM: float = 0.025
const CHARCOAL: Color = Color("343b3c")
const SHELL: Color = Color("b1b1a4")
const STEEL: Color = Color("79847c")
const RED: Color = Color("923b32")
var mesh_count: int = 0
var light_count: int = 0
var _materials: Dictionary[String, StandardMaterial3D] = {}

func build(info: Dictionary) -> void:
	name = "PortWorkmanship"
	if info.get("map_id") != 1006 or info.get("map_name") != "Port of Entry" or not info.get("solids") is Array:
		return
	var solids: Array = info["solids"]
	# These actual pressure roofs distinguish the authored port from wire fixtures.
	if _host(solids, Vector3(-42, 6, -44), Vector3(-21, 6.3, -29)).is_empty() \
		or _host(solids, Vector3(-24, 6.8, 7), Vector3(24, 7.1, 39)).is_empty():
		return
	for shape: Array in [
		[Vector3(-35, 0, -27), Vector3(-31, 2.8, -23)],
		[Vector3(-23, 0, -26), Vector3(-18, 3, -23)],
		[Vector3(-18, 0, -22), Vector3(-12, 3, -18)],
		[Vector3(28, 0, -4), Vector3(32, 2.5, -1)]]:
		var cargo: Dictionary = _host(solids, shape[0], shape[1])
		if not cargo.is_empty():
			_cargo(cargo)
	for shape: Array in [
		[Vector3(-42, 6, -44), Vector3(-21, 6.3, -29)],
		[Vector3(-42, 6.2, -29), Vector3(38, 6.5, 5)],
		[Vector3(-24, 6.8, 7), Vector3(24, 7.1, 39)],
		[Vector3(-9, 6.8, 39), Vector3(9, 7.1, 45)]]:
		var roof: Dictionary = _host(solids, shape[0], shape[1])
		if not roof.is_empty():
			_roof(roof)
	for shape: Array in [
		[Vector3(-42, 0, -30), Vector3(-35, 6, -29)],
		[Vector3(-26, 0, -30), Vector3(-21, 6, -29)]]:
		var bulkhead: Dictionary = _host(solids, shape[0], shape[1])
		if not bulkhead.is_empty():
			_bulkhead(bulkhead)
	for shape: Array in [
		[Vector3(-12, 0, 15), Vector3(-8, 0.9, 18)],
		[Vector3(8, 0, 15), Vector3(12, 0.9, 18)],
		[Vector3(-12, 0, 35), Vector3(-9, 2.4, 38)],
		[Vector3(9, 0, 35), Vector3(12, 2.4, 38)]]:
		var desk: Dictionary = _host(solids, shape[0], shape[1])
		if not desk.is_empty():
			_customs(desk)
	_floor_lane(Vector3(-30.5, 0.006, -36), 5.0)
	_floor_lane(Vector3(0, 0.006, 40), 4.0)
	ArenaSky.mark_world(self)

static func _host(solids: Array, low: Vector3, high: Vector3) -> Dictionary:
	for entry: Variant in solids:
		if not entry is Dictionary:
			continue
		var solid: Dictionary = entry
		if not solid.has_all(["min_x", "max_x", "min_z", "max_z", "top"]):
			continue
		var actual_low: Vector3 = Vector3(float(solid["min_x"]), MoveStep.solid_bottom(solid), float(solid["min_z"]))
		var actual_high: Vector3 = Vector3(float(solid["max_x"]), MoveStep.solid_top(solid), float(solid["max_z"]))
		if actual_low.is_equal_approx(low) and actual_high.is_equal_approx(high):
			return {"low": low, "high": high}
	return {}

func _cargo(host: Dictionary) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	var centre: Vector3 = (low + high) * 0.5
	var size: Vector3 = high - low
	for fraction: float in [0.22, 0.78]:
		var x: float = lerpf(low.x, high.x, fraction)
		for z: float in [low.z - 0.012, high.z + 0.012]:
			_piece("CargoLockingStrap", Vector3(x, centre.y, z), Vector3(0.11, size.y, 0.018), CHARCOAL, host)
		_piece("CargoTopStrap", Vector3(x, high.y + 0.012, centre.z), Vector3(0.11, 0.018, size.z), CHARCOAL, host)
	for y: float in [low.y + 0.15, high.y - 0.15]:
		_piece("CargoEdgeRail", Vector3(centre.x, y, high.z + 0.012), Vector3(size.x - 0.12, 0.08, 0.018), STEEL, host)
	for fraction: float in [0.35, 0.65]:
		_piece("CargoStampedRib", Vector3(lerpf(low.x, high.x, fraction), centre.y, high.z + 0.012), Vector3(0.06, size.y - 0.42, 0.018), STEEL, host)
	_piece("CargoSealedLatch", Vector3(centre.x, centre.y, high.z + 0.012), Vector3(0.58, 0.28, 0.018), SHELL, host)
	_piece("CargoSealStripe", Vector3(centre.x + 0.16, centre.y, high.z + 0.021), Vector3(0.08, 0.22, 0.006), RED, host)

func _roof(host: Dictionary) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	var width: float = high.x - low.x
	var depth: float = high.z - low.z
	for fraction: float in [0.22, 0.5, 0.78]:
		_piece("PressureRoofRib", Vector3((low.x + high.x) * 0.5, low.y - 0.012, lerpf(low.z, high.z, fraction)),
			Vector3(width - 0.4, 0.018, 0.14), CHARCOAL, host)
	var segments: int = clampi(floori(width / 12.0), 1, 3)
	for segment: int in range(segments):
		var x: float = lerpf(low.x, high.x, float(segment + 1) / float(segments + 1))
		var centre: Vector3 = Vector3(x, low.y - 0.012, lerpf(low.z, high.z, 0.43))
		_piece("RecessedTaskLampHousing", centre, Vector3(2.8, 0.018, 0.34), CHARCOAL, host)
		var diffuser: MeshInstance3D = _piece("RecessedTaskLampDiffuser", centre + Vector3(0, -0.008, 0), Vector3(2.44, 0.006, 0.18), Color("d8c69d"), host)
		diffuser.material_override = _material(Color("d8c69d"), true)
		# A small fixed practical reaches nearby architecture, never a whole hall.
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "PortTaskLight"
		light.position = centre + Vector3(0, -0.10, 0)
		light.light_color = Color("ffe2ad")
		light.light_energy = 0.65
		light.omni_range = minf(9.0, maxf(5.0, depth * 0.4))
		light.light_cull_mask = 2
		light.add_to_group(ArenaSky.PRACTICAL_GROUP)
		add_child(light)
		light_count += 1

func _bulkhead(host: Dictionary) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	var edge: float = high.x - 0.07 if high.x < -30 else low.x + 0.07
	for z: float in [low.z - 0.012, high.z + 0.012]:
		_piece("OpenPressureDoorSeal", Vector3(edge, 2.35, z), Vector3(0.12, 4.7, 0.018), CHARCOAL, host)
		for y: float in [0.45, 1.7, 3.0, 4.25]:
			_piece("PressureDoorFastener", Vector3(edge, y, z), Vector3(0.055, 0.065, 0.022), SHELL, host)
	_piece("BulkheadInstitutionBand", Vector3((low.x + high.x) * 0.5, 4.0, low.z - 0.012), Vector3(high.x - low.x - 0.35, 0.22, 0.018), RED, host)

func _customs(host: Dictionary) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	var centre: Vector3 = (low + high) * 0.5
	var size: Vector3 = high - low
	_piece("InspectionWorkMat", Vector3(centre.x, high.y + 0.012, centre.z), Vector3(size.x - 0.45, 0.018, size.z - 0.55), CHARCOAL, host)
	for offset: float in [-0.65, 0.65]:
		_piece("FlushDeclarationForm", Vector3(centre.x + offset, high.y + 0.021, centre.z - 0.2), Vector3(0.40, 0.006, 0.52), SHELL, host)
	_piece("InspectionSerialPanel", Vector3(centre.x, high.y * 0.62, low.z - 0.012), Vector3(size.x - 0.36, 0.32, 0.018), CHARCOAL, host)
	for index: int in range(5):
		_piece("SerialScore", Vector3(centre.x - 0.42 + index * 0.21, high.y * 0.62, low.z - 0.021), Vector3(0.045, 0.15 if index % 2 == 0 else 0.09, 0.006), SHELL, host)

func _floor_lane(centre: Vector3, length: float) -> void:
	for x: float in [-1.4, 1.4]:
		for index: int in range(3):
			_piece("PaintedTransferLane", centre + Vector3(x, 0, (index - 1) * length / 3.0), Vector3(0.12, 0.006, length / 4.0), Color("a69d79"))
	# Direction is surface paint, not a physical barrier or new objective marker.
	for side: float in [-1, 1]:
		var arrow: MeshInstance3D = _piece("PaintedTransferArrow", centre + Vector3(side * 0.23, 0, 0), Vector3(0.1, 0.006, 0.7), Color("a69d79"))
		arrow.rotation.y = -side * PI * 0.25

func _piece(label: String, at: Vector3, size: Vector3, color: Color, host: Dictionary = {}) -> MeshInstance3D:
	var mesh: MeshInstance3D = MoonBackdrop._piece(self, label, at, size, _material(color))
	mesh.set_meta("m06_detail_kind", label)
	if not host.is_empty():
		mesh.set_meta("m06_host_low", host["low"])
		mesh.set_meta("m06_host_high", host["high"])
	mesh_count += 1
	return mesh

func _material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var key: String = color.to_html() + str(glowing)
	if not _materials.has(key):
		var material: StandardMaterial3D = MoonBackdrop._material(color)
		if glowing:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.35
		_materials[key] = material
	return _materials[key]
