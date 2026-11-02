extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("test_island_water: " + label)

func _run() -> void:
	var info: Dictionary = {"half_extent": 20.0, "solids": [{"min_x": 0.0, "max_x": 10.0, "min_z": -10.0, "max_z": 10.0, "top": 3.0}], "water_regions": [{"min": [-20.0, -20.0], "max": [20.0, 20.0], "level": 2.2, "depth": 2.2}]}
	_check(WaterRegions.validation_error(info).is_empty(), "valid bounds accepted")
	var malformed: Dictionary = info.duplicate(true)
	malformed.water_regions[0].level = INF
	_check(not WaterRegions.validation_error(malformed).is_empty(), "nonfinite surface refused")
	malformed = info.duplicate(true)
	malformed.water_regions.append(info.water_regions[0].duplicate(true))
	_check(not WaterRegions.validation_error(malformed).is_empty(), "overlap refused")
	malformed = info.duplicate(true)
	malformed.water_regions[0].extra = true
	_check(not WaterRegions.validation_error(malformed).is_empty(), "unknown region field refused")
	var texture: ImageTexture = IslandWater._depth_texture(info, 2.2)
	var depth: Image = texture.get_image()
	_check(depth.get_size() == Vector2i(512, 512) and not depth.has_mipmaps(), "bounded static depth storage")
	_check(is_equal_approx(depth.get_pixel(300, 256).r, 0.0), "solid land supplies zero water depth")
	_check(absf(depth.get_pixel(128, 256).r * 4.0 - 2.2) < 0.02, "real seabed supplies open water depth")
	var water: IslandWater = IslandWater.new()
	root.add_child(water)
	water.build(info)
	water.apply_quality(-100)
	_check(water.quality == 0 and water.material.get_shader_parameter("water_quality") == 0, "quality lower bound applied")
	water.apply_quality(100)
	_check(water.quality == 2 and water.material.get_shader_parameter("water_quality") == 2, "quality upper bound applied")
	water.free()
	await process_frame
	if failures == 0:
		print("test_island_water: PASS strict water, registered depth and bounded quality")
	quit(0 if failures == 0 else 1)
