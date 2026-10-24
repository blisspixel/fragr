class_name ReloadCue
extends RefCounted

## What the local player can know about one reload, from the private loadout
## the server sends and the reload edge this client actually sent. It never
## grants rounds and never says a reload finished before the server's loadout
## shows the magazine filled.
##
## Requested: the edge went out and the last loadout says the server should
## accept it. Active: a loadout carries `ready_at` for the gun. Complete: that
## same gun, still selected, reached its deadline with more rounds. Cancelled:
## the deadline vanished any other way. Unavailable: the last loadout already
## says the server will ignore the press (full, nothing left, melee, no
## magazines in this mode), or a request was never accepted.
##
## Each accepted deadline starts once per life. `reset()` is the silent clear
## for swap, death, respawn, disconnect, map change and vehicle seats.

enum Phase { IDLE, PENDING, ACTIVE, COMPLETE, CANCELLED, UNAVAILABLE }

## A request with no accepted deadline after this long is reported as not
## accepted. It covers a separate host's round trip plus one server tick.
const PENDING_TIMEOUT_USEC: int = 1000000
## How long the short result lines stay up.
const COMPLETE_USEC: int = 700000
const CANCELLED_USEC: int = 900000
const UNAVAILABLE_USEC: int = 900000

## Status line translation keys by phase or unavailable reason.
const STATUS_KEYS: Dictionary[String, String] = {
	"pending": "HUD_RELOAD_PENDING",
	"active": "HUD_RELOAD_ACTIVE",
	"complete": "HUD_RELOAD_COMPLETE",
	"cancelled": "HUD_RELOAD_CANCELLED",
	"full": "HUD_RELOAD_FULL",
	"no_reserve": "HUD_RELOAD_NO_RESERVE",
	"no_magazine": "HUD_RELOAD_NO_MAGAZINE",
	"unsupported": "HUD_RELOAD_UNSUPPORTED",
	"not_accepted": "HUD_RELOAD_NOT_ACCEPTED",
}

var phase: Phase = Phase.IDLE
var weapon: String = ""
var deadline: int = -1
## Server tick the accepted reload is measured from: the accepting loadout's
## tick, or the first tick this client saw for an adopted reload.
var started_tick: int = -1
var reason: String = ""
## True for a reload first seen after a reset with no request of ours pending.
var adopted: bool = false
## Life epoch, advanced by every reset. Starts are unique within one epoch.
var epoch: int = 0

## Counters for harnesses and the performance overlay.
var starts: int = 0
var completions: int = 0
var cancellations: int = 0
var unavailable: int = 0
## Microseconds from the sent edge to the accepting loadout, and from that
## loadout to the cue being presented. -1 until measured.
var last_request_to_accept_usec: int = -1
var last_accept_to_cue_usec: int = -1

var _phase_until_usec: int = 0
var _request_usec: int = -1
var _accept_usec: int = -1
var _rounds_at_start: int = 0
var _baseline: bool = true
var _seen: Dictionary[String, bool] = {}

## Silent clear. Nothing that was in flight may produce a later sound.
func reset() -> void:
	phase = Phase.IDLE
	weapon = ""
	deadline = -1
	started_tick = -1
	reason = ""
	adopted = false
	epoch += 1
	_phase_until_usec = 0
	_request_usec = -1
	_accept_usec = -1
	_rounds_at_start = 0
	_baseline = true
	_seen.clear()

func active() -> bool:
	return phase == Phase.ACTIVE

## The reload edge actually left this client, or R was pressed where no
## magazines exist. Returns "" when the request is now pending, "busy" while
## a reload already runs, or the reason the server will ignore it.
func request(state: Dictionary, now_usec: int) -> String:
	var why: String = refusal(state)
	if why == "busy":
		return why
	if not why.is_empty():
		_show_unavailable(why, now_usec)
		return why
	if phase == Phase.PENDING:
		return ""
	phase = Phase.PENDING
	reason = ""
	weapon = str(state.get("selected", ""))
	_request_usec = now_usec
	_phase_until_usec = now_usec + PENDING_TIMEOUT_USEC
	return ""

## The server's refusal rules applied to the last loadout, for presentation.
## Mirrors `Inventory::can_reload`; the server stays the authority.
static func refusal(state: Dictionary) -> String:
	if state.is_empty() or not state.has("loaded"):
		return "unsupported"
	var selected: String = str(state.get("selected", ""))
	var size: int = int(EquipmentState.MAGAZINE_SIZES.get(selected, 0))
	if size <= 0:
		return "no_magazine"
	var entry: Dictionary = EquipmentState.magazine(state, selected)
	if entry.is_empty():
		return "no_magazine"
	for magazine: Variant in state.get("loaded", []):
		if magazine is Dictionary and (magazine as Dictionary).has("ready_at"):
			return "busy"
	if int(entry.get("rounds", 0)) >= size:
		return "full"
	if EquipmentState.reserve(state, selected) == 0:
		return "no_reserve"
	return ""

## One validated private loadout. Returns the cues to present: "start",
## "complete", "cancel". Repeated or duplicate loadouts return nothing.
func observe(state: Dictionary, now_usec: int) -> Array[String]:
	var events: Array[String] = []
	if state.is_empty():
		reset()
		return events
	var tick: int = int(state.get("tick", 0))
	var reloading: String = ""
	var ready_at: int = -1
	for entry: Variant in state.get("loaded", []):
		if entry is Dictionary and (entry as Dictionary).has("ready_at"):
			reloading = str(entry.get("weapon", ""))
			ready_at = int(entry["ready_at"])
			break
	var selected: String = str(state.get("selected", ""))
	if phase == Phase.ACTIVE and (reloading != weapon or ready_at != deadline):
		var rounds: int = int(EquipmentState.magazine(state, weapon).get("rounds", 0))
		if selected == weapon and tick >= deadline and rounds > _rounds_at_start:
			phase = Phase.COMPLETE
			_phase_until_usec = now_usec + COMPLETE_USEC
			completions += 1
			events.append("complete")
		elif selected != weapon:
			# A real weapon change is the player's own act: clear quietly.
			phase = Phase.IDLE
		else:
			phase = Phase.CANCELLED
			_phase_until_usec = now_usec + CANCELLED_USEC
			cancellations += 1
			events.append("cancel")
	if not reloading.is_empty() and reloading == selected and ready_at > tick:
		var key: String = "%s:%d" % [reloading, ready_at]
		if not _seen.has(key):
			_seen[key] = true
			var requested: bool = phase == Phase.PENDING
			adopted = _baseline and not requested
			phase = Phase.ACTIVE
			reason = ""
			weapon = reloading
			deadline = ready_at
			started_tick = tick
			_rounds_at_start = int(EquipmentState.magazine(state, reloading).get("rounds", 0))
			_accept_usec = now_usec
			if requested and _request_usec >= 0:
				last_request_to_accept_usec = maxi(0, now_usec - _request_usec)
			_request_usec = -1
			if not adopted:
				starts += 1
				events.append("start")
	_baseline = false
	return events

## Called when a cue was actually presented, to record accept-to-cue.
func presented(now_usec: int) -> void:
	if _accept_usec >= 0:
		last_accept_to_cue_usec = maxi(0, now_usec - _accept_usec)

## Expire short result lines and an unanswered request.
func advance(now_usec: int) -> void:
	match phase:
		Phase.PENDING:
			if now_usec >= _phase_until_usec:
				_request_usec = -1
				_show_unavailable("not_accepted", now_usec)
		Phase.COMPLETE, Phase.CANCELLED, Phase.UNAVAILABLE:
			if now_usec >= _phase_until_usec:
				phase = Phase.IDLE
				reason = ""

## Fraction of the accepted interval elapsed at a server tick, 0 to 1.
func progress(tick: int) -> float:
	if phase == Phase.COMPLETE:
		return 1.0
	if phase != Phase.ACTIVE or deadline <= started_tick:
		return 0.0
	return clampf(float(tick - started_tick) / float(deadline - started_tick), 0.0, 1.0)

## Translation key for the status line, or "" when nothing should show.
func status_key() -> String:
	match phase:
		Phase.PENDING:
			return STATUS_KEYS["pending"]
		Phase.ACTIVE:
			return STATUS_KEYS["active"]
		Phase.COMPLETE:
			return STATUS_KEYS["complete"]
		Phase.CANCELLED:
			return STATUS_KEYS["cancelled"]
		Phase.UNAVAILABLE:
			return str(STATUS_KEYS.get(reason, ""))
	return ""

func _show_unavailable(why: String, now_usec: int) -> void:
	# A repeated press refreshes the same line; it never stacks or sounds.
	if phase == Phase.ACTIVE:
		return
	phase = Phase.UNAVAILABLE
	reason = why
	_phase_until_usec = now_usec + UNAVAILABLE_USEC
	unavailable += 1
