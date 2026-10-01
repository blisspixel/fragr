extends SceneTree

const FIXTURE = preload("res://scripts/test_m06_mission.gd")
const RIG = preload("res://art/characters/machines.gd")
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_m06_presentation: " + message)

func _run() -> void:
	var directory: String = "res://assets/environment/moon/"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory + "manifest.json"))
	_check(manifest is Dictionary and manifest["source_sha256"] == FileAccess.get_sha256("res://../tools/bake_moon_details.gd"), "local pixel assets bind their exact source")
	if manifest is Dictionary:
		_check(manifest["files"].size() == 4 and manifest["spend_usd"] == 0, "four original textures have a bounded offline receipt")
		for entry: Dictionary in manifest["files"]:
			var path: String = directory + entry["file"]
			var texture: Texture2D = load(path) as Texture2D
			var image: Image = texture.get_image() if texture != null else null
			_check(image != null and image.get_size() == Vector2i(128, 128)
				and FileAccess.get_sha256(path) == entry["sha256"], "original lunar asset is loadable and fresh: " + path)
	var rig: RefCounted = RIG.new()
	var walk_start: Node3D = rig.build_turret("walk", 0.0)
	var walk_later: Node3D = rig.build_turret("walk", 0.37)
	_check(_transforms(walk_start) == _transforms(walk_later), "Turret walk frames never introduce a second head yaw or lamp motion")
	walk_start.free()
	walk_later.free()
	var info: Dictionary = FIXTURE.fixture_map()
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	for side: int in range(4):
		_check(not (cover.get_node("MapBoundary%d" % side) as Node3D).visible, "lunar authored pressure perimeter remains visible without generic wall masking")
	_check(cover._solid_views.size() == info["solids"].size(), "every authoritative pressure barrier still has its solid view")
	var glass: StandardMaterial3D = cover._solid_views[0].material_override as StandardMaterial3D
	_check(glass != null and glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "registered pressure glass exposes the real view")
	var earth: MeshInstance3D = cover.find_child("Earth", true, false) as MeshInstance3D
	_check(earth != null and earth.position.x < -float(info["half_extent"])
		and (earth.material_override as StandardMaterial3D).albedo_texture != null, "Earth remains an original static landmark outside gameplay bounds")
	var carrier: Node3D = cover.find_child("CommonCarrierStatic", true, false) as Node3D
	_check(carrier != null and carrier.position.x > float(info["half_extent"]), "impound ship remains a grounded exterior landmark")
	_check_landmark_bounds(cover.find_child("LunarLandmarks", true, false), float(info["half_extent"]))
	var compact_backdrop: MoonBackdrop = MoonBackdrop.new()
	root.add_child(compact_backdrop)
	compact_backdrop.build(2.0)
	_check_landmark_bounds(compact_backdrop, 2.0)
	compact_backdrop.queue_free()
	var legacy: Dictionary = {"map_id": 1002, "map_name": "Persons Unknown", "geometry_version": 2, "half_extent": 48, "solids": info["solids"], "presentation": info["presentation"].duplicate(true)}
	legacy["presentation"]["decorations"] = []
	cover.apply_map_info(legacy)
	_check((cover.get_node("MapBoundary0") as Node3D).visible and cover.find_child("Earth", true, false) == null, "nonlunar replacement restores its normal shell and removes all lunar landmarks")
	var old_glass: StandardMaterial3D = ArenaMaterials.authored("inspection_glass") as StandardMaterial3D
	_check(old_glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "M02 inspection glass retains its existing transparent presentation")
	cover.queue_free()
	await process_frame
	if failures == 0:
		print("test_m06_presentation: PASS original asset freshness, authoritative Turret yaw, lunar shell and preserved glass")
	quit(0 if failures == 0 else 1)

static func _transforms(node: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = [node.transform]
	for child: Node in node.get_children():
		if child is Node3D:
			result.append_array(_transforms(child))
	return result

func _check_landmark_bounds(backdrop: Node, half: float) -> void:
	_check(backdrop != null, "lunar exterior landmark subtree exists")
	if backdrop == null:
		return
	for node: Node in backdrop.find_children("*", "MeshInstance3D", true, false):
		var view: MeshInstance3D = node as MeshInstance3D
		if not view.mesh is BoxMesh:
			continue
		var size: Vector3 = (view.mesh as BoxMesh).size * 0.5
		var low: Vector3 = Vector3.INF
		var high: Vector3 = -Vector3.INF
		for x: float in [-1.0, 1.0]:
			for y: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					var corner: Vector3 = view.global_transform * (size * Vector3(x, y, z))
					low = low.min(corner)
					high = high.max(corner)
		_check(low.x > half or high.x < -half or low.z > half or high.z < -half,
			"full projected cosmetic landmark footprint stays separated from playable square: " + str(view.name))
