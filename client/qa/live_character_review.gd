extends SceneTree

## Controlled accepted-state presentation fixtures. No game or combat authority.
const CharacterView = preload("res://scripts/skinned_character.gd")
var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _lights: Array[DirectionalLight3D] = []
var _out: String
var _rows: Array[Dictionary] = []
var _failures: PackedStringArray = []
var _sheet: Image
var _sheet_index: int = 0
var _floor: MeshInstance3D
var _pitch_controls: Array[Dictionary] = []
var _first_person_controls: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("live_character_review: require absolute output directory")
		quit(1)
		return
	_out = args[0]
	AudioServer.set_bus_mute(0, true)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1024, 768)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("222831")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("c1c8cd")
	world.environment = _environment
	_viewport.add_child(world)
	for angles: Vector2 in [Vector2(-35, -35), Vector2(-20, 145)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(angles.x, angles.y, 0)
		_viewport.add_child(light)
		_lights.append(light)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	floor_mesh.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color("353e45")
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	floor_mesh.layers = ArenaSky.WORLD_LAYERS
	_viewport.add_child(floor_mesh)
	_floor = floor_mesh
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.15
	_viewport.add_child(_camera)
	_sheet = Image.create(256 * 8, 192 * 8, false, Image.FORMAT_RGB8)
	for kind: String in ["human", "synthetic"]:
		await _pawn_views(kind)
	await _tern_views()
	_expect(_sheet.save_png(_out.path_join("overview.png")) == OK, "overview saved")
	var sources: Dictionary = {}
	for kind: String in CharacterView.SOURCES:
		sources[kind] = {"path": CharacterView.SOURCES[kind], "sha256": FileAccess.get_sha256(CharacterView.SOURCES[kind])}
	var scripts: Dictionary = {}
	for path: String in ["res://scripts/skinned_character.gd", "res://scripts/player_pawn.gd", "res://scripts/latch_source.gd",
		"res://assets/models/character_support.json", "res://qa/live_character_review.gd"]:
		scripts[path] = FileAccess.get_sha256(path)
	var file: FileAccess = FileAccess.open(_out.path_join("review.json"), FileAccess.WRITE)
	if file == null:
		_failures.append("cannot write review receipt")
	else:
		file.store_string(JSON.stringify({"schema": 1, "scope": "Controlled accepted-state fixtures, no network play or outcome authority",
			"renderer": RenderingServer.get_current_rendering_method(), "video_adapter": RenderingServer.get_video_adapter_name(),
			"sources": sources, "scripts": scripts, "frames": _rows,
			"visible_pitch_controls": _pitch_controls, "first_person_controls": _first_person_controls,
			"overview_sha256": FileAccess.get_sha256(_out.path_join("overview.png")), "failures": _failures}, "\t") + "\n")
		file.close()
	_viewport.free()
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("live_character_review: " + failure)
		quit(1)
		return
	print("live_character_review: PASS (actual pawn skins, angle/light/motion, crouch, seats, fall/respawn, wrist anchor and full first-person hiding)")
	quit(0)

func _pawn_views(kind: String) -> void:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
	_viewport.add_child(pawn)
	pawn.set_process(false)
	pawn.nameplate_enabled = false
	pawn.set_player_data("review-" + kind, kind.capitalize())
	var state: Dictionary = {"x": 0.0, "y": 1.5, "z": 0.0, "yaw": PI * 0.5,
		"hp": 100, "weapon": "Tack", "body": kind, "ducking": false}
	pawn.update_state(state, 1)
	pawn.snap_authoritative_position()
	pawn._process(0.05)
	if pawn.character_view == null:
		_failures.append("actual pawn live source missing " + kind)
		pawn.free()
		return
	for lighting: String in ["neutral", "dim"]:
		_light(lighting)
		for angle: int in range(3):
			_angle(angle)
			pawn._attach_carried()
			await _capture("%s_%s_idle_%d" % [kind, lighting, angle], pawn.character_view)
	_light("neutral")
	_camera.position = Vector3(3.0, 1.12, 3.0)
	_camera.look_at(Vector3(0, 0.90, 0))
	var walk_strip: Image = Image.create(256 * 8, 192, false, Image.FORMAT_RGB8)
	for phase: int in range(8):
		pawn.character_view.pose(float(phase) / 8.0, true, true, false)
		pawn._attach_carried()
		var picture: Image = await _capture("%s_walk_%d" % [kind, phase], pawn.character_view)
		var cell: Image = picture.duplicate()
		cell.convert(Image.FORMAT_RGB8)
		cell.resize(256, 192, Image.INTERPOLATE_LANCZOS)
		walk_strip.blit_rect(cell, Rect2i(0, 0, 256, 192), Vector2i(phase * 256, 0))
	_save_strip(kind + "_walk_strip.png", walk_strip, kind)
	state.ducking = true
	pawn.update_state(state, 2)
	pawn._process(0.05)
	await _capture(kind + "_crouch", pawn.character_view)
	pawn.vehicle_seated = true
	pawn._process(0.05)
	_expect(not pawn._held_root.visible, "driver carried firearm hidden " + kind)
	await _capture(kind + "_driver", pawn.character_view)
	state.ducking = false
	pawn.update_state(state, 3)
	pawn._process(0.05)
	await _capture(kind + "_gunner", pawn.character_view)
	pawn.vehicle_seated = false
	state.hp = 0
	pawn.update_state(state, 4)
	pawn._process(0.4)
	_expect(not pawn.weapon_sprite.is_visible_in_tree(), "fallen carried firearm hidden " + kind)
	await _capture(kind + "_fallen", pawn.character_view)
	state.hp = 100
	pawn.update_state(state, 5)
	pawn._process(0.05)
	_expect(absf(pawn.character_view.source_body.rotation.x) < 0.0001, "respawn upright " + kind)
	await _capture(kind + "_respawn", pawn.character_view)
	for pitch: float in [-ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT]:
		state.pitch = pitch
		pawn.update_state(state)
		pawn.set_predicted_position(Vector3(0, 1.5, 0), 0.0)
		pawn._process(0.05)
		await _capture(kind + ("_aim_down" if pitch < 0.0 else "_aim_up"), pawn.character_view)
	state.pitch = 0.0
	pawn.update_state(state)
	pawn._process(0.05)
	await _visible_pitch(pawn, state, kind)
	_camera.size = 0.8
	var wrist: Vector3 = pawn.to_global(pawn._held_root.position)
	_camera.position = wrist + Vector3(2.0, 0.15, 2.0)
	_camera.look_at(wrist + Vector3(0.0, 0.05, 0.12))
	pawn._attach_carried()
	var expected: Vector3 = pawn.character_view.to_global(pawn.character_view.hand_transform().origin)
	_expect(wrist.distance_to(expected) < 0.0001, "actual carried root at weighted wrist " + kind)
	await _capture(kind + "_carried_anchor", pawn.character_view, false)
	_angle(0)
	pawn.visible = false
	var empty: Image = await _capture(kind + "_empty_control", null, false)
	pawn.visible = true
	pawn.set_local_fp(true)
	pawn.show_muzzle_flash("Tack")
	var hidden: Image = await _capture(kind + "_first_person_hidden", null, false)
	_expect(not pawn.character_view.visible and not pawn._held_root.visible and not pawn.body.visible,
		"full local body and attachments hidden " + kind)
	_expect(empty.get_data() == hidden.get_data(), "first-person pixels equal actual empty control " + kind)
	_first_person_controls.append({"kind": kind, "pixels_compared": empty.get_width() * empty.get_height(),
		"all_image_bytes_equal": empty.get_data() == hidden.get_data(), "with_muzzle_feedback_requested": true})
	pawn.cancel_fire_feedback()
	pawn.set_local_fp(false)
	pawn.free()
	await process_frame

func _visible_pitch(pawn: Node3D, state: Dictionary, kind: String) -> void:
	# Measure actual rasterized profile rotation, not only the parent transform.
	# The retained fixed-Y negative control has the correct parent gun direction
	# while keeping its painted barrel horizontal at extreme accepted pitch.
	pawn.character_view.visible = false
	_floor.visible = false
	_camera.size = 0.8
	var baseline: float = 0.0
	for fixed_y_control: bool in [true, false]:
		for pitch: float in [0.0, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT]:
			state.pitch = pitch
			pawn.update_state(state)
			pawn.set_predicted_position(Vector3(0, 1.5, 0), 0.0)
			pawn._process(0.05)
			var wrist: Vector3 = pawn.to_global(pawn._held_root.position)
			_camera.position = wrist + Vector3(3, 0, 0)
			_camera.look_at(wrist)
			pawn._attach_carried()
			if fixed_y_control:
				pawn.weapon_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			pawn.visible = false
			await process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var empty: Image = _viewport.get_texture().get_image()
			pawn.visible = true
			var suffix: String = "zero" if pitch == 0.0 else ("down" if pitch < 0.0 else "up")
			var label: String = "%s_pitch_%s_%s" % [kind, "fixed_y_control" if fixed_y_control else "actual", suffix]
			var picture: Image = await _capture(label, null, false)
			var axis: Dictionary = _pixel_axis(picture, empty)
			_expect(axis.pixels > 80 and axis.anisotropy > 1.1, "visible profile has measurable axis " + label)
			if pitch == 0.0:
				baseline = axis.angle
			var rotation: float = absf(wrapf(float(axis.angle) - baseline, -PI * 0.5, PI * 0.5))
			if pitch != 0.0:
				_expect(rotation < deg_to_rad(5) if fixed_y_control else absf(rotation - absf(pitch)) < deg_to_rad(5),
					"fixed-Y witness stays horizontal" if fixed_y_control else "visible actual profile follows extreme pitch " + label)
			_pitch_controls.append({"file": label + ".png", "kind": kind, "accepted_pitch_degrees": rad_to_deg(pitch),
				"negative_control_fixed_y": fixed_y_control, "profile_pixels": axis.pixels,
				"principal_axis_degrees": rad_to_deg(float(axis.angle)), "rotation_from_zero_degrees": rad_to_deg(rotation),
				"axis_anisotropy": axis.anisotropy})
	pawn.character_view.visible = true
	_floor.visible = true
	state.pitch = 0.0
	pawn.update_state(state)
	pawn._process(0.05)

func _pixel_axis(picture: Image, empty: Image) -> Dictionary:
	var count: int = 0
	var sum: Vector2 = Vector2.ZERO
	var square: Vector2 = Vector2.ZERO
	var product: float = 0.0
	for y: int in range(picture.get_height()):
		for x: int in range(picture.get_width()):
			var a: Color = picture.get_pixel(x, y)
			var b: Color = empty.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= 0.02:
				continue
			count += 1
			sum += Vector2(x, y)
			square += Vector2(float(x) * x, float(y) * y)
			product += float(x) * y
	if count == 0:
		return {"pixels": 0, "angle": 0.0, "anisotropy": 0.0}
	var xx: float = square.x / count - pow(sum.x / count, 2)
	var yy: float = square.y / count - pow(sum.y / count, 2)
	var xy: float = product / count - sum.x * sum.y / (float(count) * count)
	var spread: float = sqrt(pow(xx - yy, 2) + 4.0 * xy * xy)
	return {"pixels": count, "angle": 0.5 * atan2(2.0 * xy, xx - yy),
		"anisotropy": (xx + yy + spread) / maxf(0.0001, xx + yy - spread)}

func _tern_views() -> void:
	var tern: Node3D = CharacterView.new()
	_viewport.add_child(tern)
	if not tern.configure("tern"):
		_failures.append("Tern live source unavailable")
		tern.free()
		return
	for lighting: String in ["neutral", "dim"]:
		_light(lighting)
		for angle: int in range(3):
			_angle(angle)
			await _capture("tern_%s_idle_%d" % [lighting, angle], tern)
	_light("neutral")
	_camera.position = Vector3(3.0, 1.12, 3.0)
	_camera.look_at(Vector3(0, 0.90, 0))
	var walk_strip: Image = Image.create(256 * 8, 192, false, Image.FORMAT_RGB8)
	for phase: int in range(8):
		tern.pose(float(phase) / 8.0, true, false, false)
		var picture: Image = await _capture("tern_walk_%d" % phase, tern)
		var cell: Image = picture.duplicate()
		cell.convert(Image.FORMAT_RGB8)
		cell.resize(256, 192, Image.INTERPOLATE_LANCZOS)
		walk_strip.blit_rect(cell, Rect2i(0, 0, 256, 192), Vector2i(phase * 256, 0))
	_save_strip("tern_walk_strip.png", walk_strip, "tern")
	tern.free()

func _save_strip(filename: String, strip: Image, kind: String) -> void:
	var path: String = _out.path_join(filename)
	_expect(strip.save_png(path) == OK, "actual walking strip saved " + kind)
	_rows.append({"file": filename, "sha256": FileAccess.get_sha256(path), "figure_kind": kind, "sampled_motion_strip": true})

func _light(lighting: String) -> void:
	_environment.ambient_light_energy = 0.55 if lighting == "neutral" else 0.16
	_lights[0].light_energy = 1.6 if lighting == "neutral" else 0.35
	_lights[1].light_energy = 0.7 if lighting == "neutral" else 0.12

func _angle(angle: int) -> void:
	_camera.size = 2.15
	_camera.position = Vector3(sin(angle * PI * 0.5 + 0.15) * 4.0, 1.12, cos(angle * PI * 0.5 + 0.15) * 4.0)
	_camera.look_at(Vector3(0, 0.90, 0))

func _capture(label: String, figure: Node3D, in_sheet: bool = true) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	var path: String = _out.path_join(label + ".png")
	_expect(picture != null and not picture.is_empty() and picture.save_png(path) == OK, "actual saved frame " + label)
	_rows.append({"file": label + ".png", "sha256": FileAccess.get_sha256(path),
		"figure_kind": str(figure.kind) if figure != null else "empty/hidden control"})
	if in_sheet:
		var thumb: Image = picture.duplicate()
		thumb.convert(Image.FORMAT_RGB8)
		thumb.resize(256, 192, Image.INTERPOLATE_LANCZOS)
		_sheet.blit_rect(thumb, Rect2i(0, 0, 256, 192), Vector2i((_sheet_index % 8) * 256, int(_sheet_index / 8) * 192))
		_sheet_index += 1
	return picture

func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
