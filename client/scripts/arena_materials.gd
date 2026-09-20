extends RefCounted
class_name ArenaMaterials

## One palette and material set per map. Geometry stays owned by MapInfo.
const SURFACE: Shader = preload("res://assets/shaders/arena_surface.gdshader")

static func accent(map_id: int) -> Color:
	match map_id:
		2, 4: return Color("6e1218")
		3: return Color("4a8a92")
		5: return Color("6e7950")
		6: return Color("8a3a58")
		_: return Color("7a3a22")

static func make(map_id: int, kind: int) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE
	var base: Color = Color("676964") if kind == 0 else Color("727a79")
	if map_id == 2 or map_id == 4:
		base = Color("646965") if kind == 0 else Color("879184")
	elif map_id == 5:
		base = Color("756e59") if kind == 0 else Color("73796a")
	if kind == 2:
		base = base.darkened(0.15)
	material.set_shader_parameter("surface_color", base)
	material.set_shader_parameter("accent_color", accent(map_id))
	material.set_shader_parameter("surface_kind", kind)
	material.set_shader_parameter("panel_size", 3.0 if kind == 0 else (4.0 if kind == 1 else 2.0))
	return material

static func authored(surface: String) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE
	var index: int = MapGeometry.SURFACES.find(surface)
	var bases: Array[Color] = [Color("787468"), Color("c5c1a6"), Color("64675f"), Color("82917f"), Color("343e40")]
	var accents: Array[Color] = [Color("686954"), Color("52664d"), Color("b9843e"), Color("354d42"), Color("7eaaa0")]
	material.set_shader_parameter("surface_style", index + 1)
	material.set_shader_parameter("surface_color", bases[index])
	material.set_shader_parameter("accent_color", accents[index])
	material.set_shader_parameter("panel_size", 2.0)
	return material
