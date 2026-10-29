class_name M13Dressing
extends M12Dressing

## Working foundry: heat shielding, worn machinery and freight, with human
## possessions in the quarters. Process light is amber, never Union tell red.
## All fixtures belong to existing solids or overhead services.
static func foundry_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != 1013 or not info.get("m13") is Dictionary or not info.get("solids") is Array:
		return false
	if not MapGeometry.validation_error(info).is_empty():
		return false
	for pair: Array in [
		[Vector3(-40, 0, -54), Vector3(40, 0.3, 54)],
		[Vector3(-8, 0.3, -53.5), Vector3(-7.6, 4.5, -39)],
		[Vector3(13, 0.3, -36), Vector3(26, 1, -27)],
		[Vector3(-27, 0.3, 10), Vector3(-13, 3.8, 10.4)],
		[Vector3(-8.8, 6.1, 32.5), Vector3(-8, 9.1, 43.5)],
		[Vector3(-5, 3.3, 53), Vector3(5, 13.5, 53.5)]]:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

static func foundry_finish(box: AABB, surface: String) -> Material:
	var p: Vector3 = box.get_center()
	var tint: Color = Color("7e8177")
	var accent: Color = Color("9a885e")
	if surface == "concrete":
		tint = Color("77776d")
	elif surface == "records_tile":
		# The authored furnace and protected pour already carry process glow.
		return ArenaMaterials.authored(surface, "mars_foundry")
	elif surface == "enamel":
		tint = Color("948a74")
		if box.size.y < 0.4 and box.position.y > 3.5:
			tint = Color("5e6661")
			return paint("service_steel", tint, Color("6c7366"), "mars_foundry")
		elif p.z > 1 and p.z < 11:
			tint = Color("8c957f") if p.x < 0 else Color("9e9276")
		elif box.size.y < 1.6:
			tint = Color("938156")
		elif p.z > 27 and absf(p.x) < 10:
			tint = Color("a8987e")
	elif surface == "lift_panel":
		tint = Color("758075")
	else:
		tint = Color("67736d")
	var material: ShaderMaterial = paint(surface, tint, accent, "mars_foundry")
	material.set_shader_parameter("deck_spacing", 16.0)
	return material

static func restyle_foundry(cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not foundry_layout(info) or not info.get("presentation") is Dictionary:
		return
	var surfaces: Array = info["presentation"].get("solids", [])
	if surfaces.size() != views.size() or views.size() != info["solids"].size():
		return
	for index: int in range(views.size()):
		views[index].material_override = foundry_finish(_bounds(info["solids"][index]), str(surfaces[index]))
	var dressing := M13Dressing.new()
	dressing.name = "FoundryDressing"
	cover.add_child(dressing)
	dressing.configure_map(info)
	var foundation: AABB = AABB(Vector3(-40, 0, -54), Vector3(80, 0.3, 108))
	tile_foundation(cover, foundation, foundry_finish(foundation, "concrete"))

func configure_map(info: Dictionary) -> void:
	if active() and foundry_layout(info):
		return
	clear_map()
	if not foundry_layout(info):
		return
	_entrance()
	_machines()
	_people_rooms()
	_freight()
	_ladle()
	_structure()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _entrance() -> void:
	var room: Node3D = _room("Entrance")
	for z: float in [-50, -43]:
		lamp(room, Vector3(0, 4.25, z), 8)
	for index: int in range(7):
		fitting(room, "LockerSeam", Vector3(-7.57, 1.9, -51.5+index*1.4), Vector3(0.025, 2.4, 0.035), Color("555f56"))
		fitting(room, "LockerHandle", Vector3(-7.55, 1.6, -51.2+index*1.4), Vector3(0.04, 0.18, 0.06), Color("aaa183"))
	var furnace: Node3D = _room("Furnace")
	for x: float in [14, 18, 22, 25]:
		fitting(furnace, "ShieldBolt", Vector3(x, 2.05, -26.46), Vector3(0.08, 0.08, 0.04), Color("5a5d50"))
		fitting(furnace, "HoodRib", Vector3(x, 5.79, -26.46), Vector3(0.12, 0.72, 0.06), Color("a29365"))
	for x: float in [15, 24]:
		lamp(furnace, Vector3(x, 5.15, -29), 8, true)
	# Inspection slots and a guarded heat source, inside the existing furnace.
	for index: int in range(9):
		fitting(furnace, "FurnaceLouvre", Vector3(13.7+index*1.45, 3.1, -35.96), Vector3(0.75, 0.08, 0.04), Color("b2955d"))

func _machines() -> void:
	var room: Node3D = _room("MachineHall")
	# Existing modelled lathes remain the centrepiece. Cable trays and work
	# lighting frame their silhouettes without coating them in issued black.
	for z: float in [-22.5, -1.5]:
		for x: float in [-20, -9, 9, 23]:
			lamp(room, Vector3(x, 8.45, z), 10)
			fitting(room, "ServiceDrop", Vector3(x, 7.85, z), Vector3(0.06, 1.2, 0.06), Color("515c54"))
	for x: float in [-9, 9]:
		lamp(room, Vector3(x, 4.0, -13), 8)
	# The consoles are offset from their lathe centres. Keep every key on
	# the actual top, rather than floating beside it in the walking aisle.
	for x: float in [-10.5, 7.5]:
		for index: int in range(4):
			fitting(room, "ControlKey_%s_%d" % [str(x), index], Vector3(x-0.6+index*0.3, 1.33, -7.5), Vector3(0.12, 0.035, 0.14), Color("b7ab81"))
	for x: float in [-3.65, 3.65]:
		for y: float in [0.8, 1.8, 2.8, 3.8, 4.8]:
			fitting(room, "PressBolt", Vector3(x, y, 0.035), Vector3(0.1, 0.1, 0.04), Color("b7a770"))
	lamp(room, Vector3(0, 4.8, -2.5), 7)
	var ring: Node3D = _room("Maintenance")
	for z: float in [-32, -20, -8, 5, 18]:
		lamp(ring, Vector3(-34, 3.95, z), 8)
		fitting(ring, "FeedJoint", Vector3(-37.15, 1.35, z), Vector3(0.05, 2.0, 0.12), Color("a59568"))

func _people_rooms() -> void:
	var quarters: Node3D = _room("Quarters")
	lamp(quarters, Vector3(-20, 3.55, 6), 8, true)
	# Individual possessions don't imply release, safety or a uniform.
	for index: int in range(7):
		wall_pin(quarters, Vector3(-25.5+index*0.6, 2.1, 9.97), PEOPLE_COLOURS[index%4])
	for index: int in range(4):
		fitting(quarters, "SeatCloth", Vector3(-24.8+index*1.5, 0.83, 3.55), Vector3(1.1, 0.05, 0.65), PEOPLE_COLOURS[index%4])
	var office: Node3D = _room("FreightOffice")
	lamp(office, Vector3(20, 3.55, 6), 8)
	for index: int in range(8):
		fitting(office, "DispatchFolder", Vector3(19.3+index*0.65, 1.23, 8.7), Vector3(0.4, 0.04+float(index%3)*0.025, 0.45), Color("b3a27c") if index%2 == 0 else Color("6f806b"))
	# A physical dispatch board: attached forms, no additional prose.
	fitting(office, "DispatchBoard", Vector3(21, 2.4, 9.97), Vector3(4.8, 1.0, 0.035), Color("627260"))
	for index: int in range(8):
		wall_pin(office, Vector3(19+index*0.55, 2.4, 9.94), Color("baac8a"))

func _freight() -> void:
	var room: Node3D = _room("Freight")
	for x: float in [-20, -10, 10, 23]:
		lamp(room, Vector3(x, 7.85, 18.5), 10)
	for x: float in [-17, 15.5]:
		var z: float = 15 if x < 0 else 23
		var top: float = 1.8 if x < 0 else 2.1
		for offset: float in [-1.2, 1.2]:
			fitting(room, "FreightStrap", Vector3(x+offset, top+0.015, z), Vector3(0.1, 0.025, 3.95), Color("a58b4f"))
			fitting(room, "FreightStrapFace", Vector3(x+offset, (top+0.3)*0.5, z-2.02), Vector3(0.1, top-0.3, 0.025), Color("a58b4f"))

func _ladle() -> void:
	var room: Node3D = _room("Ladle")
	for x: float in [-23.5, 23.5]:
		for z: float in [29, 38, 49]:
			lamp(room, Vector3(x, 7.0, z), 9)
	for x: float in [-8.85, 8.85]:
		for z: float in [33.5, 35.5, 37.5, 39.5, 41.5]:
			fitting(room, "LadleBrace", Vector3(x, 7.6, z), Vector3(0.09, 2.8, 0.18), Color("9a895f"))
	# Suspended service fixtures use fine hangers up to the existing roof.
	for x: float in [-23.5, 23.5]:
		for z: float in [29, 38, 49]:
			fitting(room, "LampHanger", Vector3(x, 10.5, z), Vector3(0.035, 7, 0.035), Color("545f56"))
	var lift: Node3D = _room("Lift")
	for y: float in [5, 8, 11]:
		lamp(lift, Vector3(0, y, 52.9), 6)
		fitting(lift, "LandingMark", Vector3(4.57, y-0.3, 52), Vector3(0.025, 0.12, 1.5), Color("b4a269"))

## High services explain the factory's scale; floor paint explains how its
## existing machines are used. Neither can masquerade as new combat cover.
func _structure() -> void:
	var room: Node3D = _room("Structure")
	for z: float in [-35, -27, -19, -11, -3, 5, 13, 23]:
		fitting(room, "RoofRib", Vector3(5.25, 9.58, z), Vector3(68.3, 0.4, 0.22), Color("66715f"))
		for x: float in [-28.75, 39.25]:
			fitting(room, "RibAnchor", Vector3(x, 9.1, z), Vector3(0.3, 1.0, 0.65), Color("7d806a"))
	for x: float in [-15, 17]:
		_shape.rod(_props(room), "ServicePipe", Vector3(x, 9.3, -38), Vector3(x, 9.3, 26), 0.17, _mat("service_pipe", Color("a29571")), 8)
		for z: float in [-35, -19, -3, 13, 23]:
			fitting(room, "PipeSaddle", Vector3(x, 9.55, z), Vector3(0.46, 0.35, 0.1), Color("56604f"))
	# The marked operating apron stands flush with the foundation, behind
	# each machine's real front. Open walking routes remain visibly open.
	for x: float in [-9, 9]:
		fitting(room, "MachineApron", Vector3(x, 0.313, -7.5), Vector3(6, 0.008, 3), Color("797b61"))
		for offset: float in [-3.1, 3.1]:
			fitting(room, "ApronEdge", Vector3(x+offset, 0.32, -7.5), Vector3(0.08, 0.008, 3.2), Color("b29a57"))
		fitting(room, "LampHanger", Vector3(x, 6.9, -13), Vector3(0.035, 5.8, 0.035), Color("545f56"))
		# Flutes and repair plates stay on the existing head and machine box.
		for index: int in range(7):
			fitting(room, "MachineVent", Vector3(x-2.6+index*0.8, 1.8, -9.97), Vector3(0.45, 0.08, 0.025), Color("424e42"))
		for z: float in [-15, -12]:
			fitting(room, "MachinePlate", Vector3(x+3.015, 1.2, z), Vector3(0.025, 0.7, 0.8), Color("a08f63"))
	for x: float in [-20, 20]:
		for z: float in [-34, -30, -26, -22, -18, -14, -10, -6, -2, 2, 10, 14, 18, 22]:
			fitting(room, "HandlingLane", Vector3(x, 0.32, z), Vector3(0.11, 0.008, 1.7), Color("b39a5a"))
	# Vertical plate seams belong to the enclosing walls, not free-standing
	# geometry. They make the factory read at a larger scale than quarters.
	for z: float in [-46, -34, -22, -10, 2, 14, 26, 38, 50]:
		for x: float in [-39.47, 39.47]:
			fitting(room, "WallJoint", Vector3(x, 5.0, z), Vector3(0.035, 9.3, 0.15), Color("687360"))
	for x: float in [-9, 9]:
		var props: Node3D = _props(room)
		_shape.cylinder(props, "SpindleHousing", 0.4, 0.1, _mat("spindle", Color("a69c7e"), 0.5, 0.6), Vector3(x, 2.75, -11.44), 12)
		_shape.cylinder(props, "SpindleHub", 0.18, 0.13, _mat("spindle_hub", Color("546251"), 0.5, 0.6), Vector3(x, 2.75, -11.38), 8)
		for offset: float in [-1.0, 1.0]:
			fitting(room, "HeadRail", Vector3(x+offset, 2.75, -11.47), Vector3(0.14, 0.8, 0.06), Color("b5a579"))
		for index: int in range(5):
			fitting(room, "HeadDial", Vector3(x-1.5+index*0.25, 2.75, -11.43), Vector3(0.09, 0.14, 0.04), Color("b7b58e"))
