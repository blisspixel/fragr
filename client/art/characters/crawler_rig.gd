extends "res://art/characters/geometry.gd"

## Original low Union chassis. A constrained service machine, not an animal.
## The server moves its feet and chooses phases; these poses only change shape.
func build_pose(action: String, progress: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var step: float = progress * TAU if action == "scuttle" else 0.0
	var crouch: float = progress if action == "crouch" else 0.0
	var leap: float = sin(progress * PI) if action == "leap" else 0.0
	var land: float = 1.0 - progress if action == "land" else 0.0
	var pain: float = sin(progress * PI) if action == "hit" else 0.0
	var collapse: float = progress if action == "death" else 0.0
	var pitch: float = leap * 6.0 - land * 8.0 + pain * 10.0 + collapse * 22.0
	var body: Node3D = Node3D.new()
	root.add_child(body)
	body.position = Vector3(0, -crouch * 0.13 - collapse * 0.26,
		-crouch * 0.12 + leap * 0.14)
	body.rotation_degrees.x = pitch
	# Long, low armored wedge with a protected drive spine and service plating.
	part(body, Vector3(0, 0.47, -0.14), Vector3(0.68, 0.27, 1.04), STEEL)
	part(body, Vector3(0, 0.63, -0.2), Vector3(0.59, 0.075, 0.74), PLATE)
	part(body, Vector3(0, 0.69, -0.29), Vector3(0.31, 0.045, 0.34), INK)
	for side: float in [-1.0, 1.0]:
		part(body, Vector3(side * 0.32, 0.53, -0.12),
			Vector3(0.11, 0.20, 0.83), PLATE)
		part(body, Vector3(side * 0.22, 0.665, -0.16),
			Vector3(0.05, 0.025, 0.42),
			GLOW if action in ["crouch", "leap"] else RED)
	# Blunt front cutter is an issued tool repurposed as a close attack.
	part(body, Vector3(0, 0.42, 0.48 + leap * 0.14),
		Vector3(0.52, 0.16, 0.28), PLATE)
	part(body, Vector3(0, 0.40, 0.64 + leap * 0.14),
		Vector3(0.34, 0.065, 0.08), INK)
	part(body, Vector3(0, 0.47, 0.655 + leap * 0.14),
		Vector3(0.29, 0.045, 0.025), INK if action == "death" else GLOW)
	# The rear pressure pack and square exhaust make the back readable.
	part(body, Vector3(0, 0.50, -0.72), Vector3(0.46, 0.34, 0.23), PLATE)
	for side: float in [-1.0, 1.0]:
		part(body, Vector3(side * 0.13, 0.53, -0.85), Vector3(0.10, 0.11, 0.025), INK)
		part(body, Vector3(side * 0.13, 0.53, -0.87), Vector3(0.045, 0.04, 0.013), RED)
	# Four low hydraulic arms stretch forwards in the leap, clamp in the tell,
	# and splay on death. Their outline is the attack read, not just the optic.
	for front: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var z: float = 0.38 if front > 0.0 else -0.48
			var cycle: float = step + (PI if front * side < 0.0 else 0.0)
			var stride: float = cos(cycle) * 0.19 if action == "scuttle" else 0.0
			var lift: float = maxf(sin(cycle), 0.0) * 0.13 if action == "scuttle" else 0.0
			var root_joint: Vector3 = body.position + Vector3(side * 0.31, 0.49, z)
			var elbow: Vector3 = Vector3(side * (0.47 + crouch * 0.10 + collapse * 0.11),
				0.31 - crouch * 0.09 + leap * 0.10 - collapse * 0.12,
				z + front * (0.14 + leap * 0.23) + stride)
			var foot: Vector3 = Vector3(side * (0.52 + crouch * 0.10 + collapse * 0.20),
				0.08 + lift + leap * 0.06,
				z + front * (0.30 + leap * 0.37) + stride)
			limb(root, root_joint, elbow, 0.11, 0.13, STEEL)
			joint(root, elbow, 0.09, PLATE)
			limb(root, elbow, foot, 0.10, 0.13, PLATE)
			part(root, foot + Vector3(0, -0.025, front * 0.065),
				Vector3(0.16, 0.07, 0.19), INK)
	return root
