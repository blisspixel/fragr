class_name L07Assets
extends RefCounted

## Level 7 presentation sources in one table: the Sniper Rifle's sounds and
## scope settings, the Ranged Sweeper and its tell. The Sniper Rifle's
## first-person frames, pickup and scope plate live in `WeaponArt` with every
## other gun (art pass, 2026-10-02). The two sounds below are clean placeholders
## until the sound pass's delivered cues replace them here.

## A slower, lower copy of the Railgun report.
const SNIPER_FIRE_SOUND: String = "res://assets/audio/sniper/fire_placeholder.wav"
const SNIPER_HIT_SOUND: String = "res://assets/audio/hit_rail.wav"
## The marksman atlas in the shared enemy layout.
const RANGED_SWEEPER_ATLAS: String = "res://assets/characters/union/ranged_sweeper.png"
## A short original glint ting, played when the server starts a windup.
const RANGED_SWEEPER_TELL_SOUND: String = "res://assets/audio/ranged_sweeper/glint_placeholder.wav"

## Scoped view: the field of view shrinks to this share of the player's setting.
const SCOPE_FOV_FACTOR: float = 0.3
## Seconds to settle into or out of the scope.
const SCOPE_SETTLE_SECONDS: float = 0.12
