extends "res://scripts/qa_tour.gd"

## Records real custody facts during an ordinary authored range route.
var _auditor_tick: int = -1
var _custody_samples: Array[Dictionary] = []
var _channel_ticks: int = 0
var _normal_checked: bool = false
var _observer: SubViewport
var _observer_camera: Camera3D
var _capture_pending: bool = false
var _observer_frame: Dictionary = {}

func _process(delta: float) -> bool:
	super._process(delta)
	var manager: Node = _game_manager()
	if manager == null:
		return false
	var snapshot: Dictionary = manager.get("latest_snapshot")
	var tick: int = int(snapshot.get("tick", -1))
	if tick <= _auditor_tick:
		return false
	_auditor_tick = tick
	for fact: Dictionary in snapshot.get("auditors", []):
		var id: String = str(fact["id"])
		var actor: Dictionary = QaCombat.actor_by_id(snapshot, id)
		if actor.is_empty():
			continue
		var channel: String = str(fact.get("channel_target", ""))
		if not channel.is_empty():
			_channel_ticks += 1
			if _observer_frame.is_empty() and not _capture_pending:
				_capture_pending = true
				_capture_channel(manager, id)
		if _custody_samples.size() < 600:
			_custody_samples.append({"tick": tick, "auditor": actor.duplicate(true), "custody": fact.duplicate(true)})
		var pawn: Node = manager.players.get(id)
		if pawn != null:
			var sprite: Sprite3D = pawn.get_node_or_null("Body") as Sprite3D
			if sprite != null and sprite.material_override is ShaderMaterial:
				var material: ShaderMaterial = sprite.material_override as ShaderMaterial
				var normals: Texture2D = material.get_shader_parameter("sprite_normals") as Texture2D
				_normal_checked = material.get_shader_parameter("normals_enabled") == true and \
					normals != null and normals.resource_path == "res://assets/characters/union/auditor_normals.png"
	return false

func _capture_channel(manager: Node, id: String) -> void:
	var pawn: Node3D = manager.players.get(id) as Node3D
	var camera: Node3D = manager.get_node("SpectatorCamera") as Node3D
	if pawn == null or camera == null:
		_capture_pending = false
		return
	if _observer == null:
		_observer = SubViewport.new()
		_observer.size = Vector2i(960, 720)
		_observer.world_3d = pawn.get_world_3d()
		_observer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(_observer)
		_observer_camera = Camera3D.new()
		_observer_camera.fov = 65.0
		_observer.add_child(_observer_camera)
	var actor: Dictionary = QaCombat.actor_by_id(manager.latest_snapshot, id)
	var direction: Vector3 = pawn.global_position - camera.global_position
	direction.y = 0.0
	direction = direction.normalized()
	var solids: Array = manager.current_map_info.get("solids", [])
	var look: Vector3 = pawn.global_position + Vector3.DOWN * 0.5
	var at: Vector3 = Vector3.INF
	var distance: float = 0.0
	for candidate_distance: float in [6.0, 5.0, 4.0]:
		var candidate: Vector3 = pawn.global_position - direction * candidate_distance
		candidate.y = float(actor["y"]) + 0.05
		if AimAssist.line_of_sight(candidate, look, solids):
			at = candidate
			distance = candidate_distance
			break
	if not at.is_finite():
		_capture_pending = false
		return
	# Same bearing as the live eye preserves the runtime atlas direction.
	_observer_camera.global_position = at
	_observer_camera.look_at(look)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var snapshot: Dictionary = manager.latest_snapshot
	actor = QaCombat.actor_by_id(snapshot, id)
	var fact: Dictionary = {}
	for candidate: Dictionary in snapshot.get("auditors", []):
		if str(candidate["id"]) == id:
			fact = candidate
	var sprite: Sprite3D = pawn.get_node("Body") as Sprite3D
	var channels: AuditorChannels = manager.get("auditor_channels") as AuditorChannels
	if actor.get("campaign", {}).get("phase", "") == "channeling" and \
		not str(fact.get("channel_target", "")).is_empty() and \
		sprite.frame % EnemyAnimation.poses() == EnemyAnimation.pose_frame("seated", false, 0.0) and \
		channels != null and channels.channels.has(id):
		var links: Node3D = channels.channels[id]["links"] as Node3D
		var link_count: int = links.find_children("*", "MeshInstance3D", false, false).size()
		var captured: Image = _observer.get_texture().get_image()
		if links.visible and link_count == AuditorChannels.LINKS and \
			captured.save_png(_out_dir.path_join("channel-observer.png")) == OK:
			_observer_frame = {"diagnostic_observer": true, "same_world": true, "tick": snapshot["tick"],
				"camera_position": [at.x, at.y, at.z], "camera_distance_m": distance,
				"actor": actor.duplicate(true), "custody": fact.duplicate(true),
				"body_frame": sprite.frame, "actual_beam_links": link_count,
				"target": QaCombat.actor_by_id(snapshot, str(fact["channel_target"])).duplicate(true)}
	_observer.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_capture_pending = false

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var output: FileAccess = FileAccess.open(_out_dir.path_join("auditor-facts.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"channel_ticks": _channel_ticks, "live_normal_atlas": _normal_checked,
			"diagnostic_observer": _observer_frame, "samples": _custody_samples}, "\t") + "\n")
	if _channel_ticks <= 0 or not _normal_checked or _observer_frame.is_empty():
		push_error("qa_auditor_source: requires a real repair channel, its diagnostic world frame and live paired normal atlas")
		_failed = true
	elif not _failed:
		print("qa_auditor_source: PASS real channel ticks ", _channel_ticks, ", live paired normal atlas")
	else:
		print("qa_auditor_source: recorded real channel ticks ", _channel_ticks, "; overall route failed")

func _retire_scene() -> void:
	if _observer != null:
		_observer.queue_free()
		_observer = null
	await super._retire_scene()
