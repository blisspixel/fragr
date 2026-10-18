class_name M17Office
extends Node3D

## Peace Without Interruption Forever Office presenter.
signal notice_requested(text: String)

var _geometry: Dictionary = {}
var _core_seal_light: MeshInstance3D = null
var _kessel_secured: bool = false
var _core_unsealed: bool = false
var _voss_captured: bool = false
var _kessel_notice_fired: bool = false
var _core_notice_fired: bool = false
var _voss_notice_fired: bool = false
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	_core_seal_light = null
	_kessel_secured = false
	_core_unsealed = false
	_voss_captured = false
	_kessel_notice_fired = false
	_core_notice_fired = false
	_voss_notice_fired = false
	state_applied = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m17") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_build_office_visuals()

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

func _build_office_visuals() -> void:
	# Core seal indicator bar over the security bulkhead at z=18.0
	_core_seal_light = _box("CoreSealLight", Vector3(0.0, 3.8, 18.0), Vector3(6.0, 0.3, 0.4), Color("c49a45"))

func apply_state(state: Dictionary) -> void:
	if state.get("id") != MissionState.M17_ID or not state.get("m17") is Dictionary:
		return
	state_applied += 1
	var progress: Dictionary = state["m17"]
	var kessel: bool = progress.get("kessel_secured") == true
	var unsealed: bool = progress.get("core_unsealed") == true
	var voss: bool = progress.get("voss_captured") == true

	if kessel and not _kessel_notice_fired:
		_kessel_notice_fired = true
		_kessel_secured = true
		notice_requested.emit(tr("M17_KESSEL_SECURED"))

	if unsealed and not _core_notice_fired:
		_core_notice_fired = true
		_core_unsealed = true
		if _core_seal_light != null and _core_seal_light.material_override is StandardMaterial3D:
			(_core_seal_light.material_override as StandardMaterial3D).albedo_color = Color("2ed158")
		notice_requested.emit(tr("M17_CORE_UNSEALED"))

	if voss and not _voss_notice_fired:
		_voss_notice_fired = true
		_voss_captured = true
		notice_requested.emit(tr("M17_VOSS_CAPTURED"))
