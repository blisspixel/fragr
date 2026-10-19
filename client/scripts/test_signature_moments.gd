extends SceneTree

const SealCutPlateScript = preload("res://scripts/seal_cut_plate.gd")
const StampCardScript = preload("res://scripts/stamp_card.gd")
const ScreenFlashScript = preload("res://scripts/screen_flash.gd")

var _failures: int = 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_signature_moments: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# 1. Washes Removal Verification
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	hud.set_process(false)

	# Verify screen_flash is not triggered for spawn, warmup, podium, complete, fail
	if hud.screen_flash != null:
		hud.screen_flash.set_flash_mode(FragrSettings.FLASHES_FULL)
		hud.screen_flash.active = false

		hud.show_spawn_flash()
		_check(not hud.screen_flash.active, "show_spawn_flash does not trigger screen flash wash")

		hud.show_round_end("Winner", "frag limit", 20)
		_check(not hud.screen_flash.active, "show_round_end does not trigger podium flash wash")

		hud.show_episode_complete("HOST: Done")
		_check(not hud.screen_flash.active, "show_episode_complete does not trigger complete flash wash")

		hud.show_episode_fail("HOST: Fail")
		_check(not hud.screen_flash.active, "show_episode_fail does not trigger fail flash wash")

		# Damage flash is kept in first person play
		hud.set_fp_juice(true)
		hud.show_damage_flash()
		_check(hud.screen_flash.active and hud.screen_flash.current_reason == "damage", "show_damage_flash triggers directional edge damage flash")
		hud.screen_flash.active = false

	# 2. Seal Cut Plate Mechanics
	var plate = SealCutPlateScript.new()
	plate.size = Vector2(280, 80)
	root.add_child(plate)

	# Free allegiance stepped frames
	plate.play_seal_cut("coalition", false)
	_check(plate.is_playing and not plate.settled, "seal cut started playing")
	_check(plate.current_frame == 0, "frame 0 is intact seal")

	plate._process(0.08)
	_check(plate.current_frame == 1, "frame 1 is cut seal")

	plate._process(0.08)
	_check(plate.current_frame == 2, "frame 2 is peeling seal")

	plate._process(0.15)
	_check(plate.settled and plate.current_frame == 3, "frame 3 is settled scarred gunmetal")

	# Respawn shows final frame only
	plate.settle("coalition")
	_check(plate.settled and plate.current_frame == 3 and not plate.is_playing, "respawn settle shows final frame only")

	# Reduced motion shows final frame immediately
	plate.play_seal_cut("coalition", true)
	_check(plate.settled and plate.current_frame == 3 and not plate.is_playing, "reduced motion displays final frame immediately")

	# Union allegiance stepped frames
	plate.play_seal_cut("union", false)
	_check(plate.current_frame == 0, "union frame 0 is bare unsealed plate")
	plate._process(0.08)
	_check(plate.current_frame == 1, "union frame 1 is stencil mark")
	plate._process(0.08)
	_check(plate.current_frame == 2, "union frame 2 is descending seal")
	plate._process(0.15)
	_check(plate.settled and plate.current_frame == 3, "union frame 3 is affixed seal with checkmark")

	plate.queue_free()

	# 3. Stamp Card Mechanics
	var stamp = StampCardScript.new()
	root.add_child(stamp)
	var lbl = Label.new()
	lbl.text = "UNION TAKES THE MATCH"
	lbl.size = Vector2(400, 60)
	root.add_child(lbl)

	stamp.trigger_stamp(lbl, MenuTheme.DANGER, false)
	_check(stamp.is_animating, "stamp animation active")
	_check(is_equal_approx(lbl.scale.x, StampCardScript.FRAME1_SCALE), "frame 1 scale is 106%")
	_check(is_equal_approx(lbl.rotation, deg_to_rad(StampCardScript.TILT_DEGREES)), "stamp lands at 2.5 degree tilt")

	stamp._process(0.016)
	_check(not stamp.is_animating, "stamp settled")
	_check(is_equal_approx(lbl.scale.x, 1.0), "frame 2 scale settled to 100%")
	_check(is_equal_approx(lbl.rotation, deg_to_rad(StampCardScript.TILT_DEGREES)), "tilt retained after settle")

	# Reduced motion on stamp
	stamp.trigger_stamp(lbl, MenuTheme.EMBER, true)
	_check(not stamp.is_animating and is_equal_approx(lbl.scale.x, 1.0), "reduced motion on stamp settles immediately to 100%")

	# Magenta prevention on stamp
	stamp.trigger_stamp(lbl, Color(0.65, 0.1, 0.6), false)
	_check(stamp.stamp_color == MenuTheme.DANGER, "magenta stamp color is converted to danger red")

	lbl.queue_free()
	stamp.queue_free()
	hud.queue_free()

	if _failures == 0:
		print("test_signature_moments: PASS washes removed, stepped seal cut, side-awareness, stamped settle and motion bypass")
		quit(0)
	else:
		push_error("test_signature_moments: FAIL with %d failures" % _failures)
		quit(1)
