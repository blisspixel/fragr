class_name M18Transit
extends Node3D

## All Systems Normal transit and evacuation concourse presenter.
signal notice_requested(text: String)

var _geometry: Dictionary = {}
var _gate_light: MeshInstance3D = null
var _roadblock_marker: MeshInstance3D = null
var _aid_delivered: bool = false
var _square_defended: bool = false
var _collector_neutralized: bool = false
var _overlook_witnessed: bool = false
var _concourse_secured: bool = false
var _aid_notice_fired: bool = false
var _square_notice_fired: bool = false
var _collector_notice_fired: bool = false
var _overlook_notice_fired: bool = false
var _concourse_notice_fired: bool = false
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	_gate_light = null
	_roadblock_marker = null
	_aid_delivered = false
	_square_defended = false
	_collector_neutralized = false
	_overlook_witnessed = false
	_concourse_secured = false
	_aid_notice_fired = false
	_square_notice_fired = false
	_collector_notice_fired = false
	_overlook_notice_fired = false
	_concourse_notice_fired = false
	state_applied = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m18") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_build_transit_visuals()

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

func _build_transit_visuals() -> void:
	# Warning barricade light at clinic roadblock
	_roadblock_marker = _box("RoadblockMarker", Vector3(-4.0, 4.6, 0.0), Vector3(10.0, 0.3, 0.4), Color("e0633b"))
	# Concourse departure gate clearance light at x=61.0, y=8.8, z=0.0
	_gate_light = _box("ConcourseGateLight", Vector3(61.0, 8.8, 0.0), Vector3(2.0, 0.3, 0.4), Color("c49a45"))

func apply_state(state: Dictionary) -> void:
	if state.get("id") != MissionState.M18_ID or not state.get("m18") is Dictionary:
		return
	state_applied += 1
	var progress: Dictionary = state["m18"]
	var challenges: Dictionary = progress.get("challenges", {})
	var aid: bool = progress.get("aid_delivered") == true or challenges.get("aid_delivered") == true
	var square: bool = challenges.get("square_defended") == true or progress.get("square_defended") == true
	var collector: bool = challenges.get("collector_neutralized") == true or progress.get("collector_neutralized") == true
	var overlook: bool = progress.get("overlook_witnessed") == true or challenges.get("overlook_witnessed") == true
	var concourse: bool = progress.get("concourse_secured") == true or challenges.get("concourse_secured") == true

	if aid and not _aid_notice_fired:
		_aid_notice_fired = true
		_aid_delivered = true
		notice_requested.emit(tr("M18_AID_DELIVERED"))

	if square and not _square_notice_fired:
		_square_notice_fired = true
		_square_defended = true
		notice_requested.emit(tr("M18_SQUARE_DEFENDED"))

	if collector and not _collector_notice_fired:
		_collector_notice_fired = true
		_collector_neutralized = true
		notice_requested.emit(tr("M18_COLLECTOR_NEUTRALIZED"))

	if overlook and not _overlook_notice_fired:
		_overlook_notice_fired = true
		_overlook_witnessed = true
		notice_requested.emit(tr("M18_OVERLOOK_WITNESSED"))

	if concourse and not _concourse_notice_fired:
		_concourse_notice_fired = true
		_concourse_secured = true
		if _gate_light != null and _gate_light.material_override is StandardMaterial3D:
			(_gate_light.material_override as StandardMaterial3D).albedo_color = Color("2ed158")
		notice_requested.emit(tr("M18_CONCOURSE_SECURED"))
