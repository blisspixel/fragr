extends SceneTree

class MatchHost extends Node:
	var local_match: Variant = null

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_end_of_run_copy: " + message)

func _departed_state() -> Dictionary:
	return {
		"rules": {"difficulty": "standard", "revision": 1},
		"phase": "departed",
		"party": [],
		"prompts": [],
		"run": {
			"id": "00000000-0000-0000-0000-000000000002",
			"status": "complete",
			"continues": 3,
		},
	}

func _open_menu(host: Node) -> PauseMenu:
	var menu: PauseMenu = PauseMenu.new()
	host.add_child(menu)
	menu.open()
	return menu

func _run() -> void:
	var departed: String = tr("MISSION_DEPARTED")
	_check("correction ward" in departed, "departure catalog keeps the correction ward")
	_check("TRANSFER ROUTE SECURED" in departed, "departure catalog keeps the secured route")
	_check("Prototype" not in departed and "prototype" not in departed, "departure catalog does not call the prototype complete")
	_check("development" not in departed.to_lower(), "departure catalog does not say the mission is still in development")

	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.apply(_departed_state(), "")
	await process_frame
	_check("correction ward" in hud._copy.text, "departure card keeps the correction-ward result")
	_check("Prototype" not in hud._copy.text and "development" not in hud._copy.text.to_lower(), "departure card drops the prototype disclaimer")
	hud.free()

	var manager: Node = load("res://scripts/game_manager.gd").new()
	_check(manager.get("local_match") == null, "a match is not a local campaign until that process exists")
	manager.free()

	var arena: MatchHost = MatchHost.new()
	root.add_child(arena)
	var arena_menu: PauseMenu = _open_menu(arena)
	await process_frame
	_check(arena_menu._note.text == tr("MENU_LIVE_MATCH"), "arena note stays the live match line")
	_check("abandons" not in arena_menu._note.text.to_lower(), "arena note does not mention abandoning a run")
	_check("continues" not in arena_menu._note.text.to_lower(), "arena note does not mention continues")
	arena_menu.free()
	arena.free()

	var joined: MatchHost = MatchHost.new()
	joined.local_match = null
	root.add_child(joined)
	var joined_menu: PauseMenu = _open_menu(joined)
	await process_frame
	_check(joined_menu._note.text == tr("MENU_LIVE_MATCH"), "a joined match keeps the live match line")
	_check("abandons" not in joined_menu._note.text.to_lower(), "a joined match does not warn that leaving abandons a run")
	joined_menu.free()
	joined.free()

	var campaign: MatchHost = MatchHost.new()
	var owned: Node = Node.new()
	campaign.local_match = owned
	root.add_child(campaign)
	var campaign_menu: PauseMenu = _open_menu(campaign)
	await process_frame
	var warning: String = tr("MENU_EXIT_SAVES_RUN")
	_check(campaign_menu._note.text == warning, "local campaign note says exit preserves the run")
	_check("pending continue" in campaign_menu._note.text, "local campaign note preserves a pending continue")
	_check("LIVE MATCH" not in campaign_menu._note.text, "local campaign note is not the arena sentence")

	var translated: Translation = Translation.new()
	translated.locale = "de"
	translated.add_message("MENU_EXIT_SAVES_RUN", "Verlassen speichert diesen Lauf.")
	translated.add_message("MISSION_DEPARTED", "ZIEL: Korrekturstation")
	TranslationServer.add_translation(translated)
	TranslationServer.set_locale("de")
	await process_frame
	_check(campaign_menu._note.text == "Verlassen speichert diesen Lauf.", "campaign note follows the catalog")
	_check(tr("MISSION_DEPARTED") == "ZIEL: Korrekturstation", "departure follows the catalog")
	TranslationServer.set_locale("en")
	TranslationServer.remove_translation(translated)
	await process_frame
	_check(campaign_menu._note.text == tr("MENU_EXIT_SAVES_RUN"), "campaign note returns to English")
	_check("correction ward" in tr("MISSION_DEPARTED"), "departure returns to the correction ward")

	campaign_menu.free()
	owned.free()
	campaign.free()
	await process_frame
	if _failures == 0:
		print("test_end_of_run_copy: PASS")
	quit(0 if _failures == 0 else 1)
