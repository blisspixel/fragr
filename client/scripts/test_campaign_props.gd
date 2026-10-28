extends SceneTree

## The prepared campaign props stand where the server's solids already are,
## and the plain boxes they replaced cannot come back. Each level is built
## from its own authored map (or the server's native MapInfo receipt): every
## site's host is present, its box view is hidden, its props fill the volume
## within the stretch limit, carry crisp paint and add no collision, and no
## other visible mesh is left inside the volume beyond a named allowlist.
## The concourse's stretcher, cases and seats are the prepared props too.

const MAPS: Dictionary = {
	"Persons Unknown": "m02-persons-unknown",
	"Port of Entry": "m06_port_of_entry",
	"Common Carrier": "m10_common_carrier",
	"The Weight of Permission": "m13-weight-of-permission",
}
## Visible meshes allowed inside a replaced volume, by map and node name. A
## face panel the model does not carry sits on its face; only a fixture's
## backing reaches into the volume: the work strip light on the side of
## Local Exception's tram, which lights the end of the line.
const ALLOWED: Dictionary = {"Local Exception": ["FixtureMesh"]}
const TOLERANCE: float = 0.02

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_campaign_props: " + message)

func _run() -> void:
	_check_assets()
	var sites: Dictionary = CampaignProps.sites()
	for map_name: String in MAPS:
		var info: Dictionary = _authored(MAPS[map_name])
		_check(str(info.get("map_name", "")) == map_name, "%s converts from its authored map" % map_name)
		await _check_level(info, sites[map_name])
	var native: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m19_native.json"))
	_check(native is Dictionary and native.get("maps") is Array, "native Planned Works receipt")
	if native is Dictionary:
		var planned: Dictionary = native["maps"][0]
		await _check_level(planned, sites["Planned Works"])
		await _check_concourse(planned)
	var lifecycle: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m20_lifecycle.json"))
	_check(lifecycle is Dictionary and lifecycle.get("map_info") is Dictionary, "native Local Exception receipt")
	if lifecycle is Dictionary:
		await _check_level(lifecycle["map_info"], sites["Local Exception"])
	# A moved host is not guessed at: the site keeps its plain box.
	var moved: Dictionary = _authored("m02-persons-unknown")
	for solid: Dictionary in moved["solids"]:
		if is_equal_approx(float(solid["min_x"]), -4.0) and is_equal_approx(float(solid["min_z"]), -15.0):
			solid["max_x"] = -0.2
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(moved)
	_check(_props(cover).is_empty(), "a moved correction machine solid keeps its box and draws no prop")
	cover.queue_free()
	await process_frame
	# A box that would stretch a prop past the limit is refused; a quarter
	# turn swaps the axes it is measured on.
	var crate: AABB = AABB(Vector3(-0.5, 0.0, -0.4), Vector3(1.0, 1.0, 0.8))
	_check(CampaignProps.fit_scale(crate, Vector3(3.0, 1.0, 1.0), 0.0) == Vector3.ZERO, "a stretched crate is refused")
	_check(CampaignProps.fit_scale(crate, Vector3(1.0, 1.0, 0.8), 0.0).is_equal_approx(Vector3.ONE), "a crate fits its own box")
	_check(CampaignProps.fit_scale(crate, Vector3(0.8, 1.0, 1.0), 90.0).is_equal_approx(Vector3.ONE), "a turned crate fits the turned box")
	if _failures == 0:
		print("test_campaign_props: PASS props fill their server solids, replaced boxes stay gone, no collision, crisp paint, refusals for moved hosts and stretches")
	quit(0 if _failures == 0 else 1)

## Every prepared prop ships with its receipt and manifest entry.
func _check_assets() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	var listed: Dictionary = {}
	if manifest is Dictionary:
		for entry: Dictionary in manifest["models"]:
			listed[entry["file"]] = entry["sha256"]
	for prop: String in CampaignProps.NAMES:
		var path: String = CampaignProps.ROOT + prop + ".glb"
		_check(load(path) is PackedScene, "prop %s ships" % prop)
		_check(listed.get("campaign/%s.glb" % prop, "") == FileAccess.get_sha256(path), "prop %s is in the model manifest" % prop)
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
		_check(receipt is Dictionary and receipt.get("runtime_selected") == true and receipt.get("provenance") is Dictionary
			and receipt["provenance"].get("model") is Dictionary and receipt["provenance"].get("reference") is Dictionary
			and receipt.get("prepared_sha256") == FileAccess.get_sha256(path), "prop %s carries its provenance receipt" % prop)
		var node: Node3D = CampaignProps.instance(prop)
		if node != null:
			_check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), "prop %s adds no collision" % prop)
			for surface: Node in node.find_children("*", "MeshInstance3D", true, false):
				var finish: BaseMaterial3D = (surface as MeshInstance3D).get_active_material(0) as BaseMaterial3D
				_check(finish != null and finish.albedo_texture != null and finish.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
					"prop %s keeps crisp painted clusters" % prop)
			node.free()

func _check_level(info: Dictionary, sites: Array) -> void:
	var map_name: String = str(info.get("map_name", ""))
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	var presenter: Node3D = _presenter(map_name)
	if presenter != null:
		root.add_child(presenter)
		presenter.call("configure_map", info)
	await process_frame
	var props: Array[Node3D] = _props(cover)
	var expected: int = 0
	for site: Dictionary in sites:
		expected += (site["props"] as Array).size()
		for row: Array in site["props"]:
			var box: AABB = AABB(row[1], row[2] - row[1])
			var found: bool = false
			for prop: Node3D in props:
				if str(prop.get_meta("prop", "")) == str(row[0]) and _bounds(prop).position.distance_to(box.position) < TOLERANCE \
						and _bounds(prop).end.distance_to(box.end) < TOLERANCE:
					found = true
					_check(CampaignProps.stretch_log(prop.scale) <= CampaignProps.MAX_STRETCH_LOG + 0.0001, "%s %s stays within the stretch limit" % [map_name, row[0]])
			_check(found, "%s: %s fills its box %s" % [map_name, row[0], box])
		if not site["host"] is Array:
			continue
		var host: AABB = AABB(site["host"][0], site["host"][1] - site["host"][0])
		var index: int = _solid_index(info, host)
		_check(index >= 0, "%s: host %s is a server solid" % [map_name, host])
		var view: MeshInstance3D = cover.get_node_or_null("Solid_%d" % index) as MeshInstance3D
		_check(view != null and not view.visible, "%s: the plain box at %s is hidden" % [map_name, host])
		# Nothing but the props (and the allowlist) is drawn inside the volume.
		var inner: AABB = host.grow(-TOLERANCE)
		for scene: Node in [cover, presenter]:
			if scene == null:
				continue
			for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
				var mesh: MeshInstance3D = node as MeshInstance3D
				if not mesh.is_visible_in_tree() or mesh.mesh == null or _inside_prop(mesh) or str(mesh.name) in ALLOWED.get(map_name, []):
					continue
				var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
				# Merged town dressing spans whole streets; it is checked below by count.
				if bounds.size.x > host.size.x * 4.0 + 4.0 or bounds.size.z > host.size.z * 4.0 + 4.0:
					continue
				_check(not bounds.intersects(inner), "%s: %s still draws inside the replaced volume %s" % [map_name, mesh.name, host])
	_check(props.size() == expected, "%s places %d props (got %d)" % [map_name, expected, props.size()])
	if map_name == "Planned Works":
		var town: Node = presenter.find_child("TownDressing", true, false) if presenter != null else null
		_check(town != null and int(town.get_meta("trams", -1)) == 1, "Low Water paints only Splice's tram; the stalled car is the prepared model")
	if presenter != null:
		presenter.queue_free()
	cover.queue_free()
	await process_frame

## The concourse's carried stretcher, the cases on the luggage cart and the
## seats of the resting household are prepared props, never boxes again.
func _check_concourse(info: Dictionary) -> void:
	var works: M19Works = M19Works.new()
	root.add_child(works)
	var entered: Array[VisualInstance3D] = []
	var observe: Callable = func(node: Node) -> void:
		if node is VisualInstance3D and works.is_ancestor_of(node):
			entered.append(node)
			var ancestor: Node = node.get_parent()
			while ancestor != works and not ancestor is LatchView:
				ancestor = ancestor.get_parent()
			var expected: int = ArenaSky.ACTOR_LAYERS if ancestor is LatchView else ArenaSky.WORLD_LAYERS
			_check(node.layers == expected, "Planned Works enters with final render layers: " + str(node.name))
	node_added.connect(observe)
	works.configure_map(info)
	node_added.disconnect(observe)
	_check(not entered.is_empty(), "Planned Works layer check observed live geometry")
	await process_frame
	for name: String in ["StretcherBed", "Blanket", "RestCase"]:
		_check(works.find_children(name, "MeshInstance3D", true, false).is_empty(), "the concourse draws no %s box" % name)
	# Loose cases set down in the hall or on the pier are props; a case a
	# walker carries stays part of that person's figure.
	for box: Node in works.find_children("Case*", "MeshInstance3D", true, false):
		var holder: String = str(box.get_parent().name)
		_check(holder != "ConcourseCrowd" and not holder.begins_with("PierKnot"), "the concourse sets down no %s box" % box.name)
	var counts: Dictionary = {}
	for prop: Node3D in _props(works):
		counts[prop.get_meta("prop")] = int(counts.get(prop.get_meta("prop"), 0)) + 1
	_check(int(counts.get("stretcher", 0)) == 1, "the Clerk and the porter carry the prepared stretcher")
	_check(int(counts.get("hard_luggage", 0)) == 3, "three cases ride the luggage cart")
	_check(int(counts.get("duffel", 0)) >= 5, "duffels top the cart and seat the resting people")
	var stretcher: Node3D = works.find_child("Stretcher", true, false) as Node3D
	var canvas: Node3D = stretcher.find_child("Stretcher", true, false) as Node3D if stretcher != null else null
	_check(canvas != null and canvas.get_meta("prop", "") == "stretcher", "the stretcher prop hangs between its carriers")
	works.queue_free()
	await process_frame

func _presenter(map_name: String) -> Node3D:
	match map_name:
		"Planned Works": return M19Works.new()
		"Local Exception": return M20Waterworks.new()
	return null

func _props(scene: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in scene.find_children("*", "Node3D", true, false):
		if node.is_in_group(CampaignProps.GROUP):
			found.append(node as Node3D)
	return found

func _inside_prop(node: Node) -> bool:
	var at: Node = node
	while at != null:
		if at.is_in_group(CampaignProps.GROUP):
			return true
		at = at.get_parent()
	return false

func _bounds(prop: Node3D) -> AABB:
	return prop.global_transform * CampaignProps.model_bounds(prop)

func _solid_index(info: Dictionary, host: AABB) -> int:
	var solids: Array = info["solids"]
	for index: int in range(solids.size()):
		var solid: Dictionary = solids[index]
		var low: Vector3 = Vector3(float(solid["min_x"]), float(solid.get("bottom", 0.0)), float(solid["min_z"]))
		var high: Vector3 = Vector3(float(solid["max_x"]), float(solid.get("top", 0.0)), float(solid["max_z"]))
		if low.distance_to(host.position) < 0.001 and high.distance_to(host.end) < 0.001:
			return index
	return -1

## A MapInfo from the authored map file, the way the server sends it: solids
## with their surfaces, and face panels by solid index.
func _authored(file: String) -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/%s.json" % file))
	if not source is Dictionary:
		_check(false, "cannot read server/maps/%s.json" % file)
		return {}
	var solids: Array = []
	var surfaces: Array = []
	var index_of: Dictionary = {}
	for solid: Dictionary in source["solids"]:
		index_of[solid["id"]] = solids.size()
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2],
			"bottom": solid["min"][1], "top": solid["max"][1]})
		surfaces.append(solid.get("surface", "concrete"))
	var decorations: Array = []
	for detail: Dictionary in source.get("decorations", []):
		if index_of.has(detail.get("solid")):
			var copy: Dictionary = detail.duplicate(true)
			copy["solid"] = index_of[detail["solid"]]
			decorations.append(copy)
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"],
		"half_extent": source["half_extent"], "solids": solids,
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": decorations}}
