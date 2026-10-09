extends SceneTree

class CaptionProbe extends Node:
	func clear() -> void:
		pass

class HudProbe extends Node:
	var equipment_hud: EquipmentHud = EquipmentHud.new()
	var combat_feed: CombatFeed = CombatFeed.new()
	var crawler_caption: CaptionProbe = CaptionProbe.new()
	var fired: Array[String] = []
	var hits: Array[String] = []
	var blocked: Array[String] = []
	func show_fire_juice(weapon: String) -> void:
		fired.append(weapon)
	func show_hit_marker(damage: int, weapon: String) -> void:
		if damage > 0:
			hits.append(weapon)
		else:
			blocked.append(weapon)

var _failures: int = 0

class PawnProbe extends Node:
	var fired: Array[String] = []
	func get_weapon_name() -> String:
		return "Tack"
	func show_muzzle_flash(weapon: String) -> void:
		fired.append(weapon)

func _initialize() -> void:
	set_meta("fragr_automated", true)
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

## The Sniper's evidence draws a short streak at the far end, never the
## Railgun's line back to the muzzle.
func _check_sniper_tracer() -> void:
	var far: Dictionary = _shot("fighter", "sniper")
	far["trace"]["origin"] = [0.0, 1.6, 0.0]
	far["trace"]["end"] = [70.0, 1.6, 0.0]
	var rail: Dictionary = far.duplicate(true)
	rail["trace"]["weapon"] = "rail"
	for case: Array in [[far, "sniper"], [rail, "rail"]]:
		var effects: ShotEffects = ShotEffects.new()
		root.add_child(effects)
		effects.ingest(1, [case[0]])
		_check(effects.active_count() == 1, case[1] + " evidence is accepted")
		var nearest: float = INF
		for vertex: Vector3 in _vertices(effects):
			nearest = minf(nearest, vertex.x)
		if case[1] == "sniper":
			_check(nearest >= 70.0 - ShotEffects.SNIPER_TRACER_METRES - 0.01, "the Sniper tracer stays near the impact, nearest x %.2f" % nearest)
		else:
			_check(nearest < 1.0, "the Railgun beam reaches back toward the muzzle")
		effects.queue_free()

func _vertices(effects: ShotEffects) -> PackedVector3Array:
	var mesh: Mesh = effects.get_node("Surface").mesh
	if mesh.get_surface_count() == 0:
		return PackedVector3Array()
	var arrays: Array = mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]

## Impact sprite corners, on their own surface beside the traces.
func _impact_vertices(effects: ShotEffects) -> PackedVector3Array:
	var mesh: Mesh = effects.get_node("Impacts").mesh
	if mesh.get_surface_count() == 0:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _check_camera_clearance(effects: ShotEffects, camera: Camera3D, message: String) -> void:
	var transform: Transform3D = camera.get_camera_transform()
	var forward: Vector3 = -transform.basis.z.normalized()
	var clearance: float = maxf(ShotEffects.CAMERA_CLEARANCE, camera.near)
	var vertices: PackedVector3Array = _vertices(effects)
	_check(not vertices.is_empty(), message + " keeps the distant trace")
	vertices.append_array(_impact_vertices(effects))
	for vertex: Vector3 in vertices:
		_check(forward.dot(effects.to_global(vertex) - transform.origin) >= clearance - 0.00001,
			message + " emits no polygon inside the camera clearance")

func _test_incoming_camera(effects: ShotEffects) -> void:
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.0, 1.6, 0.0)
	camera.make_current()
	var incoming: Dictionary = _shot("fighter", "flechette")
	incoming["shooter_id"] = "hostile"
	incoming["trace"]["origin"] = [0.0, 1.6, -8.0]
	incoming["trace"]["end"] = [0.0, 1.6, -0.025]
	incoming["trace"]["impact"]["normal"] = [0.0, 0.0, 1.0]
	effects.ingest(100, [incoming])
	_check_camera_clearance(effects, camera, "incoming first-person hit")
	_check(effects.active_count() == 1 and effects.has_shot_from("hostile", "fighter"),
		"camera clipping retains resolved incoming hit evidence")
	effects._process(0.07)
	_check(_vertices(effects).is_empty() and not effects.visible and effects.is_processing(),
		"listener impact creates no empty surface but retains its expiry clock")
	effects._process(0.18)
	_check(effects.active_count() == 0 and not effects.is_processing(), "clipped effects still expire")
	effects.clear()
	# A Sniper shot landing on the viewer draws no streak into a scoped lens.
	var marksman_shot: Dictionary = incoming.duplicate(true)
	marksman_shot["trace"]["weapon"] = "sniper"
	marksman_shot["trace"]["origin"] = [0.0, 1.6, -70.0]
	effects.ingest(100, [marksman_shot])
	_check(_vertices(effects).is_empty() and effects.active_count() == 1,
		"an incoming Sniper hit on the viewer keeps evidence without a streak in the lens")
	effects.clear()
	marksman_shot["trace"]["end"] = [0.0, 1.6, -6.0]
	effects.ingest(100, [marksman_shot])
	_check(not _vertices(effects).is_empty(), "a Sniper impact beyond the viewer clearance keeps its streak")
	effects.clear()
	# Prediction can move the eye into an impact after the snapshot is presented.
	incoming["trace"]["end"] = [0.0, 1.6, -3.0]
	effects.ingest(101, [incoming])
	effects._process(0.07)
	_check(not _vertices(effects).is_empty(), "distant fighter impact remains visible")
	camera.position.z = -2.95
	effects._process(0.0)
	_check(_vertices(effects).is_empty() and effects.active_count() == 1,
		"moving predicted eye into a live impact clips the rebuilt geometry")
	camera.position.z = 1.0
	effects._process(0.0)
	_check_camera_clearance(effects, camera, "moving eye away from impact")
	effects.clear()
	# Use the active camera orientation, including spectator eye changes.
	camera.position.z = 0.0
	camera.rotation.y = PI * 0.5
	incoming["trace"]["origin"] = [-8.0, 1.6, 0.0]
	incoming["trace"]["end"] = [-0.025, 1.6, 0.0]
	incoming["trace"]["impact"]["normal"] = [1.0, 0.0, 0.0]
	effects.ingest(102, [incoming])
	_check_camera_clearance(effects, camera, "rotated spectator eye")
	camera.near = 1.0
	effects._process(0.0)
	_check_camera_clearance(effects, camera, "larger configured camera near plane")
	effects.clear()
	incoming["trace"]["weapon"] = "shiv"
	incoming["trace"]["origin"] = [-1.0, 1.6, 0.0]
	effects.ingest(103, [incoming])
	_check(effects.active_count() == 1 and _vertices(effects).is_empty() and _impact_vertices(effects).is_empty(),
		"close incoming melee impacts cannot cover the first-person eye")
	effects.clear()
	# A beam through the eye retains its distant section after polygon clipping.
	incoming["trace"]["weapon"] = "rail"
	incoming["trace"]["origin"] = [-8.0, 1.6, 0.0]
	incoming["trace"]["end"] = [8.0, 1.6, 0.0]
	effects.ingest(104, [incoming])
	_check_camera_clearance(effects, camera, "beam crossing the eye")
	effects.clear()
	camera.free()

func _run() -> void:
	root.set_meta("fragr_automated", true)
	if DisplayServer.get_name() != "headless":
		# Keep raster evidence isolated from the headless match-glue fixtures.
		await _rendered_camera_change()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if _failures == 0:
			print("test_shot_effects: PASS actual render-camera clearance")
		quit(0 if _failures == 0 else 1)
		return
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
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
	_check_sniper_tracer()
	_check(effects.get_node("Surface").mesh.get_surface_count() == 1, "effects share one mesh surface")
	_check(effects.impact_count() == 2, "solid and fighter hits draw one impact sprite each, a miss none")
	var sprites: ShaderMaterial = effects.get_node("Impacts").mesh.surface_get_material(0)
	_check(sprites.shader == ShotEffects.SPRITE_SHADER and sprites.shader.code.contains("camera_clearance")
		and not sprites.shader.code.contains("depth_test_disabled"), "impact sprites keep world depth and the camera clearance")
	_check(ShotVfx.impact_row("rail", "solid") == "rail" and ShotVfx.impact_row("scatter", "fighter") == "fighter"
		and ShotVfx.impact_row("tack", "solid") == "solid" and ShotVfx.impact_row("shiv", "fighter") == "melee",
		"each gun and surface picks its impact row")
	var first: Rect2 = ShotVfx.impact_uv("fighter", 0.0, ShotEffects.LIFETIME)
	var last: Rect2 = ShotVfx.impact_uv("fighter", ShotEffects.LIFETIME * 0.99, ShotEffects.LIFETIME)
	_check(first.position.x == 0.0 and is_equal_approx(last.position.x, 0.75) and first.position.y == last.position.y
		and is_equal_approx(first.position.y, 0.25), "an impact plays its row's four frames over its lifetime")
	for weapon: String in ["Tack", "Flechette", "Scatter", "Rail", "Sniper"]:
		var flash: Texture2D = ShotVfx.muzzle(weapon)
		_check(flash != null and flash.get_width() == 32 and flash.get_height() == 32, weapon + " has its own third-person flash")
	_check(ShotVfx.muzzle("Fists") == null, "a punch shows no flash")
	var material: ShaderMaterial = effects.get_node("Surface").mesh.surface_get_material(0)
	_check(material.shader == ShotEffects.CLEARANCE_SHADER
		and not material.shader.code.contains("depth_test_disabled")
		and material.get_shader_parameter("camera_clearance") == ShotEffects.CAMERA_CLEARANCE,
		"effects retain world depth and bounded actual render-camera clearance")
	effects.ingest(1, [_shot()])
	effects.ingest(0, [_shot()])
	_check(effects.active_count() == 3, "duplicate and reordered snapshots cannot repeat effects")
	effects._process(0.07)
	_check(effects.active_count() == 2, "range-only tracers expire without emitting an empty surface")
	effects._process(0.18)
	_check(effects.active_count() == 0 and not effects.visible, "every effect expires")
	_check(effects.impact_count() == 0, "expiry releases impact sprites")
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
	_test_incoming_camera(effects)
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
	_check(hud.fired.size() == 2 and hud.hits.size() == 1 and hud.blocked == ["Rail"], "a blocked body marks without confirming another damaging hit")
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
	# A neutral body stops a resolved ray without a participant ID or health.
	# Physical impact evidence and damaging hit confirmation are independent.
	var neutral: Dictionary = _shot("fighter", "flechette")
	neutral["hit"] = false
	neutral["damage"] = 0
	var neutral_fires: int = hud.fired.size()
	var neutral_hits: int = hud.hits.size()
	var neutral_blocked: int = hud.blocked.size()
	effects.clear()
	game._process_shot_results([neutral], 10)
	_check(effects.active_count() == 1 and effects.impact_count() == 1
		and effects.has_shot_from("self", "fighter"), "a no-health neutral body impact retains its resolved endpoint")
	_check(hud.fired.size() == neutral_fires + 1 and hud.hits.size() == neutral_hits and hud.blocked.size() == neutral_blocked,
		"a neutral body stop shows actual fire but grants no hit marker")
	await _resolved_dead_shooter_flash(game)
	game._clear_world()
	_check(effects.active_count() == 0, "role teardown clears world effects")
	game._process_shot_results([_shot()], 1)
	_check(effects.active_count() == 1, "new sessions may restart tick numbering")
	game._on_map_info({"map_name": "Test"})
	_check(effects.active_count() == 0, "map replacement clears old impacts")
	game.free()
	hud.equipment_hud.free()
	hud.combat_feed.free()
	hud.crawler_caption.free()
	hud.free()
	effects.queue_free()
	await process_frame
	_check(await retirement.drain(), "actual shot voices retire before the harness exits")
	if _failures == 0:
		print("test_shot_effects: PASS validated traces, bounded geometry, camera clearance, expiry, trades, lifecycle")
	quit(0 if _failures == 0 else 1)

func _resolved_dead_shooter_flash(game: Node) -> void:
	var previous: Node = game.players.get("self")
	for kind: String in PlayerBody.KINDS:
		var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
		root.add_child(pawn)
		await process_frame
		pawn.set_process(false)
		pawn.set_player_data("self", "Resolved trade fixture")
		var state: Dictionary = {"x": 0.0, "y": 1.5, "z": 0.0, "yaw": 0.0,
			"hp": 100, "weapon": "Rail", "body": kind}
		pawn.update_state(state, 1)
		pawn.set_predicted_position(Vector3(0, 1.5, 0), 0.0)
		pawn._process(0.05)
		_check(pawn.character_view != null, "trade fixture wears the actual live skin " + kind)
		# Snapshots apply zero health before presenting the same tick's resolved
		# shot. The ordinary pose pass must not hide that committed muzzle cue.
		state.hp = 0
		pawn.update_state(state, 2)
		game.players["self"] = pawn
		game._process_shot_results([_shot("range", "rail")], 11 if kind == PlayerBody.HUMAN else 12)
		pawn._process(0.01)
		_check(pawn.hp == 0 and pawn.muzzle.visible and pawn.muzzle.is_visible_in_tree(),
			"resolved dead shooter retains a visible third-person flash " + kind)
		_check(not pawn.weapon_sprite.is_visible_in_tree(), "a fallen body hides its carried gun " + kind)
		pawn.set_local_fp(true)
		_check(not pawn.muzzle.is_visible_in_tree(), "first-person hides the dead shooter's world flash " + kind)
		pawn.set_local_fp(false)
		_check(pawn.muzzle.is_visible_in_tree() and not pawn.weapon_sprite.is_visible_in_tree(),
			"leaving first-person restores the committed flash independently of its fallen gun " + kind)
		_check(pawn.muzzle.texture == ShotVfx.muzzle("Rail"), "trade retains the resolved weapon's flash " + kind)
		var deadline: int = Time.get_ticks_msec() + 2000
		while pawn.muzzle.visible and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(not pawn.muzzle.visible, "resolved trade flash expires through its ordinary timer " + kind)
		pawn.free()
	game.players["self"] = previous

func _rendered_camera_change() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 1.6, 0)
	camera.current = true
	var effects: ShotEffects = ShotEffects.new()
	viewport.add_child(effects)
	var impact: Dictionary = _shot("fighter", "flechette")
	impact["trace"]["end"] = [0.0, 1.6, -3.0]
	impact["trace"]["impact"]["normal"] = [0.0, 0.0, 1.0]
	effects.ingest(1, [impact])
	effects._process(0.07)
	effects.set_process(false)
	var surface: MeshInstance3D = effects.get_node("Surface")
	effects.visible = false
	var empty: Image = await _render_frame(viewport)
	var background: Color = empty.get_pixel(64, 64)
	effects.visible = true
	var distant: Image = await _render_frame(viewport)
	_check(_pixel_difference(distant.get_pixel(64, 64), background) > 0.1,
		"render material retains a real distant fighter impact")
	# Move the camera after the CPU clip, keeping the exact same resolved mesh.
	camera.position.z = -2.8
	var original: StandardMaterial3D = StandardMaterial3D.new()
	original.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	original.vertex_color_use_as_albedo = true
	original.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.material_override = original
	var impacts: MeshInstance3D = effects.get_node("Impacts")
	impacts.material_override = original
	var stale: Image = await _render_frame(viewport)
	_check(_pixel_difference(stale.get_pixel(64, 64), background) > 0.1,
		"the stale CPU-only meshes actually fill the aiming pixel")
	surface.material_override = null
	impacts.material_override = null
	var clipped: Image = await _render_frame(viewport)
	_check(_pixel_difference(clipped.get_pixel(64, 64), background) < 0.03,
		"actual render camera clips the stale mesh without rebuilding its evidence")
	_check(effects.active_count() == 1 and not _vertices(effects).is_empty() and effects.impact_count() == 1,
		"render clipping never discards or rewrites the authoritative shot evidence")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/m04-buildout-20260930")
	stale.save_png(directory.path_join("shot-camera-stale.png"))
	clipped.save_png(directory.path_join("shot-camera-clipped.png"))
	distant.save_png(directory.path_join("shot-camera-distant.png"))
	viewport.free()
	print("test_shot_effects: rendered PASS stale-camera impact, actual clip and distant retention")

func _render_frame(viewport: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

static func _pixel_difference(first: Color, second: Color) -> float:
	return Vector3(first.r, first.g, first.b).distance_to(Vector3(second.r, second.g, second.b))
