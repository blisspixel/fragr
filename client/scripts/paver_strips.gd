class_name PaverStrips
extends Node3D

## Presents the snapshot's marked Paver strips: the bright bounded bed on the
## floor, the projector's light fan back to the Paver and a work light that
## lifts the night around it. Preparation brightens toward the work; each work
## pulse flashes. Never decides who is inside a strip.
const STRIP_SHADER: Shader = preload("res://assets/shaders/paver_strip.gdshader")
const LIFT: float = 0.03
const LENS_HEIGHT: float = 1.64
const LENS_FORWARD: float = 0.3
const FLOOR_OFFSET: float = 1.5
## Hear a strip being charged or worked within this many metres.
const AUDIBLE_RANGE: float = 34.0

var _strips: Dictionary[String, Dictionary] = {}
var _tick: int = 0
var _since: float = 0.0
var _clock: float = 0.0
## Set by the presenter: owner ids whose preparation the player was told about.
var announced: Dictionary[String, bool] = {}
signal strip_marked(owner_id: String, origin: Vector3)
signal strip_put_out(owner_id: String, origin: Vector3)

func clear() -> void:
	for key: String in _strips.keys():
		_retire(key)
	_strips.clear()
	announced.clear()

func apply_snapshot(snapshot: Dictionary) -> void:
	if not WorksFacts.validation_error(snapshot).is_empty():
		return
	var tick: int = int(snapshot.get("tick", 0))
	if tick < _tick:
		return
	if tick > _tick:
		_since = 0.0
	_tick = tick
	var actors: Dictionary = {}
	for actor: Variant in snapshot.get("players", []):
		if actor is Dictionary:
			actors[str(actor.get("id", ""))] = actor
	var seen: Array[String] = []
	for raw: Variant in snapshot.get("paver_strips", []):
		var strip: Dictionary = raw
		var key: String = str(strip["owner_id"])
		seen.append(key)
		if not _strips.has(key):
			_strips[key] = _build(strip)
			strip_marked.emit(key, _vector(strip["origin"]))
		var view: Dictionary = _strips[key]
		view["fact"] = strip
		var owner: Variant = actors.get(key)
		if owner is Dictionary:
			view["lens"] = Vector3(float(owner["x"]), float(owner["y"]) - FLOOR_OFFSET + LENS_HEIGHT, float(owner["z"])) \
				+ Vector3(cos(float(strip["yaw"])), 0.0, sin(float(strip["yaw"]))) * LENS_FORWARD
			view["owner_phase"] = str(owner.get("campaign", {}).get("phase", ""))
		_place(view)
	for key: String in _strips.keys():
		if key not in seen:
			var view: Dictionary = _strips[key]
			var fact: Dictionary = view["fact"]
			# A preparation that vanished before its work began was put out.
			if not bool(fact["working"]) and _tick < int(fact["phase_ends"]):
				strip_put_out.emit(key, _vector(fact["origin"]))
			_retire(key)
			_strips.erase(key)

func _process(delta: float) -> void:
	_clock += delta
	_since += delta
	for key: String in _strips:
		_animate(_strips[key])

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _build(strip: Dictionary) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.name = "PaverStrip"
	add_child(root)
	var bed: MeshInstance3D = MeshInstance3D.new()
	bed.name = "StripBed"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	bed.mesh = plane
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = STRIP_SHADER
	bed.material_override = material
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bed.layers = ArenaSky.WORLD_LAYERS
	root.add_child(bed)
	var fan: MeshInstance3D = MeshInstance3D.new()
	fan.name = "ProjectorFan"
	fan.mesh = ImmediateMesh.new()
	var fan_material: StandardMaterial3D = StandardMaterial3D.new()
	fan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fan_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fan_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fan_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fan_material.vertex_color_use_as_albedo = true
	fan_material.no_depth_test = false
	fan.material_override = fan_material
	fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fan.layers = ArenaSky.WORLD_LAYERS
	add_child(fan)
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "WorkLight"
	light.light_color = Color("e8ecf2")
	light.shadow_enabled = false
	light.light_specular = 0.1
	light.omni_attenuation = 1.2
	light.light_cull_mask = ArenaSky.WORLD_LAYERS | ArenaSky.ACTOR_LAYERS
	root.add_child(light)
	var hum: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	hum.name = "ProjectorCharge"
	hum.stream = WorksAudio.projector_charge()
	hum.bus = &"Effects"
	hum.max_distance = AUDIBLE_RANGE
	hum.unit_size = 6.0
	root.add_child(hum)
	var thud: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	thud.name = "WorkThud"
	thud.stream = WorksAudio.work_thud()
	thud.bus = &"Effects"
	thud.max_distance = AUDIBLE_RANGE
	thud.unit_size = 8.0
	root.add_child(thud)
	if is_inside_tree() and not get_tree().has_meta("fragr_automated"):
		hum.play()
	return {"root": root, "bed": bed, "fan": fan, "light": light, "hum": hum, "thud": thud, "fact": strip, "last_pulse": -1, "lens": Vector3.INF, "owner_phase": ""}

func _place(view: Dictionary) -> void:
	var strip: Dictionary = view["fact"]
	var root: Node3D = view["root"]
	var yaw: float = float(strip["yaw"])
	var length: float = float(strip["length"])
	var width: float = float(strip["half_width"]) * 2.0
	var origin: Vector3 = _vector(strip["origin"])
	# Local +X along the strip (server yaw: x = cos, z = sin).
	root.transform = Transform3D(Basis(Vector3.UP, -yaw), origin + Vector3.UP * LIFT)
	var bed: MeshInstance3D = view["bed"]
	bed.position = Vector3(length * 0.5, 0.0, 0.0)
	bed.scale = Vector3(length, 1.0, width)
	var material: ShaderMaterial = bed.material_override as ShaderMaterial
	material.set_shader_parameter("strip_length", length)
	material.set_shader_parameter("half_width", width * 0.5)
	var light: OmniLight3D = view["light"]
	light.position = Vector3(length * 0.5, 1.6, 0.0)
	light.omni_range = maxf(6.0, length * 0.55 + 2.5)

func _animate(view: Dictionary) -> void:
	var strip: Dictionary = view["fact"]
	var started: int = int(strip["phase_started"])
	var ends: int = int(strip["phase_ends"])
	var age: float = float(_tick - started) + minf(_since, 0.05) * 20.0
	var working: bool = bool(strip["working"])
	var progress: float = 1.0 if working else clampf(age / maxf(1.0, float(ends - started)), 0.0, 1.0)
	var pulse: float = 0.0
	if working:
		pulse = 1.0 - fposmod(age, 4.0) / 4.0
		var index: int = int(floor(age / 4.0))
		if index != int(view["last_pulse"]) and index < 3:
			view["last_pulse"] = index
			var thud: AudioStreamPlayer3D = view["thud"]
			if thud.is_inside_tree() and not get_tree().has_meta("fragr_automated"):
				thud.play()
	var bed: MeshInstance3D = view["bed"]
	var material: ShaderMaterial = bed.material_override as ShaderMaterial
	material.set_shader_parameter("progress", progress)
	material.set_shader_parameter("working", 1.0 if working else 0.0)
	material.set_shader_parameter("pulse", pulse)
	material.set_shader_parameter("clock", _clock)
	var light: OmniLight3D = view["light"]
	light.light_energy = (2.2 + 3.6 * pulse) if working else (0.35 + 1.6 * progress * progress)
	_draw_fan(view, progress, working, pulse)

func _draw_fan(view: Dictionary, progress: float, working: bool, pulse: float) -> void:
	var fan: MeshInstance3D = view["fan"]
	var mesh: ImmediateMesh = fan.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var lens: Vector3 = view["lens"]
	if lens == Vector3.INF:
		return
	var strip: Dictionary = view["fact"]
	var yaw: float = float(strip["yaw"])
	var forward: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw))
	var lateral: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var origin: Vector3 = _vector(strip["origin"]) + Vector3.UP * LIFT
	var far: Vector3 = origin + forward * float(strip["length"])
	var half: float = float(strip["half_width"])
	var strength: float = (0.16 + 0.22 * pulse) if working else (0.03 + 0.11 * progress)
	var bright: Color = Color(0.95, 0.96, 1.0, strength)
	var faint: Color = Color(0.95, 0.96, 1.0, strength * 0.15)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for pair: Array in [[origin - lateral * half, far - lateral * half], [far - lateral * half, far + lateral * half], [far + lateral * half, origin + lateral * half]]:
		mesh.surface_set_color(bright)
		mesh.surface_add_vertex(lens)
		mesh.surface_set_color(faint)
		mesh.surface_add_vertex(pair[0])
		mesh.surface_set_color(faint)
		mesh.surface_add_vertex(pair[1])
	mesh.surface_end()

func _retire(key: String) -> void:
	var view: Dictionary = _strips[key]
	(view["root"] as Node).queue_free()
	(view["fan"] as Node).queue_free()

## Strip under the given feet, for the local caption and HUD warning.
func covering(feet: Vector3) -> Dictionary:
	for key: String in _strips:
		var fact: Dictionary = _strips[key]["fact"]
		if WorksFacts.inside(fact, feet):
			return fact
	return {}
