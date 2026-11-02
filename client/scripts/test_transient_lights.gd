extends SceneTree
## #521 transient light bounds. Every light a fight switches on for a moment
## (a gun's third-person flash, the eye's own muzzle light, a blast, a
## rocket's exhaust) stays inside ShotVfx's caps on energy and reach, casts no
## shadow map, and keeps the colour law: never Union red, never Inheritance
## cyan, the Railgun a cold near-white. Light fixtures drop their shadow maps
## under Compatibility, where a transient light joining them washed whole
## decks to white (client/qa/transient_light_review.gd measures that live).

var _failures: int = 0


func _initialize() -> void:
	set_meta("localexception_automated", true)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_transient_lights: " + message)


func _bounded(label: String, energy: float, reach: float) -> void:
	_check(energy > 0.0 and energy <= ShotVfx.TRANSIENT_MAX_ENERGY, "%s energy %.2f within %.1f" % [label, energy, ShotVfx.TRANSIENT_MAX_ENERGY])
	_check(reach > 0.0 and reach <= ShotVfx.TRANSIENT_MAX_RANGE, "%s reach %.1f m within %.1f m" % [label, reach, ShotVfx.TRANSIENT_MAX_RANGE])


func _run() -> void:
	var rows: int = 0
	for weapon: String in ShotVfx.MUZZLE_LOOK:
		var look: Dictionary = ShotVfx.MUZZLE_LOOK[weapon]
		_bounded("third-person " + weapon, float(look["energy"]), float(look["range"]))
		var colour: Color = look["light"]
		_check(not FactionPalette.is_red(colour) and not FactionPalette.is_cyan(colour), "%s light is neither Union red nor Inheritance cyan" % weapon)
		rows += 1
	for key: String in ViewLight.FLASHES:
		var spec: Dictionary = ViewLight.FLASHES[key]
		_bounded("eye " + key, float(spec["energy"]) * ViewLight.FLASH_SCALE[0], float(spec["range"]))
		rows += 1
	var rail: Color = ShotVfx.muzzle_light("Rail")
	_check(rail.s <= FactionPalette.WARM_WHITE_SATURATION and rail.v >= 0.85, "the Railgun lights a cold near-white: %s" % rail.to_html(false))
	# The eye's light as it is actually lit: full peak on the shot's frame.
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	for key: String in ViewLight.FLASHES:
		_check(ViewLight.flash(camera, key, LocalExceptionSettings.FLASHES_FULL), "%s lights the eye" % key)
		var view: ViewLight = camera.get_node(ViewLight.NODE_NAME) as ViewLight
		if not view.is_node_ready():
			await process_frame
			ViewLight.flash(camera, key, LocalExceptionSettings.FLASHES_FULL)
		var muzzle: OmniLight3D = view.get_node(ViewLight.MUZZLE_NAME) as OmniLight3D
		_bounded("lit eye " + key, muzzle.light_energy, muzzle.omni_range)
		_check(not muzzle.shadow_enabled, "%s eye light casts no shadow map" % key)
		ViewLight.cancel(camera)
	camera.free()
	# Blasts at the largest radius the server sends, several at once.
	var blasts: BlastVfx = BlastVfx.new()
	root.add_child(blasts)
	for serial: int in range(BlastVfx.MAX_LIGHTS + 1):
		blasts.blast(Vector3(float(serial), 0.0, 0.0), 12.0, serial)
	for light: Node in blasts.find_children("BlastLight*", "OmniLight3D", false, false):
		var omni: OmniLight3D = light as OmniLight3D
		if omni.visible:
			_bounded("blast", omni.light_energy, omni.omni_range)
			_check(not omni.shadow_enabled, "a blast light casts no shadow map")
			rows += 1
	_check(blasts.lights_lit() <= BlastVfx.MAX_LIGHTS, "blast lights stay pooled")
	blasts.free()
	# The fixtures' side of #521.
	_check(not RenderQuality.supports_fixture_shadows("gl_compatibility"), "Compatibility fixtures cast no shadow maps")
	_check(RenderQuality.supports_fixture_shadows("forward_plus"), "Forward+ fixtures keep theirs")
	await process_frame
	if _failures == 0:
		print("test_transient_lights: PASS %d transient lights within %.1f energy and %.1f m" % [rows, ShotVfx.TRANSIENT_MAX_ENERGY, ShotVfx.TRANSIENT_MAX_RANGE])
	quit(0 if _failures == 0 else 1)
