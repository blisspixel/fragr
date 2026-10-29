class_name M11Dressing
extends M06Dressing

## Issued fittings and orderly work rooms distinguish the custody tender
## from the Carrier. Everything sits on an existing solid, flush to a wall
## or above head height. No collision, outcome or captive identity is added.
const TENDER_MAP_ID: int = 1011
static var _tender_surfaces: Dictionary[String, ShaderMaterial] = {}

static func tender_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != TENDER_MAP_ID or not info.get("solids") is Array or not info.get("m11") is Dictionary:
		return false
	var anchors: Array = [
		[Vector3(-10, 0, -32), Vector3(10, 0.3, 32)],
		[Vector3(-10, 0.3, -32), Vector3(10, 5.4, -31.7)],
		[Vector3(9.78, 0.3, -31.7), Vector3(10, 5.4, 26)],
		[Vector3(-2.42, 3.5, -31.7), Vector3(2.42, 3.75, 18)],
		[Vector3(4.6, 0.3, 6), Vector3(7.6, 2.95, 6.65)],
		[Vector3(-9.78, 1.2, 24), Vector3(9.78, 1.5, 31.7)],
		[Vector3(-5.55, 0.3, -31.3), Vector3(-2.65, 1.65, -30.75)],
		[Vector3(-5.55, 0.3, -23.3), Vector3(-3.7, 1.45, -22.4)],
		[Vector3(5.2, 0.3, -25), Vector3(7.1, 1.15, -23.4)],
		[Vector3(8.7, 0.3, -23), Vector3(9.5, 2.2, -19.2)],
		[Vector3(8.8, 0.3, -14), Vector3(9.5, 0.85, -12)],
		[Vector3(8.8, 0.3, -10), Vector3(9.5, 0.85, -8)],
		[Vector3(8.8, 0.3, -6), Vector3(9.5, 0.85, -4)],
		[Vector3(3.5, 0.3, -15.4), Vector3(5.1, 1.4, -14.5)],
		[Vector3(4.6, 0.3, 10), Vector3(7.6, 2.95, 10.65)],
		[Vector3(4.6, 0.3, 14), Vector3(7.6, 2.95, 14.65)],
		[Vector3(8.65, 0.3, 16), Vector3(9.5, 1.4, 18)],
		[Vector3(-5.5, 0.3, -8.3), Vector3(-4.6, 2.65, -5.8)],
		[Vector3(-5.5, 0.3, -2.1), Vector3(-4.6, 2.65, 0.5)],
		[Vector3(-1.5, 1.5, 28.9), Vector3(1.5, 2.65, 30.3)],
		[Vector3(-8.6, 1.5, 28.9), Vector3(-6.3, 2.5, 30.3)],
		[Vector3(6.3, 1.5, 29.6), Vector3(8.6, 2.5, 30.8)],
	]
	for pair: Array in anchors:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

static func tender_surface(role: String) -> ShaderMaterial:
	if _tender_surfaces.has(role):
		return _tender_surfaces[role]
	var tint: Color = Color("707c78")
	var texture: String = "ship_enamel.png"
	match role:
		"roof": tint = Color("515959")
		"floor":
			tint = Color("73746b")
			texture = "ship_floor.png"
		"steel":
			tint = Color("65716d")
			texture = "ship_steel.png"
		"records": tint = Color("827962")
		"panel": tint = Color("787968")
		"bridge": tint = Color("69717b")
		"mess_deck":
			tint = Color("86795d")
			texture = "ship_floor.png"
		"transfer_deck":
			tint = Color("899180")
			texture = "ship_floor.png"
		"records_deck":
			tint = Color("81745c")
			texture = "ship_floor.png"
	var result: ShaderMaterial = _material(tint, PRODUCTION + texture, PRODUCTION + "ship_floor.png", 1, tint.darkened(0.15), 0.25)
	result.set_shader_parameter("panel_size", 1.5)
	_tender_surfaces[role] = result
	return result

static func restyle_tender(_cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not tender_layout(info) or not MissionState.map_error(info).is_empty():
		return
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"]["solids"]
	if surfaces.size() != solids.size() or views.size() != solids.size():
		return
	for index: int in range(solids.size()):
		var box: AABB = _bounds(solids[index])
		var role: String = "shell"
		if surfaces[index] == "inspection_glass":
			views[index].material_override = M10Dressing.window_glass()
			continue
		if box.size.y < 0.4:
			role = "roof" if box.position.y > 3.0 else "floor"
		elif surfaces[index] == "service_steel":
			role = "steel"
		elif surfaces[index] == "lift_panel":
			role = "panel"
		if box.position.x > 4.5 and box.position.z >= 6 and box.end.z <= 14.7:
			role = "records"
		if box.position.z > 24 and box.position.y > 1.4:
			role = "bridge"
		views[index].material_override = tender_surface(role)

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not tender_layout(info) or not MissionState.map_error(info).is_empty():
		return
	_build_spine()
	_build_armory()
	_build_mess()
	_build_transfer()
	_build_records()
	_build_service()
	_build_bridge()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _issued_lamp(room: Node3D, at: Vector3, energy: float = 1.0, reach: float = 5.0) -> void:
	var props: Node3D = _props(room)
	_block(props, "LampHousing", Vector3(0.7, 0.12, 0.24), _mat("tender_lamp_housing", Color("3e4949"), 0.4), at)
	_block(props, "LampDiffuser", Vector3(0.58, 0.035, 0.16), _glow("tender_diffuser", Color("d6d8c7"), 0.65), at - Vector3(0, 0.075, 0))
	_omni(room, "WorkLight", at - Vector3(0, 0.2, 0), Color(0.92, 0.95, 0.86), energy, reach)

func _build_spine() -> void:
	var room: Node3D = _room("Spine")
	var props: Node3D = _props(room)
	var trim: StandardMaterial3D = _mat("tender_trim", Color("48534f"), 0.4)
	var paint: StandardMaterial3D = _mat("tender_lane", Color("afa58a"))
	# Regular service lighting and paired floor marks lead toward the bridge.
	for z: float in [-27.0, -22.0, -16.0, -11.0, -5.0, 1.0, 7.0, 13.0]:
		_issued_lamp(room, Vector3(0, 3.4, z), 1.15, 5.5)
		for x: float in [-1.5, 1.5]:
			_block(props, "LaneMark", Vector3(0.10, 0.008, 1.6), paint, Vector3(x, 0.306, z))
	# Cable trays remain above the existing spine ceiling, never in firing lanes.
	for x: float in [-1.7, 1.7]:
		_block(props, "Conduit", Vector3(0.16, 0.10, 48), trim, Vector3(x, 3.43, -7))
	for z: float in [-20.0, -10.0, 0.0, 10.0]:
		# Small painted seal on the issued frame, not red corridor lighting.
		_block(props, "FrameSeal", Vector3(0.14, 0.24, 0.015), _mat("tender_seal", SEAL_RED), Vector3(2.06, 2.5, z - 0.16))
	for z: int in range(-32, 24, 8):
		for x: float in [-6.0, 2.0]:
			_block(props, "DeckTile", Vector3(8, 0.008, 8), tender_surface("floor"), Vector3(x, 0.305, z + 4))
		_block(props, "DeckTile", Vector3(4, 0.008, 8), tender_surface("floor"), Vector3(8, 0.305, z + 4))
	for x: float in [-14.0, 14.0]:
		_issued_lamp(room, Vector3(x, 3.35 if x < 0 else 4.55, -27.5 if x < 0 else 27.5), 1.3, 5)

func _build_armory() -> void:
	var room: Node3D = _room("Armory")
	var props: Node3D = _props(room)
	var rubber: StandardMaterial3D = _mat("tender_boot", Color("353c37"))
	# Issued boots sit atop the boot-rack solid, with paired size progression.
	for index: int in range(7):
		for side: float in [-0.06, 0.06]:
			_block(props, "Boot", Vector3(0.10, 0.23, 0.25), rubber, Vector3(-5.3 + index * 0.39 + side, 1.77, -31.0))
	var plate: StandardMaterial3D = _mat("tender_plate", Color("9b9d8c"), 0.3)
	for index: int in range(5):
		_block(props, "IssueDrawer", Vector3(0.31, 0.23, 0.018), plate, Vector3(-5.32 + index * 0.34, 1.07, -22.385))
		_block(props, "DrawerPull", Vector3(0.13, 0.03, 0.03), rubber, Vector3(-5.32 + index * 0.34, 1.06, -22.37))
	_issued_lamp(room, Vector3(-4.3, 3.4, -24.8), 1.4, 5)

func _build_mess() -> void:
	var room: Node3D = _room("Mess")
	var props: Node3D = _props(room)
	var tray: StandardMaterial3D = _mat("tender_tray", Color("a0a18d"), 0.4)
	var cup: StandardMaterial3D = _mat("tender_cup", Color("747b5d"))
	_block(props, "MessDeck", Vector3(7.34, 0.008, 14.68), tender_surface("mess_deck"), Vector3(6.1, 0.315, -24.35))
	_block(props, "MessWall", Vector3(0.015, 2.1, 14.6), _mat("tender_mess_paint", Color("797b58")), Vector3(9.765, 1.45, -24.35))
	_block(props, "MessRail", Vector3(0.03, 0.08, 14.6), _mat("tender_mess_rail", Color("b1a17a")), Vector3(9.75, 2.55, -24.35))
	for x: float in [5.55, 6.65]:
		for z: float in [-24.6, -23.8]:
			_block(props, "Tray", Vector3(0.4, 0.025, 0.3), tray, Vector3(x, 1.168, z))
			_block(props, "TrayWell", Vector3(0.33, 0.008, 0.23), _mat("tender_tray_well", Color("566050")), Vector3(x, 1.185, z))
			_block(props, "Cup", Vector3(0.1, 0.14, 0.1), cup, Vector3(x + 0.14, 1.25, z + 0.2))
	for x: float in [5.22, 7.08]:
		_block(props, "TableRim", Vector3(0.035, 0.055, 1.6), tray, Vector3(x, 1.175, -24.2))
	for z: float in [-24.98, -23.42]:
		_block(props, "TableRim", Vector3(1.9, 0.055, 0.035), tray, Vector3(6.15, 1.175, z))
	for z: float in [-22.05, -20.15]:
		_block(props, "IssuedBlanket", Vector3(0.7, 0.06, 1.7), _mat("tender_blanket", Color("7d8557")), Vector3(9.1, 2.23, z))
		_block(props, "Pillow", Vector3(0.48, 0.10, 0.28), _mat("tender_pillow", Color("b8ab89")), Vector3(9.1, 2.31, z - 0.5))
		for y: float in [0.8, 1.7]:
			_block(props, "BunkFace", Vector3(0.02, 0.65, 1.6), _mat("tender_bunk", Color("747c60")), Vector3(8.685, y, z))
			_block(props, "BunkLinen", Vector3(0.025, 0.12, 0.35), _mat("tender_pillow", Color("b8ab89")), Vector3(8.67, y + 0.22, z - 0.5))
			_block(props, "BlanketFold", Vector3(0.03, 0.07, 1.6), _mat("tender_blanket_fold", Color("a0a57a")), Vector3(8.66, y - 0.18, z))
	_issued_lamp(room, Vector3(6.2, 4.8, -24), 1.7, 7)
	_omni(room, "MessTaskLight", Vector3(6.2, 2.6, -24.2), Color(1.0, 0.88, 0.68), 0.65, 3.5)

func _build_transfer() -> void:
	var room: Node3D = _room("Transfer")
	var props: Node3D = _props(room)
	var plate: StandardMaterial3D = _mat("tender_restraint", Color("8b958a"), 0.3)
	_block(props, "TransferDeck", Vector3(7.34, 0.008, 15.76), tender_surface("transfer_deck"), Vector3(6.1, 0.315, -8.89))
	_block(props, "WashableBacking", Vector3(0.015, 2.3, 15.7), _mat("tender_transfer_paint", Color("929e89")), Vector3(9.765, 1.55, -8.89))
	for z: float in [-13.0, -9.0, -5.0]:
		# Rails and folded straps belong to the existing restraint benches.
		_block(props, "RestraintRail", Vector3(0.04, 0.10, 1.6), plate, Vector3(9.47, 0.92, z))
		for dz: float in [-0.5, 0.5]:
			_block(props, "FoldedStrap", Vector3(0.48, 0.025, 0.09), _mat("tender_strap", Color("595c50")), Vector3(9.15, 0.875, z + dz))
		_block(props, "StationPlate", Vector3(0.025, 0.38, 0.45), _mat("tender_station", Color("505e52")), Vector3(9.74, 2.2, z))
		for slot: int in range(3):
			_block(props, "StationSlot", Vector3(0.03, 0.035, 0.22), plate, Vector3(9.72, 2.3 - slot * 0.09, z))
		_issued_lamp(room, Vector3(7.7, 4.8, z), 1.0, 5.0)
	# Papers and one red seal make the registry's purpose legible without prose.
	_block(props, "RegistryStack", Vector3(0.5, 0.08, 0.35), _mat("tender_paper", Color("b4ad94")), Vector3(4.65, 1.44, -15))
	_block(props, "RegistrySeal", Vector3(0.10, 0.012, 0.10), _mat("tender_seal", SEAL_RED), Vector3(4.7, 1.486, -15.0))

func _build_records() -> void:
	var room: Node3D = _room("Records")
	var props: Node3D = _props(room)
	var frame: StandardMaterial3D = _mat("tender_record_frame", Color("4d5950"), 0.4)
	_block(props, "RecordsDeck", Vector3(7.34, 0.008, 19.76), tender_surface("records_deck"), Vector3(6.1, 0.315, 9.11))
	_block(props, "RecordsBacking", Vector3(0.015, 1.6, 19.7), _mat("tender_records_paint", Color("887858")), Vector3(9.765, 1.2, 9.11))
	for z: float in [6.0, 10.0, 14.0]:
		for y: float in [0.65, 1.35, 2.05, 2.75]:
			for face: float in [z - 0.012, z + 0.662]:
				_block(props, "ShelfLip", Vector3(3.0, 0.06, 0.02), frame, Vector3(6.1, y - 0.25, face))
				for index: int in range(9):
					var tint: Color = Color("899078") if index % 3 else Color("a2926b")
					_block(props, "CaseSpine", Vector3(0.24, 0.45, 0.018), _mat("tender_case_%d" % (index % 3), tint), Vector3(4.78 + index * 0.32, y, face))
					_block(props, "CaseTab", Vector3(0.1, 0.045, 0.022), _mat("tender_paper", Color("b4ad94")), Vector3(4.78 + index * 0.32, y + 0.08, face))
		_issued_lamp(room, Vector3(6.3, 4.8, z + 1.6), 1.4, 5.5)
	_block(props, "Document", Vector3(0.45, 0.012, 0.6), _mat("tender_paper", Color("b4ad94")), Vector3(9, 1.412, 17))
	_block(props, "DocumentSeal", Vector3(0.1, 0.012, 0.1), _mat("tender_seal", SEAL_RED), Vector3(9.12, 1.426, 17.15))
	_omni(room, "RecordsTaskLight", Vector3(8.9, 2.4, 17.0), Color(1.0, 0.88, 0.68), 0.65, 3.0)

func _build_service() -> void:
	var room: Node3D = _room("Service")
	var props: Node3D = _props(room)
	for z: float in [-7.0, -0.8]:
		for y: float in [0.8, 1.1, 1.4, 1.7, 2.0]:
			_block(props, "ServiceVent", Vector3(0.02, 0.06, 1.8), _mat("tender_vent", Color("37423f")), Vector3(-4.59, y, z))
	for z: float in [-23.0, -9.0, 5.0, 15.0]:
		_issued_lamp(room, Vector3(-7.5, 3.15, z), 1.0, 6)
	for z: float in [-6.0, 2.8, 10.0]:
		_issued_lamp(room, Vector3(-4.0, 4.8, z), 1.0, 5)
	for y: float in [2.65, 2.85]:
		_block(props, "ServicePipe", Vector3(0.10, 0.10, 48), _mat("tender_pipe", Color("8b8166"), 0.3), Vector3(-9.7, y, -6))

func _build_bridge() -> void:
	var room: Node3D = _room("Bridge")
	var props: Node3D = _props(room)
	var screen: StandardMaterial3D = _glow("tender_screen", Color("9a9b68"), 0.2)
	_block(props, "BridgeDeck", Vector3(16.0, 0.008, 7.68), tender_surface("bridge"), Vector3(1.75, 1.506, 27.85))
	var bezel: StandardMaterial3D = _mat("tender_bezel", Color("3d4b4c"), 0.4)
	var slate: StandardMaterial3D = _mat("tender_bridge_paint", Color("627487"))
	for x: float in [-7.5, 0.0, 7.5]:
		var z: float = 30.1 if x > 1.0 else 29.5
		var top: float = 2.5 if absf(x) > 1.0 else 2.65
		var front: float = 29.58 if x > 1.0 else 28.88
		_block(props, "ConsoleFascia", Vector3(2.0, 0.62, 0.025), slate, Vector3(x, top - 0.4, front))
		for dial: float in [-0.65, -0.2, 0.25]:
			_shape.cylinder(props, "GaugeRim", 0.13, 0.035, bezel, Vector3(x + dial, top - 0.35, front - 0.025), 12)
			_shape.cylinder(props, "GaugeFace", 0.10, 0.012, _mat("tender_gauge", Color("b6ae87")), Vector3(x + dial, top - 0.35, front - 0.05), 12)
			_block(props, "GaugeNeedle", Vector3(0.025, 0.12, 0.018), bezel, Vector3(x + dial, top - 0.32, front - 0.06))
		for slot: int in range(4):
			_block(props, "ConsoleVent", Vector3(0.18, 0.035, 0.03), bezel, Vector3(x + 0.72, top - 0.25 - slot * 0.08, front - 0.02))
		_block(props, "ConsoleScreen", Vector3(0.8, 0.015, 0.4), screen, Vector3(x, top + 0.01, z))
		for key: int in range(5):
			_block(props, "ConsoleKey", Vector3(0.06, 0.02, 0.07), _mat("tender_key", Color("b4ad94")), Vector3(x - 0.3 + key * 0.15, top + 0.015, z - 0.35))
		_issued_lamp(room, Vector3(x, 4.8, 28.0), 1.2, 5.5)
		_block(props, "DisplayFrame", Vector3(2.5, 1.55, 0.04), bezel, Vector3(x, 3.75, 31.66))
		_block(props, "DisplayPanel", Vector3(2.3, 1.35, 0.025), slate, Vector3(x, 3.75, 31.63))
		_block(props, "DisplayConduit", Vector3(0.08, 0.45, 0.06), bezel, Vector3(x + 0.9, 2.75, 31.65))
		for line: int in range(4):
			_block(props, "DisplayTrace", Vector3(1.6 - line * 0.23, 0.035, 0.03), screen, Vector3(x - 0.2, 4.15 - line * 0.24, 31.61))
	# Only an equipment diagram, not an invented mission fact or readable sign.
