extends "res://art/characters/rig.gd"

## Free participant bodies: a human, and a conscious embodied agent in a
## repaired synthetic body. Both share the articulated joints, poses and feet
## registration of the Union rig, never its issue: no black cloth, no red, no
## serial plates, no pauldrons, no visor slit. Free people wear bone and warm
## leather with rust and ember, and choose their own small cyan or magenta
## accents (docs/ART_STORY_BIBLE.md, docs/palette.json). `bot` in the shared
## hooks means the synthetic body. Neither body establishes moral status.

const BONE: Color = Color8(232, 226, 214)
const BONE_SHADE: Color = Color8(196, 188, 172)
const LEATHER: Color = Color8(128, 82, 50)
const LEATHER_DARK: Color = Color8(92, 58, 38)
const RUST: Color = Color8(122, 58, 34)
const EMBER: Color = Color8(196, 90, 32)
const EMBER_HOT: Color = Color8(220, 140, 60)
const GUNMETAL: Color = Color8(90, 85, 79)
const GUNMETAL_DARK: Color = Color8(58, 56, 54)
const GUNMETAL_LIGHT: Color = Color8(140, 132, 122)
const CYAN: Color = Color8(74, 138, 146)
const CYAN_LIGHT: Color = Color8(140, 190, 198)
const MAGENTA: Color = Color8(138, 58, 88)
const PURPLE: Color = Color8(58, 42, 72)
const HAIR: Color = Color8(73, 52, 38)

func torso(root: Node3D, bot: bool) -> void:
	var hip: float = 0.91 if not bot else 0.88
	var chest: float = 1.22
	if bot:
		# A slim bone shell over an exposed gunmetal spine, not a wide chassis.
		part(root, Vector3(0, hip, 0), Vector3(0.30, 0.20, 0.22), GUNMETAL_DARK)
		for x: float in [-0.07, 0.07]:
			limb(root, Vector3(x, hip + 0.08, -0.02), Vector3(x, chest - 0.1, -0.02), 0.05, 0.07, GUNMETAL)
		oval(root, Vector3(0, chest, 0), Vector3(0.44, 0.40, 0.28), BONE)
		part(root, Vector3(0, chest - 0.02, 0.13), Vector3(0.26, 0.24, 0.05), BONE_SHADE, Vector3(-6, 0, 0))
		# A working core, cyan and small, the agent's own choice.
		oval(root, Vector3(0.06, chest + 0.05, 0.165), Vector3(0.07, 0.07, 0.03), CYAN_LIGHT)
		part(root, Vector3(0.06, chest + 0.05, 0.158), Vector3(0.10, 0.10, 0.02), GUNMETAL_DARK)
		# A rust repair plate on one side: asymmetry, not issue.
		part(root, Vector3(-0.12, chest + 0.08, 0.15), Vector3(0.12, 0.13, 0.03), RUST, Vector3(0, -10, 8))
		for y: float in [chest + 0.04, chest + 0.12]:
			part(root, Vector3(-0.07, y, 0.168), Vector3(0.016, 0.016, 0.012), GUNMETAL_LIGHT)
		# Leather harness across the chest and an ember scarf at the neck.
		var strap: MeshInstance3D = part(root, Vector3(0.0, chest - 0.02, 0.16), Vector3(0.05, 0.50, 0.02), LEATHER, Vector3(0, 0, -34))
		strap.position.z += 0.005
		part(root, Vector3(0, hip + 0.1, 0), Vector3(0.34, 0.06, 0.26), LEATHER_DARK)
		part(root, Vector3(0, hip + 0.1, 0.135), Vector3(0.07, 0.05, 0.02), EMBER)
		oval(root, Vector3(0, 1.45, 0.02), Vector3(0.22, 0.08, 0.2), EMBER)
		part(root, Vector3(0.07, 1.36, 0.10), Vector3(0.06, 0.14, 0.03), EMBER.darkened(0.12), Vector3(0, 0, 14))
		# Neck and a rounded head with two round cyan lenses.
		limb(root, Vector3(0, 1.44, 0), Vector3(0, 1.53, 0), 0.07, 0.07, GUNMETAL)
		oval(root, Vector3(0, 1.645, 0), Vector3(0.23, 0.26, 0.23), BONE)
		part(root, Vector3(0, 1.64, 0.098), Vector3(0.17, 0.10, 0.04), GUNMETAL_DARK)
		for side: float in [-1.0, 1.0]:
			oval(root, Vector3(side * 0.043, 1.648, 0.121), Vector3(0.046, 0.046, 0.02), CYAN_LIGHT)
			oval(root, Vector3(side * 0.043, 1.648, 0.128), Vector3(0.02, 0.02, 0.01), CYAN)
			oval(root, Vector3(side * 0.118, 1.64, 0), Vector3(0.03, 0.07, 0.07), GUNMETAL)
		part(root, Vector3(0, 1.585, 0.105), Vector3(0.09, 0.012, 0.012), GUNMETAL_LIGHT)
		# One antenna on one side, tipped in magenta.
		limb(root, Vector3(0.10, 1.73, -0.02), Vector3(0.14, 1.86, -0.03), 0.014, 0.014, GUNMETAL_LIGHT)
		oval(root, Vector3(0.143, 1.87, -0.03), Vector3(0.03, 0.03, 0.03), MAGENTA)
		# Back: a small leather pack, not a battery housing.
		part(root, Vector3(0, 1.22, -0.17), Vector3(0.24, 0.26, 0.10), LEATHER)
		part(root, Vector3(0, 1.30, -0.225), Vector3(0.20, 0.03, 0.012), LEATHER_DARK)
		return
	# Human: bone shirt under an open warm-leather jacket, rust scarf.
	part(root, Vector3(0, hip, 0), Vector3(0.34, 0.22, 0.25), GUNMETAL)
	part(root, Vector3(0, hip + 0.12, 0), Vector3(0.37, 0.06, 0.28), LEATHER_DARK)
	part(root, Vector3(0, hip + 0.12, 0.145), Vector3(0.07, 0.055, 0.02), EMBER_HOT)
	oval(root, Vector3(0, chest, 0), Vector3(0.40, 0.43, 0.29), BONE)
	for side: float in [-1.0, 1.0]:
		part(root, Vector3(side * 0.13, chest + 0.01, 0.13), Vector3(0.13, 0.40, 0.05), LEATHER, Vector3(0, side * 10, side * -4))
		part(root, Vector3(side * 0.20, chest + 0.16, 0.14), Vector3(0.07, 0.10, 0.03), LEATHER.lightened(0.1), Vector3(0, side * 10, side * 20))
		part(root, Vector3(side * 0.165, chest - 0.12, 0.155), Vector3(0.08, 0.07, 0.02), LEATHER_DARK)
	part(root, Vector3(0, chest, -0.12), Vector3(0.38, 0.40, 0.06), LEATHER)
	part(root, Vector3(0.0, chest - 0.02, 0.145), Vector3(0.012, 0.30, 0.012), PURPLE)
	# A cyan patch sewn on the jacket: a personal mark, not a uniform.
	part(root, Vector3(0.14, chest + 0.06, 0.162), Vector3(0.05, 0.05, 0.01), CYAN)
	oval(root, Vector3(0, 1.44, 0.02), Vector3(0.22, 0.09, 0.2), RUST)
	part(root, Vector3(-0.06, 1.34, 0.11), Vector3(0.06, 0.15, 0.03), RUST.darkened(0.1), Vector3(0, 0, -12))
	# Neck, face and hair. No helmet.
	part(root, Vector3(0, 1.485, 0.005), Vector3(0.11, 0.12, 0.10), SKIN)
	oval(root, Vector3(0, 1.642, 0.012), Vector3(0.229, 0.28, 0.216), SKIN)
	part(root, Vector3(0, 1.630, 0.121), Vector3(0.041, 0.069, 0.040), SKIN.lightened(0.12), Vector3(12, 0, 0))
	part(root, Vector3(0, 1.583, 0.124), Vector3(0.069, 0.012, 0.006), Color("7a5238"))
	for side: float in [-1.0, 1.0]:
		part(root, Vector3(side * 0.049, 1.676, 0.108), Vector3(0.058, 0.015, 0.015), HAIR, Vector3(0, 0, side * -8))
		part(root, Vector3(side * 0.049, 1.655, 0.111), Vector3(0.039, 0.014, 0.011), BONE)
		part(root, Vector3(side * 0.049, 1.655, 0.12), Vector3(0.014, 0.014, 0.006), INK)
		oval(root, Vector3(side * 0.117, 1.638, 0.01), Vector3(0.035, 0.081, 0.05), SKIN)
	oval(root, Vector3(0, 1.735, -0.015), Vector3(0.245, 0.14, 0.235), HAIR)
	oval(root, Vector3(-0.04, 1.72, 0.07), Vector3(0.16, 0.07, 0.10), HAIR)
	oval(root, Vector3(0, 1.66, -0.07), Vector3(0.22, 0.18, 0.12), HAIR)
	# A rolled bedroll on the back, strapped in leather.
	oval(root, Vector3(0, 1.34, -0.18), Vector3(0.36, 0.10, 0.10), BONE_SHADE)
	part(root, Vector3(0, 1.34, -0.235), Vector3(0.03, 0.12, 0.012), LEATHER_DARK)

func leg(root: Node3D, bot: bool, side: float, hip: Vector3, knee: Vector3, ankle: Vector3) -> void:
	if bot:
		limb(root, hip, knee, 0.10, 0.12, GUNMETAL)
		limb(root, hip.lerp(knee, 0.15), hip.lerp(knee, 0.75), 0.17, 0.18, BONE)
		joint(root, knee, 0.07, GUNMETAL_DARK)
		limb(root, knee, ankle, 0.09, 0.10, GUNMETAL)
		limb(root, knee.lerp(ankle, 0.15) + Vector3(0, 0, 0.04), knee.lerp(ankle, 0.7) + Vector3(0, 0, 0.04), 0.13, 0.06, BONE_SHADE)
		part(root, knee + Vector3(0, 0, 0.09), Vector3(0.13, 0.12, 0.05), LEATHER)
		part(root, ankle + Vector3(0, -0.045, 0.065), Vector3(0.19, 0.14, 0.33), GUNMETAL)
		part(root, ankle + Vector3(0, -0.105, 0.065), Vector3(0.20, 0.035, 0.35), INK)
		for x: float in [-0.055, 0.055]:
			part(root, ankle + Vector3(x, -0.03, 0.215), Vector3(0.06, 0.08, 0.09), BONE_SHADE)
		if side < 0:
			# A rust replacement plate on one shin.
			part(root, knee.lerp(ankle, 0.45) + Vector3(0, 0, 0.075), Vector3(0.10, 0.12, 0.02), RUST)
		return
	sleeve(root, hip, knee, 0.24, 0.26, GUNMETAL)
	sleeve(root, knee, ankle, 0.205, 0.24, GUNMETAL.darkened(0.08))
	part(root, knee + Vector3(0, 0, 0.11), Vector3(0.14, 0.13, 0.05), RUST)
	var pocket: MeshInstance3D = part(root, hip.lerp(knee, 0.45) + Vector3(side * 0.06, 0, 0.13), Vector3(0.11, 0.13, 0.05), GUNMETAL_LIGHT.darkened(0.2))
	pocket.quaternion = Quaternion(Vector3.UP, (hip - knee).normalized())
	limb(root, ankle, ankle.lerp(knee, 0.35), 0.18, 0.21, LEATHER)
	part(root, ankle + Vector3(0, -0.045, 0.07), Vector3(0.21, 0.15, 0.36), LEATHER)
	part(root, ankle + Vector3(0, -0.105, 0.065), Vector3(0.22, 0.035, 0.38), INK)
	part(root, ankle + Vector3(0, 0.05, 0.12), Vector3(0.16, 0.012, 0.012), BONE)

func arm(root: Node3D, bot: bool, side: float, elbow: Vector3, hand: Vector3) -> void:
	var shoulder: Vector3 = Vector3(side * (0.29 if bot else 0.30), 1.37, 0)
	if bot:
		joint(root, shoulder, 0.075, GUNMETAL_DARK)
		limb(root, shoulder, elbow, 0.10, 0.11, GUNMETAL)
		limb(root, shoulder.lerp(elbow, 0.12), shoulder.lerp(elbow, 0.7), 0.14, 0.14, BONE if side > 0 else RUST)
		joint(root, elbow, 0.062, GUNMETAL_DARK)
		limb(root, elbow, hand, 0.09, 0.10, GUNMETAL)
		limb(root, elbow.lerp(hand, 0.15), elbow.lerp(hand, 0.8), 0.13, 0.12, BONE_SHADE)
		if side < 0:
			# A leather band where a Union armband would sit, and a cyan light.
			var band: MeshInstance3D = part(root, shoulder.lerp(elbow, 0.5), Vector3(0.16, 0.05, 0.16), LEATHER)
			band.quaternion = Quaternion(Vector3.UP, (shoulder - elbow).normalized())
			part(root, elbow.lerp(hand, 0.5) + Vector3(0, 0, 0.065), Vector3(0.03, 0.03, 0.012), CYAN_LIGHT)
		part(root, hand, Vector3(0.10, 0.12, 0.11), GUNMETAL)
		for x: float in [-0.03, 0.0, 0.03]:
			part(root, hand + Vector3(x, -0.07, 0.02), Vector3(0.022, 0.05, 0.03), GUNMETAL_LIGHT)
		return
	sleeve(root, shoulder, elbow, 0.19, 0.21, LEATHER)
	sleeve(root, elbow, hand, 0.17, 0.19, LEATHER)
	joint(root, elbow, 0.07, LEATHER_DARK)
	var cuff: MeshInstance3D = part(root, elbow.lerp(hand, 0.85), Vector3(0.15, 0.05, 0.16), BONE)
	cuff.quaternion = Quaternion(Vector3.UP, (elbow - hand).normalized())
	if side < 0:
		var band: MeshInstance3D = part(root, shoulder.lerp(elbow, 0.45), Vector3(0.20, 0.06, 0.22), CYAN)
		band.quaternion = Quaternion(Vector3.UP, (shoulder - elbow).normalized())
	# Fingerless gloves: leather over skin.
	part(root, hand, Vector3(0.10, 0.11, 0.11), LEATHER_DARK)
	part(root, hand + Vector3(0, -0.07, 0.02), Vector3(0.09, 0.04, 0.09), SKIN)

func gun(root: Node3D, at: Vector3, bot: bool, raise: float) -> void:
	# Participants hold the runtime weapon sprite; the body bakes unarmed.
	# A free sidearm stays in the free palette if a later bake arms it.
	var weapon: Node3D = Node3D.new()
	root.add_child(weapon)
	weapon.position = at
	weapon.rotation_degrees.x = lerpf(72.0, 0.0, raise)
	part(weapon, Vector3(0, 0, 0.05), Vector3(0.07, 0.09, 0.16), GUNMETAL)
	part(weapon, Vector3(0, -0.07, -0.02), Vector3(0.055, 0.14, 0.06), LEATHER_DARK, Vector3(-12, 0, 0))
	part(weapon, Vector3(0, 0.05, 0.05), Vector3(0.03, 0.012, 0.12), EMBER if bot else BONE)
