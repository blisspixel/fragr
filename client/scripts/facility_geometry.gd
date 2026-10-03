extends RefCounted

const Workshop = preload("res://scripts/model_geometry.gd")
var g: RefCounted = Workshop.new()
var steel: StandardMaterial3D = g.material("fixture_graphite", Color("454e4b"), 0.45, 0.65)
var bone: StandardMaterial3D = g.material("fixture_bone", Color("bdbba8"), 0.1, 0.72)
var dark: StandardMaterial3D = g.material("fixture_recess", Color("222a29"), 0.0, 0.86)

## Visible housings stay within 8 mm of their registered face. Deep components
## are inset into the host solid and never suggest new traversable geometry.
func build(kind: String, size: Vector2 = Vector2.ONE) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "FixtureHousing"
	var trim: float = minf(0.045, minf(size.x, size.y) * 0.12)
	var border: StandardMaterial3D = bone if kind == "strip_light" else steel
	for side: float in [-1.0, 1.0]:
		g.block(root, "SideFrame%d" % int(side), Vector3(trim, size.y, 0.04), border, Vector3(side * (size.x - trim) * 0.5, 0, -0.014))
		g.block(root, "EndFrame%d" % int(side), Vector3(size.x - trim * 2.0, trim, 0.04), border, Vector3(0, side * (size.y - trim) * 0.5, -0.014))
	for side: float in [-1.0, 1.0]:
		for row: float in [-1.0, 1.0]:
			g.cylinder(root, "CaptiveScrew%d_%d" % [int(side), int(row)], trim * 0.18, 0.006, dark, Vector3(side * (size.x - trim) * 0.5, row * (size.y - trim) * 0.5, 0.004), 8)
	if kind == "vent":
		var count: int = clampi(int(size.y / 0.075), 3, 16)
		for index: int in range(count):
			var y: float = -size.y * 0.5 + trim + (index + 0.5) * (size.y - trim * 2.0) / count
			var louver: MeshInstance3D = g.block(root, "Louver%d" % index, Vector3(size.x - trim * 2.0, 0.008, 0.032), steel, Vector3(0, y, -0.01))
			louver.rotation.x = -0.45
	elif kind in ["terminal", "lift_control", "m04_clinic_control", "m04_roof_departure", "m08_freight_departure", "m08_bay_release"]:
		g.block(root, "DisplayBottomBezel", Vector3(size.x * 0.9, size.y * 0.08, 0.015), dark, Vector3(0, -size.y * 0.36, -0.002))
		for index: int in range(4):
			g.block(root, "PhysicalKey%d" % index, Vector3(size.x * 0.065, size.y * 0.025, 0.009), bone, Vector3((-1.5 + index) * size.x * 0.11, -size.y * 0.365, 0.003))
	elif kind == "lockers":
		for column: int in range(3):
			var x: float = (column - 1.0) * size.x / 3.0
			g.block(root, "RecessedPull%d" % column, Vector3(trim * 0.35, minf(size.y * 0.14, 0.14), 0.01), dark, Vector3(x + size.x * 0.065, -size.y * 0.05, 0.002))
			for index: int in range(3):
				g.block(root, "LockerVent%d_%d" % [column, index], Vector3(size.x * 0.19, trim * 0.12, 0.004), dark, Vector3(x, size.y * 0.29 + index * trim * 0.3, 0.003))
	g.merge(root)
	return root
