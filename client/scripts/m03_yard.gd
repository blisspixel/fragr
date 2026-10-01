class_name M03Yard
extends Node3D

## Render server-owned captive feet and the registered transmitter solid.
## The existing participant atlas supplies the two captive body silhouettes.
var _geometry: Dictionary = {}
var _views: Dictionary[String, Array] = {}
var _seals: Dictionary[String, Node3D] = {}
var _root: Node3D
var _mast: MeshInstance3D
var _clock: float = 0.0

func clear_map() -> void:
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null
	_mast = null
	_geometry.clear()
	_views.clear()
	_seals.clear()
	_clock = 0.0

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m03") is Dictionary or not MapGeometry.validation_error(info).is_empty() \
		or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_root = Node3D.new()
	_root.name = "YardPresentation"
	add_child(_root)
	for car: Dictionary in info["m03"]["cars"]:
		var pair: Array[Sprite3D] = []
		var seal: Node3D = Node3D.new()
		seal.name = "CarSeal_" + car["id"]
		_root.add_child(seal)
		for index: int in range(2):
			var view: Sprite3D = Sprite3D.new()
			view.name = "Captive_%s_%d" % [car["id"], index]
			view.texture = load(PlayerBody.strip_path(PlayerBody.HUMAN if index == 0 else PlayerBody.SYNTHETIC)) as Texture2D
			view.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
			view.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			view.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			view.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
			view.modulate = Color("b7b3a0")
			view.set_meta("walked", 0.0)
			view.set_meta("last_move_ms", -1000)
			view.position = _feet(car["held"][index]) + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
			_root.add_child(view)
			pair.append(view)
			var cuff: MeshInstance3D = MeshInstance3D.new()
			cuff.name = "Restraint_%d" % index
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(0.7, 0.12, 0.12)
			cuff.mesh = mesh
			cuff.position = _feet(car["held"][index]) + Vector3(0.0, 1.2, 0.18)
			cuff.material_override = _material(Color("bd633d"))
			seal.add_child(cuff)
		_views[car["id"]] = pair
		_seals[car["id"]] = seal
	var solid: Dictionary = info["solids"][int(info["m03"]["mast"]["solid"])]
	_mast = MeshInstance3D.new()
	_mast.name = "MastStatusLamp"
	var lamp: BoxMesh = BoxMesh.new()
	lamp.size = Vector3(0.3, 0.3, 0.06)
	_mast.mesh = lamp
	_mast.position = Vector3((float(solid["min_x"]) + float(solid["max_x"])) * 0.5,
		(float(solid["bottom"]) + float(solid["top"])) * 0.5, float(solid["min_z"]) - 0.035)
	_mast.material_override = _material(Color("86332b") if info["m03"]["mast_shutdown"] else Color("ed4d30"))
	_root.add_child(_mast)
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "RegisteredPodShell"
	var volume: BoxMesh = BoxMesh.new()
	volume.size = Vector3(float(solid["max_x"]) - float(solid["min_x"]),
		float(solid["top"]) - float(solid["bottom"]), float(solid["max_z"]) - float(solid["min_z"])) + Vector3.ONE * 0.012
	shell.mesh = volume
	shell.position = Vector3((float(solid["min_x"]) + float(solid["max_x"])) * 0.5,
		(float(solid["bottom"]) + float(solid["top"])) * 0.5, (float(solid["min_z"]) + float(solid["max_z"])) * 0.5)
	shell.material_override = _mast.material_override
	shell.layers = ArenaSky.WORLD_LAYERS
	_root.add_child(shell)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.is_empty():
		return
	if not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	for car: Dictionary in state["m03"]["cars"]:
		_seals[car["id"]].visible = not car["released"]
		var views: Array = _views[car["id"]]
		for index: int in range(2):
			var view: Sprite3D = views[index]
			var next: Vector3 = _feet(car["captives"][index]) + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
			var distance: float = view.position.distance_to(next)
			if distance > 0.001:
				view.set_meta("walked", float(view.get_meta("walked")) + distance)
				view.set_meta("last_move_ms", Time.get_ticks_msec())
			view.position = next
			view.modulate = Color("e8e2d6") if car["released"] else Color("b7b3a0")

func _process(delta: float) -> void:
	_clock += delta
	for views: Array in _views.values():
		for view: Sprite3D in views:
			var moving: bool = Time.get_ticks_msec() - int(view.get_meta("last_move_ms")) < 150
			view.frame = PlayerBody.frame(_clock, float(view.get_meta("walked")), 2.0 if moving else 0.0)

static func _feet(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.45
	return material
