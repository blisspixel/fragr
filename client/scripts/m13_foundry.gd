class_name M13Foundry
extends Node3D

## Civilians, restraints and work lights follow accepted server facts.
var _geometry: Dictionary = {}
var _people: Array[CivilianFigure] = []
var _restraints: Array[Node3D] = []
var _overseer: CivilianFigure
var _baton: MeshInstance3D
var _hazard: MeshInstance3D
var _hazard_label: WorldSign
var _relay: MeshInstance3D
## The active relay's lamp beats the custody depot's rhythm, three short and
## one long; disabled, it is dark.
var _relay_live: bool = false
var _relay_clock: float = 0.0
var _relay_label: WorldSign
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	_people.clear()
	_restraints.clear()
	_overseer = null
	_baton = null
	_hazard = null
	_hazard_label = null
	_relay = null
	_relay_live = false
	_relay_label = null
	state_applied = 0
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

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
	material.roughness = 0.95
	node.material_override = material
	add_child(node)
	return node

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m13") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	var g: Dictionary = _geometry["m13"]
	var colors: Array[Color] = [Color("b4ad96"), Color("879b9a"), Color("c2a087")]
	for index: int in range(3):
		var person := CivilianFigure.new()
		person.name = "FoundryWorker%d" % index
		person.configure("anonymous_synthetic", colors[index])
		add_child(person)
		person.place_feet(GrenadeFacts.vector(g["workers"][index]))
		_people.append(person)
		var restraint := Node3D.new()
		restraint.name = "Restraint%d" % index
		restraint.position = person.position
		add_child(restraint)
		# A bounded mechanical waist restraint stays inside the existing body.
		# Four sides remain readable when the retained civilian strip turns.
		for side: int in range(4):
			var front: bool = side < 2
			var sign_at: float = -1.0 if side % 2 == 0 else 1.0
			var at: Vector3 = Vector3(0.0,1.05,sign_at*0.2) if front else Vector3(sign_at*0.38,1.05,0.0)
			var size: Vector3 = Vector3(0.85,0.14,0.09) if front else Vector3(0.09,0.14,0.45)
			var band: MeshInstance3D = _box("Band%d" % side,at,size,Color("c1a05b"))
			remove_child(band)
			restraint.add_child(band)
		_restraints.append(restraint)
	_overseer = CivilianFigure.new()
	_overseer.name = "SurrenderedOverseer"
	_overseer.configure("anonymous", Color("6c6664"))
	add_child(_overseer)
	_overseer.place_feet(GrenadeFacts.vector(g["overseer"]))
	_overseer.visible = true
	_baton = _box("DroppedBaton", _overseer.position+Vector3(0.55,0.06,0.0), Vector3(0.09,0.09,0.65), Color("252a2b"))
	_baton.position = _overseer.position+Vector3(0.45,0.9,0.0)
	var low: Vector3 = GrenadeFacts.vector(g["hazard"]["min"])
	var high: Vector3 = GrenadeFacts.vector(g["hazard"]["max"])
	_hazard = _box("MachineCycleIndicator", Vector3((low.x+high.x)*0.5,low.y+0.015,(low.z+high.z)*0.5), Vector3(high.x-low.x,0.025,high.z-low.z), Color("595c4c"))
	_hazard_label = WorldSign.new()
	_hazard_label.name = "MachineCycleFloorLabel"
	_hazard_label.configure("M13_HAZARD_IDLE", Vector2(high.x-low.x-0.3,0.5),WorldSign.PANEL_TEXT)
	_hazard_label.position = _hazard.position+Vector3(0.0,0.017,0.0)
	_hazard_label.rotation.x = -PI*0.5
	_hazard_label.layers = ArenaSky.WORLD_LAYERS
	add_child(_hazard_label)
	var relay: Dictionary = info["solids"][int(g["relay"])]
	var face := Vector3(float(relay["max_x"])+0.018,(float(relay["bottom"])+float(relay["top"]))*0.5,(float(relay["min_z"])+float(relay["max_z"]))*0.5)
	_relay = _box("RelayIndicator",face,Vector3(0.025,0.65,1.35),Color("91aa7c"))
	_relay_label = WorldSign.new()
	_relay_label.name = "RelayFaceLabel"
	_relay_label.configure("M13_RELAY_ACTIVE",Vector2(1.2,0.45),WorldSign.PANEL_INK)
	_relay_label.position = face+Vector3(0.017,0.0,0.0)
	_relay_label.rotation.y = PI*0.5
	_relay_label.layers = ArenaSky.WORLD_LAYERS
	add_child(_relay_label)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M13_ID or not state.get("m13") is Dictionary:
		return
	var p: Dictionary = state["m13"]
	var tick: Variant = p.get("lift", {}).get("tick")
	if not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) or not M13MissionState.validation_error({"tick":tick,"state":state},_geometry).is_empty():
		return
	state_applied += 1
	var released: bool = p["challenges"].has("workers")
	for index: int in range(3):
		_people[index].place_feet(GrenadeFacts.vector(p["worker_feet"][index]))
		_restraints[index].visible = not released
	_overseer.visible = state["phase"] != "briefing"
	_baton.visible = _overseer.visible
	_baton.position = _overseer.position+(Vector3(0.55,0.06,0.0) if p["overseer_surrendered"] else Vector3(0.45,0.9,0.0))
	var warning: Color = Color("d2a65a") if p["hazard_phase"] == "warning" else Color("d87846") if p["hazard_phase"] == "active" else Color("595c4c")
	(_hazard.material_override as StandardMaterial3D).albedo_color = warning
	var key: String = "M13_HAZARD_"+str(p["hazard_phase"]).to_upper()
	if _hazard_label.message_key != key:
		_hazard_label.configure(key,_hazard_label.bounds,WorldSign.PANEL_TEXT)
	_relay_live = not p["relay_disabled"]
	(_relay.material_override as StandardMaterial3D).albedo_color = Color("343d3d") if p["relay_disabled"] else Color("91aa7c")
	var relay_key: String = "M13_RELAY_OFFLINE" if p["relay_disabled"] else "M13_RELAY_ACTIVE"
	if _relay_label.message_key != relay_key:
		_relay_label.configure(relay_key,_relay_label.bounds,WorldSign.PANEL_TEXT if p["relay_disabled"] else WorldSign.PANEL_INK)

func _process(delta: float) -> void:
	if _relay == null or not _relay_live or not _relay.material_override is StandardMaterial3D:
		return
	_relay_clock = fposmod(_relay_clock + clampf(delta, 0.0, 0.1), M08Archive.noise_period())
	(_relay.material_override as StandardMaterial3D).albedo_color = Color("91aa7c") if M08Archive.noise_lit(_relay_clock) else Color("4b5944")
