extends SceneTree

## The wipe's other ending, as review stills on any desktop: each page of the
## exhaustion scene, then the coda's fragment on black, the anomaly and the
## credits, rendered into a fixed 1280x720 viewport. Presentation only; the
## trigger itself is covered by the presentation harness. Development
## inspection only, never an acceptance. Stills land in FRAGR_QA_DIR.
const SIZE: Vector2i = Vector2i(1280, 720)
var _viewport: SubViewport
var _out_dir: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	_out_dir = OS.get_environment("FRAGR_QA_DIR")
	if _out_dir.is_empty():
		push_error("wipe_failure_review: FRAGR_QA_DIR is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	set_meta("fragr_settings_path", _out_dir.path_join("settings.cfg"))
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var page: ScenePlayer = ScenePlayer.new(StoryScene.load_scene(StoryScene.WIPE_FAILURE))
	_viewport.add_child(page)
	await create_timer(0.8).timeout
	var count: int = page.shots().size()
	for index: int in range(count):
		await _save("%02d_page_%s" % [index, str(page.shot()["id"]).to_lower()])
		if index < count - 1:
			page.advance()
			await create_timer(0.6).timeout
	page.finish()
	page.queue_free()
	var coda: StillHereCoda = StillHereCoda.new()
	coda.ending = StillHereCoda.EXHAUSTION
	_viewport.add_child(coda)
	await create_timer(StillHereCoda.EXHAUSTION_FRAGMENT_AT + 1.6).timeout
	await _save("03_fragment_on_black")
	await create_timer(StillHereCoda.EXHAUSTION_SPACE_AT - StillHereCoda.EXHAUSTION_FRAGMENT_AT - 1.6 + 3.8).timeout
	await _save("04_anomaly")
	await create_timer(StillHereCoda.EXHAUSTION_SPACE_END - StillHereCoda.EXHAUSTION_SPACE_AT - 3.8 + 1.2).timeout
	await _save("05_credits_people")
	coda.queue_free()
	await process_frame
	quit(0)

func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var path: String = _out_dir.path_join(name + ".png")
	image.save_png(path)
	print("wipe_failure_review: saved ", path)
