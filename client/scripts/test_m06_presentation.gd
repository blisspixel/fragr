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
	_check_surface_tiles()
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
	var possessions: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/environment/moon-batch-20261001/manifest.json"))
	_check(possessions is Dictionary, "selected personal possessions retain their source receipt")
	if possessions is Dictionary:
		for entry: Dictionary in possessions["assets"]:
			if entry["id"] == "lunar_pressure_habitat_insert":
				continue
			var selected: String = M06Port.POSSESSIONS + String(entry["processed"]).get_file()
			if entry["id"] in ["lunar_child_earth_drawing", "lunar_civilian_patched_textile", "lunar_personal_meal_cloth"]:
				var texture: Texture2D = load(selected) as Texture2D
				_check(texture != null and texture.get_size() == Vector2(128, 128)
					and FileAccess.get_sha256(selected) == entry["processed_sha256"], "selected possession matches inspected original source: " + selected)
	_check(M06Port.possession_material(M06Port.DRAWING, M06Port.DRAWING_FALLBACK).albedo_texture.resource_path == M06Port.DRAWING,
		"family page prefers selected personal drawing")
	_check(M06Port.possession_material("res://missing-m06-drawing.png", M06Port.DRAWING_FALLBACK).albedo_texture.resource_path == M06Port.DRAWING_FALLBACK,
		"missing personal drawing keeps original offline fallback")
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
	await _check_environment_replacement()
	if failures == 0:
		print("test_m06_presentation: PASS original asset freshness, authoritative Turret yaw, lunar shell and preserved glass")
	quit(0 if failures == 0 else 1)

func _check_surface_tiles() -> void:
	var directory: String = "res://assets/environment/moon/surfaces/"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/environment/moon-surfaces-20261001/tile-preparation.json"))
	_check(manifest is Dictionary and manifest.get("source_sha256") == FileAccess.get_sha256("res://../tools/prepare_moon_surface_tiles.gd"), "periodic tile preparation binds its exact source")
	if not manifest is Dictionary:
		return
	_check(manifest.get("files") is Array and manifest["files"].size() == 8, "eight distinct lunar surface assets retain their preparation receipt")
	_check(manifest.get("palette_sha256") == FileAccess.get_sha256("res://../docs/palette.json"), "prepared surfaces use the current shared palette")
	for entry: Dictionary in manifest["files"]:
		var path: String = directory + entry["id"] + ".png"
		var texture: Texture2D = load(path) as Texture2D
		var image: Image = texture.get_image() if texture != null else null
		_check(image != null and image.get_size() == Vector2i(128, 128) and not image.has_mipmaps()
			and FileAccess.get_sha256(path) == entry["runtime_sha256"], "surface is fresh, nearest-ready and unmipped: " + path)
		if image == null:
			continue
		for index: int in range(128):
			_check(image.get_pixel(0, index) == image.get_pixel(127, index) and image.get_pixel(index, 0) == image.get_pixel(index, 127), "opposite tile edges match: " + path)

func _check_environment_replacement() -> void:
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.settings = FragrSettings.new()
	var world: WorldEnvironment = WorldEnvironment.new()
	manager.add_child(world)
	manager._apply_arena_sky("Port of Entry")
	var initial: Environment = world.environment
	manager._apply_arena_sky("No Forwarding Address")
	manager._apply_arena_sky("Port of Entry")
	_check(world.environment != initial and world.environment.sky != null, "rapid venue changes replace visible environment immediately")
	initial = null
	if DisplayServer.get_name() == "headless":
		_check(manager._retired_environments.is_empty(), "headless checks never await a GPU draw")
	else:
		_check(manager._retired_environments.size() == 2, "rapid replacements retain pending sky resources through draw")
		await RenderingServer.frame_post_draw
		_check(manager._retired_environments.is_empty(), "one completed draw releases both retired skies")
	manager.free()

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
