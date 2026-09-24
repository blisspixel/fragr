extends "res://art/characters/rig.gd"

## Heavy Sweeper and Turret source. Same unshaded Union kit as the Clerk and
## Sweeper: black and dark steel, red seals and red optics. The muzzle flash and
## sparks are fire, not faction, so they keep palette ember_hot. Poses are
## presentation only; server phases decide when each one plays.
const EMBER_HOT: Color = Color8(220, 140, 60)

func build_machine(kind: String, action: String, progress: float, unarmed: bool) -> Node3D:
	if kind == "turret":
		return build_turret(action, progress)
	return build_heavy(action, progress, unarmed)

## How far the weapon is up. Matches the humanoid rig's mapping.
static func raised_for(action: String, progress: float) -> float:
	if action == "raise":
		return progress
	if action in ["fire", "hit", "death"]:
		return 1.0
	if action == "recover":
		return 1.0 - progress * 0.8
	return 0.0

## The Heavy Sweeper's tell is a planted, lowered stance with lit shoulder lamps.
static func brace_for(action: String, progress: float) -> float:
	if action == "raise":
		return progress
	if action == "fire":
		return 1.0
	if action == "recover":
		return 1.0 - progress
	return 0.0

func build_heavy(action: String, progress: float, unarmed: bool) -> Node3D:
	var model: Node3D = Node3D.new()
	var upper: Node3D = Node3D.new()
	model.add_child(upper)
	var hip_height: float = 0.84
	var walk: bool = action == "walk"
	var cycle: float = progress * TAU
	var collapse: float = progress if action == "death" else 0.0
	var raised: float = raised_for(action, progress)
	var brace: float = brace_for(action, progress)
	var recoil: float = (1.0 - progress) if action == "fire" else 0.0
	var pain: float = sin(lerpf(0.2, 1.0, progress) * PI) if action == "hit" else 0.0
	var hip: Vector3 = Vector3(0, hip_height - brace * 0.07, 0)
	hip.y -= collapse * 0.6
	hip.z -= collapse * 0.30 + pain * 0.08
	if walk:
		# A heavy gait: deep bob, wide weight shift, short stride.
		hip.y += cos(cycle * 2.0) * 0.05
		hip.x += sin(cycle) * 0.05
	_heavy_torso(upper, brace, collapse > 0.5)
	for side: float in [-1.0, 1.0]:
		var phase: float = cycle + (PI if side < 0 else 0.0)
		var stride: float = cos(phase) * 0.8 if walk else side * 0.1
		var lift: float = maxf(-sin(phase), 0.0) * 0.12 if walk else 0.0
		var width: float = 0.27 + brace * 0.08
		if action == "hit" and side < 0:
			stride -= pain * 0.5
		var ankle: Vector3 = Vector3(side * width, 0.16 + lift, stride * 0.28)
		var knee: Vector3 = Vector3(side * (width + 0.03), 0.47 + lift * 0.2, stride * 0.14 + lift + 0.06 + brace * 0.05)
		knee = knee.lerp(Vector3(side * 0.32, 0.2, 0.12), collapse)
		ankle = ankle.lerp(Vector3(side * 0.32, 0.16, -0.34), collapse)
		_heavy_leg(model, hip + Vector3(side * 0.2, -0.07, 0), knee, ankle)
		var elbow: Vector3
		var hand: Vector3
		if side > 0:
			elbow = Vector3(0.52, 1.12, 0.02).lerp(Vector3(0.50, 1.18, 0.06), raised)
			hand = Vector3(0.22, 0.98, 0.22).lerp(Vector3(0.20, 1.14, 0.24), raised)
		else:
			elbow = Vector3(-0.50, 1.10, 0.14).lerp(Vector3(-0.46, 1.16, 0.22), raised)
			hand = Vector3(-0.04, 0.98, 0.42).lerp(Vector3(-0.02, 1.16, 0.46), raised)
		if walk:
			elbow.z -= stride * 0.04
			hand.z -= stride * 0.05
		if unarmed and action in ["raise", "fire", "recover"]:
			# No gun left: a slow overhead hammer blow with both fists.
			var strike: float = 1.0 if action == "fire" else (1.0 - progress if action == "recover" else progress * 0.3)
			elbow = Vector3(side * 0.44, 1.42, 0.16).lerp(Vector3(side * 0.30, 1.30, 0.40), strike)
			hand = Vector3(side * 0.16, 1.74, 0.2).lerp(Vector3(side * 0.12, 1.12, 0.62), strike)
		else:
			hand += Vector3(0, recoil * 0.04 + pain * 0.12, -recoil * 0.06)
		if collapse > 0.0:
			elbow = elbow.lerp(Vector3(side * 0.40, 0.96, 0.10), collapse)
			hand = hand.lerp(Vector3(side * 0.44, 0.84, 0.18), collapse)
		_heavy_arm(upper, side, elbow, hand)
	if not unarmed:
		var spin: float = progress * 120.0 if action in ["raise", "fire"] else 0.0
		var glow: bool = action == "fire" or (action == "raise" and progress > 0.3)
		if action == "death":
			# The cannon drops beside the body instead of pitching into the floor.
			_cannon(model, Vector3(0.14, 1.0, 0.26).lerp(Vector3(0.56, 0.14, 0.2), collapse), 1.0, 0.0, 0.0, false, collapse)
		else:
			_cannon(upper, Vector3(0.12, 1.02, 0.24).lerp(Vector3(0.10, 1.16, 0.26), raised), raised, spin, recoil, glow, 0.0)
	for child: Node3D in upper.get_children():
		child.position.y -= hip_height
	upper.position = hip
	upper.rotation_degrees.x = collapse * 88.0 - pain * 16.0 - recoil * 2.0 + brace * 6.0
	upper.rotation_degrees.z = collapse * 9.0 + pain * 4.0
	if walk:
		upper.rotation_degrees.y = sin(cycle) * 4.0
		upper.rotation_degrees.z = sin(cycle) * 3.0
	return model

func _heavy_torso(root: Node3D, brace: float, dead: bool) -> void:
	part(root, Vector3(0, 0.86, 0), Vector3(0.52, 0.24, 0.38), STEEL)
	part(root, Vector3(0, 0.98, 0), Vector3(0.58, 0.07, 0.42), INK)
	part(root, Vector3(0, 1.25, 0), Vector3(0.80, 0.56, 0.50), STEEL)
	# Split bone breastplate and hip skirts: the Union's issued armor, broader.
	part(root, Vector3(0, 1.27, 0.24), Vector3(0.68, 0.44, 0.08), PLATE)
	part(root, Vector3(0, 1.27, 0.285), Vector3(0.03, 0.42, 0.012), INK)
	part(root, Vector3(0.2, 1.39, 0.29), Vector3(0.06, 0.05, 0.01), RED)
	for side: float in [-1.0, 1.0]:
		part(root, Vector3(side * 0.22, 0.80, 0.14), Vector3(0.22, 0.26, 0.08), PLATE.darkened(0.1), Vector3(-8, 0, 0))
		part(root, Vector3(side * 0.24, 1.10, 0.27), Vector3(0.16, 0.05, 0.012), PLATE.darkened(0.25))
	# Head sunk between the shoulders: the top of this outline is two pauldrons.
	part(root, Vector3(0, 1.50, -0.02), Vector3(0.56, 0.14, 0.44), PLATE.darkened(0.15))
	part(root, Vector3(0, 1.55, 0.07), Vector3(0.30, 0.20, 0.26), PLATE)
	part(root, Vector3(0, 1.56, 0.205), Vector3(0.22, 0.05, 0.02), INK)
	var visor: Color = INK if dead else GLOW
	part(root, Vector3(0, 1.56, 0.217), Vector3(0.15, 0.022, 0.009), visor)
	for side: float in [-1.0, 1.0]:
		# The tell flares both pauldrons up and out, changing the outline itself.
		var flare: float = side * (-10.0 - brace * 22.0)
		part(root, Vector3(side * 0.42, 1.50, 0), Vector3(0.26, 0.22, 0.36), STEEL)
		var pauldron: Node3D = Node3D.new()
		root.add_child(pauldron)
		pauldron.position = Vector3(side * 0.40, 1.56 + brace * 0.04, 0)
		pauldron.rotation_degrees.z = flare
		part(pauldron, Vector3(side * 0.16, 0.04, 0), Vector3(0.50, 0.28, 0.46), PLATE)
		part(pauldron, Vector3(side * 0.18, -0.10, 0), Vector3(0.42, 0.06, 0.42), INK)
		part(pauldron, Vector3(side * 0.16, 0.05, 0.235), Vector3(0.20, 0.08, 0.02),
			GLOW if brace > 0.4 and not dead else INK)
	# Ammunition drum and feed hose read in profile and from behind.
	part(root, Vector3(0, 1.24, -0.38), Vector3(0.62, 0.52, 0.30), STEEL)
	for y: float in [1.08, 1.18, 1.28, 1.38]:
		part(root, Vector3(0, y, -0.535), Vector3(0.52, 0.03, 0.02), PLATE.darkened(0.3))
	part(root, Vector3(0, 1.44, -0.53), Vector3(0.2, 0.06, 0.02), CLOTH)
	limb(root, Vector3(0.32, 1.06, -0.3), Vector3(0.30, 0.94, 0.08), 0.07, 0.07, INK)

func _heavy_leg(root: Node3D, hip: Vector3, knee: Vector3, ankle: Vector3) -> void:
	limb(root, hip, knee, 0.26, 0.30, STEEL)
	joint(root, knee, 0.11, STEEL)
	limb(root, knee, ankle, 0.22, 0.26, STEEL)
	var pad: MeshInstance3D = part(root, knee + Vector3(0, 0, 0.14), Vector3(0.22, 0.20, 0.10), PLATE)
	pad.rotation_degrees.x = -9.0
	var shin: MeshInstance3D = part(root, knee.lerp(ankle, 0.5) + Vector3(0, 0, 0.12), Vector3(0.18, 0.22, 0.05), PLATE.darkened(0.12))
	shin.quaternion = Quaternion(Vector3.UP, (knee - ankle).normalized())
	part(root, ankle + Vector3(0, -0.08, 0.08), Vector3(0.30, 0.16, 0.46), INK)
	part(root, ankle + Vector3(0, -0.03, 0.24), Vector3(0.28, 0.10, 0.14), PLATE)

func _heavy_arm(root: Node3D, side: float, elbow: Vector3, hand: Vector3) -> void:
	var shoulder: Vector3 = Vector3(side * 0.50, 1.46, 0)
	limb(root, shoulder, elbow, 0.20, 0.22, STEEL)
	joint(root, elbow, 0.09, STEEL)
	if side < 0:
		var band: MeshInstance3D = part(root, shoulder.lerp(elbow, 0.45), Vector3(0.23, 0.08, 0.25), RED)
		band.quaternion = Quaternion(Vector3.UP, (shoulder - elbow).normalized())
	limb(root, elbow, hand, 0.19, 0.20, STEEL)
	var guard: MeshInstance3D = part(root, (elbow + hand) * 0.5, Vector3(0.18, 0.22, 0.06), PLATE)
	guard.quaternion = Quaternion(Vector3.UP, (elbow - hand).normalized())
	guard.position += guard.basis.z * 0.09
	part(root, hand, Vector3(0.15, 0.15, 0.15), STEEL)

func _cannon(root: Node3D, at: Vector3, raised: float, spin: float, recoil: float, glow: bool, collapse: float) -> void:
	var weapon: Node3D = Node3D.new()
	root.add_child(weapon)
	weapon.position = at + Vector3(0, 0, -recoil * 0.08)
	weapon.rotation_degrees.x = lerpf(20.0, 0.0, raised)
	weapon.rotation_degrees.y = collapse * 35.0
	part(weapon, Vector3(0, 0, 0.12), Vector3(0.24, 0.24, 0.56), STEEL)
	part(weapon, Vector3(0, 0.14, 0.12), Vector3(0.20, 0.06, 0.50), PLATE.darkened(0.12))
	part(weapon, Vector3(0, -0.17, 0.04), Vector3(0.18, 0.16, 0.24), CLOTH)
	var barrels: Node3D = Node3D.new()
	weapon.add_child(barrels)
	barrels.position = Vector3(0, 0, 0.56)
	barrels.rotation_degrees.z = spin
	for index: int in range(3):
		var angle: float = TAU * float(index) / 3.0
		part(barrels, Vector3(cos(angle) * 0.06, sin(angle) * 0.06, 0), Vector3(0.06, 0.06, 0.46), INK)
	part(barrels, Vector3(0, 0, 0.2), Vector3(0.22, 0.22, 0.05), STEEL)
	part(barrels, Vector3(0, 0, -0.12), Vector3(0.2, 0.2, 0.05), STEEL)
	if glow:
		part(barrels, Vector3(0, 0, 0.225), Vector3(0.10, 0.10, 0.02), GLOW)

func build_turret(action: String, progress: float) -> Node3D:
	var model: Node3D = Node3D.new()
	var cycle: float = progress * TAU
	var destroyed: float = progress if action == "death" else 0.0
	var pain: float = sin(lerpf(0.2, 1.0, progress) * PI) if action == "hit" else 0.0
	# Fixed base: plate, three braced feet and a column that breaks on death.
	part(model, Vector3(0, 0.06, 0), Vector3(0.92, 0.12, 0.92), INK)
	part(model, Vector3(0, 0.15, 0), Vector3(0.62, 0.06, 0.62), STEEL)
	for index: int in range(3):
		var angle: float = TAU * float(index) / 3.0 + PI / 6.0
		var foot: Vector3 = Vector3(cos(angle) * 0.44, 0.06, sin(angle) * 0.44)
		var brace_top: Vector3 = Vector3(cos(angle) * 0.1, lerpf(0.72, 0.34, destroyed), sin(angle) * 0.1)
		limb(model, foot + Vector3(0, 0.04, 0), brace_top, 0.07, 0.07, STEEL)
		part(model, foot, Vector3(0.20, 0.10, 0.20), PLATE.darkened(0.15))
	var column_top: float = lerpf(1.26, 0.40, destroyed)
	part(model, Vector3(0, (0.18 + column_top) * 0.5, 0), Vector3(0.20, column_top - 0.18, 0.20), STEEL)
	part(model, Vector3(0, column_top, 0), Vector3(0.30, 0.07, 0.30), PLATE if destroyed == 0.0 else INK)
	if column_top > 0.7:
		part(model, Vector3(0, 0.62, 0.105), Vector3(0.1, 0.12, 0.012), RED)
	var head: Node3D = Node3D.new()
	model.add_child(head)
	head.position = Vector3(0, 1.50, 0).lerp(Vector3(0.30, 0.24, 0.30), destroyed)
	head.rotation_degrees = Vector3(lerpf(0.0, -8.0, destroyed) - pain * 14.0, 0, lerpf(0.0, -10.0, destroyed) + pain * 5.0)
	if action == "walk":
		head.rotation_degrees.y = cos(cycle) * 9.0
	var lamp: Color = RED
	var lit: int = 0
	if action == "raise":
		lamp = GLOW
		lit = mini(4, 1 + floori(progress * 4.0))
	elif action == "fire":
		lamp = GLOW
		lit = 4
	elif action == "recover":
		lamp = GLOW if progress < 0.7 else RED
		lit = 4 - mini(4, 1 + floori(progress * 4.0))
	elif action == "death":
		lamp = INK
	# Yoke and housing. The barrel sits at eye height, where the shot starts.
	if destroyed == 0.0:
		part(head, Vector3(0, -0.24, 0), Vector3(0.16, 0.16, 0.16), INK)
	for side: float in [-1.0, 1.0]:
		part(head, Vector3(side * 0.31, -0.02, 0), Vector3(0.08, 0.30, 0.22), STEEL)
		part(head, Vector3(side * 0.28, 0.0, 0.04), Vector3(0.06, 0.26, 0.44), STEEL)
	part(head, Vector3(0, 0, -0.06), Vector3(0.52, 0.34, 0.56), PLATE)
	part(head, Vector3(0, 0, -0.06), Vector3(0.54, 0.08, 0.58), CLOTH)
	part(head, Vector3(0, 0.12, -0.36), Vector3(0.30, 0.12, 0.08), STEEL)
	part(head, Vector3(-0.19, -0.1, 0.225), Vector3(0.05, 0.04, 0.01), RED)
	# Sensor lamp: dim red while searching, lit red optics and coils when charging.
	part(head, Vector3(0, 0.1, 0.225), Vector3(0.30, 0.09, 0.04), lamp)
	part(head, Vector3(0, 0.2, 0.0), Vector3(0.05, 0.08, 0.05), STEEL)
	if action == "walk":
		part(head, Vector3(cos(cycle) * 0.18, 0.18, 0.2), Vector3(0.08, 0.03, 0.02), GLOW)
	var barrel: Node3D = Node3D.new()
	head.add_child(barrel)
	barrel.position = Vector3(0, -0.03, 0.22 - ((1.0 - progress) * 0.1 if action == "fire" else 0.0))
	barrel.rotation_degrees.z = progress * 90.0 if action == "raise" else 0.0
	part(barrel, Vector3(0, 0, 0.36), Vector3(0.13, 0.13, 0.72), STEEL)
	for side: float in [-1.0, 1.0]:
		part(barrel, Vector3(side * 0.075, 0, 0.36), Vector3(0.025, 0.05, 0.6), INK)
	for index: int in range(4):
		part(barrel, Vector3(0, 0, 0.12 + index * 0.14), Vector3(0.26, 0.26, 0.05), GLOW if lit > index else INK)
	part(barrel, Vector3(0, 0, 0.74), Vector3(0.15, 0.15, 0.08), INK)
	if action == "fire" and progress < 0.5:
		part(barrel, Vector3(0, 0, 0.86), Vector3(0.30, 0.30, 0.14), EMBER_HOT)
	if action == "hit":
		part(head, Vector3(0.24, 0.2, 0.2), Vector3(0.06, 0.06, 0.06), EMBER_HOT)
		part(head, Vector3(-0.2, 0.16, 0.18), Vector3(0.05, 0.05, 0.05), EMBER_HOT)
	if destroyed > 0.5:
		part(model, Vector3(-0.3, 0.04, 0.3), Vector3(0.22, 0.04, 0.18), PLATE.darkened(0.2), Vector3(0, 30, 0))
		part(model, Vector3(0.2, 0.04, -0.34), Vector3(0.16, 0.04, 0.14), STEEL, Vector3(0, -20, 0))
	return model
