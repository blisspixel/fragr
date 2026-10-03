extends RefCounted

const Workshop = preload("res://scripts/model_geometry.gd")

func build(hands: bool = false) -> Node3D:
	var g: RefCounted = Workshop.new()
	var gun: Node3D = Node3D.new()
	gun.name = "Shotgun"
	var steel: StandardMaterial3D = g.material("blued_steel", Color("45494b"), 0.72, 0.42)
	var dark: StandardMaterial3D = g.material("dark_mechanism", Color("1b2122"), 0.45, 0.65)
	var edge: StandardMaterial3D = g.material("worn_machined_edge", Color("8d938d"), 0.8, 0.46)
	var wood: StandardMaterial3D = g.material("walnut_wood", Color("75482e"), 0.0, 0.65)
	var wood_edge: StandardMaterial3D = g.material("oiled_wood_edge", Color("9b6b40"), 0.0, 0.55)
	var rubber: StandardMaterial3D = g.material("rubber", Color("262726"), 0.0, 0.95)
	var bone: StandardMaterial3D = g.material("bone_repair_plate", Color("bdb6a4"), 0.15, 0.75)
	var brass: StandardMaterial3D = g.material("brass_fittings", Color("9a8050"), 0.7, 0.5)
	var receiver: PackedVector2Array = PackedVector2Array([Vector2(0.032, 0.025), Vector2(-0.03, 0.06), Vector2(-0.31, 0.06), Vector2(-0.365, 0.04), Vector2(-0.36, -0.037), Vector2(-0.31, -0.069), Vector2(-0.07, -0.075), Vector2(0.025, -0.035)])
	g.prism(gun, "ForgedReceiver", receiver, 0.076, steel)
	g.block(gun, "ReceiverTopRib", Vector3(0.052, 0.011, 0.245), edge, Vector3(0, 0.06, -0.14))
	# Actual tubular bore with a recessed dark interior and chamfered muzzle crown.
	g.lathe(gun, "Barrel", PackedVector2Array([Vector2(-0.99, 0.014), Vector2(-0.99, 0.022), Vector2(-0.984, 0.026), Vector2(-0.41, 0.029), Vector2(-0.35, 0.03), Vector2(-0.35, 0.014)]), steel, Vector3(0, 0.035, 0))
	g.lathe(gun, "MuzzleCrown", PackedVector2Array([Vector2(-0.994, 0.014), Vector2(-0.994, 0.02), Vector2(-0.988, 0.024), Vector2(-0.98, 0.024), Vector2(-0.98, 0.014)]), edge, Vector3(0, 0.035, 0))
	g.cylinder(gun, "MagazineTube", 0.019, 0.47, dark, Vector3(0, -0.035, -0.595))
	g.cylinder(gun, "MagazineEndCap", 0.023, 0.024, steel, Vector3(0, -0.035, -0.84))
	g.cylinder(gun, "EndCapInset", 0.014, 0.003, brass, Vector3(0, -0.035, -0.853))
	for z: float in [-0.77, -0.385]:
		g.block(gun, "BarrelBand%d" % int(z * -100), Vector3(0.061, 0.092, 0.017), steel, Vector3(0, -0.005, z))
	# Heat guard has open gaps, not painted vent marks.
	for side: float in [-1.0, 1.0]:
		g.rod(gun, "GuardRail%d" % int(side), Vector3(side * 0.032, 0.046, -0.42), Vector3(side * 0.032, 0.046, -0.78), 0.006, dark)
	for index: int in range(9):
		var z: float = -0.43 - index * 0.038
		g.pipe(gun, "GuardBridge%d" % index, PackedVector3Array([Vector3(-0.032, 0.046, z), Vector3(-0.028, 0.065, z), Vector3(-0.014, 0.074, z), Vector3(0.014, 0.074, z), Vector3(0.028, 0.065, z), Vector3(0.032, 0.046, z)]), 0.0045, steel)
	# Receiver side panels frame the bolt/ejection recess.
	g.block(gun, "EjectionWell", Vector3(0.002, 0.038, 0.13), dark, Vector3(0.039, 0.014, -0.155))
	g.block(gun, "Bolt", Vector3(0.003, 0.022, 0.086), edge, Vector3(0.041, 0.009, -0.158))
	for y: float in [-0.01, 0.038]:
		g.block(gun, "PortLip%d" % int(y * 1000), Vector3(0.004, 0.005, 0.147), steel, Vector3(0.041, y, -0.15))
	g.block(gun, "ServicePlate", Vector3(0.004, 0.025, 0.063), bone, Vector3(0.04, -0.04, -0.244))
	for side: float in [-1.0, 1.0]:
		for z: float in [-0.055, -0.31]:
			var fastener: MeshInstance3D = g.cylinder(gun, "Pin%d_%d" % [int(side), int(z * 1000)], 0.006, 0.003, edge, Vector3(side * 0.039, -0.041, z), 8)
			fastener.rotation.y = PI * 0.5
	# Curved civilian stock with a narrow wrist and an inset wood cheek.
	var stock: PackedVector2Array = PackedVector2Array([Vector2(0.016, 0.029), Vector2(0.086, 0.025), Vector2(0.16, 0.068), Vector2(0.43, 0.055), Vector2(0.463, 0.033), Vector2(0.457, -0.145), Vector2(0.409, -0.159), Vector2(0.205, -0.133), Vector2(0.129, -0.102), Vector2(0.089, -0.13), Vector2(0.049, -0.137), Vector2(0.02, -0.093)])
	g.prism(gun, "WalnutStock", stock, 0.079, wood)
	for side: float in [-1.0, 1.0]:
		g.prism(gun, "CheekPanel%d" % int(side), PackedVector2Array([Vector2(0.17, 0.037), Vector2(0.397, 0.028), Vector2(0.407, -0.104), Vector2(0.238, -0.1), Vector2(0.177, -0.068)]), 0.004, wood_edge, Vector3(side * 0.04, 0, 0))
	g.block(gun, "RecoilPad", Vector3(0.083, 0.184, 0.022), rubber, Vector3(0, -0.055, 0.463))
	for index: int in range(8):
		g.block(gun, "PadRib%d" % index, Vector3(0.086, 0.006, 0.026), dark, Vector3(0, -0.132 + index * 0.021, 0.466))
	# The pump and support glove move as one mechanical group.
	var pump: Node3D = g.group(gun, "Pump", Vector3(0, -0.041, -0.55))
	g.prism(pump, "ForeEnd", PackedVector2Array([Vector2(-0.115, -0.028), Vector2(0.1, -0.028), Vector2(0.12, -0.014), Vector2(0.12, 0.019), Vector2(0.104, 0.032), Vector2(-0.109, 0.032), Vector2(-0.125, 0.017), Vector2(-0.125, -0.014)]), 0.082, wood)
	for index: int in range(12):
		g.block(pump, "ForeEndRib%d" % index, Vector3(0.085, 0.061, 0.007), wood_edge if index % 4 == 0 else wood, Vector3(0, 0, -0.108 + index * 0.019))
	for side: float in [-1.0, 1.0]:
		g.rod(pump, "ActionBar%d" % int(side), Vector3(side * 0.025, 0.012, 0.09), Vector3(side * 0.025, 0.012, 0.24), 0.0035, edge)
	g.pipe(gun, "TriggerGuard", PackedVector3Array([Vector3(0, -0.055, -0.15), Vector3(0, -0.099, -0.153), Vector3(0, -0.122, -0.128), Vector3(0, -0.13, -0.088), Vector3(0, -0.123, -0.047), Vector3(0, -0.086, -0.019), Vector3(0, -0.049, -0.016)]), 0.0045, dark)
	g.pipe(gun, "Trigger", PackedVector3Array([Vector3(0, -0.058, -0.078), Vector3(0, -0.088, -0.089), Vector3(0, -0.102, -0.075)]), 0.003, edge)
	g.block(gun, "RearSight", Vector3(0.044, 0.019, 0.018), dark, Vector3(0, 0.076, -0.05))
	for side: float in [-1.0, 1.0]:
		g.block(gun, "SightEar%d" % int(side), Vector3(0.008, 0.017, 0.018), edge, Vector3(side * 0.017, 0.091, -0.05))
	g.block(gun, "FrontSightBase", Vector3(0.019, 0.018, 0.032), dark, Vector3(0, 0.064, -0.925))
	g.block(gun, "FrontSight", Vector3(0.006, 0.018, 0.012), bone, Vector3(0, 0.082, -0.925))
	for z: float in [0.37, -0.812]:
		g.pipe(gun, "SlingLoop%d" % int(z * 1000), PackedVector3Array([Vector3(-0.012, -0.113, z), Vector3(-0.019, -0.14, z), Vector3(0.019, -0.14, z), Vector3(0.012, -0.113, z)]), 0.0025, brass)
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.035, -0.997)
	gun.add_child(muzzle)
	if hands:
		_hand(g, g.group(pump, "SupportHand", Vector3(-0.02, -0.063, 0.012)), true)
		_hand(g, g.group(gun, "TriggerHand", Vector3(0.04, -0.081, 0.047)), false)
	return gun

func _hand(g: RefCounted, hand: Node3D, support: bool) -> void:
	var glove: StandardMaterial3D = g.material("worn_leather_gloves", Color("74503a"), 0.0, 0.86)
	var seam: StandardMaterial3D = g.material("glove_seams", Color("ad8b62"), 0.0, 0.8)
	var sleeve: StandardMaterial3D = g.material("jacket_cloth", Color("514137"), 0.0, 0.96)
	g.block(hand, "Palm", Vector3(0.073, 0.033, 0.085), glove)
	for digit: int in range(4):
		var x: float = -0.025 + digit * 0.016
		var length: float = 0.058 - absf(digit - 1.5) * 0.008
		g.pipe(hand, "Finger%d" % digit, PackedVector3Array([Vector3(x, 0, -0.028), Vector3(x, 0.013, -0.028 - length * 0.45), Vector3(x, 0.033, -0.033 - length * 0.65), Vector3(x, 0.045, -0.022 - length * 0.5)]), 0.008, glove)
		g.block(hand, "Knuckle%d" % digit, Vector3(0.012, 0.004, 0.015), seam, Vector3(x, -0.018, -0.026))
	g.pipe(hand, "Thumb", PackedVector3Array([Vector3(0.034, 0, 0.025), Vector3(0.057, 0.016, 0.0), Vector3(0.05, 0.03, -0.032), Vector3(0.033, 0.033, -0.043)]), 0.011, glove)
	var elbow: Vector3 = Vector3(-0.085, -0.23, 0.23) if support else Vector3(0.045, -0.23, 0.22)
	g.rod(hand, "Wrist", Vector3(0, -0.005, 0.024), elbow * 0.35, 0.029, glove)
	g.rod(hand, "Sleeve", elbow * 0.3, elbow, 0.04, sleeve)
	if not support:
		hand.rotation_degrees = Vector3(58, -12, -17)

func pose(gun: Node3D, time: float) -> void:
	var t: float = maxf(0.0, time)
	var recoil: float = exp(-t * 24.0) if t < 0.22 else 0.0
	gun.rotation.x = -recoil * 0.038
	gun.position.z = recoil * 0.021
	var stroke: float = 0.0
	if t >= 0.18 and t <= 0.44:
		stroke = sin((t - 0.18) / 0.26 * PI)
	var pump: Node3D = gun.get_node("Pump")
	pump.position.z = -0.55 + stroke * 0.115

