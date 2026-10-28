class_name ArenaDecoration
extends RefCounted

const PANEL_SHADER: Shader = preload("res://assets/shaders/facility_panel.gdshader")
const FacilitySource = preload("res://scripts/facility_geometry.gd")
const BONE: Color = Color("e8e2d6")
const INK: Color = Color("242c29")
## Edda's clinic sign with its lamp out: the letters are still there.
const DARK_SIGN: Color = Color("5d5a52")
## An old Union works board the seized infrastructure has relit in the
## Inheritance's muted working cyan.
const RELIT_SIGN: Color = Color("4a8a92")
## Stencil paint straight on a wall, a car side or a tank.
const STENCIL_PAINT: Color = Color("c8c1aa")
## Signwriter's cream on a free-side board.
const SIGNWRITING: Color = Color("e8d9b0")
## The circled six is sprayed in warm free paint; on the Moon's issued steel
## it is scratched, so it shows bare metal. A child's 67 is chalk.
const SPRAY: Color = Color("c45a20")
const SCRATCH: Color = Color("c9c1ad")
const CHALK: Color = Color("dcd8cc")

## How a registered panel shows itself. Signs stand only where a player needs
## them: the way on, the objective, one landmark name for an area, a few words
## each (Nick, 2026-10-25: "we have a ton of like billboard type signs with
## text on them. a bit odd."). The rest of the story is in the room: marks,
## pictures, papers nobody stops to read, props and light.
enum Look {
	PLATE, ## The registered style with its copy: the Office's enamel or a console.
	STENCIL, ## Copy painted straight on the host, no plate.
	PAINTED, ## A free-side signwritten board.
	PAPER, ## A pasted paper notice with a few words in ink.
	SCREEN, ## A console screen with no copy; its use prompt says what it does.
	NOTICE, ## Pinned papers and photographs, unreadable at play distance.
	CHALKBOARD, ## A market board chalked up in the morning.
	SIX, ## The circled six, the free side's mark where a secret waits.
	CHALK_67, ## A child's chalk 67.
	SERVICE, ## A service door's hazard plate.
	LIFT, ## The Office's lift pictogram toward the custody lift.
	HIDDEN, ## Nothing: the host is a plain wall, the presenter dresses it.
}
const LOOKS: Dictionary[String, Look] = {
	"property_sign": Look.HIDDEN, "intake_sign": Look.HIDDEN, "records_sign": Look.HIDDEN,
	"maintenance_sign": Look.SERVICE, "transfer_sign": Look.LIFT,
	"complaint_notice": Look.NOTICE, "terminal": Look.SCREEN, "lift_control": Look.SCREEN,
	"m03_platform_car": Look.STENCIL, "m03_siding_car": Look.STENCIL, "m03_roof_car": Look.STENCIL,
	"m03_mast_sign": Look.STENCIL,
	"m04_notice_board": Look.PAPER, "m04_tram_vote": Look.PAPER, "m04_clinic_sign": Look.PAINTED,
	"m04_workshop": Look.PAINTED, "m04_water_tank": Look.STENCIL, "m04_clinic_control": Look.SCREEN,
	"m04_paint_locker": Look.SIX, "m04_noodle_six": Look.SIX, "m04_meal_six": Look.SIX,
	"m04_clinic_care": Look.HIDDEN, "m04_repair_bench": Look.HIDDEN, "m04_field_printer": Look.HIDDEN,
	"m04_market_canvas": Look.HIDDEN,
	"m05_water_tank": Look.SIX, "m05_tram_service": Look.SIX, "m05_market_six": Look.SIX,
	"m05_paint_bench": Look.HIDDEN, "m05_loading_pen": Look.STENCIL,
	"m06_rail_confiscation": Look.STENCIL, "m06_service_six": Look.SIX, "m06_crane_overlook": Look.SIX,
	"m06_duty_free_six": Look.SIX, "m06_family_window": Look.HIDDEN,
	"m07_closed_shop": Look.PAPER, "m07_curfew_notice": Look.PAPER, "m07_sniper_rack": Look.STENCIL,
	"m07_chalk_67": Look.CHALK_67, "m07_lamp_six": Look.SIX, "m07_berm_six": Look.SIX,
	"m07_transit_arrival": Look.HIDDEN, "m07_port_overlook": Look.HIDDEN,
	"m08_checkpoint_form": Look.NOTICE, "m08_bay_form": Look.NOTICE, "m08_evidence_desk": Look.PAPER,
	"m08_mine_cage": Look.STENCIL, "m08_cold_cabinet": Look.STENCIL, "m08_custody_shaft": Look.STENCIL,
	"m08_observation_six": Look.SIX, "m08_lost_property_six": Look.SIX, "m08_service_six": Look.SIX,
	"m08_authorized_noise": Look.HIDDEN,
	"m19_market_board": Look.CHALKBOARD, "m19_tram_vote": Look.PAPER, "m19_clinic_dark": Look.PAINTED,
	"m19_floating_67": Look.CHALK_67, "m19_market_six": Look.SIX, "m19_service_six": Look.SIX,
	"m19_water_tank": Look.SIX, "m19_stores_sign": Look.HIDDEN,
	"m20_refuge_notice": Look.PAINTED, "m20_valve_six": Look.SIX, "m20_lamp_six": Look.SIX,
	"m20_crane_six": Look.SIX,
	"epilogue_tram_stop": Look.NOTICE, "epilogue_clinic_sign": Look.HIDDEN,
}
## Copy for the kinds that still carry words. A kind without an entry has none.
const SIGN_KEYS: Dictionary[String, String] = {
	"lift_sign": "WORLD_CUSTODY_LIFT",
	"m09_crew_manifest": "WORLD_M09_CREW_MANIFEST",
	"m09_board_carrier": "WORLD_M09_BOARD_CARRIER",
	"m10_ship_confirmation": "WORLD_M10_SHIP_CONFIRMATION",
	"m11_transfer_release": "WORLD_M11_TRANSFER_RELEASE",
	"m11_records_document": "WORLD_M11_RECORDS_DOCUMENT",
	"m11_stern_release": "WORLD_M11_STERN_RELEASE",
	"m10_cargo_deck": "WORLD_M10_CARGO_DECK",
	"m10_passenger_deck": "WORLD_M10_PASSENGER_DECK",
	"m10_command_deck": "WORLD_M10_COMMAND_DECK",
	"m03_schedule_board": "WORLD_M03_SCHEDULE_BOARD",
	"m03_schedule_cancelled": "WORLD_M03_SCHEDULE_CANCELLED",
	"m03_platform_car": "WORLD_M03_TRANSFER_CAR",
	"m03_siding_car": "WORLD_M03_TRANSFER_CAR",
	"m03_roof_car": "WORLD_M03_TRANSFER_CAR",
	"m03_mast_sign": "WORLD_M03_MAST_SIGN",
	"m03_board_train": "WORLD_M03_BOARD_TRAIN",
	"m04_clinic_sign": "WORLD_M04_CLINIC_SIGN",
	"m04_notice_board": "WORLD_M04_NOTICE_BOARD",
	"m04_tram_vote": "WORLD_M04_TRAM_MOTION",
	"m04_water_tank": "WORLD_M04_WATER_TANK",
	"m04_workshop": "WORLD_M04_WORKSHOP",
	"m04_roof_departure": "WORLD_M04_ROOF_DEPARTURE",
	"m05_loading_pen": "WORLD_M05_LOADING_PEN",
	"m05_freight_sign": "WORLD_M05_FREIGHT_SIGN",
	"m05_ship_departure": "WORLD_M05_SHIP_DEPARTURE",
	"m06_dust_declaration": "WORLD_M06_DUST_DECLARATION",
	"m06_rail_confiscation": "WORLD_CONFISCATED",
	"m06_freight_gantry": "WORLD_M06_FREIGHT_GANTRY",
	"m06_impound_observation": "WORLD_M06_IMPOUND_OBSERVATION",
	"m06_depot_overlook": "WORLD_M06_DEPOT_OVERLOOK",
	"m06_transit_departure": "WORLD_M06_TRANSIT_DEPARTURE",
	"m08_registry": "WORLD_M08_REGISTRY",
	"m08_bay_release": "WORLD_M08_BAY_RELEASE",
	"m08_mine_cage": "WORLD_M08_MINE_CAGE",
	"m08_cold_cabinet": "WORLD_M08_COLD_CABINET",
	"m08_evidence_desk": "WORLD_M08_EVIDENCE_DESK",
	"m08_freight_departure": "WORLD_M08_FREIGHT_DEPARTURE",
	"m08_custody_shaft": "WORLD_M08_CUSTODY_SHAFT",
	"m07_closed_shop": "WORLD_M07_CLOSED_SHOP",
	"m07_curfew_notice": "WORLD_M07_CURFEW_NOTICE",
	"m07_sniper_rack": "WORLD_CONFISCATED",
	"m07_depot_freight": "WORLD_M07_DEPOT_FREIGHT",
	"m19_stores_counter": "WORLD_M19_STORES_COUNTER",
	"m19_concourse_board": "WORLD_M19_CONCOURSE_BOARD",
	"m19_planned_works": "WORLD_M19_PLANNED_WORKS",
	"m19_clinic_dark": "WORLD_M19_CLINIC_DARK",
	"m19_tram_vote": "WORLD_M19_TRAM_VOTE",
	"m19_waterworks": "WORLD_M19_WATERWORKS",
	"m20_crossing_control": "WORLD_M20_CROSSING_CONTROL",
	"m20_refuge_notice": "WORLD_M20_REFUGE_NOTICE",
	"m20_pump_board": "WORLD_M20_PUMP_BOARD",
	"m20_tower_bridge": "WORLD_M20_TOWER_BRIDGE",
}
## Cosmetic planes only. The host solid remains the sole collision authority.
## Faces a mission presenter dresses itself; a plate here would hide them.
const PRESENTER_ONLY: Array[String] = ["m07_window_figure", "m20_harbour_display",
	"epilogue_ledger", "epilogue_bench", "epilogue_ferry_board", "epilogue_missing_board"]

## Mission controls share the terminal kind with ordinary counters.
## `marked_terminal` is that registered decoration index, or -1.
static func sign_key(kind: String, index: int, marked_terminal: int, terminal_key: String = "WORLD_LATCH_RECORD") -> String:
	if index == marked_terminal and kind == "terminal":
		# Recall Notice's file monitor names Latch itself. Do not add a
		# second billboard on the desk under that monitor.
		return "" if terminal_key == "WORLD_LATCH_RECORD" else terminal_key
	return str(SIGN_KEYS.get(kind, ""))

static func build(parent: Node3D, solids: Array, details: Array, venue: ArenaSky.Preset = null, marked_terminal: int = -1, terminal_key: String = "WORLD_LATCH_RECORD") -> void:
	var preset: ArenaSky.Preset = venue if venue != null else ArenaSky.scrapyard()
	for index: int in range(details.size()):
		var detail: Dictionary = details[index]
		var kind: String = detail["kind"]
		if kind in PRESENTER_ONLY:
			continue
		var size: Vector2 = Vector2(detail["size"][0], detail["size"][1])
		var panel: MeshInstance3D = MeshInstance3D.new()
		panel.name = "Detail_%d_%s" % [index, kind]
		var mesh: QuadMesh = QuadMesh.new()
		mesh.size = size
		panel.mesh = mesh
		panel.transform = MapDecoration.placement(solids[int(detail["solid"])], detail)
		panel.set_meta("host_solid", int(detail["solid"]))
		panel.set_meta("baseline_position", panel.position)
		var look: Look = look_of(kind)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = PANEL_SHADER
		material.set_shader_parameter("panel_size", size)
		material.set_shader_parameter("style", _style(kind))
		material.set_shader_parameter("paint_color", _paint(kind))
		panel.material_override = material
		parent.add_child(panel)
		if look == Look.HIDDEN:
			# The panel stays registered (mission facts name decorations by
			# index) but draws nothing.
			panel.visible = false
			continue
		if look in [Look.PLATE, Look.SCREEN, Look.SERVICE, Look.LIFT] and kind in ["vent", "lockers", "terminal", "lift_control", "strip_light", "maintenance_sign", "transfer_sign", "lift_sign", "m04_clinic_control", "m04_roof_departure", "m08_freight_departure", "m08_bay_release"]:
			var source: RefCounted = FacilitySource.new()
			panel.add_child(source.build(kind, size))
		var copy_key: String = sign_key(kind, index, marked_terminal, terminal_key)
		if not copy_key.is_empty():
			var label: WorldSign = WorldSign.new()
			label.name = "Copy"
			# Leave the tram windows and Orrin's physical backup case clear.
			var hardware_above: bool = kind in ["m04_tram_vote", "m08_cold_cabinet"]
			label.configure(copy_key, size * Vector2(0.86, 0.24 if hardware_above else 0.74),
				_copy_color(kind))
			if hardware_above:
				label.position.y = -size.y * 0.3
			label.position.z = 0.008
			panel.add_child(label)
		if kind == "strip_light":
			panel.add_child(_practical(preset))
		elif kind == "union_seal" and preset.accent_energy > 0.0:
			panel.add_child(_seal_lamp(preset))

static func look_of(kind: String) -> Look:
	return LOOKS.get(kind, Look.PLATE)

static func _copy_color(kind: String) -> Color:
	match kind:
		"m19_clinic_dark": return DARK_SIGN
		"m19_planned_works": return RELIT_SIGN
	match look_of(kind):
		Look.PAPER: return INK
		Look.STENCIL: return STENCIL_PAINT
		Look.PAINTED: return SIGNWRITING
	return BONE

## The hand paint of a mark: sage on the paint-vote locker, scratched bare
## metal in the Moon's issued steel, chalk for a child's 67, spray elsewhere.
static func _paint(kind: String) -> Color:
	if kind == "m04_paint_locker":
		return Color("5f8a85")
	if kind.begins_with("m06_") or kind.begins_with("m08_"):
		return SCRATCH
	if look_of(kind) == Look.CHALK_67:
		return CHALK
	if look_of(kind) == Look.PAINTED:
		return Color("a76343")
	return SPRAY

static func _style(kind: String) -> int:
	match look_of(kind):
		Look.STENCIL: return 9
		Look.SIX: return 10
		Look.CHALK_67: return 11
		Look.NOTICE: return 12
		Look.CHALKBOARD: return 13
		Look.SERVICE: return 14
		Look.LIFT: return 15
		Look.PAINTED: return 16
		Look.PAPER: return 6
		Look.SCREEN: return 3
	match kind:
		"lockers": return 1
		"vent": return 2
		"terminal", "lift_control", "m04_clinic_control", "m04_roof_departure", "m07_depot_freight", "m08_freight_departure", "m08_bay_release", "m09_crew_manifest", "m09_board_carrier", "m10_ship_confirmation", "m19_stores_counter", "m19_waterworks", "m20_crossing_control": return 3
		"gate_locked", "m08_seal_locked": return 7
		"gate_open", "m08_seal_open": return 8
		"m03_schedule_cancelled": return 7
		"strip_light": return 4
		"union_seal": return 5
		_: return 0

## The fixture's own light. Eight on the wire at most; the venue sets its
## colour and reach, and quality decides whether it casts shadows. The pool
## under each fixture and the dark between fixtures is the room's structure.
static func _practical(preset: ArenaSky.Preset) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "Practical"
	light.position.z = 0.22
	light.light_color = preset.practical_color
	light.light_energy = preset.practical_energy
	light.light_specular = 0.2
	light.omni_range = preset.practical_range
	light.omni_attenuation = preset.practical_attenuation
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 1.5
	# Past the fog the pool is unseen; stop drawing its shadow map, then the light.
	light.distance_fade_enabled = true
	light.distance_fade_begin = 40.0
	light.distance_fade_length = 10.0
	light.distance_fade_shadow = 24.0
	light.add_to_group(ArenaSky.PRACTICAL_GROUP)
	return light

## A small red lamp under a Union seal: authority as a colour on the wall, not
## a flood. No shadow map, short reach, and never enough to tint a fighter.
static func _seal_lamp(preset: ArenaSky.Preset) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "SealLamp"
	light.position = Vector3(0.0, 0.0, 0.35)
	light.light_color = preset.accent_color
	light.light_energy = preset.accent_energy
	light.light_specular = 0.0
	light.omni_range = preset.accent_range
	light.omni_attenuation = 2.0
	return light
