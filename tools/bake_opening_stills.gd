extends SceneTree
## Run from the repo root: godot --headless --path client --script ../tools/bake_opening_stills.gd
## Bakes the Recall Notice opening's ADDRESS and RECALL stills from the authored
## pixel art in client/scripts/m01_opening_art.gd into
## client/assets/story/stills/opening/, and prints each file's SHA-256 for that
## directory's manifest.json. Run it after changing the art, then import.

const OUT: String = "res://assets/story/stills/opening/"
const Opening = preload("res://scripts/m01_opening_art.gd")

func _initialize() -> void:
	var stills: Dictionary[String, Image] = {
		"address.png": Opening.address(),
		"recall.png": Opening.recall(),
	}
	var failed: bool = false
	for file: String in stills:
		var path: String = OUT + file
		var result: Error = stills[file].save_png(path)
		if result != OK:
			printerr("bake_opening_stills: could not write %s (%s)" % [path, error_string(result)])
			failed = true
			continue
		print("bake_opening_stills: %s %dx%d sha256 %s" % [path, stills[file].get_width(), stills[file].get_height(), FileAccess.get_sha256(path)])
	quit(1 if failed else 0)
