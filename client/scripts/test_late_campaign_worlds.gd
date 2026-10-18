extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/late_campaign_worlds.json"))
	var failures: int = 0
	if not fixtures is Array or fixtures.size() != 12:
		push_error("test_late_campaign_worlds: missing native prepared worlds")
		quit(1)
		return
	for info: Dictionary in fixtures:
		var error: String = MissionState.map_error(info)
		if not error.is_empty():
			push_error("test_late_campaign_worlds: %s: %s" % [info.get("map_name", "unknown"), error])
			failures += 1
	var routes: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/late_campaign_routes.json"))
	if not routes is Array or routes.is_empty():
		push_error("test_late_campaign_worlds: missing native route facts")
		quit(1)
		return
	var previous: Dictionary = {}
	var hud := MissionHud.new()
	root.add_child(hud)
	await process_frame
	for message: Dictionary in routes:
		var info: Dictionary = fixtures[int(message["map_index"])]
		var geometry: Dictionary = MissionState.geometry_for(info)
		var key: String = "m%d" % (16 + int(message["map_index"]) / 3)
		var old: Dictionary = previous.get(key, {})
		if not MissionState.validation_error(message, geometry, old).is_empty():
			push_error("test_late_campaign_worlds: native route rejected %s tick %d" % [key, message["tick"]])
			failures += 1
		hud.apply(message["state"], str(message["state"]["party"][0]["id"]))
		if message["state"]["phase"] == "in_progress" and message["state"]["prompts"].is_empty() and not hud._stage_card_visible():
			push_error("test_late_campaign_worlds: active objective card omitted")
			failures += 1
		var current: Dictionary = message["state"][key].get("current", {})
		if message["state"]["phase"] == "in_progress" and current.get("action", {}).get("kind") == "use" and MissionHud.approach_points(message["state"], geometry).is_empty():
			push_error("test_late_campaign_worlds: live use approach omitted")
			failures += 1
		var forged: Dictionary = message.duplicate(true)
		forged["state"][key]["completed"].append("forged")
		if MissionState.validation_error(forged, geometry).is_empty():
			push_error("test_late_campaign_worlds: forged progression accepted")
			failures += 1
		if message["state"][key].has("current"):
			forged = message.duplicate(true)
			forged["state"][key].erase("current")
			if MissionState.validation_error(forged, geometry).is_empty():
				push_error("test_late_campaign_worlds: missing objective accepted")
				failures += 1
		if not message["state"]["prompts"].is_empty():
			forged = message.duplicate(true)
			forged["state"]["prompts"][0]["kind"] = "transfer_record"
			if MissionState.validation_error(forged, geometry).is_empty():
				push_error("test_late_campaign_worlds: forged prompt accepted")
				failures += 1
		previous[key] = message
	# The native stadium lifecycle records structural transitions, not a played clear.
	var stadium: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m15_lifecycle.json"))
	if not stadium is Array or stadium.size() != 8:
		push_error("test_late_campaign_worlds: missing native stadium lifecycle")
		quit(1)
		return
	var last_stadium: Dictionary = {}
	for receipt: Dictionary in stadium:
		var info: Dictionary = receipt["map"]
		var message: Dictionary = receipt["mission"]
		var geometry: Dictionary = MissionState.geometry_for(info)
		if not MissionState.map_error(info).is_empty() or not MissionState.validation_error(message, geometry, last_stadium).is_empty() or not ActorState.validation_error(receipt["snapshot"]).is_empty():
			push_error("test_late_campaign_worlds: native stadium lifecycle rejected at tick %d" % message["tick"])
			failures += 1
		for flag: String in ["tunnel_closed", "gates_open"]:
			var stale: Dictionary = geometry.duplicate(true)
			stale["m15"][flag] = not stale["m15"][flag]
			if MissionState.validation_error(message, stale).is_empty():
				push_error("test_late_campaign_worlds: stadium facts accepted against stale world")
				failures += 1
		last_stadium = message
	for index: int in [3, 6]:
		var net: Node = load("res://scripts/net_client.gd").new()
		root.add_child(net)
		var errors: Array[String] = []
		net.server_error.connect(func(error: String) -> void: errors.append(error))
		var first: Dictionary = fixtures[index].duplicate(true)
		net._handle_message(JSON.stringify(first))
		var changed: Dictionary = first.duplicate(true)
		var key: String = "m17" if index == 3 else "m18"
		var objective_index: int = 0 if index == 3 else 1
		changed[key]["objectives"][objective_index]["action"]["feet"][0] += 0.1
		if not MissionState.map_error(changed).is_empty():
			push_error("test_late_campaign_worlds: changed-contract fixture must independently validate")
			failures += 1
		net._handle_message(JSON.stringify(changed))
		if errors != [MissionState.INVALID]:
			push_error("test_late_campaign_worlds: changed static contract accepted live")
			failures += 1
		net.free()
	hud.queue_free()
	await process_frame
	if failures == 0:
		print("test_late_campaign_worlds: PASS all twelve native prepared worlds")
	quit(0 if failures == 0 else 1)
