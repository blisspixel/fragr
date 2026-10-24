extends SceneTree

## Reload readability: request, accepted start, sustained progress, completion,
## cancellation and refusal, deduplicated per life, weapon and deadline, and
## cleared on swap, death, vehicle, map change and disconnect. The cue reads
## only private loadouts and the reload edge this client sent.

class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: Variant = "self"
	var equipment: Dictionary = {}
	var mission: Dictionary = {}
	var last_send_ok: bool = false
	var fail_next: bool = false
	var sent: Array[Dictionary] = []
	func send_action(action: Dictionary) -> void:
		last_send_ok = not fail_next
		fail_next = false
		if last_send_ok:
			sent.append(action.duplicate(true))

class PawnProbe extends Node3D:
	var hp: int = 100
	func get_weapon_name() -> String:
		return "Flechette"

class CameraProbe extends Node3D:
	var fp_mode: bool = true
	var fp_target: Node = null
	func get_followed_target() -> Node:
		return fp_target
	func is_observing_first_person() -> bool:
		return true

class HudProbe extends Node:
	var fp_juice_enabled: bool = true
	var equipment_hud: EquipmentHud = EquipmentHud.new()
	var fp_reload_motion := WeaponArt.ReloadMotion.new()
	func _init() -> void:
		add_child(equipment_hud)
	func show_fire_juice(_weapon: String) -> void:
		pass
	func cancel_fire_juice() -> void:
		pass

var _failures: int = 0
## Reload playbacks started through the real manager, released before exit.
var _voices: Array[WeakRef] = []
const RELEASE_DEADLINE_MS: int = 5000

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_reload_cue: " + message)

const POOL_ROUNDS: Dictionary = {"bullets": 200, "shells": 50, "cells": 100, "rockets": 20}

## A discovery loadout (fists carried, finite bag) holding one gun.
func _loadout(weapon: String, rounds: int, tick: int, ready_at: int = -1, bag: int = -1) -> Dictionary:
	var pool: String = str(EquipmentState.POOLS[weapon])
	var ammo: Array = []
	for name: String in EquipmentState.POOL_ORDER:
		var amount: int = 0
		if name == pool:
			amount = bag if bag >= 0 else mini(int(POOL_ROUNDS[name]), rounds + 40)
		ammo.append({"pool": name, "rounds": amount})
	var magazine: Dictionary = {"weapon": weapon, "rounds": rounds}
	if ready_at >= 0:
		magazine["ready_at"] = ready_at
	return {"type": "loadout", "player_id": "self", "tick": tick, "selected": weapon,
		"weapons": ["fists", weapon], "ammo": ammo, "personal_claims": [],
		"dry_fire_count": 0, "grenades": 0, "loaded": [magazine]}

func _run() -> void:
	_check_refusals()
	_check_every_ordinary_gun()
	_check_duplicates_and_late_receipts()
	_check_cancel_swap_and_reset()
	_check_pending_and_taps()
	_check_hud_line()
	await _check_manager_wiring()
	print("test_reload_cue: %s" % ("PASS" if _failures == 0 else "FAIL %d" % _failures))
	quit(0 if _failures == 0 else 1)

func _check_refusals() -> void:
	var partial: Dictionary = _loadout("tack", 5, 10)
	_check(EquipmentState.validation_error(partial, "self").is_empty(), "fixture loadout is a valid private state")
	_check(ReloadCue.refusal(partial) == "", "a partial pistol with rounds in the bag can reload")
	_check(ReloadCue.refusal(_loadout("tack", 12, 10)) == "full", "a full magazine is refused as full")
	var dry: Dictionary = _loadout("tack", 4, 10, -1, 4)
	_check(EquipmentState.reserve(dry, "tack") == 0 and ReloadCue.refusal(dry) == "no_reserve", "nothing left in a finite bag is refused")
	var fists: Dictionary = partial.duplicate(true)
	fists["selected"] = "fists"
	_check(ReloadCue.refusal(fists) == "no_magazine", "fists have nothing to reload")
	var pool_only: Dictionary = partial.duplicate(true)
	pool_only.erase("loaded")
	_check(ReloadCue.refusal(pool_only) == "unsupported" and ReloadCue.refusal({}) == "unsupported", "a loadout without magazines cannot reload here")
	_check(ReloadCue.refusal(_loadout("tack", 0, 10, 26)) == "busy", "a running reload makes another press busy")
	# A weapon-only gun has one owned gun and three zero pools: an unlimited reserve.
	var only: Dictionary = {"type": "loadout", "player_id": "self", "tick": 10, "selected": "rail",
		"weapons": ["rail"], "ammo": [{"pool": "bullets", "rounds": 0}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}, {"pool": "rockets", "rounds": 0}],
		"personal_claims": [], "dry_fire_count": 0, "grenades": 0, "loaded": [{"weapon": "rail", "rounds": 1}]}
	_check(EquipmentState.validation_error(only, "self").is_empty(), "weapon-only fixture is valid")
	_check(EquipmentState.reserve(only, "rail") == -1 and ReloadCue.refusal(only) == "", "a weapon-only gun reloads from an unlimited reserve")
	# A finite arcade bag spent to zero carries several guns and is really empty.
	var spent: Dictionary = only.duplicate(true)
	spent["weapons"] = ["flechette", "scatter", "rail"]
	spent["loaded"] = [{"weapon": "flechette", "rounds": 0}, {"weapon": "scatter", "rounds": 0}, {"weapon": "rail", "rounds": 0}]
	_check(EquipmentState.reserve(spent, "rail") == 0 and ReloadCue.refusal(spent) == "no_reserve", "a spent finite arcade bag is not mistaken for weapon-only")
	var cue := ReloadCue.new()
	for case: Array in [[_loadout("tack", 12, 10), "full", "HUD_RELOAD_FULL"], [dry, "no_reserve", "HUD_RELOAD_NO_RESERVE"], [fists, "no_magazine", "HUD_RELOAD_NO_MAGAZINE"], [pool_only, "unsupported", "HUD_RELOAD_UNSUPPORTED"]]:
		_check(cue.request(case[0], 1000) == case[1] and cue.phase == ReloadCue.Phase.UNAVAILABLE and cue.status_key() == case[2], "a refused press shows its own line: " + str(case[1]))
	_check(cue.unavailable == 4 and cue.starts == 0, "refusals count but never start")
	cue.advance(1000 + ReloadCue.UNAVAILABLE_USEC)
	_check(cue.phase == ReloadCue.Phase.IDLE and cue.status_key().is_empty(), "the refusal line expires")

func _check_every_ordinary_gun() -> void:
	for weapon: String in EquipmentState.MAGAZINE_SIZES:
		var cue := ReloadCue.new()
		cue.observe(_loadout(weapon, 0, 100), 0)
		_check(cue.request(_loadout(weapon, 0, 100), 10) == "" and cue.phase == ReloadCue.Phase.PENDING and cue.status_key() == "HUD_RELOAD_PENDING", weapon + ": an acceptable press is pending, not accepted")
		var accepted: Array[String] = cue.observe(_loadout(weapon, 0, 101, 121), 50010)
		_check(accepted == ["start"] and cue.active() and cue.status_key() == "HUD_RELOAD_ACTIVE" and not cue.adopted, weapon + ": the accepting loadout starts once")
		_check(cue.last_request_to_accept_usec == 50000, weapon + ": request-to-accept is measured from the sent edge")
		cue.presented(50250)
		_check(cue.last_accept_to_cue_usec == 240, weapon + ": accept-to-cue is measured separately")
		_check(is_equal_approx(cue.progress(111), 0.5) and cue.progress(101) == 0.0 and cue.progress(140) == 1.0, weapon + ": progress spans the accepted interval")
		var size: int = int(EquipmentState.MAGAZINE_SIZES[weapon])
		_check(cue.observe(_loadout(weapon, size, 121), 1100000) == ["complete"] and cue.status_key() == "HUD_RELOAD_COMPLETE" and cue.progress(121) == 1.0, weapon + ": a filled magazine at the deadline completes once")
		cue.advance(1100000 + ReloadCue.COMPLETE_USEC)
		_check(cue.phase == ReloadCue.Phase.IDLE and cue.starts == 1 and cue.completions == 1 and cue.cancellations == 0, weapon + ": the completion line expires with one start and one finish")

func _check_duplicates_and_late_receipts() -> void:
	var cue := ReloadCue.new()
	cue.observe(_loadout("flechette", 3, 10), 0)
	cue.request(_loadout("flechette", 3, 10), 1)
	var accept: Dictionary = _loadout("flechette", 3, 11, 33)
	_check(cue.observe(accept, 2) == ["start"], "first acceptance starts")
	_check(cue.observe(accept, 3).is_empty(), "the same loadout again is silent")
	var other_change: Dictionary = accept.duplicate(true)
	other_change["tick"] = 15
	other_change["grenades"] = 1
	_check(cue.observe(other_change, 4).is_empty() and cue.active(), "an unrelated loadout change during the reload is silent")
	var early: Dictionary = _loadout("flechette", 3, 20)
	_check(cue.observe(early, 5) == ["cancel"] and cue.status_key() == "HUD_RELOAD_CANCELLED", "a deadline that vanishes early without rounds is a cancel")
	_check(cue.observe(accept, 6).is_empty() and not cue.active(), "a stale copy of the accepted deadline cannot start it again")
	var not_grown: Array[String] = ReloadCue.new().observe(_loadout("flechette", 3, 10), 0)
	_check(not_grown.is_empty(), "a first loadout with no reload is silent")
	# A reload that is already running when the cue (re)starts is adopted
	# quietly: reconnect, vehicle exit, rejoining first person.
	var late := ReloadCue.new()
	_check(late.observe(_loadout("rail", 0, 50, 70), 0).is_empty() and late.active() and late.adopted, "a reload in flight at the first observation is shown without a late start sound")
	_check(late.observe(_loadout("rail", 4, 70), 1) == ["complete"], "an adopted reload can still finish while live")
	_check(late.observe(_loadout("rail", 4, 70), 2).is_empty(), "a repeated finished loadout is silent")

func _check_cancel_swap_and_reset() -> void:
	var cue := ReloadCue.new()
	cue.observe(_loadout("scatter", 2, 10), 0)
	cue.request(_loadout("scatter", 2, 10), 1)
	cue.observe(_loadout("scatter", 2, 11, 25), 2)
	var swapped: Dictionary = _loadout("scatter", 2, 12)
	swapped["weapons"] = ["fists", "scatter", "tack"]
	swapped["selected"] = "tack"
	swapped["loaded"].append({"weapon": "tack", "rounds": 12})
	swapped["ammo"][0]["rounds"] = 40
	_check(EquipmentState.validation_error(swapped, "self").is_empty(), "swap fixture is valid")
	_check(cue.observe(swapped, 3).is_empty() and cue.phase == ReloadCue.Phase.IDLE and cue.status_key().is_empty(), "a weapon swap clears the reload quietly")
	# The deadline passed but the server never filled the gun: not complete.
	var stalled := ReloadCue.new()
	stalled.observe(_loadout("sniper", 1, 10), 0)
	stalled.request(_loadout("sniper", 1, 10), 1)
	stalled.observe(_loadout("sniper", 1, 11, 39), 2)
	_check(stalled.observe(_loadout("sniper", 1, 39), 3) == ["cancel"] and stalled.completions == 0, "completion requires the authoritative magazine to grow")
	# Death, respawn, vehicle, map change and disconnect all reset silently.
	var dead := ReloadCue.new()
	dead.observe(_loadout("tack", 0, 10), 0)
	dead.request(_loadout("tack", 0, 10), 1)
	dead.observe(_loadout("tack", 0, 11, 27), 2)
	var epoch: int = dead.epoch
	dead.reset()
	_check(dead.phase == ReloadCue.Phase.IDLE and dead.epoch == epoch + 1 and dead.status_key().is_empty() and dead.progress(20) == 0.0, "reset clears an active reload with no line or bar")
	_check(dead.observe(_loadout("tack", 12, 27), 3).is_empty() and dead.completions == 0, "a completion receipt after a reset is not a late finish")
	dead.reset()
	_check(dead.observe({}, 4).is_empty() and dead.phase == ReloadCue.Phase.IDLE, "an empty loadout is a silent disconnect")

func _check_pending_and_taps() -> void:
	var cue := ReloadCue.new()
	var state: Dictionary = _loadout("repeater", 10, 10)
	cue.observe(state, 0)
	_check(cue.request(state, 100) == "" and cue.request(state, 200) == "" and cue.request(state, 300) == "", "rapid taps keep one pending request")
	cue.advance(100 + ReloadCue.PENDING_TIMEOUT_USEC - 1)
	_check(cue.phase == ReloadCue.Phase.PENDING, "a request stays pending inside the timeout")
	cue.advance(100 + ReloadCue.PENDING_TIMEOUT_USEC)
	_check(cue.phase == ReloadCue.Phase.UNAVAILABLE and cue.status_key() == "HUD_RELOAD_NOT_ACCEPTED" and cue.starts == 0, "an unanswered request is corrected, never shown as reloading")
	_check(cue.observe(_loadout("repeater", 10, 30, 52), 2000000) == ["start"], "a later acceptance still starts")
	_check(cue.last_request_to_accept_usec == -1 or cue.last_request_to_accept_usec >= 0, "latency fields stay integers")
	var running: Dictionary = _loadout("repeater", 10, 31, 52)
	_check(cue.request(running, 2000001) == "busy" and cue.active() and cue.unavailable == 1, "a tap during the reload neither restarts nor warns")
	_check(cue.request(_loadout("repeater", 30, 31), 2000002) == "full" and cue.active(), "a refusal line never hides a running reload")

func _check_hud_line() -> void:
	var display := EquipmentHud.new()
	root.add_child(display)
	var empty: Dictionary = _loadout("tack", 0, 10)
	display.apply(empty)
	display.visible = true
	display._refresh()
	_check(display.empty_label.visible and not display.reload_label.visible and not display.reload_bar_visible(), "an empty gun says EMPTY before any reload")
	display.reload.observe(empty, 0)
	display.reload.request(empty, 1)
	display._refresh()
	_check(display.reload_label.visible and display.reload_label.text == "RELOAD REQUESTED" and not display.empty_label.visible and not display.reload_bar_visible(), "a pending press reads as requested on the EMPTY row, without a bar")
	var accepted: Dictionary = _loadout("tack", 0, 11, 27)
	display.apply(accepted)
	display.reload.observe(accepted, 2)
	display.tick = 19
	display._refresh()
	_check(display.reload_label.text == "RELOADING" and display.reload_bar_visible() and is_equal_approx(display.reload.progress(display.tick), 0.5), "an accepted reload shows RELOADING with a half bar midway")
	_check(display.reload_bar_rect().position.y >= 84.0 and display.reload_bar_rect().end.x <= EquipmentHud.WIDTH, "the bar sits under the count inside the panel")
	var done: Dictionary = _loadout("tack", 12, 27)
	display.apply(done)
	display.reload.observe(done, 3)
	display._refresh()
	_check(display.reload_label.text == "LOADED" and display.reload_colour() == MenuTheme.BONE and display.reload_bar_colour() == MenuTheme.SUCCESS, "the finish reads LOADED over a full green bar")
	display.apply({})
	_check(display.reload.phase == ReloadCue.Phase.IDLE and not display.reload_label.visible, "a cleared loadout drops the reload line")
	display.free()

## The real manager: one sent edge, one start and one finish sound, nothing on
## duplicates, death, vehicle seats or disconnect.
func _check_manager_wiring() -> void:
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var network := CaptureNetwork.new()
	var hud := HudProbe.new()
	var pawn := PawnProbe.new()
	var camera := CameraProbe.new()
	camera.fp_target = pawn
	root.add_child(hud)
	manager.net_client = network
	manager.hud = hud
	manager.camera = camera
	manager.is_human_player = true
	manager.players["self"] = pawn
	manager.local_fp_pawn_id = "self"
	manager._load_audio_streams()
	# The manager is not in the tree here; its reload player must be to play.
	if manager.reload_sound != null:
		manager.reload_sound.get_parent().remove_child(manager.reload_sound)
		root.add_child(manager.reload_sound)
	_check(manager.reload_sound != null and manager.reload_start_stream != null and manager.reload_complete_stream != null and manager.reload_sound.bus == &"Effects", "reload audio reuses the committed handling sounds on the Effects bus")
	var partial: Dictionary = _loadout("flechette", 4, 100)
	network.equipment = partial
	_deliver(manager, partial)
	_check(manager._reload_context_live and hud.equipment_hud.reload.phase == ReloadCue.Phase.IDLE, "the live fighter's first loadout is observed silently")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	manager.reload_armed = true
	manager._input(key)
	manager._last_action_usec = -1000000000
	_send(manager)
	_check(network.sent.back().get("reload") == true and hud.equipment_hud.reload.phase == ReloadCue.Phase.PENDING, "the sent reload edge shows a pending request")
	# Holding R keeps reload on the wire without asking again.
	Input.action_press("reload")
	manager._last_action_usec = -1000000000
	_send(manager)
	_check(network.sent.back().get("reload") == true and hud.equipment_hud.reload.unavailable == 0 and hud.equipment_hud.reload.phase == ReloadCue.Phase.PENDING, "a held key is not a second request")
	Input.action_release("reload")
	manager._last_action_usec = -1000000000
	_send(manager)
	_check(not network.sent.back().has("reload") and not manager._reload_sent_down, "releasing R clears the sent edge")
	var accepted: Dictionary = _loadout("flechette", 4, 101, 123)
	network.equipment = accepted
	_deliver(manager, accepted)
	_check(manager.reload_start_cue_count == 1 and manager.reload_sound.stream == manager.reload_start_stream and is_equal_approx(manager.reload_sound.pitch_scale, manager.RELOAD_START_PITCH), "acceptance plays one start sound")
	_check(hud.equipment_hud.reload.last_accept_to_cue_usec >= 0, "accept-to-cue is recorded for the live path")
	_deliver(manager, accepted)
	_deliver(manager, accepted)
	_check(manager.reload_start_cue_count == 1, "repeated loadouts never replay the start")
	var filled: Dictionary = _loadout("flechette", 20, 123)
	network.equipment = filled
	_deliver(manager, filled)
	_deliver(manager, filled)
	_check(manager.reload_complete_cue_count == 1 and manager.reload_sound.stream == manager.reload_complete_stream, "the filled magazine plays one completion sound")
	# A full gun: the edge still goes out, the corner says FULL, no sound.
	manager.reload_armed = true
	manager._input(key)
	manager._last_action_usec = -1000000000
	_send(manager)
	manager._last_action_usec = -1000000000
	_send(manager)
	_check(hud.equipment_hud.reload.status_key() == "HUD_RELOAD_FULL" and manager.reload_start_cue_count == 1, "a full magazine shows a silent refusal")
	# Death mid-reload: nothing late, not even when the server's loadouts land.
	var second: Dictionary = _loadout("flechette", 2, 200, 222)
	hud.equipment_hud.reload.reset()
	network.equipment = second
	_deliver(manager, second)
	pawn.hp = 0
	manager._refresh_equipment_visibility()
	_check(not manager._reload_context_live and hud.equipment_hud.reload.phase == ReloadCue.Phase.IDLE, "death clears the reload presentation")
	var after_death: Dictionary = _loadout("flechette", 20, 222)
	network.equipment = after_death
	_deliver(manager, after_death)
	_check(manager.reload_complete_cue_count == 1 and manager.reload_start_cue_count == 1, "no late completion is heard while dead")
	pawn.hp = 100
	manager._refresh_equipment_visibility()
	_check(manager._reload_context_live and hud.equipment_hud.reload.phase == ReloadCue.Phase.IDLE, "respawn adopts the current loadout silently")
	# Vehicle seat: the server may finish the reload; the seat hears nothing.
	var third: Dictionary = _loadout("flechette", 1, 300)
	network.equipment = third
	_deliver(manager, third)
	manager.reload_armed = true
	manager._input(key)
	manager._last_action_usec = -1000000000
	_send(manager)
	var third_accept: Dictionary = _loadout("flechette", 1, 301, 323)
	network.equipment = third_accept
	_deliver(manager, third_accept)
	_check(manager.reload_start_cue_count == 2, "a new life's reload starts once")
	manager.latest_snapshot = {"tick": 305, "vehicles": [{"id": 1, "kind": "jeep", "driver": null, "gunner": "self"}]}
	_check(manager._vehicle_seat() == "gunner", "vehicle fixture seats the local fighter")
	manager._refresh_equipment_visibility()
	_check(not manager._reload_context_live and hud.equipment_hud.reload.phase == ReloadCue.Phase.IDLE, "a vehicle seat clears the reload presentation")
	var seated_finish: Dictionary = _loadout("flechette", 20, 323)
	network.equipment = seated_finish
	_deliver(manager, seated_finish)
	_check(manager.reload_complete_cue_count == 1, "a reload finished in the seat is silent")
	manager.latest_snapshot = {}
	# Disconnect clears everything at once.
	network.equipment = _loadout("flechette", 5, 400)
	manager._refresh_equipment_visibility()
	manager._reset_reload_presentation()
	_check(not manager._reload_context_live and hud.equipment_hud.reload.phase == ReloadCue.Phase.IDLE and not manager._reload_sent_down, "disconnect and map change drop the cue")
	manager.reload_sound.stop()
	manager.reload_sound.stream = null
	# The audio server releases stopped playbacks on its own mix thread, which
	# a loaded machine can delay well past a fixed frame count. Wait on the
	# actual playbacks, bounded, as ClientRetirement does at exit.
	var release_by: int = Time.get_ticks_msec() + RELEASE_DEADLINE_MS
	while not _voices_released() and Time.get_ticks_msec() < release_by:
		await process_frame
	_check(_voices_released(), "every reload playback is released before exit")
	_voices.clear()
	manager.reload_sound.free()
	manager.free()
	hud.free()
	pawn.free()
	camera.free()
	network.free()
	await process_frame

## Deliver one private loadout and remember any reload voice it started.
func _deliver(manager: Node, loadout: Dictionary) -> void:
	manager._on_loadout_received(loadout)
	var player: AudioStreamPlayer = manager.reload_sound
	if player != null and player.has_stream_playback():
		var playback: AudioStreamPlayback = player.get_stream_playback()
		for reference: WeakRef in _voices:
			if reference.get_ref() == playback:
				return
		_voices.append(weakref(playback))

func _voices_released() -> bool:
	for reference: WeakRef in _voices:
		if reference.get_ref() != null:
			return false
	return true

func _send(manager: Node) -> void:
	_check(manager._send_local_action(Time.get_ticks_usec()), "the paced action actually went out")
