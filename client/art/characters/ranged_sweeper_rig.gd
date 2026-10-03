extends "res://art/characters/rig.gd"

## The Ranged Sweeper: the issued Sweeper body with a tall mast antenna on its
## battery pack and a long scoped precision rifle. Joints, field, feet and the
## shared 55-pose layout match the Sweeper, so the family reads at a glance
## while the antenna and the rifle make the silhouette its own. The windup
## grows a red glint on the scope lens and holds it at full size, which is the
## tell the server's windup phase pays for. Nothing here touches the Sweeper's
## own rig or atlas.

## Top of the mast, metres above the feet. The bake field ends at 2.4 m.
const MAST_TOP: float = 2.12
const BONE: Color = Color8(232, 226, 214)

func build_ranged(action: String, progress: float, unarmed: bool) -> Node3D:
	var model: Node3D = Node3D.new()
	var upper: Node3D = Node3D.new()
	model.add_child(upper)
	var hip_height: float = 0.88
	var walk: bool = action == "walk"
	var cycle: float = progress * TAU
	var collapse: float = progress if action == "death" else 0.0
	var hip: Vector3 = Vector3(0, hip_height, 0)
	hip.y -= collapse * 0.68
	hip.z -= collapse * 0.34
	if walk:
		hip.y += cos(cycle * 2.0) * 0.024
		hip.x += sin(cycle) * 0.022
	torso(upper, true)
	_mast(upper, collapse)
	var raised: float = 0.0
	if action == "raise":
		raised = progress
	elif action in ["fire", "hit", "death"]:
		raised = 1.0
	elif action == "recover":
		raised = 1.0 - progress * 0.8
	var recoil: float = (1.0 - progress) if action == "fire" else 0.0
	var pain: float = sin(lerpf(0.2, 1.0, progress) * PI) if action == "hit" else 0.0
	# The glint grows through the windup, holds at full while the shot is
	# lined up, and is gone once the rifle has spoken.
	var glint: float = 0.0
	if action == "raise" and not unarmed:
		glint = lerpf(0.35, 1.0, progress)
	for side: float in [-1.0, 1.0]:
		var phase: float = cycle + (PI if side < 0 else 0.0)
		var stride: float = cos(phase) if walk else side * 0.18
		var lift: float = maxf(-sin(phase), 0.0) * 0.17 if walk else 0.0
		var ankle: Vector3 = Vector3(side * 0.145, 0.124 + lift, stride * 0.3)
		var knee: Vector3 = Vector3(side * 0.155, 0.48 + lift * 0.15, stride * 0.16 + lift + 0.025)
		knee = knee.lerp(Vector3(side * 0.21, 0.15, 0.04), collapse)
		ankle = ankle.lerp(Vector3(side * 0.22, 0.124, -0.32 - side * 0.09), collapse)
		leg(model, true, side, hip + Vector3(side * 0.13, -0.035, 0), knee, ankle)
		# Carried low across the body, then shouldered: the trigger hand rises
		# to the cheek and the support hand reaches far up the long barrel.
		var elbow: Vector3
		var hand: Vector3
		if side > 0:
			elbow = Vector3(0.46, 1.02, 0.10).lerp(Vector3(0.34, 1.20, 0.06), raised)
			hand = Vector3(0.20, 0.98, 0.30).lerp(Vector3(0.13, 1.36, 0.24), raised)
		else:
			elbow = Vector3(-0.46, 1.02, 0.14).lerp(Vector3(-0.24, 1.18, 0.34), raised)
			hand = Vector3(-0.08, 1.02, 0.52).lerp(Vector3(0.07, 1.40, 0.62), raised)
		if walk:
			elbow.z -= stride * 0.045
			hand.z -= stride * 0.065
		if unarmed and action in ["raise", "fire", "recover"]:
			elbow = Vector3(side * 0.36, 1.16, 0.16)
			hand = Vector3(side * 0.22, 1.4, 0.23)
			if side > 0:
				var strike: float = (1.0 - progress * 0.3) if action == "fire" else (1.0 - progress if action == "recover" else 0.0)
				elbow = elbow.lerp(Vector3(0.19, 1.26, 0.39), strike)
				hand = hand.lerp(Vector3(0.08, 1.35, 0.70), strike)
		else:
			hand += Vector3(0, recoil * 0.04, -recoil * 0.07)
			hand.x += side * pain * 0.1
		if collapse > 0.0:
			elbow = elbow.lerp(Vector3(side * 0.24, 0.92, 0.06), collapse)
			hand = hand.lerp(Vector3(side * 0.28, 0.78, 0.08), collapse)
		arm(upper, true, side, elbow, hand)
		if side > 0 and not unarmed:
			_rifle(upper, hand, raised, recoil, glint, collapse)
	for child: Node3D in upper.get_children():
		child.position.y -= hip_height
	upper.position = hip
	upper.rotation_degrees.x = collapse * 88.0 - pain * 12.0 - recoil * 4.0
	upper.rotation_degrees.z = collapse * 11.0 + pain * 6.0
	if walk:
		upper.rotation_degrees.y = sin(cycle) * 3.0
	return model

## A thin mast with two cross spars and a red tip lamp, rising from the
## battery pack behind the right shoulder: the silhouette no other Sweeper has.
func _mast(root: Node3D, collapse: float) -> void:
	var foot: Vector3 = Vector3(0.10, 1.40, -0.30)
	var top: Vector3 = Vector3(0.16, MAST_TOP, -0.33)
	part(root, foot + Vector3(0, -0.04, 0), Vector3(0.10, 0.08, 0.08), STEEL)
	limb(root, foot, top, 0.046, 0.046, PLATE.darkened(0.15))
	for at: float in [0.62, 0.84]:
		var spar: Vector3 = foot.lerp(top, at)
		var width: float = 0.27 if at < 0.7 else 0.17
		part(root, spar, Vector3(width, 0.034, 0.034), PLATE.darkened(0.1))
		for end: float in [-1.0, 1.0]:
			part(root, spar + Vector3(end * width * 0.5, -0.03, 0), Vector3(0.026, 0.07, 0.026), STEEL)
	part(root, top + Vector3(0, 0.03, 0), Vector3(0.06, 0.06, 0.06), GLOW if collapse < 0.5 else RED)
	# A short whip on the other side keeps the mast from reading as a rifle.
	limb(root, Vector3(-0.09, 1.44, -0.30), Vector3(-0.13, 1.74, -0.31), 0.02, 0.02, STEEL)

## The precision rifle: skeleton stock, long receiver, a big scope and a barrel
## that runs well past the Sweeper's shoulders, unlike the issued carbine.
func _rifle(root: Node3D, hand: Vector3, raised: float, recoil: float, glint: float, collapse: float) -> void:
	var weapon: Node3D = Node3D.new()
	root.add_child(weapon)
	weapon.position = hand + Vector3(0, 0.05, 0.04)
	# A falling body pitches forward; the rifle counters it and swings across
	# the chest so the long barrel lies on the floor instead of through it.
	weapon.rotation_degrees.x = lerpf(14.0, -2.0, raised) - collapse * 86.0
	weapon.rotation_degrees.y = lerpf(-24.0, 0.0, raised) + collapse * 70.0
	# Stock and grip.
	part(weapon, Vector3(0, -0.01, -0.22), Vector3(0.06, 0.12, 0.20), INK)
	part(weapon, Vector3(0, 0.04, -0.30), Vector3(0.05, 0.05, 0.10), STEEL)
	part(weapon, Vector3(0, -0.09, 0.02), Vector3(0.06, 0.13, 0.07), INK, Vector3(-14, 0, 0))
	# Receiver and cell housing.
	part(weapon, Vector3(0, 0.03, 0.12), Vector3(0.09, 0.09, 0.34), STEEL)
	part(weapon, Vector3(0, -0.05, 0.16), Vector3(0.07, 0.09, 0.10), PLATE.darkened(0.12))
	part(weapon, Vector3(0.048, 0.03, 0.10), Vector3(0.01, 0.03, 0.12), RED)
	# Scope on two rings.
	for z: float in [0.04, 0.22]:
		part(weapon, Vector3(0, 0.10, z), Vector3(0.05, 0.05, 0.03), STEEL)
	part(weapon, Vector3(0, 0.15, 0.13), Vector3(0.075, 0.075, 0.34), INK)
	part(weapon, Vector3(0, 0.15, -0.045), Vector3(0.085, 0.085, 0.03), PLATE)
	part(weapon, Vector3(0, 0.15, 0.31), Vector3(0.095, 0.095, 0.035), PLATE)
	# Long barrel and slotted brake.
	part(weapon, Vector3(0, 0.05, 0.62), Vector3(0.04, 0.04, 0.62), STEEL)
	part(weapon, Vector3(0, 0.05, 0.96), Vector3(0.065, 0.06, 0.09), PLATE.darkened(0.2))
	for z: float in [0.94, 0.98]:
		part(weapon, Vector3(0, 0.05, z), Vector3(0.07, 0.065, 0.012), INK)
	if glint > 0.0:
		_glint(weapon, Vector3(0, 0.15, 0.335), glint)
	if recoil > 0.5:
		var flash: float = (recoil - 0.5) * 2.0
		part(weapon, Vector3(0, 0.05, 1.06 + flash * 0.06), Vector3(0.10, 0.10, 0.10) * (0.6 + flash), BONE)
		for spoke: Vector3 in [Vector3(0.12, 0, 0), Vector3(-0.12, 0, 0), Vector3(0, 0.12, 0), Vector3(0, -0.12, 0)]:
			part(weapon, Vector3(0, 0.05, 1.08) + spoke * flash, Vector3(0.05, 0.05, 0.05), GLOW)

## A star on the front lens: red rays the shader keeps full-bright in any room,
## around a bone-white core. Rays run along all three axes so the star still
## reads from the side, not only down the barrel.
func _glint(root: Node3D, at: Vector3, size: float) -> void:
	var ray: float = 0.07 + 0.17 * size
	part(root, at, Vector3(ray * 2.0, 0.026, 0.026), GLOW)
	part(root, at, Vector3(0.026, ray * 2.0, 0.026), GLOW)
	part(root, at, Vector3(0.026, 0.026, ray * 1.4), GLOW)
	part(root, at, Vector3.ONE * 0.05 * (0.7 + 0.5 * size), BONE)
	var diagonal: MeshInstance3D = part(root, at + Vector3(0, 0, -0.004), Vector3(ray * 1.1, 0.02, 0.02), GLOW)
	diagonal.rotation_degrees.z = 45.0
	var other: MeshInstance3D = part(root, at + Vector3(0, 0, -0.004), Vector3(ray * 1.1, 0.02, 0.02), GLOW)
	other.rotation_degrees.z = -45.0
