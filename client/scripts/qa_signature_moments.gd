extends SceneTree

const SealCutPlateScript = preload("res://scripts/seal_cut_plate.gd")
const StampCardScript = preload("res://scripts/stamp_card.gd")

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	hud.set_process(false)

	# Inset background behind HUD so vitals plate contrasts cleanly
	var background: ColorRect = ColorRect.new()
	background.color = MenuTheme.SURFACE
	background.size = Vector2(1280, 720)
	hud.add_child(background)
	hud.move_child(background, 0)

	var out_dir: String = ProjectSettings.globalize_path("res://../docs/screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 1. Capture Seal Cut on Join for Free seat (frame 1: seal cut slit across readouts, bone numerals readable)
	hud.set_fp_juice(true)
	hud.vitals_seal_plate.play_seal_cut("coalition", false)
	hud.vitals_seal_plate._process(0.08) # frame 1: sharp blade cut slices through seal
	hud.health_value.text = "100"
	hud.armor_value.text = "50"
	await _capture_frame(out_dir.path_join("seal_cut_join_free.png"))

	# 2. Capture Seal Cut on Join for Union seat (frame 2: tamper seal descending/pressing on plate)
	hud.vitals_seal_plate.play_seal_cut("union", false)
	hud.vitals_seal_plate._process(0.16) # frame 2: tamper seal descending/pressing
	hud.health_value.text = "100"
	hud.armor_value.text = "100"
	await _capture_frame(out_dir.path_join("seal_cut_join_union.png"))

	# 3. Capture Stamped Sabotage round card
	hud.show_sabotage_result("UNION TAKES ROUND 1\nCHARGE DETONATED // SITE B DESTROYED", "HOST: UNION CARRIES THE FREQUENCY")
	hud.stamp_card.trigger_stamp(hud.round_message, MatchRules.THEIRS_MARK, false)
	await _capture_frame(out_dir.path_join("stamped_sabotage_round_card.png"))

	print("qa_signature_moments: PASS captured screenshots in " + out_dir)
	quit(0)

func _capture_frame(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null and not img.is_empty():
		var err: Error = img.save_png(path)
		if err == OK:
			print("qa_signature_moments: saved " + path)
		else:
			push_error("qa_signature_moments: failed to save " + path + " error=" + str(err))
	else:
		push_error("qa_signature_moments: null or empty image for " + path)
