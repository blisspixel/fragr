extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_menu_theme: " + message)

func _luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722

func _contrast(first: Color, second: Color) -> float:
	var a: float = _luminance(first)
	var b: float = _luminance(second)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)

func _inspect_type(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit:
		var control: Control = node as Control
		var font: Font = control.get_theme_font("font")
		var size: int = control.get_theme_font_size("font_size")
		_check(font == MenuTheme.FONT or font == MenuTheme.DISPLAY_FONT, str(node.get_path()) + " owns its UI face")
		_check(size in (MenuTheme.DISPLAY_SIZES if font == MenuTheme.DISPLAY_FONT else MenuTheme.PIXEL_SIZES), str(node.get_path()) + " uses the intended scale")
	for child: Node in node.get_children():
		_inspect_type(child)

func _run() -> void:
	var palette: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/palette.json"))
	_check(palette is Dictionary, "canonical palette is readable")
	if palette is Dictionary:
		for key: String in MenuTheme.SWATCHES:
			var bytes: Array = palette[key]
			_check(MenuTheme.SWATCHES[key].is_equal_approx(Color8(bytes[0], bytes[1], bytes[2], bytes[3])), "canonical swatch " + key)
	var world_font: FontFile = load("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
	var pixel_font: FontFile = MenuTheme.FONT as FontFile
	_check(pixel_font != world_font and pixel_font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and pixel_font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED, "UI font owns crisp rasterization without mutating world import")
	_check(pixel_font.allow_system_fallback, "player-authored Unicode retains system glyph fallback")
	_check(WorldSign.FONT == world_font, "world signs retain their imported resource")
	for context: MenuTheme.Context in [MenuTheme.Context.FRONT_END, MenuTheme.Context.GAMEPLAY]:
		var theme: Theme = MenuTheme.build(context)
		var roles: Dictionary = MenuTheme.colors(context)
		_check(theme == MenuTheme.build(context), "theme and generated icons are cached")
		for surface: Color in [roles.ink, roles.surface]:
			_check(_contrast(roles.text, surface) >= 4.5, "body text contrast")
			_check(_contrast(roles.accent, surface) >= 4.5, "accent text contrast")
		_check(_contrast(roles.muted, roles.ink) >= 4.5, "muted text on ink")
		_check(_contrast(roles.accent, roles.surface) >= 3.0, "focus contrast")
		for type: String in ["Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit"]:
			var style: StyleBoxFlat = theme.get_stylebox("disabled", type) as StyleBoxFlat
			_check(_contrast(theme.get_color("font_disabled_color", type), style.bg_color) >= 4.5, "disabled " + type + " remains readable")
	_check(MenuTheme.build(MenuTheme.Context.FRONT_END) != MenuTheme.build(MenuTheme.Context.GAMEPLAY), "menu appearance cannot mutate the cached gameplay theme")

	var settings_path: String = "user://test-menu-theme-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	menu.set("_settings", FragrSettings.new(settings_path))
	root.add_child(menu)
	for page: String in ["main", "profile", "settings", "host", "records"]:
		menu._show(page)
		await process_frame
		_inspect_type(menu)
		if page == "settings":
			var panel: SettingsPanel = menu._root.get_node("SettingsPanel")
			for tab: String in SettingsPanel.PAGES:
				panel.show_page(tab)
				await process_frame
				_inspect_type(panel)
			panel.show_page("CONTROLS")
			panel.begin_capture("trigger_remote_mines", 0)
			await process_frame
			await process_frame
			_check(panel._note.text.contains(tr("ACTION_TRIGGER_REMOTE_MINES")), "capture names the real bound action")
			for row: Node in panel._rows.get_children():
				if row is HBoxContainer:
					_check((row as Control).size.x <= panel._scroll.size.x, "all binding columns fit the settings scroll width")
	menu._show("profile")
	await process_frame
	var callsign: LineEdit = menu._root.get_node("Callsign")
	var unicode_name: String = "Élan 東京 Жук Ω café 星".lpad(24, "ø")
	_check(unicode_name.length() == 24, "exercise the full Unicode name allowance")
	callsign.text = unicode_name
	callsign.caret_column = unicode_name.length()
	_check(callsign.text == unicode_name and callsign.caret_column == 24, "profile keeps the full Unicode name and caret")
	menu.queue_free()
	await process_frame

	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	root.add_child(hud)
	hud.set_process(false)
	hud._spawn_floating_damage(100, "Rail")
	hud.show_radio("CONTESTED FREQUENCY", "A retained track")
	hud.show_station_card({"name": "CONTESTED FREQUENCY", "badge": "CF", "tagline": "The public airwaves remain open.", "color": "#ff00ff"})
	hud.combat_feed.push(unicode_name + " joined", MenuTheme.DANGER)
	await process_frame
	_inspect_type(hud)
	_check(hud.radio_card_badge.color == MenuTheme.BORDER, "station data does not inject a new chrome hue")
	_check(hud.combat_feed.get_child(0).get_theme_color("font_color") == MenuTheme.BONE, "danger marks do not turn small text below contrast")
	for path: String in ["DamageFlash", "SpawnFlash", "StreakFlash"]:
		_check((hud.get_node(path) as ColorRect).color.a == 0.0, "palette pass preserves prior effective flash opacity")
	_check(hud.health_value.get_theme_font("font") == MenuTheme.DISPLAY_FONT, "actual health readout uses the display face")
	_check(hud.radio_label.get_global_rect().end.x <= root.get_visible_rect().end.x, "long radio copy wraps inside the viewport")
	hud.set_match_rules(MatchRules.parse({"mode": "ctf"}))
	hud.show_round_end(unicode_name, "Capture limit", 10, "Round closed", [], "coalition", {"union": 2, "coalition": 3})
	await process_frame
	await process_frame
	_check(hud.round_backdrop.visible and hud.round_backdrop.get_global_rect().encloses(hud.round_message.get_global_rect()), "display-font round result fits its opaque card")
	hud.free()
	game.free()
	await process_frame
	if _failures == 0:
		print("test_menu_theme: PASS palette, contrast, contexts, owned type and Unicode")
	quit(0 if _failures == 0 else 1)
