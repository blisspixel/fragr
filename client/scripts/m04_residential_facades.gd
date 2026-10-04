extends RefCounted

## Three sealed homes follow exact delivered bodies; their substantial shape
## and roof edges are rendered by ArenaCover from authoritative solids.
const Geometry = preload("res://scripts/model_geometry.gd")
const HOMES: Array[Dictionary] = [
	{"low": Vector3(-27, 0, 17), "high": Vector3(-20, 5.5, 24), "window": 21.0, "paint": Color("bda98b")},
	{"low": Vector3(-28, 0, 24), "high": Vector3(-20, 6.2, 31.5), "window": 27.0, "paint": Color("8dada0")},
	{"low": Vector3(-26.5, 0, 31.5), "high": Vector3(-20, 5.15, 39), "window": 35.0, "paint": Color("c3b3a1")},
]
var _mesh: ArrayMesh = ArrayMesh.new()
var _geometry: RefCounted = Geometry.new()
var _tool: SurfaceTool

func build(parent: Node3D, info: Dictionary) -> Node3D:
	var result: Node3D = Node3D.new()
	result.name = "WestResidentialFacades"
	parent.add_child(result)
	var recognized: int = 0
	# No guessed facade, door or roof decoration on a custom M04 layout.
	if not _has(info, Vector3(-20, 0, 17), Vector3(-19.5, 5, 39)):
		result.set_meta("homes", 0)
		return result
	for home: Dictionary in HOMES:
		var low: Vector3 = home["low"]
		var high: Vector3 = home["high"]
		if not _has(info, low, high) or not _has(info,
			Vector3(-20.3, high.y, low.z), Vector3(-20, high.y + 0.22, high.z)):
			continue
		_home(low, high, float(home["window"]), home["paint"])
		recognized += 1
	result.set_meta("homes", recognized)
	if recognized > 0:
		var view: MeshInstance3D = MeshInstance3D.new()
		view.name = "DomesticSurfaceMesh"
		view.mesh = _mesh
		view.layers = ArenaSky.WORLD_LAYERS
		result.add_child(view)
	return result

static func _has(info: Dictionary, low: Vector3, high: Vector3) -> bool:
	for solid: Dictionary in info["solids"]:
		if Vector3(solid["min_x"], solid.get("bottom", 0), solid["min_z"]).is_equal_approx(low) \
			and Vector3(solid["max_x"], solid.get("top", 4), solid["max_z"]).is_equal_approx(high):
			return true
	return false

func _begin(color: Color) -> void:
	_tool = SurfaceTool.new()
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var finish: ShaderMaterial = ArenaMaterials.authored("enamel", "low_water") as ShaderMaterial
	finish.set_shader_parameter("surface_color", color)
	finish.set_shader_parameter("markings_enabled", false)
	finish.set_shader_parameter("tile_strength", 0.3)
	_tool.set_material(finish)

func _end() -> void:
	_tool.commit(_mesh)

func _front(x: float, y0: float, y1: float, z0: float, z1: float) -> void:
	_geometry.quad(_tool, Vector3(x, y0, z0), Vector3(x, y0, z1),
		Vector3(x, y1, z1), Vector3(x, y1, z0), Vector3.RIGHT)

func _home(low: Vector3, high: Vector3, window: float, paint: Color) -> void:
	_begin(paint)
	# Broad domestic paint replaces repeated institutional wall bays. A real
	# opening is not implied: the retained opaque window sits on the same wall.
	_front(-19.499, 0.02, 3.24, low.z + 0.015, high.z - 0.015)
	_front(-19.499, 4.86, 4.99, low.z + 0.015, high.z - 0.015)
	_front(-19.499, 3.24, 4.86, low.z + 0.015, window - 1.05)
	_front(-19.499, 3.24, 4.86, window + 1.05, high.z - 0.015)
	# Exposed upper and side faces make each mass read as a home in the skyline.
	_front(-19.999, 5.0, high.y, low.z, high.z)
	_geometry.quad(_tool, Vector3(low.x, 0, low.z + 0.001), Vector3(low.x, high.y, low.z + 0.001),
		Vector3(high.x, high.y, low.z + 0.001), Vector3(high.x, 0, low.z + 0.001), Vector3.FORWARD)
	_end()
	_begin(paint.darkened(0.2))
	# Flush vertical rain-run paint and a broad maintained window surround,
	# at most six millimetres from the existing wall. No balcony obstruction.
	_front(-19.494, 0.08, 4.98, low.z + 0.045, low.z + 0.16)
	_front(-19.494, 3.24, 3.32, window - 1.05, window + 1.05)
	_front(-19.494, 4.78, 4.86, window - 1.05, window + 1.05)
	_front(-19.494, 3.32, 4.78, window - 1.05, window - 1.0)
	_front(-19.494, 3.32, 4.78, window + 1.0, window + 1.05)
	# The low face is paint, never a door, handle or implied use target.
	_front(-19.493, 0.08, 0.42, low.z + 0.18, high.z - 0.03)
	_end()
	_begin(Color("6e8980"))
	# Roof caps and repairs stay on the registered body/roof-edge surfaces.
	_front(-19.999, high.y + 0.04, high.y + 0.21, low.z + 0.03, high.z - 0.03)
	_geometry.quad(_tool, Vector3(-20.29, high.y + 0.219, low.z + 0.02),
		Vector3(-20.01, high.y + 0.219, low.z + 0.02), Vector3(-20.01, high.y + 0.219, high.z - 0.02),
		Vector3(-20.29, high.y + 0.219, high.z - 0.02), Vector3.UP)
	_geometry.quad(_tool, Vector3(low.x + 0.4, high.y + 0.001, low.z + 0.6),
		Vector3(low.x + 2.8, high.y + 0.001, low.z + 0.6), Vector3(low.x + 2.8, high.y + 0.001, low.z + 2.3),
		Vector3(low.x + 0.4, high.y + 0.001, low.z + 2.3), Vector3.UP)
	_end()
