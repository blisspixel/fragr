extends SceneTree

## Wave 1 visual QA regressions: one pixel type system on the match HUD,
## backed corner text, the first-run controls hint, taunt addressing, kill
## feed names, the armor readout on its plate and pixel world text.

class Fighter extends Node:
	var player_id: String = ""

class CameraProbe extends Node:
	var target: Node
	var fp_mode: bool = false
	func get_followed_target() -> Node:
		return target

var _failures: int = 0
var _audited: Array[String] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_hud_type: " + message)

func _settle() -> void:
	for _frame: int in range(3):
		await process_frame

## Every visible HUD label with text: words in the pixel face and capitals,
## the display face only for numerals.
func _audit_type(node: Node, where: String) -> void:
	for child: Node in node.get_children():
		if child is Label:
			var label: Label = child
			if label.is_visible_in_tree() and not label.text.strip_edges().is_empty():
				_audited.append(str(label.name))
				var font: Font = label.get_theme_font("font")
				var numeral: bool = font == MenuTheme.DISPLAY_FONT and MenuTheme.is_numeral_text(label.text)
				_check(font == MenuTheme.FONT or numeral, "%s: %s uses the pixel face, not %s: %s" % [where, label.name, font.resource_path, label.text])
				_check(label.uppercase or numeral, "%s: %s is drawn in capitals: %s" % [where, label.name, label.text])
				_check(is_zero_approx(label.get_global_transform().get_rotation()), "%s: %s sits on a level baseline" % [where, label.name])
		_audit_type(child, where)

func _run() -> void:
	_check(MenuTheme.is_numeral_text("16|60") and MenuTheme.is_numeral_text("100") and not MenuTheme.is_numeral_text("FRAGGED BY Rival"), "numerals are digits and readout separators only")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	root.add_child(hud)
	game.hud = hud
	game.net_client = game.get_node("NetClient")
	game.net_client.player_id = "self"
	game.is_human_player = true
	var camera: CameraProbe = CameraProbe.new()
	var watched: Fighter = Fighter.new()
	watched.player_id = "watched"
	camera.target = watched
	game.camera = camera

	# First run: the play legend shows once, fades, and never comes back.
	var settings := FragrSettings.new("user://test-hud-type-%d.cfg" % OS.get_process_id())
	hud.apply_preferences(settings)
	_check(hud.controls_hint_pending, "a fresh install owes the fighter one controls hint")
	var shown: Array[int] = []
	hud.controls_hint_shown.connect(func() -> void: shown.append(1))
	hud.set_mode("PLAYING")
	hud._process(0.0)
	var hint: String = hud.regions.hints.text
	_check(not hint.is_empty() and shown.size() == 1 and not hud.controls_hint_pending, "the first join shows the play legend once: " + hint)
	_check(not hint.to_lower().contains("opens"), "the legend names Use, not 'opens': " + hint)
	await _settle()
	_check(hud.regions.backings.context.visible and hud.regions.backings.context.get_global_rect().encloses(HudRegions.text_bounds(hud.regions.hints)), "the hint sits on its own backing over the world")
	hud.mode_entered_ms = Time.get_ticks_msec() - hud.CONTROLS_HINT_MS + hud.CONTROLS_HINT_FADE_MS / 2
	hud._process(0.0)
	_check(hud.regions.hints.modulate.a > 0.0 and hud.regions.hints.modulate.a < 1.0, "the hint fades out over its last second")
	hud.mode_entered_ms = Time.get_ticks_msec() - hud.CONTROLS_HINT_MS
	hud._process(0.0)
	_check(hud.regions.hints.text.is_empty(), "the hint leaves after its time")
	hud.set_mode("SPECTATING")
	hud.set_mode("PLAYING")
	hud._process(0.0)
	_check(hud.regions.hints.text.is_empty() and shown.size() == 1, "a later join keeps the status bar clear of developer hints")
	var seen := FragrSettings.new("user://test-hud-type-seen-%d.cfg" % OS.get_process_id())
	seen.set_value("gameplay", "controls_hint_seen", true)
	hud.controls_hint_pending = true
	hud.apply_preferences(seen)
	_check(not hud.controls_hint_pending, "a saved first run stays seen")
	hud.set_mode("SPECTATING")
	hud._process(0.0)
	_check(not hud.regions.hints.text.is_empty(), "a spectator still gets the short watch legend")
	hud.set_mode("PLAYING")
	hud._process(0.0)

	# Type: the death card, objective call and result card are pixel words.
	hud.set_fp_juice(true)
	hud.set_vitals(100, 0)
	hud.show_death_card(PackedStringArray(["FRAGGED BY Dead Air Dan", "WATCHING Dead Air Dan", "RESPAWN IN 3"]))
	hud.objective_call.push("COMPLIANCE-DRONE on deck.")
	hud.objective_call._process(0.0)
	hud.combat_feed.push("HOST: A corner line over light crates")
	hud.show_frag_event({"killer": "Scout Ant", "victim": "COMPLIANCE-DRONE", "weapon": "flechette"}, "a", "b")
	hud.frag_feed._process(0.0)
	await _settle()
	_audited.clear()
	_audit_type(hud, "death")
	for expected: String in ["Headline", "HealthValue", "ModeLabel"]:
		_check(_audited.has(expected), "the type audit reaches %s: %s" % [expected, str(_audited)])
	var headline: Label = hud.death_card._headline
	_check(headline.get_theme_font("font") == MenuTheme.FONT and headline.get_theme_font_size("font_size") in MenuTheme.PIXEL_SIZES, "the death headline is the pixel type at a pixel size")
	hud.hide_death_card()
	hud.show_round_end("Winner", "Frag limit", 10, "HOST: Round closed", [{"name": "Winner", "score": 10}])
	await _settle()
	_audit_type(hud, "result")
	_check(not hud.round_message.text.contains("FREQUENCY"), "the result card names the rules and venue, not the radio: " + hud.round_message.text)
	_check(hud.round_backdrop.visible and hud.round_backdrop.get_global_rect().encloses(HudRegions.text_bounds(hud.round_message)), "the result card is backed and its text stays on the plate")
	hud.show_round_end("Dead Air Dan", "Frag limit", 3, "HOST: Round closed", [{"name": "Dead Air Dan", "score": 3.0}, {"name": "Aunt Linda", "score": 1.0}])
	var podium: String = hud.round_message.text
	_check(podium.contains("#1" + hud.NBSP + "Dead" + hud.NBSP + "Air" + hud.NBSP + "Dan" + hud.NBSP + "3") and not podium.contains("3.0"), "a podium place is whole frags and never wraps inside a callsign: " + podium.c_escape())
	hud.round_banner_remaining = 0.01
	hud._process(0.1)

	# Corner voice lines carry their own plate.
	var voice: Label = hud.combat_feed.get_child(hud.combat_feed.get_child_count() - 1) as Label
	var plate: StyleBox = voice.get_theme_stylebox("normal")
	_check(plate is StyleBoxFlat and (plate as StyleBoxFlat).bg_color.a >= 0.75, "every corner voice line is backed")

	# Addressing: a taunt said to one fighter reaches only that fighter's view.
	var before: int = hud.combat_feed.get_child_count()
	game._on_event_received({"event": "speak", "player": "Scout Ant", "player_id": "ant", "text": "scout ant deleted you", "to_id": "someone-else"})
	_check(hud.combat_feed.get_child_count() == before, "a taunt to another fighter never reads as 'you' to this viewer")
	game._on_event_received({"event": "speak", "player": "Scout Ant", "player_id": "ant", "text": "scout ant deleted you", "to_id": "self"})
	_check(hud.combat_feed.get_child_count() == before + 1, "a taunt to the local fighter reaches them")
	game._on_event_received({"event": "speak", "player": "Scout Ant", "player_id": "ant", "text": "scout ant deleted you", "to_id": "watched"})
	_check(hud.combat_feed.get_child_count() == before + 2, "a taunt to the watched fighter reaches the eyes it is watched through")
	game._on_event_received({"event": "speak", "player": "Aunt Linda", "player_id": "linda", "text": "league says keep rolling"})
	_check(hud.combat_feed.get_child_count() == mini(before + 3, CombatFeed.LIMIT), "a room-wide line reaches everyone")
	hud.combat_feed.clear()
	hud.show_boss_down("", "Scout Ant")
	hud.show_boss_down("", "")
	var down: Array[String] = []
	for line: Node in hud.combat_feed.get_children():
		down.append((line as Label).text)
	_check(down == ["Scout Ant downs the drone.", "Drone down."], "the drone line is a sentence with or without a killer: " + str(down))

	# Kill feed: a roster name is shortened on purpose, never cut mid-letter.
	var font: Font = MenuTheme.FONT
	var short: String = FragFeed.abbreviate("COMPLIANCE-DRONE", font, MenuTheme.BODY, 200.0)
	_check(short == "C-DRONE", "a hyphenated callsign keeps its last word: " + short)
	_check(FragFeed.abbreviate("Dead Air Dan", font, MenuTheme.BODY, 160.0) == "D.A. DAN", "earlier words become initials")
	_check(FragFeed.abbreviate("Nightfall", font, MenuTheme.BODY, 400.0) == "Nightfall", "a name that fits is untouched")
	var feed: FragFeed = FragFeed.new()
	root.add_child(feed)
	feed.set_process(false)
	feed.set_region(Rect2(0, 0, 560, 216))
	for pair: Array in [["Scout Ant", "COMPLIANCE-DRONE"], ["Dead Air Dan", "Nightfall"], ["Tin Foil Tina", "Aunt Linda"], ["WWWWWWWWWWWWWWWW", "WWWWWWWWWWWWWWWW"]]:
		feed.push({"killer": pair[0], "victim": pair[1], "weapon": "rail"})
	feed._process(0.0)
	await _settle()
	for row: PanelContainer in feed._rows.values():
		for part: String in ["Content/Killer", "Content/Victim"]:
			var name_label: Label = row.get_node(part)
			var drawn: float = font.get_string_size(name_label.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuTheme.BODY).x
			_check(drawn <= name_label.size.x + 0.5 and not name_label.text.contains("…"), "a feed name fits its room without an ellipsis: " + name_label.text)
		_check(row.get_global_rect().end.x <= feed.get_global_rect().end.x + 0.5, "a feed row stays inside the column")
		# The drawn art, not just its box, keeps room on both sides.
		var art: TextureRect = row.get_node("Content/Weapon/Art")
		var killer_label: Label = row.get_node("Content/Killer")
		var victim_label: Label = row.get_node("Content/Victim")
		var art_rect: Rect2 = art.get_global_rect()
		var drawn_width: float = art_rect.size.y * float(art.texture.get_width()) / float(art.texture.get_height())
		var art_left: float = art_rect.position.x + maxf(0.0, (art_rect.size.x - drawn_width) * 0.5)
		var art_right: float = art_left + minf(art_rect.size.x, drawn_width)
		_check(art_left - killer_label.get_global_rect().end.x >= 16.0, "the weapon glyph has room after the killer")
		_check(victim_label.get_global_rect().position.x - art_right >= 24.0, "the weapon glyph has room before the victim mark and name")
	feed.queue_free()

	# The armor readout sits on the status bar plate.
	await _settle()
	var vitals: Control = hud.vitals
	var seal: Control = vitals.get_node("VitalsSealPlate")
	var plate_rect: Rect2 = seal.get_global_rect()
	var armor_box: Label = vitals.get_node("ArmorValue")
	_check(MenuTheme.DISPLAY_FONT.get_string_size("100", HORIZONTAL_ALIGNMENT_LEFT, -1, armor_box.get_theme_font_size("font_size")).x <= armor_box.size.x, "a full armor readout fits its box on the plate")
	for part: String in ["ArmorValue", "ArmorBar", "ArmorBarBack", "ArmorIcon", "HealthValue", "HealthIcon"]:
		var readout: Control = vitals.get_node(part)
		_check(plate_rect.encloses(readout.get_global_rect()), "%s sits on the status bar plate: %s in %s" % [part, readout.get_global_rect(), plate_rect])

	# The spectator's weapon tile keeps the same corner gutter as the vitals.
	var tile: Control = hud.get_node("WeaponIconBg")
	_check(-tile.offset_right >= vitals.offset_left and -tile.offset_bottom >= -vitals.offset_bottom, "the spectator weapon tile sits on the HUD gutter, not on the screen edge")

	# World text: nameplates and pickup tags use the pixel face.
	var pawn: Node = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	await process_frame
	var plate_label: Label3D = pawn.get_node("Label3D")
	_check(plate_label.font == MenuTheme.FONT and plate_label.uppercase, "a nameplate is pixel type in capitals")
	pawn.queue_free()
	var pickup: Node = load("res://scenes/weapon_pickup.tscn").instantiate()
	root.add_child(pickup)
	await process_frame
	_check((pickup.get_node("Label3D") as Label3D).font == MenuTheme.FONT, "a pickup tag is pixel type")
	pickup.queue_free()

	game.free()
	camera.free()
	watched.free()
	hud.queue_free()
	for path: String in [settings.storage_path, seen.storage_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await process_frame
	await process_frame
	if _failures == 0:
		print("test_hud_type: PASS pixel type, backed text, first-run hint, addressed taunts, feed names, armor plate and world text")
	quit(0 if _failures == 0 else 1)
