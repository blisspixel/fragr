class_name M05Town
extends M04Town

## Surface repair, fixtures and passengers are tied to registered volumes.
## Nothing here adds cover, support, a moving body or an outcome.
func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m05") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_root = Node3D.new()
	_root.name = "LowWaterRoofWorkshop"
	add_child(_root)
	var practical_count: int = 0
	for detail: Dictionary in info["presentation"]["decorations"]:
		if detail["kind"] == "strip_light":
			practical_count += 1
	var repair_lamps: int = 0
	for solid: Dictionary in info["solids"]:
		var low: Vector3 = Vector3(float(solid["min_x"]), MoveStep.solid_bottom(solid), float(solid["min_z"]))
		var high: Vector3 = Vector3(float(solid["max_x"]), MoveStep.solid_top(solid), float(solid["max_z"]))
		var center: Vector3 = (low + high) * 0.5
		var extent: Vector3 = high - low
		if high.y == 4.0 and extent.x > 20.0 and extent.z > 12.0:
			for index: int in range(5):
				_box("RoofRepair", Vector3(lerpf(low.x + 2, high.x - 2, float(index) / 4), high.y + 0.012, low.z + 1.5), Vector3(2.3, 0.015, 1.1), Color("a59b7d") if index % 2 else Color("6b8278"))
			for index: int in range(12):
				_box("RoofWaterline", Vector3(low.x + 0.02, high.y - 0.6, lerpf(low.z + 0.4, high.z - 0.4, float(index) / 11)), Vector3(0.025, 0.15, 0.5), Color("758177"))
		if extent.y == 4.0 and extent.x < 0.6 and extent.z > 5:
			for index: int in range(6):
				_box("WorkshopPatch", Vector3(high.x + 0.015, 1.6, lerpf(low.z + 0.5, high.z - 0.5, float(index) / 5)), Vector3(0.025, 0.8, 0.6), Color("b1a282") if index % 2 else Color("637f73"))
			if repair_lamps < 2 and practical_count + repair_lamps < MapDecoration.MAX_LIGHTS:
				var lamp: MeshInstance3D = _box("RepairLamp", Vector3(high.x + 0.04, high.y - 0.5, center.z), Vector3(0.06, 0.15, 0.8), Color("d2be90"))
				var light: OmniLight3D = OmniLight3D.new()
				light.name = "WorkshopRepairPool"
				light.position = lamp.position + Vector3(0.15, -0.1, 0)
				light.light_color = Color("e0c495")
				light.light_energy = 0.45
				light.omni_range = 5.0
				light.light_cull_mask = ArenaSky.WORLD_LAYERS | ArenaSky.ACTOR_LAYERS
				light.add_to_group(ArenaSky.PRACTICAL_GROUP)
				_root.add_child(light)
				repair_lamps += 1
		if extent.x == 14.0 and low.z == 36.0:
			for index: int in range(8):
				_box("CarrierWindow", Vector3(lerpf(low.x + 0.8, high.x - 0.8, float(index) / 7), high.y - 0.8, low.z - 0.015), Vector3(0.8, 0.6, 0.025), Color("53736f"))
			_box("CarrierWaterline", Vector3(center.x, low.y + 0.3, low.z - 0.016), Vector3(extent.x, 0.12, 0.025), Color("6c8075"))
	for decoration: Dictionary in info["presentation"]["decorations"]:
		var solid: Dictionary = info["solids"][int(decoration["solid"])]
		var low: Vector3 = Vector3(float(solid["min_x"]), MoveStep.solid_bottom(solid), float(solid["min_z"]))
		var high: Vector3 = Vector3(float(solid["max_x"]), MoveStep.solid_top(solid), float(solid["max_z"]))
		var center: Vector3 = (low + high) * 0.5
		match decoration["kind"]:
			"m05_water_tank":
				for fraction: float in [0.16, 0.78]:
					_box("TankRepairBand", Vector3(center.x, lerpf(low.y, high.y, fraction), high.z + 0.015), Vector3(high.x - low.x, 0.12, 0.025), Color("b8ab89"))
				_box("TankGauge", Vector3(high.x + 0.018, center.y, center.z), Vector3(0.025, 1.0, 0.15), Color("c5d7b1"))
			"m05_paint_bench":
				for index: int in range(9):
					_box("PaintSwatch", Vector3(lerpf(low.x + 0.2, high.x - 0.2, float(index) / 8), high.y + 0.016, center.z), Vector3(0.25, 0.025, 0.65), [Color("b26743"), Color("699087"), Color("bea169")][index % 3])
			"m05_loading_pen":
				for index: int in range(6):
					_box("PenServiceStripe", Vector3(high.x + 0.014, 0.75, lerpf(low.z + 0.1, high.z - 0.1, float(index) / 5)), Vector3(0.025, 0.3, 0.16), Color("d1b26f"))
			"m05_tram_service":
				for index: int in range(5):
					_box("ServiceToolPlate", Vector3(lerpf(low.x + 0.3, high.x - 0.3, float(index) / 4), high.y - 0.7, low.z - 0.018), Vector3(0.15, 0.5, 0.025), Color("bba382"))
			"m05_market_six":
				_box("MarketRepairHem", Vector3(high.x + 0.014, high.y - 0.3, center.z), Vector3(0.025, 0.2, high.z - low.z), Color("af744e"))
	for index: int in range(info["m05"]["rescue"]["captives"].size()):
		var captive: Dictionary = info["m05"]["rescue"]["captives"][index]
		var view: Sprite3D = Sprite3D.new()
		view.name = "Worker_" + captive["id"]
		view.texture = load(PlayerBody.strip_path(PlayerBody.SYNTHETIC)) as Texture2D
		view.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
		view.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		view.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		view.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
		view.position = _feet(captive["held"]) + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
		view.modulate = Color("b8bda7")
		view.set_meta("walked", 0.0)
		view.set_meta("last_move_ms", -1000)
		_root.add_child(view)
		if index == 0:
			var patch: MeshInstance3D = _box("SpliceRepairPatch", view.position + Vector3(0.26, 0.08, 0.025), Vector3(0.10, 0.13, 0.04), Color("966c83"))
			_root.remove_child(patch)
			view.add_child(patch)
			patch.position = Vector3(0.26, 0.08, 0.025)
		_views[captive["id"]] = view
	_geometry = MissionState.geometry_for(info)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M05_ID \
		or not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	for captive: Dictionary in state["m05"]["captives"]:
		var view: Sprite3D = _views[captive["id"]]
		var next: Vector3 = _feet(captive["feet"]) + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT
		var distance: float = view.position.distance_to(next)
		if distance > 0.001:
			view.set_meta("walked", float(view.get_meta("walked")) + distance)
			view.set_meta("last_move_ms", Time.get_ticks_msec())
		view.position = next
		view.modulate = Color("e8e2d6") if state["m05"]["group_released"] else Color("b8bda7")
