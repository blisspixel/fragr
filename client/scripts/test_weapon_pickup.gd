extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_weapon_pickup: " + message)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/weapon_pickup.tscn")
	var pickup: Node3D = scene.instantiate()
	root.add_child(pickup)
	var body: MeshInstance3D = pickup.get_node("Body")
	var band: MeshInstance3D = pickup.get_node("AmmoBand")
	var label: Label3D = pickup.get_node("Label3D")
	var icon: Sprite3D = pickup.get_node("Icon")
	var regular_mesh: Mesh = body.mesh
	var material: Material = body.get_active_material(0)
	_check((regular_mesh as BoxMesh).size == Vector3(0.9, 0.55, 0.9) and label.font_size == 28 and not band.visible,
		"weapons retain the original large crate and label")
	pickup.setup("shell_packet", "", Vector3.ZERO, "ammo", 8, "shells")
	_check(body.mesh is BoxMesh and (body.mesh as BoxMesh).size == Vector3(0.42, 0.22, 0.32),
		"ammo uses a compact floor packet instead of the weapon crate")
	_check(is_equal_approx(body.position.y, 0.11) and band.visible and is_equal_approx(label.position.y, 0.59),
		"ammo packet and label sit close to the floor: body=%s label=%s band=%s" % [body.position, label.position, band.visible])
	_check(label.text == "+8 SHELLS" and label.font_size == 20 and label.outline_size == 5 and not icon.visible,
		"ammo label remains explicit, outlined and smaller than weapon labels")
	pickup.set_available(false)
	_check(not pickup.visible, "server availability hides the ammo packet")
	pickup.set_available(true)
	_check(pickup.visible and body.get_active_material(0) == material,
		"availability restores the packet without allocating another material")
	pickup.setup("medkit", "", Vector3.ZERO, "health", 25)
	_check(body.mesh == regular_mesh and is_equal_approx(body.position.y, 0.28) and is_equal_approx(label.position.y, 1.55) \
		and label.font_size == 28 and not band.visible and label.text == "+25 HP",
		"health restores the existing full-size crate and label: body=%s label=%s" % [body.position, label.position])
	pickup.setup("tack", "Tack", Vector3.ZERO)
	_check(body.mesh == regular_mesh and icon.visible and label.text == "PISTOL",
		"weapon icon and full-size crate remain unchanged")
	var early: Node3D = scene.instantiate()
	early.setup("early_packet", "", Vector3.ZERO, "ammo", 8, "shells")
	root.add_child(early)
	_check((early.get_node("Body") as MeshInstance3D).mesh is BoxMesh \
		and ((early.get_node("Body") as MeshInstance3D).mesh as BoxMesh).size == Vector3(0.42, 0.22, 0.32),
		"setup before entering the tree still applies the compact ammo look")
	early.queue_free()
	pickup.queue_free()
	await process_frame
	if failures == 0:
		print("test_weapon_pickup: PASS compact ammo, readable label, availability, unchanged health and weapon")
	quit(0 if failures == 0 else 1)
