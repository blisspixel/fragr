class_name LocalLife
extends RefCounted
## The joined player's arcade life, made explicit (#441):
## ALIVE -> DOWN (death camera) -> AWAITING (server countdown known) -> ALIVE.
## OUT is a death with no respawn coming (out of lives).
##
## Presentation only. The server decides when the body returns; this class
## never requests, advances or admits a respawn. The countdown is the server's
## `Ack.respawn_ticks`, re-anchored on every Ack, so a client clock can only
## change what is shown, never when the fighter is back.

enum Phase { ALIVE, DOWN, AWAITING, OUT }

const TICK_USEC: int = 50000
## Largest countdown accepted from the wire: ten minutes at 20 Hz.
const MAX_RESPAWN_TICKS: int = 20 * 600

var phase: Phase = Phase.ALIVE
var killer_id: String = ""
var killer_name: String = ""
## "killer", "self" or "unknown": what the frag fact said about this death.
var cause: String = "unknown"
## Newest Ack tick seen while down, so an older Ack cannot rewind the count.
var _ack_tick: int = -1
## Snapshot tick the body went down on; a later Ack without a countdown is OUT.
var down_tick: int = -1
var _deadline_usec: int = -1


func alive() -> bool:
	return phase == Phase.ALIVE


## The frag fact for this player. It can arrive before or after the snapshot
## that removes the body, so it only adds who did it to the current death.
func record_frag(victim_id: String, by_id: String, by_name: String, tick: int) -> void:
	if phase == Phase.ALIVE:
		_go_down(tick)
	killer_id = by_id
	killer_name = by_name.strip_edges()
	if not by_id.is_empty() and by_id == victim_id:
		cause = "self"
		killer_id = ""
	elif by_id.is_empty() and killer_name.is_empty():
		cause = "unknown"
	else:
		cause = "killer"


## The authoritative body left the snapshot (an arcade death).
func body_gone(tick: int) -> void:
	if phase == Phase.ALIVE:
		_go_down(tick)


func _go_down(tick: int) -> void:
	phase = Phase.DOWN
	killer_id = ""
	killer_name = ""
	cause = "unknown"
	down_tick = tick
	_ack_tick = -1
	_deadline_usec = -1


## Every Ack while down re-anchors the countdown on the server's number.
func observe_ack(data: Dictionary, now_usec: int) -> void:
	if phase == Phase.ALIVE:
		return
	var tick_value: Variant = data.get("tick")
	if not (tick_value is int or tick_value is float):
		return
	var tick: int = int(tick_value)
	if tick <= _ack_tick:
		return
	_ack_tick = tick
	var raw: Variant = data.get("respawn_ticks")
	if (raw is int or raw is float) and is_finite(float(raw)) and float(raw) >= 0.0 \
			and float(raw) <= float(MAX_RESPAWN_TICKS) and float(raw) == floorf(float(raw)):
		phase = Phase.AWAITING
		_deadline_usec = now_usec + int(raw) * TICK_USEC
	elif raw == null and down_tick >= 0 and tick > down_tick:
		# Down, past the death tick, and the server names no respawn.
		phase = Phase.OUT
		_deadline_usec = -1


## The body is back in the snapshot: a new life begins.
func respawned() -> void:
	reset()


func reset() -> void:
	phase = Phase.ALIVE
	killer_id = ""
	killer_name = ""
	cause = "unknown"
	down_tick = -1
	_ack_tick = -1
	_deadline_usec = -1


## Whole seconds left as shown; -1 while the server has not said.
func seconds_left(now_usec: int) -> int:
	if phase != Phase.AWAITING or _deadline_usec < 0:
		return -1
	var remaining: int = maxi(0, _deadline_usec - now_usec)
	return int(ceil(float(remaining) / 1000000.0))


## The camera chases this fighter while down; empty holds the last view.
func chase_id() -> String:
	return killer_id if cause == "killer" and phase != Phase.ALIVE else ""


## Three lines for the death card: what happened, what you see, and when
## you are back. `watching` is the name the camera is actually following.
## A fourth names the found weapons `lost` with this life, when there were any.
## `seat` says the view is a teammate's seat, which F moves along.
func card_lines(now_usec: int, watching: String, lost: Array[String] = [], seat: bool = false) -> PackedStringArray:
	if phase == Phase.ALIVE:
		return PackedStringArray()
	var headline: String
	match cause:
		"self":
			headline = TranslationServer.translate("HUD_DEATH_SELF")
		"killer":
			var shown: String = killer_name if not killer_name.is_empty() else TranslationServer.translate("HUD_DEATH_SOMEONE")
			headline = TranslationServer.translate("HUD_DEATH_BY").format({"killer": shown})
		_:
			headline = TranslationServer.translate("HUD_DEATH_DOWN")
	var view: String = TranslationServer.translate("HUD_DEATH_HOLDING")
	if not watching.is_empty() and seat:
		view = InputGlyphs.plain(TranslationServer.translate("HUD_DEATH_WATCHING_MATE")).format({"name": watching})
	elif not watching.is_empty():
		view = TranslationServer.translate("HUD_DEATH_WATCHING").format({"name": watching})
	var timing: String
	if phase == Phase.OUT:
		timing = TranslationServer.translate("HUD_DEATH_OUT")
	else:
		var seconds: int = seconds_left(now_usec)
		if seconds > 0:
			timing = TranslationServer.translate("HUD_DEATH_RESPAWN_IN").format({"seconds": seconds})
		else:
			timing = TranslationServer.translate("HUD_DEATH_RESPAWNING")
	var lines: PackedStringArray = PackedStringArray([headline, view, timing])
	if not lost.is_empty():
		lines.append(TranslationServer.translate("HUD_DEATH_LOST").format({"weapons": MatchRules.weapon_list(lost)}))
	return lines
