extends SceneTree

## Offline review renders for prepared model candidates. Needs a real renderer:
## launch windowed (not --headless), with --audio-driver Dummy.
## For each candidate: a turnaround strip (raw source 3/4, prepared 3/4, front,
## right, back, left) under neutral light, and one shot at gameplay distance from
## eye height inside the target map, built by ArenaCover and lit by ArenaSky's
## preset for that map. Selects nothing at runtime.
##
## godot --audio-driver Dummy --path client --script ../tools/render_model_candidates.gd -- \
##   <catalog.json> <raw dir> <prepared dir> <image dir> [exact candidate id]

const TILE: int = 360
const SHOT: Vector2i = Vector2i(1280, 720)
const KEY_TRANSFORM: Transform3D = Transform3D(Basis(Vector3(0.866025, 0, -0.5), Vector3(-0.353553, 0.707107, -0.612372), Vector3(0.353553, 0.707107, 0.612372)), Vector3(8, 22, 10))

var _rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4 or args.size() > 5 or DirAccess.make_dir_recursive_absolute(args[3]) != OK:
		_fail("require catalog, raw directory, prepared directory, image directory and optional id")
		return
	if RenderingServer.get_current_rendering_method() == "dummy":
		_fail("a real renderer is required; launch windowed")
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not catalog is Dictionary:
		_fail("invalid catalog")
		return
	var repo: String = ProjectSettings.globalize_path("res://..")
	for entry: Dictionary in catalog["candidates"]:
		if args.size() == 5 and entry["id"] != args[4]:
			continue
		var raw: Node3D = _load(args[1].path_join(entry["file"]))
		var prepared: Node3D = _load(args[2].path_join(entry["id"] + ".glb"))
		if raw == null or prepared == null:
			_fail("cannot load candidate " + entry["id"])
			return
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[2].path_join(entry["id"] + ".glb.json")))
		var strip: Image = await _turnaround(raw, prepared)
		var shot: Dictionary = await _in_context(repo, entry, prepared, receipt)
		raw.free()
		prepared.free()
		if strip == null or shot.is_empty():
			_fail("render failed for " + entry["id"])
			return
		if strip.save_png(args[3].path_join(entry["id"] + "-turn.png")) != OK or (shot["image"] as Image).save_png(args[3].path_join(entry["id"] + "-context.png")) != OK:
			_fail("cannot save renders")
			return
		shot.erase("image")
		shot["id"] = entry["id"]
		_rows.append(shot)
		print("rendered %s in %s (%s, camera %.1f m)" % [entry["id"], entry["map"], shot["lighting"], shot["camera_distance_m"]])
	var file: FileAccess = FileAccess.open(args[3].path_join("renders.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write render receipt")
		return
	file.store_string(JSON.stringify({"schema": 1, "renderer": RenderingServer.get_current_rendering_method(), "shots": _rows}, "\t") + "\n")
	file.close()
	print("render_model_candidates: PASS (%d candidates rendered; looking at them is the review)" % _rows.size())
	quit(0)

func _load(path: String) -> Node3D:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	return document.generate_scene(state)

func _bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _viewport(size: Vector2i) -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	root.add_child(viewport)
	return viewport

func _turnaround(raw: Node3D, prepared: Node3D) -> Image:
	var strip: Image = Image.create(TILE * 6, TILE, false, Image.FORMAT_RGBA8)
	var views: Array[Array] = [[raw, 35.0, -22.0], [prepared, 35.0, -22.0], [prepared, 0.0, -8.0], [prepared, 90.0, -8.0], [prepared, 180.0, -8.0], [prepared, 270.0, -8.0]]
	for index: int in range(views.size()):
		var viewport: SubViewport = _viewport(Vector2i(TILE, TILE))
		var world: WorldEnvironment = WorldEnvironment.new()
		var environment: Environment = Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("6b6f73")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("c8c8c8")
		environment.ambient_light_energy = 0.55
		world.environment = environment
		viewport.add_child(world)
		for spec: Vector3 in [Vector3(-40, -35, 1.4), Vector3(-15, 150, 0.6)]:
			var light: DirectionalLight3D = DirectionalLight3D.new()
			light.rotation_degrees = Vector3(spec.x, spec.y, 0)
			light.light_energy = spec.z
			viewport.add_child(light)
		var model: Node3D = views[index][0]
		viewport.add_child(model)
		var box: AABB = _bounds(model)
		var centre: Vector3 = box.get_center()
		var radius: float = box.size.length() * 0.5
		var camera: Camera3D = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = radius * 2.1
		camera.near = 0.01
		camera.far = radius * 10.0
		var direction: Vector3 = Basis.from_euler(Vector3(deg_to_rad(views[index][2]), deg_to_rad(views[index][1]), 0)) * Vector3(0, 0, 1)
		viewport.add_child(camera)
		camera.look_at_from_position(centre + direction * radius * 4.0, centre, Vector3.UP)
		camera.make_current()
		for frame: int in range(3):
			await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(image, Rect2i(0, 0, TILE, TILE), Vector2i(index * TILE, 0))
		viewport.remove_child(model)
		viewport.queue_free()
	await process_frame
	return strip

func _map_info(repo: String, map_name: String) -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(repo.path_join("server/maps/%s.json" % map_name)))
	if not source is Dictionary:
		return {}
	var solids: Array = []
	var surfaces: Array = []
	var index_of: Dictionary = {}
	for solid: Dictionary in source["solids"]:
		index_of[solid["id"]] = solids.size()
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2], "bottom": solid["min"][1], "top": solid["max"][1]})
		surfaces.append(solid.get("surface", "concrete"))
	var decorations: Array = []
	for detail: Dictionary in source.get("decorations", []):
		if index_of.has(detail.get("solid")):
			var copy: Dictionary = detail.duplicate(true)
			copy["solid"] = index_of[detail["solid"]]
			decorations.append(copy)
	var info: Dictionary = {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"], "half_extent": source["half_extent"], "solids": solids,
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": decorations}}
	if MapGeometry.validation_error(info) != "":
		info["presentation"]["decorations"] = []
	if MapGeometry.validation_error(info) != "":
		info.erase("presentation")
	info["_source"] = source
	return info

func _in_context(repo: String, entry: Dictionary, prepared: Node3D, receipt: Dictionary) -> Dictionary:
	var info: Dictionary = _map_info(repo, entry["map"])
	if info.is_empty():
		return {}
	var source: Dictionary = info["_source"]
	info.erase("_source")
	var viewport: SubViewport = _viewport(SHOT)
	viewport.positional_shadow_atlas_size = 2048
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var cover: ArenaCover = ArenaCover.new()
	world.add_child(cover)
	cover.apply_map_info(info)
	var preset: ArenaSky.Preset = ArenaSky.preset_for(info["map_name"])
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = ArenaSky.build_environment(info["map_name"])
	world.add_child(environment)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.transform = KEY_TRANSFORM
	key.light_color = preset.key_color
	key.light_energy = preset.key_energy
	key.visible = preset.key_energy > 0.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 80.0
	world.add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(0, 12, 0)
	fill.light_color = Color(0.55, 0.62, 0.68)
	fill.light_energy = preset.scene_fill_energy
	fill.omni_range = 70.0
	fill.omni_attenuation = 0.8
	fill.visible = preset.scene_fill_energy > 0.0
	world.add_child(fill)
	var slot_boxes: Array[AABB] = []
	for solid: Dictionary in source["solids"]:
		if entry.get("slot") is Array and solid["id"] in entry["slot"]:
			slot_boxes.append(AABB(Vector3(solid["min"][0], solid["min"][1], solid["min"][2]), Vector3(solid["max"][0] - solid["min"][0], solid["max"][1] - solid["min"][1], solid["max"][2] - solid["min"][2])))
	var feet: Vector3
	if not slot_boxes.is_empty():
		var union: AABB = slot_boxes[0]
		for box: AABB in slot_boxes:
			union = union.merge(box)
		feet = Vector3(union.get_center().x, union.position.y, union.get_center().z)
	elif entry.get("place") is Array:
		feet = Vector3(entry["place"][0], entry["place"][1], entry["place"][2])
	else:
		for landmark: Dictionary in source["landmarks"]:
			if landmark["id"] == entry["place"]:
				feet = Vector3(landmark["feet"][0], landmark["feet"][1], landmark["feet"][2])
	feet.y += float(entry.get("lift", 0.0))
	var hidden: int = 0
	for node: Node in cover.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		for slot: AABB in slot_boxes:
			if box.position.distance_to(slot.position) < 0.06 and box.end.distance_to(slot.end) < 0.06:
				mesh.visible = false
				hidden += 1
	prepared.position = feet
	world.add_child(prepared)
	var box: AABB = _bounds(prepared)
	box.position += feet
	var target: Vector3 = box.get_center()
	var longest: float = box.get_longest_axis_size()
	var distance: float = 12.0 if entry["faction"] == "inheritance" else clampf(longest * 2.2, 4.0, 16.0)
	var floor_y: float = feet.y - float(entry.get("lift", 0.0))
	var blockers: Array[AABB] = []
	for solid: Dictionary in source["solids"]:
		if entry.get("slot") is Array and solid["id"] in entry["slot"]:
			continue
		blockers.append(AABB(Vector3(solid["min"][0], solid["min"][1], solid["min"][2]), Vector3(solid["max"][0] - solid["min"][0], solid["max"][1] - solid["min"][1], solid["max"][2] - solid["min"][2])))
	var chosen: Vector3 = Vector3.INF
	var used: float = distance
	var half: float = float(source["half_extent"]) - 0.5
	while chosen == Vector3.INF and used >= 2.5:
		for yaw: float in [35.0, -35.0, 145.0, -145.0, 90.0, -90.0, 0.0, 180.0]:
			var offset: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, used)
			var eye: Vector3 = Vector3(target.x + offset.x, floor_y + 1.6, target.z + offset.z)
			if absf(eye.x) > half or absf(eye.z) > half:
				continue
			var clear: bool = true
			for blocker: AABB in blockers:
				if blocker.grow(0.25).has_point(eye) or blocker.intersects_segment(eye, target):
					clear = false
					break
			if clear:
				chosen = eye
				break
		if chosen == Vector3.INF:
			used *= 0.75
	var obstructed: bool = chosen == Vector3.INF
	if obstructed:
		used = distance
		chosen = Vector3(target.x, floor_y + 1.6, target.z + distance)
	var scale_figure: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.8
	scale_figure.mesh = capsule
	var figure_material: StandardMaterial3D = StandardMaterial3D.new()
	figure_material.albedo_color = Color("3a2a48")
	scale_figure.material_override = figure_material
	var side: Vector3 = (chosen - target)
	side.y = 0.0
	side = side.normalized().cross(Vector3.UP)
	scale_figure.position = Vector3(feet.x, floor_y, feet.z) + side * (maxf(box.size.x, box.size.z) * 0.5 + 0.7) + Vector3(0, 0.9, 0)
	world.add_child(scale_figure)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 400.0
	world.add_child(camera)
	camera.look_at_from_position(chosen, target, Vector3.UP)
	camera.make_current()
	for frame: int in range(5):
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	world.remove_child(prepared)
	viewport.queue_free()
	await process_frame
	return {"image": image, "map": entry["map"], "map_name": info["map_name"], "lighting": "ArenaSky preset for '%s'" % info["map_name"], "proxy_level": bool(entry.get("proxy", false)),
		"feet": [feet.x, feet.y, feet.z], "camera": [chosen.x, chosen.y, chosen.z], "camera_distance_m": chosen.distance_to(target), "eye_height_m": 1.6, "fov": 75.0,
		"slot_solids_hidden": hidden, "view_obstructed": obstructed, "presentation_kept": info.has("presentation"), "scale_figure_m": 1.8}

func _fail(message: String) -> void:
	push_error("render_model_candidates: " + message)
	quit(1)
