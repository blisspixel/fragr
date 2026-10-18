extends SceneTree

var failures: int = 0
var hud: CanvasLayer
var settings_path: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://status-bar-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_status_bar: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	if not OS.get_environment("FRAGR_STATUS_CAPTURE").is_empty():
		var background: ColorRect = ColorRect.new()
		background.color = MenuTheme.SURFACE
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(background)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	hud = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	hud.set_process(false)
	_test_scores()
	_test_map_handoffs()
	await _test_vitals_and_motion()
	await _test_regions()
	await _test_vehicle_regions()
	hud.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if failures == 0:
		print("test_status_bar: PASS accepted score lifetimes, health thresholds, motion cancellation and combined regions")
	quit(0 if failures == 0 else 1)

func _capture(name: String) -> void:
	var directory: String = OS.get_environment("FRAGR_STATUS_CAPTURE")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _settle()
	await RenderingServer.frame_post_draw
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "capture directory")
	_check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "save explicit HUD layout fixture")

func _test_scores() -> void:
	hud.set_match_rules(MatchRules.parse({"mode": "ffa"}))
	hud.set_round_info("Active", 65, 20)
	hud.set_score_subject("local")
	hud.sync_scores_from_players([{"id":"local", "name":"Twin", "score":7}, {"id":"other", "name":"Twin", "score":2}])
	_check(hud.mode_chip_label.text == "Twin: 7 // FIRST TO 20 // 1:05", "score uses selected ID even when names match")
	hud.show_frag("Twin", "Someone")
	_check(hud.score_subject.score == 7, "late frag notification does not double count accepted scoring")
	hud.sync_scores_from_players([{"id":"other", "name":"Twin", "score":2}])
	_check(hud.score_subject.score == 7 and hud.score_subject.known, "respawn/elimination absence retains the selected accepted score")
	hud.sync_scores_from_players([{"id":"local", "name":"Twin", "score":7}])
	hud.show_frag("Twin", "Teammate")
	_check(hud.score_subject.score == 7, "a team kill notice cannot award a point")
	hud.set_score_subject("other")
	_check(not hud.score_subject.known and not hud.mode_chip_label.text.contains("Twin"), "new absent subject cannot inherit another ID's score")
	hud.sync_scores_from_players([{"id":"other", "name":"Twin", "score":2}])
	_check(hud.score_subject.score == 2, "a followed subject uses its own accepted score")
	hud.set_score_subject("")
	_check(hud.mode_chip_label.text == "FIRST TO 20 // 1:05", "free camera shows target and clock without inventing a leader")
	hud.set_round_info("Active", null, 20)
	_check(hud.mode_chip_label.text == "FIRST TO 20", "untimed round never invents a zero countdown")
	hud.set_pressure("compliance_drone")
	_check(hud.mode_chip_label.text.ends_with("ARTICLE 7 ENFORCEMENT"), "arcade drone pressure remains visible after Host notices expire")
	hud.set_pressure("compliance")
	_check(hud.mode_chip_label.text.ends_with("APPROVED LANES ONLY"), "arcade Compliance state has a persistent read")
	hud.set_pressure("")
	hud.set_round_info("Ended", 5, 20)
	hud.show_round_end("Winner", "limit", 20)
	_check(hud.mode_chip_label.text == "MVP: Winner // 20 // 0:05", "Ended uses accepted result facts")
	hud.sync_scores_from_players([{"id":"local", "name":"Twin", "score":7}])
	hud.set_score_subject("local")
	_check(hud.mode_chip_label.text.contains("MVP: Winner"), "late roster cannot revive an active score over results")
	hud.set_round_info("Warmup", 3, 20)
	_check(not hud.score_subject.known and hud.result_subject.is_empty(), "next round clears retained score and result")
	hud.reset_host_chrome()
	_check(hud.score_subject.subject_id.is_empty(), "disconnect clears participant identity")
	hud.set_match_rules(MatchRules.parse({"mode":"ctf"}))
	hud.set_ctf_state([{"team":"union", "status":"home"}, {"team":"coalition", "status":"home"}], {"union":1, "coalition":3}, 3, [])
	hud.set_round_info("Ended", null, 0)
	hud.show_round_end("Winner", "capture limit", 9, "", [], "coalition", {"union":1,"coalition":3})
	hud._process(6.0)
	_check(not hud.round_message.visible and hud.mode_chip_label.text.contains("CAPTURES") and hud.mode_chip_label.text.contains("1 : 3") and not hud.mode_chip_label.text.contains("0:00"), "CTF final objective score survives card expiry and untimed Ended")
	hud.set_match_rules(MatchRules.parse({"mode":"tdm"}))
	hud.set_team_scores({"union":20, "coalition":17})
	hud.set_round_info("Ended", null, 20)
	hud.show_round_end("Winner", "frag limit", 9)
	hud._process(6.0)
	_check(hud.mode_chip_label.text.contains("UNION 20 : 17 FREE COALITION"), "TDM accepted final team scores remain after the card closes")
	hud.round_message.hide()

func _test_map_handoffs() -> void:
	var ctf: Dictionary = MatchRules.parse({"mode":"ctf", "lives":2})
	hud.set_match_rules(ctf)
	hud.set_round_info("Active", 65, 3)
	hud.set_ctf_state([{"team":"union", "status":"home"}, {"team":"coalition", "status":"home"}], {"union":1, "coalition":2}, 3, [])
	hud.set_own_lives(1)
	hud.set_pressure("compliance")
	hud.set_match_rules(ctf)
	_check(not hud.round_clock_known and hud.round_target == 0 and hud.flag_status_text.is_empty() and hud.team_score_text.is_empty() and hud.pressure_id.is_empty() and hud.own_lives == -1, "same-mode map handoff cannot borrow previous objective, clock, pressure or lives")
	var sabotage: Dictionary = MatchRules.parse({"mode":"sabotage"})
	hud.set_match_rules(sabotage)
	hud.set_sabotage_state({"round":1, "score":{"union":1,"coalition":2}, "phase":"live", "clock_ticks":100, "alive":{"union":3,"coalition":2}}, "union", 600, false, false)
	hud.set_match_rules(sabotage)
	_check(hud.sabotage_score.is_empty() and hud.sabotage_line.is_empty(), "same-mode handoff retires previous Sabotage facts")
	hud.set_episode_chrome("old", "Old episode", "Old objective", "2 / 3", "nods")
	hud.set_match_rules(MatchRules.parse({"mode":"ffa"}))
	_check(hud.episode_id.is_empty() and hud.episode_objective.is_empty() and hud.episode_progress.is_empty(), "map handoff retires Solo Broadcast objective and progress")
	hud.round_message.hide()

func _test_vitals_and_motion() -> void:
	hud.set_match_rules(MatchRules.parse({"mode":"ffa"}))
	hud.set_round_info("Active", null, 20)
	hud.set_mode("PLAYING")
	hud.set_fp_juice(true)
	var loadout: Dictionary = {"type":"loadout", "player_id":"self", "tick":20, "selected":"tack",
		"weapons":["fists","tack"], "ammo":[{"pool":"bullets","rounds":60}, {"pool":"shells","rounds":0}, {"pool":"cells","rounds":0}, {"pool":"rockets","rounds":0}],
		"loaded":[{"weapon":"tack","rounds":0}], "personal_claims":[], "dry_fire_count":0, "grenades":4, "proximity_mines":2, "remote_mines":3}
	_check(EquipmentState.validation_error(loadout, "self").is_empty(), "layout uses valid local inventory, not widened capacities")
	hud.equipment_hud.apply(loadout)
	hud.equipment_hud.show()
	for hp: int in [100, 51, 50, 26, 25, 10, 0]:
		hud.set_vitals(hp, 100)
		var tint: Color = MenuTheme.DANGER if hp <= 25 else (MenuTheme.EMBER if hp <= 50 else MenuTheme.BONE)
		_check(hud.health_value.text == str(hp) and hud.health_value.get_theme_color("font_color") == tint, "exact HP and threshold tint: %d" % hp)
		_check(is_equal_approx(hud.health_bar.size.x, float(hp) * 2.0) and hud.health_bar.color == tint, "health bar carries amount and state: %d" % hp)
		_check(hud._critical_pulse == null, "hydration never pulses")
		if hp in [100, 50, 25, 10]:
			await _capture("fixture-vitals-%d" % hp)
	hud.set_vitals(150, -5)
	_check(hud.health_value.text == "150" and hud.health_bar.size.x == 200.0, "overfull health retains exact number and clamps fill")
	_check(hud.armor_value.text == "0" and hud.armor_bar.size.x == 0 and hud.armor_value.modulate.a < 0.4, "zero armor is readable and quiet")
	_check(hud.health_value.get_theme_font_size("font_size") == hud.armor_value.get_theme_font_size("font_size") and hud.health_value.get_theme_font_size("font_size") == hud.equipment_hud.counts.get_theme_font_size("font_size"), "all three counters use the same numeral size")
	hud.set_vitals(25, 0)
	hud.show_critical_crossing(26, 25)
	_check(hud._critical_pulse != null, "fresh local crossing starts a pulse")
	var pulse: Tween = hud._critical_pulse
	hud.show_critical_crossing(25, 10)
	_check(hud._critical_pulse == pulse, "remaining below threshold never restarts the pulse")
	await process_frame
	var prefs: FragrSettings = FragrSettings.new(settings_path)
	prefs.set_value("accessibility", "reduced_motion", true)
	_check(prefs.save_to_disk() == OK, "reduced motion persists")
	var restored: FragrSettings = FragrSettings.new(settings_path)
	restored.load_from_disk()
	hud.apply_preferences(restored)
	_check(hud.reduced_motion and not hud.head_bob_enabled and restored.get_value("gameplay", "head_bob"), "effective override preserves saved bob choice")
	_check(hud._critical_pulse == null and hud.health_value.scale == Vector2.ONE, "preference cancels active pulse to rest")
	hud.show_critical_crossing(100, 10)
	_check(hud._critical_pulse == null, "reduced motion refuses new pulse")
	hud.set_fp_weapon("Tack")
	hud.show_fire_juice("Tack")
	hud._spawn_floating_damage(10, "Tack")
	_check(hud.fp_shot_age == 0.0 and hud.fp_kick_timer == 0.0, "reduced motion retains accepted fire frame without a latent kick")
	prefs.set_value("accessibility", "reduced_motion", false)
	hud.apply_preferences(prefs)
	hud._update_floating_damage(0.1)
	_check(hud.fp_kick_timer == 0.0 and hud.floating_damage_nodes[0].node.position.y == -20, "reenable cannot revive a cancelled shot kick or damage-number travel")
	hud.show_fire_juice("Tack")
	hud._spawn_floating_damage(10, "Tack")
	hud._update_floating_damage(0.1)
	_check(hud.fp_kick_timer > 0.0 and hud.floating_damage_nodes[1].node.position.y < -20, "fresh effects can animate after reenable")
	hud.show_critical_crossing(100, 10)
	hud.set_vitals(100, 0)
	_check(hud._critical_pulse == null, "healing cancels critical pulse")
	hud.show_critical_crossing(100, 10)
	hud.set_fp_juice(false)
	_check(hud._critical_pulse == null, "leaving cancels critical pulse")
	hud.show_nods_tick("1 / 3", "Host")
	_check(hud._round_pulse != null, "ordinary NODS card owns its pulse")
	hud._show_round_banner("New result", 5.0)
	_check(hud._round_pulse == null and hud.round_message.scale == Vector2.ONE, "replacement retires old pulse")
	hud._process(1.4)
	_check(hud.round_message.visible and hud.round_message.text == "New result", "old NODS lifetime cannot hide replacement")
	hud.round_message.hide()

func _settle() -> void:
	for index: int in range(4):
		hud.regions.layout()
		await process_frame

func _test_regions() -> void:
	hud.set_mode("SPECTATING")
	hud.set_fp_juice(true)
	hud.set_match_rules(MatchRules.parse({"mode":"ctf", "mutators":["rail-only", "two-lives"], "lives":2, "friendly_fire":true}))
	hud.set_round_info("Active", 65, 20)
	hud.set_own_lives(1)
	hud.set_ctf_state([
		{"team":"union", "status":"carried", "carrier":"p"},
		{"team":"coalition", "status":"dropped", "return_ticks":39, "position":[10,0,-10]}
	], {"union":1, "coalition":2}, 3, [{"id":"p", "name":"Long Unicode 名字 carrier", "x":0, "y":0, "z":0}], "p")
	hud.set_followed_weapon("Rail", "Long Unicode 名字 carrier", "Defensive", "union")
	hud.show_radio("Contested Frequency", "The Sky Is Wrong Again")
	hud.show_station_card({"name":"Contested Frequency", "tagline":"Signals outlive the booth."})
	for i: int in range(3):
		hud.combat_feed.push("Accepted notice %d with a longer participant name" % i)
	await _settle()
	var center: Rect2 = hud.mode_chip_label.get_global_rect()
	_check(hud.radio_label.get_global_rect().end.y <= root.get_visible_rect().size.y - 248, "radio toast reserves ammunition and all explosive counters")
	_check(hud.radio_card.get_global_rect().end.y + 12 <= hud.radio_label.position.y, "station card clears the toast")
	_check(not center.intersects(hud.get_node("Panel").get_global_rect()) and not center.intersects(hud.combat_feed.get_global_rect()), "populated center stays separate from corner and feed")
	_check(hud.mode_label.get_line_count() <= 1 and hud.round_label.get_line_count() <= 1, "top left contains two short lines")
	_check(not hud.scoreboard.visible and not hud.weapon_icon.visible, "full standings stay on Tab and first-person weapon card remains hidden")
	await _capture("fixture-ctf-radio")
	hud.set_fp_juice(false)
	hud.set_followed_weapon("Rail", "Long Unicode 名字 carrier", "Defensive", "union")
	_check(hud.weapon_icon.visible and hud.weapon_icon_bg.visible, "chase view shows a card with a known weapon")
	hud.set_followed_weapon("unknown", "Long Unicode 名字 carrier")
	_check(not hud.weapon_icon.visible and not hud.weapon_icon_bg.visible, "unknown weapon cannot leave an empty frame")
	hud.set_followed_weapon("", "")
	await _settle()
	_check(not hud.weapon_label.visible, "free view retires followed identity")
	hud.set_fp_juice(true)
	hud.set_campaign(true)
	await _settle()
	_check(not hud.mode_chip_label.visible, "campaign suppresses match facts")
	_check(hud.mode_label.text == "CAMPAIGN", "campaign context cannot show a stale previous match mode")
	_check(hud.combat_feed.get_global_rect().end.y + 8 <= hud.regions.context.position.y, "campaign notices clear context stack")
	_check(hud.regions.context.get_global_rect().end.y <= hud.vitals.position.y - 16, "context clears reserved vitals")
	await _capture("fixture-campaign-feed")
	hud.mode_entered_ms = Time.get_ticks_msec() - hud.CONTROLS_HINT_MS
	hud._process(0.0)
	_check(hud.regions.hints.text.is_empty(), "hint expires without another snapshot")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "test", "letters")
	hud._process(0.0)
	_check(hud.regions.hints.text.is_empty(), "device switch never renews expired hint")
	InputDevice.reset()
	hud.set_campaign(false)
	hud.set_match_rules(MatchRules.parse({"mode":"conquest"}))
	hud.set_round_info("Active", 65, 0)
	var conquest: ConquestHud = ConquestHud.new()
	hud.add_child(conquest)
	hud.regions.conquest = conquest
	var conquest_state: Dictionary = load("res://scripts/test_conquest_state.gd").snapshot()
	for index: int in range(5):
		conquest_state.conquest.points[index].owner = "union"
		conquest_state.conquest.points[index].capturing = "coalition"
		conquest_state.conquest.points[index].progress = 80
	conquest.apply(conquest_state)
	await _settle()
	for site: Label in conquest._sites:
		_check(site.get_theme_font("font").get_string_size(site.text.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, site.get_theme_font_size("font_size")).x <= site.size.x, "site name fits its actual cell")
		_check(not site.get_global_rect().intersects(hud.combat_feed.get_global_rect()), "site text stays outside populated feed")
	_check(conquest._sites[3].position.y > conquest._sites[0].position.y and conquest._sites[4].position.y == conquest._sites[3].position.y, "five sites reflow in an ordered three plus two")
	await _capture("fixture-conquest-feed")
	hud._show_round_banner("Result card", 1.0, true)
	await _settle()
	_check(not hud.mode_chip_label.visible and not conquest.visible, "result card has priority over centered match facts and Conquest sites")
	conquest_state.conquest.tickets.union = 123
	conquest_state.conquest.points[0].owner = "coalition"
	conquest.apply(conquest_state)
	_check(not conquest.visible, "new accepted Conquest facts cannot cover an active card")
	hud._process(1.1)
	await _settle()
	_check(hud.mode_chip_label.visible and conquest.visible, "card expiry restores retained clock and Conquest facts")
	_check(conquest._tickets.text.contains("123") and conquest.state.points[0].owner == "coalition", "restored Conquest region contains facts accepted while covered")
	conquest.apply({})
	hud.set_match_rules(MatchRules.parse({"mode":"sabotage"}))
	hud.set_sabotage_state({"round":1, "score":{"union":1,"coalition":2}, "phase":"live", "clock_ticks":100, "alive":{"union":3,"coalition":2}}, "union", 600, false, false)
	hud.broadcast_chrome = true
	hud.set_map_name("Larak Lot")
	hud.set_mode("SPECTATING")
	hud.set_round_info("Active", 5, 0)
	await _settle()
	var bottom: float = hud.contested_frequency_badge.get_global_rect().end.y
	_check(hud.sabotage_hud.header_origin >= bottom + 16 and hud.mode_chip_label.position.y >= bottom + 76, "fallback badge reserves its whole band for pips and center text")
	_check(hud.combat_feed.position.y >= bottom + 16, "fallback band also clears notices")
	await _capture("fixture-broadcast-sabotage")
	hud._show_round_banner("Result card", 1.0, true)
	await _settle()
	_check(not hud.mode_chip_label.visible and not hud.sabotage_hud.visible, "result card has priority over Sabotage text and pips")
	hud._process(1.1)
	await _settle()
	_check(hud.mode_chip_label.visible and hud.sabotage_hud.visible, "Sabotage facts return after card expiry")
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("gameplay", "debug_telemetry", true)
	hud.apply_preferences(preferences)
	await _settle()
	_check(hud.sabotage_hud.header_origin == 16, "preference alone hides decoration and returns header space without a snapshot")
	_check(hud.status_label.visible and hud.status_label.get_parent() == hud.regions.context, "enabled telemetry has its own region outside the clipped corner")
	_check(hud.get_node("Panel").get_global_rect().encloses(hud.round_label.get_global_rect()), "mode and round remain inside corner with telemetry enabled")
	preferences.set_value("gameplay", "broadcast_chrome", true)
	hud.apply_preferences(preferences)
	await _settle()
	_check(hud.sabotage_hud.header_origin >= bottom + 16, "preference alone shows fallback decoration and reserves its band")
	hud.set_match_rules({})
	_check(not hud.mode_chip_label.visible and hud.sabotage_score.is_empty() and hud.sabotage_line.is_empty(), "absent rules clear all retained match facts")

func _test_vehicle_regions() -> void:
	var vehicle: VehicleHud = VehicleHud.new()
	hud.add_child(vehicle)
	hud.regions.vehicle = vehicle
	vehicle.geometry_changed.connect(hud.regions.layout)
	vehicle.visibility_changed.connect(hud.regions.layout)
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	hud.apply_preferences(preferences)
	hud.set_mode("PLAYING")
	for scenario: String in ["nearby", "hot_gunner", "aircraft"]:
		var snapshot: Dictionary = load("res://scripts/test_vehicle_state.gd")._snapshot()
		var own: String = str(snapshot.players[0].id)
		if scenario == "hot_gunner":
			snapshot.tick = 101
			snapshot.vehicles[0].gunner = own
			snapshot.vehicles[0].gun_heat = 0.98
			snapshot.vehicles[0].control_ready_tick = 110
		elif scenario == "aircraft":
			snapshot.tick = 102
			snapshot.vehicles[0].kind = "light_aircraft"
			snapshot.vehicles[0].driver = own
			snapshot.vehicles[0].speed = 32.0
		_check(VehicleState.validation_error(snapshot).is_empty(), "vehicle layout uses valid facts: " + scenario)
		vehicle.apply(snapshot, own, true)
		hud.set_vehicle_seat(vehicle.seat)
		if vehicle.seat.is_empty():
			hud.equipment_hud.show()
		hud.show_radio("Contested Frequency", "The Sky Is Wrong Again")
		hud.show_station_card({"name":"Contested Frequency", "tagline":"Signals outlive the booth."})
		await _settle()
		var rect: Rect2 = vehicle.occupied_region()
		_check(rect.has_area() and hud.radio_label.get_global_rect().end.y + 16 <= rect.position.y, "radio clears measured vehicle content: " + scenario)
		if vehicle.seat.is_empty():
			_check(rect.end.y + 16 <= root.get_visible_rect().size.y - 232, "nearby entry clears the full explosive stock above ammunition")
		_check(not hud.radio_card.get_global_rect().intersects(hud.combat_feed.get_global_rect()), "vehicle reservation leaves station card clear of notice feed: " + scenario)
		await _capture("fixture-vehicle-" + scenario)
	vehicle.apply({}, "", false)
	await _settle()
	_check(hud.radio_label.position.y == root.get_visible_rect().size.y - 348, "leaving a vehicle restores equipment reservation")
