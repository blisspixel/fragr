extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_records_path", "")
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_low_water_sabotage: " + reason)

func _run() -> void:
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	var layout: Dictionary = {"attackers": "coalition", "sites": [
		{"id": "a", "center": [-22, 3, 18], "radius": 3},
		{"id": "b", "center": [22, 3, 18], "radius": 3}],
		"callouts": [{"id": "clinic_steps", "min": [-27, 13], "max": [-17, 23]},
			{"id": "tram_stop", "min": [17, 13], "max": [27, 23]}]}
	_check(SabotageState.map_error({"sabotage": layout}).is_empty(), "two original raised-street sites pass the existing wire boundary")
	_check(SabotageState.site_name("a", layout) == "A CLINIC STEPS" and SabotageState.site_name("b", layout) == "B TRAM STOP",
		"the current site's callout supplies its proper venue words")
	_check(SabotageState.site_name("a") == "A FRAME" and SabotageState.site_name("b") == "B SERVER", "Sector 9 default words remain exact")
	var planted: Dictionary = {"kind": "planted", "site": "a", "player": "Town walker"}
	_check(SabotageState.event_line(planted, "coalition", layout).contains("A CLINIC STEPS"), "actual event uses the current static layout")
	_check(SabotageState.event_line(planted, "coalition").contains("A FRAME"), "default event preserves Sector 9")
	_check(ArenaCover.venue_for({"map_id": 8, "map_name": "Low Water"}) == "low_water", "explicit map name chooses civilian surfaces")
	_check(ArenaCover.venue_for({"map_id": 8, "map_name": "Unknown"}).is_empty(), "numeric id alone cannot invent a venue")
	_check(ArenaSky.preset_for("Low Water").sky_top == ArenaSky.low_water().sky_top, "the registered venue uses its warm town sky")
	var world: ArenaSabotage = ArenaSabotage.new()
	root.add_child(world)
	world.set_layout(layout)
	for site_id: String in ["a", "b"]:
		var site: Node3D = world.get_node("Site" + site_id.to_upper())
		_check(site.position.y == 3.0, "site feet retain authoritative raised street")
		_check((site.get_node("SiteName") as Label3D).text == SabotageState.site_name(site_id, layout), "readable site plate uses the proper local identity")
		var local_prop: Texture2D = (site.get_node("Prop") as Sprite3D).texture
		_check(local_prop != SabotageArt.site_prop(site_id), "town service controls do not pretend to be custody props")
		_check(local_prop == SabotageArt.site_prop(site_id, "clinic_steps" if site_id == "a" else "tram_stop"), "registered prop is cached")
		_check(site.find_children("*", "CollisionObject3D", true, false).is_empty(), "site presentation never adds collision")
	world.set_layout({})
	_check(world._sites.is_empty(), "changing maps retires both local site presenters")
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	menu.set("_settings", FragrSettings.new("user://test-low-water-%d.cfg" % OS.get_process_id()))
	root.add_child(menu)
	await process_frame
	menu._host_settings["mode"] = "sabotage"
	menu._host_settings["map_id"] = 8
	await menu._show("host")
	var picker: OptionButton = menu.get("_host_map")
	_check(picker.item_count == 2 and picker.get_item_id(0) == 4 and picker.get_item_id(1) == 8 and picker.get_selected_id() == 8,
		"actual Sabotage host picker preserves Sector 9 and selects Low Water")
	var requested: Dictionary = {"mode": "sabotage", "map_id": 8, "bots": 10, "bot_policy": "fixed", "fill_target": 0, "lan": false, "port": 0}
	_check(LocalHost.valid_settings(requested) and LocalHost.arguments_for(requested).has("--sabotage-five-v-five"), "town host uses the same bounded finite ten-seat profile")
	var invalid: Dictionary = requested.duplicate()
	invalid["mode"] = "tdm"
	_check(not LocalHost.valid_settings(invalid), "unadvertised town desktop modes stay refused")
	invalid = requested.duplicate()
	invalid["bots"] = 11
	_check(not LocalHost.valid_settings(invalid), "town cannot expand the ten-fighter host bound")
	menu.queue_free()
	world.queue_free()
	await process_frame
	_check(await retirement.drain(), "map and menu retirement completes")
	if _failures == 0:
		print("test_low_water_sabotage: PASS host picker, finite profile, site words, original props, venue and retirement")
	quit(0 if _failures == 0 else 1)
