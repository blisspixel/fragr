extends "res://scripts/qa_tour.gd"

## Records real custody facts during an ordinary authored range route.
var _auditor_tick: int = -1
var _custody_samples: Array[Dictionary] = []
var _channel_ticks: int = 0
var _normal_checked: bool = false

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

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var output: FileAccess = FileAccess.open(_out_dir.path_join("auditor-facts.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"channel_ticks": _channel_ticks, "live_normal_atlas": _normal_checked,
			"samples": _custody_samples}, "\t") + "\n")
	if _channel_ticks <= 0 or not _normal_checked:
		push_error("qa_auditor_source: requires a real repair channel and the live paired normal atlas")
		_failed = true
	elif not _failed:
		print("qa_auditor_source: PASS real channel ticks ", _channel_ticks, ", live paired normal atlas")
	else:
		print("qa_auditor_source: recorded real channel ticks ", _channel_ticks, "; overall route failed")
