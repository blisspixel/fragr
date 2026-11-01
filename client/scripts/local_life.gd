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
	_death_pose = _body
	if not _death_tick:
		_death_pool = _pool
	_death_tick = true
	weapon = ""
	_killer_at = Vector3.INF
	_killer_hp = -1
	_killer_armor = 0
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
	weapon = ""
	_taken.clear()
	_taken_names.clear()
	_body = Vector4(INF, INF, INF, INF)
	_death_pose = _body
	_pool = -1
	_death_pool = -1
	_death_tick = false
	_killer_at = Vector3.INF
	_killer_hp = -1
	_killer_armor = 0
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


## Death recap (#528): why this life ended, from server facts only. Hit
## events that named this fighter, the frag's weapon, and the snapshot rows of
## the killer and of this body at the death tick. Nothing here is inferred
## from a live pawn or a local trace.

## Shooters named on the damage line before the rest are counted.
const RECAP_SHOOTERS: int = 2
const MAX_RECAP_NAME: int = 32
## A wire HP or armour beyond this is refused, not shown.
const MAX_RECAP_POINTS: int = 1000
## Height difference that earns "above" or "below", metres.
const RECAP_HEIGHT: float = 2.5
## Eight bearings, clockwise from ahead, as translation keys.
const BEARINGS: Array[String] = ["HUD_RECAP_AHEAD", "HUD_RECAP_AHEAD_RIGHT", "HUD_RECAP_RIGHT", "HUD_RECAP_BEHIND_RIGHT",
	"HUD_RECAP_BEHIND", "HUD_RECAP_BEHIND_LEFT", "HUD_RECAP_LEFT", "HUD_RECAP_AHEAD_LEFT"]

## The frag's weapon wire id, empty when the server named none.
var weapon: String = ""
## Damage this life took, by shooter key (id, or name for an id-less fact).
var _taken: Dictionary[String, int] = {}
var _taken_names: Dictionary[String, String] = {}
## This body's last authoritative pose while alive: x, y, z and yaw.
var _body: Vector4 = Vector4(INF, INF, INF, INF)
var _death_pose: Vector4 = Vector4(INF, INF, INF, INF)
## Health plus armour in the last living snapshot, and what the death tick's
## hits still had to take; -1 when the snapshot did not say.
var _pool: int = -1
var _death_pool: int = -1
## The death tick's hits have begun: from here they share `_death_pool`.
var _death_tick: bool = false
## The killer's row at the death tick; INF and -1 when it was not in it.
var _killer_at: Vector3 = Vector3.INF
var _killer_hp: int = -1
var _killer_armor: int = 0


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _points(value: Variant) -> int:
	if not EquipmentState.integer(value, MAX_RECAP_POINTS):
		return -1
	return int(value)


static func _recap_name(value: Variant) -> String:
	if not value is String:
		return ""
	var clean: String = (value as String).strip_edges()
	return clean.left(MAX_RECAP_NAME)


## This body's snapshot row while it lives: where it stood and faced, and
## the health plus armour it had.
func observe_body(row: Dictionary) -> void:
	if phase != Phase.ALIVE:
		return
	var hp: int = _points(row.get("hp"))
	_pool = hp + maxi(_points(row.get("armor", 0)), 0) if hp >= 0 else -1
	for key: String in ["x", "y", "z", "yaw"]:
		if not _finite_number(row.get(key)):
			return
	_body = Vector4(float(row["x"]), float(row["y"]), float(row["z"]), float(row["yaw"]))


## A hit event that named this fighter as the target. Damage arriving after
## the frag in the same batch still belongs to the life that ended.
func record_hit(shooter_id: Variant, shooter_name: Variant, damage: Variant, hp_after: Variant = null) -> void:
	var amount: int = _points(damage)
	# The finishing hit can arrive before this client has seen the body go.
	if phase == Phase.ALIVE and _points(hp_after) == 0 and not _death_tick:
		_death_tick = true
		_death_pool = _pool
	# A tick's events follow its snapshot. While alive, that snapshot already
	# shows the hit and the hit was survived, so all of it landed. Once down,
	# the hits are the death tick's, and together they took at most the
	# health and armour the last living snapshot showed: overkill is not
	# damage taken.
	if (phase != Phase.ALIVE or _death_tick) and _death_pool >= 0:
		amount = mini(amount, _death_pool)
		_death_pool -= maxi(amount, 0)
	if amount <= 0:
		return
	var name_text: String = _recap_name(shooter_name)
	var key: String = shooter_id if shooter_id is String and not (shooter_id as String).is_empty() else name_text
	if key.is_empty():
		return
	_taken[key] = mini(_taken.get(key, 0) + amount, MAX_RECAP_POINTS * 10)
	if not name_text.is_empty():
		_taken_names[key] = name_text


## The frag's weapon and the killer's snapshot row at the death tick. A row
## that is missing or malformed leaves range and health unsaid.
func record_kill_facts(frag_weapon: Variant, killer_row: Variant) -> void:
	weapon = frag_weapon if frag_weapon is String and EquipmentState.WEAPONS.has(frag_weapon) else ""
	_killer_at = Vector3.INF
	_killer_hp = -1
	_killer_armor = 0
	if not killer_row is Dictionary or cause != "killer":
		return
	var row: Dictionary = killer_row
	for key: String in ["x", "y", "z"]:
		if not _finite_number(row.get(key)):
			return
	var hp: int = _points(row.get("hp"))
	if hp <= 0:
		return
	_killer_at = Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
	_killer_hp = hp
	_killer_armor = maxi(_points(row.get("armor", 0)), 0)


## Damage taken this life, all shooters together.
func damage_taken() -> int:
	var total: int = 0
	for amount: int in _taken.values():
		total += amount
	return total


## Where the killer stood from this body's last view: one of eight bearings
## clockwise from ahead (server yaw: forward is cos, sin on x, z), or -1.
func killer_bearing() -> int:
	if not _killer_at.is_finite() or not is_finite(_death_pose.w):
		return -1
	var dx: float = _killer_at.x - _death_pose.x
	var dz: float = _killer_at.z - _death_pose.z
	if dx * dx + dz * dz < 0.0001:
		return 0
	var relative: float = wrapf(atan2(dz, dx) - _death_pose.w, -PI, PI)
	return posmod(int(roundf(relative / (PI / 4.0))), 8)


## Metres from this body to its killer, or -1 when either is unknown.
func killer_distance() -> int:
	if not _killer_at.is_finite() or not is_finite(_death_pose.w):
		return -1
	return int(roundf(_killer_at.distance_to(Vector3(_death_pose.x, _death_pose.y, _death_pose.z))))


## Up to two recap lines for the death card: how and from where, with what
## the killer has left, then the damage this life took and from whom.
func recap_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if phase == Phase.ALIVE:
		return lines
	var how: PackedStringArray = PackedStringArray()
	if not weapon.is_empty():
		how.append(EquipmentState.display_name(weapon).to_upper())
	var metres: int = killer_distance()
	var bearing: int = killer_bearing()
	if cause == "killer" and metres >= 0 and bearing >= 0:
		var where: String = TranslationServer.translate("HUD_RECAP_RANGE").format({"metres": metres, "bearing": TranslationServer.translate(BEARINGS[bearing])})
		var rise: float = _killer_at.y - _death_pose.y
		if rise >= RECAP_HEIGHT:
			where += " " + TranslationServer.translate("HUD_RECAP_ABOVE")
		elif rise <= -RECAP_HEIGHT:
			where += " " + TranslationServer.translate("HUD_RECAP_BELOW")
		how.append(where)
	if cause == "killer" and _killer_hp > 0:
		var left: String = TranslationServer.translate("HUD_RECAP_KILLER_HP").format({"hp": _killer_hp})
		if _killer_armor > 0:
			left = TranslationServer.translate("HUD_RECAP_KILLER_HP_ARMOR").format({"hp": _killer_hp, "armor": _killer_armor})
		how.append(left)
	if not how.is_empty():
		lines.append(" // ".join(how))
	var total: int = damage_taken()
	if total > 0:
		var keys: Array[String] = []
		keys.assign(_taken.keys())
		keys.sort_custom(func(a: String, b: String) -> bool:
			return _taken[a] > _taken[b] or (_taken[a] == _taken[b] and a < b))
		var parts: PackedStringArray = PackedStringArray()
		for index: int in range(mini(keys.size(), RECAP_SHOOTERS)):
			var key: String = keys[index]
			var shown: String = _taken_names.get(key, "")
			if shown.is_empty():
				shown = TranslationServer.translate("HUD_DEATH_SOMEONE")
			parts.append("%s %d" % [shown, _taken[key]])
		var line: String = TranslationServer.translate("HUD_RECAP_TAKEN").format({"total": total, "from": ", ".join(parts)})
		if keys.size() > RECAP_SHOOTERS:
			line += " " + TranslationServer.translate("HUD_RECAP_MORE").format({"count": keys.size() - RECAP_SHOOTERS})
		lines.append(line)
	return lines
