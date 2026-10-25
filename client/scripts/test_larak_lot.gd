extends SceneTree

## Larak Lot's presenter dresses map 1 without adding collision, stays inside
## the light budget, redraws only the boxes it replaces, and writes every word
## from the catalog. The MapInfo here is a small excerpt of the server's own
## solids (the hung cruiser, a wreck, the lid, the shell and two decks).

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_larak_lot: " + message)

## Warm amber to orange: hue between about 22 and 60 degrees.
func _warm_not_red(color: Color) -> bool:
	var hue: float = color.h * 360.0
	return hue > 22.0 and hue < 60.0 and color.s > 0.3

func _solid(min_x: float, max_x: float, min_z: float, max_z: float, top: float, bottom: float = 0.0) -> Dictionary:
	var solid: Dictionary = {"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z, "top": top}
	if bottom > 0.0:
		solid["bottom"] = bottom
	return solid

func _run() -> void:
	var solids: Array = [
		_solid(-38.0, 4.0, -38.0, -28.0, 9.0),           # annex shell
		_solid(-36.0, -10.0, -28.0, -4.0, 3.0),          # Toll deck
		_solid(-24.0, -14.0, 2.0, 10.0, 3.4, 3.0),       # Low Ramp lid
		_solid(2.0, 6.4, -4.0, -2.0, 1.4),               # nose-down sedan
		_solid(-10.0, 10.0, -8.0, -5.0, 3.0, 2.6),       # Bridge
		_solid(-1.0, 1.0, -0.9, 0.9, 14.5, 10.0),        # the Repossession
		_solid(-25.0, -23.0, -17.0, -13.0, 5.8),         # the middle toll booth
		_solid(4.0, 8.4, 3.0, 8.0, 3.2),                 # THE STACK
	]
	var info: Dictionary = {
		"type": "map_info", "map_id": 1, "map_name": "Larak Lot", "half_extent": 38.0,
		"geometry_version": 2, "solids": solids,
		"presentation": {
			"ground": "concrete",
			"solids": ["concrete", "concrete", "concrete", "records_tile", "service_steel", "enamel", "enamel", "records_tile"],
			"decorations": [{"solid": 2, "face": "down", "center": [-1.0, 0.0], "size": [3.0, 0.5], "kind": "strip_light"}],
		},
	}
	_check(MapGeometry.validation_error(info).is_empty(), "the excerpt is a valid MapInfo")
	_check(ArenaCover.venue_for(info) == "larak_lot", "map name selects the venue")
	var arena: Node3D = Node3D.new()
	root.add_child(arena)
	var cover: ArenaCover = ArenaCover.new()
	arena.add_child(cover)
	cover.apply_map_info(info)
	await process_frame
	var lot: LarakLot = cover.get_node_or_null("LarakLot") as LarakLot
	_check(lot != null, "the presenter is built for map 1")
	if lot != null:
		var hung: MeshInstance3D = cover.get_node_or_null("Solid_5") as MeshInstance3D
		_check(hung != null and not hung.visible, "the cruiser's plain box is replaced by the model")
		var sedan: MeshInstance3D = cover.get_node_or_null("Solid_3") as MeshInstance3D
		_check(sedan != null and not sedan.visible, "the wreck's plain box is replaced by the car")
		var deck: MeshInstance3D = cover.get_node_or_null("Solid_1") as MeshInstance3D
		_check(deck != null and deck.visible, "ordinary decks stay drawn")
		_check(lot.get_node_or_null("Repossession") != null, "the landmark exists")
		# The prepared props stand in the volumes their solids hold.
		for index: int in [6, 7]:
			var box: MeshInstance3D = cover.get_node_or_null("Solid_%d" % index) as MeshInstance3D
			_check(box != null and not box.visible, "solid %d's plain box is replaced by its prop" % index)
		var booth: Node3D = lot.get_node_or_null("TollBooth") as Node3D
		_check(booth != null and booth.position.is_equal_approx(Vector3(-24.0, LarakLot.LEVEL_2, -15.0)), "the booth stands on its solid's floor centre")
		_check(lot.get_node_or_null("BurnedSedan") != null, "the Pit wreck is the prepared sedan")
		var stacks: int = 0
		for child: Node in lot.get_children():
			stacks += 1 if child.scene_file_path == LarakLot.PROPS + "car_stack.glb" else 0
		_check(stacks == 2, "THE STACK is two piles across its solid (got %d)" % stacks)
		var hooks: Array[Node] = lot.find_children("CraneHook", "Node3D", true, false)
		_check(hooks.size() == 1 and hooks[0].get_parent() == lot.get_node("Repossession"), "the hook block hangs with the cruiser")
		var props: Array[Node] = get_nodes_in_group(&"larak_prop")
		_check(props.size() >= 8, "the presenter places its props (got %d)" % props.size())
		for prop: Node in props:
			for surface: Node in prop.find_children("*", "MeshInstance3D", true, false):
				var finish: BaseMaterial3D = (surface as MeshInstance3D).get_active_material(0) as BaseMaterial3D
				_check(finish != null and finish.albedo_texture != null and finish.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
					"prop %s keeps crisp painted clusters" % prop.name)
		for prop_name: String in LarakLot.PROP_NAMES:
			_check(load(LarakLot.PROPS + prop_name + ".glb") is PackedScene, "prop %s ships" % prop_name)
		_check(lot.find_children("*", "CollisionObject3D", true, false).is_empty(), "the presenter adds no collision")
		var lights: Array[Node] = lot.find_children("*", "Light3D", true, false)
		var strips: int = cover.find_children("Practical", "OmniLight3D", true, false).size()
		_check(lights.size() == 4 and lights.size() + strips <= MapDecoration.MAX_LIGHTS + 4,
			"four presenter lights: flood, light bar, neon and Roof mast (got %d)" % lights.size())
		var tunnel: OmniLight3D = cover.find_child("Practical", true, false) as OmniLight3D
		_check(tunnel != null and tunnel.light_color == LarakLot.FLUORESCENT, "the Low Ramp tube burns cold")
		for sign: Node in lot.find_children("*", "WorldSign", true, false):
			_check(not (sign as WorldSign).text.is_empty(), "sign %s has catalog copy" % (sign as WorldSign).message_key)
		var neon: Label3D = lot.get_node_or_null("Neon0") as Label3D
		_check(neon != null and neon.text == "L", "the LARAK neon spells from the catalog")
		lot._process(4.3)
		_check(not (lot.get_node("Neon4") as Label3D).visible, "the K drops out")
		# Red belongs to Union optics and attack tells: the venue's own
		# emitters stay warm and out of the reserved red band.
		var bar: OmniLight3D = lot.find_child("LightBar", true, false) as OmniLight3D
		_check(bar != null and _warm_not_red(bar.light_color), "the light bar burns league amber, not red or blue")
		var neon_light: OmniLight3D = lot.get_node_or_null("LarakNeon") as OmniLight3D
		_check(neon_light != null and _warm_not_red(neon_light.light_color), "the LARAK neon sits outside the reserved red band")
		_check(lot.is_in_group(LarakLot.GROUP), "the presenter joins its group for venue events")
		var calm: float = bar.light_energy if bar != null else 0.0
		lot.plate_claimed()
		lot._process(0.6)
		_check(bar != null and bar.light_energy > calm + 1.0, "a Plate claim flares the light bar once")
		lot._process(2.0)
		_check(bar != null and bar.light_energy < calm + 1.0, "the flare settles")
		var arm: Node3D = lot.get_node_or_null("TollArm") as Node3D
		lot._process(4.6)
		var lowered: float = arm.rotation.z if arm != null else -1.0
		lot._process(6.5)
		_check(arm != null and arm.rotation.z > lowered + 0.5, "the last toll arm still lifts on its timer")
	var preset: ArenaSky.Preset = ArenaSky.preset_for("Larak Lot")
	_check(not preset.key_in_sky and preset.practical_color == LarakLot.SODIUM, "venue sky and sodium practicals")
	arena.queue_free()
	await process_frame
	if _failures == 0:
		print("test_larak_lot: PASS presenter replaces only its boxes with its props, adds no collision, keeps the light budget, warm emitters and catalog copy")
	quit(0 if _failures == 0 else 1)
