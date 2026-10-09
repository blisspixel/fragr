class_name WeaponArt
extends RefCounted

## Every picture of a weapon or supply in one table, keyed by the wire names
## the server sends ("Tack", "Flechette", "Scatter", "Rail", "Fists", "Shiv").
## First-person frames, world pickups, the profile a fighter holds and the HUD
## vitals icons come from the 2026-10-02 art pass; prompts, requests and hashes
## are in `res://assets/art-pass-20261002-manifest.json`, and for the redrawn
## Rifle in `res://assets/art-pass-2-20261002-manifest.json`. All are palette
## sprites drawn with nearest sampling.
## The Pistol's first-person pictures follow the Shotgun's drawn sprite style.
## Its separate local model still supplies the world pickup profile. The new
## sprite source and selection hashes are in pistol-sprite-20261005/selection.json.
##
## "Sniper" is the existing Level 7 Sniper Rifle. Its drawn held/fire pair
## matches the Shotgun glove family; the separate walnut/charcoal source still
## supplies its pickup. Finite Cells, scope and server shot timing are unchanged.

## First-person pose at rest. Fists and the Shiv keep their own animation.
const IDLE: Dictionary[String, Texture2D] = {
	"Fists": preload("res://assets/weapons/viewmodels/fists_idle.png"),
	"Tack": preload("res://assets/weapons/pistol-sprite-20261005/pistol_idle.png"),
	"Flechette": preload("res://assets/weapons/viewmodels/rifle_idle.png"),
	"Scatter": preload("res://assets/weapons/viewmodels/shotgun_idle.png"),
	"Rail": preload("res://assets/weapons/viewmodels/railgun_idle.png"),
	"Sniper": preload("res://assets/weapons/sniper-sprite-20261005/sniper_idle.png"),
	"Shiv": preload("res://assets/weapons/viewmodels/shiv_idle.png"),
	"Arc": preload("res://assets/weapons/arc/arc_idle.png"),
}

## The frame at the instant of the shot, its muzzle flash painted in. Each was
## drawn from its own idle, so the two register on the same full canvas.
const FIRE: Dictionary[String, Texture2D] = {
	"Tack": preload("res://assets/weapons/pistol-sprite-20261005/pistol_fire.png"),
	"Flechette": preload("res://assets/weapons/viewmodels/rifle_fire.png"),
	"Scatter": preload("res://assets/weapons/viewmodels/shotgun_fire.png"),
	"Rail": preload("res://assets/weapons/viewmodels/railgun_fire.png"),
	"Sniper": preload("res://assets/weapons/sniper-sprite-20261005/sniper_fire.png"),
	"Arc": preload("res://assets/weapons/arc/arc_fire.png"),
}

## A follow-through after the shot: the Shotgun's pump stroke.
const CYCLE: Dictionary[String, Texture2D] = {
	"Scatter": preload("res://assets/weapons/viewmodels/shotgun_pump.png"),
	"Arc": preload("res://assets/weapons/arc/arc_settle.png"),
}

## The Arc's left hand works its capacitor reset collar during the actual
## magazine reload. Its receiver and wrists share the held pose canvas.
const ARC_RELOAD: Texture2D = preload("res://assets/weapons/arc/arc_reload.png")

## Seconds the fire frame stays up, then when the cycle frame starts and ends.
const FIRE_SECONDS: float = 0.08
const CYCLE_FROM: float = 0.18
const CYCLE_UNTIL: float = 0.44

## The off hand that throws a grenade while the gun dips out of the way.
const GRENADE_READY: Texture2D = preload("res://assets/weapons/viewmodels/grenade_ready.png")
const GRENADE_THROW: Texture2D = preload("res://assets/weapons/viewmodels/grenade_throw.png")
const THROW_READY_SECONDS: float = 0.12
const THROW_SECONDS: float = 0.34

## Level 8's Proximity Mine in the off hand, held and then tossed, on the
## grenade hand's canvas so the same layout shows it.
const MINE_READY: Texture2D = preload("res://assets/weapons/viewmodels/mine_ready.png")
const MINE_PLACE: Texture2D = preload("res://assets/weapons/viewmodels/mine_place.png")

## A placed mine seen face-on, for a quad laid on the surface it stuck to. The
## states share one canvas and differ only at the lamp, so a swap never moves
## the device.
const MINE_DEVICE: Dictionary[String, Texture2D] = {
	"dark": preload("res://assets/weapons/mine/mine_dark.png"),
	"arming": preload("res://assets/weapons/mine/mine_arming.png"),
	"live": preload("res://assets/weapons/mine/mine_live.png"),
}
## World width of the face-on device.
const MINE_DEVICE_METRES: float = 0.34

## Side profiles: the world pickup and the gun a fighter holds.
const PROFILE: Dictionary[String, Texture2D] = {
	"Tack": preload("res://assets/weapons/pistol-source-20261004/pistol.png"),
	"Flechette": preload("res://assets/weapons/pickups/rifle.png"),
	"Scatter": preload("res://assets/weapons/pickups/shotgun.png"),
	"Rail": preload("res://assets/weapons/pickups/railgun.png"),
	"Sniper": preload("res://assets/weapons/sniper-source-20261004/sniper.png"),
	"Shiv": preload("res://assets/weapons/48/shiv.png"),
	"Arc": preload("res://assets/weapons/arc/arc_profile.png"),
}

## Supplies by pickup kind, and ammunition by pool.
const SUPPLY: Dictionary[String, Texture2D] = {
	"health": preload("res://assets/pickups/medkit.png"),
	"armor": preload("res://assets/pickups/armor.png"),
	"grenade": preload("res://assets/pickups/grenades.png"),
	"bullets": preload("res://assets/pickups/bullets.png"),
	"shells": preload("res://assets/pickups/shells.png"),
	"cells": preload("res://assets/pickups/cells.png"),
	"proximity_mine": preload("res://assets/pickups/proximity_mine.png"),
}

const HUD_HEALTH: Texture2D = preload("res://assets/hud/health.png")
const HUD_ARMOR: Texture2D = preload("res://assets/hud/armor.png")

## The Sniper Rifle's scope: a square plate with a transparent aperture, drawn
## centred at the window height with ink filling the remaining width.
const SCOPE_OVERLAY: Texture2D = preload("res://assets/weapons/sniper/scope_overlay.png")

## World size of one pickup texel. Pickups share one density so a pistol is
## visibly smaller than a railgun and a medkit reads at room distance.
const PICKUP_TEXEL_METRES: float = 1.0 / 72.0

## The texture for a pickup, or null when the kind has no art yet.
static func pickup_texture(kind: String, weapon: String, pool: String) -> Texture2D:
	match kind:
		"weapon", "golden_rail":
			return PROFILE.get(weapon)
		"ammo":
			return SUPPLY.get(pool.to_lower())
		_:
			return SUPPLY.get(kind)

## Which first-person frame a gun shows `since` seconds after its last shot.
static func frame_after_shot(weapon: String, since: float) -> Texture2D:
	if weapon == "Arc":
		if since >= 0.0 and since < 0.055:
			return FIRE[weapon]
		if since >= 0.055 and since < 0.14:
			return CYCLE[weapon]
		return IDLE[weapon]
	if since >= 0.0 and since < FIRE_SECONDS and FIRE.has(weapon):
		return FIRE[weapon]
	if since >= CYCLE_FROM and since < CYCLE_UNTIL and CYCLE.has(weapon):
		return CYCLE[weapon]
	return IDLE.get(weapon)

## Only an authoritative unfinished Arc magazine reload selects this pose.
## A local R press, another gun's reload, or an expired receipt cannot do so.
static func reload_frame(weapon: String, state: Dictionary, tick: int) -> Texture2D:
	if weapon != "Arc" or state.get("selected", "") != "arc":
		return null
	for magazine: Dictionary in state.get("loaded", []):
		if magazine.get("weapon", "") == "arc" and int(magazine.get("ready_at", tick)) > tick:
			return ARC_RELOAD
	return null

## The face-on picture of a placed mine for a wire phase and whether its lamp
## is lit on this server tick: a steady amber lamp while arming, red when a
## live or tripped mine's blink is on, dark in flight and between blinks.
static func mine_device(phase: String, lit: bool) -> Texture2D:
	if phase == "arming":
		return MINE_DEVICE["arming"]
	if lit and phase in ["armed", "tripped"]:
		return MINE_DEVICE["live"]
	return MINE_DEVICE["dark"]
