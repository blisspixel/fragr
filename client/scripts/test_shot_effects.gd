extends SceneTree

class HudProbe extends Node:
	var equipment_hud: EquipmentHud = EquipmentHud.new()
	var combat_feed: CombatFeed = CombatFeed.new()
	var fired: Array[String] = []
	var hits: Array[String] = []
	func show_fire_juice(weapon: String) -> void:
		fired.append(weapon)
	func show_hit_marker(_damage: int, weapon: String) -> void:
		hits.append(weapon)

var _failures: int = 0

class PawnProbe extends Node:
	var fired: Array[String] = []
	func get_weapon_name() -> String:
		return "Tack"
	func show_muzzle_flash(weapon: String) -> void:
		fired.append(weapon)

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_shot_effects: " + message)

func _shot(kind: String = "solid", weapon: String = "rail") -> Dictionary:
	var impact: Dictionary = {"kind": kind}
	if kind != "range":
		impact["normal"] = [0.0, 1.0, 0.0]
	return {"shooter_id": "self", "hit": kind == "fighter", "damage": 80,
		"trace": {"weapon": weapon, "origin": [0.0, 1.6, 0.0], "end": [3.0, 0.0, 0.0], "impact": impact}}

func _blast(target: String, kind: String, count: int, damage: int) -> Dictionary:
	var shot: Dictionary = _shot(kind, "scatter")
	shot["hit"] = kind == "fighter"
	shot["damage"] = damage
	if kind == "fighter":
		shot["target_id"] = target
	var pellets: Array = []
	for i in range(count):
		var impact: Dictionary = {"kind": kind}
		if kind != "range":
			impact["normal"] = [-1.0, 0.0, 0.0]
		pellets.append({"end": [3.0, 1.2 + 0.1 * i, 0.2 * i], "impact": impact})
	shot["trace"]["pellets"] = pellets
	shot["trace"]["end"] = pellets[0]["end"]
	shot["trace"]["impact"] = pellets[0]["impact"]
	return shot

func _run() -> void:
	var effects: ShotEffects = ShotEffects.new()
	root.add_child(effects)
	# One scatter blast: four pellets in one fighter, two in another, one lost.
	effects.ingest(1, [_blast("a", "fighter", 4, 40), _blast("b", "fighter", 2, 20), _blast("", "range", 1, 0)])
	_check(effects.active_count() == 7, "every pellet draws its own trace and impact")
	_check(effects.has_shot_from("self", "fighter") and effects.has_shot_from("self", "range"), "pellet impacts keep their own kind")
	effects.clear()
	var bad_blasts: Array = []
	var too_many: Dictionary = _blast("a", "fighter", 8, 80)
	bad_blasts.append(too_many)
	var not_scatter: Dictionary = _blast("a", "fighter", 2, 20)
	not_scatter["trace"]["weapon"] = "rail"
	bad_blasts.append(not_scatter)
	var broken: Dictionary = _blast("a", "fighter", 3, 30)
	broken["trace"]["pellets"][1]["end"] = [NAN, 0, 0]
	bad_blasts.append(broken)
	var empty: Dictionary = _blast("a", "fighter", 1, 10)
	empty["trace"]["pellets"] = []
	bad_blasts.append(empty)
	effects.ingest(1, bad_blasts)
	_check(effects.active_count() == 0, "oversized, foreign, empty or malformed pellet lists draw nothing")
	effects.clear()
	effects.ingest(1, [_shot(), _shot("fighter", "scatter"), _shot("range", "flechette")])
	_check(effects.active_count() == 3 and effects.visible, "all impact kinds create bounded presentation")
	_check(effects.get_node("Surface").mesh.get_surface_count() == 1, "effects share one mesh surface")
	var material: StandardMaterial3D = effects.get_node("Surface").mesh.surface_get_material(0)
	_check(not material.no_depth_test, "effects must remain occluded by world geometry")
	effects.ingest(1, [_shot()])
	effects.ingest(0, [_shot()])
	_check(effects.active_count() == 3, "duplicate and reordered snapshots cannot repeat effects")
	effects._process(0.07)
	_check(effects.active_count() == 2, "range-only tracers expire without emitting an empty surface")
	effects._process(0.18)
	_check(effects.active_count() == 0 and not effects.visible, "every effect expires")
	_check(effects.get_node("Surface").mesh.get_surface_count() == 0, "expiry releases draw geometry")
	var malformed: Array = [null, {}, {"trace": []}]
	for endpoint in [[], [0, 0], ["bad", 0, 0], [NAN, 0, 0], [INF, 0, 0], [9000, 0, 0], [2000, 0, 0]]:
		var bad: Dictionary = _shot()
		bad["trace"]["end"] = endpoint
		malformed.append(bad)
	for normal in [[], [0, 0, 0], [0, 2, 0], [0, INF, 0]]:
		var bad: Dictionary = _shot()
		bad["trace"]["impact"]["normal"] = normal
		malformed.append(bad)
	malformed.append(_shot("unknown"))
	malformed.append(_shot("solid", "unknown"))
	effects.ingest(2, malformed)
	_check(effects.active_count() == 0, "malformed vectors and unknown kinds do not enter the renderer")
	var many: Array = []
	for i in range(ShotEffects.MAX_EFFECTS + 10):
		var item: Dictionary = _shot()
		item["shooter_id"] = str(i)
		many.append(item)
	effects.ingest(3, many)
	_check(effects.active_count() == ShotEffects.MAX_EFFECTS, "the active effect cap is enforced")
	_check(not effects.has_shot_from("0") and effects.has_shot_from(str(ShotEffects.MAX_EFFECTS + 9)), "new shots evict the oldest effect")
	effects.clear()
	var excessive: Array = []
	excessive.resize(ShotEffects.MAX_RESULTS + 1)
	excessive.fill(_shot())
	effects.ingest(4, excessive)
	_check(effects.active_count() == 0, "oversized result batches are rejected")
	var cut: Dictionary = _shot("fighter", "shiv")
	cut["trace"]["end"] = [2.0, 1.2, 0.0]
	var long_cut: Dictionary = _shot("fighter", "shiv")
	long_cut["trace"]["end"] = [2.4, 1.2, 0.0]
	var reaching_punch: Dictionary = _shot("fighter", "fists")
	reaching_punch["trace"]["end"] = [2.0, 1.2, 0.0]
	effects.ingest(5, [cut, long_cut, reaching_punch, _shot("range", "shiv")])
	_check(effects.active_count() == 1 and effects.has_shot_from("self", "fighter"), "a Shiv cut draws inside its own reach, never as a tracer or at fist reach")
	effects.clear()
	# The real match route must retain the weapon even with no surviving pawn.
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.settings = FragrSettings.new()
	var hud: HudProbe = HudProbe.new()
	game.hud = hud
	game.net_client = game.get_node("NetClient")
	game.net_client.player_id = "self"
	game.is_human_player = true
	game.shot_effects = effects
	game._process_shot_results([_shot("fighter")], 5)
	game._process_shot_results([_shot("fighter")], 5)
	_check(hud.fired == ["Rail"] and hud.hits == ["Rail"], "HUD uses authoritative weapon once after shooter death")
	var corpse_hit: Dictionary = _shot("fighter")
	corpse_hit["damage"] = 0
	game._process_shot_results([corpse_hit], 6)
	_check(hud.fired.size() == 2 and hud.hits.size() == 1, "zero-damage impacts cannot confirm another damaging hit")
	var pawn: PawnProbe = PawnProbe.new()
	root.add_child(pawn)
	game.players["self"] = pawn
	game._process_shot_results([_shot("range", "fists")], 7)
	_check(pawn.fired == ["Fists"] and hud.fired.back() == "Fists", "a same-tick Tack pickup cannot turn a punch into gun feedback")
	game._process_shot_results([_shot("range", "tack")], 8)
	_check(pawn.fired == ["Fists", "Tack"] and hud.fired.back() == "Tack", "sidearm evidence reaches both first and third person")
	var blast_hud: int = hud.fired.size()
	var blast_hits: int = hud.hits.size()
	game._process_shot_results([_blast("a", "fighter", 4, 40), _blast("b", "fighter", 2, 20), _blast("", "range", 1, 0)], 9)
	_check(hud.fired.size() == blast_hud + 1 and hud.hits.size() == blast_hits + 1 and hud.fired.back() == "Scatter", "one blast is one kick and one hit marker")
	_check(effects.active_count() >= 7, "the blast reaches the world as seven pellets")
	game._clear_world()
	_check(effects.active_count() == 0, "role teardown clears world effects")
	game._process_shot_results([_shot()], 1)
	_check(effects.active_count() == 1, "new sessions may restart tick numbering")
	game._on_map_info({"map_name": "Test"})
	_check(effects.active_count() == 0, "map replacement clears old impacts")
	game.free()
	hud.equipment_hud.free()
	hud.combat_feed.free()
	hud.free()
	effects.queue_free()
	await process_frame
	if _failures == 0:
		print("test_shot_effects: PASS validated traces, bounded geometry, expiry, trades, lifecycle")
	quit(0 if _failures == 0 else 1)
