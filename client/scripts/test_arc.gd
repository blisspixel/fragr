extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_arc: " + message)

func _run() -> void:
	_check(EquipmentState.WEAPONS.find("arc") == 8 and "arc" not in EquipmentState.ARCADE, "Arc retains an appended identity and discovery ownership")
	_check(ArenaSky.preset_for("Arc Maintenance (development)").sky_top == ArenaSky.mars_habitat().sky_top, "maintenance practice has an explicit protected Mars work venue")
	var loadout: Dictionary = {"type":"loadout", "player_id":"self", "tick":20, "selected":"arc", "weapons":["fists", "rail", "arc"],
		"ammo":[{"pool":"bullets", "rounds":0}, {"pool":"shells", "rounds":0}, {"pool":"cells", "rounds":40}],
		"loaded":[{"weapon":"rail", "rounds":4}, {"weapon":"arc", "rounds":12}], "personal_claims":["maintenance_arc"], "dry_fire_count":0, "grenades":0}
	_check(EquipmentState.validation_error(loadout, "self").is_empty(), "finite Arc and Rail share a valid human bag")
	_check(EquipmentState.shots(loadout, "arc") == 12 and EquipmentState.count_text(loadout, "arc") == "12|24", "Arc HUD excludes both loaded magazines from shared reserve")
	var invalid: Dictionary = loadout.duplicate(true)
	invalid["loaded"][1]["rounds"] = 13
	_check(not EquipmentState.validation_error(invalid, "self").is_empty(), "Arc capacitor cannot exceed twelve rounds")
	invalid = loadout.duplicate(true)
	invalid["ammo"][2]["rounds"] = 15
	_check(not EquipmentState.validation_error(invalid, "self").is_empty(), "loaded guns cannot invent Cells beyond the bag")
	_check(WeaponArt.IDLE["Arc"] != WeaponArt.IDLE["Rail"] and WeaponArt.PROFILE["Arc"] != WeaponArt.PROFILE["Rail"], "Arc has independent held and world art")
	_check(WeaponArt.IDLE["Arc"].get_size() == WeaponArt.IDLE["Scatter"].get_size() and WeaponArt.IDLE["Arc"].get_size() == Vector2(241, 180) and WeaponArt.PROFILE["Arc"].get_size() == Vector2(80, 42), "Arc matches the actual shared held canvas and keeps its own world profile")
	invalid = loadout.duplicate(true)
	invalid["loaded"][1]["ready_at"] = 42
	_check(WeaponArt.reload_frame("Arc", invalid, 41) == WeaponArt.ARC_RELOAD, "actual pending capacitor reload shows its registered hand pose")
	_check(WeaponArt.reload_frame("Arc", invalid, 42) == null and WeaponArt.reload_frame("Rail", invalid, 41) == null and WeaponArt.reload_frame("Arc", loadout, 20) == null, "expired, other-weapon and absent reload receipts cannot select the pose")
	_check(WeaponArt.frame_after_shot("Arc", 0.0) == WeaponArt.FIRE["Arc"] and WeaponArt.frame_after_shot("Arc", 0.08) == WeaponArt.CYCLE["Arc"] and WeaponArt.frame_after_shot("Arc", 0.15) == WeaponArt.IDLE["Arc"], "discharge ends in its own settle frame before the next server shot")
	_check(ResourceLoader.load("res://assets/audio/arc/fire.wav") is AudioStreamWAV and ResourceLoader.load("res://assets/audio/arc/impact.wav") is AudioStreamWAV, "Arc has committed offline discharge and impact cues")
	var effects: ShotEffects = ShotEffects.new()
	root.add_child(effects)
	var shot: Dictionary = {"shooter_id":"self", "trace":{"weapon":"arc", "origin":[0.0, 1.6, 0.0], "end":[24.0, 1.6, 0.0], "impact":{"kind":"range"}}}
	effects.ingest(1, [shot])
	_check(effects.active_count() == 1, "resolved Arc range evidence is presented")
	var mesh: Mesh = effects.get_node("Surface").mesh
	_check(mesh.get_surface_count() == 1, "bounded discharge produces visible trace geometry")
	if mesh.get_surface_count() == 1:
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var furthest: float = 0.0
		var lateral: float = 0.0
		for vertex: Vector3 in vertices:
			furthest = maxf(furthest, vertex.x)
			lateral = maxf(lateral, Vector2(vertex.y - 1.6, vertex.z).length())
		_check(furthest <= 24.001 and furthest >= 23.99 and lateral < 0.2, "cosmetic forks stay within twenty centimetres of the resolved bounded segment, end %.4f lateral %.4f" % [furthest, lateral])
	effects._process(0.1)
	_check(effects.active_count() == 0, "discharge vanishes before the next three-tick shot")
	shot["trace"]["end"] = [24.1, 1.6, 0.0]
	effects.ingest(2, [shot])
	_check(effects.active_count() == 0, "over-range Arc evidence is refused")
	shot["trace"]["end"] = [8.0, 1.6, 0.0]
	shot["trace"]["pellets"] = [{"end":[8.0,1.6,0.0], "impact":{"kind":"range"}}]
	effects.ingest(3, [shot])
	_check(effects.active_count() == 0, "Arc cannot claim a scatter or chaining result")
	effects.free()
	print("test_arc: %s" % ("PASS" if _failures == 0 else "FAIL %d" % _failures))
	quit(0 if _failures == 0 else 1)
