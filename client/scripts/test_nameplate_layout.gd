extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var layout: GDScript = load("res://scripts/nameplate_layout.gd") as GDScript
	if layout == null:
		push_error("test_nameplate_layout: layout script missing")
		quit(1)
		return
	var entries: Array[Dictionary] = [
		{"id": "other", "rect": Rect2(100, 100, 120, 22), "priority": 2, "distance": 8.0},
		{"id": "carrier", "rect": Rect2(170, 101, 130, 22), "priority": 0, "distance": 20.0},
		{"id": "clear", "rect": Rect2(400, 100, 120, 22), "priority": 2, "distance": 12.0},
	]
	var visible: Array[String] = layout.choose(entries)
	if visible != ["carrier", "clear"]:
		push_error("test_nameplate_layout: overlapping pawn hid the carrier or an independent label")
		quit(1)
		return
	var peers: Array[Dictionary] = [
		{"id": "far", "rect": Rect2(0, 0, 100, 20), "priority": 2, "distance": 30.0},
		{"id": "near", "rect": Rect2(5, 0, 100, 20), "priority": 2, "distance": 10.0},
	]
	if layout.choose(peers) != ["near"]:
		push_error("test_nameplate_layout: nearby fighter should win an equal-priority overlap")
		quit(1)
		return
	peers[0]["distance"] = 10.0
	if layout.choose(peers) != ["far"]:
		push_error("test_nameplate_layout: equal-priority ties should be stable by id")
		quit(1)
		return
	peers[0]["distance"] = 10.004
	if layout.choose(peers) != ["far"]:
		push_error("test_nameplate_layout: sub-centimeter ties should be stable by id")
		quit(1)
		return
	var flag_block: Array[Rect2] = [Rect2(150, 90, 160, 40)]
	var plates: Array[Dictionary] = [
		{"id": "carrier", "rect": Rect2(170, 100, 130, 22), "priority": 0, "distance": 6.0},
		{"id": "wing", "rect": Rect2(400, 100, 80, 22), "priority": 2, "distance": 9.0},
	]
	if layout.choose(plates, flag_block) != ["wing"]:
		push_error("test_nameplate_layout: a flag rect should hide the plate that covers it")
		quit(1)
		return
	print("test_nameplate_layout: PASS carrier priority, clear labels, stable ties, flag yield")
	quit(0)
