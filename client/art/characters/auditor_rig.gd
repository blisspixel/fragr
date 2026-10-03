extends "res://art/characters/rig.gd"

## The Auditor: Level 8's human custody officer, built on the Clerk's issued
## body, joints, field and feet so it reads as Union staff, but with an
## officer's peaked cap, a long coat, a tall shield plate on the left forearm
## and a repair spool on its back whose cable runs to a lit emitter on the left
## glove. The pistol is the Clerk's. The layout's seated cell, which an Auditor
## never uses, holds the repair channel: the plate and emitter raised toward
## the body it repairs, the pistol lowered. Nothing here touches the Clerk's
## own rig or atlas.

## Emitter height in the channel pose, metres above the feet. Level 8's beam
## starts at the raised hand, 1.35 m (`AuditorChannels.HAND_ABOVE_FEET`).
const EMITTER_HEIGHT: float = 1.35
const BONE: Color = Color8(232, 226, 214)
## The coat is one step darker than issued cloth, so the plate leads.
const COAT: Color = Color8(24, 24, 28)

func build_auditor(action: String, progress: float, unarmed: bool) -> Node3D:
	var model: Node3D = Node3D.new()
	var upper: Node3D = Node3D.new()
	model.add_child(upper)
	var hip_height: float = 0.91
	var walk: bool = action == "walk"
	var channel: bool = action == "channel"
	var cycle: float = progress * TAU
	var collapse: float = progress if action == "death" else 0.0
	var hip: Vector3 = Vector3(0, hip_height, 0)
	hip.y -= collapse * 0.68
	hip.z -= collapse * 0.34
	if walk:
		hip.y += cos(cycle * 2.0) * 0.024
		hip.x += sin(cycle) * 0.022
	torso(upper, false)
	_cap(upper)
	_spool(upper, collapse)
	var raised: float = 0.0
	if action == "raise":
		raised = progress
	elif action in ["fire", "hit", "death"]:
		raised = 1.0
	elif action == "recover":
		raised = 1.0 - progress * 0.8
	var recoil: float = (1.0 - progress) if action == "fire" else 0.0
	var pain: float = sin(lerpf(0.2, 1.0, progress) * PI) if action == "hit" else 0.0
	var strides: Array[float] = []
	for side: float in [-1.0, 1.0]:
		var phase: float = cycle + (PI if side < 0 else 0.0)
		var stride: float = cos(phase) if walk else side * 0.18
		if channel:
			# A braced stance: the plate leg forward, the other back.
			stride = -side * 0.42
		strides.append(stride)
		var lift: float = maxf(-sin(phase), 0.0) * 0.17 if walk else 0.0
		var ankle: Vector3 = Vector3(side * 0.15, 0.124 + lift, stride * 0.3)
		var knee: Vector3 = Vector3(side * 0.16, 0.48 + lift * 0.15, stride * 0.16 + lift + 0.025)
		knee = knee.lerp(Vector3(side * 0.21, 0.15, 0.04), collapse)
		ankle = ankle.lerp(Vector3(side * 0.22, 0.124, -0.32 - side * 0.09), collapse)
		leg(model, false, side, hip + Vector3(side * 0.13, -0.035, 0), knee, ankle)
		var elbow: Vector3
		var hand: Vector3
		if side > 0:
			# The pistol hand: the Clerk's draw, out past the shoulder.
			elbow = Vector3(0.32, 1.08, 0.02).lerp(Vector3(0.36, 1.18, 0.04), raised)
			hand = Vector3(0.28, 0.86, 0.08).lerp(Vector3(0.42, 1.36, 0.08), raised)
			if channel:
				elbow = Vector3(0.33, 1.06, -0.02)
				hand = Vector3(0.30, 0.84, 0.06)
		else:
			# The plate arm: forearm across the front, plate before the chest.
			elbow = Vector3(-0.31, 1.06, 0.12).lerp(Vector3(-0.27, 1.12, 0.20), raised)
			hand = Vector3(-0.08, 1.10, 0.34).lerp(Vector3(-0.04, 1.18, 0.36), raised)
			if channel:
				elbow = Vector3(-0.26, 1.24, 0.30)
				hand = Vector3(-0.12, EMITTER_HEIGHT, 0.56)
		if walk:
			elbow.z -= stride * (0.12 if side > 0 else 0.04)
			hand.z -= stride * (0.18 if side > 0 else 0.05)
		if unarmed and side > 0 and action in ["raise", "fire", "recover"]:
			elbow = Vector3(0.36, 1.16, 0.16)
			hand = Vector3(0.22, 1.4, 0.23)
			var strike: float = (1.0 - progress * 0.3) if action == "fire" else (1.0 - progress if action == "recover" else 0.0)
			elbow = elbow.lerp(Vector3(0.19, 1.26, 0.39), strike)
			hand = hand.lerp(Vector3(0.08, 1.35, 0.70), strike)
		elif side > 0:
			hand += Vector3(0, recoil * 0.055, -recoil * 0.055)
			hand.x += pain * 0.1
		else:
			hand.x -= pain * 0.06
		if collapse > 0.0:
			elbow = elbow.lerp(Vector3(side * 0.36, 1.12, 0.17), collapse)
			hand = hand.lerp(Vector3(side * 0.46, 1.15, 0.27), collapse)
		arm(upper, false, side, elbow, hand)
		if side > 0 and not unarmed:
			gun(upper, hand + Vector3(0, 0.055, 0.045), false, raised)
		if side < 0:
			_plate(upper, elbow, hand, channel, collapse)
			_cable(upper, elbow, hand)
			if channel:
				_emitter(upper, hand)
	_coat(model, hip, strides, collapse)
	for child: Node3D in upper.get_children():
		child.position.y -= hip_height
	upper.position = hip
	upper.rotation_degrees.x = collapse * 88.0 - pain * 12.0 - recoil * 3.0
	upper.rotation_degrees.z = collapse * 11.0 + pain * 6.0
	if walk:
		upper.rotation_degrees.y = sin(cycle) * 6.0
	return model

## A peaked officer's cap over the issued helmet: a tall crown, a red band and
## a black visor, the first thing that separates an Auditor from a Clerk.
func _cap(root: Node3D) -> void:
	part(root, Vector3(0, 1.80, -0.012), Vector3(0.33, 0.085, 0.31), COAT)
	part(root, Vector3(0, 1.855, -0.03), Vector3(0.36, 0.05, 0.34), CLOTH, Vector3(-6, 0, 0))
	part(root, Vector3(0, 1.765, -0.012), Vector3(0.31, 0.04, 0.29), RED)
	part(root, Vector3(0, 1.752, 0.15), Vector3(0.25, 0.022, 0.11), INK, Vector3(-14, 0, 0))
	part(root, Vector3(0, 1.80, 0.148), Vector3(0.05, 0.04, 0.012), PLATE)

## The repair spool: a drum on the back under a short whip antenna, wound
## with cable. Its red ring is a seal, not a light.
func _spool(root: Node3D, collapse: float) -> void:
	part(root, Vector3(0, 1.22, -0.255), Vector3(0.30, 0.30, 0.13), STEEL)
	oval(root, Vector3(0, 1.22, -0.33), Vector3(0.24, 0.24, 0.07), PLATE)
	oval(root, Vector3(0, 1.22, -0.36), Vector3(0.16, 0.16, 0.04), RED)
	oval(root, Vector3(0, 1.22, -0.375), Vector3(0.07, 0.07, 0.03), INK)
	part(root, Vector3(0, 1.04, -0.25), Vector3(0.26, 0.05, 0.11), STEEL)
	if collapse < 0.5:
		limb(root, Vector3(0.11, 1.36, -0.28), Vector3(0.14, 1.62, -0.30), 0.018, 0.018, STEEL)
		part(root, Vector3(0.14, 1.64, -0.30), Vector3(0.035, 0.035, 0.035), RED)

## The shield plate rides the left forearm and faces where the forearm points,
## so the Auditor's front is covered and a flank is not.
func _plate(root: Node3D, elbow: Vector3, hand: Vector3, channel: bool, collapse: float) -> void:
	var plate: Node3D = Node3D.new()
	root.add_child(plate)
	var along: Vector3 = (hand - elbow).normalized()
	plate.position = elbow.lerp(hand, 0.55) + Vector3(0, -0.02, 0.10)
	# Face forward, with a slight inward cant so it covers the chest.
	var yaw: float = 14.0 if not channel else 6.0
	plate.rotation_degrees = Vector3(-6.0 - collapse * 70.0, yaw, 0)
	if along.y > 0.3:
		plate.rotation_degrees.x -= 10.0
	var size: Vector3 = Vector3(0.44, 0.68, 0.05)
	part(plate, Vector3.ZERO, size, PLATE)
	part(plate, Vector3(0, 0, 0.03), size * Vector3(0.84, 0.88, 0.2), STEEL.lightened(0.08))
	part(plate, Vector3(0, -0.02, 0.04), Vector3(0.06, 0.52, 0.012), RED)
	part(plate, Vector3(0, 0.30, 0.035), Vector3(0.46, 0.05, 0.04), STEEL)
	part(plate, Vector3(0, -0.32, 0.035), Vector3(0.40, 0.04, 0.04), STEEL)
	# Two sockets for the repair lamps Level 8 lights from the snapshot.
	for x: float in [-0.10, 0.10]:
		part(plate, Vector3(x, 0.20, 0.045), Vector3(0.05, 0.05, 0.02), RED.darkened(0.45))
	for corner: Vector2 in [Vector2(-0.17, 0.27), Vector2(0.17, 0.27), Vector2(-0.17, -0.29), Vector2(0.17, -0.29)]:
		part(plate, Vector3(corner.x, corner.y, 0.05), Vector3(0.025, 0.025, 0.01), PLATE.lightened(0.25))

## Cable from the spool, under the plate arm, to the glove emitter.
func _cable(root: Node3D, elbow: Vector3, hand: Vector3) -> void:
	var start: Vector3 = Vector3(-0.15, 1.12, -0.24)
	var sag: Vector3 = Vector3(-0.34, 0.98, -0.02).lerp(elbow + Vector3(-0.04, -0.08, -0.04), 0.5)
	limb(root, start, sag, 0.022, 0.022, INK)
	limb(root, sag, elbow + Vector3(0, -0.06, 0), 0.022, 0.022, INK)
	limb(root, elbow + Vector3(0, -0.06, 0), hand + Vector3(0, -0.05, 0), 0.02, 0.02, INK)

## The channel's emitter: a lit lens and a short bright stub on the glove, the
## point Level 8's beam leaves from.
func _emitter(root: Node3D, hand: Vector3) -> void:
	part(root, hand + Vector3(0, 0.02, 0.08), Vector3(0.13, 0.13, 0.05), STEEL)
	part(root, hand + Vector3(0, 0.02, 0.115), Vector3(0.10, 0.10, 0.03), GLOW)
	part(root, hand + Vector3(0, 0.02, 0.135), Vector3(0.05, 0.05, 0.02), BONE)
	for spoke: Vector3 in [Vector3(0.12, 0, 0), Vector3(-0.12, 0, 0), Vector3(0, 0.12, 0), Vector3(0, -0.12, 0)]:
		part(root, hand + Vector3(0, 0.02, 0.135) + spoke, Vector3(0.045, 0.045, 0.02), GLOW)
	for diagonal: Vector3 in [Vector3(0.08, 0.08, 0), Vector3(-0.08, 0.08, 0), Vector3(0.08, -0.08, 0), Vector3(-0.08, -0.08, 0)]:
		part(root, hand + Vector3(0, 0.02, 0.135) + diagonal, Vector3(0.03, 0.03, 0.02), GLOW)

## A long coat: front and back skirts from the belt to the knee that part with
## the stride and fold with a fall.
func _coat(root: Node3D, hip: Vector3, strides: Array[float], collapse: float) -> void:
	var waist: float = hip.y - 0.02
	for index: int in range(2):
		var side: float = -1.0 if index == 0 else 1.0
		var swing: float = strides[index]
		for front: float in [1.0, -1.0]:
			var panel: MeshInstance3D = part(root, Vector3(side * 0.12, waist - 0.24, front * 0.12 + swing * 0.07),
				Vector3(0.20, 0.46, 0.035), COAT)
			panel.rotation_degrees = Vector3(front * (6.0 + swing * 14.0) - collapse * 60.0, 0, side * 5.0)
			if collapse > 0.0:
				panel.position = panel.position.lerp(Vector3(side * 0.16, 0.28, -0.1), collapse)
	part(root, Vector3(0, waist + 0.02, 0), Vector3(0.40, 0.06, 0.30), INK)
	part(root, Vector3(0, waist + 0.02, 0.152), Vector3(0.07, 0.05, 0.012), RED)
