extends SceneTree

## Bakes every picture of a modelled gun from `client/scripts/gun_model.gd`:
## first-person frames (rest, draw, fire, recover, reload) on the shared held
## canvas, the world pickup / held profile, and the 48x16 kill icon. Each frame
## renders the posed model twice (light, then palette ramp and outline group),
## four samples to a texel, and paints the result onto docs/palette.json ramps
## with a one-texel outline. Needs a real framebuffer (a GPU display):
##
##   godot --path client --rendering-driver vulkan --windowed \
##     --script ../tools/bake_viewmodels.gd -- [--only=Tack] [--preview=DIR]
##
## Writes `res://assets/weapons/<gun>/`. Re-run after any model change and
## inspect the frames in game; a clean bake is not visual acceptance.

const GunModelScript = preload("res://scripts/gun_model.gd")
const BAKE_SHADER: Shader = preload("res://art/models/gun_bake.gdshader")
const KillIcons = preload("res://../tools/bake_kill_icons.gd")
## The held canvas: drawn at two screen pixels a texel on a 1080 line view,
## bottom centre, its lowest 12 px below the edge (hud.gd FP_BOTTOM_OVERLAP).
const CANVAS: Vector2i = Vector2i(384, 240)
const DISPLAY_SCALE: float = 2.0
const SS: int = 4
const KILL_ICON: Vector2i = Vector2i(48, 16)
## Under the game's default 75 degree vertical field.
const SCREEN_HEIGHT: float = 1080.0
const VIEW_FOV: float = 75.0
const CANVAS_CENTRE_BELOW: float = SCREEN_HEIGHT * 0.5 - CANVAS.y * DISPLAY_SCALE * 0.5 + 12.0
const NEAR: float = 0.02
## View-space direction toward the key light: high on the left, as drawn
## sprites light their guns, so top, left and right faces take three tones.
const KEY_LIGHT: Vector3 = Vector3(-0.60, 0.50, 0.60)

var model: GunModel = GunModelScript.new()
var viewport: SubViewport
var camera: Camera3D
var material: ShaderMaterial
var ramp_index: Dictionary[String, int] = {}
var ramp_names: Array[String] = []
var preview_dir: String = ""
var out_root: String = "res://assets/weapons"
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var only: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
		elif argument.begins_with("--preview="):
			preview_dir = argument.trim_prefix("--preview=")
		elif argument.begins_with("--out="):
			out_root = argument.trim_prefix("--out=")
	for key: String in GunModel.RAMPS:
		ramp_index[key] = ramp_names.size()
		ramp_names.append(key)
	_setup()
	for weapon: String in GunModel.GUNS:
		if only != "" and weapon != only:
			continue
		if "--turnaround" in OS.get_cmdline_user_args():
			await _turnaround(weapon)
			continue
		await _bake(weapon)
	if failed:
		push_error("bake_viewmodels: FAILED")
		quit(1)
		return
	print("bake_viewmodels: PASS")
	quit(0)

func _setup() -> void:
	viewport = SubViewport.new()
	viewport.size = CANVAS * SS
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	material = ShaderMaterial.new()
	material.shader = BAKE_SHADER
	material.set_shader_parameter("key_dir", KEY_LIGHT)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--key="):
			var parts: PackedFloat64Array = argument.trim_prefix("--key=").split_floats(",")
			material.set_shader_parameter("key_dir", Vector3(parts[0], parts[1], parts[2]))

# --- Views ----------------------------------------------------------------------

## The held view is drawn the way sprite shooters draw it: the eye sits low
## behind the gun, so its barrel runs into the picture toward a vanishing point
## near the top of the canvas (`vp`, in texels from the top) instead of toward
## the true crosshair far above the canvas. `fov` is the canvas's own vertical
## field. A true off-axis slice of the player's 75 degree view looks straight
## down a long thin slide.
func _held_camera(hold: Dictionary) -> void:
	var height: float = 2.0 * NEAR * tan(deg_to_rad(float(hold.get("fov", 46.0)) * 0.5))
	var above: float = CANVAS.y * 0.5 - float(hold.get("vp", 30.0))
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(height, Vector2(0.0, -above / CANVAS.y * height), NEAR, 4.0)
	camera.transform = Transform3D.IDENTITY

func _side_camera(size: Vector2i, gun: Node3D) -> void:
	var bounds: AABB = _bounds(gun)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH if float(size.x) / size.y < bounds.size.z / maxf(bounds.size.y, 0.001) else Camera3D.KEEP_HEIGHT
	camera.size = bounds.size.z * 1.04 if camera.keep_aspect == Camera3D.KEEP_WIDTH else bounds.size.y * 1.08
	camera.near = 0.01
	camera.far = 4.0
	var centre: Vector3 = bounds.get_center()
	# From the gun's right side, muzzle to image right.
	camera.transform = Transform3D(Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT), centre + Vector3(1.0, 0.0, 0.0))

## Authoring aid: the held model with hands from five orthographic angles,
## painted, into the preview directory.
func _turnaround(weapon: String) -> void:
	var held: Node3D = model.build(weapon, true)
	viewport.add_child(held)
	_dress(held)
	var bounds: AABB = _bounds(held)
	var centre: Vector3 = bounds.get_center()
	var reach: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 1.05
	var views: Dictionary[String, Basis] = {
		"right": Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT),
		"left": Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT),
		"top": Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP),
		"rear": Basis.IDENTITY,
		"front": Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD),
		"under": Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),
	}
	DirAccess.make_dir_recursive_absolute(preview_dir)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = reach
	camera.near = 0.01
	camera.far = 6.0
	for view: String in views:
		camera.transform = Transform3D(views[view], centre + views[view].z * 2.0)
		var image: Image = await _capture(Vector2i(200, 200))
		_save(image, preview_dir.path_join("turn_" + weapon.to_lower() + "_" + view + ".png"))
	held.queue_free()
	await RenderingServer.frame_post_draw

func _bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var box: AABB = node.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

# --- Rendering ------------------------------------------------------------------

## Give every mesh the bake material with its ramp and outline group.
func _dress(gun: Node3D) -> void:
	var groups: Dictionary[String, int] = {}
	for child: Node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		var source: Material = mesh.material_override
		var key: String = str(source.get_meta("finish", "steel")) if source != null else "steel"
		var group: String = str(mesh.get_meta("outline", mesh.name))
		if not groups.has(group):
			groups[group] = groups.size() + 1
		mesh.material_override = material
		mesh.set_instance_shader_parameter("ramp_id", float(ramp_index[key]))
		mesh.set_instance_shader_parameter("part_id", float(groups[group] % 120))
		mesh.set_instance_shader_parameter("glow", float(mesh.get_meta("glow", 0.72 if key in GunModel.SELF_LIT else 0.0)))

func _render(mode: int) -> Image:
	material.set_shader_parameter("mode", mode)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

## Two passes of the posed scene reduced to one canvas of palette texels.
func _capture(size: Vector2i, outline_interior: bool = true) -> Image:
	viewport.size = size * SS
	var light: Image = await _render(0)
	var ids: Image = await _render(1)
	if preview_dir != "" and size == CANVAS and not FileAccess.file_exists(preview_dir.path_join("raw_light.png")):
		DirAccess.make_dir_recursive_absolute(preview_dir)
		light.save_png(preview_dir.path_join("raw_light.png"))
		ids.save_png(preview_dir.path_join("raw_ids.png"))
	return _paint(light, ids, size, outline_interior)

func _paint(light: Image, ids: Image, size: Vector2i, outline_interior: bool) -> Image:
	var lb: PackedByteArray = light.get_data()
	var ib: PackedByteArray = ids.get_data()
	var wide: int = size.x * SS
	var count: int = size.x * size.y
	var ramp: PackedInt32Array = PackedInt32Array()
	var part: PackedInt32Array = PackedInt32Array()
	var lum: PackedFloat32Array = PackedFloat32Array()
	var spec: PackedFloat32Array = PackedFloat32Array()
	var depth: PackedFloat32Array = PackedFloat32Array()
	ramp.resize(count)
	part.resize(count)
	lum.resize(count)
	spec.resize(count)
	depth.resize(count)
	for y: int in range(size.y):
		for x: int in range(size.x):
			var votes: Dictionary[int, int] = {}
			var covered: int = 0
			for sy: int in range(SS):
				for sx: int in range(SS):
					var at: int = ((y * SS + sy) * wide + (x * SS + sx)) * 4
					if ib[at + 3] < 128:
						continue
					covered += 1
					var key: int = roundi(ib[at] / 16.0) * 256 + roundi(ib[at + 1] / 2.0)
					votes[key] = votes.get(key, 0) + 1
			var index: int = y * size.x + x
			if covered * 2 < SS * SS:
				ramp[index] = -1
				continue
			var best: int = -1
			for key: int in votes:
				if best < 0 or votes[key] > votes[best]:
					best = key
			ramp[index] = best / 256
			part[index] = best % 256
			var total: float = 0.0
			var shine: float = 0.0
			var near: float = 1.0
			var n: int = 0
			for sy: int in range(SS):
				for sx: int in range(SS):
					var at: int = ((y * SS + sy) * wide + (x * SS + sx)) * 4
					if ib[at + 3] < 128 or roundi(ib[at] / 16.0) * 256 + roundi(ib[at + 1] / 2.0) != best:
						continue
					total += lb[at] / 255.0
					shine = maxf(shine, lb[at + 1] / 255.0)
					near = minf(near, ib[at + 2] / 255.0)
					n += 1
			lum[index] = total / maxi(n, 1)
			spec[index] = shine
			depth[index] = near
	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in range(size.y):
		for x: int in range(size.x):
			var index: int = y * size.x + x
			if ramp[index] < 0:
				# Outer outline: one dark texel against any painted neighbour.
				var touching: int = -1
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + offset
					if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y and ramp[q.y * size.x + q.x] >= 0:
						touching = ramp[q.y * size.x + q.x]
				if touching >= 0:
					image.set_pixel(x, y, _outline_colour(ramp_names[touching]))
				continue
			var key: String = ramp_names[ramp[index]]
			var colours: Array = GunModel.RAMPS[key]
			var level: int = _level(key, lum[index], spec[index], colours.size(), x, y)
			# A lit rim where the part's upper or left edge meets air or a part
			# behind it, the way a drawn sprite catches its key light.
			if not key in GunModel.SELF_LIT and level > 0:
				for offset: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0)]:
					var q: Vector2i = Vector2i(x, y) + offset
					if q.x < 0 or q.y < 0:
						continue
					var rim: int = q.y * size.x + q.x
					if ramp[rim] < 0 or (part[rim] != part[index] and depth[rim] > depth[index] + 0.004):
						level = mini(level + 1, colours.size() - 1)
						break
			if outline_interior:
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + offset
					if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y:
						continue
					var other: int = q.y * size.x + q.x
					if ramp[other] >= 0 and part[other] != part[index] and depth[other] + 0.004 < depth[index]:
						level = mini(level, _line_level(key))
			image.set_pixel(x, y, colours[level])
	return image

## A two by two ordered offset, so a gradient breaks into a neat checker
## across one band edge instead of a hard contour line.
const DITHER: Array[float] = [-0.10, 0.04, 0.10, -0.04]

func _level(key: String, light: float, shine: float, steps: int, x: int = 0, y: int = 0) -> int:
	if key in GunModel.SELF_LIT:
		return clampi(int((light - 0.55) / 0.45 * steps), 0, steps - 1)
	if key in ["steel", "slide", "blued", "enamel", "brass"] and shine > 0.8:
		return steps - 1
	if light < 0.07:
		return 0
	# Shading spends the ramp above its outline step, darkest to brightest.
	var shaded: float = clampf((light - 0.07) / 0.86, 0.0, 0.999)
	# The brightest step is kept for lit rims and glints, as a drawn sprite
	# keeps its lightest colour for edges rather than whole faces.
	var top: int = steps - 2 if steps >= 4 else steps - 1
	return clampi(1 + int(shaded * top + DITHER[(y % 2) * 2 + x % 2]), 1, top)

func _line_level(key: String) -> int:
	return 1 if key in ["leather", "jacket", "brass", "glow", "flash", "bone"] else 0

func _outline_colour(key: String) -> Color:
	if key in ["glow", "flash"]:
		return Color(0, 0, 0, 0)
	return Color("0a0a0c") if key in ["polymer", "bore"] else Color("1e1e22")

# --- Guns ---------------------------------------------------------------------------

## Where the gun rests in view space and the point it aims at.
const HOLDS: Dictionary[String, Dictionary] = {
	"Tack": {"at": Vector3(0.020, -0.046, -0.500), "aim": Vector3(0.0, 0.0, -30.0), "roll": -4.0, "fov": 16.0, "vp": 24.0, "chunk": Vector3(1.2, 1.1, 1.0)},
	"Scatter": {"at": Vector3(0.036, -0.230, -0.420), "aim": Vector3(0.0, 0.0, -30.0), "roll": -3.0, "fov": 30.0, "vp": 10.0, "reach": 1.2, "tilt_roll": 22.0, "chunk": Vector3(1.7, 1.5, 1.0), "hide": ["Stock", "ButtPad", "RepairPlate"]},
	"Rail": {"at": Vector3(0.036, -0.215, -0.400), "aim": Vector3(0.0, 0.0, -30.0), "roll": -3.0, "fov": 34.0, "vp": 16.0, "reach": 1.2, "tilt_roll": 24.0, "chunk": Vector3(1.4, 1.3, 1.0), "hide": ["Stock"]},
}

func _bake(weapon: String) -> void:
	var directory: String = out_root.path_join(weapon.to_lower())
	var absolute: String = ProjectSettings.globalize_path(directory) if directory.begins_with("res://") else directory
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		push_error("bake_viewmodels: cannot create " + absolute)
		failed = true
		return
	var held: Node3D = model.build(weapon, true)
	viewport.add_child(held)
	_dress(held)
	_held_camera(HOLDS[weapon])
	var frames: Array[Dictionary] = _frames(weapon)
	# Parts that sit behind the eye in first person (a long gun's stock) stay
	# out of the held view. Authoring aid: --hide=NodeA,NodeB leaves more out.
	var hidden: Array = HOLDS[weapon].get("hide", [])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--hide="):
			hidden.append_array(argument.trim_prefix("--hide=").split(","))
	for part: Variant in hidden:
		var node: Node3D = held.find_child(str(part), true, false) as Node3D
		if node != null:
			node.get_parent().remove_child(node)
			node.free()
	for frame: Dictionary in frames:
		_pose(weapon, held, frame)
		var image: Image = await _capture(CANVAS)
		_save(image, absolute.path_join(str(frame["name"]) + ".png"))
	held.queue_free()
	var bare: Node3D = model.build(weapon, false)
	viewport.add_child(bare)
	_dress(bare)
	var profile_size: Vector2i = PROFILE_SIZE[weapon]
	_side_camera(profile_size, bare)
	_save(await _capture(profile_size), absolute.path_join("profile.png"))
	_side_camera(KILL_ICON - Vector2i(2, 2), bare)
	var icon: Image = await _capture(KILL_ICON - Vector2i(2, 2), false)
	_save(KillIcons.glyph(icon), absolute.path_join("kill.png"))
	bare.queue_free()
	await RenderingServer.frame_post_draw

const PROFILE_SIZE: Dictionary[String, Vector2i] = {"Tack": Vector2i(44, 30), "Scatter": Vector2i(92, 22), "Rail": Vector2i(96, 26)}


func _frames(weapon: String) -> Array[Dictionary]:
	match weapon:
		"Tack":
			return [
				{"name": "idle"},
				{"name": "draw_0", "drop": 1.0}, {"name": "draw_1", "drop": 0.55}, {"name": "draw_2", "drop": 0.18},
				{"name": "fire", "slide": 1.0, "trigger": 1.0, "kick": 1.0, "flash": true},
				{"name": "recover_0", "slide": 0.45, "kick": 0.55},
				{"name": "recover_1", "slide": 0.0, "kick": 0.18},
				{"name": "reload_0", "tilt": 0.6, "support": 0.6},
				{"name": "reload_1", "tilt": 1.0, "support": 1.0, "mag": 0.05},
				{"name": "reload_2", "tilt": 1.0, "support": 1.0, "mag": 1.0},
				{"name": "reload_3", "tilt": 1.0, "support": 0.45, "mag": 1.0, "fresh": 0.06},
				{"name": "reload_4", "tilt": 1.0, "support": 0.15, "mag": 0.0},
				{"name": "reload_5", "tilt": 0.8, "slide": 1.0, "support": 0.0},
				{"name": "reload_6", "tilt": 0.3, "slide": 0.0, "support": 0.0},
			]
		"Scatter":
			return [
				{"name": "idle"},
				{"name": "draw_0", "drop": 0.62}, {"name": "draw_1", "drop": 0.36}, {"name": "draw_2", "drop": 0.12},
				{"name": "fire", "kick": 1.0, "flash": true},
				{"name": "recover_0", "kick": 0.6},
				{"name": "recover_1", "kick": 0.2},
				{"name": "reload_0", "tilt": 0.5, "open": 0.45},
				{"name": "reload_1", "tilt": 1.0, "open": 1.0, "eject": 1.0},
				{"name": "reload_2", "tilt": 1.0, "open": 1.0, "shells": 0.0},
				{"name": "reload_3", "tilt": 1.0, "open": 1.0, "shells": 1.0},
				{"name": "reload_4", "tilt": 0.8, "open": 0.35},
				{"name": "reload_5", "tilt": 0.3, "open": 0.0},
			]
		"Rail":
			return [
				{"name": "idle", "charge": 0.75},
				{"name": "draw_0", "drop": 1.0, "charge": 0.62}, {"name": "draw_1", "drop": 0.55, "charge": 0.62}, {"name": "draw_2", "drop": 0.18, "charge": 0.75},
				{"name": "fire", "kick": 1.0, "flash": true, "charge": 1.0},
				{"name": "recover_0", "kick": 0.5, "charge": 0.0},
				{"name": "recover_1", "kick": 0.15, "charge": 0.62},
				{"name": "reload_0", "tilt": 0.5, "charge": 0.62},
				{"name": "reload_1", "tilt": 1.0, "cell": 0.05, "support": 0.6, "charge": 0.0},
				{"name": "reload_2", "tilt": 1.0, "cell": 1.0, "support": 1.0, "charge": 0.0},
				{"name": "reload_3", "tilt": 1.0, "cell": 0.12, "support": 0.5, "charge": 0.0},
				{"name": "reload_4", "tilt": 1.0, "cell": 0.0, "support": 0.2, "charge": 0.0},
				{"name": "reload_5", "tilt": 0.5, "charge": 0.62},
				{"name": "reload_6", "tilt": 0.15, "charge": 0.9},
			]
	return [{"name": "idle"}]

func _pose(weapon: String, gun: Node3D, frame: Dictionary) -> void:
	var hold: Dictionary = HOLDS[weapon]
	var at: Vector3 = hold["at"]
	var aim: Vector3 = hold["aim"]
	var drop: float = float(frame.get("drop", 0.0))
	var kick: float = float(frame.get("kick", 0.0))
	var tilt: float = float(frame.get("tilt", 0.0))
	var place: Transform3D = Transform3D.IDENTITY.looking_at(aim - at, Vector3.UP)
	place.origin = at
	# Draw: rise from below the frame, muzzle low, rolled in.
	place = place.rotated_local(Vector3.RIGHT, deg_to_rad(-22.0 * drop + 7.0 * kick + 16.0 * tilt))
	place = place.rotated_local(Vector3.FORWARD, deg_to_rad(float(hold["roll"]) + 30.0 * drop + float(hold.get("tilt_roll", 38.0)) * tilt))
	place.origin += Vector3(0.012 * drop - 0.010 * tilt, -0.085 * drop + 0.004 * kick + 0.010 * tilt, 0.018 * kick) * float(hold.get("reach", 1.0))
	# Held guns are drawn chunkier across than they are long, the way sprite
	# shooters exaggerate a held silhouette; the profile and pickup keep true
	# proportions.
	place.basis = place.basis * Basis.from_scale(hold.get("chunk", Vector3.ONE))
	gun.transform = place
	match weapon:
		"Tack":
			GunModel.pose_tack(gun, float(frame.get("slide", 0.0)), float(frame.get("mag", 0.0)), float(frame.get("trigger", 0.0)))
			GunModel.carry_magazine(gun, float(frame.get("fresh", -1.0)))
		"Scatter":
			GunModel.pose_scatter(gun, float(frame.get("open", 0.0)), float(frame.get("shells", 1.0)), float(frame.get("eject", 0.0)))
		"Rail":
			GunModel.pose_rail(gun, float(frame.get("cell", 0.0)))
			var charge: float = float(frame.get("charge", 0.75))
			for node: Node in gun.find_children("Charge*", "MeshInstance3D", true, false):
				(node as MeshInstance3D).visible = charge > 0.0
				(node as MeshInstance3D).set_instance_shader_parameter("glow", charge)
	var support: Node3D = gun.find_child("SupportHand", true, false) as Node3D
	if support != null:
		var away: float = float(frame.get("support", 0.0))
		support.position += Vector3(-0.03, -0.16, 0.06) * away
	var flash: Node3D = gun.find_child("Flash", true, false) as Node3D
	if flash != null:
		flash.visible = bool(frame.get("flash", false))

func _save(image: Image, path: String) -> void:
	if image.save_png(path) != OK:
		push_error("bake_viewmodels: cannot write " + path)
		failed = true
		return
	if preview_dir != "":
		var big: Image = image.duplicate()
		big.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_NEAREST)
		DirAccess.make_dir_recursive_absolute(preview_dir)
		big.save_png(preview_dir.path_join(path.get_base_dir().get_file() + "_" + path.get_file()))
