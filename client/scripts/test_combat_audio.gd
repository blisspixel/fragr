extends SceneTree

## Combat presentation audio. The Shotgun's pump closes inside its cooldown,
## resolved shots answer with the gun that landed, Union windups are announced
## once and cut off when cancelled, falls match the body, melee never borrows
## a gunshot, and pickup and dry-trigger feedback stays with the owner. Every
## cue keys off a fact the server already sent; none changes timing or outcome.

const PAWN = preload("res://scripts/player_pawn.gd")

class TestPad extends Node:
	var ammo_pool: String = ""

class NetStub extends Node:
	var player_id: Variant = "me"
	var equipment: Dictionary = {}

class HudStub extends Node:
	var toasts: int = 0
	func show_pickup_toast(_who: String, _weapon: String, _kind: String = "weapon", _amount: int = 0) -> void:
		toasts += 1
	func show_secret_found() -> void:
		pass

class AudioManager extends "res://scripts/game_manager.gd":
	func _apply_arena_sky(_map_name: String = "") -> void:
		pass

## Every new cue: mono 48 kHz, one shot, with a bounded length.
const CUES: Dictionary[String, Vector2] = {
	"res://assets/audio/fire_scatter.wav": Vector2(0.4, 0.6),
	"res://assets/audio/shotgun/cycle.wav": Vector2(0.2, 0.37),
	"res://assets/audio/fire_tack.wav": Vector2(0.2, 0.5),
	"res://assets/audio/hit_scatter.wav": Vector2(0.2, 0.5),
	"res://assets/audio/hit_tack.wav": Vector2(0.1, 0.5),
	"res://assets/audio/hit_flechette.wav": Vector2(0.1, 0.5),
	"res://assets/audio/clerk/tell.wav": Vector2(0.1, 0.6),
	"res://assets/audio/sweeper/tell.wav": Vector2(0.2, 0.7),
	"res://assets/audio/heavy_sweeper/tell.wav": Vector2(0.4, 1.2),
	"res://assets/audio/turret/tell.wav": Vector2(0.8, 1.6),
	"res://assets/audio/down/body.wav": Vector2(0.2, 1.0),
	"res://assets/audio/down/robot.wav": Vector2(0.3, 1.2),
	"res://assets/audio/melee/fists.wav": Vector2(0.1, 0.45),
	"res://assets/audio/melee/shiv.wav": Vector2(0.1, 0.35),
	"res://assets/audio/pickup/weapon.wav": Vector2(0.1, 0.7),
	"res://assets/audio/pickup/ammo.wav": Vector2(0.1, 0.7),
	"res://assets/audio/pickup/cells.wav": Vector2(0.1, 0.7),
	"res://assets/audio/pickup/health.wav": Vector2(0.1, 0.7),
	"res://assets/audio/pickup/armor.wav": Vector2(0.1, 0.7),
	"res://assets/audio/dry_fire.wav": Vector2(0.05, 0.3),
	"res://assets/audio/grenade/throw.wav": Vector2(0.1, 0.5),
	"res://assets/audio/fire_sniper.wav": Vector2(0.4, 1.2),
	"res://assets/audio/sniper/scope_in.wav": Vector2(0.05, 0.4),
	"res://assets/audio/sniper/scope_out.wav": Vector2(0.05, 0.4),
	"res://assets/audio/ranged_sweeper/tell.wav": Vector2(0.8, 1.6),
	"res://assets/audio/ranged_sweeper/fire.wav": Vector2(0.3, 1.0),
	"res://assets/audio/l07/curfew_chime.wav": Vector2(1.5, 3.5),
}

var _failures: int = 0


func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_combat_audio: " + reason)


func _union(kind: String, phase: String, started: int, ends: int, hp: int = 80) -> Dictionary:
	return {"id": "unit-" + kind, "name": kind.to_upper(), "x": 3.0, "y": 1.5, "z": 0.0,
		"yaw": 0.0, "pitch": 0.0, "hp": hp, "weapon": "Rail", "just_fired": false,
		"campaign": {"side": "union", "kind": kind, "phase": phase,
			"phase_started": started, "phase_ends": ends}}


func _run() -> void:
	_check_cues()
	var scene: PackedScene = load("res://scenes/player.tscn")
	var pawn: Node3D = scene.instantiate()
	root.add_child(pawn)
	await process_frame
	await _check_shotgun(pawn)
	_check_melee_and_impact(pawn)
	await _check_tells(scene)
	await _check_level7(scene)
	await _check_manager(scene)
	pawn.queue_free()
	await create_timer(0.3).timeout
	if _failures == 0:
		print("test_combat_audio: PASS pump inside cooldown, resolved impacts, tells, falls, melee, pickups, dry trigger and 48 kHz cues")
	quit(0 if _failures == 0 else 1)


func _check_cues() -> void:
	for path: String in CUES:
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV
		_check(stream != null, "cue imports as a sample: " + path)
		if stream == null:
			continue
		var bounds: Vector2 = CUES[path]
		_check(stream.mix_rate == 48000 and not stream.stereo
			and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
			"cue is a mono 48 kHz one-shot: " + path)
		_check(stream.get_length() >= bounds.x and stream.get_length() <= bounds.y,
			"cue length %.3f s is inside its bound: %s" % [stream.get_length(), path])
	var cycle: AudioStream = load(PAWN.SHOTGUN_CYCLE_PATH)
	_check(is_equal_approx(PAWN.SHOTGUN_COOLDOWN_SECONDS, 12.0 * MoveStep.DT_LIVE),
		"the pump is timed against Scatter's 12-tick server cooldown")
	_check(cycle != null and PAWN.SHOTGUN_CYCLE_DELAY + cycle.get_length() < PAWN.SHOTGUN_COOLDOWN_SECONDS,
		"the action closes before the next shot can fire")
	_check(is_equal_approx(PAWN.tell_pitch("turret", 1.3, 1.3), 1.0)
		and is_equal_approx(PAWN.tell_pitch("turret", 1.3, 1.0), PAWN.TELL_PITCH_MAX)
		and is_equal_approx(PAWN.tell_pitch("turret", 1.3, 2.6), PAWN.TELL_PITCH_MIN)
		and is_equal_approx(PAWN.tell_pitch("clerk", 0.3, 0.6), 1.0)
		and is_equal_approx(PAWN.tell_pitch("turret", 1.3, 0.0), 1.0),
		"only charge tells follow the windup, inside a recognisable range")


func _check_shotgun(pawn: Node3D) -> void:
	var fire: AudioStreamPlayer3D = pawn.get_node("FireSound")
	var cycle: AudioStreamPlayer3D = pawn.get_node("CycleSound")
	var timer: Timer = pawn.get_node("ShotgunCycle")
	_check(cycle.bus == &"Effects" and cycle.max_distance == 30.0 and cycle.stream != null
		and cycle.stream.resource_path == PAWN.SHOTGUN_CYCLE_PATH,
		"the pump has its own spatial Effects voice")
	_check(fire.bus == &"Effects" and is_equal_approx(fire.volume_db, -4.0) and fire.max_distance == 50.0,
		"the existing fire route and attenuation are unchanged")
	pawn.hp = 100
	pawn.current_weapon = "Scatter"
	pawn.show_muzzle_flash("Scatter")
	_check(fire.playing and fire.stream == pawn.fire_streams["Scatter"]
		and fire.stream.resource_path == "res://assets/audio/fire_scatter.wav",
		"a resolved Shotgun shot plays the blast at once")
	_check(not timer.is_stopped() and not cycle.playing and pawn.cycle_count == 0,
		"the pump waits for the blast")
	await create_timer(PAWN.SHOTGUN_CYCLE_DELAY + 0.08).timeout
	_check(pawn.cycle_count == 1 and cycle.playing, "the pump cycles once after the blast")
	await create_timer(0.4).timeout
	pawn.show_muzzle_flash("Scatter")
	pawn.current_weapon = "Rail"
	await create_timer(PAWN.SHOTGUN_CYCLE_DELAY + 0.08).timeout
	_check(pawn.cycle_count == 1, "a fighter who switched away does not work the action")
	pawn.current_weapon = "Scatter"
	pawn.show_muzzle_flash("Scatter")
	pawn.hp = 0
	await create_timer(PAWN.SHOTGUN_CYCLE_DELAY + 0.08).timeout
	_check(pawn.cycle_count == 1, "a fallen fighter does not work the action")
	pawn.hp = 100
	pawn.current_weapon = "Rail"
	pawn.show_muzzle_flash("Rail")
	_check(timer.is_stopped(), "other guns never schedule a pump")
	await create_timer(0.2).timeout


func _check_melee_and_impact(pawn: Node3D) -> void:
	var fire: AudioStreamPlayer3D = pawn.get_node("FireSound")
	for weapon: String in ["Fists", "Shiv"]:
		fire.stop()
		pawn.show_muzzle_flash(weapon)
		_check(fire.playing and fire.stream == pawn.melee_streams[weapon]
			and fire.stream != pawn.fire_streams.get("Tack"),
			"%s swings with its own cue, never a gunshot" % weapon)
	fire.stop()
	pawn.is_campaign_enemy = true
	pawn.show_muzzle_flash("Fists")
	_check(not fire.playing, "a Crawler's leap contact is not presented as a punch")
	pawn.is_campaign_enemy = false
	var hit: AudioStreamPlayer3D = pawn.get_node("HitSound")
	for weapon: String in ["Tack", "Flechette", "Rail", "Scatter"]:
		pawn.play_impact(weapon)
		_check(hit.playing and hit.stream == pawn.hit_streams[weapon]
			and hit.stream.resource_path == "res://assets/audio/hit_%s.wav" % weapon.to_lower(),
			"the %s lands with its own impact" % weapon)
	pawn.play_impact("Fists")
	_check(hit.stream == pawn.generic_hit_stream, "melee and unknown guns keep the generic hit")


func _check_tells(scene: PackedScene) -> void:
	var turret: Node3D = scene.instantiate()
	root.add_child(turret)
	await process_frame
	var tell: AudioStreamPlayer3D = turret.get_node("TellSound")
	var down: AudioStreamPlayer3D = turret.get_node("DownSound")
	turret.update_state(_union("turret", "idle", 1, 1), 10)
	_check(turret.tell_count == 0 and not tell.playing, "an idle sweep is silent")
	turret.update_state(_union("turret", "windup", 11, 37), 11)
	var charge: AudioStream = turret.tell_streams["turret"]
	_check(turret.tell_count == 1 and tell.playing and tell.stream == charge
		and is_equal_approx(tell.pitch_scale, PAWN.tell_pitch("turret", charge.get_length(), 1.3)),
		"the Turret charge starts with its authoritative windup and peaks at its end")
	turret.update_state(_union("turret", "windup", 11, 37), 12)
	_check(turret.tell_count == 1, "repeated snapshots never restart a tell")
	turret.update_state(_union("turret", "recovery", 13, 33), 13)
	_check(not tell.playing, "breaking sight cancels the charge and its sound")
	turret.update_state(_union("turret", "windup", 20, 46), 20)
	_check(turret.tell_count == 2 and tell.playing, "a new windup is a new tell")
	turret.update_state(_union("turret", "firing", 46, 47), 46)
	_check(not tell.playing, "the shot ends the charge")
	turret.update_state(_union("turret", "dead", 50, 50, 0), 50)
	_check(turret.down_count == 1 and down.playing and down.stream == turret.down_robot_stream,
		"a destroyed machine falls as a machine")
	turret.update_state(_union("turret", "dead", 50, 50, 0), 51)
	_check(turret.down_count == 1, "a corpse does not fall twice")
	var clerk: Node3D = scene.instantiate()
	root.add_child(clerk)
	await process_frame
	clerk.update_state(_union("clerk", "moving", 1, 4), 10)
	clerk.update_state(_union("clerk", "windup", 11, 23), 11)
	var clerk_tell: AudioStreamPlayer3D = clerk.get_node("TellSound")
	_check(clerk.tell_count == 1 and clerk_tell.stream == clerk.tell_streams["clerk"]
		and is_equal_approx(clerk_tell.pitch_scale, 1.0), "a Clerk's raise plays as authored")
	clerk.update_state(_union("clerk", "dead", 30, 30, 0), 30)
	_check(clerk.down_count == 1 and clerk.get_node("DownSound").stream == clerk.down_body_stream,
		"a Clerk falls as a body")
	var notary: Node3D = scene.instantiate()
	root.add_child(notary)
	await process_frame
	notary.update_state(_union("notary", "idle", 1, 1), 10)
	notary.update_state(_union("notary", "dead", 30, 30, 0), 30)
	_check(notary.down_count == 0, "the Notary keeps its own crash")
	for unit: Node3D in [turret, clerk, notary]:
		unit.queue_free()
	await process_frame


func _check_level7(scene: PackedScene) -> void:
	_check(L07Assets.SNIPER_FIRE_SOUND == "res://assets/audio/fire_sniper.wav"
		and L07Assets.RANGED_SWEEPER_TELL_SOUND == "res://assets/audio/ranged_sweeper/tell.wav"
		and L07Assets.RANGED_SWEEPER_FIRE_SOUND == "res://assets/audio/ranged_sweeper/fire.wav"
		and L07Assets.SCOPE_IN_SOUND == "res://assets/audio/sniper/scope_in.wav"
		and L07Assets.SCOPE_OUT_SOUND == "res://assets/audio/sniper/scope_out.wav"
		and L07Assets.CURFEW_CHIME_SOUND == "res://assets/audio/l07/curfew_chime.wav",
		"the level 7 table names the delivered cues, not placeholders")
	var marksman: Node3D = scene.instantiate()
	root.add_child(marksman)
	await process_frame
	_check(not marksman.tell_streams.has("ranged_sweeper"),
		"the marksman tell has one presenter, never a second copy on the pawn")
	var state: Dictionary = _union("ranged_sweeper", "firing", 40, 41)
	state["weapon"] = "Sniper"
	marksman.update_state(state, 40)
	marksman.show_muzzle_flash("Sniper")
	var fire: AudioStreamPlayer3D = marksman.get_node("FireSound")
	_check(fire.stream != null and fire.stream == marksman.ranged_fire_stream
		and fire.stream.resource_path == L07Assets.RANGED_SWEEPER_FIRE_SOUND,
		"a Ranged Sweeper fires its own machine shot")
	marksman.queue_free()
	var audio: RangedSweeperAudio = RangedSweeperAudio.new()
	root.add_child(audio)
	await process_frame
	var listener: Vector3 = Vector3(0, 1.6, 0)
	var aim: Dictionary = _union("ranged_sweeper", "windup", 100, 130)
	_check(audio.apply({"tick": 100, "players": [aim]}, listener) == 1 and audio.voices[0].playing,
		"the marksman tell starts with its windup")
	var cue: float = audio.voices[0].stream.get_length()
	_check(is_equal_approx(audio.voices[0].pitch_scale, RangedSweeperAudio.windup_pitch(cue, 1.5))
		and audio.voices[0].stream.resource_path == L07Assets.RANGED_SWEEPER_TELL_SOUND,
		"the delivered tell is paced to the 1.5 s Standard windup")
	audio.apply({"tick": 110, "players": [_union("ranged_sweeper", "recovery", 110, 130)]}, listener)
	_check(not audio.voices[0].playing, "a cancelled windup silences the held tone")
	_check(audio.apply({"tick": 140, "players": [_union("ranged_sweeper", "windup", 140, 170)]}, listener) == 1,
		"a new windup cues again")
	audio.apply({"tick": 170, "players": [_union("ranged_sweeper", "firing", 170, 171)]}, listener)
	_check(audio.voices.all(func(voice: AudioStreamPlayer3D) -> bool: return not voice.playing),
		"the shot ends the tell")
	_check(is_equal_approx(RangedSweeperAudio.windup_pitch(1.0, 0.0), 1.0)
		and is_equal_approx(RangedSweeperAudio.windup_pitch(1.18, 3.0), RangedSweeperAudio.PITCH_MIN),
		"pacing stays inside a recognisable range")
	audio.queue_free()
	await process_frame


func _check_manager(scene: PackedScene) -> void:
	var manager: Node = Node.new()
	root.add_child(manager)
	manager.set_script(AudioManager)
	var net: NetStub = NetStub.new()
	var hud: HudStub = HudStub.new()
	manager.add_child(net)
	manager.add_child(hud)
	manager.set("net_client", net)
	manager.set("hud", hud)
	manager.set("is_human_player", true)
	manager.call("_load_audio_streams")
	var pickup: AudioStreamPlayer = manager.get("pickup_sound")
	_check(pickup != null and pickup.bus == &"Effects", "pickup feedback uses the Effects bus")
	var cells: TestPad = TestPad.new()
	cells.ammo_pool = "cells"
	var shells: TestPad = TestPad.new()
	shells.ammo_pool = "shells"
	manager.add_child(cells)
	manager.add_child(shells)
	manager.set("pickups", {"cells": cells, "shells": shells})
	for case: Array in [["health", "", "health"], ["armor", "", "armor"], ["weapon", "", "weapon"],
			["golden_rail", "", "weapon"], ["grenade", "", "ammo"], ["ammo", "shells", "ammo"],
			["ammo", "cells", "cells"], ["ammo", "missing", "ammo"]]:
		manager.call("_on_event_received", {"event": "pickup", "player": "Me", "player_id": "me",
			"kind": case[0], "weapon": "", "amount": 1, "pickup_id": case[1]})
		_check(pickup.stream == manager.get("pickup_streams")[case[2]],
			"%s pickup from %s plays the %s cue" % [case[0], case[1], case[2]])
	var heard: int = manager.get("pickup_cue_count")
	manager.call("_on_event_received", {"event": "pickup", "player": "Other", "player_id": "other",
		"kind": "health", "weapon": "", "amount": 25, "pickup_id": ""})
	_check(manager.get("pickup_cue_count") == heard and hud.toasts == heard,
		"another fighter's pickup is not this screen's feedback")
	for step: Array in [[{"tick": 1, "dry_fire_count": 0}, 0], [{"tick": 2, "dry_fire_count": 1}, 1],
			[{"tick": 3, "dry_fire_count": 1}, 1], [{}, 1], [{"tick": 4, "dry_fire_count": 4}, 1],
			[{"tick": 5, "dry_fire_count": 5}, 2], [{"tick": 6, "dry_fire_count": 0}, 2],
			[{"tick": 7, "dry_fire_count": 1.5}, 2], [{"tick": 8, "dry_fire_count": 1}, 3]]:
		manager.call("_play_dry_fire_cue", step[0])
		_check(manager.get("dry_fire_cue_count") == step[1],
			"dry trigger feedback follows only a growing count: " + str(step[0]))
	var scope: AudioStreamPlayer = manager.get("scope_sound")
	manager.call("_play_scope_cue", false, false)
	manager.call("_play_scope_cue", false, true)
	_check(manager.get("scope_cue_count") == 1 and scope.stream.resource_path == L07Assets.SCOPE_IN_SOUND,
		"raising the scope plays the scope-in cue once")
	manager.call("_play_scope_cue", true, true)
	manager.call("_play_scope_cue", true, false)
	_check(manager.get("scope_cue_count") == 2 and scope.stream.resource_path == L07Assets.SCOPE_OUT_SOUND,
		"lowering it plays the scope-out cue")
	_check(not manager.call("_scope_engaged"), "a HUD without a scope is never scoped")
	var target: Node3D = scene.instantiate()
	root.add_child(target)
	await process_frame
	manager.set("players", {"target": target})
	var pellet: Dictionary = {"shooter_id": "absent", "hit": true, "damage": 10, "target_id": "target",
		"trace": {"weapon": "scatter"}}
	manager.call("_play_shot_impacts", [pellet, pellet.duplicate(true),
		{"shooter_id": "absent", "hit": false, "damage": 0, "target_id": null}])
	_check(target.impact_count == 1 and target.get_node("HitSound").stream == target.hit_streams["Scatter"],
		"one blast is one Shotgun impact per struck body")
	manager.call("_play_shot_impacts", [{"shooter_id": "absent", "hit": true, "damage": 0,
		"target_id": "target", "trace": {"weapon": "rail"}}, "malformed"])
	_check(target.impact_count == 1, "a hit without damage or a malformed result plays nothing")
	target.queue_free()
	manager.free()
	await process_frame
