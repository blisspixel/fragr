extends "res://scripts/qa_tour.gd"

var _resolved: Array[Dictionary] = []
var _shot_ticks: Dictionary[int, bool] = {}
var _shot_report: Dictionary = {}
var _pairs: Array[Dictionary] = []
const CANDIDATE: String = "res://art/models/candidates/rifle_views/"

func _capture_strip(state: Dictionary, frames: int, file_name: String) -> void:
	if state.get("trigger", "") != "fire":
		await super._capture_strip(state, frames, file_name)
		return
	var manager: Node = _game_manager()
	var network: Node = manager.get("net_client")
	var before: int = EquipmentState.shots(_equipment(), "flechette")
	network.snapshot_received.connect(_collect_shots)
	Input.action_press("fire")
	var deadline: int = Time.get_ticks_msec() + 2500
	while _resolved.is_empty() and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
	Input.action_release("fire")
	# Let the existing paced manager send the physical release with its own
	# sequence and prediction accounting before any diagnostic draw work.
	var sequence: int = int(manager.get("input_seq"))
	var release_deadline: int = Time.get_ticks_msec() + 750
	while (int(manager.get("input_seq")) == sequence or bool(manager.get("action_state").get("fire", true))) \
		and Time.get_ticks_msec() < release_deadline:
		await process_frame
	if int(manager.get("input_seq")) == sequence or bool(manager.get("action_state").get("fire", true)):
		push_error("rifle_source_comparison: ordinary physical release was not sent before capture")
		_failed = true
		return
	(network.get("socket") as WebSocketPeer).poll()
	var hud: Node = _find_hud()
	var weapon: TextureRect = hud.get_node("FpWeapon") as TextureRect
	if _resolved.size() == 1 and weapon.texture == WeaponArt.FIRE["Flechette"]:
		await _pair("resolved_fire", true, file_name)
		_probe_frames = 1
		_strip_times_ms.assign([0])
	else:
		push_error("rifle_source_comparison: actual acknowledged firing frame was not visible")
		_failed = true
	await create_timer(0.35).timeout
	network.snapshot_received.disconnect(_collect_shots)
	var after: int = EquipmentState.shots(_equipment(), "flechette")
	_shot_report = {"ammo_before":before, "ammo_after":after,
		"resolved":_resolved.duplicate(true), "player_id":str(network.get("player_id")),
		"release_sequence":int(manager.get("input_seq")), "release_before_capture":true}
	var shot_file: FileAccess = FileAccess.open(_out_dir.path_join("resolved-shot.json"), FileAccess.WRITE)
	if shot_file != null:
		shot_file.store_string(JSON.stringify(_shot_report, "\t") + "\n")
		shot_file.close()
	if before != 60 or after != 59 or _resolved.size() != 1:
		push_error("rifle_source_comparison: expected exactly one owned shot and one finite bullet: " + JSON.stringify(_shot_report))
		_failed = true
	elif _resolved[0]["shot"].get("hit", true) or _resolved[0]["shot"].get("damage", -1) != 0 \
		or _resolved[0]["shot"].get("trace", {}).get("weapon", "") != "flechette" \
		or _resolved[0]["shot"].get("trace", {}).get("impact", {}).get("kind", "") != "solid":
		push_error("rifle_source_comparison: real Rifle ray must resolve on authoritative cover")
		_failed = true

func _collect_shots(snapshot: Dictionary) -> void:
	var tick: int = int(snapshot.get("tick", -1))
	if _shot_ticks.has(tick):
		return
	_shot_ticks[tick] = true
	for shot: Dictionary in snapshot.get("shot_results", []):
		if str(shot.get("shooter_id", "")) == str(_game_manager().get("net_client").get("player_id")):
			_resolved.append({"tick":tick, "shot":shot.duplicate(true)})

func _observed_state() -> Dictionary:
	var state: Dictionary = super._observed_state()
	state["rifle_presentation_shot"] = _shot_report.duplicate(true)
	state["comparison_art"] = OS.get_environment("FRAGR_RIFLE_ART")
	state["same_sample_pairs"] = _pairs.duplicate(true)
	return state

func _measure() -> Dictionary:
	await _pair("state_%02d" % (_results.size() + 1), false)
	return await super._measure()

func _pair(label: String, fire: bool, strip_file: String = "") -> void:
	var previous_pause: bool = paused
	paused = true
	var camera: Camera3D = root.get_camera_3d()
	var transform: Transform3D = camera.global_transform
	var tick: int = int(_game_manager().get("latest_snapshot").get("tick", -1))
	var started: int = Time.get_ticks_msec()
	var originals: Dictionary[Node, Texture2D] = {}
	var weapon: TextureRect = _find_hud().get_node("FpWeapon") as TextureRect
	if _find_hud().get("current_fp_weapon") == "Flechette":
		originals[weapon] = weapon.texture
		weapon.texture = load("res://assets/weapons/viewmodels/" + ("rifle_fire.png" if fire else "rifle_idle.png")) as Texture2D
	for icon: Node in root.find_children("Icon", "Sprite3D", true, false):
		var parent: Node = icon.get_parent()
		if "weapon_name" in parent and str(parent.get("weapon_name")) == "Flechette":
			var sprite: Sprite3D = icon as Sprite3D
			originals[sprite] = sprite.texture
			sprite.texture = load("res://assets/weapons/pickups/rifle.png") as Texture2D
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var selected: Image = _grab()
	for node: Node in originals:
		if node == weapon:
			node.set("texture", load(CANDIDATE + ("rifle_fire.png" if fire else "rifle_idle.png")) as Texture2D)
		else:
			node.set("texture", load(CANDIDATE + "rifle.png") as Texture2D)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var candidate: Image = _grab()
	for node: Node in originals:
		if is_instance_valid(node):
			node.set("texture", originals[node])
	await RenderingServer.frame_post_draw
	paused = previous_pause
	var ended: int = Time.get_ticks_msec()
	var selected_path: String = _out_dir.path_join(label + "_selected.png")
	var candidate_path: String = _out_dir.path_join(label + "_candidate.png")
	if selected == null or candidate == null or selected.save_png(selected_path) != OK \
		or candidate.save_png(candidate_path) != OK or not camera.global_transform.is_equal_approx(transform) \
		or ended - started > 1500:
		push_error("rifle_source_comparison: bounded same-camera pair failed")
		_failed = true
		return
	if not strip_file.is_empty():
		var sheet: Image = Image.create(selected.get_width() * 2, selected.get_height(), false, Image.FORMAT_RGBA8)
		selected.convert(Image.FORMAT_RGBA8)
		candidate.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(selected, Rect2i(Vector2i.ZERO, selected.get_size()), Vector2i.ZERO)
		sheet.blit_rect(candidate, Rect2i(Vector2i.ZERO, candidate.get_size()), Vector2i(selected.get_width(), 0))
		if sheet.save_png(_out_dir.path_join(strip_file)) != OK:
			push_error("rifle_source_comparison: cannot write paired firing sheet")
			_failed = true
	_pairs.append({"label":label, "tick":tick, "started_ms":started, "ended_ms":ended,
		"presenter_freeze_ms":ended - started, "server_continues":true,
		"camera_origin":[transform.origin.x, transform.origin.y, transform.origin.z],
		"camera_basis":[[transform.basis.x.x,transform.basis.x.y,transform.basis.x.z],
			[transform.basis.y.x,transform.basis.y.y,transform.basis.y.z],
			[transform.basis.z.x,transform.basis.z.y,transform.basis.z.z]],
		"selected_path":selected_path, "candidate_path":candidate_path,
		"selected_sha256":FileAccess.get_sha256(selected_path),
		"candidate_sha256":FileAccess.get_sha256(candidate_path), "texture_nodes":originals.size()})
	var file: FileAccess = FileAccess.open(_out_dir.path_join("same-sample-pairs.json"), FileAccess.WRITE)
	if file == null:
		push_error("rifle_source_comparison: cannot preserve same-sample receipt")
		_failed = true
		return
	file.store_string(JSON.stringify(_pairs, "\t") + "\n")
	file.close()
