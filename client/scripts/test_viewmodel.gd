extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_viewmodel: " + message)

func _check_bottom(weapon: TextureRect, context: String) -> void:
	var bottom: float = root.get_visible_rect().size.y
	_check(weapon.position.y + weapon.size.y > bottom + 2.0, context + ": cut-off base must remain below the frame")
	var image: Image = weapon.texture.get_image()
	var texel_y: int = int((bottom - 1.0 - weapon.position.y) * float(image.get_height()) / weapon.size.y)
	_check(texel_y >= 0 and texel_y < image.get_height(), context + ": bottom pixel must come from the sprite")
	if texel_y >= 0 and texel_y < image.get_height():
		_check(image.get_pixel(112, texel_y).a > 0.99, context + ": weapon stock must cover the bottom pixel")

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
		for weapon_name: String in ["Flechette", "Rail", "Scatter"]:
			hud.call("set_fp_weapon", weapon_name)
			_check_bottom(weapon, weapon_name + " swap")
			hud.call("set_fp_walk_speed", MoveStep.TOP_SPEED)
			for frame in range(240):
				if frame % 30 == 0:
					hud.call("show_fire_juice", weapon_name)
				hud.call("_process", 1.0 / 120.0)
				_check_bottom(weapon, weapon_name + " moving/firing")
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
	hud.call("set_fp_walk_speed", NAN)
	_check(float(hud.get("fp_walk_speed")) == 0.0, "invalid speed cannot poison animation")
	hud.call("set_fp_juice", false)
	_check(float(hud.get("fp_bob_weight")) == 0.0, "leaving first person clears walking state")
	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("test_viewmodel: PASS opaque bottom at swap, walk, recoil, resize; stationary and disabled bob")
	quit(0 if _failures == 0 else 1)
