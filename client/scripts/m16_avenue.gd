class_name M16Avenue
extends Node3D

## Freedom of Movement ceremonial avenue presenter.
signal notice_requested(text: String)

var _geometry: Dictionary = {}
var _signals: Array[MeshInstance3D] = []
var _checkpoint_lifted: bool = false
var _bus_freed: bool = false
var _doors_open: bool = false
var _checkpoint_notice_fired: bool = false
var _bus_notice_fired: bool = false
var _doors_notice_fired: bool = false
## Every light on the avenue goes green for the ride. Mara did not do it.
var _green_notice_fired: bool = false
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	_signals.clear()
	_checkpoint_lifted = false
	_bus_freed = false
	_doors_open = false
	_checkpoint_notice_fired = false
	_bus_notice_fired = false
	_doors_notice_fired = false
	_green_notice_fired = false
	state_applied = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m16") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_build_signals()

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

func _build_signals() -> void:
	# Bounded signal heads on avenue gantry posts
	var positions: Array[Vector3] = [
		Vector3(-36.0, 2.8, 4.5),
		Vector3(-28.0, 2.8, 4.5),
		Vector3(-18.0, 2.8, 4.5),
		Vector3(0.0, 2.8, 4.5),
		Vector3(22.0, 2.8, 4.5),
	]
	for i: int in range(positions.size()):
		var sig := _box("Signal_%d" % i, positions[i], Vector3(0.4, 0.8, 0.3), Color("c49a45"))
		_signals.append(sig)

func apply_state(state: Dictionary) -> void:
	if state.get("id") != MissionState.M16_ID or not state.get("m16") is Dictionary:
		return
	state_applied += 1
	var progress: Dictionary = state["m16"]
	var lifted: bool = progress.get("checkpoint_lifted") == true
	var freed: bool = progress.get("bus_freed") == true
	var open: bool = progress.get("doors_open") == true

	if lifted and not _checkpoint_notice_fired:
		_checkpoint_notice_fired = true
		_checkpoint_lifted = true
		notice_requested.emit(tr("M16_CHECKPOINT_LIFTED"))

	if freed and not _bus_notice_fired:
		_bus_notice_fired = true
		_bus_freed = true
		notice_requested.emit(tr("M16_BUS_RELEASED"))

	if open and not _doors_notice_fired:
		_doors_notice_fired = true
		_doors_open = true
		notice_requested.emit(tr("M16_CHAMBER_DOORS_OPEN"))

	# Update traffic signal lights if green wave is active
	var challenges: Dictionary = progress.get("challenges", {})
	if challenges.get("green_wave_triggered") == true and not _green_notice_fired:
		_green_notice_fired = true
		notice_requested.emit(tr("M16_MARA_NOT_US"))
	if challenges.get("green_wave_triggered") == true:
		for sig: MeshInstance3D in _signals:
			if sig.material_override is StandardMaterial3D:
				(sig.material_override as StandardMaterial3D).albedo_color = Color("2ed158")
