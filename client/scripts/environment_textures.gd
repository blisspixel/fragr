extends RefCounted
class_name EnvironmentTextures

## Reviewed local material tiles. Venue selects history, surface selects use.
const EARTH: String = "res://assets/environment/earth/"
const MOON: String = "res://assets/environment/moon/surfaces/"
const PRODUCTION: String = "res://assets/environment/production/"
static var _textures: Dictionary[String, Texture2D] = {}

static func path_for(surface: String, venue: String, horizontal: bool = false) -> String:
	if venue == "common_carrier":
		match surface:
			"enamel": return MOON + ("moon_worn_deck.png" if horizontal else "moon_pressure_bone.png")
			"service_steel", "lift_panel": return MOON + ("moon_worn_deck.png" if horizontal else "moon_repair_plate.png")
			"records_tile": return PRODUCTION + "low_water_ceramic.png"
	elif venue == "moon_town":
		match surface:
			"concrete": return MOON + "moon_regolith.png"
			"enamel": return MOON + ("moon_worn_deck.png" if horizontal else "moon_pressure_bone.png")
			"records_tile": return PRODUCTION + "archive_ceramic.png"
			"service_steel": return MOON + "moon_worn_deck.png" if horizontal else PRODUCTION + "archive_steel.png"
			"lift_panel": return MOON + ("moon_worn_deck.png" if horizontal else "moon_repair_plate.png")
	elif venue == "moon_port":
		match surface:
			"concrete": return MOON + "moon_regolith.png"
			"enamel": return PRODUCTION + "archive_enamel.png"
			"records_tile": return PRODUCTION + "archive_ceramic.png"
			"service_steel": return PRODUCTION + ("archive_floor.png" if horizontal else "archive_steel.png")
			"lift_panel": return MOON + ("moon_worn_deck.png" if horizontal else "moon_repair_plate.png")
	elif venue == "low_water":
		match surface:
			"concrete": return PRODUCTION + ("low_water_concrete.png" if horizontal else "low_water_plaster.png")
			"enamel": return PRODUCTION + ("low_water_ceramic.png" if horizontal else "low_water_enamel.png")
			"records_tile": return PRODUCTION + "low_water_ceramic.png"
			"service_steel", "lift_panel": return PRODUCTION + ("low_water_floor.png" if horizontal else "low_water_steel.png")
	elif venue in ["earth_union", "earth_yard", "earth_scrap"]:
		var prefix: String = {"earth_union": "union", "earth_yard": "yard", "earth_scrap": "scrap"}[venue]
		match surface:
			"concrete": return PRODUCTION + prefix + "_concrete.png"
			"enamel": return PRODUCTION + prefix + "_enamel.png"
			"records_tile": return PRODUCTION + prefix + "_ceramic.png"
			"service_steel", "lift_panel": return PRODUCTION + prefix + ("_floor.png" if horizontal else "_steel.png")
	return ""

static func texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path) and ResourceLoader.exists(path):
		var resource: Resource = load(path)
		if resource is Texture2D:
			_textures[path] = resource as Texture2D
	return _textures.get(path) as Texture2D

static func apply(material: ShaderMaterial, surface: String, venue: String) -> void:
	var wall: Texture2D = texture_at(path_for(surface, venue))
	var floor: Texture2D = texture_at(path_for(surface, venue, true))
	if wall == null or floor == null:
		return
	material.set_shader_parameter("tile_enabled", true)
	material.set_shader_parameter("tile_wall", wall)
	material.set_shader_parameter("tile_floor", floor)
	material.set_shader_parameter("tile_strength", 0.35 if venue == "low_water" and surface in ["service_steel", "lift_panel"] else 0.55)
	if venue == "moon_town" and surface == "enamel":
		# Long dwelling fronts retain pressure-shell history without dense
		# panel noise overwhelming their shutters, people and route landmarks.
		material.set_shader_parameter("tile_strength", 0.3)
	# Palette reduction amplifies concrete pits. Keep walking lanes quieter
	# than walls so surface history does not compete with bodies and pickups.
	material.set_shader_parameter("tile_floor_strength", (0.18 if venue == "low_water" else 0.35) if surface == "concrete" else 0.55)
	material.set_shader_parameter("tile_repeat_pixels", 128.0)
