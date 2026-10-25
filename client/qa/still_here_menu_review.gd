extends SceneTree

## Single Player with a saved survival, as review stills on any desktop: the
## menu's Walk Still Here entry and the practice list's development walk,
## rendered into a fixed 1280x720 viewport. FRAGR_RUN_DIR names the run
## directory the menu previews; stills land in FRAGR_QA_DIR. Development
## inspection only, never an acceptance.
const SIZE: Vector2i = Vector2i(1280, 720)
var _viewport: SubViewport
var _out_dir: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	_out_dir = OS.get_environment("FRAGR_QA_DIR")
	if _out_dir.is_empty():
		push_error("still_here_menu_review: FRAGR_QA_DIR is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	set_meta("fragr_settings_path", _out_dir.path_join("settings.cfg"))
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.audio_listener_enable_3d = false
	root.add_child(_viewport)
	var menu: Node = (load("res://scenes/boot_menu.tscn") as PackedScene).instantiate()
	_viewport.add_child(menu)
	# The run preview is a short local child; wait for its answer.
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var owned: LocalMatch = menu.get("_local_match") as LocalMatch
		if owned != null and str(owned.run_preview.get("status", "loading")) != "loading":
			break
		await create_timer(0.2).timeout
	menu.call("_show", "single")
	await create_timer(0.8).timeout
	await _save("00_single_player_survival")
	menu.call("_show", "practice")
	await create_timer(0.6).timeout
	var selector: OptionButton = menu.find_child("DevelopmentMission", true, false) as OptionButton
	if selector != null:
		selector.select(selector.item_count - 1)
	await create_timer(0.4).timeout
	await _save("01_practice_development_walk")
	menu.queue_free()
	await process_frame
	quit(0)

func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var path: String = _out_dir.path_join(name + ".png")
	image.save_png(path)
	print("still_here_menu_review: saved ", path)
