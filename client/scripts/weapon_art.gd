class_name WeaponArt
extends RefCounted

## Every picture of a weapon or supply in one table, keyed by the wire names
## the server sends ("Tack", "Flechette", "Scatter", "Rail", "Fists", "Shiv").
## All are palette sprites drawn with nearest sampling.
##
## The modelled guns (`BAKED`) come from one source each, `gun_model.gd`,
## posed with the player's gloved hands and baked by `tools/bake_viewmodels.gd`
## into `res://assets/weapons/<gun>/`: rest, three draw frames, the shot,
## two recovery frames, the reload, the world/held profile and the kill icon,
## so every view shows the same physical gun. The other first-person pictures
## are drawn sprites from the 2026-10-02 art pass (prompts, requests and
## hashes in `res://assets/art-pass-20261002-manifest.json`, the redrawn
## Rifle in `res://assets/art-pass-2-20261002-manifest.json`).
##
## "Sniper" is the existing Level 7 Sniper Rifle. Its drawn held/fire pair
## matches the drawn glove family; the separate walnut/charcoal source still
## supplies its pickup. Finite Cells, scope and server shot timing are unchanged.

## First-person frames of each modelled gun beyond its rest and shot: the raise
## from below (lowest first), the recovery after a shot, and the reload from
## the accepted request to the seated magazine. Every frame shares one canvas.
const BAKED: Dictionary[String, Dictionary] = {
	"Tack": {
		"draw": [preload("res://assets/weapons/tack/draw_0.png"), preload("res://assets/weapons/tack/draw_1.png"), preload("res://assets/weapons/tack/draw_2.png")],
		"recover": [preload("res://assets/weapons/tack/recover_0.png"), preload("res://assets/weapons/tack/recover_1.png")],
		"reload": [preload("res://assets/weapons/tack/reload_0.png"), preload("res://assets/weapons/tack/reload_1.png"), preload("res://assets/weapons/tack/reload_2.png"),
			preload("res://assets/weapons/tack/reload_3.png"), preload("res://assets/weapons/tack/reload_4.png"), preload("res://assets/weapons/tack/reload_5.png"),
			preload("res://assets/weapons/tack/reload_6.png")],
	},
	"Scatter": {
		"draw": [preload("res://assets/weapons/scatter/draw_0.png"), preload("res://assets/weapons/scatter/draw_1.png"), preload("res://assets/weapons/scatter/draw_2.png")],
		"recover": [preload("res://assets/weapons/scatter/recover_0.png"), preload("res://assets/weapons/scatter/recover_1.png")],
		"reload": [preload("res://assets/weapons/scatter/reload_0.png"), preload("res://assets/weapons/scatter/reload_1.png"), preload("res://assets/weapons/scatter/reload_2.png"),
			preload("res://assets/weapons/scatter/reload_3.png"), preload("res://assets/weapons/scatter/reload_4.png"), preload("res://assets/weapons/scatter/reload_5.png")],
	},
	"Rail": {
		"draw": [preload("res://assets/weapons/rail/draw_0.png"), preload("res://assets/weapons/rail/draw_1.png"), preload("res://assets/weapons/rail/draw_2.png")],
		"recover": [preload("res://assets/weapons/rail/recover_0.png"), preload("res://assets/weapons/rail/recover_1.png")],
		"reload": [preload("res://assets/weapons/rail/reload_0.png"), preload("res://assets/weapons/rail/reload_1.png"), preload("res://assets/weapons/rail/reload_2.png"),
			preload("res://assets/weapons/rail/reload_3.png"), preload("res://assets/weapons/rail/reload_4.png"), preload("res://assets/weapons/rail/reload_5.png"),
			preload("res://assets/weapons/rail/reload_6.png")],
	},
}

## The drawn Rifle keeps its rest and shot; its recovery (a smoke wisp and the
## spent case) is derived from that rest by `tools/bake_flechette_frames.gd`.
const RECOVER: Dictionary[String, Array] = {
	"Flechette": [preload("res://assets/weapons/flechette/recover_0.png"), preload("res://assets/weapons/flechette/recover_1.png")],
}

## Seconds after a shot when a gun leaves its fire frame, then each recovery
## frame. All end inside the gun's server cooldown (Tack 0.25 s, Flechette
## 0.20 s, Scatter 0.60 s, Rail 1.00 s): the Rail's coils sit dark, then
## recharge.
const SHOT_FRAMES: Dictionary[String, Array] = {
	"Tack": [0.05, 0.10, 0.16],
	"Flechette": [0.06, 0.11, 0.17],
	"Scatter": [0.07, 0.16, 0.28],
	"Rail": [0.08, 0.30, 0.60],
}

## The frames a gun recovers through after its shot, or none.
static func recover_frames(weapon: String) -> Array:
	if BAKED.has(weapon):
		return BAKED[weapon]["recover"]
	return RECOVER.get(weapon, [])

## First-person pose at rest. Fists and the Shiv keep their own animation.
const IDLE: Dictionary[String, Texture2D] = {
	"Fists": preload("res://assets/weapons/viewmodels/fists_idle.png"),
	"Tack": preload("res://assets/weapons/tack/idle.png"),
	"Flechette": preload("res://assets/weapons/viewmodels/rifle_idle.png"),
	"Scatter": preload("res://assets/weapons/scatter/idle.png"),
	"Rail": preload("res://assets/weapons/rail/idle.png"),
	"Sniper": preload("res://assets/weapons/sniper-sprite-20261005/sniper_idle.png"),
	"Shiv": preload("res://assets/weapons/viewmodels/shiv_idle.png"),
	"Arc": preload("res://assets/weapons/arc/arc_idle.png"),
	"Rocket": preload("res://assets/weapons/viewmodels/rocket_idle.png"),
	"Article Blade": preload("res://assets/weapons/viewmodels/article_blade_idle.png"),
	"ArticleBlade": preload("res://assets/weapons/viewmodels/article_blade_idle.png"),
}

## The frame at the instant of the shot, its muzzle flash painted in. Each was
## drawn from its own idle, so the two register on the same full canvas.
const FIRE: Dictionary[String, Texture2D] = {
	"Tack": preload("res://assets/weapons/tack/fire.png"),
	"Flechette": preload("res://assets/weapons/viewmodels/rifle_fire.png"),
	"Scatter": preload("res://assets/weapons/scatter/fire.png"),
	"Rail": preload("res://assets/weapons/rail/fire.png"),
	"Sniper": preload("res://assets/weapons/sniper-sprite-20261005/sniper_fire.png"),
	"Arc": preload("res://assets/weapons/arc/arc_fire.png"),
	"Rocket": preload("res://assets/weapons/viewmodels/rocket_fire.png"),
	"Article Blade": preload("res://assets/weapons/viewmodels/article_blade_swing.png"),
	"ArticleBlade": preload("res://assets/weapons/viewmodels/article_blade_swing.png"),
}

## A follow-through after the shot: the Arc settling its contacts.
const CYCLE: Dictionary[String, Texture2D] = {
	"Arc": preload("res://assets/weapons/arc/arc_settle.png"),
}

## The Arc's left hand works its capacitor reset collar during the actual
## magazine reload. Its receiver and wrists share the held pose canvas.
const ARC_RELOAD: Texture2D = preload("res://assets/weapons/arc/arc_reload.png")

## How far each held gun drops, as a fraction of its frame height, at the
## bottom of an accepted reload. The Rocket keeps its original tube drop. The
## Arc's drawn capacitor reset frame is its reload, so it does not also dip.
## Every other magazine gun lowers about a third and comes back up. The
## Repeater has no first-person frame yet; its HUD line is its whole signal.
## A modelled gun's reload frames are its reload, so it does not dip either.
const RELOAD_DIP: Dictionary[String, float] = {
	"Tack": 0.0, "Flechette": 0.32, "Repeater": 0.32, "Scatter": 0.0,
	"Rail": 0.0, "Sniper": 0.32, "Arc": 0.0, "Rocket": 0.55,
}

static func reload_dip(weapon: String) -> float:
	return float(RELOAD_DIP.get(weapon, 0.0))

## A held gun leaves the aim line while its accepted reload is pending.
## The received deadline determines the pose, never a key press or a guessed
## weapon duration. This also fits future drawn held art on the same canvas.
## `enabled` is off under reduced motion; the HUD reload line still shows.
class ReloadMotion extends RefCounted:
	var depth: float = 0.0
	## How far through the accepted reload, 0 to 1; negative with none pending.
	var progress: float = -1.0
	var _deadline: int = -1
	var _started: int = -1
	var _muted: bool = false

	func clear() -> void:
		depth = 0.0
		progress = -1.0
		_deadline = -1
		_started = -1
		_muted = false

	func update(weapon: String, state: Dictionary, tick: int, delta: float, enabled: bool) -> void:
		var deadline: int = WeaponArt.reload_deadline(weapon, state, tick) if WeaponArt.RELOAD_DIP.has(weapon) else -1
		if deadline <= tick:
			clear()
			return
		if deadline != _deadline or tick < _started:
			_deadline = deadline
			_started = tick
			_muted = false
		progress = clampf(float(tick - _started) / float(_deadline - _started), 0.0, 1.0)
		_muted = _muted or not enabled
		if _muted:
			depth = 0.0
			return
		var target: float = smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.65, 1.0, progress))
		depth = move_toward(depth, target, maxf(delta, 0.0) * 12.0)

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
	"Tack": preload("res://assets/weapons/tack/profile.png"),
	"Flechette": preload("res://assets/weapons/pickups/rifle.png"),
	"Scatter": preload("res://assets/weapons/scatter/profile.png"),
	"Rail": preload("res://assets/weapons/rail/profile.png"),
	"Rocket": preload("res://assets/weapons/pickups/rocket.png"),
	"Sniper": preload("res://assets/weapons/sniper-source-20261004/sniper.png"),
	"Shiv": preload("res://assets/weapons/48/shiv.png"),
	"Arc": preload("res://assets/weapons/arc/arc_profile.png"),
	"Article Blade": preload("res://assets/weapons/pickups/article_blade.png"),
	"ArticleBlade": preload("res://assets/weapons/pickups/article_blade.png"),
}

## Kill-feed glyphs, 48x16: a flat bone silhouette with an ink edge that
## reads on the feed's dark rows and on the bone row of the viewer's own frag.
## The modelled guns' come from their model's side view; the rest from their
## world profile (`tools/bake_kill_icons.gd`).
const KILL_ICON_SIZE: Vector2i = Vector2i(48, 16)
const KILL_ICON: Dictionary[String, Texture2D] = {
	"Fists": preload("res://assets/weapons/kill/fists.png"),
	"Shiv": preload("res://assets/weapons/kill/shiv.png"),
	"Tack": preload("res://assets/weapons/tack/kill.png"),
	"Flechette": preload("res://assets/weapons/kill/flechette.png"),
	"Scatter": preload("res://assets/weapons/scatter/kill.png"),
	"Rail": preload("res://assets/weapons/rail/kill.png"),
	"Sniper": preload("res://assets/weapons/kill/sniper.png"),
	"Arc": preload("res://assets/weapons/kill/arc.png"),
	"Rocket": preload("res://assets/weapons/kill/rocket.png"),
	"Article Blade": preload("res://assets/weapons/kill/article_blade.png"),
	"ArticleBlade": preload("res://assets/weapons/kill/article_blade.png"),
}

## The kill-feed glyph for a weapon, else its held profile, else null.
static func kill_icon(weapon: String) -> Texture2D:
	return KILL_ICON.get(weapon, PROFILE.get(weapon))

## Supplies by pickup kind, and ammunition by pool.
const SUPPLY: Dictionary[String, Texture2D] = {
	"health": preload("res://assets/pickups/medkit.png"),
	"armor": preload("res://assets/pickups/armor.png"),
	"plate": preload("res://assets/pickups/plate.png"),
	"grenade": preload("res://assets/pickups/grenades.png"),
	"bullets": preload("res://assets/pickups/bullets.png"),
	"shells": preload("res://assets/pickups/shells.png"),
	"cells": preload("res://assets/pickups/cells.png"),
	"proximity_mine": preload("res://assets/pickups/proximity_mine.png"),
	"rockets": preload("res://assets/pickups/rockets.png"),
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
	if SHOT_FRAMES.has(weapon) and since >= 0.0:
		var ends: Array = SHOT_FRAMES[weapon]
		var poses: Array = [FIRE[weapon]] + recover_frames(weapon)
		for index: int in range(mini(ends.size(), poses.size())):
			if since < float(ends[index]):
				return poses[index]
		return IDLE[weapon]
	if weapon == "Arc":
		if since >= 0.0 and since < 0.055:
			return FIRE[weapon]
		if since >= 0.055 and since < 0.14:
			return CYCLE[weapon]
		return IDLE[weapon]
	if weapon in ["Article Blade", "ArticleBlade"]:
		if since >= 0.0 and since < 0.18:
			return FIRE[weapon]
		return IDLE.get(weapon)
	if since >= 0.0 and since < FIRE_SECONDS and FIRE.has(weapon):
		return FIRE[weapon]
	if since >= CYCLE_FROM and since < CYCLE_UNTIL and CYCLE.has(weapon):
		return CYCLE[weapon]
	return IDLE.get(weapon)

## Shared accepted private-loadout deadline for held poses and visual captures.
## A local R press, another gun's reload, or an expired receipt cannot supply it.
static func reload_deadline(weapon: String, state: Dictionary, tick: int) -> int:
	if state.get("selected", "") != weapon.to_lower():
		return -1
	for magazine: Dictionary in state.get("loaded", []):
		if magazine.get("weapon", "") == weapon.to_lower() and int(magazine.get("ready_at", tick)) > tick:
			return int(magazine["ready_at"])
	return -1

static func reload_frame(weapon: String, state: Dictionary, tick: int, progress: float = 0.0) -> Texture2D:
	if reload_deadline(weapon, state, tick) <= tick:
		return null
	if weapon == "Arc":
		return ARC_RELOAD
	if BAKED.has(weapon):
		var frames: Array = BAKED[weapon]["reload"]
		return frames[clampi(int(clampf(progress, 0.0, 1.0) * frames.size()), 0, frames.size() - 1)]
	return null

## The raise frame of a modelled gun `raise` of the way up (0 down, 1 up), or
## null once it is up or when the gun has no drawn raise.
static func draw_frame(weapon: String, raise: float) -> Texture2D:
	if not BAKED.has(weapon) or raise >= 1.0:
		return null
	var frames: Array = BAKED[weapon]["draw"]
	return frames[clampi(int(clampf(raise, 0.0, 1.0) * frames.size()), 0, frames.size() - 1)]

## The held gun's motion that is not a server fact: raising it after a switch
## and lowering the old one first, lag behind the look (sway) and the dip on
## landing; `bob` below is the walk. Pure presentation, in reference pixels on
## the 1080 line HUD. `update` takes the camera's yaw and pitch (radians) and
## eye height, so it reads no input and decides nothing.
class ViewMotion extends RefCounted:
	const HOLSTER_SECONDS: float = 0.08
	const DRAW_SECONDS: float = 0.22
	## Pixels of lag per radian a second of turn, and the most it can lag.
	const SWAY_PER_RATE: float = 7.0
	const SWAY_LIMIT: float = 22.0
	const LANDING_PER_SPEED: float = 4.0
	const LANDING_LIMIT: float = 34.0
	## The gun shown now: during a holster it is still the old gun.
	var shown: String = ""
	## 0 fully lowered, 1 up.
	var raise: float = 1.0
	var offset: Vector2 = Vector2.ZERO
	var _next: String = ""
	var _lowering: bool = false
	var _sway: Vector2 = Vector2.ZERO
	var _landing: float = 0.0
	var _landing_speed: float = 0.0
	var _look: Vector2 = Vector2.INF
	var _height: float = INF
	var _fall: float = 0.0

	func reset() -> void:
		shown = ""
		_next = ""
		raise = 1.0
		_lowering = false
		offset = Vector2.ZERO
		_sway = Vector2.ZERO
		_landing = 0.0
		_landing_speed = 0.0
		_look = Vector2.INF
		_height = INF
		_fall = 0.0

	## A new gun is selected. With motion on, the old one lowers first and the
	## new one comes up; `lower_old` is false when the old pose has nothing to
	## lower (bare fists, the Shiv), and the new gun simply comes up.
	func select(weapon: String, animate: bool, lower_old: bool = true) -> void:
		if weapon == shown and not _lowering:
			return
		if not animate or shown == "" or not lower_old:
			shown = weapon
			_next = ""
			_lowering = false
			raise = 1.0 if not animate else 0.0
			return
		_next = weapon
		_lowering = true

	## A shot proves the gun is up: cut any switch motion short.
	func settle() -> void:
		if _lowering:
			shown = _next
			_lowering = false
		raise = 1.0

	func update(delta: float, look: Vector2, height: float, sway: bool) -> void:
		var dt: float = maxf(delta, 0.0)
		if _lowering:
			raise = maxf(raise - dt / HOLSTER_SECONDS, 0.0)
			if raise <= 0.0:
				shown = _next
				_lowering = false
		elif raise < 1.0:
			raise = minf(raise + dt / DRAW_SECONDS, 1.0)
		var target: Vector2 = Vector2.ZERO
		if dt > 0.0 and is_finite(_look.x) and sway:
			var turn: Vector2 = Vector2(wrapf(look.x - _look.x, -PI, PI), look.y - _look.y) / dt
			target = (Vector2(turn.x, turn.y) * SWAY_PER_RATE).clamp(Vector2(-SWAY_LIMIT, -SWAY_LIMIT), Vector2(SWAY_LIMIT, SWAY_LIMIT))
		_look = look
		_sway = _sway.lerp(target if sway else Vector2.ZERO, 1.0 - exp(-12.0 * dt))
		# Landing: a fall that stops pushes the gun down and lets it spring back.
		if dt > 0.0 and is_finite(_height) and absf(height - _height) < 2.0:
			var speed: float = (height - _height) / dt
			if _fall < -3.0 and speed > -0.5 and sway:
				_landing_speed = minf(-_fall * LANDING_PER_SPEED, LANDING_LIMIT) * 9.0
			_fall = speed
		_height = height
		_landing_speed -= (_landing * 140.0 + _landing_speed * 16.0) * dt
		_landing += _landing_speed * dt
		offset = _sway + Vector2(0.0, _landing)

	## Extra drop while a gun without raise frames lowers or rises.
	func lowered(height: float) -> float:
		return (1.0 - raise) * (1.0 - raise) * height * 0.25

## The walk bob for a held gun: a slow sideways sway and a step bounce, in
## reference pixels. Long guns bob less, the Shotgun a little more.
const BOB_SCALE: Dictionary[String, float] = {"Rail": 0.55, "Sniper": 0.4, "Scatter": 1.35}

static func bob(weapon: String, phase: float, weight: float) -> Vector2:
	return Vector2(cos(phase * 0.5) * 2.0, sin(phase) * 4.0) * float(BOB_SCALE.get(weapon, 1.0)) * weight

## The face-on picture of a placed mine for a wire phase and whether its lamp
## is lit on this server tick: a steady amber lamp while arming, red when a
## live or tripped mine's blink is on, dark in flight and between blinks.
static func mine_device(phase: String, lit: bool) -> Texture2D:
	if phase == "arming":
		return MINE_DEVICE["arming"]
	if lit and phase in ["armed", "tripped"]:
		return MINE_DEVICE["live"]
	return MINE_DEVICE["dark"]
