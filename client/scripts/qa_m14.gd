extends RefCounted

## Connected launch-work probe. Only ordinary human movement, aim, fire and
## reload inputs are sent; accepted maps and snapshots own every outcome.
const SUPPORT: Array[String] = ["pad_sweeper_west", "pad_sweeper_east", "pad_notary_west", "pad_notary_east", "gantry_enforcer_west", "gantry_enforcer_east", "gantry_clerk_west", "gantry_clerk_east", "gantry_heavy", "gantry_sweeper_west", "gantry_sweeper_east"]
var frames: Array[Dictionary] = []
var samples: Array[Dictionary] = []

static func actual_solids(info: Dictionary,snapshot: Dictionary) -> Array:
	var result: Array = info["solids"].duplicate(true)
	if info.get("walker") is Dictionary and snapshot.get("walker") is Dictionary:
		for index: Variant in info["walker"]["solids"]:
			result[int(index)] = WalkerFacts.translated_solid(info,int(index),snapshot["walker"]["feet"])
	return result

static func joint_aim(eye: Vector3,info: Dictionary,solids: Array) -> Vector3:
	var nearest: Vector3 = Vector3.INF
	var distance: float = INF
	for index: Variant in info.get("walker",{}).get("solids",[]).slice(1):
		var solid: Dictionary = solids[int(index)]
		var aim := Vector3(float(solid["min_x"]),1.4,(float(solid["min_z"])+float(solid["max_z"]))*0.5)
		var clear: bool = true
		for other: int in range(solids.size()):
			if other == int(index):
				continue
			var box: AABB = M14Launch._solid_bounds(solids[other])
			if box.intersects_segment(eye,aim) != null:
				clear = false
				break
		if clear and eye.distance_squared_to(aim) < distance:
			nearest = aim
			distance = eye.distance_squared_to(aim)
	return nearest

func run(tree: SceneTree,manager: Node,directory: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(directory)
	var combat := QaCombat.new()
	combat.begin(manager)
	var start: int = Time.get_ticks_msec()
	var last_tick: int = -1
	var last_warning: int = -1
	var destination := Vector2(-1,28)
	var last_phase: String = ""
	var phases: Dictionary = {}
	var reloads: Dictionary = {}
	var failure: String = ""
	var final_hp: int = 0
	var low_hp: int = 100
	var passed: bool = false
	while Time.get_ticks_msec()-start < 180000:
		await tree.create_timer(0.05).timeout
		var snapshot: Dictionary = manager.latest_snapshot
		var info: Dictionary = manager.current_map_info
		var state: Dictionary = manager.net_client.mission.get("state",{})
		if not M14MissionState.map_error(info).is_empty() or not state.get("m14") is Dictionary:
			failure = "accepted launch map and mission facts unavailable"
			break
		var tick: int = int(snapshot.get("tick",-1))
		if tick <= last_tick:
			continue
		last_tick = tick
		var player_id: String = str(manager.net_client.player_id)
		var actor: Dictionary = QaCombat.actor_by_id(snapshot,player_id)
		if actor.is_empty() or int(actor.get("hp",0)) <= 0:
			failure = "ordinary human participant died"
			break
		final_hp = int(actor["hp"])
		low_hp = mini(low_hp,final_hp)
		var machine: Dictionary = snapshot.get("walker",{})
		var phase: String = str(machine.get("phase","fallen"))
		var loadout: Dictionary = manager.net_client.equipment
		var enemies: Array = snapshot.get("players",[]).filter(func(body: Dictionary) -> bool: return body.get("name","") in SUPPORT and int(body.get("hp",0))>0)
		samples.append({"tick":tick,"m14":state["m14"].duplicate(true),"walker":machine.duplicate(true),"player":actor.duplicate(true),"loadout":loadout.duplicate(true),"enemies":enemies.duplicate(true)})
		QaCombat.release_inputs()
		var cleared: bool = state["m14"]["completed"].size() >= 6
		if cleared and Vector2(float(actor["x"])+1,float(actor["z"])-50).length()<0.3:
			passed = bool(state["m14"]["machine_fallen"]) and phases.has("recovery")
			await _capture(tree,manager,directory,"fallen_gantry_cleared")
			break
		var solids: Array = actual_solids(info,snapshot)
		var eye := Vector3(float(actor["x"]),float(actor["y"])+QaCombat.CAMERA.FP_EYE_HEIGHT,float(actor["z"]))
		var target: Dictionary = QaCombat.visible_target(snapshot,player_id,solids,false,28.0,SUPPORT)
		var aim: Vector3 = QaCombat.exposed_point(target,eye,solids) if not target.is_empty() else joint_aim(eye,info,solids)
		phases[phase] = true
		if phase == "artillery_warning" and int(machine["phase_started"]) != last_warning:
			last_warning = int(machine["phase_started"])
			destination = Vector2(-1,28 if float(actor["z"])>33 else 38)
		# Support windups remain dangerous after the artillery escape ends.
		# Continue ordinary lateral travel instead of waiting stationary for
		# several simultaneous locked shots at the last dodge endpoint.
		if not target.is_empty() and int(machine.get("hp",0))>0 and phase not in ["artillery_warning","artillery"] and machine.get("shells",[]).is_empty():
			if Vector2(float(actor["x"]),float(actor["z"])).distance_to(destination)<0.8:
				destination.y = 28 if destination.y>33 else 38
		# A disabled machine can still own flying shells. Keep the committed
		# escape destination until the accepted shell list actually drains.
		if phase in ["disabled","fallen"] and machine.get("shells",[]).is_empty():
			destination.y = 50
			if Vector2(float(actor["x"]),float(actor["z"])).distance_to(destination)<0.6:
				destination.x = 13 if destination.x<0 else -1
		if cleared:
			# Retire only after the actual final guards clear. Reach a known safe
			# northern anchor through ordinary input before the next still/Use.
			destination = Vector2(float(actor["x"]) if float(actor["z"])<49.7 else -1,50)
		var reloading: bool = false
		for magazine: Dictionary in loadout.get("loaded",[]):
			if magazine.has("ready_at"):
				reloading = true
				reloads[int(magazine["ready_at"])] = true
		var selected: String = str(loadout.get("selected","flechette"))
		var weapon: String = selected if reloading else ("rocket" if target.is_empty() and phase == "recovery" and EquipmentState.ammo(loadout,"rockets")>0 else "flechette")
		if selected != weapon:
			manager.pending_weapon_swap = weapon
		elif aim.is_finite():
			var direction: Vector3 = aim-eye
			manager.camera.fp_yaw = atan2(direction.z,direction.x)
			manager.camera.fp_pitch = atan2(direction.y,Vector2(direction.x,direction.z).length())
			if QaCombat.reload_needed(loadout):
				var press := InputEventAction.new()
				press.action = "reload"
				press.pressed = true
				Input.parse_input_event(press)
				var release: InputEventAction = press.duplicate()
				release.pressed = false
				Input.parse_input_event(release)
			elif EquipmentState.shots(loadout,weapon)>0 and (not target.is_empty() or phase=="recovery"):
				# Conserve the finite Rifle bag for guards. Closed plated joints
				# still take native chip damage, but waiting for their exposed
				# recovery is the ordinary weak-point lesson this route exercises.
				Input.action_press("fire")
		var course: Vector2 = destination-Vector2(float(actor["x"]),float(actor["z"]))
		if course.length()>(0.2 if cleared else 0.45):
			if cleared:
				manager.camera.fp_yaw = atan2(course.y,course.x)
				manager.camera.fp_pitch = 0.0
			var buttons: Dictionary = QaCombat.route_buttons(course,manager.camera.fp_yaw)
			for action: String in buttons:
				if buttons[action]:
					Input.action_press(action)
		if phase != last_phase:
			await _capture(tree,manager,directory,"%s_%d" % [phase,tick])
		last_phase = phase
	QaCombat.release_inputs()
	combat.finish()
	if not passed and failure.is_empty():
		failure = "connected Walker, supports and final gantry did not clear within bounded ordinary route"
	var report: Dictionary = {"passed":passed,"scope":"ordinary finite human inputs through M14 Walker, registered support waves and final gantry","phase_control":false,"resource_grants":false,"teleports":false,"low_hp":low_hp,"final_hp":final_hp,"phases":phases.keys(),"reload_deadlines":reloads.keys(),"failure":failure,"frames":frames,"samples":samples}
	var file := FileAccess.open(directory.path_join("m14-battle.json"),FileAccess.WRITE)
	if file == null:
		report["passed"] = false
	else:
		file.store_string(JSON.stringify(report,"\t")+"\n")
		file.close()
	if not report["passed"]:
		push_error("qa_m14: "+failure)
	return report

func _capture(tree: SceneTree,manager: Node,directory: String,label: String) -> void:
	if frames.size()>=48 or DisplayServer.get_name()=="headless":
		return
	await RenderingServer.frame_post_draw
	var filename: String = label+".png"
	var shot: Image = tree.root.get_texture().get_image()
	if shot != null and shot.save_png(directory.path_join(filename)) == OK:
		frames.append({"file":filename,"tick":manager.latest_snapshot.get("tick"),"m14":manager.net_client.mission.get("state",{}).get("m14",{}).duplicate(true)})
