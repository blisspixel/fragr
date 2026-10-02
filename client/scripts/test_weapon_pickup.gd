extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

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
	{"kind":"weapon", "weapon":"Shiv", "pool":""},
	{"kind":"ammo", "weapon":"", "pool":"bullets"},
	{"kind":"ammo", "weapon":"", "pool":"shells"},
	{"kind":"ammo", "weapon":"", "pool":"cells"},
	{"kind":"health", "weapon":"", "pool":""},
	{"kind":"armor", "weapon":"", "pool":""},
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
			var bottom: float = icon.position.y - float(texture.get_height()) * icon.pixel_size * 0.5
			_check(bottom > 0.0 and bottom < 0.12, context + " rests just above the floor: %f" % bottom)
			widths[context] = float(texture.get_width()) * icon.pixel_size
	_check(widths.get("weapon Tack", 0.0) < widths.get("weapon Rail", 0.0) * 0.6,
		"a pistol is visibly smaller than a railgun at one texel density")
	_check(widths.get("health ", 0.0) > 0.4 and widths.get("health ", 0.0) < 0.9, "a medkit reads at room scale")
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
	pickup.setup("golden_rail", "Rail", Vector3.ZERO, "golden_rail")
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
	_check(highest > rest + 0.02 and highest <= rest + 0.051, "the sprite bobs gently above its rest")
	pickup.set_available(false)
	_check(not pickup.visible, "server availability hides the pickup")
	pickup.set_available(true)
	_check(pickup.visible and body.get_active_material(0) == material,
		"availability restores the pickup without allocating another material")
	var early: Node3D = scene.instantiate()
	early.setup("early_packet", "", Vector3.ZERO, "ammo", 8, "shells")
	root.add_child(early)
	_check((early.get_node("Icon") as Sprite3D).visible and not (early.get_node("Body") as MeshInstance3D).visible,
		"setup before entering the tree still applies the sprite look")
	early.queue_free()
	pickup.queue_free()
	await process_frame
	if failures == 0:
		print("test_weapon_pickup: PASS sprite for every kind, no world text, floor rest, bob, availability, fallback")
	quit(0 if failures == 0 else 1)
