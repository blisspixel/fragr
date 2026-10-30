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
		[Vector3(-8, 0.3, -53.5), Vector3(-7.6, 4.5, -43.2)],
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
		tint = Color("857f6e")
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
		tint = Color("5b655e")
	else:
		# Dark industrial frames: presses, posts, columns and gallery decks.
		tint = Color("4a514c")
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
	_process_light()
	_railings(info)
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _entrance() -> void:
	var room: Node3D = _room("Entrance")
	for z: float in [-50, -43]:
		lamp(room, Vector3(0, 4.25, z), 8)
	for index: int in range(6):
		fitting(room, "LockerSeam", Vector3(-7.57, 1.9, -51.5+index*1.4), Vector3(0.025, 2.4, 0.035), Color("555f56"))
		fitting(room, "LockerHandle", Vector3(-7.55, 1.6, -51.2+index*1.4), Vector3(0.04, 0.18, 0.06), Color("aaa183"))
	var furnace: Node3D = _room("Furnace")
	for x: float in [14, 18, 22, 25]:
		fitting(furnace, "ShieldBolt", Vector3(x, 2.05, -26.46), Vector3(0.08, 0.08, 0.04), Color("5a5d50"))
		fitting(furnace, "HoodRib", Vector3(x, 5.79, -26.46), Vector3(0.12, 0.72, 0.06), Color("a29365"))
	for x: float in [15, 24]:
		lamp(furnace, Vector3(x, 5.15, -29), 8, true)
	# The crucible's dark lip and pouring spout frame its protected amber charge.
	for z: float in [-33.55, -29.45]:
		fitting(furnace, "CrucibleLip", Vector3(19.5, 3.7, z), Vector3(4.1, 0.24, 0.1), Color("3b403d"))
	for x: float in [17.45, 21.55]:
		fitting(furnace, "CrucibleLip", Vector3(x, 3.7, -31.5), Vector3(0.1, 0.24, 4.1), Color("3b403d"))
	fitting(furnace, "CrucibleSpout", Vector3(19.5, 3.55, -29.25), Vector3(0.9, 0.3, 0.5), Color("3b403d"))
	# Inspection slots and a guarded heat source, inside the existing furnace.
	for index: int in range(9):
		fitting(furnace, "FurnaceLouvre", Vector3(13.7+index*1.45, 3.1, -35.96), Vector3(0.75, 0.08, 0.04), Color("b2955d"))

func _machines() -> void:
	var room: Node3D = _room("MachineHall")
	# Lathes, presses, pots and the casting conveyor are authoritative solids.
	# Fixtures here only dress their faces, tops and the services above them.
	for z: float in [-22.5, -1.5]:
		for x: float in [-20, -9, 9, 23]:
			lamp(room, Vector3(x, 6.6, z), 10)
			fitting(room, "ServiceDrop", Vector3(x, 8.2, z), Vector3(0.06, 3.2, 0.06), Color("515c54"))
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
	# The press window: worn die faces on the bolster top and ram underside.
	fitting(room, "BolsterDie", Vector3(0, 1.115, -2.75), Vector3(4.2, 0.03, 3.0), Color("8c7a4e"))
	fitting(room, "RamDie", Vector3(0, 2.985, -2.75), Vector3(4.0, 0.03, 2.7), Color("3b4140"))
	for x: float in [-25.0]:
		fitting(room, "WestBolsterDie", Vector3(x, 1.015, -16.5), Vector3(3.0, 0.03, 2.8), Color("8c7a4e"))
		fitting(room, "WestRamDie", Vector3(x, 3.385, -16.5), Vector3(2.6, 0.03, 2.8), Color("3b4140"))
		_shape.rod(_props(room), "WestPressCylinder", Vector3(x, 6.4, -16.5), Vector3(x, 8.7, -16.5), 0.32, _mat("press_cylinder", Color("4c5450"), 0.5, 0.6), 10)
		for z: float in [-18.62, -14.38]:
			for y: float in [1.6, 2.6, 3.6, 4.6]:
				fitting(room, "WestFrameBolt", Vector3(x-1.2, y, z), Vector3(0.1, 0.1, 0.04), Color("b7a770"))
				fitting(room, "WestFrameBolt", Vector3(x+1.2, y, z), Vector3(0.1, 0.1, 0.04), Color("b7a770"))
	# Annealing pot: a protected amber charge, never a Union tell.
	fitting(room, "PotLid", Vector3(-26, 2.62, -7.5), Vector3(2.4, 0.04, 2.4), Color("4a504c"))
	fitting(room, "PotCharge", Vector3(-26, 1.62, -3), Vector3(2.2, 0.03, 2.2), Color("6e5d3e"))
	# Casting conveyor: rollers on the bed and castings riding it into the hood.
	for index: int in range(20):
		fitting(room, "ConveyorRoller", Vector3(24.4+index*0.72, 1.02, -12.8), Vector3(0.12, 0.04, 1.5), Color("3c4441"))
	for x: float in [25.6, 27.8, 36.4]:
		fitting(room, "Casting", Vector3(x, 1.16, -12.8), Vector3(0.7, 0.24, 0.9), Color("6b6250"))
	for z: float in [-14.22, -11.38]:
		for x: float in [30.2, 32, 33.8]:
			fitting(room, "HoodVent", Vector3(x, 2.2, z), Vector3(0.9, 0.08, 0.025), Color("2f3533"))
	lamp(room, Vector3(32, 3.36, -12.8), 7, true)
	for z: float in [-5.8, -3.2]:
		fitting(room, "CoilBand", Vector3(35, 1.52, z), Vector3(3.9, 0.03, 0.12), Color("9a885e"))
	var ring: Node3D = _room("Maintenance")
	for z: float in [-32, -20, -8, 5, 18]:
		lamp(ring, Vector3(-34, 3.95, z), 8)
		fitting(ring, "FeedJoint", Vector3(-37.15, 1.35, z), Vector3(0.05, 2.0, 0.12), Color("a59568"))
	# The service corridor joins the entrance to the ring's south end.
	for x: float in [-34, -24, -14]:
		lamp(ring, Vector3(x, 4.15, -41.45), 8)
	# The town's armoured water main enters here and runs to the ring's
	# protected feed: the corridor exists to carry and service it.
	_shape.rod(_props(ring), "CorridorMain", Vector3(-39.3, 3.4, -43.15), Vector3(-8.4, 3.4, -43.15), 0.3, _mat("water_main", Color("55665f"), 0.4, 0.7), 10)
	_shape.rod(_props(ring), "FeedRiser", Vector3(-37.95, 3.4, -43.15), Vector3(-37.95, 3.4, -31.0), 0.3, _mat("water_main", Color("55665f"), 0.4, 0.7), 10)
	for x: float in [-34.0, -29.0, -24.0, -16.0, -11.0]:
		fitting(ring, "MainCollar", Vector3(x, 3.4, -43.15), Vector3(0.18, 0.7, 0.7), Color("3b403d"))
	lamp(ring, Vector3(-20.5, 4.15, -42.2), 6, true)
	# A valve bank on the main gives the corridor one piece of cover.
	for x: float in [-21.2, -19.8]:
		_shape.rod(_props(ring), "ValveStem", Vector3(x, 1.6, -43.05), Vector3(x, 3.25, -43.05), 0.06, _mat("service_pipe", Color("a29571")), 6)
		_shape.cylinder(_props(ring), "ValveWheel", 0.28, 0.05, _mat("valve_wheel", Color("8f7a45")), Vector3(x, 2.2, -42.95), 10)
	for x: float in [-36, -28, -12]:
		fitting(ring, "CorridorSaddle", Vector3(x, 3.4, -43.42), Vector3(0.12, 0.45, 0.16), Color("56604f"))
	# The maintenance stairwell: a lit, walled climb behind the galleries.
	var stair: Node3D = _room("Stairwell")
	for z: float in [31, 37]:
		lamp(stair, Vector3(-36.18, 5.85, z), 8)
	for z: float in [29.5, 33.5, 37.5]:
		fitting(stair, "StairWallJoint", Vector3(-36.0+0.018, 3.0, z), Vector3(0.035, 5.4, 0.12), Color("687360"))
	for index: int in range(12):
		fitting(stair, "TreadNose", Vector3(-37.75, 0.555+0.25*index, 28.06+index), Vector3(3.4, 0.012, 0.1), Color("b29a57"))
	lamp(stair, Vector3(-32, 2.95, 41.75), 7)

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
		# Vents and repair plates stay on the existing headstock and bed faces.
		var sign: float = signf(x)
		for index: int in range(4):
			fitting(room, "MachineVent", Vector3(sign*10.8, 1.2+index*0.4, -10.985), Vector3(1.6, 0.08, 0.03), Color("424e42"))
		fitting(room, "MachinePlate", Vector3(sign*5.985, 0.8, -13.5), Vector3(0.03, 0.6, 0.8), Color("a08f63"))
	for x: float in [-20, 20]:
		for z: float in [-34, -30, -26, -22, -18, -14, -10, -6, -2, 2, 10, 14, 18, 22]:
			fitting(room, "HandlingLane", Vector3(x, 0.32, z), Vector3(0.11, 0.008, 1.7), Color("b39a5a"))
	# Vertical plate seams belong to the enclosing walls, not free-standing
	# geometry. They make the factory read at a larger scale than quarters.
	for z: float in [-46, -34, -22, -10, 2, 14, 26, 38, 50]:
		for x: float in [-39.47, 39.47]:
			fitting(room, "WallJoint", Vector3(x, 5.0, z), Vector3(0.035, 9.3, 0.15), Color("687360"))
	# Each lathe turns a bar between its headstock chuck and tailstock centre.
	for x: float in [-9, 9]:
		var props: Node3D = _props(room)
		var sign: float = signf(x)
		var face: float = sign*9.6
		_shape.rod(props, "Chuck", Vector3(face, 1.95, -13.5), Vector3(face-sign*0.35, 1.95, -13.5), 0.42, _mat("spindle", Color("a69c7e"), 0.5, 0.6), 12)
		_shape.rod(props, "Workpiece", Vector3(face-sign*0.35, 1.95, -13.5), Vector3(sign*7.4, 1.95, -13.5), 0.1, _mat("spindle_hub", Color("546251"), 0.5, 0.6), 8)
		for index: int in range(5):
			fitting(room, "HeadDial", Vector3(face-sign*0.015, 2.5, -14.4+index*0.25), Vector3(0.04, 0.14, 0.09), Color("b7b58e"))
		fitting(room, "BedWay", Vector3(sign*7.8, 1.265, -13.1), Vector3(3.6, 0.03, 0.14), Color("b5a579"))
		fitting(room, "BedWay", Vector3(sign*7.8, 1.265, -13.9), Vector3(3.6, 0.03, 0.14), Color("b5a579"))

## Process light: hot amber pools where metal is melted, poured and cast.
## It is never red, which stays the Union attack tell, and it lights the
## world layer only, so fighters keep their own readable fill.
const PROCESS_LIGHT: Color = Color(1.0, 0.62, 0.3)
const MOLTEN: Color = Color("e0802e")

func _process_light() -> void:
	var room: Node3D = _room("Process")
	# The crucible and the furnace hearth behind its heat shields.
	_omni(room, "CrucibleGlow", Vector3(19.5, 4.6, -31.5), PROCESS_LIGHT, 6.0, 16.0)
	_omni(room, "HearthGlow", Vector3(19.5, 2.6, -25.6), PROCESS_LIGHT, 3.0, 9.0)
	_sparks(room, "CrucibleSparks", Vector3(19.5, 3.6, -29.1), 0.6)
	# The pour from the great ladle and its protected stream.
	_omni(room, "PourGlow", Vector3(0, 2.2, 31.2), PROCESS_LIGHT, 5.0, 14.0)
	_omni(room, "LadleGlow", Vector3(0, 5.6, 38.0), PROCESS_LIGHT, 4.5, 16.0)
	_sparks(room, "PourSparks", Vector3(0, 0.9, 32.6), 1.0)
	# The mould line takes the pour: molten tops and a low pool of heat.
	for x: float in [-11.5, -6.0]:
		_block(_props(room), "MouldCharge", Vector3(3.2, 0.03, 0.6), _glow("molten", MOLTEN, 1.6), Vector3(x, 1.515, -20.0))
		_omni(room, "MouldGlow", Vector3(x, 2.3, -20.0), PROCESS_LIGHT, 2.6, 7.5)
	for x: float in [-14.0, -3.5]:
		fitting(room, "MouldStop", Vector3(x, 1.1, -20.0), Vector3(0.12, 0.3, 1.3), Color("2f3533"))
	# The annealing pot, the slag pots and the conveyor hood.
	_omni(room, "PotGlow", Vector3(-25.0, 3.4, -7.5), PROCESS_LIGHT, 3.0, 9.0)
	_block(_props(room), "SlagCrust", Vector3(3.6, 0.03, 3.6), _glow("molten", MOLTEN, 1.6), Vector3(33.0, 1.815, 35.0))
	_omni(room, "SlagGlow", Vector3(33.0, 2.8, 35.0), PROCESS_LIGHT, 3.5, 10.0)
	_omni(room, "HoodGlow", Vector3(32.0, 1.6, -12.8), PROCESS_LIGHT, 2.6, 7.0)
	# The overhead crane carries a teeming ladle over the mould line: a
	# glowing pour falls from its lip into the waiting moulds.
	fitting(room, "CraneTrolley", Vector3(-8.75, 7.3, -20.0), Vector3(2.4, 0.6, 1.6), Color("3b403d"))
	for x: float in [-9.2, -8.3]:
		fitting(room, "CraneCable", Vector3(x, 5.7, -20.0), Vector3(0.04, 2.6, 0.04), Color("2a2e2d"))
	fitting(room, "LadleBail", Vector3(-8.75, 4.45, -20.0), Vector3(1.7, 0.1, 0.1), Color("2a2e2d"))
	_block(_props(room), "LadleCharge", Vector3(1.3, 0.03, 1.2), _glow("molten", MOLTEN, 1.6), Vector3(-8.75, 4.415, -20.0))
	fitting(room, "LadleLip", Vector3(-7.85, 3.1, -20.0), Vector3(0.3, 0.2, 0.4), Color("2a2e2d"))
	_block(_props(room), "PourStream", Vector3(0.12, 1.5, 0.12), _glow("molten", MOLTEN, 1.6), Vector3(-7.6, 2.25, -20.0))
	_sparks(room, "MouldSparks", Vector3(-7.6, 1.6, -20.0), 0.5)
	_omni(room, "TeemGlow", Vector3(-8.75, 2.6, -20.0), PROCESS_LIGHT, 3.0, 9.0)
	for z: float in [-20.62, -19.38]:
		fitting(room, "GirderFlange", Vector3(5.2, 8.0, z), Vector3(67.6, 0.12, 0.04), Color("b29a57"))

## Steel railings: the authoritative handrail blocks a body, so the kick
## plate and thin posts below it are fittings that leave the open gap open.
func _railings(info: Dictionary) -> void:
	var room: Node3D = _room("Railings")
	for solid: Dictionary in info["solids"]:
		if not is_equal_approx(float(solid.get("bottom", 0.0)), 4.25) or not is_equal_approx(float(solid["top"]), 4.4):
			continue
		var low: Vector3 = Vector3(float(solid["min_x"]), 3.3, float(solid["min_z"]))
		var high: Vector3 = Vector3(float(solid["max_x"]), 4.25, float(solid["max_z"]))
		var size: Vector3 = high - low
		var along_x: bool = size.x >= size.z
		var length: float = size.x if along_x else size.z
		var centre: Vector3 = (low + high) * 0.5
		fitting(room, "KickPlate", Vector3(centre.x, 3.36, centre.z), Vector3(size.x, 0.12, size.z), Color("3b403d"))
		var posts: int = maxi(1, ceili(length / 1.6))
		for index: int in range(posts + 1):
			var t: float = float(index) / float(posts)
			var at: Vector3 = Vector3(lerpf(low.x+0.05, high.x-0.05, t) if along_x else centre.x, 3.775, centre.z if along_x else lerpf(low.z+0.05, high.z-0.05, t))
			fitting(room, "RailPost", at, Vector3(0.07, 0.95, 0.07), Color("3b403d"))

func _sparks(room: Node3D, label: String, at: Vector3, spread: float) -> void:
	var sparks: CPUParticles3D = CPUParticles3D.new()
	sparks.name = label
	sparks.position = at
	sparks.amount = 18
	sparks.lifetime = 0.9
	sparks.explosiveness = 0.0
	sparks.randomness = 0.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = spread * 0.3
	sparks.direction = Vector3.UP
	sparks.spread = 70.0
	sparks.initial_velocity_min = 1.2
	sparks.initial_velocity_max = 2.6
	sparks.gravity = Vector3(0, -6.0, 0)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.05)
	sparks.mesh = mesh
	sparks.material_override = _glow("spark", Color("ffb050"), 2.4)
	room.add_child(sparks)

## Work lamps in a dark works throw a brighter, tighter pool than the
## habitat's, so shade and light alternate down each aisle.
func lamp(room: Node3D, at: Vector3, reach: float = 7.0, warm: bool = false) -> void:
	_block(_props(room), "Fixture", Vector3(0.7, 0.09, 0.25), _mat("lamp_housing", Color("57625b")), at)
	_block(_props(room), "Diffuser", Vector3(0.58, 0.035, 0.18), _glow("mars_lamp_warm" if warm else "mars_lamp", Color("e4c99c") if warm else Color("d8d9c8"), 1.2), at - Vector3(0, 0.05, 0))
	_omni(room, "WorkLight%d" % lamps, at - Vector3(0, 0.25, 0), Color(1.0, 0.85, 0.65) if warm else Color(1.0, 0.97, 0.88), 2.4, reach * 1.25)
