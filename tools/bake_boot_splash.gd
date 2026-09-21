extends SceneTree
## Run from the repo root: godot --headless --path client --script ../tools/bake_boot_splash.gd
## Keep the approved source pixels intact and write a runtime PNG without editor metadata.

func _initialize() -> void:
	var source: Image = Image.load_from_file("res://../docs/fragr-logo-refined.png")
	if source == null or source.is_empty():
		push_error("boot splash bake: could not load the approved logo")
		quit(1)
		return
	var destination: String = ProjectSettings.globalize_path("res://assets/ui/boot_splash.png")
	if source.save_png(destination) != OK:
		push_error("boot splash bake: could not save the runtime image")
		quit(1)
		return
	var saved: Image = Image.load_from_file(destination)
	if saved == null or saved.get_size() != source.get_size() or saved.get_data() != source.get_data():
		push_error("boot splash bake: decoded pixels changed")
		quit(1)
		return
	print("boot splash bake: PASS, approved pixels preserved at ", saved.get_size())
	quit()
