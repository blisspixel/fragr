extends SceneTree

## Held-gun motion review without a match: the real HUD over a plain field,
## driven frame by frame, so the switch, the shot, the reload, the sway and the
## landing are captured at exact times rather than whenever a live tour lands.
## Writes one strip per sequence (bottom-centre crops) into FRAGR_QA_DIR:
##
##   FRAGR_QA_DIR=/abs/dir godot --path client --rendering-driver vulkan \
##     --windowed --script res://qa/viewmodel_review.gd
##
## Presentation review only: no server, no shot or reload is decided here.

const SIZE: Vector2i = Vector2i(1280, 720)
const CROP: Vector2i = Vector2i(560, 360)
const STEP: float = 1.0 / 30.0
var _output: String
var _hud: CanvasLayer
var _camera: Camera3D
var _failed: bool = false

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	_run.call_deferred()

func _run() -> void:
	_output = OS.get_environment("FRAGR_QA_DIR")
	if not _output.is_absolute_path():
		push_error("viewmodel_review: FRAGR_QA_DIR must be an absolute directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	root.mode = Window.MODE_WINDOWED
	root.size = SIZE
	var field: ColorRect = ColorRect.new()
	field.color = Color("3a3836")
	field.size = Vector2(1920, 1080)
	root.add_child(field)
	# A camera the HUD reads for sway and landing, moved by hand below.
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.position = Vector3(0.0, 1.6, 0.0)
	world.add_child(_camera)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	_hud = scene.get_node("HUD") as CanvasLayer
	scene.remove_child(_hud)
	scene.free()
	root.add_child(_hud)
	_hud.set_process(false)
	_hud.set_fp_juice(true)
	for _i: int in range(4):
		await process_frame
	await _switch("Fists", "Tack")
	await _switch("Tack", "Scatter")
	await _switch("Scatter", "Rail")
	await _switch("Rail", "Flechette")
	for weapon: String in ["Tack", "Scatter", "Rail", "Flechette"]:
		await _fire(weapon)
		await _reload(weapon)
	await _sway_and_land("Tack")
	quit(1 if _failed else 0)

func _advance(seconds: float) -> void:
	_hud._process(seconds)

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		_failed = true
		return Image.create_empty(CROP.x, CROP.y, false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	return image.get_region(Rect2i((image.get_width() - CROP.x) / 2, image.get_height() - CROP.y, CROP.x, CROP.y))

func _strip(file_name: String, frames: Array[Image]) -> void:
	var strip: Image = Image.create_empty(CROP.x * frames.size(), CROP.y, false, Image.FORMAT_RGBA8)
	for index: int in range(frames.size()):
		strip.blit_rect(frames[index], Rect2i(Vector2i.ZERO, CROP), Vector2i(index * CROP.x, 0))
	if strip.save_png(_output.path_join(file_name)) != OK:
		push_error("viewmodel_review: cannot write " + file_name)
		_failed = true
	print("viewmodel_review: %s (%d frames)" % [file_name, frames.size()])

func _settle(weapon: String) -> void:
	_hud.set_fp_weapon(weapon)
	for _i: int in range(30):
		_advance(STEP)

func _switch(from: String, to: String) -> void:
	_settle(from)
	_hud.set_fp_weapon(to)
	var frames: Array[Image] = []
	for _i: int in range(12):
		frames.append(await _grab())
		_advance(STEP)
	_strip("switch_%s_to_%s.png" % [from.to_lower(), to.to_lower()], frames)

func _fire(weapon: String) -> void:
	_settle(weapon)
	_hud.show_fire_juice(weapon)
	var frames: Array[Image] = []
	for _i: int in range(10):
		frames.append(await _grab())
		_advance(STEP * (2.0 if weapon == "Rail" else 1.0))
	_strip("fire_%s.png" % weapon.to_lower(), frames)

func _reload(weapon: String) -> void:
	_settle(weapon)
	var key: String = weapon.to_lower()
	var ticks: int = 28 if weapon == "Rail" else (14 if weapon == "Scatter" else (16 if weapon == "Tack" else 22))
	var pool: String = str(EquipmentState.POOLS[key])
	var ammo: Array = []
	for name: String in EquipmentState.POOL_ORDER:
		ammo.append({"pool": name, "rounds": 40 if name == pool else 0})
	var state: Dictionary = {"selected": key, "tick": 100, "weapons": ["fists", key], "ammo": ammo,
		"loaded": [{"weapon": key, "rounds": 0, "ready_at": 100 + ticks}], "dry_fire_count": 0, "grenades": 0, "personal_claims": []}
	_hud.equipment_hud.apply(state)
	var frames: Array[Image] = []
	for tick: int in range(100, 100 + ticks + 2, 2):
		_hud.equipment_hud.tick = tick
		_advance(0.1)
		frames.append(await _grab())
	_hud.equipment_hud.apply({})
	_strip("reload_%s.png" % key, frames)

## Turn left for a third of a second, then let go; then drop a metre and land.
func _sway_and_land(weapon: String) -> void:
	_settle(weapon)
	var frames: Array[Image] = []
	for index: int in range(10):
		if index < 5:
			_camera.rotation.y += 0.09
		_hud._process(STEP)
		frames.append(await _grab())
	_strip("sway_%s.png" % weapon.to_lower(), frames)
	frames = []
	for index: int in range(14):
		if index < 6:
			_camera.position.y -= 0.22
		_hud._process(STEP)
		frames.append(await _grab())
	_strip("land_%s.png" % weapon.to_lower(), frames)
