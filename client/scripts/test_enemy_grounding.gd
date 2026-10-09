extends SceneTree

const KINDS: Array[String] = ["clerk", "sweeper", "heavy_sweeper", "turret", "ranged_sweeper", "auditor", "enforcer", "redactor", "jammer", "crawler", "notary"]
const PHASES: Array[String] = ["idle", "moving", "windup", "firing", "recovery", "hit", "dead"]
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_enemy_grounding: " + message)

func _expected(kind: String) -> float:
	return (NotaryAnimation.CENTRE_HEIGHT if kind == "notary" else EnemyAnimation.CENTRE_HEIGHT) - 1.5

func _run() -> void:
	var scene: PackedScene = load("res://scenes/player.tscn")
	for kind: String in KINDS:
		for floor_y: float in [0.0, 2.4]:
			var pawn: Node3D = scene.instantiate()
			root.add_child(pawn)
			pawn.set_process(false)
			pawn.set_player_data("ground-check", "Ground check")
			pawn.position = Vector3(0, floor_y + 1.5, 0)
			var state: Dictionary = {"id":"ground-check", "x":0.0, "y":floor_y + 1.5, "z":0.0,
				"yaw":0.0, "hp":60, "weapon":"Tack", "campaign":{
					"side":"union", "kind":kind, "phase":"idle", "phase_started":100, "phase_ends":120}}
			var body: Sprite3D = pawn.get_node("Body")
			pawn.update_state(state, 100)
			_check(is_equal_approx(body.position.y, _expected(kind)), kind + " presenter selects its actual origin")
			var atlas_image: Image = body.texture.get_image()
			for phase: String in PHASES:
				state.campaign.phase = phase
				state.campaign.phase_started = 100
				state.campaign.phase_ends = 140
				state.hp = 0 if phase == "dead" else 60
				pawn.update_state(state, 139)
				pawn.broadcast_scale_enabled = true
				pawn.hit_flash_timer = 0.2
				pawn._process(0.05)
				_check(is_equal_approx(body.position.y, _expected(kind)), kind + "/" + phase + " retains origin after real frame and hit scaling")
				_check(body.scale.is_equal_approx(Vector3.ONE), kind + "/" + phase + " retains physical dimensions")
				if kind == "auditor":
					_check(pawn.get_node("AuditorPlate").visible == (phase != "dead"), "Auditor lamps follow the actual living/dead phase")
				if kind != "notary":
					var tile_size: int = body.texture.get_width() / body.hframes
					var poses: int = JammerAnimation.poses() if kind == "jammer" else (CrawlerAnimation.poses() if kind == "crawler" else EnemyAnimation.poses())
					var pose: int = body.frame % poses
					for facing: int in range(8):
						var selected: int = facing * poses + pose
						var tile_origin: Vector2i = Vector2i(selected % body.hframes, selected / body.hframes) * tile_size
						var used: Rect2i = atlas_image.get_region(Rect2i(tile_origin, Vector2i.ONE * tile_size)).get_used_rect()
						_check(used.has_area(), "%s/%s direction %d has a real opaque body" % [kind, phase, facing])
						var visible_bottom: float = body.global_position.y + (tile_size * 0.5 - used.end.y) * body.pixel_size
						_check(absf(visible_bottom - floor_y) <= 0.08, "%s/%s actual opaque feet %.4f meet support %.4f (frame %d)" % [kind, phase, visible_bottom, floor_y, selected])
				pawn.update_state(state, 139)
				pawn._process(0.05)
				_check(is_equal_approx(body.position.y, _expected(kind)), kind + "/" + phase + " repeated snapshot retains origin")
			if kind == "auditor":
				state.hp = 60
				state.campaign.phase = "recovery"
				state.campaign.phase_started = 140
				state.campaign.phase_ends = 180
				pawn.update_state(state, 140)
				pawn._process(0.05)
				_check(not pawn.get_node("AuditorPlate").visible, "A repaired body's rising pose keeps standing sockets hidden")
				state.campaign.phase = "idle"
				pawn.update_state(state, 181)
				pawn._process(0.05)
				_check(pawn.get_node("AuditorPlate").visible, "Auditor standing lamps return after actual repaired rise")
			# This deliberately recreates the stale cache, then requires the actual
			# process path to expose it. It must not be a second expected constant.
			var corrected: float = body.position.y
			pawn._body_rest_y = -0.15
			pawn._process(0.05)
			_check(not is_equal_approx(body.position.y, corrected), kind + " stale-cache negative control visibly changes registration")
			pawn.queue_free()
			await process_frame
	await create_timer(0.3).timeout
	if _failures == 0:
		print("test_enemy_grounding: PASS")
	quit(0 if _failures == 0 else 1)
