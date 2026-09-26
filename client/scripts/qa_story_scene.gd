extends SceneTree

## Renders one story scene shot for visual review: a still, a speaker caption and
## the progress row. Needs a rendering display, not --headless.
##   godot --path client --resolution 1280x720 --script res://scripts/qa_story_scene.gd -- --out PATH.png
## The still is the committed coalition banner standing in for unmade scene art.

const STILL: String = "res://assets/factions/free_coalition/dont_tread_on_me.png"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = arguments.find("--out")
	if index < 0 or index + 1 >= arguments.size():
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
	var player: ScenePlayer = ScenePlayer.new(manifest)
	root.add_child(player)
	await process_frame
	player.advance()
	for frame: int in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(arguments[index + 1])
	print("qa_story_scene: saved %s (%dx%d, %s)" % [arguments[index + 1], image.get_width(), image.get_height(), error_string(result)])
	player.free()
	quit(0 if result == OK else 1)
