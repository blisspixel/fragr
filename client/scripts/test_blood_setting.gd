extends SceneTree

## The Blood presentation setting: On by default, persisted through the one
## settings file, and Off reaches every blood path (the body-hit sprite, its
## thrown droplets and the joined player's damage edge). Machines keep their
## sparks and oil either way. Run:
##   godot --path client --headless --script res://scripts/test_blood_setting.gd

const BLOOD_DROPLET: Color = Color("6e1218")

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_blood_setting: " + message)

func _fighter_shot(target: String) -> Dictionary:
	return {"shooter_id": "self", "target_id": target, "hit": true, "damage": 20,
		"trace": {"weapon": "tack", "origin": [0.0, 1.6, 0.0], "end": [3.0, 1.2, 0.0],
			"impact": {"kind": "fighter", "normal": [-1.0, 0.0, 0.0]}}}

func _run() -> void:
	_check_store()
	_check_panel()
	_check_tables()
	_check_atlas()
	_check_effects()
	_check_damage_edge()
	if _failures == 0:
		print("test_blood_setting: PASS default on, persisted, every blood path neutral when off")
	quit(0 if _failures == 0 else 1)

func _check_store() -> void:
	var path: String = "user://test-blood-%d.cfg" % OS.get_process_id()
	var fresh: FragrSettings = FragrSettings.new(path)
	_check(fresh.blood(), "a fresh store defaults Blood to On")
	# A file without the key, or with a junk value, reads as On.
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("accessibility", "reduced_motion", true)
	cfg.save(ProjectSettings.globalize_path(path))
	var missing: FragrSettings = FragrSettings.new(path)
	missing.load_from_disk()
	_check(missing.blood() and missing.reduced_motion(), "a file without the key keeps Blood On and its other choices")
	cfg.set_value("accessibility", "blood", "off")
	cfg.save(ProjectSettings.globalize_path(path))
	var junk: FragrSettings = FragrSettings.new(path)
	junk.load_from_disk()
	_check(junk.blood(), "a non-boolean Blood value is refused for the default")
	junk.set_value("accessibility", "blood", false)
	_check(junk.save_to_disk() == OK, "Blood Off saves")
	var reloaded: FragrSettings = FragrSettings.new(path)
	reloaded.load_from_disk()
	_check(not reloaded.blood(), "Blood Off survives a fresh store")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check_panel() -> void:
	var path: String = "user://test-blood-panel-%d.cfg" % OS.get_process_id()
	var preferences: FragrSettings = FragrSettings.new(path)
	var panel: SettingsPanel = SettingsPanel.new()
	panel.preferences = preferences
	root.add_child(panel)
	panel.show_page("ACCESSIBILITY")
	var toggle: Button = panel.find_child("blood", true, false) as Button
	_check(toggle != null and toggle.toggle_mode and toggle.button_pressed, "Accessibility shows Blood, On by default")
	if toggle != null:
		toggle.button_pressed = false
		_check(toggle.text == TranslationServer.translate("LOOK_OFF"), "the Blood row reads Off once toggled")
	_check(preferences.blood(), "the draft does not change active preferences before saving")
	panel.save()
	_check(not preferences.blood(), "saving applies Blood Off")
	var loaded: FragrSettings = FragrSettings.new(path)
	loaded.load_from_disk()
	_check(not loaded.blood(), "the panel's Blood Off survives a fresh store")
	panel.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check_tables() -> void:
	_check(ShotVfx.fighter_class(ShotVfx.FLESH, true) == ShotVfx.FLESH, "a human bleeds with Blood On")
	_check(ShotVfx.fighter_class(ShotVfx.FLESH, false) == ShotVfx.FABRIC, "a human puffs dust with Blood Off")
	_check(ShotVfx.fighter_class("", false) == ShotVfx.FABRIC, "an unknown fighter never bleeds with Blood Off")
	_check(ShotVfx.fighter_class(ShotVfx.SYNTHETIC, true) == ShotVfx.SYNTHETIC
		and ShotVfx.fighter_class(ShotVfx.SYNTHETIC, false) == ShotVfx.SYNTHETIC, "machines spark and leak oil either way")
	_check(ShotVfx.impact_row("tack", "fighter", ShotVfx.FABRIC) == "fabric", "the fabric class picks its own impact row")
	_check(ShotVfx.impact_row("rail", "fighter", ShotVfx.FABRIC) == "rail"
		and ShotVfx.impact_row("shiv", "fighter", ShotVfx.FABRIC) == "melee", "the Railgun ring and melee smack stay their own")
	_check(ShotVfx.IMPACT_METRES.has("fabric"), "the fabric impact has a world size")

## Blood reads red: red well above green and blue. The fabric row has none of
## it and no Inheritance cyan; the flesh row is the positive control.
static func _reddish(colour: Color) -> bool:
	return colour.r > colour.g * 2.0 and colour.r > colour.b * 2.0 and colour.r > 0.2

static func _cyan(colour: Color) -> bool:
	return colour.b > colour.r + 0.08 and colour.g > colour.r + 0.08

func _row_counts(atlas: Image, row: String) -> Vector3i:
	var index: int = ShotVfx.IMPACT_ROWS.find(row)
	var cell: int = atlas.get_height() / ShotVfx.IMPACT_ROWS.size()
	var counts: Vector3i = Vector3i.ZERO
	for y: int in range(index * cell, (index + 1) * cell):
		for x: int in range(atlas.get_width()):
			var colour: Color = atlas.get_pixel(x, y)
			if colour.a == 0.0:
				continue
			counts.x += 1
			if _reddish(colour):
				counts.y += 1
			if _cyan(colour):
				counts.z += 1
	return counts

func _check_atlas() -> void:
	var atlas: Image = ShotVfx.IMPACTS.get_image()
	_check(atlas.get_width() == 32 * ShotVfx.IMPACT_FRAMES and atlas.get_height() == 32 * ShotVfx.IMPACT_ROWS.size(),
		"the impact atlas carries one 32 pixel row per impact class")
	if atlas.is_compressed():
		atlas.decompress()
	var flesh: Vector3i = _row_counts(atlas, "flesh")
	var fabric: Vector3i = _row_counts(atlas, "fabric")
	_check(flesh.y > 40, "the flesh row reads as blood (control): %d red pixels" % flesh.y)
	_check(fabric.x > 200, "the fabric row draws a visible puff: %d pixels" % fabric.x)
	_check(fabric.y == 0 and fabric.z == 0, "the fabric row has no red and no cyan: %d red, %d cyan" % [fabric.y, fabric.z])

func _colours(effects: ShotEffects) -> PackedColorArray:
	var mesh: ImmediateMesh = effects.get_node("Surface").mesh as ImmediateMesh
	var out: PackedColorArray = PackedColorArray()
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			out.append_array(arrays[Mesh.ARRAY_COLOR])
	return out

func _droplets(colours: PackedColorArray) -> int:
	var count: int = 0
	for colour: Color in colours:
		if colour.is_equal_approx(BLOOD_DROPLET) or _reddish(colour):
			count += 1
	return count

func _check_effects() -> void:
	var effects: ShotEffects = ShotEffects.new()
	root.add_child(effects)
	effects.fighter_surface = func(id: String) -> String:
		return ShotVfx.SYNTHETIC if id == "machine" else ShotVfx.FLESH
	_check(effects.blood, "shot effects start with Blood On")
	effects.ingest(1, [_fighter_shot("human")])
	_check(effects._effects.size() == 1 and effects._effects[0].surface == ShotVfx.FLESH, "Blood On: a human hit is flesh")
	_check(_droplets(_colours(effects)) > 0, "Blood On: a human hit throws dark red droplets")
	effects.clear()
	effects.blood = false
	effects.ingest(2, [_fighter_shot("human"), _fighter_shot("machine")])
	_check(effects._effects.size() == 2 and effects._effects[0].surface == ShotVfx.FABRIC,
		"Blood Off: a human hit is a fabric puff")
	_check(effects._effects.size() == 2 and effects._effects[1].surface == ShotVfx.SYNTHETIC,
		"Blood Off: a machine hit still sparks")
	_check(_droplets(_colours(effects)) == 0, "Blood Off: nothing red is thrown")
	effects.clear()
	effects.ingest(3, [_fighter_shot("nobody")])
	effects.fighter_surface = Callable()
	effects.ingest(4, [_fighter_shot("unresolved")])
	for effect: ShotEffects.Effect in effects._effects:
		_check(effect.surface == ShotVfx.FABRIC, "Blood Off: an unresolved fighter never bleeds")
	effects.free()

func _check_damage_edge() -> void:
	var path: String = "user://test-blood-hud-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", path)
	# The HUD alone, as the accessibility harness takes it: the match (and its
	# radio) never starts.
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	hud.set_process(false)
	var preferences: FragrSettings = FragrSettings.new(path)
	hud.apply_preferences(preferences)
	_check(hud.damage_flash_colour() == MenuTheme.DANGER, "Blood On: the damage edge is red")
	preferences.set_value("accessibility", "blood", false)
	preferences.set_value("accessibility", "screen_flashes", FragrSettings.FLASHES_FULL)
	hud.apply_preferences(preferences)
	_check(hud.damage_flash_colour() == MenuTheme.BONE, "Blood Off: the damage edge is a neutral bone")
	_check(hud.screen_flash.flash_mode == FragrSettings.FLASHES_FULL, "the Screen Flashes setting reaches the HUD flash")
	hud.fp_juice_enabled = true
	root.remove_meta("fragr_flash_history")
	hud.show_damage_flash()
	_check(hud.screen_flash.active and hud.screen_flash.current_color == MenuTheme.BONE, "Blood Off: the damage cue flashes bone")
	preferences.set_value("accessibility", "screen_flashes", FragrSettings.FLASHES_OFF)
	hud.apply_preferences(preferences)
	hud.show_damage_flash()
	_check(not hud.screen_flash.active, "Screen Flashes Off still suppresses the damage cue")
	hud.free()
	remove_meta("fragr_settings_path")
