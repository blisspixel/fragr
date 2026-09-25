extends RefCounted
class_name ArenaSky

## The thing above the arena walls, and it is different per venue.
##
## This is values, not a node. The arena scenes already carry a
## WorldEnvironment, so adding a second one produced exactly the duplicate
## shape this codebase keeps getting bitten by: two environments, one of them
## silently ignored, and the black sky still black. The environment built here
## is applied to the one that already exists.
##
## The arena environment drew its background as a flat colour, and the colour
## was palette ink, so everything above the wall line was a black void. In a
## first person shot taken beside cover that void was most of the frame; in
## every spectator shot it was the top quarter. The visual QA tour measured the
## HUD in each of those frames and never measured this, because nothing was
## wrong with the HUD.
##
## Doom solved it with a sky texture on outdoor sectors and a ceiling
## everywhere else, and never showed you nothing. This is the cheap version of
## the same rule: a graded sky the arena sits under, and distance fog in the
## same hues so the far wall recedes instead of ending.
##
## A venue gets its own sky because the sky is the cheapest way to tell two
## maps apart. Two arenas built from the same tiles under the same sky are the
## same place with the furniture moved; change what is above them and they are
## two places. It also carries faction: a scrapyard nobody maintains sits under
## a warm sodium haze, and a Union facility sits under something colder and
## more even, because the Union does not permit weather in its car parks.
##
## The venue also owns its light plan: how strong the scene's key light is,
## what colour the practical fixtures burn, the red authority accents on Union
## seals, and the faint view fill that keeps a dark enemy readable. Quality
## (shadows, contact shading, glow) stays in render_quality.gd.

## Registered practical lights join this group so quality can toggle shadows.
const PRACTICAL_GROUP: StringName = &"fragr_practical_light"
## The name of the view-attached readability fill under the camera.
const VIEW_FILL: String = "ViewFill"
## Server-built world geometry renders on visual layer 2 only. The view fill
## lights layer 1 (fighters, enemies, pickups, effects) and never the walls,
## so a dark room stays dark while whatever is in it stays readable.
const WORLD_LAYERS: int = 2
const ACTOR_LAYERS: int = 1

## One venue's sky and light plan.
class Preset extends RefCounted:
	var sky_top: Color
	var sky_horizon: Color
	var ground_horizon: Color
	var fog_color: Color
	var fog_density: float
	## The flat ambient tint. This is the floor under every light, not the sky.
	var ambient_color: Color
	var ambient_energy: float
	## Enclosed venues ignore the outdoor arena's sun and ember props.
	var interior: bool = false
	## The scene's DirectionalLight3D, and the arena's overhead omni fill.
	var key_color: Color = Color(1.0, 0.86, 0.72)
	var key_energy: float = 1.15
	var scene_fill_energy: float = 0.35
	## Registered strip lights on the map's surfaces.
	var practical_color: Color = Color("ffe7ba")
	var practical_energy: float = 1.25
	var practical_range: float = 9.0
	var practical_attenuation: float = 1.5
	## Union seals burn a small red lamp. Zero turns the accent off.
	var accent_color: Color = Color8(139, 30, 30) # palette.json on_air
	var accent_energy: float = 0.0
	var accent_range: float = 4.0
	## A light at the eye that only reaches actors (see ACTOR_LAYERS). A
	## black-and-red enemy in a dark aisle keeps a lit front toward the player
	## without flattening the room the way a raised ambient floor would.
	var view_fill_energy: float = 0.0
	var view_fill_range: float = 24.0
	var exposure: float = 1.0
	var contrast: float = 1.0
	var saturation: float = 1.0
	var glow_intensity: float = 0.0

	func _init(
		top: Color,
		horizon: Color,
		ground: Color,
		fog: Color,
		density: float,
		ambient_tint: Color,
		ambient: float
	) -> void:
		sky_top = top
		sky_horizon = horizon
		ground_horizon = ground
		fog_color = fog
		fog_density = density
		ambient_color = ambient_tint
		ambient_energy = ambient


## The default, and the outdoor scrapyard look.
##
## The top is cool and dark but deliberately not palette ink. The first attempt
## used ink itself, the darkest value in the game, on the theory that the sky
## should stay out of the way, and it was indistinguishable from the black void
## it replaced. The fix for a void is not a darker void, it is a value the eye
## can separate from the silhouette in front of it.
##
## A slightly lower ambient floor and a stronger, warmer sun than before, so
## cover throws a shadow that reads as a shadow while the whole yard stays lit.
static func scrapyard() -> Preset:
	var preset: Preset = Preset.new(
		Color(0.086, 0.082, 0.106),  # cool night
		Color(0.286, 0.196, 0.141),  # sodium haze
		Color(0.180, 0.129, 0.102),
		Color(0.200, 0.150, 0.118),
		0.009,
		Color(0.66, 0.66, 0.70),     # neutral sky fill against a warm key
		0.72
	)
	preset.key_color = Color(1.0, 0.84, 0.64)  # low sodium sun
	preset.key_energy = 1.45
	preset.scene_fill_energy = 0.2
	preset.view_fill_energy = 0.0
	preset.contrast = 1.06
	preset.glow_intensity = 0.35
	return preset


## A Union facility. Colder, more even, and less weather, because an approved
## venue does not get a sunset. The green bias is the institutional enamel the
## Continuance paints everything it owns.
static func compliance() -> Preset:
	var preset: Preset = Preset.new(
		Color(0.063, 0.075, 0.086),
		Color(0.145, 0.184, 0.176),
		Color(0.110, 0.133, 0.125),
		Color(0.140, 0.170, 0.165),
		0.011,
		Color(0.62, 0.68, 0.66),
		0.7
	)
	preset.key_color = Color(0.90, 0.94, 1.0)
	preset.key_energy = 1.35
	preset.scene_fill_energy = 0.2
	preset.contrast = 1.06
	preset.saturation = 0.94
	preset.glow_intensity = 0.35
	return preset


## An enclosed Union interior. Doom and Dusk readability first: the whole room
## is clearly lit by a warm ambient floor, and the registered strip lights add
## brighter pools with shadows under the fixtures, so shape comes from light
## on top of a readable base rather than from a dark baseline. The haze is a
## light grey-green and thin, so a black-and-red silhouette separates from the
## far end of an aisle instead of dissolving into it, and the actor-only view
## fill gives every enemy a lit front toward the player.
static func facility() -> Preset:
	var preset: Preset = Preset.new(
		Color(0.063, 0.075, 0.086),
		Color(0.145, 0.184, 0.176),
		Color(0.110, 0.133, 0.125),
		Color(0.235, 0.250, 0.230),
		0.012,
		Color(0.78, 0.77, 0.70),     # warm service white, not a green cast
		0.82
	)
	preset.interior = true
	preset.key_color = Color(0.70, 0.80, 0.90)
	preset.key_energy = 0.3
	preset.scene_fill_energy = 0.0
	preset.practical_color = Color(0.93, 0.98, 0.86)  # service fluorescent
	preset.practical_energy = 3.2
	preset.practical_range = 12.0
	preset.practical_attenuation = 1.4
	preset.accent_energy = 2.2
	preset.accent_range = 4.5
	preset.view_fill_energy = 1.0
	preset.view_fill_range = 45.0
	preset.contrast = 1.05
	preset.saturation = 0.97
	preset.glow_intensity = 0.45
	return preset


## Pick the venue's sky by map name.
##
## Matched loosely on the name the server sends, because MapInfo carries a
## display name rather than an identifier, and an unknown venue gets the
## scrapyard rather than nothing. Recall Notice and the Persons Unknown ward are
## interiors, so they do not inherit the outdoor scrap fill.
static func preset_for(map_name: String) -> Preset:
	var key: String = map_name.strip_edges().to_lower()
	if key.contains("recall") or key.contains("persons unknown"):
		return facility()
	if key.contains("compliance") or key.contains("yard"):
		return compliance()
	return scrapyard()


## Built in code rather than as a scene sub-resource on purpose. A sub-resource
## dropped into the wrong half of a .tscn file silently invalidates the scene,
## which has cost this project a client boot once already.
static func build_environment(map_name: String = "") -> Environment:
	var preset: Preset = preset_for(map_name)

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = preset.sky_top
	sky_material.sky_horizon_color = preset.sky_horizon
	sky_material.ground_bottom_color = preset.sky_top
	sky_material.ground_horizon_color = preset.ground_horizon
	sky_material.sun_angle_max = 30.0
	sky_material.energy_multiplier = 1.0

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	# Ambient stays a flat colour, and this is the important line in the file.
	#
	# Taking ambient from the sky instead looks correct on paper and was wrong
	# here: this sky is a dark night sky, so sky-derived ambient is far dimmer
	# than the flat tint the arenas were authored against, and every surface
	# lost its light at once. A cover block two metres from the camera went
	# pure black and filled most of a first person frame, which is a worse bug
	# than the black void this file was written to fix.
	#
	# The lesson is that a background and a light are two different jobs. The
	# sky is scenery; the ambient tint is the floor that keeps a wall readable.
	# The look pass lowered that floor and put the difference into real lights,
	# so shade has somewhere to be without any surface going to pure black.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = preset.ambient_color
	env.ambient_light_energy = preset.ambient_energy

	# Fog so the far end of a large map recedes. Without it a bigger arena just
	# puts the same flat wall further away, which is the failure mode every
	# time a map is scaled up.
	env.fog_enabled = true
	env.fog_light_color = preset.fog_color
	env.fog_density = preset.fog_density
	env.fog_sky_affect = 0.0

	# Filmic keeps a bright fixture from clipping to a flat white card while
	# the ambient floor stays where it was authored.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = preset.exposure
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = preset.contrast
	env.adjustment_saturation = preset.saturation

	# Glow is off here; quality turns it on at Balanced and above. Only emissive
	# fixtures and lamps reach the threshold, so it never washes the frame.
	env.glow_enabled = false
	env.glow_intensity = preset.glow_intensity
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	return env


## Retune the lights the arena scene ships for this venue. The arena scene was
## authored outdoors: a sun, an overhead fill and three ember lamps near the
## origin. An interior keeps a faint cool key for any open shaft and drops the
## embers, which would otherwise glow orange in the middle of intake.
static func apply_scene_lights(layout: Node, map_name: String) -> void:
	if layout == null:
		return
	var preset: Preset = preset_for(map_name)
	var key: DirectionalLight3D = layout.get_node_or_null("KeyLight") as DirectionalLight3D
	if key != null:
		key.light_color = preset.key_color
		key.light_energy = preset.key_energy
		key.visible = preset.key_energy > 0.0
	var fill: OmniLight3D = layout.get_node_or_null("FillLight") as OmniLight3D
	if fill != null:
		fill.light_energy = preset.scene_fill_energy
		fill.visible = preset.scene_fill_energy > 0.0
	for ember: String in ["EmberPit", "EmberCornerNE", "EmberCornerSW"]:
		var lamp: Node3D = layout.get_node_or_null(ember) as Node3D
		if lamp != null:
			lamp.visible = not preset.interior


## One faint fill at the eye, kept under the active camera. No shadow map, no
## cost worth measuring, and removed where the venue does not use it.
static func apply_view_fill(camera: Camera3D, map_name: String) -> void:
	if camera == null:
		return
	var preset: Preset = preset_for(map_name)
	var fill: OmniLight3D = camera.get_node_or_null(VIEW_FILL) as OmniLight3D
	if preset.view_fill_energy <= 0.0:
		if fill != null:
			fill.queue_free()
		return
	if fill == null:
		fill = OmniLight3D.new()
		fill.name = VIEW_FILL
		camera.add_child(fill)
	fill.light_color = Color(0.86, 0.88, 0.92)
	fill.light_energy = preset.view_fill_energy
	fill.light_specular = 0.0
	fill.omni_range = preset.view_fill_range
	# A shallow falloff: about half the near strength still arrives at ten
	# metres and about a sixth at thirty, the far end of an M01 aisle.
	fill.omni_attenuation = 0.5
	fill.light_cull_mask = ACTOR_LAYERS
	fill.shadow_enabled = false


## Move built world geometry off the actor layer. The camera still draws every
## layer; only the view fill tells them apart.
static func mark_world(root: Node) -> void:
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = WORLD_LAYERS
