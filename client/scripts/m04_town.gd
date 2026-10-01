class_name M04Town
extends Node3D

## Town fixtures follow registered server geometry. They never add collision.
var _geometry: Dictionary = {}
var _views: Dictionary[String, Sprite3D] = {}
var _root: Node3D
var _clock: float = 0.0

func clear_map() -> void:
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null
	_geometry.clear()
	_views.clear()
	_clock = 0.0

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m04") is Dictionary or not MapGeometry.validation_error(info).is_empty() \
		or not MissionState.map_error(info).is_empty():
		return
	_root = Node3D.new()
	_root.name = "LowWaterPresentation"
	add_child(_root)
	for decoration: Dictionary in info["presentation"]["decorations"]:
		var solid: Dictionary = info["solids"][int(decoration["solid"])]
		var low: Vector3 = Vector3(float(solid["min_x"]), float(solid.get("bottom", MoveStep.GROUND_Y)), float(solid["min_z"]))
		var high: Vector3 = Vector3(float(solid["max_x"]), float(solid.get("top", MoveStep.WALL_TOP)), float(solid["max_z"]))
		var center: Vector3 = (low + high) * 0.5
		match decoration["kind"]:
			"m04_market_canvas":
				_canvas(low, high)
			"m04_water_tank":
				_tank(low, high)
			"m04_tram_vote":
				for index: int in range(4):
					_box("TramWindow", Vector3(low.x - 0.025, center.y + 0.25, lerpf(low.z + 0.6, high.z - 0.6, float(index) / 3.0)),
						Vector3(0.04, 0.75, 0.85), Color("517576"))
				_box("TramRoof", Vector3(center.x, high.y + 0.04, center.z), Vector3(high.x - low.x, 0.08, high.z - low.z), Color("984c37"))
			"m04_clinic_sign":
				_box("ClinicLamp", Vector3(high.x + 0.05, high.y - 0.15, center.z), Vector3(0.08, 0.15, high.z - low.z), Color("c5d7b1"))
			"m04_workshop":
				_box("WorkshopGantry", Vector3(center.x, high.y + 0.15, center.z), Vector3(0.6, 0.3, high.z - low.z), Color("8d6c43"))
			"m04_paint_locker":
				for index: int in range(3):
					_box("PaintVote", Vector3(lerpf(low.x + 0.12, high.x - 0.12, float(index) / 2.0), high.y - 0.28, high.z + 0.03),
						Vector3(0.16, 0.35, 0.04), [Color("a76343"), Color("5f8a85"), Color("baa26a")][index])
			"m04_field_printer":
				for index: int in range(3):
					_box("PrinterPaper", Vector3(center.x + float(index) * 0.2, high.y + 0.015 + float(index) * 0.018, center.z),
						Vector3(0.6, 0.015, 0.9), Color("d1cbb4"))
	for index: int in range(info["m04"]["patients"].size()):
		var patient: Dictionary = info["m04"]["patients"][index]
		var view: Sprite3D = Sprite3D.new()
		view.name = "Patient_" + patient["id"]
		view.texture = load(PlayerBody.strip_path(PlayerBody.HUMAN if index % 2 == 0 else PlayerBody.SYNTHETIC)) as Texture2D
		view.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
		view.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		view.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		view.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
		view.modulate = Color("c5c2af")
		view.position = _feet(patient["held"]) + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
		view.set_meta("walked", 0.0)
		view.set_meta("last_move_ms", -1000)
		_root.add_child(view)
		_views[patient["id"]] = view
	_geometry = MissionState.geometry_for(info)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.is_empty() \
		or not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	for patient: Dictionary in state["m04"]["patients"]:
		if not _views.has(patient["id"]) or not is_instance_valid(_views[patient["id"]]):
			return
	for patient: Dictionary in state["m04"]["patients"]:
		var view: Sprite3D = _views[patient["id"]]
		var next: Vector3 = _feet(patient["feet"]) + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
		var distance: float = view.position.distance_to(next)
		if distance > 0.001:
			view.set_meta("walked", float(view.get_meta("walked")) + distance)
			view.set_meta("last_move_ms", Time.get_ticks_msec())
		view.position = next
		view.modulate = Color("e8e2d6") if state["m04"]["patients_released"] else Color("c5c2af")

func _process(delta: float) -> void:
	_clock += delta
	for view: Sprite3D in _views.values():
		var moving: bool = Time.get_ticks_msec() - int(view.get_meta("last_move_ms")) < 150
		view.frame = PlayerBody.frame(_clock, float(view.get_meta("walked")), 2.0 if moving else 0.0)

func _canvas(low: Vector3, high: Vector3) -> void:
	var colors: Array[Color] = [Color("bead80"), Color("965b42"), Color("6e8980"), Color("ae985e")]
	var width: float = (high.x - low.x) / 8.0
	for index: int in range(8):
		var shade: Color = colors[(int(absf(low.x + low.z)) + index % 2) % colors.size()]
		_box("CanvasStripe", Vector3(low.x + width * (float(index) + 0.5), high.y + 0.025, (low.z + high.z) * 0.5),
			Vector3(width, 0.04, high.z - low.z), shade)
		_box("CanvasHem", Vector3(low.x + width * (float(index) + 0.5), high.y - 0.12, low.z - 0.02),
			Vector3(width, 0.24, 0.04), shade.darkened(0.1))

func _tank(low: Vector3, high: Vector3) -> void:
	var center: Vector3 = (low + high) * 0.5
	var radius: float = minf(high.x - low.x, high.z - low.z) * 0.42
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "CommunalWaterTank"
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.2
	cylinder.radial_segments = 12
	body.mesh = cylinder
	body.position = Vector3(center.x, high.y + 0.6, center.z)
	body.material_override = _material(Color("6e8980"))
	body.layers = ArenaSky.WORLD_LAYERS
	_root.add_child(body)
	for height: float in [0.15, 1.0]:
		var band: MeshInstance3D = MeshInstance3D.new()
		band.name = "TankBand"
		var ring: CylinderMesh = CylinderMesh.new()
		ring.top_radius = radius + 0.025
		ring.bottom_radius = radius + 0.025
		ring.height = 0.09
		ring.radial_segments = 12
		band.mesh = ring
		band.position = Vector3(center.x, high.y + height, center.z)
		band.material_override = _material(Color("a6a18d"))
		band.layers = ArenaSky.WORLD_LAYERS
		_root.add_child(band)

func _box(label: String, position_value: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "%s_%d" % [label, _root.get_child_count()]
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = _material(color)
	instance.layers = ArenaSky.WORLD_LAYERS
	_root.add_child(instance)
	return instance

static func _feet(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
