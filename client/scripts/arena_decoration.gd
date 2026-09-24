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
static func build(parent: Node3D, solids: Array, details: Array) -> void:
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
			var light: OmniLight3D = OmniLight3D.new()
			light.name = "Practical"
			light.position.z = 0.22
			light.light_color = Color("ffe7ba")
			light.light_energy = 1.25
			light.omni_range = 9.0
			light.omni_attenuation = 1.5
			# Eight fill fixtures maximum on the wire. The directional scene
			# light supplies shadows; these markers do not add shadow maps.
			panel.add_child(light)

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
