extends SceneTree

## Registers the selected Arc source surfaces without rebuilding gameplay or audio.
const SOURCE: String = "res://art/weapons/arc-20261008"
const OUT: String = "res://assets/weapons/arc"
const CANVAS: Vector2i = Vector2i(241, 180)

func _initialize() -> void:
	var output: String = OUT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	var idle: Image = _source("arc_idle_source.png", CANVAS)
	var fire: Image = _source("arc_fire_source.png", CANVAS)
	var reload: Image = _source("arc_reload_source.png", CANVAS)
	var profile_source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE.path_join("arc_profile_source.png")))
	if idle == null or fire == null or reload == null or profile_source == null or profile_source.get_height() != 28 or profile_source.get_width() > 80:
		push_error("bake_arc: missing or invalid selected source")
		quit(1)
		return
	var profile: Image = Image.create_empty(80, 42, false, Image.FORMAT_RGBA8)
	profile.blit_rect(profile_source, Rect2i(Vector2i.ZERO, profile_source.get_size()), Vector2i((80 - profile_source.get_width()) / 2, 7))
	# The follow-through retains the entire idle geometry and only energized
	# recessed contacts. The discharge above the emitter ends with the fire frame.
	var settle: Image = idle.duplicate()
	for region: Rect2i in [Rect2i(100, 25, 43, 46), Rect2i(143, 101, 23, 8)]:
		settle.blit_rect(fire, region, region.position)
	var muzzle: Image = Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var discharge: Image = fire.get_region(Rect2i(83, 0, 39, 17))
	discharge.resize(32, 14, Image.INTERPOLATE_NEAREST)
	muzzle.blit_rect(discharge, Rect2i(0, 0, 32, 14), Vector2i(0, 9))
	var products: Dictionary[String, Image] = {
		"arc_idle":idle, "arc_fire":fire, "arc_settle":settle,
		"arc_reload":reload, "arc_profile":profile, "arc_muzzle":muzzle,
	}
	var directory: String = ProjectSettings.globalize_path(output) if output.begins_with("res://") else output
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("bake_arc: output directory unavailable")
		quit(1)
		return
	for product: String in products:
		if products[product].save_png(directory.path_join(product + ".png")) != OK:
			push_error("bake_arc: image write failed")
			quit(1)
			return
	print("bake_arc: PASS six registered surfaces, held canvas241x180, audio unchanged")
	quit(0)

func _source(file_name: String, expected: Vector2i) -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE.path_join(file_name)))
	if image == null or image.get_size() != expected:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image
