extends "res://art/characters/geometry.gd"

## An exposed service transmitter, with a folding dish instead of a gun.
func build_pose(action: String, progress: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var spread: float = progress if action == "unfold" else 0.0
	if action == "pulse":
		spread = 1.0
	elif action == "fold":
		spread = 1.0 - progress
	var recoil: float = sin(progress * PI) if action == "pulse" else 0.0
	var pain: float = sin(progress * PI) if action == "hit" else 0.0
	var collapse: float = progress if action == "death" else 0.0
	# Four anchored feet and a narrow unarmored drive spine distinguish the
	# stationary emitter from a Turret barrel or a Sweeper's shoulders.
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			var foot: Vector3 = Vector3(side * 0.35, 0.08, end * 0.26)
			limb(root, Vector3(side * 0.13, 0.47, end * 0.08), foot, 0.085, 0.085, STEEL)
			part(root, foot, Vector3(0.19, 0.11, 0.23), INK)
	part(root, Vector3(0, 0.42, 0), Vector3(0.40, 0.32, 0.36), STEEL)
	part(root, Vector3(0, 0.45, 0.20), Vector3(0.30, 0.19, 0.055), PLATE)
	part(root, Vector3(0, 0.50, 0.235), Vector3(0.18, 0.035, 0.02), RED)
	var emitter: Node3D = Node3D.new()
	root.add_child(emitter)
	emitter.position = Vector3(0, 0.60 - collapse * 0.32, -recoil * 0.06)
	emitter.rotation_degrees = Vector3(pain * 13.0 + collapse * 82.0, 0, pain * 9.0)
	part(emitter, Vector3(0, 0.38, 0), Vector3(0.16, 0.79, 0.18), PLATE)
	# Rear capacitor slats establish an exposed flank rather than an animal.
	part(emitter, Vector3(0, 0.38, -0.17), Vector3(0.38, 0.55, 0.19), INK)
	for height: float in [0.17, 0.28, 0.39, 0.50, 0.61]:
		part(emitter, Vector3(0, height, -0.28), Vector3(0.34, 0.045, 0.035), PLATE)
		part(emitter, Vector3(0.18, height, -0.18), Vector3(0.025, 0.035, 0.15), RED)
	# Four petals fan out during the long windup. The geometry change carries
	# the tell even at distance or with sound disabled.
	var hub: Vector3 = Vector3(0, 0.61, 0.03)
	for index: int in range(4):
		var petal: Node3D = Node3D.new()
		emitter.add_child(petal)
		petal.position = hub
		petal.rotation_degrees.z = index * 90.0
		var hinge: Node3D = Node3D.new()
		petal.add_child(hinge)
		hinge.rotation_degrees.x = 68.0 * (1.0 - spread)
		part(hinge, Vector3(0, 0.30, 0), Vector3(0.25, 0.58, 0.07), PLATE)
		part(hinge, Vector3(0, 0.30, 0.044), Vector3(0.19, 0.45, 0.022), STEEL)
		part(hinge, Vector3(0, 0.30, 0.061), Vector3(0.04, 0.42, 0.013),
			GLOW if spread > 0.35 and collapse == 0.0 else RED)
	oval(emitter, hub + Vector3(0, 0, 0.12), Vector3(0.20, 0.20, 0.13), INK)
	oval(emitter, hub + Vector3(0, 0, 0.19), Vector3(0.10 + recoil * 0.09,
		0.10 + recoil * 0.09, 0.04), INK if collapse > 0.0 else (GLOW if spread > 0.35 else RED))
	return root
