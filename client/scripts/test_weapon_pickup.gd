extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

## A stand-in venue stage: a 12 cm seat, counting the asks.
func _stage_script() -> GDScript:
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node\nvar asks: int = 0\nvar floor: Vector3 = Vector3.ZERO\nfunc stage_pickup(_id: String, _kind: String, _weapon: String, at: Vector3) -> float:\n\tasks += 1\n\tfloor = at\n\treturn 0.12\n"
	script.reload()
	return script

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_weapon_pickup: " + message)

## Every kind the server sends, with the art it must show.
const DRAWN: Array[Dictionary] = [
	{"kind":"weapon", "weapon":"Tack", "pool":""},
	{"kind":"weapon", "weapon":"Flechette", "pool":""},
	{"kind":"weapon", "weapon":"Scatter", "pool":""},
	{"kind":"weapon", "weapon":"Rail", "pool":""},
	{"kind":"weapon", "weapon":"Repeater", "pool":""},
	{"kind":"weapon", "weapon":"Rocket", "pool":""},
	{"kind":"weapon", "weapon":"Shiv", "pool":""},
	{"kind":"ammo", "weapon":"", "pool":"bullets"},
	{"kind":"ammo", "weapon":"", "pool":"shells"},
	{"kind":"ammo", "weapon":"", "pool":"cells"},
	{"kind":"health", "weapon":"", "pool":""},
	{"kind":"armor", "weapon":"", "pool":""},
	{"kind":"plate", "weapon":"", "pool":""},
	{"kind":"grenade", "weapon":"", "pool":""},
]

func _run() -> void:
	var scene: PackedScene = load("res://scenes/weapon_pickup.tscn")
	var pickup: Node3D = scene.instantiate()
	root.add_child(pickup)
	var body: MeshInstance3D = pickup.get_node("Body")
	var band: MeshInstance3D = pickup.get_node("AmmoBand")
	var label: Label3D = pickup.get_node("Label3D")
	var icon: Sprite3D = pickup.get_node("Icon")
	var material: Material = body.get_active_material(0)
	_check(icon.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and not icon.shaded \
		and icon.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y, "pickup sprites are upright nearest-sampled pixels")
	var widths: Dictionary[String, float] = {}
	for entry: Dictionary in DRAWN:
		pickup.setup("pad_" + str(entry["kind"]), str(entry["weapon"]), Vector3.ZERO, str(entry["kind"]), 8, str(entry["pool"]))
		var context: String = "%s %s%s" % [entry["kind"], entry["weapon"], entry["pool"]]
		_check(icon.visible and icon.texture != null, context + " shows its sprite")
		_check(not body.visible and not band.visible, context + " hides the fallback crate")
		_check(not label.visible, context + " puts no text in the world")
		var texture: Texture2D = icon.texture
		if texture != null:
			var image: Image = texture.get_image()
			_check(not image.has_mipmaps() and image.detect_alpha() != Image.ALPHA_NONE, context + " is a cut-out pixel sprite")
			# The server reports a pad 0.4 m over its floor; the item seats
			# itself back down on that floor.
			var bottom: float = icon.position.y - float(texture.get_height()) * icon.pixel_size * 0.5 + pickup.PAD_LIFT
			_check(bottom > 0.0 and bottom < 0.06, context + " is seated on its floor: %f" % bottom)
			var shadow: MeshInstance3D = pickup.get_node_or_null("ContactShadow")
			_check(shadow != null and shadow.visible and absf(shadow.position.y + pickup.PAD_LIFT) < 0.02,
				context + " has a contact shadow on its floor")
			widths[context] = float(texture.get_width()) * icon.pixel_size
	_check(widths.get("weapon Tack", 0.0) < widths.get("weapon Rail", 0.0) * 0.6,
		"a pistol is visibly smaller than a railgun at one texel density")
	_check(widths.get("health ", 0.0) > 0.4 and widths.get("health ", 0.0) < 0.9, "a medkit reads at room scale")
	_check(widths.get("plate ", 0.0) > widths.get("armor ", 0.0) * 1.2,
		"the Custody Plate stands larger than the ordinary vest")
	_check(widths.get("weapon Rocket", 0.0) > 1.0, "the Rocket Launcher reads as a long tube")
	pickup.setup("larak_custody_plate", "", Vector3.ZERO, "plate", 100)
	_check(label.text == TranslationServer.translate("PICKUP_PLATE") and pickup.reach_metres() == pickup.POWER_REACH_METRES,
		"the Plate is named for the feed and heard across the map like a power item")
	# The keyed words stay correct for the fallback crate and the corner feed.
	pickup.setup("vest", "", Vector3.ZERO, "armor", 50)
	_check(label.text == "+50 ARMOR", "armor names the whole word, not ARM: " + label.text)
	pickup.setup("vest_unknown", "", Vector3.ZERO, "armor", 0)
	_check(label.text == "ARMOR", "armor without an amount still reads as armor: " + label.text)
	pickup.setup("workshop_grenades", "", Vector3.ZERO, "grenade", 2)
	_check(label.text == "+2 GRENADES" and not label.visible and icon.visible,
		"a grenade supply is drawn, and its keyed words name its grenades: " + label.text)
	# A mine supply keeps its keyed words, and is drawn the moment its art joins
	# the supply table; until then it is the labelled crate.
	pickup.setup("cage_mines", "", Vector3.ZERO, "proximity_mine", 3)
	var mine_drawn: bool = WeaponArt.SUPPLY.has("proximity_mine")
	_check(label.text == "+3 MINES" and icon.visible == mine_drawn and label.visible == not mine_drawn,
		"a mine supply names its mines and swaps to art by table: " + label.text)
	pickup.setup("armory_remotes", "", Vector3.ZERO, "remote_mine", 4)
	_check(label.text == "+4 REMOTE CHARGES" and not label.visible and not icon.visible and not body.visible,
		"remote stock retains keyed words without a generic crate or floating label")
	_check(pickup._remote_body != null and pickup._remote_body.visible and pickup._remote_body.has_node("Receiver"),
		"remote stock presents its distinct rectangular charge and receiver")
	pickup.setup("golden_rail", "Rail", Vector3.ZERO, "golden_rail")
	_check(not pickup._remote_body.visible, "switching stock retires the charge presentation")
	_check(icon.visible and label.visible and label.text == TranslationServer.translate("PICKUP_GOLDEN_RAIL"),
		"the golden Railgun keeps its one name above its sprite")
	_check(icon.modulate.r > 1.2 and icon.modulate.b < 0.6, "the golden Railgun is tinted gold")
	pickup.setup("mystery", "", Vector3.ZERO, "unknown")
	_check(body.visible and label.visible and not icon.visible, "a kind without art falls back to the labelled crate")
	pickup.setup("shell_packet", "", Vector3.ZERO, "ammo", 8, "shells")
	var rest: float = icon.position.y
	var highest: float = rest
	for frame: int in range(90):
		pickup._process(1.0 / 60.0)
		highest = maxf(highest, icon.position.y)
	_check(is_equal_approx(highest, rest), "a seated item rests on its pad rather than floating")
	pickup.set_reduced_motion(true)
	pickup._process(0.4)
	_check(is_equal_approx(icon.position.y, pickup._sprite_rest_y), "reduced motion restores the actual texture's resting height")
	var physical_position: Vector3 = pickup.position
	pickup._process(1.0)
	_check(is_equal_approx(icon.position.y, pickup._sprite_rest_y) and pickup.position == physical_position, "muted decoration never changes authoritative pickup position")
	pickup.set_available(false)
	_check(not pickup.visible, "server availability hides the pickup")
	pickup.set_available(true)
	_check(pickup.visible and body.get_active_material(0) == material,
		"availability restores the pickup without allocating another material")
	# Where a pad is, heard: the first snapshot is silent, a server change is not.
	var rail: Node3D = scene.instantiate()
	root.add_child(rail)
	rail.setup("pad_rail", "Rail", Vector3(4.0, 0.4, 2.0), "weapon")
	rail.note_server_available(true)
	_check(rail.return_cue_count == 0 and rail.taken_cue_count == 0, "a joiner hears nothing for a pad that was already up")
	rail.note_server_available(false)
	_check(rail.taken_cue_count == 1, "somebody else taking the pad is heard where it is")
	rail.note_server_available(false)
	_check(rail.taken_cue_count == 1, "an unchanged pad stays quiet")
	rail.note_server_available(true)
	_check(rail.return_cue_count == 1, "the pad coming back on its clock is heard")
	var cue: AudioStreamPlayer3D = rail.get_node_or_null("PadCue")
	_check(cue != null and cue.stream != null and cue.max_distance == rail.POWER_REACH_METRES,
		"the Railgun's return carries across the map")
	_check(rail.scale.x < 1.0, "the item rises back from small on its return")
	var shimmer: Sprite3D = rail.get_node_or_null("Shimmer")
	_check(shimmer != null and shimmer.visible, "the return shimmers")
	if shimmer != null:
		var warm: Color = rail.SHIMMER_COLOR
		_check(warm.r >= warm.g and warm.g >= warm.b and (warm.h < 0.17 or warm.h > 0.95),
			"the shimmer is warm, never the Inheritance's cyan")
	for frame: int in range(30):
		rail._process(1.0 / 60.0)
	_check(rail.scale.is_equal_approx(Vector3.ONE), "the return settles at full size")
	for frame: int in range(30):
		rail._process(1.0 / 60.0)
	_check(shimmer != null and not shimmer.visible and (rail.get_node("Icon") as Sprite3D).modulate.is_equal_approx(Color.WHITE),
		"the shimmer burns out and the item settles to its own colours")
	var flechette: Node3D = scene.instantiate()
	root.add_child(flechette)
	flechette.setup("pad_flechette", "Flechette", Vector3.ZERO, "weapon")
	_check(flechette.reach_metres() == flechette.COMMON_REACH_METRES, "an ordinary gun is heard across a room or two")
	flechette.set_reduced_motion(true)
	flechette.note_server_available(false)
	flechette.note_server_available(true, false)
	_check(flechette.return_cue_count == 1 and flechette.get_node_or_null("PadCue") == null,
		"the fighter standing on the pad is not played a second cue")
	_check(flechette.scale.is_equal_approx(Vector3.ONE), "reduced motion returns the item without the rise")
	_check(flechette.get_node_or_null("Shimmer") == null, "reduced motion returns the item without the shimmer")
	rail.queue_free()
	flechette.queue_free()
	# A venue that stages its pads seats the item on what it built, once.
	var stage: Node = Node.new()
	stage.set_script(_stage_script())
	root.add_child(stage)
	stage.add_to_group(&"pickup_stage")
	var seated: Node3D = scene.instantiate()
	root.add_child(seated)
	seated.setup("staged_rail", "Rail", Vector3(3.0, 0.9, -2.0), "weapon")
	seated.setup("staged_rail", "Rail", Vector3(3.0, 0.9, -2.0), "weapon")
	var seated_icon: Sprite3D = seated.get_node("Icon")
	var seated_bottom: float = seated_icon.position.y - float(seated_icon.texture.get_height()) * seated_icon.pixel_size * 0.5
	_check(stage.get("asks") == 1 and (stage.get("floor") as Vector3).is_equal_approx(Vector3(3.0, 0.5, -2.0)),
		"the stage is asked once, at the pad's floor")
	_check(is_equal_approx(seated.seat_height, 0.12) and seated_bottom > -seated.PAD_LIFT + 0.12 and seated_bottom < -seated.PAD_LIFT + 0.18,
		"the item sits on the staged seat: %f" % seated_bottom)
	# A dropped gun lies on its floor: the venue never stages under it, and
	# it blinks out over its last seconds (reduced motion holds it dim).
	var dropped: Node3D = scene.instantiate()
	root.add_child(dropped)
	dropped.setup("drop_7", "Rocket", Vector3(1.0, 0.4, 1.0), "weapon", 3, "", true)
	_check(stage.get("asks") == 1 and is_zero_approx(dropped.seat_height), "a dropped gun is not staged")
	var dropped_icon: Sprite3D = dropped.get_node("Icon")
	_check(dropped_icon.visible and dropped_icon.texture != null, "a dropped gun reads by the same picture")
	dropped._process(dropped.DROPPED_SECONDS - dropped.DROPPED_BLINK_SECONDS - 0.5)
	_check(is_equal_approx(dropped_icon.modulate.a, 1.0), "steady before the warning")
	dropped._process(0.6)
	var seen: Dictionary = {}
	for step: int in range(8):
		dropped._process(0.0625)
		seen[dropped_icon.modulate.a > 0.5] = true
	_check(seen.size() == 2, "the warning blinks")
	dropped.set_reduced_motion(true)
	dropped._process(0.1)
	_check(is_equal_approx(dropped_icon.modulate.a, 1.0) and dropped_icon.modulate.r < 0.9, "reduced motion dims instead of blinking")
	dropped.queue_free()
	seated.queue_free()
	stage.queue_free()
	var early: Node3D = scene.instantiate()
	early.setup("early_packet", "", Vector3.ZERO, "ammo", 8, "shells")
	root.add_child(early)
	early.set_reduced_motion(true)
	early._process(0.5)
	_check(is_equal_approx(early.get_node("Icon").position.y, early._sprite_rest_y), "new pickups inherit the muted rest pose")
	_check((early.get_node("Icon") as Sprite3D).visible and not (early.get_node("Body") as MeshInstance3D).visible,
		"setup before entering the tree still applies the sprite look")
	early.queue_free()
	pickup.queue_free()
	await process_frame
	if failures == 0:
		print("test_weapon_pickup: PASS sprite for every kind, no world text, seated with a contact shadow, staged seats, dropped guns, return shimmer, availability, fallback")
	quit(0 if failures == 0 else 1)
