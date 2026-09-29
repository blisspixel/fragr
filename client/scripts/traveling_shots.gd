class_name TravelingShots
extends Node3D

## Server positions for points still in flight. This node does not move them.
const MARKER_SIZE: float = 0.18
const MAX_COORDINATE: float = 8192.0

func clear_shots() -> void:
	for child in get_children():
		child.free()

func apply(shots: Variant) -> void:
	clear_shots()
	if not shots is Array:
		return
	for shot in shots:
		var marker: MeshInstance3D = _marker(shot)
		if marker != null:
			add_child(marker)

func _marker(shot: Variant) -> MeshInstance3D:
	if not shot is Dictionary:
		return null
	var id: Variant = shot.get("id")
	var x: Variant = shot.get("x")
	var y: Variant = shot.get("y")
	var z: Variant = shot.get("z")
	if not _number(id) or not _coordinate(x) or not _coordinate(y) or not _coordinate(z):
		return null
	var mesh := BoxMesh.new()
	mesh.size = Vector3(MARKER_SIZE, MARKER_SIZE, MARKER_SIZE)
	var marker := MeshInstance3D.new()
	marker.name = "Shot%s" % int(id)
	marker.mesh = mesh
	marker.position = Vector3(float(x), float(y), float(z))
	marker.layers = ArenaSky.WORLD_LAYERS
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.95, 0.86, 0.35)
	marker.material_override = material
	return marker

func _number(value: Variant) -> bool:
	return value is int or value is float

func _coordinate(value: Variant) -> bool:
	return _number(value) and is_finite(float(value)) and absf(float(value)) <= MAX_COORDINATE
