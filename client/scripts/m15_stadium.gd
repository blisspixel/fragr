class_name M15Stadium
extends Node3D

## Civic Pressure Valve connected stadium bout presenter.
signal notice_requested(text: String)

var _geometry: Dictionary = {}
var _placards: Array[MeshInstance3D] = []
var _broadcast_taken: bool = false
var _notice_fired: bool = false
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	_placards.clear()
	_broadcast_taken = false
	_notice_fired = false
	state_applied = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m15") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_build_placards()

func _box(label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.layers = ArenaSky.WORLD_LAYERS
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	node.material_override = material
	add_child(node)
	return node

func _build_placards() -> void:
	# Bounded placard boards on posts in the pen
	var positions: Array[Vector3] = [
		Vector3(-16.0, 1.2, -30.9),
		Vector3(-12.0, 1.2, -30.9),
		Vector3(-8.0, 1.2, -30.9),
		Vector3(-4.0, 1.2, -30.9),
		Vector3(12.0, 1.2, -28.1),
	]
	var labels: Array[String] = ["Placard04", "Placard12", "Placard44", "Placard71", "Placard67"]
	for i: int in range(positions.size()):
		var placard := _box(labels[i], positions[i], Vector3(0.5, 0.6, 0.04), Color("e8e0c2"))
		_placards.append(placard)

func apply_state(state: Dictionary) -> void:
	if state.get("id") != MissionState.M15_ID or not state.get("m15") is Dictionary:
		return
	state_applied += 1
	var progress: Dictionary = state["m15"]
	var broadcast: bool = progress.get("broadcast_taken") == true
	if broadcast and not _notice_fired:
		_notice_fired = true
		_broadcast_taken = true
		notice_requested.emit(tr("M15_BROADCAST_TAKEN"))
