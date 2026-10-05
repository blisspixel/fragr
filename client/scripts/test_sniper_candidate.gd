extends SceneTree

const Source = preload("res://art/models/sniper_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://test-sniper-candidate-%d.cfg" % OS.get_process_id())
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_sniper_candidate: " + message)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() == 1 else "res://art/models/candidates/sniper_views"
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("bake.json")))
	_check(receipt is Dictionary and receipt.get("runtime_selected") == false
		and receipt.get("source_sha256") == FileAccess.get_sha256(Source.SOURCE)
		and receipt.get("presenter_sha256") == FileAccess.get_sha256("res://art/models/sniper_source.gd")
		and receipt.get("bake_sha256") == FileAccess.get_sha256("res://../tools/preview_sniper_source.gd"),
		"candidate pictures bind exact offline source/presenter/bake")
	var pictures: Dictionary[String, Image] = {}
	for label: String in ["sniper_idle.png", "sniper_fire.png", "sniper.png"]:
		var picture: Image = Image.load_from_file(path.path_join(label))
		_check(picture != null, "candidate " + label + " exists")
		if picture == null:
			quit(1)
			return
		pictures[label] = picture
		var selected: Texture2D = WeaponArt.PROFILE["Sniper"] if label == "sniper.png" else WeaponArt.IDLE["Sniper"]
		print(label, " candidate=", picture.get_size(), " selected=", Vector2i(selected.get_width(), selected.get_height()), " bounds=", picture.get_used_rect())
		_check(picture.get_size() == Vector2i(selected.get_width(), selected.get_height()) and not picture.has_mipmaps(),
			label + " retains existing canvas/density without mipmaps")
		_check(receipt is Dictionary and receipt.get("frames", {}).get(label) == FileAccess.get_sha256(path.path_join(label)),
			label + " pixels match the actual rendered receipt")
		var hard_alpha: bool = true
		for y: int in range(picture.get_height()):
			for x: int in range(picture.get_width()):
				var alpha: float = picture.get_pixel(x, y).a
				hard_alpha = hard_alpha and (alpha == 0.0 or alpha == 1.0)
		_check(hard_alpha, label + " has deliberate hard pixel silhouette")
	for label: String in ["sniper_idle.png", "sniper_fire.png"]:
		var picture: Image = pictures[label]
		var bounds: Rect2i = picture.get_used_rect()
		_check(bounds.size.x >= 100 and bounds.size.y >= 145 and bounds.position.y >= 8 and bounds.end.y == 180,
			label + " has a useful held silhouette, sight headroom and lower wrist crop")
		var opaque_bottom: bool = true
		for y: int in range(160, 180):
			opaque_bottom = opaque_bottom and picture.get_pixel(112, y).a > 0.99
		_check(opaque_bottom, label + " keeps unchanged opaque lower column112 through bob/recoil/resize sampling")
	var flash: int = 0
	var idle: Image = pictures["sniper_idle.png"]
	var fire: Image = pictures["sniper_fire.png"]
	for y: int in range(90):
		for x: int in range(241):
			var a: Color = idle.get_pixel(x, y)
			var b: Color = fire.get_pixel(x, y)
			if b.a > 0.99 and b.r > a.r + 0.20 and b.g > a.g + 0.15 and b.b < 0.75:
				flash += 1
	_check(flash >= 10, "coherent flash accompanies actual muzzle-facing fire frame")
	await _check_actual_hud(idle, fire)
	if _failures == 0:
		print("test_sniper_candidate: PASS offline canvas/hash/alpha/registration/muzzle-flash and actual HUD walk/recoil/resize/scope checks; played comparison and selection separate")
	quit(0 if _failures == 0 else 1)

func _check_actual_hud(idle: Image, fire: Image) -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD") as CanvasLayer
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	hud.set_process(false)
	var idle_texture: ImageTexture = ImageTexture.create_from_image(idle)
	var fire_texture: ImageTexture = ImageTexture.create_from_image(fire)
	var selected_idle: Texture2D = WeaponArt.IDLE["Sniper"]
	var selected_fire: Texture2D = WeaponArt.FIRE["Sniper"]
	# Only this temporary presenter instance receives the offline candidate.
	# Production fire-frame selection remains unchanged and is never mutated.
	hud.viewmodel_textures = hud.viewmodel_textures.duplicate()
	hud.viewmodel_textures["Sniper"] = idle_texture
	hud.set_fp_juice(true)
	var weapon: TextureRect = hud.get_node("FpWeapon") as TextureRect
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2560, 1080)]:
		root.size = dimensions
		await process_frame
		hud.set_fp_weapon("Sniper")
		_check(weapon.texture == idle_texture and weapon.visible, "actual HUD accepts unscoped candidate without selecting global art")
		hud.set_fp_walk_speed(MoveStep.TOP_SPEED)
		var covered: bool = true
		for frame: int in range(240):
			if frame % 30 == 0:
				hud.show_fire_juice("Sniper")
			hud._process(1.0 / 120.0)
			weapon.texture = fire_texture if hud.fp_shot_age < WeaponArt.FIRE_SECONDS else idle_texture
			var bottom: float = root.get_visible_rect().size.y
			var texel: int = int((bottom - 1.0 - weapon.position.y) * 180.0 / weapon.size.y)
			covered = covered and weapon.position.y + weapon.size.y > bottom + 2.0 and texel >= 0 and texel < 180
			if texel >= 0 and texel < 180:
				covered = covered and weapon.texture.get_image().get_pixel(112, texel).a > 0.99
		_check(covered, "candidate covers the real lower HUD frame through unchanged Sniper bob/recoil at " + str(dimensions))
		var factor: float = hud.update_scope(1.0, "Sniper", true, true)
		_check(is_equal_approx(factor, L07Assets.SCOPE_FOV_FACTOR) and not weapon.visible and hud.sniper_scope.visible,
			"actual scope keeps its existing field of view and hides candidate held art")
		hud.update_scope(1.0, "Sniper", false, true)
		_check(weapon.visible and not hud.sniper_scope.visible, "ordinary scope release restores held presentation")
	_check(WeaponArt.IDLE["Sniper"] == selected_idle and WeaponArt.FIRE["Sniper"] == selected_fire,
		"candidate HUD proof leaves selected textures intact")
	hud.free()
	await process_frame
