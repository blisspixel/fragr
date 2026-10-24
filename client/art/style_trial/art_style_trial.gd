extends SceneTree

## Art style trial (exp/art-style-trial). Renders three units in Arena Duel
## under the shipped look and three candidate treatments with matched cameras,
## then composes contact sheets. Presentation only: no shipped default, asset
## or setting changes, and no combat authority.
##
##   S  shipped today: free bodies are live skins with their full-resolution
##      maps sampled nearest (skinned_character.gd); the Clerk is its shipped
##      baked atlas, so S and B are the same image for the Clerk
##   A  live skinned model, pixel material (low-res palette map, stepped light,
##      edge light, outline_purple hull), smooth motion, continuous facing
##   B  shipped directional bake: 8 directions, 55 poses, 160 px cells, paired
##      view normals under the Union sprite shader
##   C  hybrid: A's material and model, pose time held on a 12 fps clock,
##      facing snapped to the same 8 directions as B, frame rendered at the
##      existing "medium" integer pixel look (360 world lines)
##
## godot --path client --windowed --audio-driver Dummy \
##   --script res://art/style_trial/art_style_trial.gd -- \
##   <abs out dir> <abs bake dir> <server host:port | abs map_info.json>

const TrialPose = preload("res://art/style_trial/trial_pose_source.gd")
const PIXEL_SHADER: Shader = preload("res://art/style_trial/pixel_actor.gdshader")
const OUTLINE_SHADER: Shader = preload("res://art/style_trial/pixel_outline.gdshader")
const UNION_SPRITE: Shader = preload("res://assets/shaders/union_sprite.gdshader")
const GAMEPLAY_VERSION: int = preload("res://scripts/net_client.gd").GAMEPLAY_VERSION

const OUTPUT: Vector2i = Vector2i(1280, 720)
const CELL: Vector2i = Vector2i(280, 380)
const UNITS: Array[String] = ["human", "clerk", "synthetic"]
const UNIT_TITLES: Dictionary[String, String] = {
	"human": "Free human (player body)",
	"clerk": "Union Clerk",
	"synthetic": "Civilian synthetic (free agent)",
}
const TREATMENTS: Array[String] = ["S", "A", "B", "C"]
const TREATMENT_TITLES: Dictionary[String, String] = {
	"S": "S  Shipped today: live skins for free bodies, baked atlas for the Clerk",
	"A": "A  Live 3D, pixel material",
	"B": "B  Baked 8-direction sprites + normals",
	"C": "C  Hybrid: live 3D, 12 fps, 8 facings, 360-line frame",
}
const TREATMENT_SHORT: Dictionary[String, String] = {
	"S": "S shipped today\n(free bodies live,\nClerk baked)",
	"A": "A live 3D\npixel material",
	"B": "B baked\n8-dir sprites",
	"C": "C hybrid\n12 fps, 8 facings\n360-line frame",
}
const ACTIONS: Array[Dictionary] = [
	{"label": "idle", "action": "idle", "progress": 0.0},
	{"label": "run", "action": "walk", "progress": 0.25},
	{"label": "fire", "action": "fire", "progress": 0.0},
	{"label": "hit", "action": "hit", "progress": 0.0},
	{"label": "death", "action": "death", "progress": 1.0},
]
const DISTANCES: Array[float] = [3.0, 10.0, 25.0]
const ZOOM: Dictionary[float, int] = {3.0: 1, 10.0: 2, 25.0: 4}
## Two real Arena Duel spots. Light: south of the south gantry, sun behind the
## camera. Shade: in the north gantry's cast shadow, sun behind the unit.
const SETS: Dictionary[String, Dictionary] = {
	"light": {"base": Vector3(10.0, 0.0, 22.0), "toward": Vector3(0, 0, 1)},
	"shade": {"base": Vector3(-10.0, 0.0, -21.15), "toward": Vector3(0, 0, -1)},
}
const EYE_HEIGHT: float = 1.6
const TARGET_HEIGHT: float = 0.9
const CLIP_FRAMES: int = 72
const CLIP_FPS: float = 30.0
const RUN_SPEED: float = 4.0
const STEP_FPS: float = 12.0
const OUTLINE_PURPLE: Color = Color8(58, 42, 72)
const INK: Color = Color8(10, 10, 12)
const BONE: Color = Color8(232, 226, 214)
const FLASH_COLORS: Array[Color] = [Color("ffe2a2"), Color("e47e3b")]
const TEXTURE_SIZE: int = 256
const PALETTE_COLORS: int = 24

var _out: String
var _bake: String
var _view: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _settings: FragrSettings
var _pixel_settings: FragrSettings
var _sources: Dictionary[String, RefCounted] = {}
var _atlases: Dictionary[String, Texture2D] = {}
var _normals: Dictionary[String, Texture2D] = {}
var _material_cache: Dictionary = {}
var _texture_cache: Dictionary = {}
var _outlines: Dictionary[String, ShaderMaterial] = {}
var _cells: Dictionary[String, Image] = {}
var _clip_cells: Dictionary[String, Image] = {}
var _receipt: Dictionary = {}
var _failures: PackedStringArray = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3 or not args[0].is_absolute_path() or not args[1].is_absolute_path():
		push_error("art_style_trial: require <out dir> <bake dir> <server | map_info.json>")
		quit(1)
		return
	_out = args[0]
	_bake = args[1]
	for folder: String in ["cells", "frames", "clips", "sheets"]:
		DirAccess.make_dir_recursive_absolute(_out.path_join(folder))
	var only: String = args[3] if args.size() > 3 else ""
	var started: int = Time.get_ticks_msec()
	var info: Dictionary = await _map_info(args[2])
	if info.is_empty():
		push_error("art_style_trial: no map_info")
		quit(1)
		return
	_build_scene(info)
	_load_assets()
	_receipt = {"schema": 1, "engine": Engine.get_version_info()["string"],
		"renderer": RenderingServer.get_current_rendering_method(), "video_adapter": RenderingServer.get_video_adapter_name(),
		"map": str(info.get("map_name", "")), "map_id": info.get("map_id"), "output": [OUTPUT.x, OUTPUT.y],
		"cell": [CELL.x, CELL.y], "zoom": {"3m": 1, "10m": 2, "25m": 4}, "vertical_fov": 75.0,
		"eye_height": EYE_HEIGHT, "sets": {"light": "south gantry face, sun behind camera", "shade": "north gantry cast shadow, sun behind unit"},
		"texture_size": TEXTURE_SIZE, "palette_colors": PALETTE_COLORS, "clip_fps": CLIP_FPS, "c_step_fps": STEP_FPS,
		"run_speed_mps": RUN_SPEED}
	if only == "" or only == "stills":
		await _stills()
		await _groups()
	if only == "" or only == "clips":
		await _clips()
	if only == "" or only == "perf":
		await _perf()
	if only == "" or only == "stills":
		await _sheets()
	_receipt["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	_receipt["failures"] = _failures
	var scripts: Dictionary = {}
	for path: String in ["res://art/style_trial/art_style_trial.gd", "res://art/style_trial/pixel_actor.gdshader",
			"res://art/style_trial/pixel_outline.gdshader", "res://art/style_trial/trial_pose_source.gd",
			"res://assets/shaders/union_sprite.gdshader", "res://assets/characters/union/clerk.png",
			"res://assets/characters/union/clerk_normals.png"]:
		scripts[path] = FileAccess.get_sha256(path)
	_receipt["sources"] = scripts
	var file: FileAccess = FileAccess.open(_out.path_join("receipt-%s.json" % (only if only != "" else "all")), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_receipt, "\t") + "\n")
		file.close()
	_view.queue_free()
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("art_style_trial: " + failure)
		quit(1)
		return
	print("art_style_trial: PASS (%s)" % (only if only != "" else "all"))
	quit(0)

# --- map and scene ---------------------------------------------------------

func _map_info(source: String) -> Dictionary:
	if source.ends_with(".json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		return parsed if parsed is Dictionary else {}
	var socket: WebSocketPeer = WebSocketPeer.new()
	if socket.connect_to_url("ws://" + source) != OK:
		return {}
	var deadline: int = Time.get_ticks_msec() + 15000
	var greeted: bool = false
	while Time.get_ticks_msec() < deadline:
		socket.poll()
		var state: int = socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN and not greeted:
			greeted = true
			socket.send_text(JSON.stringify({"type": "hello", "role": "spectator", "name": "ArtTrial",
				"geometry_version": MapGeometry.VERSION, "gameplay_version": GAMEPLAY_VERSION}))
		while socket.get_available_packet_count() > 0:
			var message: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if message is Dictionary and (message as Dictionary).get("type") == "map_info":
				socket.close()
				var file: FileAccess = FileAccess.open(_out.path_join("map_info.json"), FileAccess.WRITE)
				if file != null:
					file.store_string(JSON.stringify(message))
					file.close()
				return message
		if state == WebSocketPeer.STATE_CLOSED:
			break
		await process_frame
	return {}

func _build_scene(info: Dictionary) -> void:
	_settings = FragrSettings.new("")
	_pixel_settings = FragrSettings.new("")
	_pixel_settings.set_value("video", "pixel_scale", 2)
	_view = SubViewport.new()
	_view.size = OUTPUT
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	var arena: Node3D = Node3D.new()
	arena.name = "Arena"
	_view.add_child(arena)
	var layout: Node3D = (load("res://scenes/arena.tscn") as PackedScene).instantiate() as Node3D
	layout.name = "Layout"
	arena.add_child(layout)
	var cover: ArenaCover = ArenaCover.new()
	arena.add_child(cover)
	cover.apply_map_info(info)
	var map_name: String = str(info.get("map_name", ""))
	var world: WorldEnvironment = layout.get_node("WorldEnvironment") as WorldEnvironment
	world.environment = ArenaSky.build_environment(map_name)
	RenderQuality.apply_environment(world.environment, _settings)
	ArenaSky.apply_scene_lights(layout, map_name)
	RenderQuality.apply_practicals(arena, _settings)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 500.0
	_view.add_child(_camera)
	_camera.current = true
	ArenaSky.apply_view_fill(_camera, map_name)
	_stage = Node3D.new()
	_stage.name = "TrialStage"
	_view.add_child(_stage)
	_quality(false)

func _quality(pixel_look: bool) -> void:
	RenderQuality.apply(_view, _pixel_settings if pixel_look else _settings)

func _load_assets() -> void:
	for unit: String in UNITS:
		_sources[unit] = TrialPose.new(unit)
	_atlases["clerk"] = load("res://assets/characters/union/clerk.png") as Texture2D
	_normals["clerk"] = load("res://assets/characters/union/clerk_normals.png") as Texture2D
	for unit: String in ["human", "synthetic"]:
		var albedo: Image = Image.load_from_file(_bake.path_join(unit + ".png"))
		var normal: Image = Image.load_from_file(_bake.path_join(unit + "_normals.png"))
		if albedo == null or normal == null:
			_failures.append("missing bake for " + unit)
			continue
		_atlases[unit] = ImageTexture.create_from_image(albedo)
		_normals[unit] = ImageTexture.create_from_image(normal)
	for treatment: String in ["A", "C"]:
		var outline: ShaderMaterial = ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("outline_color", OUTLINE_PURPLE)
		# C's 360-line frame already has sprite-sized pixels: its line is one
		# world texel and fades out with the texel at range, as B's rim does.
		outline.set_shader_parameter("min_pixels", 1.0 if treatment == "A" else 0.0)
		_outlines[treatment] = outline

# --- treatments ------------------------------------------------------------

## Direction cell the shipped runtime would select: the baker turns a +Z
## facing model by d * 45 degrees in front of a camera on +Z.
static func _direction(yaw: float, unit_at: Vector3, eye: Vector3) -> int:
	var to_eye: Vector3 = eye - unit_at
	var bearing: float = atan2(to_eye.x, to_eye.z)
	return posmod(roundi((yaw - bearing) / (PI / 4.0)), 8)

static func _snapped_yaw(yaw: float, unit_at: Vector3, eye: Vector3) -> float:
	var to_eye: Vector3 = eye - unit_at
	return atan2(to_eye.x, to_eye.z) + _direction(yaw, unit_at, eye) * PI / 4.0

func _spawn(unit: String, treatment: String, action: String, progress: float, at: Vector3, yaw: float) -> Node3D:
	var eye: Vector3 = _camera.global_position
	if treatment == "B" or (treatment == "S" and unit == "clerk"):
		var holder: Node3D = Node3D.new()
		holder.position = at
		var sprite: Sprite3D = Sprite3D.new()
		sprite.texture = _atlases[unit]
		sprite.hframes = EnemyAnimation.COLUMNS
		sprite.vframes = EnemyAnimation.rows()
		sprite.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.shaded = true
		sprite.position.y = EnemyAnimation.CENTRE_HEIGHT
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = UNION_SPRITE
		material.set_shader_parameter("sprite_texture", sprite.texture)
		material.set_shader_parameter("normals_enabled", true)
		material.set_shader_parameter("sprite_normals", _normals[unit])
		if unit != "clerk":
			# Free bodies carry no Union red; their line is outline purple.
			material.set_shader_parameter("red_glow", 0.0)
			material.set_shader_parameter("rim_color", OUTLINE_PURPLE)
			material.set_shader_parameter("rim_glow", 1.0)
		sprite.material_override = material
		sprite.frame = _direction(yaw, at, eye) * EnemyAnimation.poses() + EnemyAnimation.pose_frame(action, false, progress)
		holder.add_child(sprite)
		_stage.add_child(holder)
		return holder
	var model: Node3D = _sources[unit].call("build_pose", action, progress, false) as Node3D
	model.position = at
	model.rotation.y = _snapped_yaw(yaw, at, eye) if treatment == "C" else yaw
	_stage.add_child(model)
	if treatment == "S":
		_shipped_skin(model)
	else:
		_pixelize(model, unit, treatment)
	return model

## The shipped live skin's only material change: nearest sampling.
func _shipped_skin(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var override: StandardMaterial3D = mesh_node.material_override as StandardMaterial3D
		if override != null:
			var copy: StandardMaterial3D = override.duplicate() as StandardMaterial3D
			copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mesh_node.material_override = copy
		elif mesh_node.mesh != null:
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				var original: StandardMaterial3D = mesh_node.get_active_material(surface) as StandardMaterial3D
				if original != null:
					var material: StandardMaterial3D = original.duplicate() as StandardMaterial3D
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_node.set_surface_override_material(surface, material)
	for child: Node in node.get_children():
		_shipped_skin(child)

func _pixelize(node: Node, unit: String, treatment: String) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var override: StandardMaterial3D = mesh_node.material_override as StandardMaterial3D
		if override != null:
			mesh_node.material_override = _pixel_material(override, unit, treatment)
		elif mesh_node.mesh != null:
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				var original: StandardMaterial3D = mesh_node.get_active_material(surface) as StandardMaterial3D
				if original != null:
					mesh_node.set_surface_override_material(surface, _pixel_material(original, unit, treatment))
	for child: Node in node.get_children():
		_pixelize(child, unit, treatment)

func _pixel_material(original: StandardMaterial3D, unit: String, treatment: String) -> ShaderMaterial:
	var key: String = "%s:%s:%d" % [unit, treatment, original.get_instance_id()]
	if _material_cache.has(key):
		return _material_cache[key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = PIXEL_SHADER
	material.set_shader_parameter("albedo", original.albedo_color)
	var flash: bool = false
	for colour: Color in FLASH_COLORS:
		if original.albedo_color.is_equal_approx(colour):
			flash = true
	material.set_shader_parameter("unshaded_flash", flash)
	if original.albedo_texture != null:
		material.set_shader_parameter("use_texture", true)
		material.set_shader_parameter("albedo_texture", _low_res(original.albedo_texture, true))
	else:
		material.set_shader_parameter("use_texture", false)
	if original.normal_enabled and original.normal_texture != null:
		material.set_shader_parameter("use_normal", true)
		material.set_shader_parameter("normal_texture", _low_res(original.normal_texture, false))
	material.set_shader_parameter("red_glow", 1.6 if unit == "clerk" else 0.0)
	if not flash:
		material.next_pass = _outlines[treatment]
	_material_cache[key] = material
	return material

func _low_res(texture: Texture2D, quantize: bool) -> ImageTexture:
	var key: String = "%d:%s" % [texture.get_instance_id(), quantize]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var image: Image = texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var target: Vector2i = Vector2i(mini(TEXTURE_SIZE, image.get_width()), mini(TEXTURE_SIZE, image.get_height()))
	# Point sampling, not averaging: the prepared skins use fragmented UV
	# atlases, and an averaged reduction bleeds neighbouring islands into each
	# other (run2 evidence: dark work trousers turned brown at 128 px).
	if image.get_size() != target:
		image.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	if quantize:
		_quantize(image, PALETTE_COLORS)
		image.save_png(_out.path_join("cells/texture_%s.png" % texture.resource_path.get_file().get_basename().validate_filename()))
	var result: ImageTexture = ImageTexture.create_from_image(image)
	_texture_cache[key] = result
	return result

## Small k-means palette per map, like an indexed sprite palette: keeps skin,
## leather and cloth ramps instead of forcing them onto the world swatches.
func _quantize(image: Image, count: int) -> void:
	var data: PackedByteArray = image.get_data()
	var pixels: int = image.get_width() * image.get_height()
	var centres: Array[Vector3] = []
	for index: int in range(count):
		var at: int = int(float(index) / count * pixels) * 4
		centres.append(Vector3(data[at], data[at + 1], data[at + 2]))
	var assignment: PackedInt32Array = PackedInt32Array()
	assignment.resize(pixels)
	for iteration: int in range(8):
		var sums: Array[Vector3] = []
		var counts: PackedInt32Array = PackedInt32Array()
		counts.resize(count)
		for index: int in range(count):
			sums.append(Vector3.ZERO)
		# Fit the palette on every third texel; assign every texel below.
		for pixel: int in range(0, pixels, 3):
			var colour: Vector3 = Vector3(data[pixel * 4], data[pixel * 4 + 1], data[pixel * 4 + 2])
			var best: int = _nearest(colour, centres)
			sums[best] += colour
			counts[best] += 1
		for index: int in range(count):
			if counts[index] > 0:
				centres[index] = sums[index] / counts[index]
	for pixel: int in range(pixels):
		assignment[pixel] = _nearest(Vector3(data[pixel * 4], data[pixel * 4 + 1], data[pixel * 4 + 2]), centres)
	for pixel: int in range(pixels):
		var centre: Vector3 = centres[assignment[pixel]]
		data[pixel * 4] = clampi(roundi(centre.x), 0, 255)
		data[pixel * 4 + 1] = clampi(roundi(centre.y), 0, 255)
		data[pixel * 4 + 2] = clampi(roundi(centre.z), 0, 255)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)

static func _nearest(colour: Vector3, centres: Array[Vector3]) -> int:
	var best: int = 0
	var best_distance: float = INF
	for index: int in range(centres.size()):
		var distance: float = colour.distance_squared_to(centres[index])
		if distance < best_distance:
			best_distance = distance
			best = index
	return best

func _clear_stage() -> void:
	for child: Node in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()

func _place_camera(at: Vector3, toward: Vector3, distance: float) -> void:
	_camera.position = Vector3(at.x, EYE_HEIGHT, at.z) + toward * distance
	_camera.look_at(Vector3(at.x, TARGET_HEIGHT, at.z))

func _shot() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = _view.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image

func _crop(image: Image, centre: Vector2, zoom: int) -> Image:
	var size: Vector2i = CELL / zoom
	var corner: Vector2i = Vector2i(roundi(centre.x - size.x * 0.5), roundi(centre.y - size.y * 0.5))
	corner.x = clampi(corner.x, 0, image.get_width() - size.x)
	corner.y = clampi(corner.y, 0, image.get_height() - size.y)
	var cell: Image = image.get_region(Rect2i(corner, size))
	cell.resize(CELL.x, CELL.y, Image.INTERPOLATE_NEAREST)
	return cell

# --- captures --------------------------------------------------------------

func _stills() -> void:
	for set_name: String in SETS:
		var base: Vector3 = SETS[set_name]["base"]
		var toward: Vector3 = SETS[set_name]["toward"]
		var yaw: float = 0.0 if toward.z > 0.0 else PI
		for unit: String in UNITS:
			for distance: float in DISTANCES:
				_place_camera(base, toward, distance)
				for treatment: String in TREATMENTS:
					_quality(treatment == "C")
					for entry: Dictionary in ACTIONS:
						_spawn(unit, treatment, str(entry["action"]), float(entry["progress"]), base, yaw)
						var image: Image = await _shot()
						var centre: Vector2 = _camera.unproject_position(base + Vector3(0, 0.85, 0))
						var cell: Image = _crop(image, centre, ZOOM[distance])
						var key: String = "%s|%s|%s|%d|%s" % [treatment, unit, set_name, int(distance), entry["label"]]
						_cells[key] = cell
						cell.save_png(_out.path_join("cells/%s.png" % key.replace("|", "_")))
						if entry["label"] in ["idle", "fire"]:
							image.save_png(_out.path_join("frames/%s.png" % key.replace("|", "_")))
						_clear_stage()
		print("art_style_trial: stills ", set_name)
	_quality(false)

func _groups() -> void:
	for set_name: String in SETS:
		var base: Vector3 = SETS[set_name]["base"]
		var toward: Vector3 = SETS[set_name]["toward"]
		var yaw: float = 0.0 if toward.z > 0.0 else PI
		var side: Vector3 = Vector3(1.4, 0, 0)
		for distance: float in [3.5, 10.0]:
			_place_camera(base, toward, distance)
			for treatment: String in TREATMENTS:
				_quality(treatment == "C")
				for label: String in ["idle", "fire"]:
					for index: int in range(UNITS.size()):
						_spawn(UNITS[index], treatment, label, 0.0, base + side * (index - 1), yaw)
					var image: Image = await _shot()
					image.save_png(_out.path_join("frames/group_%s_%s_%d_%s.png" % [treatment, set_name, int(distance), label]))
					_clear_stage()
	_quality(false)

## One clip pose at time t. A: continuous. B: the runtime's discrete cell.
## C: time held on a 12 fps clock.
static func _clip_pose(clip: String, t: float) -> Dictionary:
	if clip == "run":
		return {"action": "walk", "progress": fposmod(t * RUN_SPEED / EnemyAnimation.STRIDE_METRES, 1.0), "yaw": TAU * t / 2.4}
	var yaw: float = deg_to_rad(35.0)
	if t < 0.3:
		return {"action": "idle", "progress": 0.0, "yaw": yaw}
	if t < 0.6:
		return {"action": "raise", "progress": (t - 0.3) / 0.3, "yaw": yaw}
	if t < 0.7:
		return {"action": "fire", "progress": (t - 0.6) / 0.1, "yaw": yaw}
	if t < 0.9:
		return {"action": "raise", "progress": 1.0, "yaw": yaw}
	if t < 1.0:
		return {"action": "fire", "progress": (t - 0.9) / 0.1, "yaw": yaw}
	if t < 1.2:
		return {"action": "hit", "progress": (t - 1.0) / 0.2, "yaw": yaw}
	return {"action": "death", "progress": minf(1.0, (t - 1.2) / EnemyAnimation.DEATH_SECONDS), "yaw": yaw}

func _clips() -> void:
	var base: Vector3 = SETS["light"]["base"]
	var toward: Vector3 = SETS["light"]["toward"]
	_place_camera(base, toward, 10.0)
	for unit: String in UNITS:
		for clip: String in ["run", "combat"]:
			for treatment: String in TREATMENTS:
				_quality(treatment == "C")
				var folder: String = _out.path_join("clips/%s_%s_%s" % [unit, clip, treatment])
				DirAccess.make_dir_recursive_absolute(folder)
				for frame: int in range(CLIP_FRAMES):
					var t: float = frame / CLIP_FPS
					if treatment == "C":
						t = floorf(t * STEP_FPS) / STEP_FPS
					var pose: Dictionary = _clip_pose(clip, t)
					_spawn(unit, treatment, str(pose["action"]), float(pose["progress"]), base, float(pose["yaw"]))
					var image: Image = await _shot()
					var centre: Vector2 = _camera.unproject_position(base + Vector3(0, 0.85, 0))
					var cell: Image = _crop(image, centre, 2)
					cell.save_png(folder.path_join("f%03d.png" % frame))
					if (clip == "run" and frame < 12) or (clip == "combat" and frame >= 30 and (frame - 30) % 3 == 0):
						_clip_cells["%s|%s|%s|%d" % [unit, clip, treatment, frame]] = cell
					_clear_stage()
			print("art_style_trial: clip ", unit, " ", clip)
	_quality(false)
	await _strips()

## Motion strips: one stride at full 30 fps (frames 0-11, facing turning),
## then hit and collapse sampled every third frame (10 Hz, frames 30-63).
func _strips() -> void:
	var label_width: int = 210
	var header: int = 44
	var small: Vector2i = CELL / 2
	var rows: Array[Array] = []
	for clip: String in ["run", "combat"]:
		for treatment: String in TREATMENTS:
			rows.append([clip, treatment])
	for unit: String in UNITS:
		var sheet: Image = Image.create(label_width + small.x * 12, header + small.y * rows.size(), false, Image.FORMAT_RGB8)
		sheet.fill(INK)
		sheet.blit_rect(await _text("%s motion, 10 m light, 2x. Run rows: frames 0-11 at 30 fps while turning. Combat rows: raise, fire, hit, collapse every 3rd frame (10 Hz)." % UNIT_TITLES[unit],
			Vector2i(sheet.get_width(), header), 16), Rect2i(0, 0, sheet.get_width(), header), Vector2i.ZERO)
		for row: int in range(rows.size()):
			var clip: String = rows[row][0]
			var treatment: String = rows[row][1]
			var y: int = header + row * small.y
			sheet.blit_rect(await _text("%s\n%s" % [clip, TREATMENT_SHORT[treatment]], Vector2i(label_width, small.y), 15), Rect2i(0, 0, label_width, small.y), Vector2i(0, y))
			for column: int in range(12):
				var frame: int = column if clip == "run" else 30 + column * 3
				var key: String = "%s|%s|%s|%d" % [unit, clip, treatment, frame]
				if not _clip_cells.has(key):
					continue
				var cell: Image = _clip_cells[key].duplicate() as Image
				cell.resize(small.x, small.y, Image.INTERPOLATE_NEAREST)
				sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, small), Vector2i(label_width + column * small.x, y))
		sheet.save_png(_out.path_join("sheets/strips_%s.png" % unit))

## Rough render cost on this machine: sixteen actors walking in the lit set.
## A and C animate real skeletons on the GPU path; B swaps atlas cells.
func _perf() -> void:
	var base: Vector3 = SETS["light"]["base"]
	var toward: Vector3 = SETS["light"]["toward"]
	_place_camera(base, toward, 12.0)
	RenderingServer.viewport_set_measure_render_time(_view.get_viewport_rid(), true)
	var results: Dictionary = {}
	for treatment: String in ["none", "none_pixel", "A", "B", "C"]:
		_quality(treatment in ["C", "none_pixel"])
		var actors: Array[Node3D] = []
		if not treatment.begins_with("none"):
			for index: int in range(16):
				var unit: String = UNITS[index % 3]
				var at: Vector3 = base + Vector3((index % 4 - 1.5) * 2.0, 0, floorf(index / 4.0) * 2.0)
				var actor: Node3D = _spawn(unit, treatment, "idle", 0.0, at, 0.0)
				actors.append(actor)
				if treatment != "B":
					var player: AnimationPlayer = actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
					if player != null and player.has_animation(&"walk"):
						player.play(&"walk")
						player.seek(index * 0.07, true)
		for warm: int in range(30):
			await process_frame
		var gpu: PackedFloat64Array = PackedFloat64Array()
		var cpu: PackedFloat64Array = PackedFloat64Array()
		for sample: int in range(120):
			await RenderingServer.frame_post_draw
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_view.get_viewport_rid()))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_view.get_viewport_rid()))
			for index: int in range(actors.size()):
				if treatment == "B":
					var sprite: Sprite3D = actors[index].get_child(0) as Sprite3D
					sprite.frame = EnemyAnimation.pose_frame("walk", false, fposmod(sample * 0.05 + index * 0.1, 1.0))
		gpu.sort()
		cpu.sort()
		results[treatment] = {"gpu_ms_median": gpu[gpu.size() / 2], "gpu_ms_p90": gpu[int(gpu.size() * 0.9)],
			"cpu_ms_median": cpu[cpu.size() / 2], "actors": actors.size()}
		_clear_stage()
		await process_frame
	_receipt["perf"] = results
	print("art_style_trial: perf ", results)
	_quality(false)

# --- sheets ----------------------------------------------------------------

func _text(text: String, size: Vector2i, font_size: int, colour: Color = BONE, background: Color = INK) -> Image:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var panel: ColorRect = ColorRect.new()
	panel.color = background
	panel.size = Vector2(size)
	viewport.add_child(panel)
	var label: Label = Label.new()
	label.text = text
	label.position = Vector2(8, 0)
	label.size = Vector2(size.x - 16, size.y)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	viewport.add_child(label)
	root.add_child(viewport)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	viewport.queue_free()
	return image

func _sheets() -> void:
	var label_width: int = 210
	var header: int = 44
	for treatment: String in TREATMENTS:
		var title: int = 70
		var block: int = header + CELL.y * 6
		var sheet: Image = Image.create(label_width + CELL.x * ACTIONS.size(), title + block * UNITS.size(), false, Image.FORMAT_RGB8)
		sheet.fill(INK)
		sheet.blit_rect(await _text(TREATMENT_TITLES[treatment] + "   (Arena Duel, 1280x720 frame, 75 deg FOV; 10 m cells 2x, 25 m cells 4x nearest)", Vector2i(sheet.get_width(), title), 22), Rect2i(0, 0, sheet.get_width(), title), Vector2i.ZERO)
		for unit_index: int in range(UNITS.size()):
			var unit: String = UNITS[unit_index]
			var top: int = title + unit_index * block
			sheet.blit_rect(await _text(UNIT_TITLES[unit], Vector2i(label_width, header), 16, BONE, OUTLINE_PURPLE), Rect2i(0, 0, label_width, header), Vector2i(0, top))
			for action_index: int in range(ACTIONS.size()):
				sheet.blit_rect(await _text(str(ACTIONS[action_index]["label"]), Vector2i(CELL.x, header), 18, BONE, OUTLINE_PURPLE), Rect2i(0, 0, CELL.x, header), Vector2i(label_width + action_index * CELL.x, top))
			var row: int = 0
			for set_name: String in SETS:
				for distance: float in DISTANCES:
					var y: int = top + header + row * CELL.y
					sheet.blit_rect(await _text("%s\n%d m\nzoom %dx" % [set_name, int(distance), ZOOM[distance]], Vector2i(label_width, CELL.y), 20), Rect2i(0, 0, label_width, CELL.y), Vector2i(0, y))
					for action_index: int in range(ACTIONS.size()):
						var key: String = "%s|%s|%s|%d|%s" % [treatment, unit, set_name, int(distance), ACTIONS[action_index]["label"]]
						if _cells.has(key):
							sheet.blit_rect(_cells[key], Rect2i(Vector2i.ZERO, CELL), Vector2i(label_width + action_index * CELL.x, y))
					row += 1
		sheet.save_png(_out.path_join("sheets/sheet_%s.png" % treatment))
	for set_name: String in SETS:
		var columns: Array[String] = ["idle", "fire", "death"]
		var title_height: int = 70
		var sheet: Image = Image.create(label_width + CELL.x * columns.size() * TREATMENTS.size(),
			title_height + header * 2 + CELL.y * UNITS.size() * DISTANCES.size(), false, Image.FORMAT_RGB8)
		sheet.fill(INK)
		sheet.blit_rect(await _text("Side by side, %s set: S shipped today  |  A live pixel 3D  |  B baked sprites  |  C hybrid. Same camera per row." % set_name, Vector2i(sheet.get_width(), title_height), 22), Rect2i(0, 0, sheet.get_width(), title_height), Vector2i.ZERO)
		for column_group: int in range(columns.size()):
			var x0: int = label_width + column_group * CELL.x * TREATMENTS.size()
			sheet.blit_rect(await _text(columns[column_group], Vector2i(CELL.x * TREATMENTS.size(), header), 20, BONE, OUTLINE_PURPLE), Rect2i(0, 0, CELL.x * TREATMENTS.size(), header), Vector2i(x0, title_height))
			for treatment_index: int in range(TREATMENTS.size()):
				sheet.blit_rect(await _text(TREATMENTS[treatment_index], Vector2i(CELL.x, header), 20), Rect2i(0, 0, CELL.x, header), Vector2i(x0 + treatment_index * CELL.x, title_height + header))
		var row: int = 0
		for unit: String in UNITS:
			for distance: float in DISTANCES:
				var y: int = title_height + header * 2 + row * CELL.y
				sheet.blit_rect(await _text("%s\n%d m, zoom %dx" % [UNIT_TITLES[unit], int(distance), ZOOM[distance]], Vector2i(label_width, CELL.y), 18), Rect2i(0, 0, label_width, CELL.y), Vector2i(0, y))
				for column_group: int in range(columns.size()):
					for treatment_index: int in range(TREATMENTS.size()):
						var key: String = "%s|%s|%s|%d|%s" % [TREATMENTS[treatment_index], unit, set_name, int(distance), columns[column_group]]
						if _cells.has(key):
							sheet.blit_rect(_cells[key], Rect2i(Vector2i.ZERO, CELL),
								Vector2i(label_width + (column_group * TREATMENTS.size() + treatment_index) * CELL.x, y))
				row += 1
		sheet.save_png(_out.path_join("sheets/compare_%s.png" % set_name))
	await _context_sheet()

func _context_sheet() -> void:
	var tile: Vector2i = Vector2i(640, 360)
	var label_width: int = 210
	var columns: Array[String] = ["light_3_idle", "light_10_fire", "shade_3_idle", "shade_10_fire"]
	var header: int = 44
	var sheet: Image = Image.create(label_width + tile.x * columns.size(), header + tile.y * TREATMENTS.size(), false, Image.FORMAT_RGB8)
	sheet.fill(INK)
	for column: int in range(columns.size()):
		var parts: PackedStringArray = columns[column].split("_")
		var caption: String = "%s set, camera %s m, %s" % [parts[0], "3.5" if parts[1] == "3" else parts[1], parts[2]]
		sheet.blit_rect(await _text(caption, Vector2i(tile.x, header), 18, BONE, OUTLINE_PURPLE), Rect2i(0, 0, tile.x, header), Vector2i(label_width + column * tile.x, 0))
	for row: int in range(TREATMENTS.size()):
		sheet.blit_rect(await _text(TREATMENT_SHORT[TREATMENTS[row]], Vector2i(label_width, tile.y), 18), Rect2i(0, 0, label_width, tile.y), Vector2i(0, header + row * tile.y))
		for column: int in range(columns.size()):
			var parts: PackedStringArray = columns[column].split("_")
			var distance: int = 3 if parts[1] == "3" else 10
			var path: String = _out.path_join("frames/group_%s_%s_%d_%s.png" % [TREATMENTS[row], parts[0], distance, parts[2]])
			var image: Image = Image.load_from_file(path)
			if image == null:
				continue
			image.convert(Image.FORMAT_RGB8)
			image.resize(tile.x, tile.y, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, tile), Vector2i(label_width + column * tile.x, header + row * tile.y))
	sheet.save_png(_out.path_join("sheets/context_groups.png"))
