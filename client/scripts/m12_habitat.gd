class_name M12Habitat
extends Node3D

## The accepted habitat state owns release and aid. This node only presents it.
var _geometry: Dictionary = {}
var _people: Array[CivilianFigure] = []
var _pumps: Array[MeshInstance3D] = []
var _aid: Node3D
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	state_applied = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_people.clear()
	_pumps.clear()
	_aid = null

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m12") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	var g: Dictionary = info["m12"]
	var shades: Array[Color] = [Color("a9b0a2"),Color("c2a087"),Color("9cabb9")]
	for group: String in ["shelter_people","workers"]:
		for index: int in range(3):
			var person := CivilianFigure.new()
			person.name = ("ShelterPerson" if group == "shelter_people" else "UtilityWorker") + str(index)
			person.configure("anonymous",shades[index])
			add_child(person)
			var p: Array = g[group][index]
			person.place_feet(Vector3(float(p[0]),float(p[1]),float(p[2])))
			_people.append(person)
	for pump: Dictionary in g["pumps"]:
		var host: Dictionary = info["solids"][int(pump["solids"][0])]
		var lens := MeshInstance3D.new()
		lens.name = "PumpCondition" + str(pump["id"]).capitalize()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5,0.2,0.025)
		lens.mesh = mesh
		lens.layers = ArenaSky.WORLD_LAYERS
		lens.position = Vector3((float(host["min_x"])+float(host["max_x"]))*0.5,1.8,float(host["min_z"])-0.025)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("91aa7c")
		material.emission_enabled = true
		material.emission = material.albedo_color*0.2
		lens.material_override = material
		add_child(lens)
		_pumps.append(lens)
	_aid = Node3D.new()
	_aid.name = "MutualAidSupplies"
	add_child(_aid)
	_aid.visible = false
	for index: int in range(3):
		var case := MeshInstance3D.new()
		case.name = "SupplyCase" + str(index)
		case.layers = ArenaSky.WORLD_LAYERS
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.55,0.35,0.7)
		case.mesh = mesh
		case.position = Vector3(-8.3+index*0.8,1.675,33.5)
		case.material_override = ArenaMaterials.authored("service_steel","mars_habitat")
		_aid.add_child(case)
	# Fit the occupied west doorway jamb and the depot's south-facing rear wall.
	_sign("Shelter", "M12_SHELTER_SIGN", Vector3(19.98,2.15,28.85), -PI/2.0, Vector2(1.55,0.7))
	_sign("MutualAid", "M12_AID_SIGN", Vector3(0.0,3.45,34.68), PI, Vector2(4.2,0.75))

func _sign(label: String,key: String,at: Vector3,yaw: float,size: Vector2) -> void:
	var sign := WorldSign.new()
	sign.name = label
	sign.configure(key,size*Vector2(0.86,0.74),MenuTheme.BONE)
	sign.position = at
	sign.rotation.y = yaw
	sign.layers = ArenaSky.WORLD_LAYERS
	sign.no_depth_test = false
	add_child(sign)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var mesh := QuadMesh.new()
	mesh.size = size
	plate.mesh = mesh
	plate.position.z = -0.008
	plate.layers = ArenaSky.WORLD_LAYERS
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("343d3d")
	material.roughness = 0.95
	plate.material_override = material
	sign.add_child(plate)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M12_ID or not MissionState.validation_error({"tick":EquipmentState.MAX_EXACT_INTEGER,"state":state},_geometry).is_empty():
		return
	state_applied += 1
	var facts: Dictionary = state["m12"]
	var health: Array = facts["challenges"]["pump_health"]
	for index: int in range(_pumps.size()):
		var material: StandardMaterial3D = _pumps[index].material_override
		material.albedo_color = Color("91aa7c") if int(health[index]) == 100 else Color("d2a65a") if int(health[index]) > 0 else Color("a94d46")
		material.emission = material.albedo_color*0.2
	if is_instance_valid(_aid):
		_aid.visible = facts["aid_vehicle_ids"].size() == 2
	for person: CivilianFigure in _people:
		person.visible = state["phase"] != "departed"
