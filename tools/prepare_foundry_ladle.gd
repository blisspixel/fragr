extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const SOURCE_SHA: String = "eb86d37171e803fca42507fc3eb1347c62c0ca8055ea49e12e37904da7d88519"

# Preserve the source candidate offline, removing only optional software credit.
# Geometry, materials and required legal metadata remain unchanged.
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.get_sha256(args[0]) != SOURCE_SHA:
		_fail("require exact retained source and new output file")
		return
	if FileAccess.file_exists(args[1]) or DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK:
		_fail("output must be new with a writable parent")
		return
	if DirAccess.copy_absolute(args[0], args[1]) != OK or not Metadata.clean(args[1]):
		_fail("cannot retain candidate metadata")
		return
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(args[1], state) != OK:
		_fail("retained candidate fails GLB import")
		return
	var scene: Node = document.generate_scene(state)
	if scene == null:
		_fail("retained candidate has no scene")
		return
	scene.free()
	print("foundry_ladle_source: PASS (retained offline; geometry and played acceptance remain separate)")
	quit(0)

func _fail(message: String) -> void:
	push_error("foundry_ladle_source: " + message)
	quit(1)
