extends RefCounted
class_name OffworldMaterials

## Inspected material library. This does not register a playable Mars map.
const SIZE: int = 128
const TEXELS_PER_METRE: int = 16
const IDS: Array[String] = ["mars_basalt", "mars_regolith", "offworld_pressure_habitat", "offworld_mining_deck", "offworld_thermal_ceramic"]
const DIRECTORY: String = "res://assets/environment/offworld/"
static var _textures: Dictionary[String, Texture2D] = {}

static func describe(id: String) -> Dictionary:
	match id:
		"mars_basalt":
			return {"path": DIRECTORY + "mars_basalt.png", "purpose": "dark fractured Mars exterior rock", "venue": "future Mars exterior"}
		"mars_regolith":
			return {"path": DIRECTORY + "mars_regolith.png", "purpose": "quiet dust-red Mars ground", "venue": "future Mars exterior"}
		"offworld_pressure_habitat":
			return {"path": DIRECTORY + "offworld_pressure_habitat.png", "purpose": "maintained pale pressure cladding", "venue": "future enclosed habitat"}
		"offworld_mining_deck":
			return {"path": DIRECTORY + "offworld_mining_deck.png", "purpose": "worn industrial walking plate", "venue": "future mining or freight deck"}
		"offworld_thermal_ceramic":
			return {"path": DIRECTORY + "offworld_thermal_ceramic.png", "purpose": "pale thermal shield ceramic", "venue": "future launch service or habitat"}
	return {}

static func texture(id: String) -> Texture2D:
	var descriptor: Dictionary = describe(id)
	if descriptor.is_empty():
		return null
	if not _textures.has(id):
		var path: String = descriptor.path
		if not ResourceLoader.exists(path):
			return null
		var loaded: Resource = load(path)
		if not loaded is Texture2D:
			return null
		_textures[id] = loaded as Texture2D
	return _textures[id]

static func make(id: String) -> StandardMaterial3D:
	var tile: Texture2D = texture(id)
	if tile == null:
		return null
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = tile
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.texture_repeat = true
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	return material
