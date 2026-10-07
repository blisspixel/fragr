class_name LocalFireFeedback
extends RefCounted

## Presentation receipts only. The server owns ammunition, traces and damage.
## Cadence mirrors WeaponType::cooldown_ticks; checked by the focused harness.
const COOLDOWN_TICKS: Dictionary = {
	"fists": 8, "shiv": 6, "tack": 5, "flechette": 4,
	"rail": 20, "sniper": 32, "repeater": 2, "scatter": 12,
}
const TICK_USEC: int = 50000
const WARMUP_USEC: int = 6 * TICK_USEC
const MAX_PENDING: int = 8
const MAX_AHEAD_USEC: int = 500000
const REJECT_GRACE_TICKS: int = 2

var pending: Array[Dictionary] = []
var predicted_count: int = 0
var confirmed_count: int = 0
var rejected_count: int = 0
var next_fire_usec: int = 0
var _held_since: int = -1
var _held_weapon: String = ""
var _latest_seq: int = -1
var _wanted_weapon: String = ""
var _switch_seq: int = -1
var _switch_ack_tick: int = -1

func reset() -> void:
	pending.clear()
	next_fire_usec = 0
	_held_since = -1
	_held_weapon = ""
	_latest_seq = -1
	_wanted_weapon = ""
	_switch_seq = -1
	_switch_ack_tick = -1

## Called only after a successful send. A withheld or failed action cannot
## make a gunshot. Unknown inventory waits for the authoritative path.
func sent(action: Dictionary, equipment: Dictionary, weapon: String, tick: int, now_usec: int, allowed: bool) -> bool:
	observe_equipment(equipment)
	var swap: Variant = action.get("weapon_swap")
	if swap is String and swap != "" and swap != weapon:
		_wanted_weapon = swap
		_switch_seq = int(action.get("seq", -1))
		_switch_ack_tick = -1
	var trigger: bool = allowed and bool(action.get("fire", false)) \
		and not bool(action.get("reload", false)) \
		and not bool(action.get("throw_grenade", false)) \
		and not bool(action.get("place_mine", false))
	if not trigger or weapon != _held_weapon:
		_held_since = -1
	_held_weapon = weapon
	if not trigger or not _wanted_weapon.is_empty() or not COOLDOWN_TICKS.has(weapon):
		return false
	if equipment.is_empty() or not EquipmentState.carried_names(equipment).has(weapon):
		return false
	for magazine: Dictionary in equipment.get("loaded", []):
		if magazine.get("weapon") == weapon and magazine.has("ready_at"):
			_held_since = -1
			return false
	var available: int = EquipmentState.shots(equipment, weapon)
	if available >= 0:
		for receipt: Dictionary in pending:
			var same_supply: bool = receipt["weapon"] == weapon if equipment.has("loaded") \
				else EquipmentState.POOLS.get(receipt["weapon"], "") == EquipmentState.POOLS.get(weapon, "")
			if same_supply:
				available -= 1
		if available <= 0:
			_held_since = -1
			return false
	if _held_since < 0:
		_held_since = now_usec
	if weapon == "repeater" and now_usec - _held_since < WARMUP_USEC:
		return false
	if now_usec < next_fire_usec or pending.size() >= MAX_PENDING:
		return false
	for receipt: Dictionary in pending:
		if int(receipt["confirmed_tick"]) < 0 and now_usec - int(receipt["sent_usec"]) >= MAX_AHEAD_USEC:
			return false
	_latest_seq = int(action["seq"])
	pending.append({"seq": _latest_seq, "weapon": weapon, "after_tick": tick,
		"sent_usec": now_usec, "ack_tick": -1, "confirmed_tick": -1})
	next_fire_usec = now_usec + int(COOLDOWN_TICKS[weapon]) * TICK_USEC
	predicted_count += 1
	return true

## A server result consumes one cue, including a miss or shielded impact.
## Pellet folding happens in GameManager before this method is called.
func confirm(weapon: String, tick: int, now_usec: int) -> bool:
	for receipt: Dictionary in pending:
		if receipt["weapon"] == weapon and int(receipt["confirmed_tick"]) < 0 and tick > int(receipt["after_tick"]):
			receipt["confirmed_tick"] = tick
			confirmed_count += 1
			return true
	# An unpredicted shot still owns the shared cooldown, even after a switch.
	if COOLDOWN_TICKS.has(weapon):
		next_fire_usec = maxi(next_fire_usec, now_usec + int(COOLDOWN_TICKS[weapon]) * TICK_USEC)
	_latest_seq = -1
	return false

## Confirmed rounds remain reserved until the inventory includes that shot.
func observe_equipment(equipment: Dictionary) -> void:
	var tick: int = int(equipment.get("tick", -1))
	for index: int in range(pending.size() - 1, -1, -1):
		var confirmed: int = int(pending[index]["confirmed_tick"])
		if confirmed >= 0 and confirmed <= tick:
			pending.remove_at(index)
	if equipment.get("selected") == _wanted_weapon:
		_wanted_weapon = ""
		_switch_seq = -1
		_switch_ack_tick = -1

func acknowledge(seq: int, tick: int) -> void:
	for receipt: Dictionary in pending:
		if int(receipt["ack_tick"]) < 0 and _seq_reached(seq, int(receipt["seq"])):
			receipt["ack_tick"] = tick
	if _switch_seq >= 0 and _switch_ack_tick < 0 and _seq_reached(seq, _switch_seq):
		_switch_ack_tick = tick

## Call after presenting the snapshot's shots. A held trigger can reach the
## next server tick while local cadence is up to one tick ahead, so allow two
## ticks before retiring an applied action with no corresponding shot.
func reconcile(tick: int) -> bool:
	var cancel_latest: bool = false
	for index: int in range(pending.size() - 1, -1, -1):
		var receipt: Dictionary = pending[index]
		var ack_tick: int = int(receipt["ack_tick"])
		if int(receipt["confirmed_tick"]) < 0 and ack_tick >= 0 and tick >= ack_tick + REJECT_GRACE_TICKS:
			cancel_latest = cancel_latest or int(receipt["seq"]) == _latest_seq
			pending.remove_at(index)
			rejected_count += 1
	if _switch_ack_tick >= 0 and tick >= _switch_ack_tick + REJECT_GRACE_TICKS:
		_wanted_weapon = ""
		_switch_seq = -1
		_switch_ack_tick = -1
	return cancel_latest

static func _seq_reached(received: int, sent_seq: int) -> bool:
	# Input sequences wrap at u32::MAX. Outstanding receipts cover under a second.
	return received >= 0 and sent_seq >= 0 and ((received - sent_seq) & 0xffffffff) < 0x80000000
