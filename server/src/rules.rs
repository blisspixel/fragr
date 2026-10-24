//! The rule set a server runs: a mode plus host mutators, validated once at
//! start and carried in `MatchConfig`. The sim asks it questions; the wire
//! shape readers see is `protocol::MatchRules`.
use crate::protocol::{
    EquipmentPolicy, GameMode, MatchRules, Mutator, Team, TeamScores, WeaponType,
};

mod sabotage;
pub use sabotage::{match_outcome, round_slot, MatchOutcome, RoundSlot, SabotageConfig};

/// Lives each fighter has per round under Two Lives.
pub const TWO_LIVES: u8 = 2;
/// Default frag limit for a team round: side frags, not fighter frags.
pub const TEAM_FRAG_LIMIT: u32 = 25;
pub const CTF_CAPTURE_LIMIT: u32 = 3;
/// Weapon pads come back on the rule sheet's slower team clock.
pub const TEAM_WEAPON_RESPAWN_TICKS: u32 = 20 * 30;
/// Free-for-all pad clocks. Every life starts with the Pistol, so a gun on
/// the floor is an appointment: the Rifle, Shotgun and Repeater return in
/// 15 s, the long and heavy guns in 25 s, a spare Pistol in 8 s.
pub const FFA_WEAPON_RESPAWN_TICKS: u32 = 20 * 15;
pub const FFA_POWER_WEAPON_RESPAWN_TICKS: u32 = 20 * 25;
pub const FFA_SIDEARM_RESPAWN_TICKS: u32 = 20 * 8;
/// Free-for-all health and armour, the rule sheet's 25 s. Team modes keep
/// the 15 s health and armour clock.
pub const FFA_HEALTH_ARMOR_RESPAWN_TICKS: u32 = 20 * 25;
/// Ticks a fallen free-for-all fighter waits before the server tries to put
/// them back: four seconds at 20 Hz (Nick, 2026-10-23). It moves neither the
/// team modes nor the spawn shield.
pub const FFA_RESPAWN_DELAY_TICKS: u32 = 80;
/// The same wait for team modes that respawn (TDM, CTF, Conquest). Kept
/// separate so FFA pacing can change without silently moving these.
pub const TEAM_RESPAWN_DELAY_TICKS: u32 = 60;
/// The wait a campaign participant's body is given at death. Campaign maps
/// run under the default (FFA) rule sheet, so without this value an FFA
/// pacing change would silently move campaign death timing as well. Mission
/// recovery owns what happens next.
pub const CAMPAIGN_RESPAWN_DELAY_TICKS: u32 = 60;
/// No Host reaction lands within eight seconds of the last one.
pub const REACTION_GAP_TICKS: u64 = 20 * 8;
/// A streak this long is worth a line when it ends.
pub const STREAK_WORTH_ENDING: u32 = 3;
/// A side this far behind that draws level is a comeback.
pub const COMEBACK_DEFICIT: u32 = 4;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RuleSet {
    mode: GameMode,
    mutators: Vec<Mutator>,
    friendly_fire: bool,
}

impl RuleSet {
    /// Refuse combinations that contradict each other, so a host learns at
    /// start rather than in the middle of a confusing round.
    pub fn new(mode: GameMode, mutators: &[Mutator], friendly_fire: bool) -> Result<Self, String> {
        let mut mutators = mutators.to_vec();
        mutators.sort_unstable();
        mutators.dedup();
        let only: Vec<Mutator> = mutators
            .iter()
            .copied()
            .filter(|m| m.only_weapon().is_some())
            .collect();
        if only.len() > 1 {
            return Err(format!(
                "choose one weapon mutator, not {}",
                only.iter()
                    .map(|m| m.id())
                    .collect::<Vec<_>>()
                    .join(" and ")
            ));
        }
        if mutators.contains(&Mutator::GoldenRail) {
            if mutators.contains(&Mutator::LicenceToKill) {
                return Err(
                    "golden-rail needs one weapon to be special; licence-to-kill makes every hit kill"
                        .into(),
                );
            }
            if let Some(m) = only.first().filter(|m| **m != Mutator::RailOnly) {
                return Err(format!(
                    "golden-rail is a Railgun and cannot run with {}",
                    m.id()
                ));
            }
        }
        if mutators.contains(&Mutator::FullArsenal) {
            if mode != GameMode::Ffa {
                return Err(format!(
                    "full-arsenal changes the free-for-all start; {} keeps its own kit",
                    mode.id()
                ));
            }
            if let Some(m) = only
                .first()
                .or(mutators.iter().find(|m| **m == Mutator::GoldenRail))
            {
                return Err(format!(
                    "{} already sets the starting weapons; drop full-arsenal",
                    m.id()
                ));
            }
        }
        if friendly_fire && !mode.teams() {
            return Err("friendly fire needs a team mode".into());
        }
        if mode == GameMode::Conquest && mutators.contains(&Mutator::TwoLives) {
            return Err("conquest requires ticket-governed respawns".into());
        }
        if mode == GameMode::Ctf && mutators.contains(&Mutator::TwoLives) {
            return Err("two-lives would let elimination decide a capture the flag round".into());
        }
        if mode == GameMode::Sabotage && mutators.contains(&Mutator::TwoLives) {
            return Err(
                "sabotage already gives one life per round; two-lives contradicts it".into(),
            );
        }
        Ok(Self {
            mode,
            mutators,
            friendly_fire,
        })
    }

    /// The `full-arsenal` free-for-all, for fixtures that measure the arcade
    /// guns rather than the start kit.
    #[cfg(test)]
    pub(crate) fn arsenal() -> Self {
        Self::new(GameMode::Ffa, &[Mutator::FullArsenal], false)
            .expect("full-arsenal free-for-all is valid")
    }

    pub fn mode(&self) -> GameMode {
        self.mode
    }

    pub fn mutators(&self) -> &[Mutator] {
        &self.mutators
    }

    pub fn has(&self, mutator: Mutator) -> bool {
        self.mutators.contains(&mutator)
    }

    pub fn teams(&self) -> bool {
        self.mode.teams()
    }

    pub fn friendly_fire(&self) -> bool {
        self.friendly_fire
    }

    /// Plain free-for-all: what every server ran before rule sets.
    pub fn is_plain(&self) -> bool {
        *self == Self::default()
    }

    pub fn only_weapon(&self) -> Option<WeaponType> {
        self.mutators.iter().find_map(|m| m.only_weapon())
    }

    /// Lives per fighter per round, None when unlimited.
    pub fn lives(&self) -> Option<u8> {
        if self.mode == GameMode::Sabotage {
            return Some(1);
        }
        self.has(Mutator::TwoLives).then_some(TWO_LIVES)
    }

    pub fn name(&self) -> String {
        if self.mutators.is_empty() {
            return self.mode.name().to_string();
        }
        let twists: Vec<&str> = self.mutators.iter().map(|m| m.name()).collect();
        format!("{}: {}", self.mode.name(), twists.join(", "))
    }

    /// What a fresh life holds on an arena map under these rules. Campaign
    /// maps carry their own equipment and never ask.
    pub fn start_kit(&self, sabotage: &SabotageConfig) -> StartKit {
        if self.mode == GameMode::Sabotage && sabotage.five_vs_five {
            return StartKit::Found { sidearm: true };
        }
        if let Some(weapon) = self.only_weapon() {
            return StartKit::Only(weapon);
        }
        match self.mode {
            GameMode::Sabotage => StartKit::Found { sidearm: false },
            GameMode::Ffa if !self.has(Mutator::GoldenRail) && !self.has(Mutator::FullArsenal) => {
                StartKit::Found { sidearm: true }
            }
            _ => StartKit::Arsenal,
        }
    }

    /// Ticks until a claimed pad returns, by what it holds. `None` for kinds
    /// whose clock does not depend on the rule sheet.
    pub fn pad_respawn_ticks(
        &self,
        weapon: Option<WeaponType>,
        health_or_armor: bool,
    ) -> Option<u32> {
        if self.teams() {
            return weapon.map(|_| TEAM_WEAPON_RESPAWN_TICKS);
        }
        if health_or_armor {
            return Some(FFA_HEALTH_ARMOR_RESPAWN_TICKS);
        }
        weapon.map(|weapon| match weapon {
            WeaponType::Tack => FFA_SIDEARM_RESPAWN_TICKS,
            WeaponType::Rail | WeaponType::Sniper | WeaponType::Arc | WeaponType::Rocket => {
                FFA_POWER_WEAPON_RESPAWN_TICKS
            }
            _ => FFA_WEAPON_RESPAWN_TICKS,
        })
    }

    pub fn wire(&self, sabotage: &SabotageConfig) -> MatchRules {
        MatchRules {
            mode: self.mode,
            name: self.name(),
            mutators: self.mutators.clone(),
            friendly_fire: self.friendly_fire,
            lives: self.lives(),
            start_kit: self.start_kit(sabotage).weapons(),
        }
    }

    /// Ticks between an arcade death and the respawn attempt. Elimination
    /// (out of lives) never uses it; campaign maps use
    /// [`CAMPAIGN_RESPAWN_DELAY_TICKS`] instead (see `GameState`).
    pub fn respawn_delay_ticks(&self) -> u32 {
        match self.mode {
            GameMode::Ffa => FFA_RESPAWN_DELAY_TICKS,
            GameMode::Tdm | GameMode::Ctf | GameMode::Sabotage | GameMode::Conquest => {
                TEAM_RESPAWN_DELAY_TICKS
            }
        }
    }

    /// The frag limit a host gets without naming one.
    pub fn default_frag_limit(&self) -> u32 {
        if self.teams() {
            TEAM_FRAG_LIMIT
        } else {
            10
        }
    }
}

/// What every fresh arena life holds. "Nothing is issued, everything is
/// liberated": in free-for-all that is the Pistol and Fists, and every
/// stronger gun is owned only after its pad is taken.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StartKit {
    /// A weapon-only mutator: that one weapon, unlimited, nothing to find.
    Only(WeaponType),
    /// Rifle, Shotgun and Railgun at spawn; weapon pads restock them.
    Arsenal,
    /// Owned equipment: Fists, plus the Pistol and its fifty Bullets when
    /// `sidearm`. Pads grant the guns.
    Found { sidearm: bool },
}

impl StartKit {
    /// The weapons a fresh life can select, in wire order.
    pub fn weapons(self) -> Vec<WeaponType> {
        match self {
            Self::Only(weapon) => vec![weapon],
            Self::Arsenal => WeaponType::ALL
                .into_iter()
                .filter(|weapon| WeaponType::ARCADE.contains(weapon))
                .collect(),
            Self::Found { sidearm } => {
                let mut weapons = vec![WeaponType::Fists];
                if sidearm {
                    weapons.push(WeaponType::Tack);
                }
                weapons
            }
        }
    }

    /// The weapon a fresh life holds.
    pub fn selected(self) -> WeaponType {
        match self {
            Self::Only(weapon) => weapon,
            Self::Arsenal => WeaponType::default(),
            Self::Found { sidearm: true } => WeaponType::Tack,
            Self::Found { sidearm: false } => WeaponType::Fists,
        }
    }

    pub fn policy(self) -> EquipmentPolicy {
        match self {
            Self::Only(_) | Self::Arsenal => EquipmentPolicy::FullArsenal,
            Self::Found { .. } => EquipmentPolicy::Discovery,
        }
    }
}

/// The side a joiner takes: the smaller one, then the one behind on frags,
/// then the coalition. Humans, agents and rule bots all come through here.
pub fn choose_team(counts: [usize; 2], scores: TeamScores) -> Team {
    let [union, coalition] = counts;
    if union != coalition {
        return if union < coalition {
            Team::Union
        } else {
            Team::Coalition
        };
    }
    match scores.leader() {
        Some(leader) => leader.other(),
        None => Team::Coalition,
    }
}

/// Which half of the map a spawn point belongs to. The Union holds negative
/// X and the coalition positive X; a point on the line belongs to neither.
pub fn spawn_side(x: f32) -> Option<Team> {
    if x < -0.5 {
        Some(Team::Union)
    } else if x > 0.5 {
        Some(Team::Coalition)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_rules_are_the_old_free_for_all() {
        let plain = RuleSet::default();
        assert!(plain.is_plain());
        assert_eq!(plain.name(), "Free-for-all");
        assert_eq!(plain.lives(), None);
        assert_eq!(plain.only_weapon(), None);
        assert_eq!(plain.default_frag_limit(), 10);
        assert!(!RuleSet::new(GameMode::Tdm, &[], false).unwrap().is_plain());
    }

    #[test]
    fn mutators_sort_dedupe_and_name_themselves() {
        let rules = RuleSet::new(
            GameMode::Tdm,
            &[Mutator::TwoLives, Mutator::RailOnly, Mutator::TwoLives],
            true,
        )
        .unwrap();
        assert_eq!(rules.mutators(), &[Mutator::RailOnly, Mutator::TwoLives]);
        assert_eq!(rules.name(), "Team Deathmatch: Rail Only, Two Lives");
        assert_eq!(rules.only_weapon(), Some(WeaponType::Rail));
        assert_eq!(rules.lives(), Some(2));
        assert_eq!(rules.default_frag_limit(), TEAM_FRAG_LIMIT);
        let wire = rules.wire(&SabotageConfig::default());
        assert!(wire.friendly_fire);
        assert_eq!(wire.lives, Some(2));
    }

    #[test]
    fn contradictory_rules_refuse_to_start() {
        for bad in [
            vec![Mutator::RailOnly, Mutator::FistsOnly],
            vec![Mutator::GoldenRail, Mutator::LicenceToKill],
            vec![Mutator::GoldenRail, Mutator::ShotgunOnly],
            vec![Mutator::GoldenRail, Mutator::FistsOnly],
        ] {
            assert!(RuleSet::new(GameMode::Ffa, &bad, false).is_err(), "{bad:?}");
        }
        assert!(RuleSet::new(GameMode::Ffa, &[], true).is_err());
        assert!(RuleSet::new(GameMode::Ctf, &[Mutator::TwoLives], false).is_err());
        assert!(RuleSet::new(GameMode::Sabotage, &[Mutator::TwoLives], false).is_err());
        let sabotage = RuleSet::new(
            GameMode::Sabotage,
            &[Mutator::LicenceToKill, Mutator::RailOnly],
            true,
        )
        .unwrap();
        assert_eq!(sabotage.lives(), Some(1));
        assert!(sabotage.teams() && sabotage.friendly_fire());
        assert!(GameMode::Sabotage.objective() && !GameMode::Tdm.objective());
        assert!(RuleSet::new(
            GameMode::Ffa,
            &[Mutator::GoldenRail, Mutator::RailOnly],
            false
        )
        .is_ok());
    }

    #[test]
    fn joiners_fill_the_short_side_then_the_losing_side() {
        let level = TeamScores::default();
        assert_eq!(choose_team([2, 1], level), Team::Coalition);
        assert_eq!(choose_team([1, 2], level), Team::Union);
        assert_eq!(choose_team([1, 1], level), Team::Coalition);
        let union_ahead = TeamScores {
            union: 3,
            coalition: 1,
        };
        assert_eq!(choose_team([2, 2], union_ahead), Team::Coalition);
        let coalition_ahead = TeamScores {
            union: 0,
            coalition: 5,
        };
        assert_eq!(choose_team([2, 2], coalition_ahead), Team::Union);
    }

    #[test]
    fn spawn_halves_split_on_x() {
        assert_eq!(spawn_side(-10.0), Some(Team::Union));
        assert_eq!(spawn_side(10.0), Some(Team::Coalition));
        assert_eq!(spawn_side(0.0), None);
    }
}
