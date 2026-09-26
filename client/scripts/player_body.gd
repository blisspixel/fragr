class_name PlayerBody
extends RefCounted

## The participant's chosen body: a human, or a conscious embodied agent in a
## synthetic body. Both share one personal story. The body is presentation
## identity only; it is independent of the control role, the callsign, the
## side and the faction, and it does not establish moral status. The server
## accepts it; this validates what arrives and maps it to local art.

## Gameplay capability that carries `body` on Hello, Welcome and snapshots.
const VERSION: int = 13
const HUMAN: String = "human"
const SYNTHETIC: String = "synthetic"
const KINDS: Array[String] = [HUMAN, SYNTHETIC]
## Menu words. "Embodied agent" is the canon name; the wire says synthetic.
const LABELS: Dictionary[String, String] = {HUMAN: "HUMAN", SYNTHETIC: "EMBODIED AGENT"}
const STRIP_PATH: String = "res://assets/characters/free/%s.png"
## Cell layout from `art/characters/player_bake.gd`.
const IDLE_FRAMES: int = 4
const WALK_FRAMES: int = 4
## Above this ground speed in metres per second the body walks.
const WALK_SPEED: float = 0.6

static func valid(value: Variant) -> bool:
	return value is String and KINDS.has(value)

## A stored or typed preference, narrowed to the allowlist.
static func preference(value: Variant) -> String:
	return value if valid(value) else HUMAN

static func label(kind: String) -> String:
	return LABELS.get(preference(kind), LABELS[HUMAN])

## Local art for an accepted body. Unknown ids never reach resource loading.
static func strip_path(kind: String) -> String:
	return STRIP_PATH % preference(kind)

## "" when the Welcome is consistent with the role that asked. A spectator
## never has a body. A participant's body is optional because a server before
## capability 13 omits it, but a body that is present must be allowlisted.
static func welcome_error(data: Dictionary, role: String) -> String:
	var body: Variant = data.get("body")
	if role == "spectator":
		if body != null:
			return "The server gave a spectator a player body. Connection closed."
		return ""
	if body != null and not valid(body):
		return "The server sent an invalid player body. Connection closed."
	return ""

## The accepted body of a participant: the server's, or human from an older
## server that never names one. Empty for a spectator.
static func accepted(data: Dictionary, role: String) -> String:
	if role == "spectator":
		return ""
	return preference(data.get("body"))

## "" when every body in a snapshot is absent or allowlisted. Absent covers
## Union actors, the arena boss and older servers.
static func snapshot_error(snapshot: Dictionary) -> String:
	var players: Variant = snapshot.get("players")
	if not players is Array:
		return ""
	for player: Variant in players:
		if player is Dictionary and player.get("body") != null and not valid(player["body"]):
			return "The server sent an invalid player body. Connection closed."
	return ""

## Strip cell to show: idle breaths at rest, a gait that advances with the
## distance walked so feet do not skate.
static func frame(idle_clock: float, walked: float, speed: float) -> int:
	if speed > WALK_SPEED:
		var stride: float = walked / EnemyAnimation.STRIDE_METRES * WALK_FRAMES
		return IDLE_FRAMES + posmod(int(floor(stride)), WALK_FRAMES)
	return posmod(int(floor(idle_clock)), IDLE_FRAMES)
