class_name CampaignProps
extends RefCounted

## Prepared campaign props (tools/campaign_props_20261025.json): canon-gated
## Meshy models with the pixel treatment, each standing in for a plain box.
## A site names the server solid that already holds the object; its box view
## (and any face panel the model now carries itself) is hidden and the model
## fills the same volume, so a shot still stops where it looks like it should.
## A site with no host solid stands only where nobody can walk. Collision is
## unchanged: the server owns every solid named here.
##
## Each prop is placed by the box it fills. Its prepared bounds, turned by a
## quarter-turn yaw, are scaled to that box; the scale may differ between
## axes by at most MAX_STRETCH_LOG either side of its mean, so a fit never
## turns into a different object.

const ROOT: String = "res://assets/models/campaign/"
const NAMES: Array[String] = ["civilian_tram", "correction_machine", "duffel", "galley", "gantry_hoist",
	"hard_luggage", "impound_tug", "lathe", "pilot_console", "ship_bunk", "stretcher", "supply_crate"]
const GROUP: StringName = &"campaign_prop"
const MAX_STRETCH_LOG: float = 0.15
const EPSILON: float = 0.001

## Map name to its sites. `host` is the solid's [min, max] or null for a
## site outside every walkable volume; `hide` names the host's own face
## panels the model replaces; `props` are [name, box min, box max, yaw in
## degrees] with the box in world metres.
static func sites() -> Dictionary:
	return {
		"Persons Unknown": [
			# The correction machine: the open intake toward the ward door.
			{"host": [Vector3(-4, 0, -15), Vector3(0, 3.2, -13)], "hide": ["vent"],
				"props": [["correction_machine", Vector3(-4, 0, -15), Vector3(0, 3.2, -13), 180]]},
		],
		"Port of Entry": [
			# The impound tug on the sealed apron, seen through the customs glass
			# on its way to the impound berth. Outside the shell: no host.
			{"host": null, "hide": [],
				"props": [["impound_tug", Vector3(28.6, 0, 21.0), Vector3(30.9, 2.9, 26.5), 90]]},
		],
		"Common Carrier": [
			# The pilot's two consoles, screens aft toward the pilot.
			{"host": [Vector3(1.5, 7.6, -16.8), Vector3(3.5, 8.5, -16.0)], "hide": [],
				"props": [["pilot_console", Vector3(1.5, 7.6, -16.8), Vector3(2.5, 8.5, -16.0), 0],
					["pilot_console", Vector3(2.5, 7.6, -16.8), Vector3(3.5, 8.5, -16.0), 0]]},
			# The galley island: two units on each face, back to back.
			{"host": [Vector3(4.5, 4.8, -5.8), Vector3(7.3, 5.9, -4.5)], "hide": [],
				"props": [["galley", Vector3(4.5, 4.8, -5.15), Vector3(5.9, 5.9, -4.5), 0],
					["galley", Vector3(5.9, 4.8, -5.15), Vector3(7.3, 5.9, -4.5), 0],
					["galley", Vector3(4.5, 4.8, -5.8), Vector3(5.9, 5.9, -5.15), 180],
					["galley", Vector3(5.9, 4.8, -5.8), Vector3(7.3, 5.9, -5.15), 180]]},
			# The crew berths, open toward the aisle between them.
			{"host": [Vector3(5.4, 4.8, -17.1), Vector3(7.3, 5.3, -15.9)], "hide": [],
				"props": [["ship_bunk", Vector3(5.4, 4.8, -17.1), Vector3(7.3, 5.3, -15.9), 0]]},
			{"host": [Vector3(5.4, 4.8, -12.7), Vector3(7.3, 5.3, -11.5)], "hide": [],
				"props": [["ship_bunk", Vector3(5.4, 4.8, -12.7), Vector3(7.3, 5.3, -11.5), 180]]},
		],
		"The Weight of Permission": [
			# Four lathes in two rows at the works' north edge, facing the floor.
			{"host": [Vector3(-23, 0.3, -35), Vector3(-17, 2.0, -31)], "hide": [],
				"props": [["lathe", Vector3(-23, 0.3, -32.9), Vector3(-20, 2.0, -31), 0],
					["lathe", Vector3(-20, 0.3, -32.9), Vector3(-17, 2.0, -31), 0],
					["lathe", Vector3(-23, 0.3, -35), Vector3(-20, 2.0, -33.1), 0],
					["lathe", Vector3(-20, 0.3, -35), Vector3(-17, 2.0, -33.1), 0]]},
			# The freight hoist under its beam, the hook block in the hook's solid.
			{"host": [Vector3(-0.4, 5.7, 18.2), Vector3(0.4, 8.1, 18.8)], "hide": [],
				"props": [["gantry_hoist", Vector3(-1.59, 5.7, 18.0), Vector3(0.57, 8.1, 19.0), 0]]},
		],
		"Planned Works": _planned_works(),
		"Local Exception": [
			# The tram left at the end of the line, pantograph folded.
			{"host": [Vector3(30, 0, -44), Vector3(33, 3.2, -34)], "hide": [],
				"props": [["civilian_tram", Vector3(30, 0, -44), Vector3(33, 3.2, -34), 90]]},
		],
	}

static func _planned_works() -> Array:
	var rows: Array = []
	# The street's stalled tram, pantograph folded.
	rows.append({"host": [Vector3(-24, 0, -21), Vector3(-15, 3.2, -18)], "hide": [],
		"props": [["civilian_tram", Vector3(-24, 0, -21), Vector3(-15, 3.2, -18), 0]]})
	# Crate stacks: a two-by-two grid of supply crates fills each solid.
	for stack: Array in [[Vector3(4, 0, 15), Vector3(6, 1.4, 17)], [Vector3(32, 0, 20), Vector3(34, 1.2, 22)],
			[Vector3(48.5, 0, 45), Vector3(50.5, 1.2, 47)], [Vector3(55, 0, 24), Vector3(57, 1.2, 26)]]:
		var low: Vector3 = stack[0]
		var high: Vector3 = stack[1]
		var props: Array = []
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var a: Vector3 = Vector3(lerpf(low.x, high.x, cell.x * 0.5), low.y, lerpf(low.z, high.z, cell.y * 0.5))
			var b: Vector3 = Vector3(lerpf(low.x, high.x, cell.x * 0.5 + 0.5), high.y, lerpf(low.z, high.z, cell.y * 0.5 + 0.5))
			props.append(["supply_crate", a, b, [0, 90, 180, 270][(cell.x + cell.y * 2 + int(low.x)) % 4]])
		rows.append({"host": [low, high], "hide": [], "props": props})
	return rows

## True when a site in this map replaces the solid with these bounds, so
## other dressing (Low Water's painted tram) leaves its faces alone.
static func replaces(info: Dictionary, low: Vector3, high: Vector3) -> bool:
	for site: Dictionary in sites().get(str(info.get("map_name", "")), []):
		if site["host"] is Array and _same(site["host"][0], low) and _same(site["host"][1], high):
			return true
	return false

## The solid indices of this map's sites whose host is present: the boxes a
## built cover hides behind its props.
static func host_indices(info: Dictionary) -> Array[int]:
	var hosts: Array[int] = []
	for site: Dictionary in sites().get(str(info.get("map_name", "")), []):
		if site["host"] is Array:
			var index: int = _host_index(info.get("solids", []), site["host"][0], site["host"][1])
			if index >= 0:
				hosts.append(index)
	return hosts

## Draws every site of this map whose host solid is present, inside `cover`,
## and hides the boxes and face panels the models replace. Returns the props.
static func build(cover: Node3D, info: Dictionary, solid_views: Array[MeshInstance3D]) -> Array[Node3D]:
	var placed: Array[Node3D] = []
	var solids: Array = info.get("solids", [])
	for site: Dictionary in sites().get(str(info.get("map_name", "")), []):
		var host: int = -1
		if site["host"] is Array:
			host = _host_index(solids, site["host"][0], site["host"][1])
			if host < 0:
				continue
		var props: Array[Node3D] = []
		for row: Array in site["props"]:
			var node: Node3D = place(cover, str(row[0]), row[1], row[2], float(row[3]))
			if node == null:
				break
			props.append(node)
		if props.size() != (site["props"] as Array).size():
			# A site draws whole or not at all, and then its box stays.
			for node: Node3D in props:
				node.queue_free()
			continue
		placed.append_array(props)
		if host >= 0:
			if host < solid_views.size() and is_instance_valid(solid_views[host]):
				solid_views[host].visible = false
			for child: Node in cover.get_children():
				if child.has_meta("host_solid") and int(child.get_meta("host_solid")) == host:
					for kind: String in site["hide"]:
						if str(child.name).ends_with("_" + kind):
							(child as Node3D).visible = false
	return placed

## One prepared prop filling the box from `low` to `high`, turned by `yaw`
## degrees (a quarter turn). Null, with an error, when the asset is missing
## or the box would stretch it past MAX_STRETCH_LOG.
static func place(parent: Node3D, prop: String, low: Vector3, high: Vector3, yaw: float) -> Node3D:
	var node: Node3D = instance(prop)
	if node == null:
		return null
	var bounds: AABB = model_bounds(node)
	var scale: Vector3 = fit_scale(bounds, high - low, yaw)
	if scale == Vector3.ZERO:
		push_error("campaign_props: %s would stretch past %.2f in its box" % [prop, MAX_STRETCH_LOG])
		node.free()
		return null
	node.scale = scale
	node.rotation.y = deg_to_rad(yaw)
	var target: Vector3 = high - low
	var centre: Vector3 = bounds.get_center()
	var offset: Vector3 = node.basis * Vector3(centre.x, bounds.position.y, centre.z)
	node.position = Vector3((low.x + high.x) * 0.5, low.y, (low.z + high.z) * 0.5) - offset
	node.set_meta("box", AABB(low, target))
	parent.add_child(node)
	return node

## One prepared prop at its prepared size times `scale`, standing with its
## floor centre on `feet` and turned by `yaw` degrees: possessions a
## presenter sets down outside any solid (a case under a resting evacuee).
static func stand(parent: Node3D, prop: String, feet: Vector3, yaw: float, scale: float = 1.0) -> Node3D:
	var node: Node3D = instance(prop)
	if node == null:
		return null
	var bounds: AABB = model_bounds(node)
	node.scale = Vector3.ONE * scale
	node.rotation.y = deg_to_rad(yaw)
	var centre: Vector3 = bounds.get_center()
	node.position = feet - node.basis * Vector3(centre.x, bounds.position.y, centre.z)
	parent.add_child(node)
	return node

## The scale, in the model's own axes, that fills `target` (world metres)
## with `bounds` turned by `yaw` degrees, or zero when that would stretch one
## axis past MAX_STRETCH_LOG from the mean. A quarter turn swaps x and z.
static func fit_scale(bounds: AABB, target: Vector3, yaw: float) -> Vector3:
	var turned: bool = roundi(yaw / 90.0) % 2 != 0
	var size: Vector3 = Vector3(bounds.size.z, bounds.size.y, bounds.size.x) if turned else bounds.size
	var scale: Vector3 = Vector3(target.x / size.x, target.y / size.y, target.z / size.z)
	if stretch_log(scale) > MAX_STRETCH_LOG + 0.0001:
		return Vector3.ZERO
	return Vector3(scale.z, scale.y, scale.x) if turned else scale

## The prepared model, crisp: nearest filtering on every surface.
static func instance(prop: String) -> Node3D:
	var scene: PackedScene = load(ROOT + prop + ".glb") as PackedScene if ResourceLoader.exists(ROOT + prop + ".glb") else null
	var node: Node3D = scene.instantiate() as Node3D if scene != null else null
	if node == null:
		push_error("campaign_props: missing prop " + prop)
		return null
	node.name = prop.to_pascal_case()
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var surface: MeshInstance3D = child as MeshInstance3D
		surface.layers = ArenaSky.WORLD_LAYERS
		for index: int in range(surface.get_surface_override_material_count()):
			var finish: BaseMaterial3D = surface.get_active_material(index) as BaseMaterial3D
			if finish != null:
				finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	node.add_to_group(GROUP)
	node.set_meta("prop", prop)
	return node

## The prepared mesh's bounds in the model's own frame.
static func model_bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var surface: MeshInstance3D = child as MeshInstance3D
		var box: AABB = surface.transform * surface.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

## Largest departure of one axis from the scale's geometric mean, in log units.
static func stretch_log(scale: Vector3) -> float:
	var mean: float = (log(scale.x) + log(scale.y) + log(scale.z)) / 3.0
	return maxf(absf(log(scale.x) - mean), maxf(absf(log(scale.y) - mean), absf(log(scale.z) - mean)))

static func _host_index(solids: Array, low: Vector3, high: Vector3) -> int:
	for index: int in range(solids.size()):
		var solid: Dictionary = solids[index]
		var a: Vector3 = Vector3(float(solid.get("min_x", 0.0)), float(solid.get("bottom", MoveStep.GROUND_Y)), float(solid.get("min_z", 0.0)))
		var b: Vector3 = Vector3(float(solid.get("max_x", 0.0)), float(solid.get("top", MoveStep.WALL_TOP)), float(solid.get("max_z", 0.0)))
		if _same(a, low) and _same(b, high):
			return index
	return -1

static func _same(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < EPSILON
