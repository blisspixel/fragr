class_name MoonBackdrop
extends Node3D

## Static lunar landmarks outside the playable square, never collision or travel.
func build(half: float) -> void:
	name = "LunarLandmarks"
	var basalt: Material = _material(Color("343b3c"))
	var shell: Material = _material(Color("b1b1a4"))
	var steel: Material = _material(Color("515d5d"))
	var warm: Material = _material(Color("d8c69d"), true)
	for index: int in range(9):
		var angle: float = float(index) * TAU / 9.0
		# A rotated rim's full footprint must remain outside the playable square.
		var radius: float = half * sqrt(2.0) + 21.0 + float(index % 3) * 5.0
		var berm: MeshInstance3D = _box("CraterRim", Vector3(cos(angle) * radius, 1.8, sin(angle) * radius),
			Vector3(21, 3.6, 8), basalt)
		berm.rotation.y = -angle
	# Low handling structure leaves the small Earth disc readable through glass.
	for z: float in [-26.0, -8.0]:
		_box("FreightGantryLeg", Vector3(-half - 5.0, 2.6, z), Vector3(0.8, 5.2, 0.8), steel)
	_box("FreightGantry", Vector3(-half - 5.0, 5.6, -17), Vector3(1.4, 0.8, 19), shell)
	var earth: MeshInstance3D = MeshInstance3D.new()
	earth.name = "Earth"
	var disc: QuadMesh = QuadMesh.new()
	disc.size = Vector2(13, 13)
	earth.mesh = disc
	earth.position = Vector3(-half - 76, 17, -17)
	var planet: StandardMaterial3D = _material(Color.WHITE, true)
	planet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	planet.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var earth_path: String = "res://assets/environment/moon/earth.png"
	if ResourceLoader.exists(earth_path):
		planet.albedo_texture = load(earth_path) as Texture2D
	earth.material_override = planet
	add_child(earth)
	# The Common Carrier preserves the earlier broad rectangular hull and windows.
	var carrier: Node3D = Node3D.new()
	carrier.name = "CommonCarrierStatic"
	carrier.position = Vector3(half + 13, 0, 19)
	add_child(carrier)
	_piece(carrier, "ImpoundCradle", Vector3(0, 0.8, 0), Vector3(18, 1.6, 8), steel)
	_piece(carrier, "CarrierHull", Vector3(0, 3.5, 0), Vector3(14, 3.8, 6), basalt)
	_piece(carrier, "CarrierShell", Vector3(0, 5.2, 0), Vector3(14.3, 0.35, 6.1), shell)
	_piece(carrier, "Cockpit", Vector3(-5.5, 4.9, 0), Vector3(3.1, 2.1, 4.5), steel)
	_piece(carrier, "CockpitWindow", Vector3(-7.08, 5.15, 0), Vector3(0.035, 1.2, 2.6), _material(Color("789991"), true))
	for index: int in range(6):
		_piece(carrier, "CarrierWindow", Vector3(-3.5 + float(index) * 1.7, 4.15, -3.025), Vector3(0.85, 0.7, 0.04), warm)
	_piece(carrier, "TernProvisionalHead", Vector3(-7.12, 5.35, 0), Vector3(0.045, 0.28, 0.32), shell)
	_piece(carrier, "TernProvisionalHarness", Vector3(-7.12, 4.97, 0), Vector3(0.045, 0.38, 0.52), steel)
	_piece(carrier, "TernShoulderRepair", Vector3(-7.15, 5.04, 0.27), Vector3(0.04, 0.16, 0.1), _material(Color("9c6846")))
	# Custody tower with radiating service structures; a destination, not a room.
	var depot: Node3D = Node3D.new()
	depot.name = "CustodyDepotStatic"
	depot.position = Vector3(half + 38, 0, 28)
	add_child(depot)
	_piece(depot, "CustodyTower", Vector3(0, 13, 0), Vector3(8, 26, 8), shell)
	_piece(depot, "TowerCrown", Vector3(0, 26.5, 0), Vector3(10, 1, 10), basalt)
	for index: int in range(4):
		var wing: MeshInstance3D = _piece(depot, "RadialWing", Vector3(0, 3.5, 11).rotated(Vector3.UP, index * PI * 0.5), Vector3(5, 7, 19), basalt)
		wing.rotation.y = index * PI * 0.5
	for y: float in [7, 12, 17, 22]:
		_piece(depot, "TowerWindows", Vector3(-4.02, y, 0), Vector3(0.04, 0.45, 6), warm)
	ArenaSky.mark_world(self)

func _box(label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	return _piece(self, label, at, size, material)

static func _piece(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node

static func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.93
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
