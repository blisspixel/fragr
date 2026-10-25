extends SceneTree

## The modelled guns and every picture baked from them: one source per gun,
## its markers where the tables say, palette-only frames on one canvas, warm
## light only, and a kill glyph for every weapon the feed can name.

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_gun_model: " + message)

func _palette() -> Array[Color]:
	var colours: Array[Color] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	if parsed is Dictionary:
		for value: Variant in (parsed as Dictionary).values():
			if value is Array and (value as Array).size() >= 3:
				colours.append(Color8(int(value[0]), int(value[1]), int(value[2])))
	return colours

func _run() -> void:
	var palette: Array[Color] = _palette()
	_check(palette.size() > 10, "docs/palette.json reads")
	for key: String in GunModel.RAMPS:
		for colour: Color in GunModel.RAMPS[key]:
			_check(colour in palette, "ramp %s uses only palette swatches: %s" % [key, colour.to_html(false)])
		_check(GunModel.MID.has(key) and GunModel.MID[key] < GunModel.RAMPS[key].size(), "ramp %s has a live albedo step" % key)
	# Light a gun makes is warm: never the Union's red or the Inheritance's cyan.
	for colour: Color in GunModel.RAMPS["glow"]:
		var hue: float = colour.h * 360.0
		_check(colour.s < 0.15 or (hue > 15.0 and hue < 60.0), "glow stays amber to bone: " + colour.to_html(false))
	var model: GunModel = GunModel.new()
	for weapon: String in GunModel.GUNS:
		var gun: Node3D = model.build(weapon, true)
		var marker: Node3D = gun.find_child("Muzzle", true, false) as Node3D
		_check(marker != null and marker.position.is_equal_approx(GunModel.MUZZLE[weapon]), weapon + " muzzle marker matches the table")
		_check(gun.find_child("TriggerHand", true, false) != null and gun.find_child("SupportHand", true, false) != null, weapon + " is held in both gloves")
		for node: Node in gun.find_children("*", "MeshInstance3D", true, false):
			var piece: MeshInstance3D = node as MeshInstance3D
			var finish: Variant = piece.material_override.get_meta("finish", "") if piece.material_override != null else ""
			_check(GunModel.RAMPS.has(str(finish)) and piece.has_meta("outline"), weapon + " part has a finish and outline group: " + str(piece.name))
		gun.free()
		var carried: ArrayMesh = GunModel.carried_mesh(weapon)
		_check(carried != null and carried.get_surface_count() <= 2 and GunModel.carried_mesh(weapon) == carried, weapon + " carries as one cached mesh of at most two draws")
		_check(GunModel.carried_mesh(weapon, true).get_surface_count() >= 3, weapon + " keeps a per-finish copy for recolouring presenters")
		var bare: Node3D = model.build(weapon, false)
		_check(bare.find_child("TriggerHand", true, false) == null, weapon + " world model has no hands")
		bare.free()
	_check(GunModel.carried_mesh("Flechette") == null and not GunModel.has_model("Flechette"), "an unmodelled gun has no carried model")
	# Every baked frame: one canvas per gun, palette texels, hard alpha.
	for weapon: String in WeaponArt.BAKED:
		var frames: Array = [WeaponArt.IDLE[weapon], WeaponArt.FIRE[weapon]]
		for set_name: String in ["draw", "recover", "reload"]:
			frames.append_array(WeaponArt.BAKED[weapon][set_name])
		_check(WeaponArt.BAKED[weapon]["draw"].size() == 3 and WeaponArt.BAKED[weapon]["recover"].size() == 2, weapon + " has three raise and two recovery frames")
		_check(WeaponArt.BAKED[weapon]["reload"].size() >= 6 and WeaponArt.BAKED[weapon]["reload"].size() <= 8, weapon + " reload has six to eight frames")
		for texture: Texture2D in frames:
			_check(texture.get_size() == Vector2(384, 240), weapon + " frame shares the held canvas: " + texture.resource_path)
		var image: Image = WeaponArt.IDLE[weapon].get_image()
		image.convert(Image.FORMAT_RGBA8)
		var stray: int = 0
		for y: int in range(0, image.get_height(), 3):
			for x: int in range(0, image.get_width(), 3):
				var texel: Color = image.get_pixel(x, y)
				if texel.a > 0.0 and (texel.a < 1.0 or not Color(texel.r, texel.g, texel.b) in palette):
					stray += 1
		_check(stray == 0, weapon + " rest frame is palette texels with hard alpha (%d stray)" % stray)
		_check(WeaponArt.PROFILE[weapon].resource_path.begins_with("res://assets/weapons/" + weapon.to_lower() + "/"), weapon + " pickup comes from its model")
	for weapon: String in WeaponArt.KILL_ICON:
		_check(WeaponArt.KILL_ICON[weapon].get_size() == Vector2(WeaponArt.KILL_ICON_SIZE), weapon + " kill glyph is 48x16")
	for weapon: String in ["Tack", "Flechette", "Scatter", "Rail", "Sniper", "Shiv", "Arc", "Rocket", "Article Blade", "Fists"]:
		_check(WeaponArt.kill_icon(weapon) == WeaponArt.KILL_ICON.get(weapon), weapon + " has its own kill glyph")
	_check(WeaponArt.kill_icon("Unsupported") == null, "an unknown weapon has no borrowed glyph")
	if failures == 0:
		print("test_gun_model: PASS palette ramps, markers, carried meshes, baked canvases and kill glyphs")
	quit(0 if failures == 0 else 1)
