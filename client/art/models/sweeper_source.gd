extends RefCounted

const Workshop = preload("res://scripts/model_geometry.gd")
var g: RefCounted = Workshop.new()
var steel: StandardMaterial3D = g.material("issued_graphite", Color("43494b"), 0.55, 0.54)
var edge: StandardMaterial3D = g.material("machined_edges", Color("858c88"), 0.65, 0.45)
var joint: StandardMaterial3D = g.material("joint_elastomer", Color("202627"), 0.1, 0.85)
var bone: StandardMaterial3D = g.material("service_ceramic", Color("b9b8a5"), 0.05, 0.7)
var red: StandardMaterial3D = g.material("issue_red", Color("7e2925"), 0.2, 0.6)
var optic: StandardMaterial3D = g.material("red_optical_slit", Color("c8412f"), 0.05, 0.4)

func build_pose(_bot: bool = true, action: String = "idle", progress: float = 0.0, unarmed: bool = false) -> Node3D:
	var model: Node3D = Node3D.new()
	model.name = "Sweeper"
	var upper: Node3D = g.group(model, "Hip")
	var collapse: float = progress if action == "death" else 0.0
	var cycle: float = progress * TAU
	var walk: bool = action == "walk"
	var hip: Vector3 = Vector3(0, 0.88 - collapse * 0.68, -collapse * 0.34)
	if walk:
		hip += Vector3(sin(cycle) * 0.022, cos(cycle * 2.0) * 0.024, 0)
	_torso(upper)
	var raised: float = progress if action == "raise" else (1.0 if action in ["fire", "hit", "death"] else (1.0 - progress * 0.8 if action == "recover" else 0.0))
	var recoil: float = 1.0 - progress if action == "fire" else 0.0
	var pain: float = sin(lerpf(0.2, 1.0, progress) * PI) if action == "hit" else 0.0
	for side: float in [-1.0, 1.0]:
		var phase: float = cycle + (PI if side < 0 else 0.0)
		var stride: float = cos(phase) if walk else side * 0.18
		var lift: float = maxf(-sin(phase), 0.0) * 0.17 if walk else 0.0
		var ankle: Vector3 = Vector3(side * 0.145, 0.124 + lift, stride * 0.3)
		var knee: Vector3 = Vector3(side * 0.155, 0.48 + lift * 0.15, stride * 0.16 + lift + 0.025)
		knee = knee.lerp(Vector3(side * 0.21, 0.15, 0.04), collapse)
		ankle = ankle.lerp(Vector3(side * 0.22, 0.124, -0.32 - side * 0.09), collapse)
		_leg(g.group(model, "LeftLeg" if side < 0 else "RightLeg"), hip + Vector3(side * 0.13, -0.035, 0), knee, ankle)
		var elbow: Vector3 = Vector3(side * 0.45, 1.07, 0.09).lerp(Vector3(side * 0.45, 1.15, 0.24), raised)
		var hand: Vector3
		if side > 0:
			hand = Vector3(0.12, 0.98, 0.25).lerp(Vector3(0.105, 1.13, 0.28), raised)
		else:
			hand = Vector3(0.03, 1.02, 0.48).lerp(Vector3(0.045, 1.17, 0.51), raised)
		if walk:
			elbow.z -= stride * 0.045
			hand.z -= stride * 0.065
		if unarmed and action in ["raise", "fire", "recover"]:
			elbow = Vector3(side * 0.36, 1.16, 0.16)
			hand = Vector3(side * 0.22, 1.4, 0.23)
			if side > 0:
				var strike: float = 1.0 - progress * 0.3 if action == "fire" else (1.0 - progress if action == "recover" else 0.0)
				elbow = elbow.lerp(Vector3(0.19, 1.26, 0.39), strike)
				hand = hand.lerp(Vector3(0.08, 1.35, 0.70), strike)
		else:
			hand += Vector3(side * pain * 0.1, recoil * 0.055, -recoil * 0.055)
		elbow = elbow.lerp(Vector3(side * 0.24, 0.92, 0.06), collapse)
		hand = hand.lerp(Vector3(side * 0.28, 0.78, 0.08), collapse)
		_arm(g.group(upper, "LeftArm" if side < 0 else "RightArm"), side, elbow, hand)
		if side > 0 and not unarmed:
			_rifle(g.group(upper, "IssuedRifle", hand + Vector3(-0.06, 0.025, 0.04)), raised)
	for child: Node3D in upper.get_children():
		child.position.y -= 0.88
	upper.position = hip
	upper.rotation_degrees = Vector3(collapse * 88.0 - pain * 12.0 - recoil * 3.0, sin(cycle) * 3.0 if walk else 0.0, collapse * 11.0 + pain * 6.0)
	return model

func _torso(parent: Node3D) -> void:
	g.prism(parent, "PelvisShell", PackedVector2Array([Vector2(-0.14, -0.07), Vector2(0.14, -0.07), Vector2(0.16, 0.04), Vector2(0.09, 0.09), Vector2(-0.12, 0.09)]), 0.29, steel, Vector3(0, 0.88, 0))
	g.cylinder(parent, "SpinalActuator", 0.09, 0.22, joint, Vector3(0, 1.03, 0)).rotation.x = PI * 0.5
	for index: int in range(4):
		g.block(parent, "AbdominalSegment%d" % index, Vector3(0.26 + index * 0.023, 0.035, 0.105), edge if index == 3 else joint, Vector3(0, 1.01 + index * 0.045, 0.098))
	g.hull(parent, "ChestShell", PackedVector3Array([Vector3(1.14, 0.145, 0.12), Vector3(1.19, 0.22, 0.15), Vector3(1.38, 0.32, 0.175), Vector3(1.47, 0.29, 0.145), Vector3(1.49, 0.145, 0.105)]), steel)
	for side: float in [-1.0, 1.0]:
		g.hull(parent, "ChestOverlay%d" % int(side), PackedVector3Array([Vector3(-0.12, 0.075, 0.015), Vector3(-0.06, 0.09, 0.025), Vector3(0.08, 0.105, 0.025), Vector3(0.12, 0.075, 0.01)]), steel, Vector3(side * 0.103, 1.34, 0.145)).rotation.z = side * -0.10
		g.rod(parent, "ChestMachinedSeam%d" % int(side), Vector3(side * 0.035, 1.22, 0.184), Vector3(side * 0.19, 1.43, 0.15), 0.004, edge)
		g.block(parent, "ServiceTag%d" % int(side), Vector3(0.042, 0.021, 0.005), bone if side > 0 else red, Vector3(side * 0.14, 1.4, 0.169))
	g.block(parent, "BatteryBackpack", Vector3(0.29, 0.30, 0.13), steel, Vector3(0, 1.31, -0.20))
	for index: int in range(7):
		g.block(parent, "BatteryLouver%d" % index, Vector3(0.235, 0.012, 0.009), joint, Vector3(0, 1.2 + index * 0.03, -0.271))
	for side: float in [-1.0, 1.0]:
		g.pipe(parent, "ShoulderCable%d" % int(side), PackedVector3Array([Vector3(side * 0.13, 1.46, -0.15), Vector3(side * 0.25, 1.43, -0.14), Vector3(side * 0.29, 1.34, -0.04)]), 0.012, joint)
	g.cylinder(parent, "NeckGimbal", 0.071, 0.13, edge, Vector3(0, 1.54, 0)).rotation.x = PI * 0.5
	g.prism(parent, "OpticalHead", PackedVector2Array([Vector2(-0.11, -0.045), Vector2(-0.075, -0.105), Vector2(0.071, -0.105), Vector2(0.12, -0.065), Vector2(0.118, 0.07), Vector2(0.085, 0.108), Vector2(-0.075, 0.105), Vector2(-0.11, 0.07)]), 0.255, steel, Vector3(0, 1.69, 0.0), 0.22)
	g.block(parent, "FaceRecess", Vector3(0.223, 0.065, 0.018), joint, Vector3(0, 1.70, 0.116))
	optic.emission_enabled = true
	optic.emission = Color("9d3528")
	optic.emission_energy_multiplier = 0.25
	g.block(parent, "OpticalSlit", Vector3(0.19, 0.019, 0.004), optic, Vector3(0, 1.70, 0.128))
	for index: int in range(4):
		g.block(parent, "JawVent%d" % index, Vector3(0.022, 0.031, 0.007), joint, Vector3(-0.057 + index * 0.038, 1.63, 0.111))

func _leg(parent: Node3D, hip: Vector3, knee: Vector3, ankle: Vector3) -> void:
	_segment(parent, "Thigh", hip, knee, Vector3(0.15, 0.0, 0.20))
	_joint(parent, "Knee", knee, 0.077)
	_segment(parent, "Shin", knee, ankle, Vector3(0.12, 0.0, 0.15))
	g.rod(parent, "ShinPiston", knee + Vector3(0.074, -0.04, -0.01), ankle + Vector3(0.068, 0.03, -0.01), 0.014, edge)
	g.block(parent, "Kneecap", Vector3(0.14, 0.13, 0.06), steel, knee + Vector3(0, 0, 0.085))
	g.block(parent, "Boot", Vector3(0.19, 0.14, 0.33), steel, ankle + Vector3(0, -0.035, 0.055))
	g.block(parent, "BootSole", Vector3(0.20, 0.033, 0.35), joint, ankle + Vector3(0, -0.106, 0.055))
	for index: int in range(3):
		g.block(parent, "ToeRib%d" % index, Vector3(0.17, 0.011, 0.014), edge, ankle + Vector3(0, 0.037, 0.09 + index * 0.04))

func _arm(parent: Node3D, side: float, elbow: Vector3, hand: Vector3) -> void:
	var shoulder: Vector3 = Vector3(side * 0.39, 1.42, 0)
	_joint(parent, "ShoulderJoint", shoulder, 0.087)
	_segment(parent, "UpperArm", shoulder, elbow, Vector3(0.13, 0.0, 0.15))
	_joint(parent, "Elbow", elbow, 0.064)
	_segment(parent, "Forearm", elbow, hand, Vector3(0.115, 0.0, 0.13))
	g.block(parent, "ShoulderShell", Vector3(0.27, 0.13, 0.24), steel, shoulder + Vector3(side * 0.05, 0.044, 0)).rotation.z = side * -0.18
	g.block(parent, "IssueStripe", Vector3(0.006, 0.063, 0.11), red, shoulder + Vector3(side * 0.185, 0.017, 0))
	g.block(parent, "Palm", Vector3(0.085, 0.09, 0.086), joint, hand)
	for digit: int in range(4):
		g.block(parent, "Finger%d" % digit, Vector3(0.016, 0.045, 0.025), edge, hand + Vector3(-0.029 + digit * 0.019, -0.026, 0.047))
	g.rod(parent, "ForearmActuator", elbow + Vector3(side * 0.058, 0, 0), hand + Vector3(side * 0.058, 0, 0), 0.01, edge)

func _joint(parent: Node3D, label: String, at: Vector3, radius: float) -> void:
	g.cylinder(parent, label, radius, radius * 1.8, joint, at).rotation.y = PI * 0.5
	for side: float in [-1.0, 1.0]:
		g.cylinder(parent, label + "Cap%d" % int(side), radius * 0.63, 0.008, edge, at + Vector3(side * radius * 0.94, 0, 0), 12).rotation.y = PI * 0.5

func _segment(parent: Node3D, label: String, a: Vector3, b: Vector3, size: Vector3) -> void:
	var body: MeshInstance3D = g.hull(parent, label, PackedVector3Array([Vector3(-0.13, size.x * 0.32, size.z * 0.32), Vector3(-0.11, size.x * 0.42, size.z * 0.42), Vector3(0.075, size.x * 0.53, size.z * 0.50), Vector3(0.115, size.x * 0.47, size.z * 0.46), Vector3(0.13, size.x * 0.34, size.z * 0.34)]), steel, (a + b) * 0.5)
	body.scale.y = a.distance_to(b) * 0.78 / 0.26
	body.quaternion = Quaternion(Vector3.UP, (a - b).normalized())

func _rifle(parent: Node3D, raised: float) -> void:
	g.block(parent, "Receiver", Vector3(0.06, 0.085, 0.24), steel)
	g.block(parent, "Handguard", Vector3(0.065, 0.065, 0.23), joint, Vector3(0, 0.015, 0.21))
	g.cylinder(parent, "Barrel", 0.013, 0.28, edge, Vector3(0, 0.021, 0.43))
	g.block(parent, "Stock", Vector3(0.045, 0.095, 0.18), joint, Vector3(0, -0.016, -0.2))
	g.block(parent, "Grip", Vector3(0.037, 0.12, 0.056), joint, Vector3(0, -0.078, -0.04))
	for index: int in range(5):
		g.block(parent, "CoolingCut%d" % index, Vector3(0.067, 0.025, 0.012), steel, Vector3(0, 0.01, 0.14 + index * 0.03))
	parent.rotation.x = lerpf(-0.17, 0.0, raised)
