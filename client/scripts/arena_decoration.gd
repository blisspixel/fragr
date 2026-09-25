class_name ArenaDecoration
extends RefCounted

const PANEL_SHADER: Shader = preload("res://assets/shaders/facility_panel.gdshader")
const BONE: Color = Color("e8e2d6")
const INK: Color = Color("242c29")
const SIGN_KEYS: Dictionary[String, String] = {
	"property_sign": "WORLD_PROPERTY_INTAKE", "intake_sign": "WORLD_CIVIC_INTAKE",
	"records_sign": "WORLD_TRANSFER_RECORDS", "maintenance_sign": "WORLD_SERVICE_ACCESS",
	"transfer_sign": "WORLD_TRANSFER_CONTROL", "lift_sign": "WORLD_CUSTODY_LIFT",
	"complaint_notice": "WORLD_PROPERTY_COMPLAINT", "terminal": "WORLD_TRANSFER_QUEUE",
	"lift_control": "WORLD_LIFT_CONTROL",
}

## Cosmetic planes only. The host solid remains the sole collision authority.
static func build(parent: Node3D, solids: Array, details: Array, venue: ArenaSky.Preset = null) -> void:
	var preset: ArenaSky.Preset = venue if venue != null else ArenaSky.scrapyard()
	for index: int in range(details.size()):
		var detail: Dictionary = details[index]
		var kind: String = detail["kind"]
		var size: Vector2 = Vector2(detail["size"][0], detail["size"][1])
		var panel: MeshInstance3D = MeshInstance3D.new()
		panel.name = "Detail_%d_%s" % [index, kind]
		var mesh: QuadMesh = QuadMesh.new()
		mesh.size = size
		panel.mesh = mesh
		panel.transform = MapDecoration.placement(solids[int(detail["solid"])], detail)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = PANEL_SHADER
		material.set_shader_parameter("panel_size", size)
		material.set_shader_parameter("style", _style(kind))
		panel.material_override = material
		parent.add_child(panel)
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
		"terminal", "lift_control": return 3
		"gate_locked": return 7
		"gate_open": return 8
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
