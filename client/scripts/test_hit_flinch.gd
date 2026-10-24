extends SceneTree

# Headless check for the struck-fighter flinch: a snap, a settle back to rest,
# and no residue on the body once the recoil ends. No scene or server required.
# Run: godot --path client --headless --script res://scripts/test_hit_flinch.gd

const PawnScript: GDScript = preload("res://scripts/player_pawn.gd")

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("test_hit_flinch: " + message)

func _run() -> void:
	var ok: bool = true
	var total: float = float(PawnScript.get("FLINCH_SECONDS"))
	if total <= 0.1 or total > 0.4:
		_fail("flinch should last a beat, got %s s" % str(total))
		ok = false
	var at_rest: float = float(PawnScript.call("flinch_envelope", 0.0))
	var snapped: float = float(PawnScript.call("flinch_envelope", total * 0.15))
	var settling: float = float(PawnScript.call("flinch_envelope", total * 0.7))
	var done: float = float(PawnScript.call("flinch_envelope", total))
	if at_rest != 0.0 or done != 0.0:
		_fail("flinch must start and end at rest: %s, %s" % [str(at_rest), str(done)])
		ok = false
	if snapped < 0.6:
		_fail("flinch must snap early, weight %s" % str(snapped))
		ok = false
	if settling <= 0.0 or settling >= snapped:
		_fail("flinch must settle after the snap: %s then %s" % [str(snapped), str(settling)])
		ok = false
	var peak: float = 0.0
	var steps: int = 48
	for step in range(steps + 1):
		var weight: float = float(PawnScript.call("flinch_envelope", total * float(step) / float(steps)))
		if weight < 0.0 or weight > 1.0:
			_fail("flinch weight out of range: %s" % str(weight))
			ok = false
		peak = maxf(peak, weight)
	if peak < 0.6:
		_fail("flinch peak too small to read: %s" % str(peak))
		ok = false

	# A live pawn: a hit starts the recoil, the body moves back from its facing
	# and returns exactly to rest.
	var scene: PackedScene = load("res://scenes/player.tscn") as PackedScene
	if scene == null:
		_fail("failed to load player scene")
		quit(1)
		return
	var pawn: Node3D = scene.instantiate() as Node3D
	root.add_child(pawn)
	await process_frame
	var body: Sprite3D = pawn.get_node("Body") as Sprite3D
	var rest_x: float = body.position.x
	pawn.set("hp", 80)
	pawn.call("show_hit_feedback")
	if float(pawn.get("flinch_timer")) <= 0.0:
		_fail("a hit did not start the flinch")
		ok = false
	pawn.call("_process", total * 0.15)
	if body.position.x >= rest_x - 0.02:
		_fail("struck body did not give ground: %s" % str(body.position.x))
		ok = false
	for _i in range(10):
		pawn.call("_process", total * 0.15)
	if absf(body.position.x - rest_x) > 0.0001 or float(pawn.get("flinch_timer")) != 0.0:
		_fail("flinch left residue: %s" % str(body.position.x))
		ok = false
	# A downed fighter or a campaign actor does not take the arcade recoil.
	pawn.set("hp", 0)
	pawn.call("show_hit_feedback")
	if float(pawn.get("flinch_timer")) != 0.0:
		_fail("a dead body flinched")
		ok = false
	# Let the hit feedback's own short timer finish and silence its impact
	# before the pawn goes, so no playback outlives the scene.
	await create_timer(0.2).timeout
	var hit_sound: Variant = pawn.get("hit_sound")
	if hit_sound is AudioStreamPlayer3D:
		(hit_sound as AudioStreamPlayer3D).stop()
		(hit_sound as AudioStreamPlayer3D).stream = null
	pawn.queue_free()
	await create_timer(0.3).timeout
	if ok:
		print("test_hit_flinch: PASS")
		quit(0)
	else:
		quit(1)
