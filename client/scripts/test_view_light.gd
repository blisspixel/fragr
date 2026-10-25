extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_view_light: " + message)

func _run() -> void:
	# Canon: muzzle light is warm or near-white, never Union red or
	# Inheritance cyan, and blades and fists make none.
	for weapon: String in ViewLight.FLASHES:
		var colour: Color = ViewLight.FLASHES[weapon]["colour"]
		var hue: float = colour.h * 360.0
		var red: bool = colour.s > 0.35 and (hue >= 340.0 or hue <= 20.0)
		var cyan: bool = colour.s > 0.15 and hue >= 160.0 and hue <= 220.0
		_check(not red and not cyan, "%s muzzle light is red or cyan" % weapon)
		_check(float(ViewLight.FLASHES[weapon]["seconds"]) <= 0.15, "%s muzzle light outlasts a flash" % weapon)
	_check(ViewLight.FLASHES["repeater"]["energy"] < ViewLight.FLASHES["tack"]["energy"]
		and ViewLight.FLASHES["scatter"]["energy"] > ViewLight.FLASHES["tack"]["energy"],
		"fast guns must burn dimmer than the Pistol and the Scatter brighter")
	_check(ViewLight.weapon_key(" Article Blade ") == "article_blade" and ViewLight.weapon_key("Tack") == "tack", "HUD weapon names map to wire keys")

	_check(ViewLight.sample(null) == Color.WHITE, "no camera samples as untinted")
	var scene: Node3D = Node3D.new()
	root.add_child(scene)
	var camera: Camera3D = Camera3D.new()
	scene.add_child(camera)
	_check(ViewLight.sample(camera) == Color.WHITE, "a camera without a ViewLight samples as untinted")
	_check(not ViewLight.flash(null, "Tack"), "no camera, no light")

	var view: ViewLight = ViewLight.attach(camera)
	_check(view != null and ViewLight.attach(camera) == view and camera.get_child_count() == 1, "attach reuses the one ViewLight under the camera")
	var muzzle: OmniLight3D = view.find_child(ViewLight.MUZZLE_NAME, false, false) as OmniLight3D
	_check(muzzle != null and not muzzle.visible and not muzzle.shadow_enabled, "the muzzle light waits dark and casts no shadow map")
	_check(muzzle != null and muzzle.position.z < 0.0 and muzzle.position.y < 0.0, "the muzzle light sits ahead of and below the eye")

	_check(not ViewLight.flash(camera, "Fists") and not ViewLight.flash(camera, "Shiv") and not ViewLight.flash(camera, "Article Blade"),
		"blades and fists make no muzzle light")
	_check(muzzle != null and not muzzle.visible, "a blade left the light dark")
	_check(ViewLight.flash(camera, "Tack", FragrSettings.FLASHES_FULL), "the Pistol lights its muzzle")
	var full: float = muzzle.light_energy if muzzle != null else 0.0
	_check(muzzle != null and muzzle.visible and is_equal_approx(full, float(ViewLight.FLASHES["tack"]["energy"])), "Full flashes fire at the gun's peak")
	_check(muzzle != null and muzzle.light_color == ViewLight.FLASHES["tack"]["colour"], "the light takes the gun's colour")
	view._process(0.0)
	_check(view.flash_energy() > 0.0, "a fresh shot reports its energy to the gun sample")
	view._process(0.03)
	_check(muzzle.visible and muzzle.light_energy < full and muzzle.light_energy > 0.0, "the pulse decays")
	view._process(0.2)
	_check(not muzzle.visible and is_zero_approx(muzzle.light_energy) and view.flash_energy() == 0.0, "the pulse is gone after its seconds")
	ViewLight.flash(camera, "Tack", FragrSettings.FLASHES_REDUCED)
	_check(is_equal_approx(muzzle.light_energy, full * ViewLight.FLASH_SCALE[FragrSettings.FLASHES_REDUCED]), "Reduced flashes dim the light")
	ViewLight.cancel(camera)
	_check(not muzzle.visible and is_zero_approx(muzzle.light_energy), "a rejected shot puts its light out at once")
	_check(not ViewLight.flash(camera, "Tack", FragrSettings.FLASHES_OFF) and not muzzle.visible, "Off flashes make no light")
	ViewLight.cancel(null)

	# The measurement.
	_check(is_equal_approx(ViewLight.tint_for(Color(0, 0, 0)).r, ViewLight.MIN_BRIGHT)
		and is_equal_approx(ViewLight.tint_for(Color(0.01, 0.01, 0.01)).g, ViewLight.MIN_BRIGHT), "a dark corner keeps the gun readable")
	var reference: Color = ViewLight.tint_for(Color(ViewLight.REFERENCE, ViewLight.REFERENCE, ViewLight.REFERENCE))
	_check(absf(reference.r - 1.0) < 0.01 and absf(reference.b - 1.0) < 0.01, "reference light leaves the art as authored")
	var bright: Color = ViewLight.tint_for(Color(40, 40, 40))
	_check(absf(bright.get_luminance() - ViewLight.MAX_BRIGHT) < 0.02, "a hot lamp never bleaches the gun")
	var sodium: Color = ViewLight.tint_for(Color(1.6, 1.0, 0.4))
	_check(sodium.r > sodium.b and sodium.b > 0.5 * sodium.r, "sodium warms the gun without painting it orange")
	_check(ViewLight.omni_attenuation(0.5, 10.0, 1.0) > ViewLight.omni_attenuation(4.0, 10.0, 1.0)
		and ViewLight.omni_attenuation(10.0, 10.0, 1.0) == 0.0 and ViewLight.omni_attenuation(2.0, 0.0, 1.0) == 0.0,
		"omni falloff matches the engine's shape and ends at its range")
	var roof: Dictionary = {"min_x": -5.0, "max_x": 5.0, "min_z": -5.0, "max_z": 5.0, "bottom": 3.0, "top": 3.5}
	_check(ViewLight.key_blocked(Vector3(0, 1.4, 0), Vector3.UP, [roof]), "a roof blocks an overhead key")
	_check(not ViewLight.key_blocked(Vector3(0, 1.4, 0), Vector3.UP, []), "open sky does not block the key")
	_check(not ViewLight.key_blocked(Vector3(0, 1.4, 0), Vector3.UP, ["bad", {"min_x": "x"}]), "malformed solids are ignored")

	var environment: Environment = Environment.new()
	environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	environment.ambient_light_energy = 1.0
	var none: Array[Light3D] = []
	var ambient: Color = ViewLight.incident_at(Vector3.ZERO, environment, none, [])
	_check(is_equal_approx(ambient.r, 0.5), "ambient is the flat floor")
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.36)
	lamp.light_energy = 3.0
	lamp.omni_range = 8.0
	scene.add_child(lamp)
	lamp.global_position = Vector3(0, 2, 0)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_energy = 1.0
	scene.add_child(key)
	key.rotation_degrees = Vector3(-90, 0, 0)
	var both: Array[Light3D] = [lamp, key]
	var near_lamp: Color = ViewLight.incident_at(Vector3(0, 1.5, 0), environment, both, [])
	var far_lamp: Color = ViewLight.incident_at(Vector3(0, 1.5, 20), environment, both, [])
	_check(near_lamp.r > far_lamp.r and near_lamp.r - near_lamp.b > far_lamp.r - far_lamp.b, "a near lamp brightens and warms the gun")
	var covered: Color = ViewLight.incident_at(Vector3(0, 1.5, 20), environment, both,
		[{"min_x": -5.0, "max_x": 5.0, "min_z": 15.0, "max_z": 25.0, "bottom": 3.0, "top": 3.5}])
	_check(covered.r < far_lamp.r, "a roof over the gun takes the key away")
	lamp.visible = false
	_check(is_equal_approx(ViewLight.incident_at(Vector3(0, 1.5, 0), environment, [lamp] as Array[Light3D], []).r, 0.5), "a hidden lamp gives no light")

	# Live: the node keeps a light list from the tree and smooths toward it.
	lamp.visible = true
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	scene.add_child(world)
	camera.global_position = Vector3(0, 1.6, 0.5)
	camera.make_current()
	view.set_solids([])
	for _i in 8:
		await process_frame
	var under: Color = ViewLight.sample(camera)
	camera.global_position = Vector3(0, 1.6, 30)
	for _i in 40:
		await process_frame
	var away: Color = ViewLight.sample(camera)
	_check(under.r > away.r, "walking away from a lamp darkens the gun: %s then %s" % [under, away])
	_check(under.a == 1.0 and away.a == 1.0, "the gun tint stays opaque")
	var tracked: int = view._lights.size()
	_check(view._lights.has(lamp) and view._lights.has(key), "the view tracks the tree's lamps")
	lamp.queue_free()
	await process_frame
	_check(view._lights.size() == tracked - 1, "a freed lamp leaves the light list")
	scene.queue_free()
	await process_frame
	if _failures == 0:
		print("test_view_light: PASS canon muzzle colours, flash lifecycle, accessibility scale, cancel, measurement and live sampling")
	quit(1 if _failures > 0 else 0)
