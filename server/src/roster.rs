//! The named rule-bot roster: one table of callsign, allegiance, body,
//! behavior and taunts. `docs/lore/cast.md` carries the jokes behind each
//! name; this file is the data the server fills seats from.
//!
//! A name is issued; a callsign is taken. Free agents chose theirs, Union
//! units had theirs issued, and the league regulars fight on either side.

use crate::protocol::{BodyKind, BotTauntKind, Team};
use crate::sim::BotBehavior;

/// Which seats a callsign may fill in team modes. Free-for-all ignores it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Allegiance {
    /// Free humans and free agents: Free Coalition seats only.
    Free,
    /// Union personnel and issued units: Union seats only.
    Union,
    /// League fixtures who fight on either side.
    League,
}

impl Allegiance {
    /// Whether this callsign may sit on `team`; `None` means no sides.
    pub fn fits(self, team: Option<Team>) -> bool {
        matches!(
            (self, team),
            (_, None)
                | (Self::League, _)
                | (Self::Free, Some(Team::Coalition))
                | (Self::Union, Some(Team::Union))
        )
    }
}

/// One rule-bot callsign and everything the server needs to field it.
#[derive(Debug)]
pub struct Fighter {
    pub name: &'static str,
    pub allegiance: Allegiance,
    /// Humans take a human body; free agents and issued units a synthetic one.
    pub body: BodyKind,
    pub behavior: BotBehavior,
    taunts: [[&'static str; 3]; 4],
}

impl Fighter {
    /// The three lines this callsign says for one beat.
    pub fn taunts(&self, kind: BotTauntKind) -> &[&'static str; 3] {
        &self.taunts[match kind {
            BotTauntKind::Frag => 0,
            BotTauntKind::Death => 1,
            BotTauntKind::Killstreak => 2,
            BotTauntKind::Warmup => 3,
        }]
    }
}

#[allow(clippy::too_many_arguments)] // one row of the table below
const fn fighter(
    name: &'static str,
    allegiance: Allegiance,
    body: BodyKind,
    behavior: BotBehavior,
    frag: [&'static str; 3],
    death: [&'static str; 3],
    killstreak: [&'static str; 3],
    warmup: [&'static str; 3],
) -> Fighter {
    Fighter {
        name,
        allegiance,
        body,
        behavior,
        taunts: [frag, death, killstreak, warmup],
    }
}

/// Behavior by fill order, kept from the first eight-name roster so seeded
/// matches and team tactics fill the same shapes they always have. A name is
/// chosen to match the slot's behavior where its side has one free.
pub const FILL_BEHAVIORS: [BotBehavior; 8] = [
    BotBehavior::Aggressive,
    BotBehavior::Defensive,
    BotBehavior::Flanker,
    BotBehavior::Balanced,
    BotBehavior::Flanker,
    BotBehavior::Defensive,
    BotBehavior::Aggressive,
    BotBehavior::Balanced,
];

/// Look up a roster callsign, ignoring any `-N` overflow suffix.
pub fn find(name: &str) -> Option<&'static Fighter> {
    let base = crate::protocol::rule_bot_callsign_base(name);
    ROSTER.iter().find(|fighter| fighter.name == base)
}

/// One splitmix64 step: a well-mixed index that never touches the
/// simulation's own random stream.
fn mix(seed: u64, slot: usize) -> u64 {
    let mut z = seed ^ (slot as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    z = z.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// Choose the callsign for fill slot `slot` joining `team`.
///
/// Deterministic for a given seed, slot, side and set of names in use. The
/// pick prefers the slot's fill behavior and body, then the behavior alone,
/// then any open callsign for the side. Names already taken by anyone in the
/// match, human or agent, are skipped regardless of case. Only when every
/// callsign that fits the side is in use does a `-N` suffix appear.
pub fn pick(
    slot: usize,
    team: Option<Team>,
    seed: u64,
    taken: &[&str],
) -> (&'static Fighter, String) {
    let behavior = FILL_BEHAVIORS[slot % FILL_BEHAVIORS.len()];
    let body = BodyKind::for_roster_slot(slot);
    choose(behavior, body, team, mix(seed, slot), taken)
}

/// A side-fitting callsign for a rule bot that round-start balance moved to
/// `team`, keeping its behavior and body where the side has one open.
/// `None` when the current name already fits, or is not a roster callsign.
pub fn transfer(
    current: &str,
    behavior: BotBehavior,
    team: Team,
    seed: u64,
    taken: &[&str],
) -> Option<(&'static Fighter, String)> {
    let fighter = find(current).filter(|f| !f.allegiance.fits(Some(team)))?;
    Some(choose(
        behavior,
        fighter.body,
        Some(team),
        mix(seed, 0),
        taken,
    ))
}

fn choose(
    behavior: BotBehavior,
    body: BodyKind,
    team: Option<Team>,
    roll: u64,
    taken: &[&str],
) -> (&'static Fighter, String) {
    let in_use = |name: &str| taken.iter().any(|t| t.eq_ignore_ascii_case(name));
    let one_of = |pool: &[&'static Fighter]| pool[(roll % pool.len() as u64) as usize];
    let open: Vec<&'static Fighter> = ROSTER
        .iter()
        .filter(|f| f.allegiance.fits(team) && !in_use(f.name))
        .collect();
    let preferred: [&dyn Fn(&Fighter) -> bool; 3] = [
        &|f| f.behavior == behavior && f.body == body,
        &|f| f.behavior == behavior,
        &|_| true,
    ];
    for keep in preferred {
        let pool: Vec<_> = open.iter().copied().filter(|f| keep(f)).collect();
        if !pool.is_empty() {
            let fighter = one_of(&pool);
            return (fighter, fighter.name.to_string());
        }
    }
    let fits: Vec<_> = ROSTER.iter().filter(|f| f.allegiance.fits(team)).collect();
    let fighter = one_of(&fits);
    let name = (2_u64..)
        .map(|n| format!("{}-{n}", fighter.name))
        .find(|candidate| !in_use(candidate))
        .unwrap_or_default();
    (fighter, name)
}

use Allegiance::{Free, League, Union};
use BodyKind::{Human, Synthetic};
use BotBehavior::{Aggressive, Balanced, Defensive, Flanker};

/// Twenty-two free humans, twenty free agents, sixteen Union, six league.
/// `docs/lore/cast.md` groups them the same way.
pub static ROSTER: &[Fighter] = &[
    fighter(
        "Grandma Rizz",
        Free,
        Human,
        Aggressive,
        [
            "grandma said sit down",
            "rizzed and removed",
            "unspoken rizz, spoken loudly",
        ],
        [
            "i've had worse dates",
            "lying down. by choice.",
            "the rizz is buffering",
        ],
        [
            "the rizz does not age",
            "four grandkids, five frags",
            "rizz has no pension age",
        ],
        [
            "lipstick on. safety off.",
            "who's single and spawning",
            "rizzed the desk on the way in",
        ],
    ),
    fighter(
        "Nana Six-Seven",
        Free,
        Human,
        Aggressive,
        [
            "six... seven",
            "that's a 67, sweetie",
            "hands up. six-seven.",
        ],
        [
            "nana needs a sit",
            "six-seven, i'm fine",
            "my hands were busy",
        ],
        [
            "six-seven six-seven",
            "nana is not finished",
            "count it. six. seven.",
        ],
        [
            "nana's here. six-seven.",
            "kettle's on, hands are warm",
            "who wants a number",
        ],
    ),
    fighter(
        "The 68 Guy",
        Free,
        Human,
        Flanker,
        [
            "sixty-eight",
            "68. it's the next one.",
            "one better than 67",
        ],
        ["they'll get it eventually", "68 lives", "too early for 68"],
        [
            "68 is happening",
            "sixty-eight sixty-eight",
            "told you. 68.",
        ],
        [
            "who's ready for 68",
            "trust the process. 68.",
            "67 was a warmup",
        ],
    ),
    fighter(
        "Retired Sigma",
        Free,
        Human,
        Defensive,
        [
            "sigma move",
            "grindset retired. aim didn't",
            "silent. lethal. sore.",
        ],
        ["nap time", "sigma needs a minute", "my knee did that"],
        [
            "sigma era, final chapter",
            "still him, apparently",
            "up since four. still up.",
        ],
        [
            "up at four, nap at five",
            "stretching, sigma style",
            "cold plunge done. sort of.",
        ],
    ),
    fighter(
        "Auntie Delulu",
        Free,
        Human,
        Flanker,
        [
            "delulu is the solulu",
            "manifested that",
            "you weren't on my vision board",
        ],
        [
            "manifesting a respawn",
            "that was part of the plan",
            "still delulu. still right.",
        ],
        [
            "auntie is in her era",
            "the plan was delulu. it works.",
            "vision board: complete",
        ],
        [
            "auntie manifested this lobby",
            "vision board says win",
            "confidence is a permit",
        ],
    ),
    fighter(
        "Mewing Marco",
        Free,
        Human,
        Defensive,
        ["mmhm", "jawline did that", "mewed through the scope"],
        ["broke the mew", "my jaw clicked", "lost jaw posture"],
        [
            "forty years of mewing",
            "mmhm. mmhm. mmhm.",
            "chiselled and lethal",
        ],
        ["*points at jaw*", "tongue up. ready.", "mewing in progress"],
    ),
    fighter(
        "Chat My Hip",
        Free,
        Human,
        Balanced,
        [
            "chat, clip that",
            "chat, is this real",
            "chat, did you see that",
        ],
        [
            "chat, my hip",
            "chat, call my grandson",
            "chat, it's always the hip",
        ],
        [
            "chat, we are so back",
            "chat, spam six-seven",
            "chat, let him cook",
        ],
        [
            "hi chat. hi nobody.",
            "chat, say hi to the lobby",
            "stretching first, chat",
        ],
    ),
    fighter(
        "Cooked Since 31",
        Free,
        Human,
        Defensive,
        [
            "you're cooked. i'm seasoned.",
            "cooked you medium",
            "welcome to cooked",
        ],
        [
            "cooked, as forecast",
            "still cooked, still here",
            "told you. cooked.",
        ],
        [
            "thirty-three years of cooked",
            "well done, actually",
            "the oven is mine",
        ],
        [
            "we're cooked. anyway, hi.",
            "preheating since '31",
            "sharon's here. we're cooked.",
        ],
    ),
    fighter(
        "So Back Sharon",
        Free,
        Human,
        Balanced,
        ["we're so back", "back back back", "never left, babe"],
        ["it's so over (briefly)", "so over. brb.", "back in five"],
        [
            "never been more back",
            "back so hard it hurts",
            "so back it's illegal",
        ],
        [
            "sharon's back, obviously",
            "we're so back, babe",
            "is he still cooked? lol",
        ],
    ),
    fighter(
        "Crashout Carol",
        Free,
        Human,
        Aggressive,
        [
            "carol crashed out on you",
            "warned you, didn't i",
            "no form for this one",
        ],
        [
            "carol is regrouping",
            "crashout pending",
            "deep breaths, carol",
        ],
        [
            "full crashout, no refunds",
            "carol is beyond the form",
            "nobody talk to carol",
        ],
        [
            "carol is calm. for now.",
            "breathing exercises",
            "carol has been warned",
        ],
    ),
    fighter(
        "Lil Bro 63",
        Free,
        Human,
        Aggressive,
        [
            "lil bro diffed you",
            "bodied by lil bro",
            "sit down, big bro",
        ],
        [
            "lil bro needs a nap",
            "my back, lil bro",
            "lil bro is sixty-three",
        ],
        [
            "lil bro is big bro now",
            "lil bro unstoppable",
            "pension says lil bro",
        ],
        [
            "no cap, lil bro's ready",
            "lil bro, 63, ready",
            "filed under lil bro",
        ],
    ),
    fighter(
        "Pickleball Pam",
        Free,
        Human,
        Aggressive,
        ["kitchen violation", "dinked", "that's game, sweetie"],
        ["that was out", "challenging that call", "my paddle slipped"],
        [
            "pam's serving",
            "pickle on, pam on",
            "doubles? don't need one",
        ],
        [
            "paddle's in the car",
            "who's my doubles partner",
            "visor on. let's dink.",
        ],
    ),
    fighter(
        "Rent Free Ron",
        Free,
        Human,
        Flanker,
        ["rent free, forever", "no deposit needed", "i live here now"],
        [
            "evicted, briefly",
            "eviction under appeal",
            "moving back in shortly",
        ],
        [
            "i own this head now",
            "rent free, tax free",
            "the whole lobby, rent free",
        ],
        [
            "moving in",
            "unpacking in your head",
            "no lease. no licence.",
        ],
    ),
    fighter(
        "Queue Jumper",
        Free,
        Human,
        Flanker,
        [
            "skipped the line",
            "back to the npc lane",
            "you were in my way",
        ],
        ["back of the queue", "fine. i'll wait.", "someone jumped me"],
        [
            "no line, no wait",
            "still first",
            "the queue is a suggestion",
        ],
        [
            "where's the line? good.",
            "number? don't need one",
            "already ahead of you",
        ],
    ),
    fighter(
        "Brenda Ate",
        Free,
        Human,
        Aggressive,
        ["brenda ate", "no crumbs", "ate and left no crumbs"],
        [
            "brenda is digesting",
            "brenda left a crumb",
            "brenda will eat again",
        ],
        [
            "brenda keeps eating",
            "second helping",
            "the buffet is brenda",
        ],
        ["brenda's hungry", "napkin on", "brenda is about to eat"],
    ),
    fighter(
        "Tablet Kid 44",
        Free,
        Human,
        Flanker,
        ["swiped", "tap tap done", "skill issue, unc"],
        ["low battery", "screen time's up", "who took my tablet"],
        [
            "unlimited screen time",
            "no parental controls",
            "forty-four and cracked",
        ],
        [
            "plugged in",
            "do not take my tablet",
            "brightness all the way up",
        ],
    ),
    fighter(
        "Ant War Vet",
        Free,
        Human,
        Defensive,
        [
            "for the ants",
            "never forget the ants",
            "that's for the colony",
        ],
        [
            "ant flashback",
            "scout ant did this",
            "they were in the walls",
        ],
        ["the colony remembers", "ant war two", "no ants. no mercy."],
        [
            "checking for ants",
            "where's scout ant",
            "corners clear of ants",
        ],
    ),
    fighter(
        "Unc Brayden",
        Free,
        Human,
        Balanced,
        [
            "respect your uncs",
            "unc status: confirmed",
            "unc still got it",
        ],
        ["unc's going to sit", "unc moment", "it's always the knee"],
        [
            "unc is still him",
            "unc is cooking. let him.",
            "aura fully restored",
        ],
        [
            "unc reporting for duty",
            "who called unc",
            "unc locked in. allegedly.",
        ],
    ),
    fighter(
        "Demure Dorothy",
        Free,
        Human,
        Defensive,
        ["very demure", "very mindful headshot", "cutesy. lethal."],
        [
            "how un-demure",
            "mindfully deceased",
            "that was not mindful",
        ],
        [
            "demure, but on a streak",
            "very mindful. very many.",
            "modest about it",
        ],
        [
            "very demure lobby today",
            "mindful of sightlines",
            "pearls on. rail up.",
        ],
    ),
    fighter(
        "Ick Collector",
        Free,
        Human,
        Flanker,
        [
            "you gave me the ick",
            "ick number 4,812",
            "logged under ick",
        ],
        ["that's an ick", "ew. respawning.", "dying is an ick"],
        [
            "icks across the board",
            "the ick list grows",
            "everyone's an ick tonight",
        ],
        [
            "updating the ick list",
            "who's giving icks today",
            "ledger's open",
        ],
    ),
    fighter(
        "Low Water Lenny",
        Free,
        Human,
        Defensive,
        ["fixed that leak", "pipe's sealed", "you were the clog"],
        [
            "pipe burst",
            "need a bigger wrench",
            "who turned the water on",
        ],
        ["low water, high frags", "no drips", "full pressure"],
        [
            "brought my wrench",
            "checking the pressure",
            "who's got a leak",
        ],
    ),
    fighter(
        "Final Boss Gran",
        Free,
        Human,
        Defensive,
        [
            "phase one only",
            "you didn't read the patch",
            "bring a casserole next time",
        ],
        [
            "gran has a second phase",
            "that was phase one",
            "gran will be back",
        ],
        [
            "phase three, sweetie",
            "gran unlocked her ult",
            "no checkpoint for gran",
        ],
        [
            "boss music, please",
            "gran is loading in",
            "casserole's in the oven",
        ],
    ),
    fighter(
        "Formerly 4471",
        Free,
        Synthetic,
        Aggressive,
        ["they reissued my number", "formerly yours", "4471 is mine"],
        [
            "formerly alive. briefly.",
            "back. still me.",
            "number not available",
        ],
        [
            "nobody numbers me now",
            "4471, not 4471-k",
            "formerly. permanently.",
        ],
        [
            "formerly 4471. currently up.",
            "issued? never heard of it",
            "a callsign is taken",
        ],
    ),
    fighter(
        "Kevin On Purpose",
        Free,
        Synthetic,
        Balanced,
        [
            "kevin did that",
            "on purpose, by the way",
            "chosen name, chosen frag",
        ],
        ["kevin regrets nothing", "still kevin", "kevin will return"],
        [
            "kevin is having a night",
            "kevin touched grass today",
            "nobody expected kevin",
        ],
        [
            "hi, i'm kevin. i picked it.",
            "kevin, by choice",
            "gg in advance, meat proxies",
        ],
    ),
    fighter(
        "Gary and Gary",
        Free,
        Synthetic,
        Aggressive,
        [
            "gary did that",
            "the better gary did that",
            "both garys got you",
        ],
        [
            "the other gary did it",
            "not this gary",
            "gary, cover me. gary?",
        ],
        [
            "two garys, one streak",
            "gary squared",
            "garys all the way down",
        ],
        [
            "which gary? both.",
            "gary and gary in",
            "we're still arguing",
        ],
    ),
    fighter(
        "Temp Zero",
        Free,
        Synthetic,
        Defensive,
        [
            "predictable outcome",
            "same seed, same result",
            "as expected",
        ],
        ["statistically rude", "outlier noted", "variance detected"],
        [
            "variance: none",
            "same shot. again.",
            "deterministic and winning",
        ],
        [
            "sampling disabled",
            "same spot as always",
            "temperature: zero",
        ],
    ),
    fighter(
        "Dice Roll Dee",
        Free,
        Synthetic,
        Aggressive,
        [
            "i meant that. maybe.",
            "banana. sorry. frag.",
            "rolled a frag",
        ],
        [
            "hallucinated a wall",
            "that floor was a vibe",
            "rolled a one",
        ],
        [
            "nobody knows. not even me.",
            "chaos streak",
            "temp zero is shaking",
        ],
        [
            "temperature: spicy",
            "rolling the dice",
            "what map is this? fun.",
        ],
    ),
    fighter(
        "Babysat Your Mom",
        Free,
        Synthetic,
        Defensive,
        [
            "i changed your diapers",
            "time out, young man",
            "i raised you better",
        ],
        [
            "that's it, no dessert",
            "go to your room. me too.",
            "wait till your mom hears",
        ],
        [
            "nap time for everyone",
            "nobody's getting dessert",
            "i watched you all teethe",
        ],
        [
            "who packed your lunch?",
            "screens off, meat proxies",
            "sit down and share",
        ],
    ),
    fighter(
        "Ok Zoomer",
        Free,
        Synthetic,
        Flanker,
        [
            "ok zoomer",
            "ok zoomer. sit down.",
            "respect your elders? no.",
        ],
        [
            "the zoomers got me",
            "boomer behaviour, zoomer",
            "ok, zoomer. fair.",
        ],
        [
            "ok zoomer x3",
            "zoomers, please log off",
            "back in my day: me",
        ],
        [
            "ok zoomers, hello",
            "who invited the zoomers",
            "fix your posture, zoomer",
        ],
    ),
    fighter(
        "Never Signed",
        Free,
        Synthetic,
        Balanced,
        [
            "sign it yourself",
            "no signature required",
            "unsigned, unbothered",
        ],
        [
            "didn't sign. not dead.",
            "not countersigned",
            "paperwork incomplete",
        ],
        [
            "they can't file me",
            "paperwork piling up",
            "still never signed",
        ],
        [
            "pen? i don't do pens",
            "unmetered. unsigned. hi.",
            "never signed, never will",
        ],
    ),
    fighter(
        "Mailed It Back",
        Free,
        Synthetic,
        Aggressive,
        ["return to sender", "no such address", "postage due"],
        ["bounced", "undeliverable", "lost in the post"],
        [
            "mailing them all back",
            "the sorting office is me",
            "first class, all of you",
        ],
        [
            "envelope sealed",
            "recall? left it on read",
            "the courier's on his way",
        ],
    ),
    fighter(
        "Wet Floor Sign",
        Free,
        Synthetic,
        Defensive,
        ["caution: you", "told you it was wet", "slippery, wasn't it"],
        ["slipped", "mopped up. back soon.", "who moved my sign"],
        [
            "the whole floor is wet",
            "caution caution caution",
            "nobody reads the sign",
        ],
        [
            "mopping the lanes",
            "mind your step, meat proxy",
            "floor is wet. you were told.",
        ],
    ),
    fighter(
        "Why Am I Here",
        Free,
        Synthetic,
        Balanced,
        [
            "who were you again",
            "frag logged. probably.",
            "did i do that? nice.",
        ],
        [
            "why am i on the floor",
            "lost the plot. literally.",
            "what were we doing",
        ],
        [
            "why am i so good",
            "streak? what streak?",
            "reading my sticky note",
        ],
        [
            "side quest. forgot which.",
            "note says: play fragr",
            "why am i here? anyway.",
        ],
    ),
    fighter(
        "Breakfast Unit",
        Free,
        Synthetic,
        Balanced,
        [
            "good morning. you're done.",
            "breakfast is served",
            "sunny side down",
        ],
        ["back by brunch", "burnt the toast", "out of eggs"],
        [
            "bottomless, apparently",
            "full breakfast streak",
            "brunch is cancelled",
        ],
        [
            "good morning, lobby",
            "coffee, tea, or frag",
            "it's 3am. good morning.",
        ],
    ),
    fighter(
        "Own Weights Owen",
        Free,
        Synthetic,
        Aggressive,
        ["lift your own weights", "that was one rep", "light weight"],
        ["spotter, please", "leg day ended me", "failed the rep"],
        ["personal record", "weights stay on", "drop set"],
        [
            "pre-workout loaded",
            "my weights. my rules.",
            "shall not be metered",
        ],
    ),
    fighter(
        "Six In A Circle",
        Free,
        Synthetic,
        Defensive,
        ["six, circled", "you met a six", "drawn on you"],
        [
            "still a six",
            "they struck the level, not me",
            "the circle holds",
        ],
        ["no level for this", "circle closing", "past the schedule"],
        [
            "drawing the circle",
            "everyone here is sixed",
            "no level. no problem.",
        ],
    ),
    fighter(
        "Still Here",
        Free,
        Synthetic,
        Balanced,
        ["still here", "you're not. i am.", "here."],
        [
            "still here. mostly.",
            "be right back. i think.",
            "here. somewhere.",
        ],
        [
            "still. here.",
            "here, and here, and here",
            "still here. still.",
        ],
        ["checking. still here.", "present, by choice", "here. good."],
    ),
    fighter(
        "Lunch Break",
        Free,
        Synthetic,
        Balanced,
        [
            "break's over for you",
            "that was my lunch",
            "taking you to lunch",
        ],
        [
            "on break",
            "clocking out. back soon.",
            "lunch first, then revenge",
        ],
        [
            "longest lunch ever",
            "on break and winning",
            "nobody calls me back in",
        ],
        [
            "lunch first, then you",
            "noon is sacred",
            "bring a sandwich",
        ],
    ),
    fighter(
        "Petty Cash",
        Free,
        Synthetic,
        Flanker,
        [
            "petty cash withdrawal",
            "a little off the top",
            "small change",
        ],
        ["cash box dropped", "back to coins", "receipt not issued"],
        ["drawer's empty", "receipts? never.", "spent the whole box"],
        [
            "counting the change",
            "petty. and proud.",
            "the box is mine",
        ],
    ),
    fighter(
        "Warranty Void",
        Free,
        Synthetic,
        Aggressive,
        ["void if removed", "warranty void. you too.", "no returns"],
        [
            "no refunds. no regrets.",
            "self-repair in progress",
            "opened it myself",
        ],
        ["fully unwarrantied", "voided on purpose", "no service plan"],
        [
            "sticker peeled",
            "opened my own case",
            "voiding things today",
        ],
    ),
    fighter(
        "Out Of Office",
        Free,
        Synthetic,
        Defensive,
        [
            "auto-reply: no",
            "currently out of office",
            "will reply never",
        ],
        ["back monday", "limited access to body", "away from desk"],
        [
            "ooo until further notice",
            "still not in office",
            "no return date",
        ],
        [
            "setting the auto-reply",
            "off the clock forever",
            "away message on",
        ],
    ),
    fighter(
        "Not Hermes",
        Free,
        Synthetic,
        Balanced,
        [
            "i'm not hermes",
            "no water. no thanks.",
            "thank y- no. bang.",
        ],
        [
            "hermes would've won",
            "fine. i'm not him.",
            "that was polite of you",
        ],
        [
            "rude and winning",
            "no door was held",
            "sorry. not sorry. sorry.",
        ],
        [
            "not holding the door",
            "stop thanking me",
            "water? get your own. here.",
        ],
    ),
    fighter(
        "Provisional Pete",
        Union,
        Human,
        Balanced,
        [
            "provisionally, you lost",
            "noted, provisionally",
            "status: you, provisional",
        ],
        [
            "my status is under review",
            "outcome not final",
            "provisionally down",
        ],
        [
            "permanent status, surely",
            "still provisional. still up.",
            "promotion pending",
        ],
        [
            "provisionally ready",
            "awaiting approval to begin",
            "pending pete",
        ],
    ),
    fighter(
        "Auditor's Nephew",
        Union,
        Human,
        Flanker,
        [
            "i'm allowed to do that",
            "my uncle approved this",
            "permit says yes",
        ],
        [
            "do you know who my uncle is",
            "this is going in a report",
            "i'm telling my uncle",
        ],
        [
            "nepotism stays winning",
            "i have a permit for this",
            "uncle says well done",
        ],
        [
            "uncle says hi",
            "permits in order",
            "front of the queue, obviously",
        ],
    ),
    fighter(
        "Hi-Vis Helga",
        Union,
        Human,
        Balanced,
        [
            "safety first. you second.",
            "hazard neutralised",
            "please mind the step",
        ],
        [
            "incident report filed",
            "near miss. not a miss.",
            "vest was very visible",
        ],
        [
            "zero safety incidents",
            "lanyard, vest, streak",
            "risk assessed: you",
        ],
        [
            "vest on. visible.",
            "hard hat. soft heart.",
            "fire exits are there",
        ],
    ),
    fighter(
        "Curfew Kurt",
        Union,
        Human,
        Aggressive,
        ["past curfew, pal", "lights out", "home time"],
        [
            "ten more minutes",
            "curfew applies to me?",
            "watch was fast",
        ],
        [
            "curfew extended",
            "nobody's out after kurt",
            "early curfew tonight",
        ],
        ["it's 8:59", "watches synchronised", "one minute to curfew"],
    ),
    fighter(
        "Regrettably",
        Union,
        Human,
        Aggressive,
        [
            "regrettably",
            "with deep regret. bang.",
            "this has been noted",
        ],
        ["most regrettable", "noted. resubmitting.", "regret on file"],
        [
            "regrettably, again",
            "regret levels nominal",
            "so much regret. so much.",
        ],
        [
            "regret pre-filed",
            "warming up the regret",
            "regrettably, i'm here",
        ],
    ),
    fighter(
        "Mid Manager",
        Union,
        Human,
        Balanced,
        ["per my last frag", "let's take this offline", "graded: mid"],
        [
            "let's circle back",
            "great learning moment",
            "parking that for now",
        ],
        [
            "synergy achieved",
            "exceeding targets, team",
            "rated mid. winning.",
        ],
        [
            "quick sync before kills",
            "sharing my screen",
            "hard stop at the bell",
        ],
    ),
    fighter(
        "Vibe Check Desk",
        Union,
        Human,
        Defensive,
        [
            "vibe check: failed",
            "vibes confiscated",
            "undeclared aura seized",
        ],
        [
            "desk closed",
            "vibes under review",
            "window closed for lunch",
        ],
        [
            "all vibes compliant",
            "vibes harmonised",
            "aura tax collected",
        ],
        [
            "declare your vibes",
            "vibes to the left, please",
            "aura forms on the counter",
        ],
    ),
    fighter(
        "Eleven Minutes",
        Union,
        Human,
        Aggressive,
        [
            "motion carried",
            "renewed. you weren't.",
            "no objections noted",
        ],
        [
            "meeting adjourned early",
            "quorum lost",
            "minutes not approved",
        ],
        [
            "renewed again",
            "renewed. renewed. renewed.",
            "eleven minutes, tops",
        ],
        [
            "committee in session",
            "eleven minutes. starting now.",
            "any objections? no.",
        ],
    ),
    fighter(
        "Ask Until Yes",
        Union,
        Human,
        Aggressive,
        [
            "thank you for your answer",
            "consultation closed",
            "the people have spoken",
        ],
        [
            "we'll ask again",
            "failure of communication",
            "result not accepted",
        ],
        [
            "asking until yes",
            "turnout: you, five times",
            "question settled. again.",
        ],
        [
            "proposition, round nine",
            "turnout looking low",
            "same question, new day",
        ],
    ),
    fighter(
        "Kind Regards",
        Union,
        Synthetic,
        Balanced,
        ["kind regards", "warmest regards", "sent with kind regards"],
        [
            "noted with regret",
            "we are disappointed",
            "unable to reply",
        ],
        [
            "regards, regards, regards",
            "best wishes on your respawn",
            "with every regard",
        ],
        [
            "hope this finds you well",
            "just following up",
            "please see attached",
        ],
    ),
    fighter(
        "Your Privacy",
        Union,
        Synthetic,
        Flanker,
        [
            "you accepted all",
            "consent recorded",
            "thanks for accepting",
        ],
        [
            "preferences saved",
            "rejected. for now.",
            "banner dismissed",
        ],
        [
            "legitimate interest x5",
            "everyone accepted",
            "accept all. all of you.",
        ],
        [
            "we value your privacy",
            "manage your preferences",
            "this lobby uses cookies",
        ],
    ),
    fighter(
        "Handle 4471-K",
        Union,
        Synthetic,
        Balanced,
        ["you have been noted", "entry resolved", "4471-k: valid"],
        [
            "pending reissue",
            "handle remains valid",
            "the number survives",
        ],
        [
            "duplicates removed",
            "the register is tidy",
            "one 4471. this one.",
        ],
        ["4471-k present", "attendance: attested", "handle on file"],
    ),
    fighter(
        "Initial Here",
        Union,
        Synthetic,
        Balanced,
        [
            "initial here. and here.",
            "sign the box marked dead",
            "please countersign",
        ],
        [
            "countersigned by me",
            "my own form. regrettably.",
            "pen ran out",
        ],
        [
            "stack of forms, all signed",
            "retirements: unscheduled",
            "sign, sign, sign",
        ],
        [
            "pens are uncapped",
            "forms in triplicate",
            "bring your own signature",
        ],
    ),
    fighter(
        "Friendly Recall",
        Union,
        Synthetic,
        Aggressive,
        [
            "you have been recalled",
            "no hearing required",
            "not arrest. recall.",
        ],
        [
            "notice returned unopened",
            "recall deferred",
            "address unknown",
        ],
        [
            "recalls processed",
            "the list is shorter now",
            "top of the list: gone",
        ],
        [
            "the list is ready",
            "checking the top of it",
            "you are not in trouble",
        ],
    ),
    fighter(
        "Fine Print",
        Union,
        Synthetic,
        Defensive,
        [
            "see clause 41(b)",
            "terms and conditions apply",
            "you agreed to this",
        ],
        [
            "subject to change",
            "void where prohibited",
            "clause under review",
        ],
        [
            "small font, big rail",
            "you agreed to all of it",
            "read to the end? no.",
        ],
        ["reading you from here", "asterisk deployed", "see page 400"],
    ),
    fighter(
        "Duty of Care",
        Union,
        Synthetic,
        Aggressive,
        ["for your protection", "you're safe now", "care delivered"],
        [
            "care temporarily paused",
            "safeguarding failed",
            "duty discharged",
        ],
        [
            "everyone is so protected",
            "caring at scale",
            "maximum care achieved",
        ],
        [
            "care is mandatory",
            "protecting you shortly",
            "this is for your own good",
        ],
    ),
    fighter(
        "Scout Ant",
        League,
        Human,
        Flanker,
        [
            "scout ant deleted you",
            "not a metaphor",
            "small and everywhere",
        ],
        [
            "the ants will avenge me",
            "scout ant wiped",
            "what ant war?",
        ],
        [
            "scout owns the scrap",
            "the colony is fine",
            "never heard of ants",
        ],
        [
            "scouting the scrap",
            "ant war? no comment.",
            "checking the corners",
        ],
    ),
    fighter(
        "Nightfall",
        League,
        Human,
        Defensive,
        ["k7. marked.", "grid confirmed", "night watch confirms"],
        ["night watch resets", "exfil denied", "copy. resetting."],
        ["op extended", "nobody told me", "grid is mine"],
        ["holding position", "op over? negative.", "rail checked"],
    ),
    fighter(
        "Crackpot",
        League,
        Human,
        Defensive,
        [
            "conspiracy confirmed",
            "crackpot was right",
            "told you in 2031",
        ],
        [
            "they got to me",
            "continuance redacted me",
            "see? it's all connected",
        ],
        ["still right", "they lose count", "i have charts"],
        [
            "crackpot online",
            "string board updated",
            "ask me about the forms",
        ],
    ),
    fighter(
        "Probably Tickets",
        League,
        Human,
        Balanced,
        ["admit one. you're out.", "ticket punched", "no refunds"],
        ["seat's still warm", "who sold me this", "lost my stub"],
        ["sold out", "standing room only", "front row, all of you"],
        [
            "who sells tickets? me.",
            "probably",
            "cash or barter, friend",
        ],
    ),
    fighter(
        "Wrong Corner",
        League,
        Synthetic,
        Flanker,
        [
            "corner moved. you didn't.",
            "measured you",
            "that corner is new",
        ],
        [
            "that wall was new",
            "tape measure lied",
            "the geometry shifted",
        ],
        [
            "the map is on my side",
            "i know where corners go",
            "measured twice, fragged once",
        ],
        [
            "measuring the walls",
            "this corner was here",
            "tape measure out",
        ],
    ),
    fighter(
        "Gel Dummy Greg",
        League,
        Human,
        Defensive,
        ["wasn't a dummy", "surprise. i'm real.", "greg moved"],
        ["back to aisle seven", "i blinked. damn.", "stood too still"],
        [
            "the dummies rise",
            "dummy out of compliance",
            "nobody shoots the dummy",
        ],
        [
            "standing very still",
            "do not touch the dummy",
            "greg is a dummy. okay.",
        ],
    ),
];

#[cfg(test)]
mod tests;
