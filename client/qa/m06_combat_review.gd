extends "res://scripts/qa_tour.gd"

## Port of Entry combat review. Runs the ordinary-input route
## (`client/qa/m06_port_of_entry.json`) and, from the player's own view, takes
## stills of the moments a fight is read by: a Turret or Heavy Sweeper at rest
## and near the top of its windup, and Railgun beams as they hang and fade. Each still has a nearest-neighbour crop around the subject so
## optic colour and plate value can be judged at pixel scale. Observations
## only: the route's inputs, geometry and gates are the tour's own.
##
## Run with `FRAGR_QA_SCRIPT=res://qa/m06_combat_review.gd
## FRAGR_QA_MANIFEST=res://qa/m06_port_of_entry.json FRAGR_QA_BOTS=0
## FRAGR_QA_SEED=42 FRAGR_QA_MAP_FILE=server/maps/m06_port_of_entry.json
## tools/qa_tour.sh <out>`. Stills and `m06-combat-review.json` land in <out>.
const WATCH_KINDS: Array[String] = ["turret", "heavy_sweeper"]
## Windup progress that counts as the top of the tell.
const LATE_WINDUP: float = 0.8
## Rail beam ages photographed, in seconds (ShotEffects.RAIL_SECONDS is 0.6),
## after the shot's own tick has passed.
const RAIL_AGES: Array[float] = [0.12, 0.25, 0.45]
const CROP_METRES: float = 3.2
const CROP_ZOOM_MAX: int = 6
const PER_KEY_LIMIT: int = 3

var _review_shots: Array[Dictionary] = []
var _review_counts: Dictionary = {}
var _review_seen: Dictionary = {}
var _review_busy: bool = false

func _process(delta: float) -> bool:
	super._process(delta)
	var game: Node = _game_manager()
	if game == null or _review_busy or _out_dir.is_empty():
		return false
	var snapshot: Dictionary = game.latest_snapshot
	var camera: Camera3D = root.get_camera_3d()
	if snapshot.is_empty() or camera == null:
		return false
	var tick: int = int(snapshot.get("tick", 0))
	for actor: Variant in snapshot.get("players", []):
		if not actor is Dictionary or ActorState.is_participant(actor):
			continue
		var campaign: Dictionary = actor.get("campaign", {})
		var kind: String = str(campaign.get("kind", ""))
		if kind not in WATCH_KINDS or int(actor.get("hp", 0)) <= 0:
			continue
		var pawn: Node3D = game.players.get(str(actor["id"])) as Node3D
		if not is_instance_valid(pawn):
			continue
		var body: Node3D = pawn.get_node_or_null("Body") as Node3D
		var focus: Vector3 = body.global_position if body != null and body.visible else pawn.global_position + Vector3(0.0, 0.2, 0.0)
		var phase: String = str(campaign.get("phase", ""))
		var started: int = int(campaign.get("phase_started", tick))
		var ends: int = int(campaign.get("phase_ends", tick))
		var key: String = ""
		# The tour's own combat capture takes the tell's first frame and the
		# one-tick shot; reading the frame back on those ticks as well can
		# cost it that frame, so this review leaves them to it.
		if phase == "windup" and ends > started and float(tick - started) / float(ends - started) >= LATE_WINDUP:
			key = "windup_late"
		elif phase in ["idle", "moving"]:
			key = "rest"
		if key.is_empty():
			continue
		var moment: String = "%s_%s_%d" % [actor["id"], key, started if key != "rest" else 0]
		if _review_seen.has(moment):
			continue
		var label: String = "%s_%s" % [kind, key]
		if int(_review_counts.get(label, 0)) >= PER_KEY_LIMIT or not _on_screen(camera, focus):
			continue
		_review_seen[moment] = true
		_shot(label, str(actor["id"]), focus, camera, {"phase": phase, "tick": tick,
			"phase_started": started, "phase_ends": ends})
		return false
	var effects: ShotEffects = game.shot_effects
	if effects == null:
		return false
	for effect: ShotEffects.Effect in effects._effects:
		if effect.weapon != "rail":
			continue
		var beam: String = "%s_%s" % [effect.shooter, str(effect.end.snapped(Vector3.ONE * 0.01))]
		for age: float in RAIL_AGES:
			var moment: String = "%s_%.2f" % [beam, age]
			if effect.age < age or _review_seen.has(moment):
				continue
			_review_seen[moment] = true
			var label: String = "rail_%02d" % roundi(age * 100.0)
			if int(_review_counts.get(label, 0)) >= PER_KEY_LIMIT * 2:
				continue
			var middle: Vector3 = effects.to_global(effect.origin.lerp(effect.end, 0.5))
			_shot(label, effect.shooter, middle, camera, {"age": effect.age,
				"length": effect.origin.distance_to(effect.end), "outcome": effect.kind})
			return false
	return false

func _on_screen(camera: Camera3D, point: Vector3) -> bool:
	if camera.is_position_behind(point):
		return false
	var screen: Vector2 = camera.unproject_position(point)
	var size: Vector2 = Vector2(root.get_viewport().get_visible_rect().size)
	return screen.x >= 0.0 and screen.y >= 0.0 and screen.x < size.x and screen.y < size.y

func _shot(label: String, subject: String, focus: Vector3, camera: Camera3D, facts: Dictionary) -> void:
	_review_busy = true
	_review_counts[label] = int(_review_counts.get(label, 0)) + 1
	_take.call_deferred(label, subject, focus, camera, facts)

func _take(label: String, subject: String, focus: Vector3, camera: Camera3D, facts: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var frame: Image = _grab()
	var filename: String = "m06c_%02d_%s" % [_review_shots.size(), label]
	if frame != null and not frame.is_empty():
		frame.convert(Image.FORMAT_RGB8)
		var record: Dictionary = facts.duplicate()
		record.merge({"file": filename + ".png", "subject": subject})
		if frame.save_png(_out_dir.path_join(filename + ".png")) == OK:
			if is_instance_valid(camera) and _on_screen(camera, focus):
				var crop: Image = _crop(frame, camera, focus)
				if crop != null and crop.save_png(_out_dir.path_join(filename + "_zoom.png")) == OK:
					record["zoom"] = filename + "_zoom.png"
			record["distance"] = camera.global_position.distance_to(focus) if is_instance_valid(camera) else -1.0
			_review_shots.append(record)
	_review_busy = false

## A square around the subject sized to CROP_METRES at its distance, scaled up
## with nearest filtering so each rendered pixel stays one block.
func _crop(frame: Image, camera: Camera3D, focus: Vector3) -> Image:
	var centre: Vector2 = camera.unproject_position(focus)
	var edge: Vector2 = camera.unproject_position(focus + camera.global_transform.basis.x * CROP_METRES * 0.5)
	var half: int = clampi(roundi(centre.distance_to(edge)), 24, 240)
	var scale: Vector2 = Vector2(frame.get_size()) / root.get_viewport().get_visible_rect().size
	var x: int = clampi(roundi(centre.x * scale.x) - half, 0, maxi(0, frame.get_width() - half * 2))
	var y: int = clampi(roundi(centre.y * scale.y) - half, 0, maxi(0, frame.get_height() - half * 2))
	var side: int = mini(half * 2, mini(frame.get_width(), frame.get_height()))
	var crop: Image = frame.get_region(Rect2i(x, y, side, side))
	var zoom: int = clampi(480 / side, 1, CROP_ZOOM_MAX)
	crop.resize(side * zoom, side * zoom, Image.INTERPOLATE_NEAREST)
	return crop

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var file: FileAccess = FileAccess.open(_out_dir.path_join("m06-combat-review.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1, "observations_only": true, "shots": _review_shots}, "\t") + "\n")
		file.close()
