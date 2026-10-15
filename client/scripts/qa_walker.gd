class_name QaWalker
extends RefCounted

## Ordinary human controls for the isolated authored range. Never mutates state.
var samples: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var phases: Dictionary[String,bool] = {}
var _last_tick: int = -1
var _last_warning: int = -1
var _dodge_z: float = 10.0
var _recoveries: int = 0
var _seen_shell: bool = false

func run(tree: SceneTree, manager: Node, directory: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(directory)
	var start: int = Time.get_ticks_msec()
	var failure: String = ""
	var last_phase: String = ""
	var initial_hp: int = -1
	var low_hp: int = 100
	var final_hp: int = 0
	var reloads: Dictionary[int,bool] = {}
	var anchor := Vector2(-9,10)
	while Time.get_ticks_msec()-start < 150000:
		await tree.create_timer(0.05).timeout
		var snapshot: Dictionary = manager.latest_snapshot
		var info: Dictionary = manager.current_map_info
		if not WalkerFacts.validation_error(snapshot,info).is_empty():
			failure = "Walker state is missing or invalid"
			break
		var tick: int = int(snapshot["tick"])
		if tick <= _last_tick:
			continue
		_last_tick = tick
		var actor: Dictionary = QaCombat.actor_by_id(snapshot,str(manager.net_client.player_id))
		if actor.is_empty() or int(actor.get("hp",0)) <= 0:
			failure = "ordinary human participant died"
			break
		if initial_hp < 0:
			initial_hp = int(actor["hp"])
		low_hp = mini(low_hp,int(actor["hp"]))
		final_hp = int(actor["hp"])
		var machine: Dictionary = snapshot["walker"]
		var phase: String = machine["phase"]
		var loadout: Dictionary = manager.net_client.equipment
		var changed: bool = phase != last_phase
		phases[phase] = true
		if phase=="recovery" and changed:
			_recoveries += 1
		if not machine["shells"].is_empty():
			_seen_shell = true
		samples.append({"tick":tick,"walker":machine.duplicate(true),"player":actor.duplicate(true),"loadout":loadout.duplicate(true)})
		QaCombat.release_inputs()
		if phase=="disabled":
			await _capture(tree,directory,manager,"disabled")
			break
		var feet := Vector3(float(actor["x"]),float(actor["y"])-LocalPrediction.FLOOR_OFFSET,float(actor["z"]))
		var eye: Vector3 = feet+Vector3(0,MoveStep.EYE_HEIGHT,0)
		var best: Vector3 = Vector3.INF
		var nearest: float = INF
		for index: Variant in info["walker"]["solids"].slice(1):
			var solid: Dictionary = WalkerFacts.translated_solid(info,int(index),machine["feet"])
			var center := Vector3((float(solid["min_x"])+float(solid["max_x"]))*0.5,(float(solid["bottom"])+float(solid["top"]))*0.5,(float(solid["min_z"])+float(solid["max_z"]))*0.5)
			if center.distance_squared_to(eye) < nearest:
				nearest = center.distance_squared_to(eye)
				best = center
		var direction: Vector3 = best-eye
		var yaw: float = atan2(direction.z,direction.x)
		manager.camera.fp_yaw = yaw
		manager.camera.fp_pitch = atan2(direction.y,Vector2(direction.x,direction.z).length())
		if phase=="artillery_warning" and int(machine["phase_started"]) != _last_warning:
			_last_warning = int(machine["phase_started"])
			_dodge_z = 2.0 if feet.z>6.0 else 10.0
		anchor.y = _dodge_z
		var course: Vector2 = anchor-Vector2(feet.x,feet.z)
		var moving: bool = course.length()>0.35
		if moving:
			manager.camera.fp_yaw = atan2(course.y,course.x)
			manager.camera.fp_pitch = 0.0
			Input.action_press("move_forward")
		var reloading: bool = false
		for magazine: Dictionary in loadout.get("loaded",[]):
			reloading = reloading or magazine.has("ready_at")
		var weapon: String = str(loadout.get("selected","flechette")) if reloading else ("rocket" if phase=="recovery" and EquipmentState.ammo(loadout,"rockets")>0 else "flechette")
		if str(loadout.get("selected","")) != weapon:
			manager.pending_weapon_swap = weapon
		elif not moving:
			if QaCombat.reload_needed(loadout):
				var press := InputEventAction.new()
				press.action = "reload"
				press.pressed = true
				Input.parse_input_event(press)
				var release: InputEventAction = press.duplicate()
				release.pressed = false
				Input.parse_input_event(release)
			elif EquipmentState.shots(loadout,weapon)>0:
				Input.action_press("fire")
		for magazine: Dictionary in loadout.get("loaded",[]):
			if magazine.has("ready_at"):
				reloads[int(magazine["ready_at"])] = true
		if changed or (not machine["shells"].is_empty() and frames.size()<30 and tick%6==0):
			await _capture(tree,directory,manager,"%s_%d" % [phase,tick])
		last_phase = phase
	QaCombat.release_inputs()
	var passed: bool = failure.is_empty() and manager.latest_snapshot.get("walker",{}).get("phase")=="disabled" \
		and phases.has("recovery") and _seen_shell and final_hp>0
	if not passed and failure.is_empty():
		failure = "ordinary encounter exceeded the bounded route time"
	var report: Dictionary = {"passed":passed,"scope":"ordinary finite human inputs on isolated Walker development range","phase_control":false,"resource_grants":false,"teleports":false,"phases":phases.keys(),"shell_seen":_seen_shell,"reload_deadlines":reloads.keys(),"initial_hp":initial_hp,"low_hp":low_hp,"final_hp":final_hp,"failure":failure,"frames":frames,"samples":samples}
	var file: FileAccess = FileAccess.open(directory.path_join("walker-route.json"),FileAccess.WRITE)
	if file==null:
		report["passed"]=false
	else:
		file.store_string(JSON.stringify(report,"\t")+"\n")
		file.close()
	if not report["passed"]:
		push_error("qa_walker: ordinary route failed: "+failure)
	return report

func _capture(tree: SceneTree, directory: String, manager: Node, label: String) -> void:
	if frames.size()>=48 or DisplayServer.get_name()=="headless":
		return
	await RenderingServer.frame_post_draw
	var filename: String = label+".png"
	var shot: Image = tree.root.get_texture().get_image()
	if shot!=null and shot.save_png(directory.path_join(filename))==OK:
		frames.append({"file":filename,"tick":manager.latest_snapshot.get("tick"),"walker":manager.latest_snapshot.get("walker",{}).duplicate(true)})
