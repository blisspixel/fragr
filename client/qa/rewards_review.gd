extends SceneTree

## Rendering review from an isolated profile earned by earned_rewards_live.gd.
var _output: String
var _failed: bool = false

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error("rewards_review: " + message)

func _run() -> void:
	_output = OS.get_environment("FRAGR_QA_DIR")
	var profile_path: String = OS.get_environment("FRAGR_REWARDS_PROFILE")
	if not _output.is_absolute_path() or not profile_path.is_absolute_path():
		push_error("rewards_review: isolated absolute output/profile paths required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	OS.set_environment("FRAGR_RUN_DIR", _output.path_join("run"))
	# Boot applies preferences after the initial window setup. Use an isolated
	# windowed document so the real menu cannot restore the fullscreen default.
	var settings_path: String = _output.path_join("settings.cfg")
	var settings: FragrSettings = FragrSettings.new(settings_path)
	settings.set_value("video", "display_mode", 0)
	settings.set_value("video", "resolution_height", 720)
	_check(settings.save_to_disk() == OK, "isolated capture preferences save")
	set_meta("fragr_settings_path", settings_path)
	set_meta("fragr_records_path", profile_path)
	var store: PlayerRecords = PlayerRecords.for_tree(self)
	_check(store.error == OK and store.unlocks.size() == 2, "profile retains both real awards")
	if _failed:
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/boot_menu.tscn")
	await process_frame
	await process_frame
	await current_scene._show("rewards")
	await RenderingServer.frame_post_draw
	_capture("earned-profile.png", Vector2i(1280, 720))
	var panel: RewardsPanel = current_scene._root.get_node("RewardsPanel")
	panel.records = PlayerRecords.new("")
	panel.draft = PlayerRewards.DEFAULTS.duplicate()
	panel.draft["finish"] = "margin_teal"
	panel._refresh()
	# Rebuild for accurate locked criteria, keeping the preview uncommitted.
	set_meta("fragr_records_path", "")
	await current_scene._show("rewards")
	panel = current_scene._root.get_node("RewardsPanel")
	panel._selectors["finish"].select(2)
	panel._selectors["finish"].item_selected.emit(2)
	_check(panel._save.disabled, "locked preview cannot save")
	await RenderingServer.frame_post_draw
	_capture("locked-profile.png", Vector2i(1280, 720))
	current_scene.queue_free()
	await process_frame
	await _shader_pixels()
	await _frames()
	await RenderingServer.frame_post_draw
	_check(await ClientRetirement.for_tree(self).drain(), "review resources retire cleanly")
	if not _failed:
		print("rewards_review: PASS earned/locked profiles, shader pixels and eleven idle/fire/cycle comparisons")
	quit(1 if _failed else 0)

func _capture(filename: String, expected_size: Vector2i) -> void:
	var captured: Image = root.get_texture().get_image()
	_check(captured.get_size() == expected_size, "actual image dimensions: " + filename)
	captured.save_png(_output.path_join(filename))

func _shader_pixels() -> void:
	var fixture: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	fixture.fill(Color(0.3, 0.3, 0.3))
	fixture.set_pixel(2, 2, Color(0.4, 0.2, 0.1))
	fixture.set_pixel(4, 2, Color(0.8, 0.8, 0.8))
	fixture.set_pixel(6, 2, Color(0.1, 0.7, 0.8))
	fixture.set_pixel(8, 2, Color(0, 0, 0, 0))
	var texture: ImageTexture = ImageTexture.create_from_image(fixture)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(16, 16)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var face: TextureRect = TextureRect.new()
	face.texture = texture
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(face)
	await RenderingServer.frame_post_draw
	var original: Image = viewport.get_texture().get_image()
	for finish: String in ["oxide", "margin_teal"]:
		face.material = PlayerRewards.material(finish)
		await RenderingServer.frame_post_draw
		var painted: Image = viewport.get_texture().get_image()
		_check(painted.get_pixel(10, 2) != original.get_pixel(10, 2), "neutral dark metal actually changes: " + finish)
		for point: Vector2i in [Vector2i(2, 2), Vector2i(4, 2), Vector2i(6, 2), Vector2i(8, 2), Vector2i(10, 14)]:
			_check(painted.get_pixelv(point) == original.get_pixelv(point), "warm, bright, light, transparent and lower-grip controls stay exact: " + finish)
		for y: int in range(16):
			for x: int in range(16):
				_check(painted.get_pixel(x, y).a == original.get_pixel(x, y).a, "paint preserves every alpha texel")
		var before: Color = original.get_pixel(10, 2)
		var after: Color = painted.get_pixel(10, 2)
		var weights: Vector3 = Vector3(0.2126, 0.7152, 0.0722)
		_check(absf(Vector3(before.r, before.g, before.b).dot(weights) - Vector3(after.r, after.g, after.b).dot(weights)) < 0.005, "paint preserves luminance within output quantization: " + finish)
	viewport.queue_free()
	await process_frame

func _frames() -> void:
	root.size = Vector2i(960, 360)
	root.content_scale_size = Vector2i(960, 360)
	await process_frame
	var sample: int = 0
	for weapon: String in ["Tack", "Flechette", "Scatter", "Rail", "Sniper"]:
		var poses: Array[Texture2D] = [WeaponArt.IDLE[weapon], WeaponArt.FIRE[weapon]]
		if weapon == "Scatter":
			poses.append(WeaponArt.CYCLE[weapon])
		for pose: int in range(poses.size()):
			sample += 1
			var row: HBoxContainer = HBoxContainer.new()
			row.theme = MenuTheme.build()
			root.add_child(row)
			for finish: String in ["standard", "oxide", "margin_teal"]:
				var column: VBoxContainer = VBoxContainer.new()
				column.custom_minimum_size = Vector2(312, 350)
				row.add_child(column)
				var label: Label = Label.new()
				label.text = weapon + " / " + str(pose) + "\n" + PlayerRewards.label(finish)
				label.add_theme_font_size_override("font_size", 18)
				column.add_child(label)
				var face: TextureRect = TextureRect.new()
				face.texture = poses[pose]
				face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				face.custom_minimum_size = Vector2(312, 290)
				face.material = PlayerRewards.material(finish)
				column.add_child(face)
			await RenderingServer.frame_post_draw
			_capture("%02d_%s_pose%d.png" % [sample, weapon.to_lower(), pose], Vector2i(960, 360))
			row.queue_free()
			await process_frame
