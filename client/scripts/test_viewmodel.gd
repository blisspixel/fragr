extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_viewmodel: " + message)

## Texel column that reaches the bottom edge: the gun stocks sit centrally,
## the Shiv's gauntlet enters from the lower right.
func _column(weapon_name: String) -> int:
	return 190 if weapon_name == "Shiv" else 112

func _check_bottom(weapon: TextureRect, context: String, column: int = 112) -> void:
	var bottom: float = root.get_visible_rect().size.y
	_check(weapon.position.y + weapon.size.y > bottom + 2.0, context + ": cut-off base must remain below the frame")
	var image: Image = weapon.texture.get_image()
	var texel_y: int = int((bottom - 1.0 - weapon.position.y) * float(image.get_height()) / weapon.size.y)
	_check(texel_y >= 0 and texel_y < image.get_height(), context + ": bottom pixel must come from the sprite")
	if texel_y >= 0 and texel_y < image.get_height():
		_check(image.get_pixel(column, texel_y).a > 0.99, context + ": weapon stock must cover the bottom pixel")

func _run() -> void:
	set_meta("fragr_settings_path", "user://test-viewmodel-%d.cfg" % OS.get_process_id())
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	hud.set_process(false)
	hud.call("set_fp_juice", true)
	var weapon: TextureRect = hud.get_node("FpWeapon")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2560, 1080)]:
		root.size = viewport_size
		await process_frame
		for weapon_name: String in ["Flechette", "Rail", "Scatter", "Tack", "Shiv"]:
			hud.call("set_fp_weapon", weapon_name)
			_check_bottom(weapon, weapon_name + " swap", _column(weapon_name))
			hud.call("set_fp_walk_speed", MoveStep.TOP_SPEED)
			for frame in range(240):
				if frame % 30 == 0:
					hud.call("show_fire_juice", weapon_name)
				hud.call("_process", 1.0 / 120.0)
				_check_bottom(weapon, weapon_name + " moving/firing", _column(weapon_name))
			hud.call("set_fp_walk_speed", 0.0)
			for frame in range(60):
				hud.call("_process", 1.0 / 60.0)
			var resting: Vector2 = weapon.position
			for frame in range(60):
				hud.call("_process", 1.0 / 60.0)
				_check(weapon.position == resting, "stationary fighter must not walk-bob")
			hud.set("head_bob_enabled", false)
			hud.call("set_fp_walk_speed", MoveStep.TOP_SPEED)
			for frame in range(60):
				hud.call("_process", 1.0 / 60.0)
				_check(weapon.position == resting, "bob setting must disable walking motion")
			hud.set("head_bob_enabled", true)
		hud.set_fp_weapon("Shiv")
		_check(weapon.visible and not hud.melee_view.visible, "the Shiv is one held blade, not the fists' arms")
		hud.show_fire_juice("Shiv")
		var widest: float = 1.0
		for frame in range(40):
			hud._process(1.0 / 120.0)
			widest = maxf(widest, weapon.scale.x)
			_check(not hud.fp_muzzle.visible, "a cut never flashes a muzzle")
			_check(weapon.position.y + weapon.pivot_offset.y * (1.0 - weapon.scale.y) + weapon.size.y * weapon.scale.y > root.get_visible_rect().size.y + 2.0, "the gauntlet stays below the frame through the thrust")
		_check(widest > hud.FP_SHIV_SCALE * 1.15 and is_equal_approx(weapon.scale.x, hud.FP_SHIV_SCALE), "the thrust reaches forward and settles back")
		hud.set_fp_weapon("Fists")
		_check(not weapon.visible and hud.melee_view.visible, "fists show independently animated arms")
		_check(weapon.scale == Vector2.ONE and weapon.pivot_offset == Vector2.ZERO, "swapping away from the Shiv clears its thrust")
		var first_arm: int = hud.melee_view.active_arm
		hud.show_fire_juice("Fists")
		_check(hud.melee_view.active_arm != first_arm and not hud.fp_muzzle.visible, "punch alternates arms without a gun flash")
		for frame in range(45):
			hud.melee_view._process(1.0 / 120.0)
			hud._process(1.0 / 120.0)
			for arm: TextureRect in hud.melee_view.arms:
				_check(arm.global_position.y + arm.size.y > root.get_visible_rect().size.y + 2.0, "punch wrists remain below frame")
		hud.show_fire_juice("Fists")
		_check(hud.melee_view.active_arm == first_arm, "second punch uses other arm")
	hud.call("set_fp_walk_speed", NAN)
	_check(float(hud.get("fp_walk_speed")) == 0.0, "invalid speed cannot poison animation")
	hud.call("set_fp_juice", false)
	_check(float(hud.get("fp_bob_weight")) == 0.0, "leaving first person clears walking state")
	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("test_viewmodel: PASS opaque bottom at swap, walk, recoil, resize; stationary and disabled bob")
	quit(0 if _failures == 0 else 1)
