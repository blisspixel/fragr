class_name TravelingShots
extends Node3D

## Server positions for points still in flight. This node does not move them.
const MARKER_SIZE: float = 0.28
const MAX_COORDINATE: float = 8192.0
const MAX_MARKERS: int = 512
var _markers: Dictionary[int, MeshInstance3D] = {}
var _mesh: SphereMesh
var _material: StandardMaterial3D

func clear_shots() -> void:
	for child in get_children():
		child.free()
	_markers.clear()

func apply(shots: Variant) -> void:
	if not shots is Array:
		clear_shots()
		return
	var seen: Dictionary[int, bool] = {}
	for index: int in range(mini(shots.size(), MAX_MARKERS)):
		var shot: Variant = shots[index]
		if not _valid(shot):
			continue
		var id: int = int(shot["id"])
		if seen.has(id):
			continue
		seen[id] = true
		var marker: MeshInstance3D = _markers.get(id)
		if marker == null:
			marker = _marker(id)
			_markers[id] = marker
			add_child(marker)
		marker.position = Vector3(float(shot["x"]), float(shot["y"]), float(shot["z"]))
	for id: int in _markers.keys():
		if not seen.has(id):
			_markers[id].free()
			_markers.erase(id)

func _valid(shot: Variant) -> bool:
	if not shot is Dictionary:
		return false
	var id: Variant = shot.get("id")
	var x: Variant = shot.get("x")
	var y: Variant = shot.get("y")
	var z: Variant = shot.get("z")
	return EquipmentState.integer(id, EquipmentState.MAX_EXACT_INTEGER) \
		and _coordinate(x) and _coordinate(y) and _coordinate(z)

func _marker(id: int) -> MeshInstance3D:
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = MARKER_SIZE * 0.5
		_mesh.height = MARKER_SIZE
		_mesh.radial_segments = 8
		_mesh.rings = 4
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.albedo_color = Color("ffb454")
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.name = "Shot%s" % int(id)
	marker.mesh = _mesh
	marker.layers = ArenaSky.WORLD_LAYERS
	marker.material_override = _material
	return marker

func _number(value: Variant) -> bool:
	return value is int or value is float

func _coordinate(value: Variant) -> bool:
	return _number(value) and is_finite(float(value)) and absf(float(value)) <= MAX_COORDINATE
