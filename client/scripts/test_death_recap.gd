extends SceneTree
## #528 death recap. The recap reads only server facts (hit events naming this
## fighter, the frag's weapon, the killer's and this body's snapshot rows),
## says who, with what, from where, what the killer kept and the damage taken,
## and is on the card on the first frame after the frag fact, well inside the
## 300 ms gate, without touching the respawn countdown.

const SELF: String = "00000000-0000-4000-8000-000000000001"
const RIVAL: String = "00000000-0000-4000-8000-000000000002"
const OTHER: String = "00000000-0000-4000-8000-000000000003"
const THIRD: String = "00000000-0000-4000-8000-000000000004"
## The gate (docs/plans/fun-craft-targets.md, feedback and readability).
const RECAP_GATE_USEC: int = 300000

class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: String = SELF
	var player_name: String = "Meat"
	var mission: Dictionary = {}
	var equipment: Dictionary = {}
	var sent: Array[Dictionary] = []
	var last_send_ok: bool = true
	func send_action(action: Dictionary) -> void:
		last_send_ok = true
		sent.append(action.duplicate())

var _failures: int = 0


func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_death_recap: " + message)


func _run() -> void:
	_recap_lines()
	_landed()
	_bearings()
	_boundaries()
	await _fits()
	await _first_frame()
	if _failures == 0:
		print("test_death_recap: PASS recap facts, bearings, refused rows, first-frame card")
	quit(0 if _failures == 0 else 1)


func _body(x: float, y: float, z: float, yaw: float) -> Dictionary:
	return {"id": SELF, "x": x, "y": y, "z": z, "yaw": yaw}


func _recap_lines() -> void:
	var life: LocalLife = LocalLife.new()
	_check(life.recap_lines().is_empty(), "a living fighter has no recap")
	# Facing +X (server yaw 0); the killer stands 23 m behind.
	life.observe_body(_body(0.0, 1.5, 0.0, 0.0))
	life.record_hit(RIVAL, "Rival", 40)
	life.record_hit(OTHER, "Bot Two", 25)
	life.record_hit(RIVAL, "Rival", 60)
	life.record_frag(SELF, RIVAL, "Rival", 50)
	life.record_kill_facts("rail", {"id": RIVAL, "x": -23.0, "y": 1.5, "z": 0.0, "hp": 64, "armor": 25})
	var lines: PackedStringArray = life.recap_lines()
	_check(lines.size() == 2, "two recap lines: %s" % [lines])
	_check(lines.size() > 0 and lines[0] == "RAILGUN // 23 M BEHIND YOU // THEY KEPT 64 HP 25 ARMOR", "how, where and what the killer kept: %s" % [lines])
	_check(lines.size() > 1 and lines[1] == "TOOK 125: Rival 100, Bot Two 25", "damage taken by shooter, most first: %s" % [lines])
	# A body that moved after the death does not move the recap.
	life.observe_body(_body(50.0, 1.5, 50.0, 1.0))
	_check(life.recap_lines() == lines, "the pose is the last one alive")
	# A hit that lands in the same batch after the frag still counts.
	life.record_hit(THIRD, "Third", 5)
	_check(life.recap_lines()[1] == "TOOK 130: Rival 100, Bot Two 25 +1 MORE", "three shooters name two and count the rest: %s" % [life.recap_lines()])
	life.respawned()
	_check(life.recap_lines().is_empty() and life.damage_taken() == 0 and life.weapon.is_empty(), "a new life starts with no recap")
	# Self-inflicted: the weapon and the damage, no range or killer health.
	life.observe_body(_body(0.0, 1.5, 0.0, 0.0))
	life.record_hit(SELF, "Meat", 70)
	life.record_frag(SELF, SELF, "Meat", 60)
	life.record_kill_facts("rocket", {"id": SELF, "x": 0.0, "y": 1.5, "z": 0.0, "hp": 30})
	_check(life.recap_lines() == PackedStringArray(["ROCKET LAUNCHER", "TOOK 70: Meat 70"]), "a self frag names only the weapon and the damage: %s" % [life.recap_lines()])
	life.reset()
	# The killer left the snapshot (traded, or gone): no range or health.
	life.observe_body(_body(0.0, 1.5, 0.0, 0.0))
	life.record_frag(SELF, RIVAL, "Rival", 70)
	life.record_kill_facts("scatter", null)
	_check(life.recap_lines() == PackedStringArray(["SHOTGUN"]), "an absent killer leaves range and health unsaid: %s" % [life.recap_lines()])


## Damage taken is what landed: health plus armour lost, never overkill.
func _landed() -> void:
	# A 160 Railgun hit on a 100 HP fighter reports at most what they had.
	var life: LocalLife = LocalLife.new()
	var row: Dictionary = _body(0.0, 1.5, 0.0, 0.0)
	row["hp"] = 100
	life.observe_body(row)
	life.body_gone(10)
	life.record_hit(RIVAL, "Rival", 160)
	life.record_frag(SELF, RIVAL, "Rival", 10)
	_check(life.damage_taken() == 100 and life.recap_lines()[-1] == "TOOK 100: Rival 100", "a 160 Railgun hit on 100 HP lands 100: %s" % [life.recap_lines()])
	# Armour counts as lost too, and the death tick's hits share what was left.
	life.reset()
	row["hp"] = 40
	row["armor"] = 25
	life.observe_body(row)
	life.body_gone(20)
	life.record_hit(OTHER, "Bot Two", 50)
	life.record_hit(RIVAL, "Rival", 160)
	_check(life.damage_taken() == 65 and life.recap_lines()[-1] == "TOOK 65: Bot Two 50, Rival 15", "two death-tick hits share 40 HP and 25 armour: %s" % [life.recap_lines()])
	# Hits that were survived landed whole, before the death tick's are capped.
	life.reset()
	row["hp"] = 100
	row.erase("armor")
	life.observe_body(row)
	life.record_hit(RIVAL, "Rival", 30)
	row["hp"] = 70
	life.observe_body(row)
	life.body_gone(30)
	life.record_hit(RIVAL, "Rival", 160)
	_check(life.damage_taken() == 100, "30 survived plus a 160 finisher on 70 HP is 100: %d" % life.damage_taken())
	# A killer's armour is named as armour, never folded into health.
	life.record_frag(SELF, RIVAL, "Rival", 30)
	life.record_kill_facts("rail", {"x": -10.0, "y": 1.5, "z": 0.0, "hp": 100, "armor": 73})
	_check(life.recap_lines()[0] == "RAILGUN // 10 M BEHIND YOU // THEY KEPT 100 HP 73 ARMOR", "armour is labelled: %s" % [life.recap_lines()])


func _bearings() -> void:
	# Eight sectors clockwise from ahead; forward is (cos yaw, sin yaw) on x, z
	# and right is yaw + 90 degrees, as the movement mirror has it.
	var cases: Array[Array] = [
		[Vector3(10, 0, 0), "AHEAD"], [Vector3(10, 0, 10), "AHEAD RIGHT"], [Vector3(0, 0, 10), "RIGHT"],
		[Vector3(-10, 0, 10), "BEHIND RIGHT"], [Vector3(-10, 0, 0), "BEHIND YOU"], [Vector3(-10, 0, -10), "BEHIND LEFT"],
		[Vector3(0, 0, -10), "LEFT"], [Vector3(10, 0, -10), "AHEAD LEFT"],
	]
	for yaw: float in [0.0, 2.0]:
		for entry: Array in cases:
			var offset: Vector3 = entry[0]
			var rotated: Vector3 = Vector3(offset.x * cos(yaw) - offset.z * sin(yaw), 0.0, offset.x * sin(yaw) + offset.z * cos(yaw))
			var life: LocalLife = LocalLife.new()
			life.observe_body(_body(5.0, 1.5, -3.0, yaw))
			life.record_frag(SELF, RIVAL, "Rival", 1)
			life.record_kill_facts("tack", {"x": 5.0 + rotated.x, "y": 1.5, "z": -3.0 + rotated.z, "hp": 100})
			var line: String = life.recap_lines()[0]
			_check(line.contains(" M " + str(entry[1]) + " //"), "yaw %.1f bearing %s: %s" % [yaw, entry[1], line])
	var high: LocalLife = LocalLife.new()
	high.observe_body(_body(0.0, 1.5, 0.0, 0.0))
	high.record_frag(SELF, RIVAL, "Rival", 1)
	high.record_kill_facts("sniper", {"x": 30.0, "y": 9.5, "z": 0.0, "hp": 100})
	_check(high.recap_lines()[0] == "SNIPER RIFLE // 31 M AHEAD ABOVE // THEY KEPT 100 HP", "a killer on a ledge reads above: %s" % [high.recap_lines()])


func _boundaries() -> void:
	var life: LocalLife = LocalLife.new()
	life.observe_body({"x": "1", "y": 0.0, "z": 0.0, "yaw": 0.0})
	life.record_hit(RIVAL, "Rival", -5)
	life.record_hit(RIVAL, "Rival", 25.5)
	life.record_hit(RIVAL, "Rival", "40")
	life.record_hit(null, null, 30)
	_check(life.damage_taken() == 0, "malformed or anonymous damage is refused")
	life.record_frag(SELF, RIVAL, "Rival", 1)
	life.record_kill_facts("plasma", {"x": 1.0, "y": 0.0, "z": INF, "hp": 40})
	_check(life.recap_lines().is_empty(), "an unknown weapon, a non-finite killer and no pose say nothing: %s" % [life.recap_lines()])
	life.reset()
	life.observe_body(_body(0.0, 0.0, 0.0, 0.0))
	life.record_frag(SELF, RIVAL, "Rival", 1)
	life.record_kill_facts("rail", {"x": 10.0, "y": 0.0, "z": 0.0, "hp": 5000})
	_check(life.recap_lines() == PackedStringArray(["RAILGUN"]), "an impossible killer health refuses the row: %s" % [life.recap_lines()])
	life.record_hit(RIVAL, "A name far longer than any callsign the server would ever send", 10)
	_check(life.recap_lines()[1].length() < 64, "names are bounded: %s" % [life.recap_lines()])


## The longest recap a match can produce stays inside the view, on its two
## lines, at 1280x720 and 1280x800.
func _fits() -> void:
	var card: DeathCard = DeathCard.new()
	root.add_child(card)
	var lines: PackedStringArray = PackedStringArray(["FRAGGED BY COMPLIANCE-DRONE", "WATCHING COMPLIANCE-DRONE", "RESPAWN IN 4", "LOST RIFLE + RAILGUN"])
	var recap: PackedStringArray = PackedStringArray(["ROCKET LAUNCHER // 38 M BEHIND RIGHT ABOVE // THEY KEPT 100 HP 150 ARMOR",
		"TOOK 250: COMPLIANCE-DRONE 160, SIXTEEN-CHARACTER 90 +2 MORE"])
	for view: Vector2 in [Vector2(1280, 720), Vector2(1280, 800)]:
		card.size = view
		card.present(lines, false, recap)
		for _frame: int in range(3):
			await process_frame
		card.present(lines, false, recap)
		var plate: Rect2 = card.plate_rect()
		_check(plate.size.y > 0.0 and plate.end.y <= view.y and plate.position.x >= 0.0 and plate.end.x <= view.x,
			"the full recap fits %s: %s" % [view, plate])
	card.queue_free()
	await process_frame


## The real manager and HUD: hit events, the death snapshot and the frag
## fact, then one frame. The card carries the recap on that frame.
func _first_frame() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var network: CaptureNetwork = CaptureNetwork.new()
	manager.set("net_client", network)
	manager.set("is_human_player", true)
	manager.set("hud", hud)
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	root.add_child(camera)
	camera.set_process(false)
	manager.camera = camera
	var me: Dictionary = {"id": SELF, "name": "Meat", "x": 0.0, "y": 1.5, "z": 0.0, "yaw": PI * 0.5, "pitch": 0.0, "hp": 100}
	var rival: Dictionary = {"id": RIVAL, "name": "Rival", "x": 0.0, "y": 1.5, "z": 18.0, "yaw": 0.0, "pitch": 0.0, "hp": 71}
	manager.latest_snapshot = {"tick": 40, "players": [me, rival]}
	manager.call("_update_local_fp_hud", [me, rival])
	# A survived hit: its snapshot shows the loss, then its event follows.
	me["hp"] = 70
	manager.latest_snapshot = {"tick": 41, "players": [me, rival]}
	manager.call("_update_local_fp_hud", [me, rival])
	manager.call("_on_event_received", {"event": "hit", "shooter": "Rival", "shooter_id": RIVAL, "target": "Meat", "target_id": SELF, "damage": 30, "target_hp_after": 70})
	# The death snapshot omits the body; a 160 hit finishes 70 HP, then the frag.
	manager.latest_snapshot = {"tick": 42, "players": [rival]}
	manager.call("_update_local_fp_hud", [rival])
	manager.call("_on_event_received", {"event": "hit", "shooter": "Rival", "shooter_id": RIVAL, "target": "Meat", "target_id": SELF, "damage": 160, "target_hp_after": 0})
	var fact_usec: int = Time.get_ticks_usec()
	manager.call("_on_event_received", {"event": "frag", "killer": "Rival", "victim": "Meat", "killer_score": 1, "killer_id": RIVAL, "victim_id": SELF, "weapon": "flechette"})
	manager.call("_process", 1.0 / 60.0)
	var shown_usec: int = Time.get_ticks_usec() - fact_usec
	_check(hud.death_card.visible, "the card is up on the first frame")
	_check(hud.death_card.recap() == "RIFLE // 18 M AHEAD // THEY KEPT 71 HP", "the recap names weapon, range, bearing and the killer's health: " + hud.death_card.recap())
	_check(hud.death_card.taken() == "TOOK 100: Rival 100", "the recap names the damage that landed, never overkill: " + hud.death_card.taken())
	_check(shown_usec < RECAP_GATE_USEC, "recap within the 300 ms gate: %d us" % shown_usec)
	print("test_death_recap: frag fact to recap on the card in 1 frame, %d us of handling" % shown_usec)
	# The recap never holds the countdown: the server's number is still shown.
	manager.call("_on_ack_received", {"seq": 1, "tick": 42, "x": 0.0, "z": 0.0, "yaw": 0.0, "respawn_ticks": 60})
	manager.call("_process", 1.0 / 60.0)
	_check(hud.death_card.timing() == "RESPAWN IN 3", "the countdown is the server's: " + hud.death_card.timing())
	# Layout settles over a drawn frame or two, as it does in a match.
	for _frame: int in range(3):
		await process_frame
		manager.call("_process", 1.0 / 60.0)
	_check(hud.death_card.plate_rect().size.y > 0.0 and hud.death_card.plate_rect().end.y <= hud.death_card.size.y, "the plate with the recap fits the view: %s in %s" % [hud.death_card.plate_rect(), hud.death_card.size])
	manager.call("_reset_local_life")
	_check(not hud.death_card.visible and hud.death_card.recap().is_empty(), "leaving clears the recap")
	manager.free()
	network.free()
	camera.free()
	hud.queue_free()
	await process_frame
