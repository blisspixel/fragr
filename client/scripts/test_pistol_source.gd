extends SceneTree

const Source = preload("res://art/models/pistol_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_pistol_source: " + message)

func _run() -> void:
	var source: RefCounted = Source.new()
	var gun: Node3D = source.build(true)
	root.add_child(gun)
	var counts: Dictionary[String, int] = {"Body":2685, "Slide":1985, "Trigger":176, "Hammer":308}
	for name: String in counts:
		var mesh: MeshInstance3D = gun.get_node(name + "/" + name + "Mesh") as MeshInstance3D
		_check(mesh.mesh.get_faces().size() / 3 == counts[name], "preserved " + name + " topology")
		var material: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
		_check(material.albedo_texture.get_width() == 1024 and material.normal_texture.get_width() == 1024,
			name + " embeds bounded 1K maps")
		_check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, name + " samples nearest pixels")
	var source_bounds: AABB
	var bounded: bool = false
	for name: String in counts:
		var mesh: MeshInstance3D = gun.get_node(name + "/" + name + "Mesh") as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		source_bounds = source_bounds.merge(box) if bounded else box
		bounded = true
	_check(absf(source_bounds.size.z - 0.24) < 0.0001 and source_bounds.size.y > 0.19
		and source_bounds.size.y < 0.21 and source_bounds.size.x < 0.05,
		"preserved civilian sidearm remains 24 cm long, 20 cm high and under 5 cm wide")
	var blade: MeshInstance3D = gun.get_node("Trigger/CurvedBlade") as MeshInstance3D
	var guide: MeshInstance3D = gun.get_node("Body/SpringGuide") as MeshInstance3D
	_check(blade.mesh.get_faces().size() / 3 == 60 and guide.mesh.get_faces().size() / 3 == 120,
		"authored trigger and guide counts remain separate")
	var body: Node3D = gun.get_node("Body") as Node3D
	var body_rest: Transform3D = body.transform
	var fixed_guide: Transform3D = guide.transform
	var slide: Node3D = gun.get_node("Slide") as Node3D
	var slide_rest: Transform3D = slide.transform
	var trigger: Node3D = gun.get_node("Trigger") as Node3D
	var hammer: Node3D = gun.get_node("Hammer") as Node3D
	var trigger_rest: Transform3D = trigger.transform
	var hammer_rest: Transform3D = hammer.transform
	var glove: Node3D = gun.get_node("TriggerHand") as Node3D
	var support: Node3D = gun.get_node("SupportHand") as Node3D
	var hand_rest: Transform3D = glove.transform
	var support_rest: Transform3D = support.transform
	for hand: Node3D in [glove, support]:
		for piece: Node in hand.get_children():
			if piece is MeshInstance3D:
				var shape: MeshInstance3D = piece as MeshInstance3D
				var box: AABB = shape.global_transform * shape.get_aabb()
				_check(box.end.y < -0.035, "glove stays below moving slide and sight line")
	var muzzle: Node3D = gun.get_node("Muzzle") as Node3D
	var muzzle_rest: Transform3D = muzzle.transform
	_check(muzzle.position.z < -0.17 and absf(muzzle.position.x) < 0.002 and absf(muzzle.position.y) < 0.005,
		"actual muzzle remains aligned with the reviewed bore")
	var maximum: float = 0.0
	for index: int in range(31):
		source.pose(gun, index / 100.0)
		maximum = maxf(maximum, slide.position.distance_to(slide_rest.origin))
		_check(body.transform == body_rest and guide.transform == fixed_guide and muzzle.transform == muzzle_rest,
			"receiver, spring guide and bore stay fixed inside the recoiling gun")
		_check(glove.transform == hand_rest and support.transform == support_rest,
			"gloves retain receiver contact through independent slide motion")
	_check(is_equal_approx(maximum, 0.012), "mechanism has a measured twelve-millimetre stroke")
	source.pose(gun, 0.06)
	_check(not trigger.transform.is_equal_approx(trigger_rest) and not hammer.transform.is_equal_approx(hammer_rest),
		"trigger and hammer independently move during the shot")
	for invalid: float in [-1.0, INF, NAN, 0.25, 1.0]:
		source.pose(gun, invalid)
		_check(slide.transform.is_equal_approx(slide_rest) and trigger.transform.is_equal_approx(trigger_rest)
			and hammer.transform.is_equal_approx(hammer_rest) and gun.transform.is_equal_approx(Transform3D.IDENTITY),
			"mechanism returns to rest without accumulating offsets")
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(Source.SOURCE + ".json"))
	_check(receipt is Dictionary and receipt.get("prepared_sha256") == FileAccess.get_sha256(Source.SOURCE),
		"prepared source matches its receipt")
	_check(receipt is Dictionary and receipt.get("prepare_sha256") == FileAccess.get_sha256("res://../tools/prepare_pistol_source.gd"),
		"preparation source hash remains exact")
	var directory: String = Source.SOURCE.get_base_dir().path_join("pistol_views")
	var bake: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("bake.json")))
	_check(bake is Dictionary and bake.get("source_sha256") == FileAccess.get_sha256(Source.SOURCE)
		and bake.get("presenter_sha256") == FileAccess.get_sha256("res://art/models/pistol_source.gd")
		and bake.get("bake_sha256") == FileAccess.get_sha256("res://../tools/preview_pistol_source.gd")
		and bake.get("runtime_selected") == false, "candidate pixels match the actual source and bake without selecting runtime")
	for label: String in ["pistol_idle.png", "pistol_fire.png", "pistol.png"]:
		var path: String = directory.path_join(label)
		var texture: Texture2D = load(path) as Texture2D
		var image: Image = texture.get_image() if texture != null else null
		var size: Vector2i = Vector2i(36, 26) if label == "pistol.png" else Vector2i(224, 180)
		_check(image != null and image.get_size() == size, "candidate retains selected canvas size")
		_check(bake is Dictionary and bake.get("frames", {}).get(label) == FileAccess.get_sha256(path), "immutable baked " + label)
		if image == null:
			continue
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var alpha: float = image.get_pixel(x, y).a
				_check(alpha == 0.0 or alpha == 1.0, "candidate has hard pixel alpha without a studio rectangle")
		_check(image.get_used_rect().size.x > 8 and image.get_pixel(0, 0).a == 0.0, "object silhouette is bounded and background transparent")
		if size.y == 180:
			for y: int in range(166, 180):
				_check(image.get_pixel(112, y).a == 1.0, "centre glove cut remains opaque at the inherited bottom edge")
	gun.free()
	await process_frame
	if _failures == 0:
		print("test_pistol_source: PASS preserved topology, authored hardware, bounded maps and independent contact-safe shot mechanism")
	quit(0 if _failures == 0 else 1)
