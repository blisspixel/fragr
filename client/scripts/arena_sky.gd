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

## One venue's sky.
class Preset extends RefCounted:
	var sky_top: Color
	var sky_horizon: Color
	var ground_horizon: Color
	var fog_color: Color
	var fog_density: float
	## The flat ambient tint. This is what lights the arena, not the sky.
	var ambient_color: Color
	var ambient_energy: float

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
static func scrapyard() -> Preset:
	return Preset.new(
		Color(0.086, 0.082, 0.106),  # cool night
		Color(0.286, 0.196, 0.141),  # sodium haze
		Color(0.180, 0.129, 0.102),
		Color(0.125, 0.094, 0.078),
		0.006,
		Color(0.68, 0.65, 0.60),
		0.8
	)


## A Union facility. Colder, more even, and less weather, because an approved
## venue does not get a sunset. The green bias is the institutional enamel the
## Continuance paints everything it owns.
static func compliance() -> Preset:
	return Preset.new(
		Color(0.063, 0.075, 0.086),
		Color(0.145, 0.184, 0.176),
		Color(0.110, 0.133, 0.125),
		Color(0.090, 0.110, 0.106),
		0.009,
		Color(0.61, 0.67, 0.64),
		0.8
	)


## Pick the venue's sky by map name.
##
## Matched loosely on the name the server sends, because MapInfo carries a
## display name rather than an identifier, and an unknown venue gets the
## scrapyard rather than nothing.
static func preset_for(map_name: String) -> Preset:
	var key: String = map_name.strip_edges().to_lower()
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
	# sky is scenery; the ambient tint is what makes a wall readable.
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

	return env
