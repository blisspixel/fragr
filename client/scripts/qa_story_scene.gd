extends SceneTree

## Renders one story scene shot for visual review: a still, a speaker caption and
## the progress row. Needs a rendering display, not --headless.
##   godot --path client --resolution 1280x720 --script res://scripts/qa_story_scene.gd -- --out PATH.png
##   ... -- --scene opening --shot 5 --out PATH.png
## Without --scene, the committed coalition banner stands in for unmade scene art.
## With --scene, the committed manifest plays from its first shot to the
## numbered one (1-based), so the capture shows exactly what a player sees.

const STILL: String = "res://assets/factions/free_coalition/dont_tread_on_me.png"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _argument(arguments: PackedStringArray, flag: String) -> String:
	var index: int = arguments.find(flag)
	return arguments[index + 1] if index >= 0 and index + 1 < arguments.size() else ""

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = _argument(arguments, "--out")
	if out.is_empty():
		printerr("qa_story_scene: pass -- --out PATH.png")
		quit(2)
		return
	var manifest: Dictionary = {
		"format": 1.0, "id": "qa_capture", "title_key": "STORY_L02_TITLE", "skip_key": "STORY_SKIP_SCENE",
		"shots": [
			{"id": "LEDGER", "caption_key": "STORY_L01_L02_LEDGER", "image": STILL, "motion": {"kind": "none"}},
			{"id": "SHIFT", "speaker_key": "STORY_SPEAKER_MARA", "caption_key": "STORY_L01_L02_SHIFT", "image": STILL, "motion": {"kind": "none"}},
			{"id": "WARD", "caption_key": "STORY_L01_L02_WARD"},
		],
	}
	var target: int = 2
	var scene_id: String = _argument(arguments, "--scene")
	if not scene_id.is_empty():
		manifest = StoryScene.load_scene(scene_id)
		target = _argument(arguments, "--shot").to_int() if arguments.has("--shot") else 1
		if manifest.is_empty() or target < 1 or target > (manifest["shots"] as Array).size():
			printerr("qa_story_scene: unknown scene or shot out of range")
			quit(2)
			return
	var player: ScenePlayer = ScenePlayer.new(manifest)
	root.add_child(player)
	await process_frame
	for step: int in target - 1:
		player.advance()
	for frame: int in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(out)
	print("qa_story_scene: saved %s (%dx%d, %s)" % [out, image.get_width(), image.get_height(), error_string(result)])
	player.free()
	quit(0 if result == OK else 1)
