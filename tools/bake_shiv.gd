extends SceneTree

## Offline reduction of the reviewed source. Keep alpha and wrist registration.
func _initialize() -> void:
	var root: String = ProjectSettings.globalize_path("res://")
	# The first-person Shiv now comes from the 2026-10-02 art pass, which used
	# shiv-view-source.png as its edit reference; only the icon is baked here.
	var sources: Array[String] = ["shiv-icon-source.png"]
	var outputs: Array[String] = ["assets/weapons/48/shiv.png"]
	var sizes: Array[Vector2i] = [Vector2i(48, 48)]
	for index: int in range(sources.size()):
		var source: Image = Image.load_from_file(root.path_join("art/weapons").path_join(sources[index]))
		if source == null or source.is_empty() or source.is_invisible() or source.detect_alpha() == Image.ALPHA_NONE:
			push_error("bake_shiv: source requires visible content and transparent alpha")
			quit(1)
			return
		source.resize(sizes[index].x, sizes[index].y, Image.INTERPOLATE_NEAREST)
		var output: String = root.path_join(outputs[index])
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		if source.save_png(output) != OK:
			push_error("bake_shiv: could not save reduced asset")
			quit(1)
			return
	print("bake_shiv: PASS icon")
	quit(0)
