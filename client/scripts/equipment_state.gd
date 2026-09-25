class_name EquipmentState
extends RefCounted

## Private server inventory. These limits validate presentation, never award ammo.
## One count per ammunition type and no magazines: a shot spends one unit.
## Wire and record order. The Shiv is appended so old record slots keep their meaning.
const WEAPONS: Array[String] = ["fists", "tack", "flechette", "scatter", "rail", "shiv"]
const POOLS: Dictionary = {"tack": "bullets", "flechette": "bullets", "scatter": "shells", "rail": "cells"}
const CAPACITIES: Dictionary = {"bullets": 200, "shells": 50, "cells": 50}
## Pool order on the wire, matching the server.
const POOL_ORDER: Array[String] = ["bullets", "shells", "cells"]
const DISPLAY_NAMES: Dictionary = {"fists": "Fists", "shiv": "Shiv", "tack": "Pistol", "flechette": "Rifle", "scatter": "Shotgun", "rail": "Railgun"}
const POOL_NAMES: Dictionary = {"bullets": "Bullets", "shells": "Shells", "cells": "Cells"}
## Rays in one shot. The shotgun's seven pellets still spend one shell.
const PELLETS: Dictionary = {"scatter": 7}
## Doom's ladder for the guns that exist: fists, pistol, shotgun, rifle, railgun.
## One number key per slot. Slot one also holds the Shiv, as Doom's holds the chainsaw.
const SLOTS: Array[String] = ["fists", "tack", "scatter", "flechette", "rail"]
## The wheel order: the Shiv sits beside the fists it shares a key with.
const CYCLE: Array[String] = ["fists", "shiv", "tack", "scatter", "flechette", "rail"]
const MELEE: Array[String] = ["fists", "shiv"]
const ARCADE: Array[String] = ["scatter", "flechette", "rail"]
const MAX_EXACT_INTEGER: int = 9007199254740991

static func display_name(weapon: String) -> String:
	return str(DISPLAY_NAMES.get(weapon.to_lower(), weapon))

static func pool_name(pool: String) -> String:
	return str(POOL_NAMES.get(pool.to_lower(), pool))

static func integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= maximum and float(value) == floorf(float(value))

static func pellets(weapon: String) -> int:
	return int(PELLETS.get(weapon.to_lower(), 1))

static func validation_error(data: Dictionary, owner: Variant, previous: Dictionary = {}) -> String:
	const INVALID: String = "The server sent invalid equipment. Connection closed."
	if not owner is String or data.get("player_id") != owner:
		return INVALID
	if not integer(data.get("tick"), MAX_EXACT_INTEGER) or not integer(data.get("dry_fire_count"), MAX_EXACT_INTEGER):
		return INVALID
	if not previous.is_empty() and int(data["tick"]) < int(previous["tick"]):
		return INVALID
	# The magazine era sent reserves and reload; that shape is refused whole.
	if data.has("reserves") or data.has("reload"):
		return INVALID
	if not data.get("selected") is String or not data.get("weapons") is Array \
		or not data.get("ammo") is Array or not data.get("personal_claims") is Array:
		return INVALID
	var weapons: Array = data["weapons"]
	var ammo: Array = data["ammo"]
	var claims: Array = data["personal_claims"]
	if weapons.is_empty() or weapons.size() > WEAPONS.size() or ammo.size() != CAPACITIES.size() or claims.size() > 128:
		return INVALID
	var owned: Dictionary = {}
	for weapon: Variant in weapons:
		if not weapon is String or weapon not in WEAPONS or owned.has(weapon):
			return INVALID
		owned[weapon] = true
	if not owned.has("fists") or not owned.has(data["selected"]):
		return INVALID
	var pools: Dictionary = {}
	for entry: Variant in ammo:
		if not entry is Dictionary or entry.size() != 2 or not entry.get("pool") is String:
			return INVALID
		var pool: String = entry["pool"]
		if not CAPACITIES.has(pool) or pools.has(pool) or not integer(entry.get("rounds"), CAPACITIES[pool]):
			return INVALID
		pools[pool] = int(entry["rounds"])
	var claimed: Dictionary = {}
	for claim: Variant in claims:
		if not claim is String or claim.is_empty() or claim.length() > 64 or claimed.has(claim):
			return INVALID
		for character: String in claim:
			if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
				return INVALID
		claimed[claim] = true
	return ""

## Shots the weapon can fire now, or -1 when it needs no ammunition.
static func shots(state: Dictionary, weapon: String) -> int:
	var pool: String = str(POOLS.get(weapon, ""))
	if pool.is_empty():
		return -1
	return ammo(state, pool)

static func ammo(state: Dictionary, pool: String) -> int:
	for entry: Dictionary in state.get("ammo", []):
		if entry["pool"] == pool:
			return int(entry["rounds"])
	return 0

static func carried_names(state: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for weapon: Variant in state.get("weapons", []):
		names.append(str(weapon).to_lower())
	return names

static func owned_in_order(carried: Array) -> Array[String]:
	var have: Dictionary = {}
	for weapon in carried:
		have[str(weapon).to_lower()] = true
	var order: Array[String] = []
	for weapon: String in CYCLE:
		if have.has(weapon):
			order.append(weapon)
	return order

static func cycle_owned(carried: Array, current: String, step: int) -> String:
	var order: Array[String] = owned_in_order(carried)
	if order.is_empty():
		return current.to_lower()
	var index: int = order.find(current.to_lower())
	if index < 0:
		index = -1 if step > 0 else 0
	return order[posmod(index + step, order.size())]

static func cycle(state: Dictionary, current: String, step: int) -> String:
	return cycle_owned(carried_names(state), current, step)

## Slot one draws the Shiv when carried, and a second press while holding it
## goes back to fists. Every other slot names one gun.
static func slot_if_owned(carried: Array, slot: int, current: String = "") -> String:
	if slot < 1 or slot > SLOTS.size():
		return ""
	var owned: Array[String] = owned_in_order(carried)
	var weapon: String = SLOTS[slot - 1]
	if slot == 1 and owned.has("shiv") and current.to_lower() != "shiv":
		return "shiv"
	if not owned.has(weapon):
		return ""
	return weapon
