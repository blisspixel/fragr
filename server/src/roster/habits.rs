//! What a rule bot reaches for, and what it says when it settles a score.
//!
//! Every callsign has a favourite gun and one pad it keeps time on. Most take
//! both from their behavior; the ones canon speaks for take them from canon
//! (`docs/lore/cast.md`, `docs/lore/the-league.md`): the Night Watch favour
//! the rail and Nightfall times it, the Static Kids spray scatter and push,
//! Hangar Candy are flechette mains, and Aunt Linda farms health. The habit
//! follows the callsign, so a bot renamed by round-start balance takes the
//! new name's habits with it.

use super::{find, tribe, Allegiance, Tribe};
use crate::protocol::{BodyKind, WeaponType};
use crate::sim::BotBehavior;

/// The one pad a callsign keeps an appointment with.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PadHabit {
    /// The Custody Plate, and ordinary armour on the way.
    Plate,
    /// The Railgun, or the Sniper where a map lays one.
    Rail,
    Scatter,
    Rocket,
    Health,
}

impl PadHabit {
    /// The power pads are worth a walk across the map; the rest only when
    /// they are close (`sim/bot_senses.rs`).
    pub fn map_wide(self) -> bool {
        matches!(self, Self::Plate | Self::Rail | Self::Rocket)
    }
}

/// A callsign's favourite gun and the pad it times.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Habits {
    pub favourite: WeaponType,
    pub times: PadHabit,
}

/// The behavior's own habits: rushers time the Plate, the defensive line
/// keeps the Railgun, flankers push the Scatter and the balanced regulars
/// farm health. Rushers and the balanced regulars reach for the Rocket.
pub const fn behavior_habits(behavior: BotBehavior) -> Habits {
    match behavior {
        BotBehavior::Aggressive => Habits {
            favourite: WeaponType::Rocket,
            times: PadHabit::Plate,
        },
        BotBehavior::Defensive | BotBehavior::Compliance => Habits {
            favourite: WeaponType::Rail,
            times: PadHabit::Rail,
        },
        BotBehavior::Flanker => Habits {
            favourite: WeaponType::Scatter,
            times: PadHabit::Scatter,
        },
        BotBehavior::Balanced => Habits {
            favourite: WeaponType::Rocket,
            times: PadHabit::Health,
        },
    }
}

/// Callsigns whose habits canon names, with only what it names: a favourite
/// gun, a timed pad, or both. Everything else is the behavior's.
const CANON: &[(&str, Option<WeaponType>, Option<PadHabit>)] = &[
    // Night Watch favour the rail (the-league.md); Nightfall times it.
    ("Nightfall", Some(WeaponType::Rail), Some(PadHabit::Rail)),
    (
        "Graveyard Shift",
        Some(WeaponType::Rail),
        Some(PadHabit::Rail),
    ),
    // Static Kids spray scatter and push.
    (
        "Static Kid",
        Some(WeaponType::Scatter),
        Some(PadHabit::Scatter),
    ),
    (
        "Pckt Lss",
        Some(WeaponType::Scatter),
        Some(PadHabit::Scatter),
    ),
    ("Dd Pxl", Some(WeaponType::Scatter), Some(PadHabit::Scatter)),
    // Hangar Candy: flechette mains, the most reliable thing in the room.
    ("Eyes Only", Some(WeaponType::Flechette), None),
    ("Need To Know", Some(WeaponType::Flechette), None),
    // Holds a tent revival on level three of the lot; farms health.
    ("Aunt Linda", None, Some(PadHabit::Health)),
    // Compliance-flavoured, a joke he has decided to enjoy: he wears the
    // Custody Plate whenever it is his to wear.
    ("Crackpot", None, Some(PadHabit::Plate)),
    // Exactly what it says: the Plate is never yours while he is up.
    ("Buzzkill", None, Some(PadHabit::Plate)),
];

/// The habits of the fighter called `name`, playing `behavior`.
pub fn habits(name: &str, behavior: BotBehavior) -> Habits {
    let base = crate::protocol::rule_bot_callsign_base(name);
    let own = behavior_habits(behavior);
    CANON
        .iter()
        .find(|(callsign, _, _)| *callsign == base)
        .map_or(own, |(_, favourite, times)| Habits {
            favourite: favourite.unwrap_or(own.favourite),
            times: times.unwrap_or(own.times),
        })
}

/// How a callsign settles a score, by register. NODS have no grudges: they
/// answer only with Articles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Register {
    NightWatch,
    StaticKids,
    HangarCandy,
    GulfBreeze,
    Hermes,
    Pi,
    L5,
    UnionUnit,
    UnionStaff,
    FreeAgent,
    Street,
}

pub(super) fn register(name: &str) -> Option<Register> {
    let fighter = find(name)?;
    if fighter.name.starts_with("NODS ") {
        return None;
    }
    Some(match (fighter.name, tribe(name)) {
        (_, Some(Tribe::NightWatch)) => Register::NightWatch,
        (_, Some(Tribe::StaticKids)) => Register::StaticKids,
        (_, Some(Tribe::HangarCandy)) => Register::HangarCandy,
        (_, Some(Tribe::GulfBreeze)) => Register::GulfBreeze,
        ("Hermes", _) => Register::Hermes,
        ("Pi", _) => Register::Pi,
        ("L5", _) => Register::L5,
        _ => match (fighter.allegiance, fighter.body) {
            (Allegiance::Union, BodyKind::Synthetic) => Register::UnionUnit,
            (Allegiance::Union, _) => Register::UnionStaff,
            (Allegiance::Free, BodyKind::Synthetic) => Register::FreeAgent,
            _ => Register::Street,
        },
    })
}

/// Lines a callsign says to the fighter it owed, `{}` standing for that
/// fighter's name. Lowercase except the Night Watch, who use capitals and no
/// punctuation; no radio words, no slur.
fn lines(register: Register) -> &'static [&'static str] {
    match register {
        Register::NightWatch => &["DEBT CLOSED {}", "SQUARED {}", "LOGGED AND PAID {}"],
        Register::StaticKids => &["patched you out, {}", "glitch was you, {}", "rbt cmplt, {}"],
        Register::HangarCandy => &[
            "grudge declassified: {}",
            "file closed. {}: denied",
            "eyes only. {} knows why",
        ],
        Register::GulfBreeze => &[
            "same coordinates, {}",
            "logged the sighting, {}",
            "saw you coming, {}",
        ],
        Register::Hermes => &["thank you for the rematch, {}", "thank you, {}. water?"],
        Register::Pi => &["a card is in the post, {}", "noted, {}. with thanks"],
        Register::L5 => &["even."],
        Register::UnionUnit => &[
            "your complaint is actioned, {}",
            "matter closed, {}. kind regards",
        ],
        Register::UnionStaff => &["your file is current, {}", "we keep records, {}"],
        Register::FreeAgent => &[
            "we're square, {}",
            "kept the receipt, {}",
            "chose to remember that, {}",
        ],
        Register::Street => &[
            "told you i'd remember, {}",
            "that's for earlier, {}",
            "receipts, {}",
            "we're even, {}. for now",
        ],
    }
}

/// What `name` says to `victim` on fragging the fighter it held a grudge
/// against, or `None` for a callsign with no grudges (NODS) or no roster row.
pub fn grudge_line(name: &str, victim: &str, salt: u64) -> Option<String> {
    let register = register(name)?;
    let pool = lines(register);
    let line = pool[(salt % pool.len() as u64) as usize];
    let victim = crate::protocol::rule_bot_callsign_base(victim);
    let victim = if register == Register::NightWatch {
        victim
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == ' ')
            .collect::<String>()
            .to_ascii_uppercase()
    } else {
        victim.to_string()
    };
    Some(line.replacen("{}", victim.trim(), 1))
}
