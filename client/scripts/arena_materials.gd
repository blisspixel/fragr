extends RefCounted
class_name ArenaMaterials

## One palette and material set per map. Geometry stays owned by MapInfo.
const SURFACE: Shader = preload("res://assets/shaders/arena_surface.gdshader")
const PLASTER_DETAIL: Texture2D = preload("res://assets/environment/low_water/plaster_repairs.png")
const STEEL_DETAIL: Texture2D = preload("res://assets/environment/low_water/steel_repairs.png")
static var _moon_textures: Dictionary[String, Texture2D] = {}

static func scenery_tile(path: String, base: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("surface_color", base)
	material.set_shader_parameter("markings_enabled", false)
	material.set_shader_parameter("base_shade", 0.0)
	var texture: Texture2D = EnvironmentTextures.texture_at(path)
	if texture != null:
		material.set_shader_parameter("tile_enabled", true)
		material.set_shader_parameter("tile_wall", texture)
		material.set_shader_parameter("tile_floor", texture)
		material.set_shader_parameter("tile_strength", 0.7)
		material.set_shader_parameter("tile_floor_strength", 0.7)
	return material

## Street decking has no issued warning signal. Duplicate only this material
## so the same authored steel on the post and barriers keeps its red markings.
static func ground(material: Material, surface: String, venue: String) -> Material:
	if venue != "moon_town" or surface != "service_steel" or not material is ShaderMaterial:
		return material
	var deck: ShaderMaterial = material.duplicate() as ShaderMaterial
	deck.set_shader_parameter("surface_color", Color("505954"))
	deck.set_shader_parameter("accent_color", Color("7f8278"))
	deck.set_shader_parameter("warning_color", Color("7f8278"))
	deck.set_shader_parameter("trim_glow", 0.0)
	return deck

static func accent(map_id: int) -> Color:
	match map_id:
		2, 4: return Color("6e1218")
		3: return Color("4a8a92")
		5: return Color("6e7950")
		6: return Color("8a3a58")
		7: return Color("4d7870")
		1004, 1005: return Color("8b6850")
		1006, 1007, 1008: return Color("b7aea0")
		_: return Color("7a3a22")

static func make(map_id: int, kind: int) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE
	var base: Color = Color("676964") if kind == 0 else Color("727a79")
	if map_id == 2 or map_id == 4:
		base = Color("646965") if kind == 0 else Color("879184")
	elif map_id == 5:
		base = Color("756e59") if kind == 0 else Color("73796a")
	elif map_id == 7:
		base = Color("b8ab7d") if kind == 0 else Color("b8c1aa")
	elif map_id in [1004, 1005]:
		base = Color("686f69") if kind == 0 else Color("8c796a")
	elif map_id in [1006, 1007, 1008]:
		base = Color("a9a698") if kind == 0 else Color("8b8e87")
	if kind == 2:
		base = base.darkened(0.15)
	material.set_shader_parameter("surface_color", base)
	material.set_shader_parameter("accent_color", accent(map_id))
	material.set_shader_parameter("surface_kind", kind)
	material.set_shader_parameter("panel_size", 3.0 if kind == 0 else (4.0 if kind == 1 else 2.0))
	if map_id == 7:
		material.set_shader_parameter("markings_enabled", kind != 0)
		material.set_shader_parameter("surface_style", 1)
		material.set_shader_parameter("trim_glow", 0.0)
		material.set_shader_parameter("warning_color", Color("73816c"))
		EnvironmentTextures.apply(material, "concrete", "low_water")
		material.set_shader_parameter("tile_strength", 0.25)
	if map_id == 1:
		EnvironmentTextures.apply(material, "concrete" if kind == 0 else "service_steel", "earth_scrap")
	return material

static func authored(surface: String, venue: String = "") -> Material:
	if venue == "mars_foundry" and surface == "records_tile":
		# This venue reserves the registered surface for three shielded process
		# solids. Its steady light is appearance only, with no heat rule.
		var process: StandardMaterial3D = StandardMaterial3D.new()
		process.albedo_color = Color("d78d47")
		process.albedo_texture = EnvironmentTextures.texture_at(OffworldMaterials.DIRECTORY + "offworld_thermal_ceramic.png")
		process.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		process.roughness = 1.0
		process.metallic_specular = 0.0
		process.emission_enabled = true
		process.emission = Color("b05b22")
		process.emission_energy_multiplier = 1.3
		return process
	if surface == "inspection_glass":
		var glass: StandardMaterial3D = StandardMaterial3D.new()
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(0.31, 0.52, 0.53, 0.38)
		glass.roughness = 0.85
		glass.metallic_specular = 0.0
		glass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		return glass
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE
	var index: int = MapGeometry.SURFACES.find(surface)
	# Issued service steel retains its red markings. Civilian enamel receives
	# its venue's quiet paint rather than the shader's default warning pinline.
	var bases: Array[Color] = [Color("787468"), Color("c5c1a6"), Color("565753"), Color("82917f"), Color("343e40")]
	var accents: Array[Color] = [Color("686954"), Color("52664d"), Color("8b1e1e"), Color("354d42"), Color("7eaaa0")]
	if venue == "right_of_search":
		bases = [Color("777f7e"), Color("aeb9b6"), Color("3b494c"), Color("7e9995"), Color("263b40")]
		accents = [Color("4b6566"), Color("3d6264"), Color("708c8e"), Color("315557"), Color("91aca3")]
	elif venue == "common_carrier":
		bases = [Color("787468"), Color("c9bd9f"), Color("46514f"), Color("849283"), Color("394c4e")]
		accents = [Color("666756"), Color("82745f"), Color("798172"), Color("617164"), Color("71928c")]
	elif venue == "low_water":
		bases = [Color("788078"), Color("bd9c80"), Color("537574"), Color("adc0aa"), Color("49534c")]
		accents = [Color("5a655f"), Color("6f6554"), Color("aa7451"), Color("577165"), Color("b6a579")]
	elif venue in ["launch_works", "mars_habitat"]:
		bases = [Color("ab7961"), Color("c7c5b1"), Color("414b4b"), Color("a4b0a3"), Color("424f50")]
		accents = [Color("835d4d"), Color("7c8473"), Color("9a302a"), Color("657d6d"), Color("9aafa6")]
	elif venue == "mars_foundry":
		bases = [Color("818276"), Color("c5bda7"), Color("394749"), Color("d78d47"), Color("465552")]
		accents = [Color("636d65"), Color("7c8172"), Color("79928d"), Color("b05b22"), Color("99aaa1")]
	elif venue in ["moon_port", "moon_town"]:
		bases = [Color("a9a698"), Color("d0cbb8"), Color("394144"), Color("9aa397"), Color("505954")]
		accents = [Color("6c6e64"), Color("7f8278"), Color("9a302a"), Color("4e5c55"), Color("a9ad99")]
	material.set_shader_parameter("surface_style", index + 1)
	material.set_shader_parameter("surface_color", bases[index])
	material.set_shader_parameter("accent_color", accents[index])
	if venue in ["low_water", "common_carrier", "right_of_search", "mars_foundry"] or (venue == "moon_town" and surface == "enamel") or (venue in ["launch_works", "mars_habitat"] and surface in ["concrete", "enamel", "records_tile"]):
		material.set_shader_parameter("warning_color", accents[index])
		material.set_shader_parameter("trim_glow", 0.0)
	material.set_shader_parameter("panel_size", 2.0)
	EnvironmentTextures.apply(material, surface, venue)
	if venue == "launch_works" and surface == "concrete":
		# This venue uses dust and berm terrain. Keep
		# its pixel grain without painting an institutional slab grid over it.
		material.set_shader_parameter("markings_enabled", false)
		material.set_shader_parameter("panel_contrast", 0.2)
	if venue == "low_water" and surface in ["concrete", "enamel", "service_steel"]:
		material.set_shader_parameter("detail_enabled", true)
		material.set_shader_parameter("detail_texture", STEEL_DETAIL if surface == "service_steel" else PLASTER_DETAIL)
	elif venue in ["moon_port", "moon_town"] and surface in ["concrete", "enamel", "service_steel"] \
		and material.get_shader_parameter("tile_enabled") != true:
		var path: String = "res://assets/environment/moon/" + ("dust.png" if surface == "concrete" else "pressure_shell.png")
		if not _moon_textures.has(path) and ResourceLoader.exists(path):
			_moon_textures[path] = load(path) as Texture2D
		if _moon_textures.get(path) != null:
			material.set_shader_parameter("detail_enabled", true)
			material.set_shader_parameter("detail_texture", _moon_textures[path])
	return material
