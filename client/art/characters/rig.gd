extends "res://art/characters/geometry.gd"

func torso(root: Node3D, bot: bool) -> void:
	var hip: float = 0.91 if not bot else 0.88
	var chest: float = 1.22
	var cloth: Color = CLOTH if not bot else STEEL
	part(root,Vector3(0,hip,0),Vector3(0.34,0.22,0.25),cloth)
	part(root,Vector3(0,hip+0.13,0),Vector3(0.38,0.07,0.29),INK)
	part(root,Vector3(0,hip+0.13,0.155),Vector3(0.075,0.062,0.035),PLATE)
	oval(root,Vector3(0,chest,0),Vector3(0.40 if not bot else 0.66,0.43,0.30 if not bot else 0.38),cloth)
	# Segmented breastplate and shoulder seams leave the uniform readable.
	for side: float in [-1.0,1.0]:
		part(root,Vector3(side*0.109,chest+0.035,0.17),Vector3(0.20,0.27,0.075),PLATE,Vector3(0,side*8,side*-3))
		part(root,Vector3(side*0.109,chest+0.04,0.211),Vector3(0.16,0.20,0.012),PLATE.darkened(0.075),Vector3(0,side*8,side*-3))
		part(root,Vector3(side*0.22,hip+0.12,0.085),Vector3(0.08,0.115,0.14),CLOTH.darkened(0.25))
		part(root,Vector3(side*0.225,hip+0.16,0.161),Vector3(0.065,0.023,0.012),PLATE.darkened(0.22))
		part(root,Vector3(side*0.075,chest-0.135,0.135),Vector3(0.13,0.10,0.055),STEEL)
		part(root,Vector3(side*0.16,1.40,0.01),Vector3(0.065,0.065,0.33),STEEL)
	part(root,Vector3(0.12,1.31,0.221),Vector3(0.045,0.044,0.009),RED)
	# Neck, open-face helmet and skin distinguish the human from issued machinery.
	if not bot:
		part(root,Vector3(0,1.485,0.005),Vector3(0.115,0.13,0.11),SKIN)
		oval(root,Vector3(0,1.642,0.012),Vector3(0.229,0.28,0.216),SKIN)
		part(root,Vector3(0,1.555,0.066),Vector3(0.148,0.075,0.095),SKIN.darkened(0.12))
		part(root,Vector3(0,1.630,0.121),Vector3(0.041,0.069,0.040),SKIN.lightened(0.12),Vector3(12,0,0))
		part(root,Vector3(0,1.583,0.126),Vector3(0.069,0.012,0.006),Color("664a36"))
		for side: float in [-1.0,1.0]:
			part(root,Vector3(side*0.049,1.674,0.108),Vector3(0.058,0.015,0.015),Color("332b24"),Vector3(0,0,side*-8))
			part(root,Vector3(side*0.049,1.655,0.111),Vector3(0.039,0.014,0.011),Color("d6c9aa"))
			part(root,Vector3(side*0.049,1.655,0.12),Vector3(0.014,0.014,0.006),INK)
			oval(root,Vector3(side*0.066,1.62,0.091),Vector3(0.072,0.05,0.054),SKIN.lightened(0.05))
			part(root,Vector3(side*0.117,1.638,0.01),Vector3(0.033,0.081,0.046),SKIN)
			part(root,Vector3(side*0.125,1.625,0.040),Vector3(0.018,0.20,0.034),STEEL)
			oval(root,Vector3(side*0.133,1.670,-0.039),Vector3(0.050,0.14,0.126),PLATE)
		helmet(root)
	else:
		part(root,Vector3(0,1.465,0),Vector3(0.10,0.10,0.12),STEEL)
		part(root,Vector3(0,1.64,-0.01),Vector3(0.38,0.32,0.30),PLATE)
		part(root,Vector3(0,1.652,0.142),Vector3(0.24,0.074,0.025),INK)
		part(root,Vector3(0,1.652,0.157),Vector3(0.18,0.03,0.009),GLOW)
		part(root,Vector3(0,1.54,0.095),Vector3(0.165,0.045,0.06),STEEL)
		for x: float in [-0.055,0.0,0.055]:
			part(root,Vector3(x,1.565,0.119),Vector3(0.02,0.045,0.009),INK)
		part(root,Vector3(0,1.25,-0.22),Vector3(0.33,0.35,0.19),STEEL)
		for y: float in [1.16,1.23,1.30,1.37]:
			part(root,Vector3(0,y,-0.325),Vector3(0.28,0.025,0.02),PLATE.darkened(0.3))
	if not bot:
		part(root,Vector3(0,1.24,-0.146),Vector3(0.32,0.28,0.041),CLOTH.darkened(0.24))
		for side: float in [-1.0,1.0]:
			part(root,Vector3(side*0.123,1.22,-0.173),Vector3(0.038,0.35,0.017),STEEL)
			part(root,Vector3(side*0.122,1.37,-0.187),Vector3(0.06,0.043,0.014),PLATE.darkened(0.28))
		part(root,Vector3(0,1.06,-0.168),Vector3(0.36,0.045,0.025),STEEL)
		part(root,Vector3(0.226,0.85,-0.017),Vector3(0.08,0.22,0.17),STEEL,Vector3(8,0,-5))
		part(root,Vector3(0,1.18,0.189),Vector3(0.035,0.25,0.02),CLOTH.darkened(0.35))
	# Issued fasteners and a restrained serial plate, never luminous faction paint.
	for side: float in [-1.0,1.0]:
		for y: float in [1.14,1.35]:
			part(root,Vector3(side*0.178,y,0.212),Vector3(0.014,0.014,0.013),STEEL)
	part(root,Vector3(-0.102,1.285,0.22),Vector3(0.079,0.047,0.01),CLOTH)
	for x: float in [-0.129,-0.108,-0.092,-0.077]:
		part(root,Vector3(x,1.287,0.227),Vector3(0.007,0.025,0.007),PLATE.darkened(0.2))
	part(root,Vector3(0.088,1.184,0.221),Vector3(0.04,0.013,0.008),STEEL)
	part(root,Vector3(0.16,1.353,0.214),Vector3(0.043,0.011,0.008),STEEL)

func leg(root: Node3D, bot: bool, side: float, hip: Vector3, knee: Vector3, ankle: Vector3) -> void:
	var cloth: Color = STEEL if bot else CLOTH
	if bot:
		limb(root,hip,knee,0.18,0.23,cloth)
	else:
		sleeve(root,hip,knee,0.24,0.26,cloth)
	joint(root,knee,0.079,STEEL)
	if bot:
		limb(root,knee,ankle,0.13,0.15,cloth)
		limb(root,knee+Vector3(side*0.07,-0.08,-0.01),ankle+Vector3(side*0.07,0.02,-0.01),0.034,0.034,PLATE.darkened(0.3))
	else:
		sleeve(root,knee,ankle,0.205,0.24,cloth)
		limb(root,ankle,ankle.lerp(knee,0.43),0.185,0.22,STEEL)
	var pad: MeshInstance3D = part(root,knee+Vector3(0,0,0.108),Vector3(0.16,0.15,0.073),PLATE)
	pad.rotation_degrees.x = -9.0
	part(root,knee+Vector3(0,0,0.15),Vector3(0.105,0.083,0.009),PLATE.darkened(0.2))
	part(root,ankle+Vector3(0,-0.04,0.07),Vector3(0.22,0.16,0.37),INK)
	part(root,ankle+Vector3(0,0.01,0.17),Vector3(0.205,0.11,0.15),PLATE if bot else STEEL)
	part(root,ankle+Vector3(0,-0.105,0.06),Vector3(0.23,0.037,0.39),INK)
	if not bot:
		var pouch: MeshInstance3D = part(root,hip.lerp(knee,0.42)+Vector3(side*0.055,0,0.14),Vector3(0.11,0.14,0.05),CLOTH.lightened(0.12))
		pouch.quaternion = Quaternion(Vector3.UP,(hip-knee).normalized())

func arm(root: Node3D, bot: bool, side: float, elbow: Vector3, hand: Vector3) -> void:
	var cloth: Color = STEEL if bot else CLOTH
	var shoulder: Vector3 = Vector3(side*(0.31 if not bot else 0.34),1.37,0)
	if bot:
		limb(root,shoulder,elbow,0.16,0.17,cloth)
		limb(root,elbow,hand,0.14,0.15,cloth)
	else:
		sleeve(root,shoulder,elbow,0.18,0.20,cloth)
		sleeve(root,elbow,hand,0.162,0.18,cloth)
	joint(root,elbow,0.073,STEEL)
	# Issued red armband on the left arm, the same on humans and bots.
	if side < 0:
		var band: MeshInstance3D = part(root,shoulder.lerp(elbow,0.45),Vector3(0.2 if not bot else 0.18,0.07,0.22 if not bot else 0.19),RED)
		band.quaternion = Quaternion(Vector3.UP,(shoulder-elbow).normalized())
	var pauldron: Vector3 = Vector3(0.16, 0.11, 0.20) if not bot else Vector3(0.38, 0.16, 0.30)
	part(root,shoulder+Vector3(side*(0.02 if not bot else 0.10),0.04,0),pauldron,PLATE,Vector3(0,0,side*-14))
	var guard: MeshInstance3D = part(root,(elbow+hand)*0.5,Vector3(0.14,0.18,0.05),PLATE)
	guard.quaternion = Quaternion(Vector3.UP,(elbow-hand).normalized())
	guard.position += guard.basis.z*0.074
	part(root,hand,Vector3(0.11,0.13,0.12),STEEL)
	part(root,hand+Vector3(0,0.039,0.055),Vector3(0.10,0.045,0.024),STEEL.lightened(0.17))

func build_pose(bot: bool, action: String, progress: float, unarmed: bool = false) -> Node3D:
	var model: Node3D = Node3D.new()
	var upper: Node3D = Node3D.new()
	model.add_child(upper)
	var hip_height: float = 0.88 if bot else 0.91
	var walk: bool = action == "walk"
	var cycle: float = progress * TAU
	var collapse: float = progress if action == "death" else 0.0
	var hip: Vector3 = Vector3(0,hip_height,0)
	hip.y -= collapse*0.68
	hip.z -= collapse*0.34
	if walk:
		hip.y += cos(cycle*2.0)*0.024
		hip.x += sin(cycle)*0.022
	torso(upper,bot)
	var raised: float = 0.0
	if action == "raise":
		raised = progress
	elif action in ["fire","hit","death"]:
		raised = 1.0
	elif action == "recover":
		raised = 1.0-progress*0.8
	var recoil: float = (1.0-progress) if action == "fire" else 0.0
	var pain: float = sin(lerpf(0.2,1.0,progress)*PI) if action == "hit" else 0.0
	for side: float in [-1.0,1.0]:
		var phase: float = cycle + (PI if side<0 else 0.0)
		var stride: float = cos(phase) if walk else side*0.18
		var lift: float = maxf(-sin(phase),0.0)*0.17 if walk else 0.0
		var ankle: Vector3 = Vector3(side*0.145,0.124+lift,stride*0.3)
		var knee: Vector3 = Vector3(side*0.155,0.48+lift*0.15,stride*0.16+lift+0.025)
		knee = knee.lerp(Vector3(side*0.21,0.15,0.04),collapse)
		ankle = ankle.lerp(Vector3(side*0.22,0.124,-0.32-side*0.09),collapse)
		leg(model,bot,side,hip+Vector3(side*0.13,-0.035,0),knee,ankle)
		var elbow: Vector3 = Vector3(side*0.32,1.08,0.02)
		var hand: Vector3 = Vector3(side*0.28,0.86,0.08)
		if bot:
			# Wide brace and a level rifle. The firing pose stays low and broad.
			elbow = Vector3(side*0.48,1.02,0.12).lerp(Vector3(side*0.44,1.08,0.28),raised)
			hand = Vector3(side*0.20,0.98,0.34).lerp(Vector3(side*0.12,1.04,0.56),raised)
		elif side>0:
			# The pistol clears the shoulder, a spike the box-headed bot does not grow.
			elbow = elbow.lerp(Vector3(0.36,1.18,0.04),raised)
			hand = hand.lerp(Vector3(0.42,1.36,0.08),raised)
		else:
			elbow = elbow.lerp(Vector3(-0.18,1.16,0.10),raised)
			hand = hand.lerp(Vector3(-0.04,1.28,0.14),raised)
		if walk:
			elbow.z -= stride*(0.045 if bot else 0.12)
			hand.z -= stride*(0.065 if bot else 0.18)
		if unarmed and action in ["raise","fire","recover"]:
			elbow = Vector3(side*0.36,1.16,0.16)
			hand = Vector3(side*0.22,1.4,0.23)
			if side>0:
				var strike: float = (1.0-progress*0.3) if action == "fire" else (1.0-progress if action == "recover" else 0.0)
				elbow = elbow.lerp(Vector3(0.19,1.26,0.39),strike)
				hand = hand.lerp(Vector3(0.08,1.35,0.70),strike)
				if action == "raise":
					hand.z -= progress*0.13
					hand.y += progress*0.04
		else:
			hand += Vector3(0,recoil*0.055,-recoil*0.055)
			hand.x += side*pain*0.1
		if collapse>0.0:
			if bot:
				elbow = elbow.lerp(Vector3(side*0.24,0.92,0.06),collapse)
				hand = hand.lerp(Vector3(side*0.28,0.78,0.08),collapse)
			else:
				elbow = elbow.lerp(Vector3(side*0.36,1.12,0.17),collapse)
				hand = hand.lerp(Vector3(side*0.46,1.15,0.27),collapse)
		arm(upper,bot,side,elbow,hand)
		if side>0 and not unarmed:
			gun(upper,hand+Vector3(0,0.055,0.045),bot,raised)
	for child: Node3D in upper.get_children():
		child.position.y -= hip_height
	upper.position = hip
	upper.rotation_degrees.x = collapse*88.0 - pain*12.0 - recoil*3.0
	upper.rotation_degrees.z = collapse*11.0 + pain*6.0
	if walk:
		upper.rotation_degrees.y = sin(cycle)*(3.0 if bot else 6.0)
	return model
