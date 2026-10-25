extends SceneTree

## Combat effects are pixel art, never placeholder blocks: no mesh under the
## combat effect presenters may be an untextured box. Also checks the blast's
## colour law (amber light, never Union red), the bounded light and mark
## budgets, surface classes from map materials and fighter bodies, and the
## one muzzle table both views read.

const OWNER: String = "00000000-0000-4000-8000-0000000000aa"
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_vfx_meshes: " + message)

## Every box mesh under `root_node` that has no texture on its material.
static func untextured_boxes(root_node: Node) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var nodes: Array[Node] = root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		nodes.append(root_node)
	for node: Node in nodes:
		var view: MeshInstance3D = node as MeshInstance3D
		if not view.mesh is BoxMesh:
			continue
		var material: Material = view.material_override
		if material == null:
			material = (view.mesh as BoxMesh).material
		if not _textured(material):
			found.append(str(root_node.get_path_to(view)))
	return found

static func _textured(material: Material) -> bool:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_texture != null
	if material is ShaderMaterial:
		for uniform: Dictionary in (material as ShaderMaterial).shader.get_shader_uniform_list():
			if (material as ShaderMaterial).get_shader_parameter(uniform["name"]) is Texture2D:
				return true
	return false

func _map() -> Dictionary:
	return {"map_id": 1, "half_extent": 20.0, "geometry_version": 2,
		"solids": [
			{"min_x": 2.0, "max_x": 3.0, "min_z": -2.0, "max_z": 2.0, "bottom": 0.0, "top": 3.0},
			{"min_x": -3.0, "max_x": -2.0, "min_z": -2.0, "max_z": 2.0, "bottom": 0.0, "top": 3.0},
		],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "concrete"], "decorations": []}}

func _run() -> void:
	var effects: GrenadeEffects = GrenadeEffects.new()
	root.add_child(effects)
	var decals: VfxDecals = VfxDecals.new()
	root.add_child(decals)
	effects.set_decals(decals)
	decals.set_map(_map())
	# Every device and effect the presenter can build, through its real paths.
	effects.apply({"tick": 1, "players": [{"id": OWNER}], "grenades": [{"id": 1, "owner_id": OWNER,
		"position": [0, 1, 0], "fuse_ticks": 30, "bounce_count": 0}]}, Vector3.ZERO)
	effects.apply({"tick": 2, "players": [{"id": OWNER}], "rockets": [{"id": 7, "owner_id": OWNER,
		"position": [1.0, 1.6, 0.0], "velocity": [18.0, 0.0, 0.0], "age_ticks": 0}]}, Vector3.ZERO)
	effects.apply({"tick": 3, "players": [{"id": OWNER}], "rockets": [{"id": 7, "owner_id": OWNER,
		"position": [1.9, 1.6, 0.0], "velocity": [18.0, 0.0, 0.0], "age_ticks": 1}],
		"explosions": [{"id": 9, "owner_id": OWNER, "position": [2.0, 0.3, 0.0], "radius": 4, "hits": []}]}, Vector3.ZERO)
	effects.add_child(effects._mine_body())
	effects.add_child(RemoteMineEffects.make_body())
	var canister: Node3D = Node3D.new()
	canister.add_child(effects._round(0.12, 0.24, ShotVfx.CANISTER_SKIN))
	effects.add_child(canister)
	_check(effects.rockets.size() == 1 and effects.bursts.size() == 1, "the fixture builds a rocket and a blast")
	var boxes: PackedStringArray = untextured_boxes(effects)
	_check(boxes.is_empty(), "no untextured box mesh in grenade, rocket, device or blast effects: " + ", ".join(boxes))
	var shots: ShotEffects = ShotEffects.new()
	root.add_child(shots)
	var travel: TravelingShots = TravelingShots.new()
	root.add_child(travel)
	travel.apply([{"id": 3, "x": 1.0, "y": 1.0, "z": 1.0}])
	for presenter: Node in [shots, travel, decals]:
		boxes = untextured_boxes(presenter)
		_check(boxes.is_empty(), "no untextured box mesh in %s: %s" % [presenter.name, ", ".join(boxes)])
	# The blast: amber light, bounded lights, a scorch on the wall it struck.
	var blast: BlastVfx = effects.blast
	_check(blast.lights_lit() == 1 and blast.fire.active_count() >= 1 and blast.debris.active_count() > 0,
		"one blast shows a fireball, debris and one light")
	var hue: float = ShotVfx.BLAST_LIGHT.h * 360.0
	_check(hue > 20.0 and hue < 50.0 and ShotVfx.BLAST_LIGHT.s > 0.4, "the blast light is amber, never red (hue %.0f)" % hue)
	for weapon: String in ShotVfx.MUZZLE_LOOK:
		var light: Color = ShotVfx.muzzle_light(weapon)
		var red: bool = light.s > 0.25 and (light.h * 360.0 < 20.0 or light.h * 360.0 > 340.0)
		var cyan: bool = light.s > 0.25 and light.h * 360.0 > 160.0 and light.h * 360.0 < 220.0
		_check(not red and not cyan, weapon + " muzzle light is neither Union red nor Inheritance cyan")
	_check(ShotVfx.muzzle_light("Unknown") == ShotVfx.muzzle_light(ShotVfx.MUZZLE_DEFAULT), "an unlisted gun lights like the default")
	_check(decals.scorch_count() == 1, "the blast scorched the steel wall it went off beside")
	for serial: int in range(10, 10 + BlastVfx.MAX_LIGHTS + 3):
		blast.blast(Vector3(0, 1, 0), 4.0, serial)
	_check(blast.lights_lit() <= BlastVfx.MAX_LIGHTS, "blast lights stay within their budget")
	_check(decals.scorch_count() <= VfxDecals.MAX_SCORCHES, "scorches stay within their budget")
	_check(is_equal_approx(BlastVfx.light_energy(0.0), BlastVfx.LIGHT_PEAK) and BlastVfx.light_energy(BlastVfx.LIGHT_SECONDS) == 0.0
		and BlastVfx.light_energy(0.1) < BlastVfx.LIGHT_PEAK, "the flare peaks at once and dies within its time")
	for step: int in range(40):
		blast.advance(0.05)
		blast.fire.advance(0.05)
		blast.smoke.advance(0.05)
		blast.debris.advance(0.05)
	_check(blast.lights_lit() == 0 and blast.fire.active_count() == 0 and blast.debris.active_count() == 0,
		"fire, debris and light all retire")
	_check(ShotVfx.blast_kick(0.0, 4.0) == 1.0 and ShotVfx.blast_kick(12.0, 4.0) == 0.0
		and ShotVfx.blast_kick(6.0, 4.0) > 0.0 and ShotVfx.blast_kick(INF, 4.0) == 0.0, "the view kick falls off to nothing by its reach")
	# Surfaces: registered materials and bodies pick their impact rows.
	_check(decals.surface_at(Vector3(2.0, 1.0, 0.0), Vector3.LEFT) == ShotVfx.METAL, "a shot on service steel is metal")
	_check(decals.surface_at(Vector3(-2.0, 1.0, 0.0), Vector3.RIGHT) == ShotVfx.CONCRETE, "a shot on concrete is concrete")
	_check(decals.surface_at(Vector3(0.0, 0.0, 0.0), Vector3.UP) == ShotVfx.CONCRETE, "the ground reads its own kit")
	shots.decals = decals
	shots.fighter_surface = func(id: String) -> String:
		return ShotVfx.SYNTHETIC if id == "agent" else ShotVfx.FLESH
	var marks: int = decals.mark_count()
	shots.ingest(1, [_shot("solid", [2.0, 1.2, 0.5], [-1, 0, 0], ""), _shot("fighter", [0.5, 1.2, 0.0], [-1, 0, 0], "agent"),
		_shot("fighter", [0.5, 1.2, 0.3], [-1, 0, 0], "person")])
	_check(decals.mark_count() == marks + 1, "a solid hit leaves one mark and a body hit none")
	_check(shots.has_shot_from("self", "solid"), "the solid hit is shown")
	var rows: PackedStringArray = PackedStringArray()
	for effect: ShotEffects.Effect in shots._effects:
		rows.append(ShotVfx.impact_row(effect.weapon, effect.kind, effect.surface))
	_check(rows == PackedStringArray(["metal", "synthetic", "flesh"]), "impact rows follow struck surfaces: " + str(rows))
	_check(ShotVfx.impact_row("rail", "fighter", ShotVfx.SYNTHETIC) == "rail" and ShotVfx.impact_row("fists", "solid", ShotVfx.METAL) == "melee",
		"the Railgun ring and melee smack keep their own rows on any surface")
	_check(ShotVfx.mark_cell("flechette", "fighter", ShotVfx.FLESH, 0) == "" and ShotVfx.mark_cell("rail", "solid", ShotVfx.METAL, 0) == "rail",
		"bodies take no mark; the Railgun leaves its scorch")
	for index: int in range(VfxDecals.MAX_MARKS + 6):
		decals.add_mark(Vector3(-2.0, 1.0 + index * 0.01, 0.0), Vector3.RIGHT, "concrete")
	_check(decals.mark_count() == VfxDecals.MAX_MARKS, "marks stay within their budget")
	_check(not decals.add_mark(Vector3(10.0, 1.0, 10.0), Vector3.RIGHT, "concrete"), "a point on no face takes no mark")
	decals._process(VfxDecals.SCORCH_SECONDS + 1.0)
	_check(decals.mark_count() == 0 and decals.scorch_count() == 0, "marks and scorches expire")
	decals.set_map({"map_id": 1})
	_check(not decals.add_mark(Vector3(-2.0, 1.0, 0.0), Vector3.RIGHT, "concrete"), "an invalid map leaves the marks inert")
	# The Railgun lingers and other tracers do not.
	shots.clear()
	shots.ingest(2, [_rail()])
	shots._process(ShotEffects.RAIL_SECONDS * 0.8)
	_check(shots.active_count() == 1, "the Railgun beam lingers")
	shots._process(ShotEffects.RAIL_SECONDS * 0.3)
	_check(shots.active_count() == 0, "the Railgun beam expires")
	for node: Node in [effects, decals, shots, travel]:
		node.queue_free()
	effects.reset()
	await process_frame
	if _failures == 0:
		print("test_vfx_meshes: PASS no untextured boxes, amber blast light, bounded lights and marks, surface rows, lingering rail")
	quit(0 if _failures == 0 else 1)

func _shot(kind: String, end: Array, normal: Array, target: String) -> Dictionary:
	var result: Dictionary = {"shooter_id": "self", "hit": kind == "fighter", "damage": 10,
		"trace": {"weapon": "flechette", "origin": [0.0, 1.6, 0.0], "end": end, "impact": {"kind": kind, "normal": normal}}}
	if not target.is_empty():
		result["target_id"] = target
	return result

func _rail() -> Dictionary:
	return {"shooter_id": "self", "hit": false, "damage": 0,
		"trace": {"weapon": "rail", "origin": [0.0, 1.6, 0.0], "end": [30.0, 1.6, 0.0], "impact": {"kind": "range"}}}
