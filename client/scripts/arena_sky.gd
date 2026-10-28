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
## Glow shape, from the most local level (1) to the blurriest (7). Forward+
## and Mobile read these; Compatibility has its own fixed blur.
## The threshold is tested on the half-resolution first level, so a bulb two
## pixels across averages below it and stays crisp; a lamp head, a lit window
## or a sign letter clears it. The short ramp (HDR scale) lets an emitter just
## over the line glow fully instead of fading in over two more stops.
const GLOW_LEVELS: Array[float] = [1.0, 0.9, 0.35, 0.0, 0.0, 0.0, 0.0]
const GLOW_THRESHOLD: float = 0.85
const GLOW_HDR_SCALE: float = 1.0
const GLOW_LUMINANCE_CAP: float = 6.0

## One venue's sky and light plan.
class Preset extends RefCounted:
	var sky_top: Color
	var sky_horizon: Color
	var ground_horizon: Color
	var haze_below_horizon: bool = false
	var fog_color: Color
	var fog_density: float
	## A low haze layer: the fog thickens below `fog_height` (world metres) at
	## `fog_height_density` per metre. Godot's height fog depends on height
	## alone, not distance, so it tints every surface under the line by the
	## same amount; keep it thin and below a fighter's chest. Zero is off.
	var fog_height: float = 0.0
	var fog_height_density: float = 0.0
	## The flat ambient tint. This is the floor under every light, not the sky.
	var ambient_color: Color
	var ambient_energy: float
	## Enclosed venues ignore the outdoor arena's sun and ember props.
	var interior: bool = false
	var outdoor_embers: bool = true
	## The scene's DirectionalLight3D, and the arena's overhead omni fill.
	var key_color: Color = Color(1.0, 0.86, 0.72)
	var key_energy: float = 1.15
	## Euler degrees for the key light, or zero to keep the scene's own aim.
	var key_rotation_degrees: Vector3 = Vector3.ZERO
	## False keeps the key out of the sky: a city glow is not a sun disc.
	var key_in_sky: bool = true
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


## Recall Notice's civic intake (docs/design/earth.md): bone enamel and green
## tile under cold institutional strips, with warm service lamps where people
## work. The ambient floor keeps the facility's readable base, a step cooler and
## lower so the fixture pools and the warm lamps shape the rooms instead of one
## flat wash. The night street outside the annex shows its own sky.
static func intake() -> Preset:
	var preset: Preset = facility()
	preset.sky_top = Color(0.035, 0.043, 0.063)
	preset.sky_horizon = Color(0.176, 0.153, 0.149)
	preset.ground_horizon = Color(0.090, 0.086, 0.086)
	preset.fog_color = Color(0.180, 0.196, 0.188)
	preset.fog_density = 0.010
	# A cooler, lower floor than the ward: about half the facility's
	# luminance, so pools and shade read. The actor fill keeps enemies lit.
	preset.ambient_color = Color(0.5, 0.53, 0.5)
	preset.ambient_energy = 0.75
	preset.practical_color = Color(0.86, 0.95, 0.88)  # institutional fluorescent
	preset.practical_energy = 4.2
	preset.practical_range = 13.0
	preset.practical_attenuation = 1.3
	preset.contrast = 1.1
	preset.saturation = 1.0
	return preset

## Persons Unknown's correction rooms (docs/design/earth.md): issued steel and
## controlled enamel under bounded fixture light. The floor sits a step below
## the intake's, so the cold strips, the hard pool over the restraint frame and
## the few warm lamps where staff work shape each room; the actor fill keeps
## black-and-red guards readable against the enamel and the dark machinery.
static func correction() -> Preset:
	var preset: Preset = facility()
	preset.fog_color = Color(0.165, 0.180, 0.176)
	preset.fog_density = 0.011
	preset.ambient_color = Color(0.50, 0.53, 0.51)
	preset.ambient_energy = 0.88
	preset.practical_color = Color(0.84, 0.93, 0.92)  # issued cold fluorescent
	preset.practical_energy = 3.8
	preset.practical_range = 11.0
	preset.practical_attenuation = 1.35
	preset.contrast = 1.12
	preset.saturation = 0.95
	return preset

## The warm service lamp: a caged tungsten bulb over a counter, a stair or a
## service door. Short reach and no shadow map, so a room can carry several.
const SERVICE_LAMP_COLOR: Color = Color(1.0, 0.74, 0.46)

## Pick the venue's sky by map name.
##
## Matched loosely on the name the server sends, because MapInfo carries a
## display name rather than an identifier, and an unknown venue gets the
## scrapyard rather than nothing. Recall Notice and the Persons Unknown ward are
## interiors, so they do not inherit the outdoor scrap fill.
static func preset_for(map_name: String) -> Preset:
	var key: String = map_name.strip_edges().to_lower()
	if key.contains("larak"):
		return larak_lot()
	if key in ["launch authority", "launch authority (development)", "continuance walker (development)"]:
		return mars_launch()
	if key in ["terms of cooperation", "terms of cooperation (development)", "arc maintenance (development)"]:
		return mars_habitat()
	if key in ["the weight of permission (development)", "the weight of permission"]:
		return mars_foundry()
	if key.contains("holdfast"):
		return holdfast()
	if key.contains("common carrier") or key.contains("right of search"):
		return carrier()
	if key.contains("port of entry"):
		return port_of_entry()
	if key.contains("passenger manifest"):
		return moon_port()
	if key.contains("custodian of record") or key.contains("custody device range"):
		return moon_archive()
	if key.contains("declared goods"):
		return moon_town()
	if key.contains("planned works"):
		return planned_works()
	if key.begins_with("still here"):
		return still_here_later() if key.contains("years later") else still_here()
	if key.contains("local exception"):
		return waterworks()
	if key.contains("notice to vacate"):
		return notice_to_vacate()
	if key == "low water" or key.contains("low water market") or key.contains("no forwarding address"):
		return low_water()
	if key.contains("scheduled service") or key.contains("recall freight yard"):
		return freight_yard()
	if key.begins_with("recall notice"):
		return intake()
	if key.contains("persons unknown"):
		return correction()
	if key.contains("recall"):
		return facility()
	if key.contains("compliance") or key.contains("yard"):
		return compliance()
	return scrapyard()

## Dust-filtered afternoon over launch services. Neutral work lights and pale
## shielding preserve enemy silhouettes against the rust terrain.
static func mars_launch() -> Preset:
	var preset: Preset = Preset.new(Color("8d786d"), Color("d9aa83"),
		Color("97644c"), Color("c29b7a"), 0.0015, Color("d6cec2"), 0.72)
	preset.outdoor_embers = false
	preset.key_color = Color("ffdeb2")
	preset.key_energy = 1.3
	preset.scene_fill_energy = 0.10
	preset.practical_color = Color("e1ebe5")
	preset.practical_energy = 1.7
	preset.practical_range = 10.0
	preset.view_fill_energy = 0.4
	preset.view_fill_range = 60.0
	preset.contrast = 1.05
	preset.saturation = 0.9
	return preset

## Protected habitat courts retain amber daylight with quieter, neutral work
## light under their authored roofs. This is an exterior development venue.
static func mars_habitat() -> Preset:
	var preset: Preset = mars_launch()
	preset.sky_top = Color("a18b7c")
	preset.sky_horizon = Color("dfba98")
	preset.fog_color = Color("c8ac91")
	preset.fog_density = 0.0018
	preset.ambient_color = Color("d4dbd0")
	preset.ambient_energy = 0.78
	preset.practical_energy = 2.0
	preset.key_energy = 1.1
	return preset

## The foundry is roofed working space. Neutral task lighting keeps fighters
## separate from the protected warm process surfaces and exterior Mars dust.
static func mars_foundry() -> Preset:
	var preset: Preset = mars_launch()
	preset.interior = true
	preset.ambient_color = Color("c9d0ca")
	preset.ambient_energy = 0.82
	preset.key_energy = 0.0
	preset.scene_fill_energy = 0.0
	preset.practical_color = Color("e3ede5")
	preset.practical_energy = 2.1
	preset.practical_range = 13.0
	preset.view_fill_energy = 0.48
	preset.view_fill_range = 45.0
	preset.fog_density = 0.0008
	return preset

static func holdfast() -> Preset:
	var preset: Preset = Preset.new(Color("367c9a"), Color("aec8bd"),
		Color("558886"), Color("adbfaa"), 0.0014, Color("c3d3bd"), 0.68)
	# The distant sea fades into the same haze below the horizon. A separate
	# ground-sky color otherwise exposes a blue stripe beyond the camera's far plane.
	preset.sky_horizon = preset.fog_color
	preset.ground_horizon = preset.fog_color
	preset.haze_below_horizon = true
	preset.key_color = Color("ffe4ad")
	preset.key_energy = 1.25
	preset.scene_fill_energy = 0.12
	preset.view_fill_energy = 0.25
	preset.contrast = 1.04
	preset.saturation = 0.93
	return preset

static func carrier() -> Preset:
	var preset: Preset = facility()
	preset.sky_top = Color("060910")
	preset.sky_horizon = Color("0b111a")
	preset.ground_horizon = Color("060910")
	preset.practical_color = Color("ffe1b1")
	preset.practical_energy = 1.3
	preset.practical_range = 8.0
	preset.key_energy = 0.0
	preset.scene_fill_energy = 0.1
	return preset

static func moon_port() -> Preset:
	var preset: Preset = Preset.new(Color("090b10"), Color("141a20"),
		Color("343b3c"), Color("787b73"), 0.0006, Color("b8bdb6"), 0.58)
	preset.key_color = Color("fff0cf")
	preset.key_energy = 1.45
	preset.scene_fill_energy = 0.10
	preset.practical_color = Color("ffe8bb")
	preset.practical_energy = 2.2
	preset.practical_range = 13.0
	preset.practical_attenuation = 1.2
	preset.accent_energy = 1.0
	preset.accent_range = 3.0
	preset.view_fill_energy = 0.55
	preset.view_fill_range = 65.0
	preset.contrast = 1.08
	preset.saturation = 0.90
	return preset

## Port of Entry (docs/design/moon.md): the port's lunar light with a lower
## ambient floor and a dimmer key, so the hard exterior light stays outside
## the pressure glass and the halls are shaped by their own fixtures. M06Dressing
## lights the apron, the high bays and the work stations; the actor fill keeps
## black-and-red guards readable against cargo and shell.
static func port_of_entry() -> Preset:
	var preset: Preset = moon_port()
	preset.ambient_color = Color(0.70, 0.72, 0.72)
	preset.ambient_energy = 0.55
	preset.key_color = Color("f4f1e8")
	preset.key_energy = 0.55
	preset.practical_energy = 2.4
	preset.practical_range = 11.0
	preset.view_fill_energy = 0.7
	preset.contrast = 1.12
	preset.saturation = 0.95
	return preset

## The custody archive: an enclosed lunar institution lit by desk lamps,
## the shaft's cold glow and the freight lane. Darker than the port, with
## warmer, shorter practical pools.
static func moon_archive() -> Preset:
	var preset: Preset = moon_port()
	preset.key_energy = 1.1
	preset.scene_fill_energy = 0.08
	preset.practical_color = Color("ffe2ad")
	preset.practical_energy = 2.6
	preset.practical_range = 11.0
	preset.view_fill_energy = 0.5
	preset.contrast = 1.1
	return preset

## The curfew town: a low sun behind the town wall, so the streets lie in
## long shade under the dome and the crater cut beyond is hard light on dust.
## M07Dressing puts the Union's cold floods and the post's pools in the shade;
## every window stays dark until the lamp line is lit. The actor fill keeps a
## black-and-red guard readable in the shaded street and on the rim.
static func moon_town() -> Preset:
	var preset: Preset = moon_port()
	preset.ambient_color = Color(0.66, 0.70, 0.72)
	preset.ambient_energy = 0.5
	preset.key_color = Color("fff3dc")
	preset.key_energy = 1.15
	preset.key_rotation_degrees = Vector3(-13.0, 165.0, 0.0)
	preset.scene_fill_energy = 0.05
	preset.practical_color = Color("d9e0dc")
	preset.practical_energy = 1.6
	preset.practical_range = 10.0
	preset.view_fill_energy = 0.6
	preset.contrast = 1.1
	return preset

static func low_water() -> Preset:
	var preset: Preset = Preset.new(Color("778da2"), Color("d6b898"),
		Color("948779"), Color("c6b298"), 0.0025, Color("e0d2bc"), 0.8)
	preset.key_color = Color("ffdaa2")
	preset.key_energy = 1.2
	preset.scene_fill_energy = 0.12
	preset.practical_color = Color("ffeac2")
	preset.practical_energy = 0.9
	preset.saturation = 0.92
	return preset

## Notice to Vacate, late afternoon (docs/design/earth.md "M04 Low Water"):
## a low warm sun from the south-west throws long shadows across the square
## and puts the court and the clinic side of the market in cool shade, so the
## stall lamps, lit windows and the clinic read as practical light. A faint
## actor fill keeps a black-and-red Union body readable in that shade.
static func notice_to_vacate() -> Preset:
	var preset: Preset = Preset.new(Color("6c87a8"), Color("e8b68a"),
		Color("9a7f6c"), Color("cfae8e"), 0.0032, Color("a3a9b4"), 0.62)
	preset.key_color = Color("ffc58a")
	preset.key_energy = 1.5
	preset.key_rotation_degrees = Vector3(-22.0, -118.0, 0.0)
	preset.scene_fill_energy = 0.05
	preset.practical_color = Color("ffe0b0")
	preset.practical_energy = 1.0
	preset.view_fill_energy = 0.28
	preset.view_fill_range = 30.0
	preset.contrast = 1.08
	preset.saturation = 0.98
	preset.glow_intensity = 0.35
	return preset

## Larak Lot: an old range's car park at night. Deep indigo over a sodium
## haze, a low cool city glow raking in from the south-west across the Roof and
## the Pit, and warm sodium practicals in the covered bays: warm outside the
## lightwells, cold inside the concrete. The floors stay mid-value so a body
## never disappears into a corner, and the actor fill keeps a NODS bot's dark
## plate and a free fighter's own colours readable at thirty metres. The
## Office's one seal here is dead: no red lamp burns in a league venue, where
## red is a Union body's tell.
static func larak_lot() -> Preset:
	var preset: Preset = Preset.new(
		Color("1b1838"),             # deep indigo-violet
		Color("8a5a3c"),             # sodium haze on the horizon
		Color("2d2420"),
		Color("4a3b37"),
		0.0045,
		Color("a3a2ba"),             # cool fill against warm practicals
		0.6
	)
	preset.outdoor_embers = false
	# Exhaust and sodium haze settled in the Pit, under the first deck.
	preset.fog_height = 0.9
	preset.fog_height_density = 0.18
	preset.key_color = Color("b9c6e6")  # cool city glow
	preset.key_energy = 0.95
	preset.key_in_sky = false
	preset.key_rotation_degrees = Vector3(-24.0, -45.0, 0.0)
	preset.scene_fill_energy = 0.0
	preset.practical_color = Color("ffb35c")  # sodium
	preset.practical_energy = 4.0
	preset.practical_range = 15.0
	preset.practical_attenuation = 1.2
	preset.accent_energy = 0.0
	preset.view_fill_energy = 0.55
	preset.view_fill_range = 32.0
	preset.contrast = 1.1
	preset.saturation = 1.0
	preset.glow_intensity = 0.8
	return preset

## Low Water the night of the wipe. A cool moon key and a deep blue sky keep
## silhouettes separate; the warm practicals that still burn are the
## interrupted light, and glow lets the white work marks read as light on the
## ground rather than paint. The actor fill keeps every machine readable.
static func planned_works() -> Preset:
	var preset: Preset = Preset.new(Color("0b1220"), Color("2b3446"),
		Color("1b1f26"), Color("1d2533"), 0.0065, Color("7d8aa6"), 0.36)
	preset.outdoor_embers = false
	preset.key_color = Color("9fb4d6")
	preset.key_energy = 0.48
	preset.scene_fill_energy = 0.05
	preset.practical_color = Color("ffd29a")
	preset.practical_energy = 2.4
	preset.practical_range = 12.0
	preset.practical_attenuation = 1.3
	preset.view_fill_energy = 0.7
	preset.view_fill_range = 40.0
	preset.contrast = 1.06
	preset.saturation = 0.9
	preset.glow_intensity = 0.55
	return preset

## Local Exception: the waterworks and the refuge pier at the last blue hour.
## A cool low key keeps every silhouette, the fog leans indigo over the
## harbour, and the warmth comes from the people's lamps and the tower.
static func waterworks() -> Preset:
	var preset: Preset = Preset.new(Color("1f2738"), Color("8b6253"),
		Color("2f3540"), Color("4a5160"), 0.0065, Color("7f8aa0"), 0.42)
	preset.key_color = Color("aebbd6")
	preset.key_energy = 0.55
	preset.scene_fill_energy = 0.08
	preset.practical_color = Color("ffcf94")
	preset.practical_energy = 3.0
	preset.practical_range = 12.0
	preset.practical_attenuation = 1.3
	preset.accent_energy = 0.0
	preset.view_fill_energy = 0.42
	preset.view_fill_range = 50.0
	preset.contrast = 1.07
	preset.saturation = 0.94
	preset.glow_intensity = 0.55
	return preset

## Still Here, the first light after the reprieve: the blue hour gone to a
## grey dawn, smoke and haze over the harbour, a weak low sun coming up behind
## the refuge, and the warmth still in the lamps people carried.
static func still_here() -> Preset:
	var preset: Preset = Preset.new(Color("2c3442"), Color("8f7f78"),
		Color("3a3f46"), Color("5d6268"), 0.0062, Color("8d93a2"), 0.55)
	preset.outdoor_embers = false
	preset.key_color = Color("ffb88a")
	preset.key_energy = 0.55
	preset.key_rotation_degrees = Vector3(-12.0, 90.0, 0.0)
	preset.scene_fill_energy = 0.1
	preset.practical_color = Color("ffc98a")
	preset.practical_energy = 2.2
	preset.practical_range = 10.0
	preset.practical_attenuation = 1.3
	preset.accent_energy = 0.0
	preset.view_fill_energy = 0.4
	preset.view_fill_range = 40.0
	preset.contrast = 1.05
	preset.saturation = 0.84
	preset.glow_intensity = 0.4
	return preset

## Still Here, years later: a clear morning over clean water, the sun well up
## in the east, the same court in plain daylight. Warmer and greener than the
## Low Water afternoon, never a green wash.
static func still_here_later() -> Preset:
	var preset: Preset = Preset.new(Color("5d87b0"), Color("d6d2bf"),
		Color("8a8c78"), Color("c3cbc8"), 0.0016, Color("d6d4c2"), 0.68)
	preset.outdoor_embers = false
	# A warm morning sun, not a noon glare: the pale paving and Latch's bone
	# paint keep their values instead of washing out to white.
	preset.key_color = Color("ffdcac")
	preset.key_energy = 1.12
	preset.key_rotation_degrees = Vector3(-34.0, 127.0, 0.0)
	preset.scene_fill_energy = 0.14
	preset.practical_color = Color("ffeac2")
	preset.practical_energy = 0.6
	preset.accent_energy = 0.0
	preset.view_fill_energy = 0.22
	preset.exposure = 0.95
	preset.contrast = 1.08
	preset.saturation = 1.0
	preset.glow_intensity = 0.2
	return preset

static func freight_yard() -> Preset:
	var preset: Preset = Preset.new(Color("537e9a"), Color("b8c4bc"),
		Color("777a68"), Color("adb6a8"), 0.003, Color("d1d4ca"), 0.8)
	preset.key_color = Color("ffe1b0")
	preset.key_energy = 1.3
	# Scheduled Service's bright afternoon: a lower western sun rakes the car
	# ribs and throws the consist's shadows across the lanes, and the actor
	# fill keeps a black-and-red guard's front readable in that shade.
	preset.key_rotation_degrees = Vector3(-36.0, -62.0, 0.0)
	preset.view_fill_energy = 0.25
	preset.scene_fill_energy = 0.15
	preset.practical_energy = 0.8
	preset.contrast = 1.08
	preset.saturation = 0.94
	return preset


## Built in code rather than as a scene sub-resource on purpose. A sub-resource
## dropped into the wrong half of a .tscn file silently invalidates the scene,
## which has cost this project a client boot once already.
static func build_environment(map_name: String = "") -> Environment:
	var preset: Preset = preset_for(map_name)

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = preset.sky_top
	sky_material.sky_horizon_color = preset.sky_horizon
	sky_material.ground_bottom_color = preset.fog_color if preset.haze_below_horizon else preset.sky_top
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
	env.fog_height = preset.fog_height
	env.fog_height_density = preset.fog_height_density

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
	# The bloom is small on purpose: the tight levels carry it, so a bulb,
	# a window or a sign letter gets a halo a few pixels wide and the wide
	# levels that fog a whole wall stay off. A lit floor under a lamp stays
	# below the threshold, and the luminance cap stops one hot lamp from
	# flooding the frame around a fighter standing under it.
	env.glow_enabled = false
	env.glow_intensity = preset.glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_hdr_scale = GLOW_HDR_SCALE
	env.glow_hdr_luminance_cap = GLOW_LUMINANCE_CAP
	env.glow_normalized = false
	for level: int in GLOW_LEVELS.size():
		env.set_glow_level(level, GLOW_LEVELS[level])
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
		if preset.key_rotation_degrees != Vector3.ZERO:
			if not key.has_meta("authored_rotation"):
				key.set_meta("authored_rotation", key.rotation_degrees)
			key.rotation_degrees = preset.key_rotation_degrees
		elif key.has_meta("authored_rotation"):
			key.rotation_degrees = key.get_meta("authored_rotation")
		key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if preset.key_in_sky else DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	var fill: OmniLight3D = layout.get_node_or_null("FillLight") as OmniLight3D
	if fill != null:
		fill.light_energy = preset.scene_fill_energy
		fill.visible = preset.scene_fill_energy > 0.0
	for ember: String in ["EmberPit", "EmberCornerNE", "EmberCornerSW"]:
		var lamp: Node3D = layout.get_node_or_null(ember) as Node3D
		if lamp != null:
			lamp.visible = not preset.interior and preset.outdoor_embers


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
