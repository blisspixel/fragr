extends SceneTree

## Conquest bleed review: the real gameplay HUD with its Conquest panel, fed
## controlled ticket counts (both sides full, one side under the bleed line
## at the pulse's cool and hot ends, and the last tickets). A presentation
## fixture: no server, no outcome authority; the siren and heartbeat
## counters are printed, not heard.
##
## Usage: godot --path client --script res://qa/conquest_bleed_review.gd -- /abs/out
const MOMENTS: Array[Dictionary] = [
	{"label": "full", "union": 200, "coalition": 186, "seconds": 0.0},
	{"label": "bleed_cool", "union": 24, "coalition": 151, "seconds": 0.02},
	{"label": "bleed_hot", "union": 24, "coalition": 151, "seconds": 0.5},
	{"label": "last_tickets", "union": 7, "coalition": 133, "seconds": 0.0},
]

var _out: String = ""
var _failures: PackedStringArray = []


func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	call_deferred("_run")


static func _snapshot(union: int, coalition: int) -> Dictionary:
	var points: Array = []
	var positions: Array = [[-105, 3, 65], [-100, 3, -35], [0, 3, -70], [100, 3, -35], [105, 3, 65]]
	var owners: Array = ["union", "union", null, "coalition", "coalition"]
	for index: int in range(5):
		points.append({"id": ConquestState.SITES[index], "position": positions[index], "radius": 8.0,
			"owner": owners[index], "capturing": null, "progress": 0, "contested": false})
	return {"conquest": {"tickets": {"union": union, "coalition": coalition},
		"initial_tickets": 200, "capture_ticks": 160, "points": points}}


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("conquest_bleed_review: give an output directory")
		quit(1)
		return
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("39424a")
	backdrop.size = Vector2(1920, 1080)
	root.add_child(backdrop)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	root.add_child(hud)
	game.free()
	# The fixture is a Conquest room on Holdfast Atoll, live: the HUD gets the
	# same rules, venue and round facts a real snapshot would give it.
	hud.set_match_rules(MatchRules.parse({"mode": "conquest", "name": "Conquest"}))
	hud.set_map_name("Holdfast Atoll")
	hud.set_round_info("Active", 600, 0)
	hud.set_mode("SPECTATING")
	var panel: ConquestHud = ConquestHud.new()
	hud.add_child(panel)
	hud.regions.conquest = panel
	await process_frame
	for moment: Dictionary in MOMENTS:
		panel.apply(_snapshot(int(moment["union"]), int(moment["coalition"])))
		if hud.has_method("set_team_scores"):
			hud.set_team_scores(_snapshot(int(moment["union"]), int(moment["coalition"]))["conquest"]["tickets"])
		panel.set_process(false)
		panel._process(float(moment["seconds"]))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = _out.path_join("conquest_%s.png" % moment["label"])
		if image == null or image.is_empty() or image.save_png(path) != OK:
			_failures.append("could not save " + path)
		print("conquest_bleed_review: %s bleeding=%s last=%s sirens=%d beats=%d -> %s" % [moment["label"], panel.bleeding, panel.last_tickets, panel.siren_count, panel.heartbeat_count, path])
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
