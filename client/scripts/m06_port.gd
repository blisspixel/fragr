class_name M06Port
extends Node3D

## Registered pressure windows, possessions and flush maintenance detail.
## Residents and Tern are provisional static art, never simulated participants.
var _root: Node3D
var _geometry: Dictionary = {}
var residents: Array[Sprite3D] = []
var _service_lamp: MeshInstance3D
var _water_material: ShaderMaterial
var _water_seconds: float = 0.0

func clear_map() -> void:
	_geometry.clear()
	residents.clear()
	_service_lamp = null
	_water_material = null
	_water_seconds = 0.0
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m06") is Dictionary or not MapGeometry.validation_error(info).is_empty() \
		or not MissionState.map_error(info).is_empty():
		return
	_root = Node3D.new()
	_root.name = "LunarPortDetails"
	add_child(_root)
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"]["solids"]
	for index: int in range(solids.size()):
		if surfaces[index] == "inspection_glass":
			_window_frame(solids[index])
	for detail: Dictionary in info["presentation"]["decorations"]:
		var host: Dictionary = solids[int(detail["solid"])]
		var transform: Transform3D = MapDecoration.placement(host, detail)
		match detail["kind"]:
			"m06_family_window":
				_family_room(host, transform.basis.z)
			"m06_service_six":
				_service_lamp = _box("ServiceRouteLamp", transform.origin + transform.basis.x * 0.8,
					Vector3(0.12, 0.12, 0.08), Color("737c70"))
			"m06_dust_declaration":
				var foot: Vector3 = transform.origin + transform.basis.z * 0.6
				foot.y = MoveStep.solid_bottom(host) + 0.014
				for strip: int in range(5):
					var line: MeshInstance3D = _box("DustTrap", foot + transform.basis.x * (float(strip) - 2.0) * 0.25,
						Vector3(0.10, 0.012, 0.8), Color("6d776e"))
					line.rotation.y = transform.basis.get_euler().y
			"m06_rail_confiscation":
				var seal: MeshInstance3D = _box("DestructionSeal", transform.origin + transform.basis.x * 0.7,
					Vector3(0.1, 0.45, 0.024), Color("923b32"))
				seal.basis = transform.basis
	_geometry = M06MissionState.geometry_for(info)
	ArenaSky.mark_world(self)

func _window_frame(host: Dictionary) -> void:
	var low: Vector3 = Vector3(float(host.min_x), MoveStep.solid_bottom(host), float(host.min_z))
	var high: Vector3 = Vector3(float(host.max_x), MoveStep.solid_top(host), float(host.max_z))
	var x: float = high.x + 0.018 if low.x < 0 else low.x - 0.018
	for z: float in [low.z, high.z]:
		_box("PressureSeal", Vector3(x, (low.y + high.y) * 0.5, z), Vector3(0.045, high.y - low.y, 0.14), Color("79847c"))
	for y: float in [low.y + 0.07, high.y - 0.07]:
		_box("PressureSeal", Vector3(x, y, (low.z + high.z) * 0.5), Vector3(0.045, 0.14, high.z - low.z), Color("79847c"))
	var sections: int = maxi(1, floori((high.z - low.z) / 5.0))
	for index: int in range(1, sections):
		_box("PressureMullion", Vector3(x, (low.y + high.y) * 0.5, lerpf(low.z, high.z, float(index) / sections)),
			Vector3(0.04, high.y - low.y, 0.1), Color("899286"))

func _family_room(host: Dictionary, outward: Vector3) -> void:
	var centre: Vector3 = Vector3((float(host.min_x) + float(host.max_x)) * 0.5, 0,
		(float(host.min_z) + float(host.max_z)) * 0.5) - outward * 3.0
	_box("FamilyFloor", centre + Vector3(0, 0.008, 0), Vector3(5.3, 0.016, 12), Color("867f6d"))
	_box("PossessionsBench", centre + Vector3(-1, 0.55, -3), Vector3(1.3, 1.1, 3), Color("746e61"))
	for index: int in range(4):
		_box("PersonalStorage", centre + Vector3(-1, 1.25, -4.0 + index * 0.65), Vector3(0.8, 0.3, 0.5),
			[Color("b09674"), Color("749284"), Color("a27b62"), Color("c6bea0")][index])
	_box("MealTable", centre + Vector3(0.2, 0.78, 1.8), Vector3(2.0, 0.12, 1.4), Color("b8aa87"))
	_box("FamilyTaskLamp", centre + Vector3(0, 3.3, 1.8), Vector3(1.2, 0.06, 0.28), Color("d8c69d"))
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "FamilyWarmLight"
	light.position = centre + Vector3(0, 3.15, 1.8)
	light.light_color = Color("ffe2ad")
	light.light_energy = 1.2
	light.omni_range = 8.0
	light.light_cull_mask = 2
	light.add_to_group(ArenaSky.PRACTICAL_GROUP)
	_root.add_child(light)
	_box("TableSupport", centre + Vector3(0.2, 0.37, 1.8), Vector3(0.35, 0.74, 0.35), Color("707a70"))
	for index: int in range(3):
		_box("MealBowl", centre + Vector3(-0.4 + index * 0.55, 0.90, 1.8), Vector3(0.23, 0.12, 0.23), Color("d0c6a8"))
	# A closed recycling tray makes this small indoor water use explicit.
	_box("RecyclingTray", centre + Vector3(-0.8, 0.92, 4.2), Vector3(1.5, 0.3, 0.65), Color("63796e"))
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "ContainedWater"
	var surface: PlaneMesh = PlaneMesh.new()
	surface.size = Vector2(1.3, 0.48)
	water.mesh = surface
	water.position = centre + Vector3(-0.8, 1.075, 4.2)
	_water_material = ShaderMaterial.new()
	_water_material.shader = preload("res://assets/shaders/arena_water.gdshader")
	_water_material.set_shader_parameter("patch_size", surface.size)
	_water_material.set_shader_parameter("water_color", Color("648d84"))
	_water_material.set_shader_parameter("crest_color", Color("aec5ae"))
	water.material_override = _water_material
	_root.add_child(water)
	var water_label: Label3D = Label3D.new()
	water_label.name = "RecyclingCopy"
	water_label.text = tr("WORLD_M06_RECYCLED_WATER")
	water_label.font = MenuTheme.FONT
	water_label.font_size = 24
	water_label.pixel_size = 0.008
	water_label.position = centre + Vector3(0.7, 1.3, 4.2)
	water_label.rotation.y = PI * 0.5
	water_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_root.add_child(water_label)
	var drawing: MeshInstance3D = MeshInstance3D.new()
	drawing.name = "EarthDrawing"
	var page: QuadMesh = QuadMesh.new()
	page.size = Vector2(1.0, 1.0)
	drawing.mesh = page
	drawing.position = centre + Vector3(-2.0, 2.1, 0)
	drawing.rotation.y = PI * 0.5
	var paper: StandardMaterial3D = MoonBackdrop._material(Color.WHITE)
	var path: String = "res://assets/environment/moon/drawing.png"
	if ResourceLoader.exists(path):
		paper.albedo_texture = load(path) as Texture2D
	drawing.material_override = paper
	_root.add_child(drawing)
	for index: int in range(2):
		var resident: Sprite3D = Sprite3D.new()
		resident.name = "ResidentHuman" if index == 0 else "ResidentAgent"
		resident.texture = load(PlayerBody.strip_path(PlayerBody.HUMAN if index == 0 else PlayerBody.SYNTHETIC)) as Texture2D
		resident.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
		resident.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
		resident.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		resident.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		resident.position = centre + Vector3(0.8, EnemyAnimation.CENTRE_HEIGHT, -0.5 + index * 3.0)
		resident.modulate = Color("d8c6a0") if index == 0 else Color("a9bcac")
		_root.add_child(resident)
		residents.append(resident)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M06_ID \
		or not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	if is_instance_valid(_service_lamp):
		_service_lamp.material_override = MoonBackdrop._material(Color("c3d0ae") if state["m06"]["prisoner_route_marked"] else Color("737c70"))

func _process(delta: float) -> void:
	if _water_material != null:
		_water_seconds = fposmod(_water_seconds + maxf(delta, 0.0), 256.0)
		_water_material.set_shader_parameter("ripple_time", _water_seconds)

func _box(label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	return MoonBackdrop._piece(_root, label, at, size, MoonBackdrop._material(color))
