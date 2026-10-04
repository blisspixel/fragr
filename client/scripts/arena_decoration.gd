class_name ArenaDecoration
extends RefCounted

const PANEL_SHADER: Shader = preload("res://assets/shaders/facility_panel.gdshader")
const FacilitySource = preload("res://scripts/facility_geometry.gd")
const BONE: Color = Color("e8e2d6")
const INK: Color = Color("242c29")
const SIGN_KEYS: Dictionary[String, String] = {
	"property_sign": "WORLD_PROPERTY_INTAKE", "intake_sign": "WORLD_CIVIC_INTAKE",
	"records_sign": "WORLD_TRANSFER_RECORDS", "maintenance_sign": "WORLD_SERVICE_ACCESS",
	"transfer_sign": "WORLD_TRANSFER_CONTROL", "lift_sign": "WORLD_CUSTODY_LIFT",
	"complaint_notice": "WORLD_PROPERTY_COMPLAINT", "terminal": "WORLD_TRANSFER_QUEUE",
	"lift_control": "WORLD_LIFT_CONTROL",
	"m09_crew_manifest": "WORLD_M09_CREW_MANIFEST",
	"m09_board_carrier": "WORLD_M09_BOARD_CARRIER",
	"m03_schedule_board": "WORLD_M03_SCHEDULE_BOARD",
	"m03_schedule_cancelled": "WORLD_M03_SCHEDULE_CANCELLED",
	"m03_platform_car": "WORLD_M03_PLATFORM_CAR",
	"m03_siding_car": "WORLD_M03_SIDING_CAR",
	"m03_roof_car": "WORLD_M03_ROOF_CAR",
	"m03_mast_sign": "WORLD_M03_MAST_SIGN",
	"m03_board_train": "WORLD_M03_BOARD_TRAIN",
	"m04_clinic_care": "WORLD_M04_CLINIC_CARE",
	"m04_clinic_sign": "WORLD_M04_CLINIC_SIGN",
	"m04_field_printer": "WORLD_M04_FIELD_PRINTER",
	"m04_market_canvas": "WORLD_M04_MARKET_CANVAS",
	"m04_meal_six": "WORLD_M04_MEAL_SIX",
	"m04_noodle_six": "WORLD_M04_NOODLE_SIX",
	"m04_notice_board": "WORLD_M04_NOTICE_BOARD",
	"m04_paint_locker": "WORLD_M04_PAINT_LOCKER",
	"m04_repair_bench": "WORLD_M04_REPAIR_BENCH",
	"m04_tram_vote": "WORLD_M04_TRAM_VOTE",
	"m04_water_tank": "WORLD_M04_WATER_TANK",
	"m04_workshop": "WORLD_M04_WORKSHOP",
	"m04_clinic_control": "WORLD_M04_CLINIC_CONTROL",
	"m04_roof_departure": "WORLD_M04_ROOF_DEPARTURE",
	"m05_water_tank": "WORLD_M05_WATER_TANK",
	"m05_paint_bench": "WORLD_M05_PAINT_BENCH",
	"m05_loading_pen": "WORLD_M05_LOADING_PEN",
	"m05_tram_service": "WORLD_M05_TRAM_SERVICE",
	"m05_market_six": "WORLD_M05_MARKET_SIX",
	"m05_freight_sign": "WORLD_M05_FREIGHT_SIGN",
	"m05_ship_departure": "WORLD_M05_SHIP_DEPARTURE",
	"m06_dust_declaration": "WORLD_M06_DUST_DECLARATION",
	"m06_rail_confiscation": "WORLD_M06_RAIL_CONFISCATION",
	"m06_freight_gantry": "WORLD_M06_FREIGHT_GANTRY",
	"m06_family_window": "WORLD_M06_FAMILY_WINDOW",
	"m06_service_six": "WORLD_M06_SERVICE_SIX",
	"m06_crane_overlook": "WORLD_M06_CRANE_OVERLOOK",
	"m06_duty_free_six": "WORLD_M06_DUTY_FREE_SIX",
	"m06_impound_observation": "WORLD_M06_IMPOUND_OBSERVATION",
	"m06_depot_overlook": "WORLD_M06_DEPOT_OVERLOOK",
	"m06_transit_departure": "WORLD_M06_TRANSIT_DEPARTURE",
	"m08_checkpoint_form": "WORLD_M08_CHECKPOINT_FORM",
	"m08_observation_six": "WORLD_M08_OBSERVATION_SIX",
	"m08_lost_property_six": "WORLD_M08_LOST_PROPERTY_SIX",
	"m08_registry": "WORLD_M08_REGISTRY",
	"m08_bay_release": "WORLD_M08_BAY_RELEASE",
	"m08_bay_form": "WORLD_M08_BAY_FORM",
	"m08_mine_cage": "WORLD_M08_MINE_CAGE",
	"m08_seal_locked": "WORLD_M08_SEAL_LOCKED",
	"m08_seal_open": "WORLD_M08_SEAL_OPEN",
	"m08_service_six": "WORLD_M08_SERVICE_SIX",
	"m08_cold_cabinet": "WORLD_M08_COLD_CABINET",
	"m08_evidence_desk": "WORLD_M08_EVIDENCE_DESK",
	"m08_authorized_noise": "WORLD_M08_AUTHORIZED_NOISE",
	"m08_freight_departure": "WORLD_M08_FREIGHT_DEPARTURE",
	"m08_custody_shaft": "WORLD_M08_CUSTODY_SHAFT",
	"m07_closed_shop": "WORLD_M07_CLOSED_SHOP",
	"m07_curfew_notice": "WORLD_M07_CURFEW_NOTICE",
	"m07_chalk_67": "WORLD_M07_CHALK_67",
	"m07_transit_arrival": "WORLD_M07_TRANSIT_ARRIVAL",
	"m07_lamp_six": "WORLD_M07_LAMP_SIX",
	"m07_berm_six": "WORLD_M07_BERM_SIX",
	"m07_sniper_rack": "WORLD_M07_SNIPER_RACK",
	"m07_port_overlook": "WORLD_M07_PORT_OVERLOOK",
	"m07_depot_freight": "WORLD_M07_DEPOT_FREIGHT",
}

## Cosmetic planes only. The host solid remains the sole collision authority.
## Faces a mission presenter dresses itself; a plate here would hide them.
const PRESENTER_ONLY: Array[String] = ["m07_window_figure"]

static func build(parent: Node3D, solids: Array, details: Array, venue: ArenaSky.Preset = null) -> void:
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
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = PANEL_SHADER
		material.set_shader_parameter("panel_size", size)
		material.set_shader_parameter("style", _style(kind))
		panel.material_override = material
		parent.add_child(panel)
		if kind in ["vent", "lockers", "terminal", "lift_control", "strip_light", "property_sign", "intake_sign", "records_sign", "maintenance_sign", "transfer_sign", "lift_sign", "m04_clinic_control", "m04_roof_departure", "m08_freight_departure", "m08_bay_release"]:
			var source: RefCounted = FacilitySource.new()
			panel.add_child(source.build(kind, size))
		if SIGN_KEYS.has(kind):
			var label: WorldSign = WorldSign.new()
			label.name = "Copy"
			label.configure(SIGN_KEYS[kind], size * Vector2(0.86, 0.74),
				INK if kind == "complaint_notice" else BONE)
			label.position.z = 0.008
			panel.add_child(label)
		if kind == "strip_light":
			panel.add_child(_practical(preset))
		elif kind == "union_seal" and preset.accent_energy > 0.0:
			panel.add_child(_seal_lamp(preset))

static func _style(kind: String) -> int:
	match kind:
		"lockers": return 1
		"vent": return 2
		"terminal", "lift_control", "m04_clinic_control", "m04_roof_departure", "m07_depot_freight", "m08_freight_departure", "m08_bay_release", "m09_crew_manifest", "m09_board_carrier": return 3
		"gate_locked", "m08_seal_locked": return 7
		"gate_open", "m08_seal_open": return 8
		"m03_schedule_cancelled": return 7
		"strip_light": return 4
		"union_seal": return 5
		"complaint_notice": return 6
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
