class_name M20Waterworks
extends Node3D

## Local Exception presentation: the sluices running for the refuge, the
## waterworks tower lit from inside, the people at the crossing behind the
## fence, Edda's lamp, the crates they carried, the harbour display's one
## message, the crew who keep the pumps going, and Latch walking back. Every
## piece presents server facts or static scenery outside the walking volumes;
## none of it is collision, cover or a mission control.
signal notice_requested(text: String)

const WARM: Color = Color("ffc98a")
const LAMP: Color = Color("ffd9a0")
const TOWER_WINDOW: Color = Color("f6c27c")
const DISPLAY_DARK: Color = Color("121a1c")
const DISPLAY_TEXT: Color = Color("a9d4cc")
const BONE: Color = Color("d6d0c2")
## Warning beacons at height burn amber: a red point up there reads as a
## Union optic at 30 m.
const AMBER_BEACON: Color = Color("e0a03f")
const CREW_COLOR: Color = Color("c9a16a")
## The crowd's own clothes, recoloured over the free citizen atlas: varied
## practical colours in the mid range, never Union black and red, cyan or a
## matte off-white base, and never one issued jacket.
const COATS: Array[Color] = [Color("b08a3a"), Color("6f7a3e"), Color("7a5232"), Color("b0642e"),
	Color("6e4a6a"), Color("34476e"), Color("4a6488"), Color("a88f6a"), Color("5e6b5a"),
	Color("c08a3c"), Color("3e5a40"), Color("7a6e64"), Color("9c8a4a"), Color("5a6ea8"), Color("8a5a3a")]
const TROUSERS: Array[Color] = [Color("3a3a40"), Color("5a4430"), Color("3e4e6a"), Color("4e523a"),
	Color("8a7a5a"), Color("2a2a2e"), Color("6a5a48")]
const SKIN_TONES: Array[Color] = [Color(1.0, 1.0, 1.0), Color(0.86, 0.76, 0.68), Color(0.64, 0.5, 0.42),
	Color(0.46, 0.34, 0.28), Color(0.96, 0.9, 0.82), Color(0.76, 0.6, 0.5)]
## Free synthetics: warm personal panels, plates warmed off the reserved
## off-white, and their own screen light.
const SYNTHETIC_PANELS: Array[Color] = [Color("8a6a4a"), Color("6a7a4a"), Color("7a5a6a"), Color("9a7a3a"), Color("6a6a7a")]
const ORRIN: Color = Color("c89058")
const SORREL: Color = Color("a87a8a")
const PLATE_WARMTH: Color = Color(0.86, 0.72, 0.54)
const FACE_LAMPS: Array[Color] = [Color("ffb060"), Color("ffe0b0"), Color("d8e070")]
const BUNDLES: Array[Color] = [Color("6b5a48"), Color("4d5a57"), Color("7a6852"), Color("5b4f5c"), Color("8a6a40"), Color("4a4a3a")]
## Lifts the crowd's values toward the mid range under the blue hour.
const CROWD_LIFT: float = 1.25
const KNOTS_PER_SIDE: int = 12
const PIER_KNOTS: int = 6
## Sluice channels: x range, z range, water surface height below the deck.
const CHANNELS: Array[Rect2] = [Rect2(-54.0, -16.0, 4.0, 36.0), Rect2(-44.0, -16.0, 4.0, 36.0)]
const CHANNEL_LEVEL: float = 0.68
## Lamp heads on the authored poles (the poles are server solids).
const POLES: Array[Vector3] = [Vector3(22.0, 7.0, 19.5), Vector3(22.0, 7.0, -22.5), Vector3(50.0, 7.0, 19.5),
	Vector3(48.0, 7.0, -24.5), Vector3(-18.0, 6.5, 8.8), Vector3(11.0, 6.5, -10.2), Vector3(22.0, 7.0, 26.2)]
const TOWER_MIN: Vector3 = Vector3(-8.0, 0.0, 30.0)
const TOWER_MAX: Vector3 = Vector3(8.0, 24.0, 44.0)
const EDDA_LAMP: Vector3 = Vector3(51.0, 1.0, 15.0)
const CRATES: Dictionary[String, Vector3] = {
	"crate_a": Vector3(44.0, 0.55, 16.5), "crate_b": Vector3(19.0, 0.55, -3.0),
	"crate_c": Vector3(22.5, 0.55, 15.5), "crate_d": Vector3(41.0, 0.55, -19.0),
	"crate_e": Vector3(32.5, 1.55, -5.0), "crate_f": Vector3(50.0, 0.55, -6.5),
	"crate_g": Vector3(45.5, 0.55, 3.5),
}
## Where the crew stand once through the wicket, behind the fence.
const CREW_REFUGE: Array[Vector3] = [Vector3(59.2, 0.2, -10.0), Vector3(60.4, 0.2, -11.6), Vector3(59.0, 0.2, -13.2)]

var _geometry: Dictionary = {}
var _static: Node3D
var _crowd: Array[Node3D] = []
var _crowd_yaw: Array[float] = []
var _crowd_home: Array[Vector3] = []
var _crew: Array[CivilianFigure] = []
var _latch: LatchView
var _latch_feet: Vector3 = Vector3.INF
var _latch_travel: float = 0.0
var _display_root: Node3D
var _display_lines: Array[Label3D] = []
var _display_light: OmniLight3D
var _tower_band: Array[MeshInstance3D] = []
var _tower_talkers: Array[MeshInstance3D] = []
var _tower_stair: Array[MeshInstance3D] = []
var _gate_leaf: Node3D
var _barricade: Array[MeshInstance3D] = []
var _lids: Dictionary[String, MeshInstance3D] = {}
var _crate_lamps: Dictionary[String, OmniLight3D] = {}
var _edda_light: OmniLight3D
var _channel_materials: Array[ShaderMaterial] = []
var _flicker: float = 0.0
var _named: Dictionary[String, Node3D] = {}
var _notices: Dictionary[String, bool] = {}
var _spoken: Dictionary[String, bool] = {}
## Spoken lines in play: sentence case with a speaker label, never a banner.
var caption: SpeakerCaption
## The restoration Pavers' marked strips on the service road and the yard.
var strips: PaverStrips
var state_applied: int = 0
var _facts: Dictionary = {}
## Tern, over the channel, once, near the end: the only laugh in Episode V.
const TERN_SECONDS: int = 40
var integrity: int = 100
var display_lit: bool = false
var gate_open: bool = false
var reprieve: bool = false

func clear_map() -> void:
	_geometry.clear()
	_crowd.clear()
	_crowd_home.clear()
	_crowd_yaw.clear()
	_crew.clear()
	_latch = null
	_latch_feet = Vector3.INF
	_display_lines.clear()
	_display_root = null
	_display_light = null
	_tower_band.clear()
	_tower_talkers.clear()
	_tower_stair.clear()
	_gate_leaf = null
	_barricade.clear()
	_lids.clear()
	_crate_lamps.clear()
	_edda_light = null
	_channel_materials.clear()
	_named.clear()
	_notices.clear()
	_spoken.clear()
	caption = null
	strips = null
	_facts.clear()
	state_applied = 0
	integrity = 100
	display_lit = false
	gate_open = false
	reprieve = false
	_static = null
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	# The gate-open world arrives as a new MapInfo for the same attempt: keep
	# what has already been said and shown so Latch's line still lands.
	var reopened: bool = not _geometry.is_empty() and info.get("m20") is Dictionary
	var said: Dictionary[String, bool] = _spoken.duplicate()
	var shown: Dictionary[String, bool] = _notices.duplicate()
	var applied: int = state_applied
	clear_map()
	if not info.get("m20") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	if reopened:
		_spoken = said
		_notices = shown
		state_applied = applied
	_geometry = MissionState.geometry_for(info)
	_static = Node3D.new()
	_static.name = "Waterworks"
	add_child(_static)
	caption = SpeakerCaption.new()
	caption.name = "WaterworksCaptions"
	add_child(caption)
	strips = PaverStrips.new()
	strips.name = "PaverStrips"
	add_child(strips)
	_build_sluices()
	_build_tower()
	_build_lamps()
	_build_quay()
	_build_crane()
	_build_display(info)
	_build_edda_lamp()
	_build_crates()
	_build_fence_and_gate()
	_build_crowd()
	_build_crew()
	ArenaSky.mark_world(_static)

# ---------------------------------------------------------------- static

func _build_sluices() -> void:
	var detail: Texture2D = EnvironmentTextures.texture_at("res://assets/environment/production/water_ripples.png")
	for index: int in range(CHANNELS.size()):
		var rect: Rect2 = CHANNELS[index]
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = ArenaWater.SHADER
		material.set_shader_parameter("river_mode", true)
		material.set_shader_parameter("patch_size", rect.size)
		material.set_shader_parameter("phase", float(index) * 2.3)
		material.set_shader_parameter("deep_color", Color("1d3436"))
		material.set_shader_parameter("water_color", Color("355452"))
		material.set_shader_parameter("crest_color", Color("8fa79c"))
		material.set_shader_parameter("shore_color", Color("2a3330"))
		if detail != null:
			material.set_shader_parameter("ripple_detail", detail)
			material.set_shader_parameter("detail_enabled", true)
		var water: MeshInstance3D = _plane("Sluice%d" % index, Vector3(rect.position.x + rect.size.x * 0.5, CHANNEL_LEVEL, rect.position.y + rect.size.y * 0.5), rect.size, material)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_channel_materials.append(material)
		# Channel walls stained to the waterline, and the culvert the pumps
		# feed at the north end with white water falling into the cut.
		var stain: StandardMaterial3D = _material(Color("3a403a"))
		for side: float in [rect.position.x + 0.01, rect.position.x + rect.size.x - 0.01]:
			_box("ChannelStain", Vector3(side, CHANNEL_LEVEL + 0.06, rect.position.y + rect.size.y * 0.5), Vector3(0.02, 0.18, rect.size.y), stain)
		var culvert: Vector3 = Vector3(rect.position.x + rect.size.x * 0.5, 1.05, 19.96)
		_box("Culvert", culvert, Vector3(3.0, 0.8, 0.06), _material(Color("101414")))
		_box("CulvertLip", culvert + Vector3(0, 0.48, 0.02), Vector3(3.4, 0.16, 0.12), _material(Color("6a6b62")))
		var foam: StandardMaterial3D = _material(Color("aebdb6"), true, 0.12)
		_box("Spill", culvert + Vector3(0, -0.12, -0.25), Vector3(2.6, 0.6, 0.12), foam)
		# Broken foam bands where the spill meets the channel, thinning out
		# downstream rather than one bright slab.
		for band: int in range(3):
			var width: float = 3.4 - float(band) * 0.9
			_box("SpillFoam", Vector3(culvert.x + (0.3 if band == 1 else -0.2) * float(band), CHANNEL_LEVEL + 0.02, 19.55 - float(band) * 0.55), Vector3(width, 0.04, 0.28), foam)
		# Gauge boards on the channel heads: the pumps still run for the refuge.
		_box("GaugePost", Vector3(rect.position.x - 0.35, 1.9, 18.6), Vector3(0.12, 1.4, 0.12), _material(Color("2c3331")))
		_box("Gauge", Vector3(rect.position.x - 0.35, 2.55, 18.52), Vector3(0.5, 0.5, 0.04), _material(Color("d8cfb4")))
		_box("GaugeNeedle", Vector3(rect.position.x - 0.35, 2.58, 18.49), Vector3(0.04, 0.32, 0.02), _material(Color("8a2f24")))
	# Pump housings breathe: a valve wheel and a running lamp on each.
	for at: Vector3 in [Vector3(-58.75, 3.4, -5.0), Vector3(-58.75, 3.4, 7.5), Vector3(-47.0, 3.0, 4.5), Vector3(-47.0, 3.0, -10.5)]:
		_box("PumpRunLamp", at + Vector3(0, 0.08, 0), Vector3(0.22, 0.16, 0.22), _material(Color("9fd18c"), true, 1.2))
		var wheel: MeshInstance3D = _box("ValveWheel", at + Vector3(1.31, -1.1, 0), Vector3(0.06, 0.7, 0.7), _material(Color("7d3b2c")))
		wheel.rotation.x = PI * 0.25

func _build_tower() -> void:
	# The waterworks tower where the free agents are talking: lit from
	# inside, the one warm block in the district's skyline.
	var glow: StandardMaterial3D = _material(TOWER_WINDOW, true, 1.8)
	var dark: StandardMaterial3D = _material(Color("1b2124"))
	var frame: StandardMaterial3D = _material(Color("8f8d82"))
	var size: Vector3 = TOWER_MAX - TOWER_MIN
	for level: int in range(6):
		var y: float = 4.0 + float(level) * 3.2
		for column: int in range(5):
			var x: float = TOWER_MIN.x + 1.6 + float(column) * 3.2
			var lit: bool = (level + column * 2) % 3 != 1 or level >= 4
			_box("TowerWindowS", Vector3(x, y, TOWER_MIN.z - 0.04), Vector3(1.6, 1.8, 0.08), glow if lit else dark)
			_box("TowerSill", Vector3(x, y - 1.0, TOWER_MIN.z - 0.08), Vector3(1.9, 0.14, 0.16), frame)
		for row: int in range(4):
			var z: float = TOWER_MIN.z + 1.8 + float(row) * 3.4
			var lit_side: bool = (level + row) % 2 == 0 or level >= 4
			_box("TowerWindowE", Vector3(TOWER_MAX.x + 0.04, y, z), Vector3(0.08, 1.8, 1.6), glow if lit_side else dark)
	# The control room crown: a band of light, a parapet and the radio mast.
	# Each band owns its material so the reprieve can turn it down alone.
	_tower_band.append(_box("ControlBand", Vector3(0, 21.6, TOWER_MIN.z - 0.05), Vector3(size.x - 1.0, 1.6, 0.08), _material(TOWER_WINDOW, true, 1.8)))
	_tower_band.append(_box("ControlBandE", Vector3(TOWER_MAX.x + 0.05, 21.6, (TOWER_MIN.z + TOWER_MAX.z) * 0.5), Vector3(0.08, 1.6, size.z - 1.0), _material(TOWER_WINDOW, true, 1.8)))
	# One lamp stays on in the control room after the talking is done.
	_box("ControlLamp", Vector3(2.6, 21.6, TOWER_MIN.z - 0.07), Vector3(1.4, 1.2, 0.08), _material(TOWER_WINDOW, true, 2.2))
	_box("Parapet", Vector3(0, 24.3, (TOWER_MIN.z + TOWER_MAX.z) * 0.5), Vector3(size.x + 0.4, 0.6, size.z + 0.4), frame)
	_box("Mast", Vector3(4.0, 28.0, 37.0), Vector3(0.25, 8.0, 0.25), _material(Color("3a403f")))
	# Amber, never a red point at height: red there reads as a Union optic.
	_box("MastLamp", Vector3(4.0, 32.1, 37.0), Vector3(0.4, 0.3, 0.4), _material(AMBER_BEACON, true, 2.0))
	# Two silhouettes at the big control window, talking.
	for x: float in [-1.4, 0.9]:
		_tower_talkers.append(_box("Talker", Vector3(x, 21.4, TOWER_MIN.z + 0.2), Vector3(0.55, 1.5, 0.3), _material(Color("2a2420"))))
	# The stair windows down the tower's south face, dark until they come down.
	for level: int in range(6):
		var stair: MeshInstance3D = _box("StairLight", Vector3(TOWER_MIN.x + 0.9, 4.6 + float(level) * 3.2, TOWER_MIN.z - 0.06), Vector3(0.7, 1.2, 0.08), _material(TOWER_WINDOW, true, 2.0))
		stair.visible = false
		_tower_stair.append(stair)
	for at: Vector3 in [Vector3(-4.0, 21.0, TOWER_MIN.z - 2.5), Vector3(4.0, 21.0, TOWER_MIN.z - 2.5), Vector3(TOWER_MAX.x + 2.5, 18.0, 37.0)]:
		_light("TowerSpill", at, TOWER_WINDOW, 3.5, 16.0)

func _build_lamps() -> void:
	for at: Vector3 in POLES:
		_box("LampArm", at + Vector3(0, -0.15, 0), Vector3(0.9, 0.14, 0.14), _material(Color("2c3331")))
		_box("LampHead", at + Vector3(0.4, -0.32, 0), Vector3(0.6, 0.22, 0.4), _material(LAMP, true, 2.2))
		var light: OmniLight3D = _light("QuayLamp", at + Vector3(0.4, -0.7, 0), LAMP, 3.0, 13.0)
		light.add_to_group(ArenaSky.PRACTICAL_GROUP)

## The quay floor tells its history: the tram line that ends at the freight
## platform, the freight siding along it with a buffer stop at each end, the
## painted refuge line the machines must not stand on, the hatched lane to
## the gate and rain standing in the low places under the lamps. Flat paint
## and inlays only; nothing here rises above the walking surface.
func _build_quay() -> void:
	var rail: StandardMaterial3D = _material(Color("8b8a84"))
	rail.roughness = 0.35
	rail.metallic = 0.6
	var groove: StandardMaterial3D = _material(Color("2a2c2a"))
	# Tram line out of the trench, ending at the platform's south steps.
	for x: float in [30.8, 32.2]:
		_box("TramGroove", Vector3(x, 0.006, -36.0), Vector3(0.16, 0.012, 52.0), groove)
		_box("TramRail", Vector3(x, 0.012, -36.0), Vector3(0.07, 0.014, 52.0), rail)
	# Freight siding along the platform's east face.
	for x: float in [42.1, 43.5]:
		_box("SidingGroove", Vector3(x, 0.006, -1.5), Vector3(0.16, 0.012, 45.0), groove)
		_box("SidingRail", Vector3(x, 0.012, -1.5), Vector3(0.07, 0.014, 45.0), rail)
	var oxide: StandardMaterial3D = _material(Color("7d3b2c"))
	var hazard: StandardMaterial3D = _material(Color("c79a3a"))
	for end: float in [-23.4, 20.4]:
		# Flat painted end plates where the siding stops short.
		_box("SidingEnd", Vector3(42.8, 0.005, end), Vector3(2.0, 0.01, 0.5), hazard)
		_box("SidingEndBar", Vector3(42.8, 0.006, end), Vector3(2.0, 0.012, 0.12), oxide)
	# The refuge line: where a standing machine wears the barricade. Painted
	# so the rule is readable from anywhere on the quay.
	var paint: StandardMaterial3D = _material(Color("d2b25a"), true, 0.18)
	var z: float = -25.6
	while z < 21.6:
		_box("RefugeLinePaint", Vector3(48.0, 0.004, z + 0.7), Vector3(0.22, 0.008, 1.4), paint)
		z += 2.2
	# Hatched lane to the gate, kept clear for the crossing.
	var hatch: StandardMaterial3D = _material(Color("c9c2a8"), true, 0.08)
	for index: int in range(9):
		var stripe: MeshInstance3D = _box("LaneHatch", Vector3(52.2, 0.004, -2.4 + float(index) * 0.6), Vector3(7.6, 0.008, 0.16), hatch)
		stripe.rotation.y = 0.55
	_box("LaneEdge", Vector3(52.2, 0.004, -2.95), Vector3(7.6, 0.008, 0.14), hatch)
	_box("LaneEdge", Vector3(52.2, 0.004, 2.95), Vector3(7.6, 0.008, 0.14), hatch)
	# Standing rain: dark glossy patches that catch the lamps and the display.
	var wet: StandardMaterial3D = StandardMaterial3D.new()
	wet.albedo_color = Color(0.07, 0.08, 0.09, 0.55)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.08
	wet.metallic_specular = 0.9
	for patch: Vector4 in [Vector4(23.0, 17.5, 3.4, 1.8), Vector4(22.4, -20.6, 2.8, 2.0), Vector4(47.6, 16.8, 3.0, 1.6),
			Vector4(45.6, -22.6, 4.0, 1.5), Vector4(36.0, 12.0, 2.2, 1.2), Vector4(21.5, 0.5, 1.6, 3.0),
			Vector4(51.0, -12.0, 2.4, 1.4), Vector4(29.0, -14.5, 3.2, 1.3), Vector4(-12.0, 4.0, 2.6, 1.6),
			Vector4(4.0, -4.5, 3.0, 1.2), Vector4(38.0, -40.0, 2.0, 4.0)]:
		for blob: int in range(3):
			var offset: Vector3 = Vector3(float(blob - 1) * patch.z * 0.3, 0.003 + float(blob) * 0.0005, float((blob * 2) % 3 - 1) * patch.w * 0.25)
			var piece: MeshInstance3D = _plane("Puddle", Vector3(patch.x, 0.0, patch.y) + offset, Vector2(patch.z * (0.7 + 0.15 * float(blob)), patch.w * (0.9 - 0.12 * float(blob))), wet)
			piece.rotation.y = float(blob) * 0.6 + patch.x * 0.1
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## The pier crane over the freight yard: hoist trolley, hook block hanging
## on its cable, warning paint on the legs and a beacon on each. Its cab is
## the server's solid; only its lit window and the scenery are drawn here.
func _build_crane() -> void:
	var steel: StandardMaterial3D = _material(Color("3e4648"))
	var hazard: StandardMaterial3D = _material(Color("c79a3a"))
	var dark: StandardMaterial3D = _material(Color("161a1b"))
	for x: float in [20.0, 54.0]:
		for band: int in range(4):
			_box("LegPaint", Vector3(x, 0.6 + float(band) * 0.9, 39.0), Vector3(2.06, 0.44, 2.06), hazard if band % 2 == 0 else dark)
		_box("Beacon", Vector3(x, 14.25, 39.0), Vector3(0.36, 0.3, 0.36), _material(AMBER_BEACON, true, 3.0))
		_light("CraneBeacon", Vector3(x, 14.8, 39.0), AMBER_BEACON, 1.2, 6.0)
	_box("Trolley", Vector3(48.5, 11.6, 39.0), Vector3(2.6, 0.8, 2.4), steel)
	_box("Cable", Vector3(48.5, 8.7, 39.0), Vector3(0.06, 5.0, 0.06), dark)
	_box("HookBlock", Vector3(48.5, 6.0, 39.0), Vector3(0.7, 0.6, 0.5), hazard)
	_box("Hook", Vector3(48.5, 5.5, 39.0), Vector3(0.14, 0.4, 0.14), dark)
	# The cab's lamp is still on: someone left in a hurry, or never left.
	_box("CabWindow", Vector3(35.0, 11.0, 34.52), Vector3(3.6, 1.0, 0.04), _material(Color("e7c18a"), true, 1.2))
	_light("CabLamp", Vector3(35.0, 11.2, 36.0), Color("e7c18a"), 1.4, 6.0)

func _build_display(info: Dictionary) -> void:
	var g: Dictionary = _geometry["m20"]
	var detail: Dictionary = info["presentation"]["decorations"][int(g["harbour_display"])]
	var solid: Dictionary = info["solids"][int(detail["solid"])]
	_display_root = Node3D.new()
	_display_root.name = "HarbourDisplay"
	_display_root.transform = MapDecoration.placement(solid, detail)
	_static.add_child(_display_root)
	var size: Vector2 = Vector2(float(detail["size"][0]), float(detail["size"][1]))
	_display_root.add_child(_quad("Bezel", Vector3(0, 0, 0.0), size + Vector2(0.3, 0.3), _material(Color("1e2224"))))
	var screen: MeshInstance3D = _quad("Screen", Vector3(0, 0, 0.01), size, _material(DISPLAY_DARK, true, 0.15))
	_display_root.add_child(screen)
	var lines: Array[String] = ["", "", "", ""]
	for index: int in range(lines.size()):
		var label: Label3D = Label3D.new()
		label.name = "DisplayLine%d" % index
		label.font = WorldSign.FONT
		label.font_size = 32
		label.pixel_size = 0.0075
		label.modulate = DISPLAY_TEXT
		label.outline_size = 0
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.double_sided = false
		label.position = Vector3(0, size.y * 0.32 - float(index) * size.y * 0.21, 0.02)
		label.visible = false
		_display_root.add_child(label)
		_display_lines.append(label)
	_display_light = OmniLight3D.new()
	_display_light.position = Vector3(0, 0, 1.2)
	_display_light.light_color = DISPLAY_TEXT
	_display_light.light_energy = 0.0
	_display_light.omni_range = 9.0
	_display_root.add_child(_display_light)

func _build_edda_lamp() -> void:
	# A hurricane lamp on the bollard by the fence, lit whatever happened.
	_box("LampBase", EDDA_LAMP + Vector3(0, 0.05, 0), Vector3(0.26, 0.1, 0.26), _material(Color("4a3a2a")))
	_box("LampGlass", EDDA_LAMP + Vector3(0, 0.28, 0), Vector3(0.2, 0.32, 0.2), _material(Color("ffd08a"), true, 2.6))
	_box("LampCap", EDDA_LAMP + Vector3(0, 0.48, 0), Vector3(0.28, 0.08, 0.28), _material(Color("4a3a2a")))
	_box("LampHandle", EDDA_LAMP + Vector3(0, 0.6, 0), Vector3(0.04, 0.16, 0.22), _material(Color("2a2420")))
	_edda_light = _light("EddaLamp", EDDA_LAMP + Vector3(0, 0.35, 0), Color("ffc27a"), 2.4, 7.0)

func _build_crates() -> void:
	var wood: StandardMaterial3D = _material(Color("7a5f42"))
	var strap: StandardMaterial3D = _material(Color("2f2a24"))
	var chalk: StandardMaterial3D = _material(Color("d9d3c2"))
	for key: String in CRATES:
		var top: Vector3 = CRATES[key]
		for x: float in [-0.9, 0.0, 0.9]:
			_box("CrateStrap", top + Vector3(x, -0.27, 0), Vector3(0.08, 0.56, 1.22), strap)
		_box("CrateChalk", top + Vector3(0.0, -0.3, 0.61), Vector3(1.2, 0.18, 0.02), chalk)
		var lid: MeshInstance3D = _box("CrateLid", top + Vector3(0, 0.05, 0), Vector3(2.38, 0.1, 1.18), wood)
		_lids[key] = lid
		var lamp: OmniLight3D = _light("CrateLamp", top + Vector3(0, 0.8, 0), WARM, 0.0, 4.0)
		_crate_lamps[key] = lamp

func _build_fence_and_gate() -> void:
	# The fence is glass in collision; draw it as posts, rails and mesh.
	var post: StandardMaterial3D = _material(Color("2f3634"))
	var mesh_wire: StandardMaterial3D = _material(Color("8d968f"))
	mesh_wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_wire.albedo_color = Color(0.55, 0.6, 0.57, 0.28)
	for span: Vector2 in [Vector2(3.0, 22.0), Vector2(-26.0, -3.0)]:
		var z: float = span.x
		while z <= span.y + 0.01:
			_box("FencePost", Vector3(56.5, 1.7, z), Vector3(0.14, 3.4, 0.14), post)
			z += 2.5
		_box("FenceRail", Vector3(56.5, 3.35, (span.x + span.y) * 0.5), Vector3(0.1, 0.1, span.y - span.x), post)
		_box("FenceRailLow", Vector3(56.5, 0.25, (span.x + span.y) * 0.5), Vector3(0.1, 0.1, span.y - span.x), post)
		_box("FenceMesh", Vector3(56.5, 1.8, (span.x + span.y) * 0.5), Vector3(0.02, 3.1, span.y - span.x), mesh_wire)
	# Barricade along the line: what the people stacked against the fence.
	# Machines on the line wear it; pieces fall as the integrity drops.
	var stacked: Array[Color] = [Color("6d5a43"), Color("57605a"), Color("7c6b55"), Color("4f5650")]
	var index: int = 0
	var z: float = -25.0
	while z < 21.5:
		if absf(z) > 3.6:
			var height: float = 0.7 + float(index % 3) * 0.35
			var piece: MeshInstance3D = _box("Barricade", Vector3(55.6 - float(index % 2) * 0.25, height * 0.5, z), Vector3(0.9, height, 1.5), _material(stacked[index % stacked.size()]))
			_barricade.append(piece)
		index += 1
		z += 1.8
	_gate_leaf = Node3D.new()
	_gate_leaf.name = "GateLeaf"
	_gate_leaf.position = Vector3(56.5, 0, 3.0)
	_static.add_child(_gate_leaf)
	var leaf: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.18, 3.3, 6.0)
	leaf.mesh = box
	leaf.position = Vector3(0, 1.65, -3.0)
	leaf.material_override = _material(Color("4f5b58"))
	leaf.visible = false
	_gate_leaf.add_child(leaf)

## The people at the crossing, behind the fence on both sides of the lane and
## further along the pier: families and friends in knots around what they
## carried, some sitting on crates or bags, children among the adults, people
## turned to each other rather than lined up for anyone. Every knot, person
## and outfit is deterministic from its index; no two neighbours dress alike.
func _build_crowd() -> void:
	var knots: Array[Vector3] = []
	# Behind the fence: x 57.4 to 63.6, both sides of the clear lane.
	for side: float in [1.0, -1.0]:
		for index: int in range(KNOTS_PER_SIDE):
			var row: int = index % 3
			var column: int = index / 3
			var x: float = 58.6 + float(row) * 2.0 + float((index * 7) % 5) * 0.12
			var z: float = side * (5.6 + float(column) * 3.8 + float((index * 5) % 4) * 0.35)
			knots.append(Vector3(minf(x, 62.8), 0.2, z))
	# Out along the pier past the gate, where the rest wait their turn.
	for index: int in range(PIER_KNOTS):
		var z: float = -1.2 if index % 2 == 0 else 1.3
		knots.append(Vector3(66.2 + float(index) * 2.1 + float(index % 3) * 0.3, 0.0, z + float((index * 3) % 4) * 0.12 - 0.18))
	var person: int = 0
	for knot: int in range(knots.size()):
		var center: Vector3 = knots[knot]
		# Two to five people, with what they carried in the middle.
		var size: int = 2 + (knot * 7 + 3) % 4
		var lane_side: bool = center.x < 64.0
		_knot_belongings(knot, center)
		for member: int in range(size):
			var angle: float = float(member) * TAU / float(size) + float(knot) * 0.9
			var reach: float = 0.62 + float((knot + member) % 3) * 0.14
			var feet: Vector3 = center + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
			if lane_side:
				feet.x = clampf(feet.x, 57.5, 63.5)
			var role: String = _crowd_role(knot, member, person)
			var body: Node3D = _crowd_person(person, role)
			body.set_meta("crowd_role", role)
			add_child(body)
			body.position = feet
			if body is SkinnedCharacter:
				# Settle the pose once in the tree; a waiting crowd stands still.
				# People sitting by their bags crouch with their arms in.
				(body as SkinnedCharacter).pose(0.0, false, false, role == "sitting", 0.0, role == "sitting")
			# Most turn to their own people; some watch the quay and the gate.
			var inward: float = atan2(center.x - feet.x, center.z - feet.z)
			var yaw: float = -PI * 0.5 + float((person * 5) % 7 - 3) * 0.12 if person % 4 == 0 else inward
			body.rotation.y = yaw
			_crowd.append(body)
			_crowd_home.append(feet)
			_crowd_yaw.append(yaw)
			person += 1
	_build_lanterns()

## Who stands where in a knot: an adult first, then children, people sitting
## on what they carried, and free synthetics among the humans.
static func _crowd_role(knot: int, member: int, person: int) -> String:
	if member > 0 and (knot + member) % 4 == 1:
		return "child"
	if member > 0 and (knot * 3 + member) % 5 == 2:
		return "sitting"
	if (person * 3 + knot) % 5 == 2:
		return "synthetic"
	if member > 0 and (knot + member * 2) % 6 == 3:
		return "carrying"
	return "standing"

## A refuge person in their own clothes. The strip sprite is the fallback only.
func _crowd_person(index: int, role: String) -> Node3D:
	var synthetic: bool = role == "synthetic"
	var body: SkinnedCharacter = SkinnedCharacter.new()
	if body.configure("synthetic" if synthetic else "human"):
		body.name = "Refugee%d" % index
		var coat: Color = (SYNTHETIC_PANELS if synthetic else COATS)[(index * 5 + index / 3) % (SYNTHETIC_PANELS if synthetic else COATS).size()]
		var trousers: Color = TROUSERS[(index * 3 + 1) % TROUSERS.size()]
		var tone: Color = PLATE_WARMTH if synthetic else SKIN_TONES[(index * 7 + 2) % SKIN_TONES.size()]
		CrowdLook.outfit(body, coat, trousers, tone, CROWD_LIFT)
		if synthetic:
			CrowdLook.face_lamp(body, FACE_LAMPS[index % FACE_LAMPS.size()])
		var scale_by: float = 0.66 + float(index % 3) * 0.04 if role == "child" else 0.93 + float((index * 13) % 7) * 0.02
		body.scale = Vector3.ONE * scale_by
		if role == "carrying":
			_carry(body, index)
		return body
	body.free()
	var figure: CivilianFigure = CivilianFigure.new()
	figure.name = "Refugee%d" % index
	figure.configure("anonymous_synthetic" if synthetic else "anonymous_human", COATS[index % COATS.size()])
	return figure

## A bundle or a bag held against the chest, mounted on the left hand.
func _carry(body: SkinnedCharacter, index: int) -> void:
	var mount: BoneAttachment3D = BoneAttachment3D.new()
	mount.name = "Bundle"
	mount.bone_name = "LeftHand"
	body.skeleton.add_child(mount)
	var bundle: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	# Skeleton space is centimetres under the source's 0.01 scale.
	box.size = Vector3(28.0, 22.0, 30.0) if index % 2 == 0 else Vector3(36.0, 16.0, 24.0)
	bundle.mesh = box
	bundle.position = Vector3(0.0, 8.0, 10.0)
	bundle.layers = ArenaSky.ACTOR_LAYERS
	bundle.material_override = _material(BUNDLES[index % BUNDLES.size()])
	mount.add_child(bundle)

## What one knot carried: bags and bedding at their feet, and a crate or a
## trunk some of them sit beside. Scenery inside the crowd strips only.
func _knot_belongings(knot: int, center: Vector3) -> void:
	var cloth: StandardMaterial3D = _material(BUNDLES[(knot * 3) % BUNDLES.size()])
	var strap: StandardMaterial3D = _material(Color("2f2a24"))
	if knot % 3 == 0:
		var trunk: MeshInstance3D = _box("Trunk", center + Vector3(0, 0.22, 0), Vector3(0.9, 0.44, 0.55), _material(Color("6a4a30") if knot % 2 == 0 else Color("4f5a4a")))
		trunk.rotation.y = float(knot) * 0.8
		_box("TrunkBand", center + Vector3(0, 0.45, 0), Vector3(0.94, 0.04, 0.12), strap).rotation.y = trunk.rotation.y
	elif knot % 3 == 1:
		_box("BeddingRoll", center + Vector3(0, 0.14, 0), Vector3(0.8, 0.28, 0.32), cloth).rotation.y = float(knot) * 0.7
		_box("Bag", center + Vector3(0.28, 0.2, 0.2), Vector3(0.5, 0.4, 0.3), _material(BUNDLES[(knot + 1) % BUNDLES.size()])).rotation.y = float(knot) * 1.3
	else:
		_box("Bag", center + Vector3(0, 0.2, 0), Vector3(0.5, 0.4, 0.3), cloth).rotation.y = float(knot) * 1.1
		_box("BagStrap", center + Vector3(0, 0.42, 0), Vector3(0.06, 0.06, 0.3), strap).rotation.y = float(knot) * 1.1
		_box("Bundle", center + Vector3(-0.3, 0.12, -0.2), Vector3(0.4, 0.24, 0.4), _material(BUNDLES[(knot + 2) % BUNDLES.size()])).rotation.y = float(knot) * 0.4

## Lanterns the people brought: the refuge glows warmer than the quay.
func _build_lanterns() -> void:
	var glass: StandardMaterial3D = _material(Color("ffc27a"), true, 2.4)
	var strap: StandardMaterial3D = _material(Color("2f2a24"))
	for index: int in range(8):
		var z: float = (6.5 + float(index) * 4.2) if index < 4 else -(6.5 + float(index - 4) * 4.2)
		var at: Vector3 = Vector3(59.2 + float(index % 3) * 1.5, 0.2, z)
		_box("Lantern", at + Vector3(0, 0.16, 0), Vector3(0.16, 0.24, 0.16), glass)
		_box("LanternCap", at + Vector3(0, 0.31, 0), Vector3(0.2, 0.05, 0.2), strap)
		_light("RefugeLantern", at + Vector3(0, 0.45, 0), Color("ffbf73"), 1.5, 5.5)

func _build_crew() -> void:
	for index: int in range(M20MissionState.CREW):
		var worker: CivilianFigure = CivilianFigure.new()
		worker.name = "Crew%d" % index
		worker.configure("free_human", CREW_COLOR.lerp(Color("8fa3a0"), float(index) * 0.3))
		add_child(worker)
		_crew.append(worker)

func _named_figure(key: String, person: String, color: Color, feet: Vector3, yaw: float) -> void:
	if _named.has(key):
		return
	var figure: CivilianFigure = CivilianFigure.new()
	figure.name = key.capitalize()
	figure.configure(person, color)
	if person == "free_synthetic" and figure.skin != null:
		CrowdLook.face_lamp(figure.skin, FACE_LAMPS[_named.size() % FACE_LAMPS.size()])
	add_child(figure)
	figure.place_feet(feet)
	figure.rotation.y = yaw
	_named[key] = figure

# ---------------------------------------------------------------- state

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M20_ID or not state.get("m20") is Dictionary:
		return
	state_applied += 1
	var facts: Dictionary = state["m20"]
	var refuge: Dictionary = facts.get("refuge", {})
	# The people the run brought: Edda by her lamp, Splice and Orrin at the
	# fence, Sorrel on a crate behind the line, not following anyone.
	if refuge.get("edda") == true:
		_named_figure("edda", "edda", Color.WHITE, Vector3(57.8, 0.2, 14.6), -PI * 0.5)
	if refuge.get("splice") == true:
		_named_figure("splice", "splice", Color.WHITE, Vector3(57.9, 0.2, -6.0), -PI * 0.5)
	# Orrin is a plainly repaired chassis in warm ochre; Sorrel sits apart in
	# dusty plum. Neither reads pale or cool at 30 m beside the machines.
	if refuge.get("orrin") == true:
		_named_figure("orrin", "free_synthetic", ORRIN, Vector3(58.6, 0.2, -7.4), -PI * 0.4)
	if refuge.get("sorrel") == true:
		_named_figure("sorrel", "free_synthetic", SORREL, Vector3(61.0, 0.55, 8.0), PI)
	for index: int in range(mini(_crew.size(), facts["crew"].size())):
		var member: Dictionary = facts["crew"][index]
		var feet: Array = member["feet"]
		_crew[index].place_feet(CREW_REFUGE[index] if member["phase"] == "arrived" else Vector3(float(feet[0]), float(feet[1]), float(feet[2])))
		if member["phase"] == "arrived":
			_crew[index].rotation.y = -PI * 0.5
	integrity = int(facts["refuge_integrity"])
	_wear_barricade(integrity)
	display_lit = facts["display_lit"]
	reprieve = facts.has("reprieve_at")
	_light_display(display_lit, int(refuge.get("persons", M20MissionState.REFUGE_BASE)), reprieve)
	_turn_tower(reprieve)
	if facts.has("latch"):
		var feet: Array = facts["latch"]
		_place_latch(Vector3(float(feet[0]), float(feet[1]), float(feet[2])))
	gate_open = facts["gate_open"]
	if _gate_leaf != null:
		var leaf: Node3D = _gate_leaf.get_child(0) as Node3D
		leaf.visible = gate_open
		_gate_leaf.rotation.y = -PI * 0.42 if gate_open else 0.0
	# Behind a fallen barricade the people pull back from the line.
	for index: int in range(_crowd.size()):
		var home: Vector3 = _crowd_home[index]
		if integrity <= 0 and home.x < 64.0:
			home.x = minf(home.x + 2.4, 63.6)
		_crowd[index].position = home
	var completed: int = facts["completed"].size()
	_notice("crossing", completed >= 2, "M20_NOTICE_CREW_CROSSING")
	_notice("crossed", facts["challenges"]["crew_crossed"], "M20_NOTICE_CREW_CROSSED")
	_notice("mark", facts["challenges"]["mark_broken"], "M20_NOTICE_MARK_BROKEN")
	_notice("barricade", not facts["challenges"]["refuge_held"], "M20_NOTICE_BARRICADE_FELL")
	# Latch, back across the pier, quietly: the gate opens on that arrival.
	_speak("latch", gate_open, "M20_LATCH_EVEN")
	_facts = facts

## Crates come up as the clock runs: an open lid and a lamp mark stock.
func apply_snapshot(snapshot: Dictionary) -> void:
	if _geometry.is_empty():
		return
	if strips != null:
		strips.apply_snapshot(snapshot)
	if not _facts.is_empty() and snapshot.get("tick") is float:
		var left: int = M20MissionState.seconds_left(_geometry, _facts, int(snapshot["tick"]))
		_speak("tern", left >= 0 and left <= TERN_SECONDS, "M20_TERN_POLITE")
	for pickup: Variant in snapshot.get("pickups", []):
		if not pickup is Dictionary:
			continue
		var id: String = str(pickup.get("id", ""))
		for key: String in _lids:
			if id.begins_with(key + "_"):
				var open: bool = pickup.get("available") == true
				var lid: MeshInstance3D = _lids[key]
				if open:
					lid.position = CRATES[key] + Vector3(0, 0.55, -0.62)
					lid.rotation.x = -1.2
					_crate_lamps[key].light_energy = 1.4
				elif lid.rotation.x == 0.0:
					_crate_lamps[key].light_energy = 0.0

func _notice(key: String, condition: bool, copy: String) -> void:
	if condition and not _notices.get(key, false):
		_notices[key] = true
		if state_applied > 1:
			notice_requested.emit(tr(copy))
	elif not condition:
		_notices[key] = false

## A line someone says, once per attempt, on the speaker caption.
func _speak(key: String, condition: bool, copy: String) -> void:
	if condition and not _spoken.get(key, false):
		_spoken[key] = true
		if state_applied > 1 and caption != null:
			caption.say([tr(copy)])
	elif not condition:
		_spoken[key] = false

func _wear_barricade(value: int) -> void:
	var standing: int = ceili(float(_barricade.size()) * clampf(float(value) / 100.0, 0.0, 1.0))
	for index: int in range(_barricade.size()):
		# Wear removes pieces in a scattered, deterministic order.
		var order: int = (index * 7) % _barricade.size()
		var piece: MeshInstance3D = _barricade[index]
		var up: bool = order < standing
		piece.rotation.z = 0.0 if up else 1.35
		piece.position.y = (piece.mesh as BoxMesh).size.y * 0.5 if up else 0.22

## The harbour display's one message. At the reprieve only the closure line
## changes, to one precise exception: the same voice, no explanation.
func _light_display(lit: bool, persons: int, excepted: bool) -> void:
	if _display_lines.is_empty():
		return
	var copy: Array[String] = [
		tr("M20_DISPLAY_PIER"),
		tr("M20_DISPLAY_PERSONS").format({"persons": persons}),
		tr("M20_DISPLAY_NAMES"),
		tr("M20_DISPLAY_EXCEPTED") if excepted else tr("M20_DISPLAY_CLOSES"),
	]
	for index: int in range(_display_lines.size()):
		_display_lines[index].text = copy[index]
		_display_lines[index].visible = lit
	if _display_light != null:
		_display_light.light_energy = 1.6 if lit else 0.0
	var screen: MeshInstance3D = _display_root.get_node_or_null("Screen") as MeshInstance3D
	if screen != null:
		(screen.material_override as StandardMaterial3D).emission_energy_multiplier = 0.9 if lit else 0.15

## The tower answers the reprieve at the same moment: the control room the
## free agents talked from goes down to one lamp, the two figures leave the
## window and the stair below it lights as they come down.
func _turn_tower(excepted: bool) -> void:
	if _tower_band.is_empty():
		return
	for band: MeshInstance3D in _tower_band:
		(band.material_override as StandardMaterial3D).emission_energy_multiplier = 0.35 if excepted else 1.8
	for talker: MeshInstance3D in _tower_talkers:
		talker.visible = not excepted
	for stair: MeshInstance3D in _tower_stair:
		stair.visible = excepted

func _place_latch(feet: Vector3) -> void:
	if _latch == null:
		_latch = LatchView.new()
		_latch.name = "LatchWalk"
		add_child(_latch)
		_latch.set_render_layers(ArenaSky.ACTOR_LAYERS)
		_latch.set_weapon_visible(false)
		# Walking back from the machines' tower under the blue hour, Latch's
		# screen burns warm phosphor: a free agent, never a pale machine.
		_latch.set_face_phosphor(Color("ffb860"), Color("6a3a16"), 0.7)
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "LatchScreenLight"
		lamp.light_color = Color("ffb860")
		lamp.light_energy = 0.9
		lamp.omni_range = 2.4
		lamp.position = Vector3(0.0, 1.7, 0.0)
		_latch.add_child(lamp)
		_latch.position = feet
	if _latch_feet.is_finite():
		var delta: Vector3 = feet - _latch_feet
		var distance: float = Vector2(delta.x, delta.z).length()
		if distance > 0.001 and distance < 2.0:
			_latch_travel += distance
			_latch.rotation.y = atan2(delta.x, delta.z)
	_latch_feet = feet

func _process(delta: float) -> void:
	if not is_finite(delta) or _geometry.is_empty():
		return
	_flicker = fmod(_flicker + maxf(delta, 0.0), 64.0)
	for material: ShaderMaterial in _channel_materials:
		material.set_shader_parameter("ripple_time", fmod(_flicker * 1.6, 32.0))
	if _edda_light != null:
		_edda_light.light_energy = 2.2 + 0.25 * sin(_flicker * 7.3) + 0.12 * sin(_flicker * 17.1)
	# People waiting shift and look about; a slow turn is enough to stop a
	# crowd reading as a photograph.
	for index: int in range(_crowd.size()):
		_crowd[index].rotation.y = _crowd_yaw[index] + sin(_flicker * 0.35 + float(index) * 1.7) * 0.09
	if _latch != null and _latch_feet.is_finite():
		var before: Vector3 = _latch.position
		_latch.position = before.lerp(_latch_feet, clampf(delta * 10.0, 0.0, 1.0))
		_latch.advance(delta, Vector2(_latch.position.x - before.x, _latch.position.z - before.z).length(), "following")

# ---------------------------------------------------------------- helpers

func _box(label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	_static.add_child(node)
	return node

func _plane(label: String, at: Vector3, size: Vector2, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	_static.add_child(node)
	return node

func _quad(label: String, at: Vector3, size: Vector2, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	return node

func _light(label: String, at: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = label
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.light_specular = 0.25
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	_static.add_child(light)
	return light

static func _material(color: Color, glow: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
	return material
