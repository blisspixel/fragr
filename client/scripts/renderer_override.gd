extends RefCounted
class_name RendererOverride

## The renderer choice that only a restart can apply. Godot reads the
## rendering method at startup and has no runtime setter, so the choice lives
## in an override file the project names in
## `application/config/project_settings_override` (client/project.godot),
## read before the renderer starts. Verified on 4.7.2-stable: a missing file
## is ignored; a present one switches Forward+ to Compatibility. A command
## line `--rendering-method` still wins. Recovery when it goes wrong: delete
## the file (docs/GRAPHICS.md names where it is) or start with
## `--rendering-method forward_plus`.

const PATH: String = "user://renderer_override.cfg"
const METHODS: Array[String] = ["forward_plus", "gl_compatibility"]

## The overridden method in `path`, or "" when there is none.
static func active(path: String = PATH) -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var method: Variant = cfg.get_value("rendering", "renderer/rendering_method", "")
	return str(method) if method is String and str(method) in METHODS else ""

static func write(method: String, path: String = PATH) -> Error:
	if method not in METHODS:
		return ERR_INVALID_PARAMETER
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("rendering", "renderer/rendering_method", method)
	return cfg.save(path)

static func clear(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Restart into the overridden renderer. The tune record carries the Forward+
## figure, so the next start measures again and keeps Compatibility only if
## it is faster.
static func restart(tree: SceneTree) -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	tree.quit()
