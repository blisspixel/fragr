extends SceneTree

## Offline lit library preview. No server, authored map or playable Mars claim.
const Library = preload("res://scripts/offworld_materials.gd")
const OUTPUT: String = "res://art/environment/offworld-batch-20261001/material_preview.png"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("offworld preview requires a real renderer")
		quit(1)
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("1e1e22")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e8e2d6")
	world.environment.ambient_light_energy = 0.35
	viewport.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 0.85
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 21.0
	camera.position = Vector3(0.0, 7.0, 15.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.6, 0.0))
	camera.current = true
	for index: int in range(Library.IDS.size()):
		var material: StandardMaterial3D = Library.make(Library.IDS[index])
		if material == null:
			push_error("offworld preview cannot load " + Library.IDS[index])
			viewport.queue_free()
			await process_frame
			quit(1)
			return
		# One full tile on each labelled slab. This material board deliberately
		# exposes all pixels, rather than claiming a future world texel density.
		var slab: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(3.5, 2.6, 0.25)
		slab.mesh = box
		slab.material_override = material
		slab.position = Vector3(float(index - 2) * 3.9, 1.3, 0.0)
		viewport.add_child(slab)
		var floor: MeshInstance3D = MeshInstance3D.new()
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(3.5, 3.5)
		floor.mesh = plane
		floor.material_override = material
		floor.position = Vector3(slab.position.x, 0.0, 1.8)
		viewport.add_child(floor)
	var overlay: CanvasLayer = CanvasLayer.new()
	viewport.add_child(overlay)
	var title: Label = Label.new()
	title.text = "OFFWORLD MATERIAL LIBRARY"
	title.position = Vector2(32.0, 22.0)
	title.add_theme_color_override("font_color", Color("e8e2d6"))
	title.add_theme_font_size_override("font_size", 28)
	overlay.add_child(title)
	var note: Label = Label.new()
	note.text = "Lit material slabs and floors. Mars missions remain unbuilt."
	note.position = Vector2(32.0, 60.0)
	note.add_theme_color_override("font_color", Color("8c847a"))
	note.add_theme_font_size_override("font_size", 18)
	overlay.add_child(note)
	var names: Array[String] = ["BASALT", "REGOLITH", "PRESSURE HABITAT", "MINING DECK", "THERMAL CERAMIC"]
	for index: int in range(names.size()):
		var label: Label = Label.new()
		label.text = names[index]
		label.position = Vector2(30.0 + float(index) * 246.0, 622.0)
		label.size = Vector2(232.0, 28.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color("e8e2d6"))
		label.add_theme_font_size_override("font_size", 18)
		overlay.add_child(label)
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var saved: Error = image.save_png(ProjectSettings.globalize_path(OUTPUT))
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	if saved != OK:
		push_error("offworld preview cannot save frame")
		quit(1)
		return
	print("offworld material preview: PASS five lit library samples, no gameplay authority or Mars map")
	quit()
