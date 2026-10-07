class_name M11Tender
extends Node3D

## Anonymous people remain in their authored hold. Release is not evacuation.
var _geometry: Dictionary = {}
var _people: Array[Sprite3D] = []
var _carrier: Node3D
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	state_applied = 0
	for figure: Sprite3D in _people:
		remove_child(figure)
		figure.queue_free()
	_people.clear()
	if is_instance_valid(_carrier):
		remove_child(_carrier)
		_carrier.queue_free()
	_carrier = null

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m11") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_build_carrier()
	var shades: Array[Color] = [Color("a9b0a2"), Color("c2a087"), Color("9cabb9")]
	for index: int in range(info["m11"]["transfer_people"].size()):
		var figure: Sprite3D = Sprite3D.new()
		figure.name = "TransferPerson%d" % index
		figure.texture = load(PlayerBody.strip_path(PlayerBody.HUMAN)) as Texture2D
		figure.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
		figure.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
		figure.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		figure.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		figure.layers = ArenaSky.ACTOR_LAYERS
		figure.modulate = shades[index]
		var feet: Array = info["m11"]["transfer_people"][index]
		figure.position = Vector3(float(feet[0]), float(feet[1]) + EnemyAnimation.CENTRE_HEIGHT, float(feet[2]))
		add_child(figure)
		_people.append(figure)

func _build_carrier() -> void:
	# The sealed observation panes look onto the nearby civilian hull. This is
	# scenery outside the playable pressure shell, never an alternate floor.
	_carrier = Node3D.new()
	_carrier.name = "CarrierOutside"
	add_child(_carrier)
	var enamel: Material = ArenaMaterials.authored("enamel", "common_carrier")
	var steel: Material = ArenaMaterials.authored("service_steel", "common_carrier")
	_carrier_part("Hull", Vector3(10, 9.6, 57), Vector3(-27, 3.0, 0), enamel)
	_carrier_part("Bow", Vector3(7.5, 7.2, 5), Vector3(-27.8, 2.0, -30.5), steel)
	_carrier_part("Stern", Vector3(8, 7.2, 4), Vector3(-27.5, 2.0, 30), steel)
	for deck: int in range(3):
		_carrier_part("Deck%d" % deck, Vector3(0.08, 0.18, 56), Vector3(-21.95, -0.3 + deck * 2.8, 0), steel)
		for bay: int in range(6):
			var glass: StandardMaterial3D = StandardMaterial3D.new()
			glass.albedo_color = Color("bfac76") if posmod(deck + bay, 3) != 0 else Color("46595b")
			glass.emission_enabled = true
			glass.emission = glass.albedo_color * 0.3
			_carrier_part("Window%d_%d" % [deck, bay], Vector3(0.12, 0.8, 3.5), Vector3(-21.9, 0.8 + deck * 2.8, -23 + bay * 9), glass)
	for station: float in [-27.5, 27.5]:
		_carrier_part("Coupling%d" % int(station), Vector3(4, 2.5, 2.5), Vector3(-20, 1.5 if station < 0 else 2.7, station), steel)

func _carrier_part(label: String, size: Vector3, position: Vector3, material: Material) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = label
	part.layers = ArenaSky.WORLD_LAYERS
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	part.material_override = material
	_carrier.add_child(part)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M11_ID \
		or not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	state_applied += 1
	# No arrival or later identity is inferred from opening a release panel.
	for figure: Sprite3D in _people:
		figure.visible = state["phase"] != "departed"
