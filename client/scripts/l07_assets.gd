class_name L07Assets
extends RefCounted

## Level 7 presentation sources in one table: the Sniper Rifle's sounds and
## scope settings, the Ranged Sweeper and its tell. The Sniper Rifle's
## first-person frames, pickup and scope plate live in `WeaponArt` with every
## other gun (art pass, 2026-10-02). The sounds are the sound pass cues
## (2026-10-02); provenance is in `assets/audio/sound-pass-20261002.json`.

## A dry supersonic crack with no electric layer, unlike the Railgun.
const SNIPER_FIRE_SOUND: String = "res://assets/audio/fire_sniper.wav"
const SNIPER_HIT_SOUND: String = "res://assets/audio/hit_rail.wav"
## The marksman atlas in the shared enemy layout.
const RANGED_SWEEPER_ATLAS: String = "res://assets/characters/union/ranged_sweeper.png"
## A glint, then a held targeting tone, from the start of the server windup
## until the shot or a cancelled windup cuts it off.
const RANGED_SWEEPER_TELL_SOUND: String = "res://assets/audio/ranged_sweeper/tell.wav"
## The marksman's own machine-mounted shot, distinct from the player's rifle.
const RANGED_SWEEPER_FIRE_SOUND: String = "res://assets/audio/ranged_sweeper/fire.wav"
## Raising and lowering the Sniper Rifle scope.
const SCOPE_IN_SOUND: String = "res://assets/audio/sniper/scope_in.wav"
const SCOPE_OUT_SOUND: String = "res://assets/audio/sniper/scope_out.wav"
## The town's curfew chime, for the level to play every thirty seconds.
const CURFEW_CHIME_SOUND: String = "res://assets/audio/l07/curfew_chime.wav"

## Scoped view: the field of view shrinks to this share of the player's setting.
const SCOPE_FOV_FACTOR: float = 0.3
## Seconds to settle into or out of the scope.
const SCOPE_SETTLE_SECONDS: float = 0.12
