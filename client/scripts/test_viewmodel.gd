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
	match weapon_name:
		"Shiv":
			return 190
		"Tack":
			# Both retained frames have an opaque grip and right wrist at 144.
			return 144
		"Sniper":
			# The registered drawn pair has its right cuff at this column.
			return 174
		"Arc":
			# Right leather wrist shared by idle, discharge and capacitor reset.
			return 184
	return 112

func _check_bottom(weapon: TextureRect, context: String, column: int = 112) -> void:
	var bottom: float = root.get_visible_rect().size.y
	_check(weapon.position.y + weapon.size.y > bottom + 2.0, context + ": cut-off base must remain below the frame")
	var image: Image = weapon.texture.get_image()
	var texel_y: int = int((bottom - 1.0 - weapon.position.y) * float(image.get_height()) / weapon.size.y)
	_check(texel_y >= 0 and texel_y < image.get_height(), context + ": bottom pixel must come from the sprite")
	if texel_y >= 0 and texel_y < image.get_height():
		_check(image.get_pixel(column, texel_y).a > 0.99, context + ": weapon stock must cover the bottom pixel")

## Compare actual selected controls rather than their constants: one texel of
## the same player's resting glove must have the same display scale. Stabbing
## still deliberately reaches forward, then returns to that resting scale.
func _source_span(weapon: TextureRect, a: Vector2, b: Vector2) -> float:
	var fit: float = minf(weapon.size.x / weapon.texture.get_width(), weapon.size.y / weapon.texture.get_height())
	var transform: Transform2D = root.get_stretch_transform() * weapon.get_global_transform_with_canvas()
	return (transform * (a * fit)).distance_to(transform * (b * fit))

func _check_transformed_bottom(weapon: TextureRect, column: int, context: String) -> void:
	var image: Image = weapon.texture.get_image()
	var fit: float = minf(weapon.size.x / image.get_width(), weapon.size.y / image.get_height())
	var inset: Vector2 = (weapon.size - Vector2(image.get_size()) * fit) * 0.5
	var transform: Transform2D = root.get_stretch_transform() * weapon.get_global_transform_with_canvas()
	var bottom: float = root.size.y
	var wrist_base: Vector2 = transform * (inset + Vector2(column, image.get_height()) * fit)
	_check(wrist_base.y > bottom + 2.0, context + ": actual wrist base remains below the physical window")
	var sample: Vector2 = (transform.affine_inverse() * Vector2(wrist_base.x, bottom - 1.0) - inset) / fit
	_check(sample.y >= 0.0 and sample.y < image.get_height(), context + ": actual physical bottom samples the picture during use")
	if sample.y >= 0.0 and sample.y < image.get_height():
		_check(image.get_pixel(column, floori(sample.y)).a > 0.99, context + ": actual wrist is opaque at the physical bottom")

func _check_shiv_hand_scale(hud: CanvasLayer, weapon: TextureRect) -> void:
	hud.set_fp_walk_speed(0.0)
	hud.head_bob_enabled = false
	hud._process(1.0)
	hud.set_fp_weapon("Scatter")
	var reference: float = _source_span(weapon, Vector2(51, 163), Vector2(83, 178)) / Vector2(51, 163).distance_to(Vector2(83, 178))
	hud.set_fp_weapon("Shiv")
	var rest: float = _source_span(weapon, Vector2(164, 160), Vector2(191, 150)) / Vector2(164, 160).distance_to(Vector2(191, 150))
	_check(is_equal_approx(rest, reference), "resting Shiv glove texels match the Shotgun display scale at this aspect")
	var blade_rest: float = _source_span(weapon, Vector2(106, 44), Vector2(142, 98))
	_check(blade_rest > reference * 60.0, "unchanged Shiv blade retains its substantial diagonal silhouette")
	hud.show_fire_juice("Shiv")
	var longest: float = blade_rest
	for frame: int in range(60):
		hud._process(1.0 / 120.0)
		longest = maxf(longest, _source_span(weapon, Vector2(106, 44), Vector2(142, 98)))
		_check_transformed_bottom(weapon, 190, "Shiv")
	_check(longest > blade_rest * 1.15, "ordinary resolved use still reaches forward visibly")
	var settled: float = _source_span(weapon, Vector2(164, 160), Vector2(191, 150)) / Vector2(164, 160).distance_to(Vector2(191, 150))
	_check(is_equal_approx(settled, reference), "resolved use settles to the same player's glove scale")
	hud.head_bob_enabled = true

func _check_arc_hand_scale(hud: CanvasLayer, weapon: TextureRect) -> void:
	hud.set_fp_walk_speed(0.0)
	hud.head_bob_enabled = false
	hud._process(1.0)
	hud.set_fp_weapon("Scatter")
	var reference: float = _source_span(weapon, Vector2(51, 163), Vector2(83, 178)) / Vector2(51, 163).distance_to(Vector2(83, 178))
	hud.set_fp_weapon("Arc")
	var actual: float = _source_span(weapon, Vector2(32, 160), Vector2(57, 178)) / Vector2(32, 160).distance_to(Vector2(57, 178))
	_check(is_equal_approx(actual, reference), "Arc glove texels match the actual Shotgun display scale at this aspect")
	for texture: Texture2D in [WeaponArt.IDLE["Arc"], WeaponArt.FIRE["Arc"], WeaponArt.CYCLE["Arc"], WeaponArt.ARC_RELOAD]:
		_check(texture.get_size() == WeaponArt.IDLE["Scatter"].get_size(), "all Arc held poses share the actual approved full canvas")
		weapon.texture = texture
		var used: Rect2i = texture.get_image().get_used_rect()
		_check(used.size.x >= 180 and used.size.y >= 160 and used.end.y == 180, "Arc has a substantial receiver and gloves through the canvas bottom")
		_check_transformed_bottom(weapon, _column("Arc"), "Arc held pose")
	var state: Dictionary = {"selected":"arc", "tick":20, "weapons":["fists", "arc"], "ammo":[{"pool":"bullets","rounds":0},{"pool":"shells","rounds":0},{"pool":"cells","rounds":40}], "loaded":[{"weapon":"arc","rounds":0,"ready_at":42}], "dry_fire_count":0}
	hud.equipment_hud.apply(state)
	hud._process(0.01)
	_check(weapon.texture == WeaponArt.ARC_RELOAD, "HUD shows capacitor reset only for the actual pending reload")
	_check_transformed_bottom(weapon, _column("Arc"), "Arc authoritative reload")
	hud.equipment_hud.tick = 42
	hud._process(0.01)
	_check(weapon.texture == WeaponArt.IDLE["Arc"], "authoritative ready tick returns the Arc to idle")
	hud.equipment_hud.apply({})
	hud.head_bob_enabled = true

## Each gun shows its drawn fire frame for the shot, the Shotgun pumps after
## it, and every gun settles back to its idle pose.
func _check_fire_frames(hud: CanvasLayer, weapon: TextureRect) -> void:
	hud.set_fp_walk_speed(0.0)
	for weapon_name: String in ["Tack", "Flechette", "Scatter", "Rail", "Sniper", "Arc"]:
		hud.set_fp_weapon(weapon_name)
		_check(weapon.texture == WeaponArt.IDLE[weapon_name], weapon_name + " rests on its idle frame")
		hud.show_fire_juice(weapon_name)
		_check(weapon.texture == WeaponArt.FIRE[weapon_name], weapon_name + " shows its fire frame on the shot")
		_check(not hud.fp_muzzle.visible, weapon_name + " fire frame carries its own flash")
		_check_bottom(weapon, weapon_name + " fire frame", _column(weapon_name))
		var pumped: bool = false
		for frame: int in range(48):
			hud._process(1.0 / 120.0)
			pumped = pumped or weapon.texture == WeaponArt.CYCLE.get(weapon_name)
			_check_bottom(weapon, weapon_name + " after the shot", _column(weapon_name))
		_check(pumped == WeaponArt.CYCLE.has(weapon_name), weapon_name + " cycle frame only where drawn")
		for frame: int in range(40):
			hud._process(1.0 / 120.0)
		_check(weapon.texture == WeaponArt.IDLE[weapon_name], weapon_name + " settles back to idle")

## The off hand rises with the grenade, releases it while the gun dips, then
## both return.
func _check_throw(hud: CanvasLayer, weapon: TextureRect) -> void:
	hud.set_fp_weapon("Rail")
	for frame: int in range(30):
		hud._process(1.0 / 60.0)
	var rest: float = weapon.position.y
	hud.show_grenade_throw()
	var hand: TextureRect = hud.fp_throw_hand
	var readied: bool = false
	var released: bool = false
	var deepest: float = rest
	for frame: int in range(48):
		hud._process(1.0 / 120.0)
		readied = readied or (hand.visible and hand.texture == WeaponArt.GRENADE_READY)
		released = released or (hand.visible and hand.texture == WeaponArt.GRENADE_THROW)
		deepest = maxf(deepest, weapon.position.y)
	_check(readied and released, "the throw shows the ready and release frames")
	_check(deepest > rest + 60.0, "the gun dips out of the way during the throw")
	for frame: int in range(30):
		hud._process(1.0 / 120.0)
	_check(not hand.visible and weapon.position.y == rest, "hand and gun return after the throw")
	hud.show_mine_place()
	var held: bool = false
	var tossed: bool = false
	for frame: int in range(48):
		hud._process(1.0 / 120.0)
		held = held or (hand.visible and hand.texture == WeaponArt.MINE_READY)
		tossed = tossed or (hand.visible and hand.texture == WeaponArt.MINE_PLACE)
	_check(held and tossed, "placing a mine shows the mine in the same off hand")
	for frame: int in range(30):
		hud._process(1.0 / 120.0)
	hud.show_grenade_throw()
	hud._process(1.0 / 120.0)
	_check(hand.texture == WeaponArt.GRENADE_READY, "the next grenade throw shows the grenade again")
	for frame: int in range(60):
		hud._process(1.0 / 120.0)

func _check_missing_art(hud: CanvasLayer, weapon: TextureRect) -> void:
	hud.set_fp_weapon("Sniper")
	hud.update_scope(1.0, "Sniper", true, true)
	_check(hud.sniper_scope.scoped() and not weapon.visible, "known scoped Sniper hides its held frame")
	hud.set_fp_weapon("Repeater")
	_check(not weapon.visible and weapon.texture == null and hud.current_fp_weapon == "", "unsupported Repeater clears the prior gun rather than borrowing it")
	hud.update_scope(1.0, "Repeater", false, true)
	_check(not hud.sniper_scope.scoped() and not weapon.visible, "scope release cannot reveal the prior Sniper for Repeater")
	for unsupported: String in ["Repeater", "Unsupported"]:
		hud.show_fire_juice(unsupported)
		_check(not hud.fp_muzzle.visible and hud.fp_muzzle_timer == 0.0 and is_inf(hud.fp_shot_age), "unsupported resolved fire has no borrowed frame or generic old-gun flash")
	hud._process(0.2)
	_check(not weapon.visible and weapon.texture == null and not hud.melee_view.visible, "unsupported gun remains absent through presentation updates")
	hud.set_fp_weapon("Flechette")
	_check(weapon.visible and weapon.texture == WeaponArt.IDLE["Flechette"], "known selected Rifle returns with its actual idle frame")
	hud.show_fire_juice("Flechette")
	_check(weapon.texture == WeaponArt.FIRE["Flechette"] and not hud.fp_muzzle.visible, "known selected Rifle retains its actual resolved fire frame")
	hud._process(0.03)
	var age: float = hud.fp_shot_age
	hud.show_fire_juice("Unsupported")
	_check(hud.fp_shot_age == age and weapon.texture == WeaponArt.FIRE["Flechette"] and not hud.fp_muzzle.visible, "unsupported fire cannot replace an existing known Rifle shot")
	hud._process(0.5)
	_check(weapon.texture == WeaponArt.IDLE["Flechette"], "known Rifle still settles to its own idle after unsupported fire")

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
	_check_missing_art(hud, weapon)
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2560, 1080)]:
		root.size = viewport_size
		await process_frame
		_check_shiv_hand_scale(hud, weapon)
		_check_arc_hand_scale(hud, weapon)
		for weapon_name: String in ["Flechette", "Rail", "Scatter", "Tack", "Sniper", "Shiv", "Arc"]:
			hud.call("set_fp_weapon", weapon_name)
			_check_bottom(weapon, weapon_name + " swap", _column(weapon_name))
			hud.call("set_fp_walk_speed", MoveStep.TOP_SPEED)
			for frame in range(240):
				if frame % 30 == 0:
					hud.call("show_fire_juice", weapon_name)
				hud.call("_process", 1.0 / 120.0)
				_check_bottom(weapon, weapon_name + " moving/firing", _column(weapon_name))
				if weapon_name == "Arc":
					_check_transformed_bottom(weapon, _column("Arc"), "Arc moving/firing")
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
	_check_fire_frames(hud, weapon)
	_check_throw(hud, weapon)
	hud.call("set_fp_walk_speed", NAN)
	_check(float(hud.get("fp_walk_speed")) == 0.0, "invalid speed cannot poison animation")
	hud.call("set_fp_juice", false)
	_check(float(hud.get("fp_bob_weight")) == 0.0, "leaving first person clears walking state")
	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("test_viewmodel: PASS opaque bottom at swap, walk, recoil, resize; stationary and disabled bob")
	quit(0 if _failures == 0 else 1)
