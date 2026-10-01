extends "res://art/characters/geometry.gd"

## Original black-box silhouette shares the passive gallery drone's twin ducts.
func build(action: String, progress: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var housing: Node3D = Node3D.new()
	housing.position.y = 0.35
	root.add_child(housing)
	var bright: bool = action in ["windup", "fire"]
	var wreck: bool = action == "wreck"
	part(housing, Vector3.ZERO, Vector3(0.7, 0.37, 0.48), STEEL)
	part(housing, Vector3(0, -0.19, 0), Vector3(0.61, 0.15, 0.42), PLATE)
	part(housing, Vector3(0, -0.025, 0.255), Vector3(0.36, 0.22, 0.045), INK)
	var aperture: float = 0.18 + progress * 0.1 if action == "windup" else 0.28 if action == "fire" else 0.105
	var flare: Color = GLOW if bright else RED.darkened(0.35)
	if wreck or action == "tumble":
		flare = INK
	part(housing, Vector3(0, -0.025, 0.285), Vector3(aperture, aperture * 0.62, 0.022), flare)
	if bright:
		part(housing, Vector3(0, -0.025, 0.30), Vector3(aperture * 0.53, aperture * 0.31, 0.012), Color("ffd29a"))
	part(housing, Vector3(0.23, 0.08, 0.252), Vector3(0.08, 0.07, 0.015), RED)
	for side: float in [-1.0, 1.0]:
		part(housing, Vector3(side * 0.39, 0.12, 0), Vector3(0.18, 0.08, 0.11), STEEL)
		var duct: Node3D = Node3D.new()
		duct.position = Vector3(side * 0.42, 0.25, 0)
		housing.add_child(duct)
		var ring: MeshInstance3D = MeshInstance3D.new()
		var mesh: TorusMesh = TorusMesh.new()
		mesh.inner_radius = 0.14
		mesh.outer_radius = 0.23
		mesh.rings = 16
		mesh.ring_segments = 6
		ring.mesh = mesh
		ring.material_override = material(PLATE)
		duct.add_child(ring)
		part(duct, Vector3.ZERO, Vector3(0.07, 0.06, 0.07), INK)
		for blade: int in range(3):
			var pivot: Node3D = Node3D.new()
			pivot.rotation.y = float(blade) * TAU / 3.0 + progress * PI
			duct.add_child(pivot)
			part(pivot, Vector3(0, 0, 0.115), Vector3(0.045, 0.016, 0.15), STEEL.lightened(0.22))
		part(housing, Vector3(side * 0.2, -0.28, 0), Vector3(0.04, 0.12, 0.32), INK)
	if action == "tumble":
		housing.rotation_degrees = Vector3(progress * 70.0, 0, progress * 105.0)
	elif wreck:
		housing.rotation_degrees.z = 18.0
		housing.position.y = 0.22
	elif action == "hit":
		housing.rotation_degrees.z = -12.0
	elif action == "recovery":
		housing.rotation_degrees.z = 5.0 * (1.0 - progress)
	return root
