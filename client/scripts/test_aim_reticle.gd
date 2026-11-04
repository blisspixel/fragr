extends SceneTree

var failures: Array[String] = []
var hud: CanvasLayer
var camera: Camera3D


func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("localexception_settings_path", "")
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _aim(weapon: String, cone: int) -> void:
	hud.current_fp_weapon = weapon.replace("_", "").capitalize()
	# Test the same names snapshots give the presenter.
	if weapon == "flechette":
		hud.current_fp_weapon = "Flechette"
	hud.set_aim_state({"weapon": weapon, "cone_microradians": cone})


func _run() -> void:
	root.size = Vector2i(1280, 720)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 75.0
	root.add_child(camera)
	camera.make_current()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	hud = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	hud.set_process(false)
	hud.set_fp_juice(true)
	_aim("flechette", 0)
	var pip: Rect2 = AimReticle.PIP
	var centre: Vector2 = hud.aim_reticle.global_position
	_check(hud.aim_reticle.visible and hud.aim_reticle.radius == 0.0, "rested Rifle is a pip")
	_check(not hud.crosshair_hbar.visible and not hud.crosshair_vbar.visible, "old bars do not obscure the cone")
	_aim("flechette", 9000)
	var first_bloom: float = hud.aim_reticle.radius
	_aim("flechette", 45000)
	var full_bloom: float = hud.aim_reticle.radius
	_check(full_bloom > first_bloom and first_bloom > 0.0, "authoritative sustained burst opens the ring")
	_check(hud.aim_reticle.global_position == centre and AimReticle.PIP == pip, "bloom never moves the pip")
	_aim("flechette", 0)
	_check(hud.aim_reticle.radius == 0.0, "authoritative rest closes the ring")
	_aim("rail", 0)
	_check(hud.aim_reticle.radius == 0.0, "rested Rail stays a pip")
	_aim("rail", 12000)
	_check(hud.aim_reticle.radius > 0.0, "moving Rail shows its server cone")
	_aim("scatter", 95000)
	var pellet_radius: float = hud.aim_reticle.radius
	_aim("scatter", 190000)
	_check(hud.aim_reticle.radius > pellet_radius, "running Scatter shows the wider pellet cone")
	_aim("flechette", 45000)
	_check(is_equal_approx(hud.aim_reticle.radius, full_bloom), "campaign table cone is not presented as exact")
	hud.fp_motion.select("Rail", false)
	hud.fp_motion.select("Scatter", true)
	hud.current_fp_weapon = "Scatter"
	hud.set_aim_state({"weapon": "scatter", "cone_microradians": 95000, "raise_ready_at": 24})
	hud.set_aim_state({"weapon": "scatter", "cone_microradians": 95000})
	_check(hud.fp_motion.shown == "Scatter" and hud.fp_motion.raise == 1.0, "authoritative ready settles the raised gun")
	_aim("flechette", 45000)
	camera.fov = 100.0
	hud._update_aim_reticle()
	_check(hud.aim_reticle.radius < full_bloom, "wider camera FOV shrinks projected angle")
	camera.fov = 75.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	hud._update_aim_reticle()
	_check(is_equal_approx(hud.aim_reticle.radius / full_bloom, 1280.0 / 720.0), "horizontal FOV uses viewport width")
	hud.reduced_motion = true
	_aim("flechette", 0)
	_check(hud.aim_reticle.radius == 0.0, "reduced motion still shows authoritative accuracy")
	_aim("sniper", 12000)
	hud.update_scope(1.0, "sniper", true, true)
	hud._update_aim_reticle()
	_check(not hud.crosshair.visible and not hud.aim_reticle.visible, "scope owns its reticle")
	hud.update_scope(1.0, "sniper", false, false)
	hud.current_fp_weapon = "Scatter"
	hud.set_vehicle_seat("gunner")
	hud.set_aim_state({"weapon": "flechette", "cone_microradians": 0})
	_check(hud.aim_reticle.is_visible_in_tree() and hud.aim_reticle.radius == 0.0, "mounted gun shows its own authoritative pip")
	hud.set_vehicle_seat("driver")
	_check(not hud.crosshair.visible, "driver has no firing sight")
	hud.set_vehicle_seat("")
	_aim("flechette", 0)
	hud.set_aim_state({})
	_check(not hud.aim_reticle.visible and hud.crosshair_hbar.visible, "watching without private aim restores static reticle")
	_aim("flechette", 45000)
	hud.set_fp_juice(false)
	_check(not hud.crosshair.visible, "death hides pip and cone together")
	_check(is_equal_approx(AimReticle.projected_radius(45000, 75.0, root.get_visible_rect().size.y * 0.5), full_bloom * 0.5), "pixel scale keeps angular size")
	_check(AimReticle.projected_radius(45000, NAN, 720.0) == 0.0, "invalid camera cannot create nonfinite geometry")
	hud.queue_free()
	camera.queue_free()
	await process_frame
	for failure: String in failures:
		push_error("test_aim_reticle: " + failure)
	if failures.is_empty():
		print("test_aim_reticle: PASS fixed pip, authoritative cone, projection, camera and lifecycle")
	quit(0 if failures.is_empty() else 1)
