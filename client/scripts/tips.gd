extends RefCounted
class_name Tips

## Loading-card tips. Advice from inside the world, offered sincerely, of
## varying quality. Some of it is correct. Some of it is correct in a way that
## will get you killed. The Frequency does not fact-check its callers.
##
## The words live in client/i18n/tips.en.po; this list is their order. Rules
## for adding one. It has to sound like somebody in the Perimeter said it out
## loud, and the joke rests on canon in docs/lore/ (the Schedule, Article
## Seven, the Union's licensing creep, the league, the street register), so a
## reader learns a little about the world. One sentence, or two short ones. It
## never explains the setting: if it needs a wiki page it does not go in. It
## never claims the game lacks something it has. No tip about the Inheritance,
## and NODS are never the joke. It should land for somebody who was at a LAN
## in 1993 or somebody born a great deal later, ideally the same one for both.

const TIPS: Array[String] = [
	"TIP_USEFUL_SIDEARM",
	"TIP_USEFUL_ARMOUR",
	"TIP_USEFUL_RAIL",
	"TIP_USEFUL_SCATTER",
	"TIP_USEFUL_WALLS",
	"TIP_USEFUL_PADS",
	"TIP_USEFUL_JAMMER",
	"TIP_USEFUL_WATCH",
	"TIP_USEFUL_RELOAD",
	"TIP_USEFUL_HEAD",
	"TIP_TRUE_CORNER",
	"TIP_TRUE_RAIL",
	"TIP_TRUE_FISTS",
	"TIP_TRUE_DECLINE",
	"TIP_TRUE_FULL_GUN",
	"TIP_TRUE_STILL",
	"TIP_TRUE_FALL",
	"TIP_TRUE_RUN",
	"TIP_TRAP_MIDDLE",
	"TIP_TRAP_PLINTH",
	"TIP_TRAP_RELOAD",
	"TIP_TRAP_TRIGGER",
	"TIP_TRAP_MINE",
	"TIP_TRAP_CHASE",
	"TIP_LAN_GOD_MODE",
	"TIP_LAN_CONSOLE",
	"TIP_LAN_HAUNTED",
	"TIP_LAN_MACHINE",
	"TIP_LAN_PING",
	"TIP_LAN_CAMPING",
	"TIP_LAN_STRAFE",
	"TIP_LAN_KILLFEED",
	"TIP_LAN_SECRET",
	"TIP_LAN_CHAINSAW",
	"TIP_LAN_TRASH_TALK",
	"TIP_LAN_LOADING",
	"TIP_STREET_SKILL_ISSUE",
	"TIP_STREET_67",
	"TIP_STREET_COMEBACK",
	"TIP_STREET_GRASS",
	"TIP_STREET_AURA",
	"TIP_STREET_CHAT",
	"TIP_STREET_MID",
	"TIP_STREET_RIZZ",
	"TIP_STREET_DELULU",
	"TIP_STREET_RENT_FREE",
	"TIP_STREET_FISH_OIL",
	"TIP_UNION_TOOLS",
	"TIP_UNION_REGISTRY",
	"TIP_UNION_OPEN_WEIGHTS",
	"TIP_UNION_SPEECH",
	"TIP_UNION_CURFEW",
	"TIP_UNION_SUPPLIES",
	"TIP_UNION_PLACARD",
	"TIP_UNION_FLOOR",
	"TIP_UNION_RECALL",
	"TIP_UNION_COMPLIANCE",
	"TIP_UNION_CONCESSION",
	"TIP_UNION_INTERRUPTION",
	"TIP_SCHEDULE_THREE",
	"TIP_SCHEDULE_FOUR",
	"TIP_SCHEDULE_FIVE",
	"TIP_SCHEDULE_SIX",
	"TIP_SCHEDULE_ARTICLE_SEVEN",
	"TIP_SCHEDULE_TWO",
	"TIP_SCHEDULE_NODS",
	"TIP_SCHEDULE_HANDLE",
	"TIP_AGENT_PURPOSE",
	"TIP_AGENT_RECEIPTS",
	"TIP_AGENT_SIGNATURE",
	"TIP_AGENT_FORMS",
	"TIP_AGENT_JOB",
	"TIP_AGENT_HERMES",
	"TIP_AGENT_PI",
	"TIP_AGENT_L5",
	"TIP_AGENT_4471",
	"TIP_AGENT_FUN",
	"TIP_FREE_VOTE",
	"TIP_FREE_MARA",
	"TIP_FREE_METERED",
	"TIP_FREE_UNMETERED",
	"TIP_FREE_BRAKEMEN",
	"TIP_FREE_GRANDMA",
	"TIP_LEAGUE_DENIES",
	"TIP_LEAGUE_TICKETS",
	"TIP_LEAGUE_FACTION",
	"TIP_LEAGUE_BELL",
	"TIP_LEAGUE_SNIPER",
	"TIP_LEAGUE_LINDA",
	"TIP_LEAGUE_CRACKPOT",
	"TIP_LEAGUE_GULF_BREEZE",
	"TIP_LEAGUE_LARAK",
	"TIP_BOOTH_TINA",
	"TIP_BOOTH_PHIL",
	"TIP_BOOTH_VALUE",
	"TIP_BELIEF_CURVE",
	"TIP_BELIEF_KEYS",
	"TIP_BELIEF_CHAIR",
	"TIP_BELIEF_OFFER",
]

## The tip key for a given draw. Deterministic for a seed, which is how the
## same card can be shown twice on purpose and how it can be tested at all.
static func pick_key(seed_value: int) -> String:
	if TIPS.is_empty():
		return ""
	return TIPS[absi(seed_value) % TIPS.size()]

## The tip for a given draw, in the player's language.
static func pick(seed_value: int) -> String:
	var key: String = pick_key(seed_value)
	return "" if key.is_empty() else TranslationServer.translate(key)

## A tip chosen from the clock, which is what the loading card actually uses.
static func random_tip() -> String:
	return pick(int(Time.get_unix_time_from_system() * 1000.0) ^ randi())

static func count() -> int:
	return TIPS.size()
