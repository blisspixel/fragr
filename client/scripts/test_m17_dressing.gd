extends SceneTree

## The Forever Office's command galleries: an authored-layout guard, every
## room furnished, local practical light with no red or cyan, no words and no
## bodies of its own, and the institution on the Union's palette: mid-value
## grey stone and graphite steel, never the late story's off-white, and no sun
## disc in the dawn sky.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m17_dressing: " + message)

static func authored_info() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m17-peace-without-interruption.json"))
	if not source is Dictionary:
		return {}
	var solids: Array = []
	var surfaces: Array = []
	for solid: Dictionary in source["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2],
			"bottom": solid["min"][1], "top": solid["max"][1]})
		surfaces.append(solid.get("surface", "concrete"))
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"],
		"half_extent": source["half_extent"], "solids": solids, "m17": {},
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": []}}

func _run() -> void:
	var info: Dictionary = authored_info()
	_expect(not info.is_empty(), "the authored Forever Office loads")
	_expect(M17Dressing.office_layout(info), "the authored command block is recognized")
	var other: Dictionary = info.duplicate(true)
	other["map_id"] = 1016
	_expect(not M17Dressing.office_layout(other), "another mission never receives the office furniture")
	var moved: Dictionary = info.duplicate(true)
	for solid: Dictionary in moved["solids"]:
		if is_equal_approx(float(solid["min_x"]), -34.0) and is_equal_approx(float(solid["bottom"]), 2.6):
			solid["bottom"] = 0.0
	_expect(not M17Dressing.office_layout(moved), "a reused id without the raised gallery stays bare")
	_expect(not M17Dressing.office_layout({"map_id": 1017}), "a malformed map is refused")

	var office: M17Dressing = M17Dressing.new()
	root.add_child(office)
	office.configure_map(moved)
	_expect(office.get_child_count() == 0 and not office.active(), "unrecognized layouts stay bare")
	office.configure_map(info)
	for room: String in M17Dressing.ROOMS:
		_expect(room in office.rooms and office.has_node(room), "room dressed: " + room)
	_expect(office.lamps >= 8, "practical light shapes the galleries, found %d" % office.lamps)
	for light: Node in office.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
		if lamp is SpotLight3D:
			_expect((lamp as SpotLight3D).spot_range <= 10.0 and (lamp as SpotLight3D).spot_angle <= 60.0, "floods stay bounded: " + lamp.name)
	for node: Node in office.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(office.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(office.find_children("*", "Label3D", true, false).is_empty(), "the office tells its story without words")
	for room: String in office.rooms:
		var props: Node = office.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	for colour: Color in [M17Dressing.WALNUT, M17Dressing.PAPER, M17Dressing.AMBER, M17Dressing.SCREEN] + M17Dressing.BELONGINGS:
		_expect(not (colour.v >= 0.8 and colour.s <= 0.15), "no off-white in the office's things: " + colour.to_html(false))
	office.configure_map(other)
	_expect(not office.active(), "another map clears the office furniture")
	await process_frame
	_expect(office.get_child_count() == 0, "cleared rooms leave the tree")
	office.queue_free()

	# The institution's surfaces: Union palette, mid-value, never off-white.
	_expect(ArenaCover.venue_for(info) == "forever_office", "the Forever Office has its own venue")
	for surface: String in ["concrete", "enamel", "service_steel", "records_tile"]:
		var material: ShaderMaterial = ArenaMaterials.authored(surface, "forever_office") as ShaderMaterial
		_expect(material != null, "authored material: " + surface)
		if material == null:
			continue
		var base: Color = material.get_shader_parameter("surface_color")
		_expect(not (base.v >= 0.8 and base.s <= 0.15), "no off-white institution: " + surface)
		_expect(base.s < 0.45, "restrained institutional colour: " + surface)
		_expect(float(material.get_shader_parameter("trim_glow")) == 0.0, "painted marks never glow: " + surface)
	var walls: Color = (ArenaMaterials.authored("enamel", "forever_office") as ShaderMaterial).get_shader_parameter("surface_color")
	_expect(walls.v >= 0.4 and walls.v <= 0.7, "walls stay mid-value so black-and-red bodies read: %f" % walls.v)
	var band: Color = (ArenaMaterials.authored("enamel", "forever_office") as ShaderMaterial).get_shader_parameter("accent_color")
	_expect(band.g <= band.r + 0.03, "no institutional green band in the Union's own seat")
	var sky: ArenaSky.Preset = ArenaSky.preset_for("Peace Without Interruption")
	_expect(not sky.key_in_sky and not sky.outdoor_embers, "the dawn sky carries no sun disc or scrapyard embers")
	_expect(sky.view_fill_energy > 0.0, "black-and-red bodies keep a lit front in the galleries' shade")
	if failures == 0:
		print("test_m17_dressing: PASS layout guard, five furnished rooms, local light without red or cyan, no words or bodies, Union palette and a dawn sky without a sun disc")
		quit(0)
	else:
		push_error("test_m17_dressing FAILED with %d failures" % failures)
		quit(1)
