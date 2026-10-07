//! Intent and the local controller. A `Plan` is what the brain (or the local
//! rules standing in for it) wants for the next second or so. `micro_action`
//! turns the plan into a wire action on every tick from the latest snapshot,
//! so aim, spacing, and fire never wait on the network.

use crate::telemetry::{Telemetry, NEAR_PAD_UNITS};
use fragr_server::navigation::Navigation;
use fragr_server::protocol::{Action, LookAt, Snapshot, WeaponType};
use fragr_server::sim::PLAYER_FLOOR_Y;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Stop closing in when this near the target.
pub const CLOSE_RANGE: f32 = 3.0;
/// Back away while kiting inside this distance.
pub const KITE_RANGE: f32 = 8.0;
/// Push when the enemy is inside this distance; hold beyond it.
pub const PUSH_RANGE: f32 = 25.0;
/// Only a nearby exposed guard interrupts authored campaign traversal.
pub const CAMPAIGN_ENGAGE_RANGE: f32 = 20.0;
/// An awake guard is answered out to the distance a campaign enemy can see a
/// participant. Sweepers fire from 24 metres; an agent that only answered at
/// 20 stood in the open until it died.
pub const CAMPAIGN_THREAT_RANGE: f32 = 32.0;
/// Stop closing in once a visible target is this share of the held weapon's
/// reach away, and shoot from there instead of routing past it.
pub const CAMPAIGN_HOLD_SHARE: f32 = 0.75;
/// Head for health below this HP when a pad is available.
pub const LOW_HP: i32 = 40;
/// Prefer scatter inside this distance.
pub const SCATTER_RANGE: f32 = 10.0;
/// Prefer rail beyond this distance.
pub const RAIL_RANGE: f32 = 30.0;
/// Ticks between strafe direction changes while holding or kiting.
pub const STRAFE_PERIOD_TICKS: u64 = 20;

/// What the fighter is trying to do right now.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Stance {
    PushEnemy,
    FallBackHeal,
    HoldAngle,
    KiteDistance,
}

impl Stance {
    pub const ALL: [Stance; 4] = [
        Stance::PushEnemy,
        Stance::FallBackHeal,
        Stance::HoldAngle,
        Stance::KiteDistance,
    ];

    /// The option name the brain chooses between.
    pub fn name(self) -> &'static str {
        match self {
            Stance::PushEnemy => "push_enemy",
            Stance::FallBackHeal => "fall_back_heal",
            Stance::HoldAngle => "hold_angle",
            Stance::KiteDistance => "kite_distance",
        }
    }

    pub fn parse(text: &str) -> Option<Stance> {
        Stance::ALL.into_iter().find(|s| s.name() == text)
    }

    /// The description the brain is given for this option.
    pub fn criteria(self) -> &'static str {
        match self {
            Stance::PushEnemy => {
                "Close in and keep firing. For: we are healthier than the enemy, or the enemy is low. Not for: low health, or heavy incoming damage."
            }
            Stance::FallBackHeal => {
                "Break off toward the health pad. For: low health with a health pad near. Not for: no pad near, or the enemy is low and we are healthy."
            }
            Stance::HoldAngle => {
                "Hold position, strafe, shoot what comes. For: no enemy, or an enemy at far range. Not for: low health with a pad near, or an enemy close."
            }
            Stance::KiteDistance => {
                "Back away while firing. For: a close enemy with a shotgun while we hold a longer weapon. Not for: we hold the shotgun ourselves, or the enemy is far."
            }
        }
    }
}

/// Where the current plan came from; reported so a run can be audited.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Source {
    /// Nothing decided yet.
    Initial,
    /// Local rules by choice (`--provider local`).
    Local,
    /// The remote brain answered with enough confidence.
    Remote,
    /// The remote brain answered below the confidence floor; local rules used.
    LowConfidence,
    /// The remote call failed or timed out; local rules used.
    Failure,
    /// A spend cap stopped the call; local rules used.
    Budget,
}

/// The macro intent for the next stretch of play.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Plan {
    pub stance: Stance,
    /// Swap to this weapon; `None` keeps the current one.
    pub weapon: Option<WeaponType>,
    /// 1 (safe) to 5 (dying).
    pub danger: u8,
    /// Confidence reported by the brain, or 1.0 for local rules.
    pub confidence: f64,
    pub source: Source,
}

impl Default for Plan {
    fn default() -> Self {
        Plan {
            stance: Stance::HoldAngle,
            weapon: None,
            danger: 1,
            confidence: 0.0,
            source: Source::Initial,
        }
    }
}

/// Parse a wire weapon name (`flechette`, `Rail`, ...).
pub fn parse_weapon(name: &str) -> Option<WeaponType> {
    match name.to_ascii_lowercase().as_str() {
        "fists" => Some(WeaponType::Fists),
        "shiv" => Some(WeaponType::Shiv),
        "tack" => Some(WeaponType::Tack),
        "flechette" => Some(WeaponType::Flechette),
        "rail" => Some(WeaponType::Rail),
        "scatter" => Some(WeaponType::Scatter),
        "sniper" => Some(WeaponType::Sniper),
        "repeater" => Some(WeaponType::Repeater),
        _ => None,
    }
}

pub fn weapon_name(weapon: WeaponType) -> &'static str {
    match weapon {
        WeaponType::Fists => "fists",
        WeaponType::Shiv => "shiv",
        WeaponType::Tack => "tack",
        WeaponType::Flechette => "flechette",
        WeaponType::Rail => "rail",
        WeaponType::Scatter => "scatter",
        WeaponType::Sniper => "sniper",
        WeaponType::Repeater => "repeater",
    }
}

/// The weapon local rules would hold at this distance.
pub fn weapon_for_distance(dist: f32) -> WeaponType {
    if dist < SCATTER_RANGE {
        WeaponType::Scatter
    } else if dist > RAIL_RANGE {
        WeaponType::Rail
    } else {
        WeaponType::Flechette
    }
}

/// Local rules: the plan the fighter follows when the brain is absent, slow,
/// unsure, or out of budget. Deterministic in the telemetry.
pub fn fallback_plan(t: &Telemetry, source: Source) -> Plan {
    let current = parse_weapon(&t.weapon);
    let (stance, danger, weapon) = match &t.enemy {
        _ if t.hp < LOW_HP && t.health_pad.is_some() => (Stance::FallBackHeal, 4, None),
        Some(enemy)
            if enemy.dist < KITE_RANGE
                && enemy.weapon == "scatter"
                && current != Some(WeaponType::Scatter) =>
        {
            (
                Stance::KiteDistance,
                3,
                Some(weapon_for_distance(enemy.dist)),
            )
        }
        Some(enemy) if enemy.dist < PUSH_RANGE => (
            Stance::PushEnemy,
            if t.under_fire { 3 } else { 2 },
            Some(weapon_for_distance(enemy.dist)),
        ),
        Some(enemy) => (Stance::HoldAngle, 1, Some(weapon_for_distance(enemy.dist))),
        None => (Stance::HoldAngle, 1, None),
    };
    Plan {
        stance,
        weapon: weapon.filter(|w| Some(*w) != current),
        danger,
        confidence: 1.0,
        source,
    }
}

fn strafe(tick: u64) -> (bool, bool) {
    if (tick / STRAFE_PERIOD_TICKS).is_multiple_of(2) {
        (true, false)
    } else {
        (false, true)
    }
}

/// Every tick: turn the plan into a wire action from the latest snapshot.
pub fn micro_action(plan: &Plan, me: Uuid, snapshot: &Snapshot) -> Action {
    micro_action_with_visibility(plan, me, snapshot, |_, _| true, |_, _| true)
}

/// Arena CTF uses local route intent at tick rate. A decision model can still
/// choose equipment and stance, but cannot override objective ownership.
pub fn ctf_micro_action(plan: &Plan, me: Uuid, snapshot: &Snapshot) -> Action {
    ctf_micro_action_with_visibility(plan, me, snapshot, |_, _| true)
}

/// The live brain uses the validated map when deciding whether combat can
/// interrupt a flag route. The server remains the authority for shot outcomes.
pub fn ctf_micro_action_in_world(
    plan: &Plan,
    me: Uuid,
    snapshot: &Snapshot,
    world: &Navigation,
) -> Action {
    ctf_micro_action_with_visibility(plan, me, snapshot, |mine, other| {
        target_visible(world, mine, other)
    })
}

fn ctf_micro_action_with_visibility(
    plan: &Plan,
    me: Uuid,
    snapshot: &Snapshot,
    visible: impl Fn(&fragr_server::protocol::PlayerState, &fragr_server::protocol::PlayerState) -> bool,
) -> Action {
    let Some(flags) = snapshot.flags.as_ref() else {
        return micro_action(plan, me, snapshot);
    };
    let Some(mine) = snapshot.players.iter().find(|p| p.id == me && p.hp > 0) else {
        return Action::default();
    };
    let Some(team) = mine.team else {
        return Action::default();
    };
    let own = &flags[team.index()];
    let enemy = &flags[team.other().index()];
    let carrying = enemy.carrier == Some(me);
    // Side comes from the server, never from a callsign or display chip.
    // These stance chips are accepted only from external agents; rule bots
    // have separate chips and humans cannot publish one. They advertise this
    // controller's coordination contract without assuming every teammate
    // follows it. Our own identity is known even before its first chip echo.
    let compatible = |p: &fragr_server::protocol::PlayerState| {
        p.id == me || p.behavior.as_deref().and_then(Stance::parse).is_some()
    };
    let coordinated = snapshot
        .players
        .iter()
        .filter(|p| p.team == Some(team) && compatible(p))
        .count()
        >= 3;
    let mut eligible: Vec<_> = snapshot
        .players
        .iter()
        .filter(|p| {
            p.team == Some(team) && compatible(p) && p.hp > 0 && enemy.carrier != Some(p.id)
        })
        .map(|p| p.id)
        .collect();
    eligible.sort_unstable();
    let defending = coordinated && eligible.first() == Some(&me);
    let carrier = enemy.carrier.and_then(|id| {
        snapshot
            .players
            .iter()
            .find(|p| p.id == id && p.team == Some(team) && p.hp > 0)
    });
    let escorting = coordinated && carrier.is_some() && eligible.get(1) == Some(&me);
    let recovering = own.status == fragr_server::protocol::FlagStatus::Dropped;
    if carrying && (!coordinated || eligible.is_empty()) {
        if let Some(thief) = own.carrier.and_then(|id| {
            snapshot
                .players
                .iter()
                .find(|p| p.id == id && mine.is_hostile_to(p) && visible(mine, p))
        }) {
            let distance = (thief.x - mine.x).hypot(thief.z - mine.z);
            let weapon = plan
                .weapon
                .or_else(|| parse_weapon(&mine.weapon))
                .unwrap_or_default();
            return Action {
                forward: distance > 1.5,
                fire: distance <= weapon.range_units(),
                look_at: Some(LookAt {
                    player_id: Some(thief.id),
                    ..LookAt::default()
                }),
                weapon_swap: plan.weapon,
                ..Action::default()
            };
        }
    }
    let nearby_threat = |from: &fragr_server::protocol::PlayerState,
                         other: &fragr_server::protocol::PlayerState| {
        !carrying
            && from.is_hostile_to(other)
            && (other.x - from.x).hypot(other.z - from.z) < 12.0
            && visible(from, other)
            && (!defending || !recovering)
            && (!defending || own.carrier.is_none_or(|id| other.id == id))
            && (!escorting
                || carrier.is_some_and(|ally| {
                    (ally.x - from.x).hypot(ally.z - from.z) <= 6.0
                        && (other.x - ally.x).hypot(other.z - ally.z) < 12.0
                }))
    };
    if snapshot
        .players
        .iter()
        .any(|other| nearby_threat(mine, other))
    {
        let mut action =
            micro_action_with_visibility(plan, me, snapshot, nearby_threat, |_, _| true);
        if escorting
            && action
                .look_at
                .as_ref()
                .is_some_and(|aim| aim.player_id.is_some())
        {
            action.forward = false;
            action.back = false;
            action.left = false;
            action.right = false;
        }
        return action;
    }
    let goal = if carrying && coordinated && !eligible.is_empty() {
        // Scoring waits for the home flag. The carrier keeps its safe return
        // position while the defender handles recovery, rather than chasing.
        own.stand
    } else if carrying {
        if recovering {
            own.position
        } else {
            own.carrier
                .and_then(|id| snapshot.players.iter().find(|p| p.id == id && p.hp > 0))
                .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
                .unwrap_or(own.stand)
        }
    } else if recovering && (defending || !coordinated) {
        own.position
    } else if defending || (!coordinated && own.carrier.is_some()) {
        own.carrier
            .and_then(|id| snapshot.players.iter().find(|p| p.id == id && p.hp > 0))
            .map(|p| [p.x, p.y - fragr_server::sim::PLAYER_FLOOR_Y, p.z])
            .unwrap_or(own.stand)
    } else if escorting {
        let ally = carrier.expect("escort requires a living teammate carrier");
        let dx = ally.x - own.stand[0];
        let dz = ally.z - own.stand[2];
        let distance = dx.hypot(dz);
        let (dx, dz) = if distance > 0.001 {
            (dx / distance, dz / distance)
        } else {
            let x = enemy.stand[0] - own.stand[0];
            let z = enemy.stand[2] - own.stand[2];
            let length = x.hypot(z).max(0.001);
            (x / length, z / length)
        };
        if distance <= 10.0 {
            [
                own.stand[0] + dx * 6.0,
                own.stand[1],
                own.stand[2] + dz * 6.0,
            ]
        } else {
            [
                ally.x + dx * 4.0,
                ally.y - PLAYER_FLOOR_Y,
                ally.z + dz * 4.0,
            ]
        }
    } else if enemy.carrier.is_none() {
        enemy.position
    } else if coordinated {
        enemy.stand
    } else {
        own.stand
    };
    let close = (goal[0] - mine.x).hypot(goal[2] - mine.z) < 1.5;
    Action {
        forward: !close,
        look_at: Some(LookAt {
            x: Some(goal[0]),
            y: Some(goal[1]),
            z: Some(goal[2]),
            player_id: None,
        }),
        weapon_swap: plan.weapon,
        ..Action::default()
    }
}

/// Campaign combat only takes over the mission route for a guard in view.
/// Visibility is an observation; the server still resolves every shot.
pub fn campaign_micro_action(
    plan: &Plan,
    me: Uuid,
    snapshot: &Snapshot,
    world: &Navigation,
) -> Action {
    campaign_micro_action_with_solids(plan, me, snapshot, world, None)
}

pub fn campaign_micro_action_with_solids(
    plan: &Plan,
    me: Uuid,
    snapshot: &Snapshot,
    world: &Navigation,
    solids: Option<&[fragr_server::movement::Solid]>,
) -> Action {
    let mut action = campaign_micro_action_unheld(plan, me, snapshot, world, solids);
    // A guard already in view and within reach is shot from here. Pushing on
    // made the shared router walk a long way round to a guard on a roof or a
    // gallery, with the trigger released for the whole detour.
    if plan.stance == Stance::PushEnemy && action.fire {
        let target = action.look_at.as_ref().and_then(|aim| aim.player_id);
        let mine = snapshot.players.iter().find(|player| player.id == me);
        let other = target.and_then(|id| snapshot.players.iter().find(|player| player.id == id));
        if let (Some(mine), Some(other)) = (mine, other) {
            let held = action
                .weapon_swap
                .or_else(|| parse_weapon(&mine.weapon))
                .unwrap_or_default();
            let distance = (other.x - mine.x).hypot(other.z - mine.z);
            if distance <= held.range_units() * CAMPAIGN_HOLD_SHARE {
                let (left, right) = strafe(snapshot.tick);
                action.forward = false;
                action.left = left;
                action.right = right;
            }
        }
    }
    action
}

fn campaign_micro_action_unheld(
    plan: &Plan,
    me: Uuid,
    snapshot: &Snapshot,
    world: &Navigation,
    solids: Option<&[fragr_server::movement::Solid]>,
) -> Action {
    micro_action_with_visibility(
        plan,
        me,
        snapshot,
        |mine, other| campaign_enemy_engageable_with_solids(world, mine, other, solids),
        |mine, pad| {
            if plan.source != Source::Remote {
                return true;
            }
            if mine.hp >= LOW_HP || (pad.x - mine.x).hypot(pad.z - mine.z) > NEAR_PAD_UNITS {
                return false;
            }
            world.walkable(
                [mine.x, mine.y - PLAYER_FLOOR_Y, mine.z],
                [pad.x, pad.y, pad.z],
            )
        },
    )
}

/// The same immediate target is used for campaign control and decision state.
pub fn campaign_target<'a>(
    me: Uuid,
    snapshot: &'a Snapshot,
    world: &Navigation,
) -> Option<&'a fragr_server::protocol::PlayerState> {
    campaign_target_with_solids(me, snapshot, world, None)
}

pub fn campaign_target_with_solids<'a>(
    me: Uuid,
    snapshot: &'a Snapshot,
    world: &Navigation,
    solids: Option<&[fragr_server::movement::Solid]>,
) -> Option<&'a fragr_server::protocol::PlayerState> {
    let mine = snapshot.players.iter().find(|player| player.id == me)?;
    snapshot
        .players
        .iter()
        .filter(|other| {
            mine.is_hostile_to(other)
                && campaign_enemy_engageable_with_solids(world, mine, other, solids)
        })
        .min_by(|a, b| {
            (a.x - mine.x)
                .hypot(a.z - mine.z)
                .total_cmp(&(b.x - mine.x).hypot(b.z - mine.z))
        })
}

pub fn campaign_enemy_engageable(
    world: &Navigation,
    mine: &fragr_server::protocol::PlayerState,
    other: &fragr_server::protocol::PlayerState,
) -> bool {
    campaign_enemy_engageable_with_solids(world, mine, other, None)
}

pub fn campaign_enemy_engageable_with_solids(
    world: &Navigation,
    mine: &fragr_server::protocol::PlayerState,
    other: &fragr_server::protocol::PlayerState,
    solids: Option<&[fragr_server::movement::Solid]>,
) -> bool {
    let distance = (other.x - mine.x).hypot(other.z - mine.z);
    let reach = if campaign_enemy_awake(other) {
        CAMPAIGN_THREAT_RANGE
    } else {
        CAMPAIGN_ENGAGE_RANGE
    };
    if distance > reach {
        return false;
    }
    target_visible_with_solids(world, mine, other, solids)
}

/// A Union body that has started its own fight: walking, aiming, shooting,
/// recovering or stunned. A quiet idle guard is not yet a threat.
fn campaign_enemy_awake(other: &fragr_server::protocol::PlayerState) -> bool {
    use fragr_server::protocol::{CampaignActor, EnemyPhase};
    matches!(
        other.campaign,
        Some(CampaignActor::Union { phase, .. })
            if !matches!(phase, EnemyPhase::Idle | EnemyPhase::Dead)
    )
}

/// Ticks an agent may stand still with no target before it goes looking.
pub const CAMPAIGN_STALL_TICKS: u64 = 400;
/// How long one search lasts before the agent rechecks its surroundings.
pub const CAMPAIGN_HUNT_TICKS: u64 = 600;

/// A campaign stall breaker. A required group can end with a guard standing
/// out of sight, and the objective then waits for a fight nobody resumes.
/// After standing still with nothing to shoot, the agent walks toward the
/// nearest living Union body it was told about; combat takes over once that
/// guard is in view. Positions come from the ordinary snapshot.
#[derive(Debug, Default, Clone)]
pub struct StallWatch {
    anchor: Option<[f32; 3]>,
    since: u64,
    hunt: Option<(Uuid, u64)>,
}

impl StallWatch {
    /// Adjust one campaign action after the agent's own targeting.
    pub fn apply(&mut self, me: Uuid, snapshot: &Snapshot, mut action: Action) -> Action {
        let Some(mine) = snapshot.players.iter().find(|p| p.id == me && p.hp > 0) else {
            *self = Self::default();
            return action;
        };
        let here = [mine.x, mine.y, mine.z];
        let targeted = action
            .look_at
            .as_ref()
            .is_some_and(|aim| aim.player_id.is_some());
        let moved = self
            .anchor
            .is_none_or(|anchor| (anchor[0] - here[0]).hypot(anchor[2] - here[2]) > 1.0);
        if targeted || moved {
            self.anchor = Some(here);
            self.since = snapshot.tick;
        }
        if targeted {
            self.hunt = None;
            return action;
        }
        let living = |id: Uuid| {
            snapshot
                .players
                .iter()
                .any(|p| p.id == id && p.hp > 0 && mine.is_hostile_to(p))
        };
        if self
            .hunt
            .is_some_and(|(id, until)| snapshot.tick > until || !living(id))
        {
            self.hunt = None;
            self.anchor = Some(here);
            self.since = snapshot.tick;
        }
        if self.hunt.is_none() && snapshot.tick.saturating_sub(self.since) >= CAMPAIGN_STALL_TICKS {
            self.hunt = snapshot
                .players
                .iter()
                .filter(|p| p.hp > 0 && mine.is_hostile_to(p))
                .min_by(|a, b| {
                    (a.x - mine.x)
                        .hypot(a.z - mine.z)
                        .total_cmp(&(b.x - mine.x).hypot(b.z - mine.z))
                })
                .map(|p| (p.id, snapshot.tick + CAMPAIGN_HUNT_TICKS));
        }
        if let Some((id, _)) = self.hunt {
            action.look_at = Some(LookAt {
                player_id: Some(id),
                x: None,
                y: None,
                z: None,
            });
            action.forward = true;
            action.fire = false;
        }
        action
    }

    pub fn hunting(&self) -> Option<Uuid> {
        self.hunt.map(|(id, _)| id)
    }
}

/// Actor geometry visibility without a mode's separate engagement radius.
pub fn target_visible(
    world: &Navigation,
    mine: &fragr_server::protocol::PlayerState,
    other: &fragr_server::protocol::PlayerState,
) -> bool {
    target_visible_with_solids(world, mine, other, None)
}

fn target_visible_with_solids(
    world: &Navigation,
    mine: &fragr_server::protocol::PlayerState,
    other: &fragr_server::protocol::PlayerState,
    solids: Option<&[fragr_server::movement::Solid]>,
) -> bool {
    let eye = [
        mine.x,
        mine.y - PLAYER_FLOOR_Y + fragr_server::movement::EYE_HEIGHT,
        mine.z,
    ];
    let center = [
        other.x,
        other.y - PLAYER_FLOOR_Y + fragr_server::combat::aim_height(other.campaign),
        other.z,
    ];
    solids.map_or_else(
        || world.line_of_sight(eye, center),
        |solids| fragr_server::combat::line_of_sight(eye, center, solids),
    )
}

fn micro_action_with_visibility(
    plan: &Plan,
    me: Uuid,
    snapshot: &Snapshot,
    visible: impl Fn(&fragr_server::protocol::PlayerState, &fragr_server::protocol::PlayerState) -> bool,
    heal_pad: impl Fn(
        &fragr_server::protocol::PlayerState,
        &fragr_server::protocol::PickupState,
    ) -> bool,
) -> Action {
    let Some(mine) = snapshot.players.iter().find(|p| p.id == me) else {
        return Action::default();
    };
    let held = parse_weapon(&mine.weapon).unwrap_or_default();
    let weapon_swap = plan.weapon.filter(|w| *w != held);
    let fire_range = weapon_swap.unwrap_or(held).range_units();
    let mut nearest: Option<(f32, Uuid, f32, f32)> = None;
    let mut nearest_key = (true, f32::MAX);
    for other in &snapshot.players {
        if !mine.is_hostile_to(other) || !visible(mine, other) {
            continue;
        }
        let dist = ((other.x - mine.x).powi(2) + (other.z - mine.z).powi(2)).sqrt();
        // A channeling Auditor comes first: break the repair before it lands.
        let key = fragr_server::combat::engagement_key(other.campaign, dist);
        if nearest.is_none() || fragr_server::combat::engagement_before(key, nearest_key) {
            nearest = Some((dist, other.id, other.x, other.z));
            nearest_key = key;
        }
    }
    let (left, right) = strafe(snapshot.tick);
    let mut action = Action {
        weapon_swap,
        ..Action::default()
    };
    if plan.stance == Stance::FallBackHeal {
        let pad = snapshot
            .pickups
            .iter()
            .filter(|p| p.available && p.kind == "health" && heal_pad(mine, p))
            .map(|p| {
                let dist = ((p.x - mine.x).powi(2) + (p.z - mine.z).powi(2)).sqrt();
                (dist, p.x, p.z)
            })
            .min_by(|a, b| a.0.total_cmp(&b.0));
        if let Some((dist, x, z)) = pad {
            action.look_at = Some(LookAt {
                y: None,
                x: Some(x),
                z: Some(z),
                player_id: None,
            });
            action.forward = dist > 1.0;
            return action;
        }
        // No pad to run to: behave like a kiter.
    }
    let Some((dist, target, _, _)) = nearest else {
        return action;
    };
    action.look_at = Some(LookAt {
        y: None,
        player_id: Some(target),
        x: None,
        z: None,
    });
    action.fire = dist <= fire_range;
    match plan.stance {
        Stance::PushEnemy => {
            action.forward = dist > CLOSE_RANGE;
        }
        Stance::HoldAngle => {
            action.left = left;
            action.right = right;
        }
        Stance::KiteDistance | Stance::FallBackHeal => {
            action.back = dist < KITE_RANGE;
            action.left = left;
            action.right = right;
        }
    }
    action
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::telemetry::fixtures::{pad, player, snapshot};
    use crate::telemetry::{observe, RecentHits};
    use fragr_server::movement::{Arena, Solid};

    fn telemetry_for(snapshot: &Snapshot, me: Uuid) -> Telemetry {
        let mut hits = RecentHits::default();
        observe(me, snapshot, &mut hits).unwrap()
    }

    #[test]
    fn campaign_plans_and_micro_control_ignore_allies_and_dead_guards() {
        use fragr_server::protocol::{CampaignActor, EnemyKind, EnemyPhase};
        let me = Uuid::from_u128(1);
        let ally = Uuid::from_u128(2);
        let foe = Uuid::from_u128(3);
        let mut mine = player("me", me, 0.0, 0.0, 100, "tack");
        mine.campaign = Some(CampaignActor::Participant {});
        let mut partner = player("partner", ally, 1.0, 0.0, 100, "tack");
        partner.campaign = mine.campaign;
        let mut guard = player("clerk", foe, 8.0, 0.0, 60, "tack");
        guard.campaign = Some(CampaignActor::Union {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        });
        let mut snap = snapshot(1, vec![mine, partner, guard], vec![]);
        let telemetry = telemetry_for(&snap, me);
        assert_eq!(telemetry.enemy.as_ref().unwrap().id, foe);
        let plan = fallback_plan(&telemetry, Source::Local);
        assert_eq!(
            micro_action(&plan, me, &snap).look_at.unwrap().player_id,
            Some(foe)
        );
        snap.players[2].hp = 0;
        assert!(telemetry_for(&snap, me).enemy.is_none());
        let action = micro_action(&plan, me, &snap);
        assert!(!action.fire && action.look_at.is_none());
    }

    #[test]
    fn hidden_guard_does_not_block_mission_but_visible_guard_does() {
        use fragr_server::protocol::{
            AmmoCount, AmmoPool, CampaignActor, EnemyKind, EnemyPhase, LoadoutState,
        };
        let me = Uuid::from_u128(1);
        let hidden = Uuid::from_u128(2);
        let visible = Uuid::from_u128(3);
        let mut mine = player("me", me, 0.0, 0.0, 100, "tack");
        mine.campaign = Some(CampaignActor::Participant {});
        let mut guard = player("hidden", hidden, 10.0, 0.0, 60, "tack");
        guard.campaign = Some(CampaignActor::Union {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        });
        let world = Navigation::new(Arena {
            half: 24.0,
            solids: vec![Solid::from_center(5.0, 0.0, 0.5, 3.0)],
        })
        .unwrap();
        let plan = Plan {
            stance: Stance::PushEnemy,
            ..Plan::default()
        };
        let mut snap = snapshot(1, vec![mine, guard.clone()], vec![]);
        let blocked = campaign_micro_action(&plan, me, &snap, &world);
        assert!(blocked.look_at.is_none() && !blocked.fire);
        let moved_cover = [Solid::from_center(5.0, 8.0, 0.5, 3.0)];
        let exposed =
            campaign_micro_action_with_solids(&plan, me, &snap, &world, Some(&moved_cover));
        assert!(exposed.fire);
        assert_eq!(exposed.look_at.unwrap().player_id, Some(hidden));
        assert_eq!(
            campaign_target_with_solids(me, &snap, &world, Some(&moved_cover))
                .unwrap()
                .id,
            hidden
        );
        let returned_cover = [Solid::from_center(5.0, 0.0, 0.5, 3.0)];
        assert!(campaign_target_with_solids(me, &snap, &world, Some(&returned_cover)).is_none());
        assert!(
            !campaign_micro_action_with_solids(&plan, me, &snap, &world, Some(&returned_cover))
                .fire
        );
        let loadout = LoadoutState {
            player_id: me,
            tick: 1,
            selected: WeaponType::Tack,
            weapons: vec![WeaponType::Fists, WeaponType::Tack],
            // Six bullets, the magazine-era fixture's loaded rounds.
            ammo: AmmoPool::ALL
                .into_iter()
                .map(|pool| AmmoCount {
                    pool,
                    rounds: if pool == AmmoPool::Bullets { 6 } else { 0 },
                })
                .collect(),
            personal_claims: vec![],
            dry_fire_count: 0,
            grenades: 0,
            proximity_mines: 0,
            loaded: Vec::new(),
            remote_mines: 0,
        };
        let through_inventory = |snap: &Snapshot| {
            fragr_server::inventory::control_action_with_target_filter(
                me,
                snap,
                Some(&loadout),
                campaign_micro_action(&plan, me, snap, &world),
                true,
                |mine, other| campaign_enemy_engageable(&world, mine, other),
            )
        };
        assert!(through_inventory(&snap).look_at.is_none());
        assert!(campaign_target(me, &snap, &world).is_none());
        assert_eq!(
            micro_action(&plan, me, &snap).look_at.unwrap().player_id,
            Some(hidden)
        );
        guard.id = visible;
        guard.z = 8.0;
        snap.players.push(guard);
        let action = campaign_micro_action(&plan, me, &snap, &world);
        assert_eq!(action.look_at.unwrap().player_id, Some(visible));
        assert!(action.fire);
        assert_eq!(
            through_inventory(&snap).look_at.unwrap().player_id,
            Some(visible)
        );
        assert_eq!(campaign_target(me, &snap, &world).unwrap().id, visible);
        snap.players[2].x = 24.0;
        snap.players[2].z = 20.0;
        assert!(through_inventory(&snap).look_at.is_none());
    }

    #[test]
    fn campaign_answers_an_awake_guard_out_to_its_sight_and_holds_to_shoot() {
        use fragr_server::protocol::{CampaignActor, EnemyKind, EnemyPhase};
        let me = Uuid::from_u128(1);
        let foe = Uuid::from_u128(2);
        let mut mine = player("me", me, 0.0, 0.0, 100, "flechette");
        mine.campaign = Some(CampaignActor::Participant {});
        let guard_in = |phase: EnemyPhase, x: f32| {
            let mut guard = player("sweeper", foe, x, 0.0, 80, "flechette");
            guard.campaign = Some(CampaignActor::Union {
                kind: EnemyKind::Sweeper,
                phase,
                phase_started: 0,
                phase_ends: 0,
                seated: false,
            });
            guard
        };
        let world = Navigation::new(Arena {
            half: 48.0,
            solids: vec![],
        })
        .unwrap();
        // The M06 Railgun lane: a Sweeper firing from 24 metres used to
        // outrange the agent's 20 metre engagement and won every time.
        let firing = snapshot(
            1,
            vec![mine.clone(), guard_in(EnemyPhase::Windup, 24.0)],
            vec![],
        );
        assert_eq!(campaign_target(me, &firing, &world).unwrap().id, foe);
        let idle = snapshot(
            1,
            vec![mine.clone(), guard_in(EnemyPhase::Idle, 24.0)],
            vec![],
        );
        assert!(
            campaign_target(me, &idle, &world).is_none(),
            "a quiet distant guard still does not interrupt the route"
        );
        let beyond = snapshot(
            1,
            vec![mine.clone(), guard_in(EnemyPhase::Firing, 33.0)],
            vec![],
        );
        assert!(campaign_target(me, &beyond, &world).is_none());

        // A visible guard within reach is shot from where the agent stands.
        let push = Plan {
            stance: Stance::PushEnemy,
            ..Plan::default()
        };
        let held = campaign_micro_action(&push, me, &firing, &world);
        assert!(
            held.fire && !held.forward,
            "hold and shoot at 24 metres with a Rifle"
        );
        assert_eq!(held.look_at.unwrap().player_id, Some(foe));
        let far = snapshot(1, vec![mine, guard_in(EnemyPhase::Moving, 31.0)], vec![]);
        let closing = campaign_micro_action(&push, me, &far, &world);
        assert!(
            closing.forward,
            "beyond three quarters of the Rifle's reach the agent still closes"
        );
    }

    #[test]
    fn stalled_campaign_agent_goes_looking_for_the_nearest_hidden_guard() {
        use fragr_server::protocol::{CampaignActor, EnemyKind, EnemyPhase};
        let me = Uuid::from_u128(1);
        let near = Uuid::from_u128(2);
        let far = Uuid::from_u128(3);
        let mut mine = player("me", me, -13.0, 35.5, 100, "flechette");
        mine.campaign = Some(CampaignActor::Participant {});
        let guard = |id: Uuid, x: f32, z: f32| {
            let mut guard = player("guard", id, x, z, 60, "tack");
            guard.campaign = Some(CampaignActor::Union {
                kind: EnemyKind::Clerk,
                phase: EnemyPhase::Idle,
                phase_started: 0,
                phase_ends: 0,
                seated: false,
            });
            guard
        };
        let at = |tick: u64, players| {
            let mut snap = snapshot(1, players, vec![]);
            snap.tick = tick;
            snap
        };
        let players = vec![
            mine.clone(),
            guard(near, 10.0, 24.5),
            guard(far, 30.0, -30.0),
        ];
        let mut watch = StallWatch::default();
        let idle = Action::default();
        // Waiting at the locomotive while the last train guard idles out of
        // sight: nothing happens until the stall window passes.
        let early = watch.apply(me, &at(100, players.clone()), idle.clone());
        assert!(early.look_at.is_none() && watch.hunting().is_none());
        let late = watch.apply(
            me,
            &at(100 + CAMPAIGN_STALL_TICKS, players.clone()),
            idle.clone(),
        );
        assert_eq!(late.look_at.unwrap().player_id, Some(near));
        assert!(late.forward && !late.fire);

        // Seeing the guard hands control back to ordinary combat.
        let seen = Action {
            look_at: Some(LookAt {
                player_id: Some(near),
                ..LookAt::default()
            }),
            fire: true,
            ..Action::default()
        };
        let fighting = watch.apply(me, &at(600, players.clone()), seen);
        assert!(fighting.fire && watch.hunting().is_none());

        // A search ends with its time bound and the window starts again.
        let mut moving = mine.clone();
        let mut watch = StallWatch::default();
        watch.apply(me, &at(0, players.clone()), idle.clone());
        watch.apply(me, &at(CAMPAIGN_STALL_TICKS, players.clone()), idle.clone());
        assert_eq!(watch.hunting(), Some(near));
        moving.x += 5.0;
        let mut walked = players.clone();
        walked[0] = moving;
        let expired = CAMPAIGN_STALL_TICKS + CAMPAIGN_HUNT_TICKS + 1;
        assert!(watch
            .apply(me, &at(expired, walked), idle)
            .look_at
            .is_none());
        assert!(watch.hunting().is_none());
    }

    #[test]
    fn campaign_visibility_uses_the_crawlers_low_hit_volume() {
        use fragr_server::protocol::{CampaignActor, EnemyKind, EnemyPhase};
        let me = Uuid::from_u128(1);
        let foe = Uuid::from_u128(2);
        let mut mine = player("me", me, 0.0, 0.0, 100, "tack");
        mine.campaign = Some(CampaignActor::Participant {});
        mine.y = PLAYER_FLOOR_Y;
        let mut guard = player("guard", foe, 10.0, 0.0, 60, "tack");
        guard.y = PLAYER_FLOOR_Y;
        guard.campaign = Some(CampaignActor::Union {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        });
        let world = Navigation::new(Arena {
            half: 24.0,
            solids: vec![Solid::from_center_top(5.0, 0.0, 0.25, 2.0, 1.15)],
        })
        .unwrap();
        assert!(campaign_enemy_engageable(&world, &mine, &guard));
        guard.campaign = Some(CampaignActor::Union {
            kind: EnemyKind::Crawler,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
        });
        assert!(!campaign_enemy_engageable(&world, &mine, &guard));
    }

    #[test]
    fn campaign_health_detour_requires_injury_nearby_pad_and_clear_walk() {
        let me = Uuid::from_u128(1);
        let plan = Plan {
            stance: Stance::FallBackHeal,
            source: Source::Remote,
            ..Plan::default()
        };
        let clear = Navigation::new(Arena {
            half: 24.0,
            solids: vec![],
        })
        .unwrap();
        let blocked = Navigation::new(Arena {
            half: 24.0,
            solids: vec![Solid::from_center(2.0, 0.0, 0.5, 2.0)],
        })
        .unwrap();
        let mut snap = snapshot(
            1,
            vec![player("me", me, 0.0, 0.0, 100, "tack")],
            vec![pad("health", "", 4.0, 0.0, true)],
        );
        snap.players[0].y = PLAYER_FLOOR_Y;
        assert!(campaign_micro_action(&plan, me, &snap, &clear)
            .look_at
            .is_none());
        snap.players[0].hp = 20;
        assert!(campaign_micro_action(&plan, me, &snap, &blocked)
            .look_at
            .is_none());
        let near = campaign_micro_action(&plan, me, &snap, &clear);
        assert_eq!(near.look_at.unwrap().x, Some(4.0));
        assert!(near.forward);
        snap.pickups[0].x = 18.0;
        assert!(campaign_micro_action(&plan, me, &snap, &clear)
            .look_at
            .is_none());
        let local = Plan {
            source: Source::Local,
            ..plan
        };
        assert_eq!(
            campaign_micro_action(&local, me, &snap, &clear)
                .look_at
                .unwrap()
                .x,
            Some(18.0)
        );
    }

    #[test]
    fn healthy_campaign_heal_reply_still_walks_toward_the_record() {
        use fragr_server::maps::AuthoredMap;
        use fragr_server::mission::MissionClient;
        use fragr_server::navigation::Navigator;
        use fragr_server::protocol::{MissionReady, Role};
        use fragr_server::session::GameSession;
        let map = AuthoredMap::read(
            include_bytes!("../../../server/maps/m01-recall-notice.json").as_slice(),
        )
        .unwrap();
        let mut session = GameSession::with_authored_map(map);
        let me = Uuid::from_u128(1);
        session
            .state
            .add_player(me, "Brain".to_string(), Role::Agent);
        let first = session.state.mission_state().unwrap();
        assert!(session.state.acknowledge_mission(
            me,
            MissionReady {
                id: first.id,
                attempt: first.attempt,
            }
        ));
        session.tick_messages(0.05);
        let state = &session.state;
        let mut client = MissionClient::default();
        client
            .replace_map(
                state.map.mission(),
                state.map.arena().half,
                &state.map.arena().solids,
                state.map.presentation_ref(),
            )
            .unwrap();
        client
            .observe(state.tick, state.mission_state().unwrap())
            .unwrap();
        let mut snap = state.snapshot();
        snap.players.retain(|player| player.id == me);
        let mine = &snap.players[0];
        snap.pickups = vec![pad("health", "", mine.x, mine.z, true)];
        let plan = Plan {
            stance: Stance::FallBackHeal,
            source: Source::Remote,
            ..Plan::default()
        };
        let action = campaign_micro_action(&plan, me, &snap, state.map.navigation());
        assert!(action.look_at.is_none());
        let routed = client.steer(
            &mut Navigator::default(),
            state.map.navigation(),
            me,
            &snap,
            action,
        );
        assert!(routed.forward || routed.back || routed.left || routed.right);
        assert!(routed.yaw.is_some());
    }

    #[test]
    fn stance_names_roundtrip_and_have_criteria() {
        for stance in Stance::ALL {
            assert_eq!(Stance::parse(stance.name()), Some(stance));
            assert!(stance.criteria().contains("Not for"));
            let json = serde_json::to_string(&stance).unwrap();
            assert_eq!(json, format!("\"{}\"", stance.name()));
        }
        assert_eq!(Stance::parse("teleport"), None);
        assert_eq!(Plan::default().stance, Stance::HoldAngle);
        assert_eq!(Plan::default().source, Source::Initial);
    }

    #[test]
    fn weapon_helpers() {
        assert_eq!(parse_weapon("Rail"), Some(WeaponType::Rail));
        assert_eq!(parse_weapon("scatter"), Some(WeaponType::Scatter));
        assert_eq!(parse_weapon("FLECHETTE"), Some(WeaponType::Flechette));
        assert_eq!(parse_weapon("bfg"), None);
        for weapon in WeaponType::ALL {
            assert_eq!(parse_weapon(weapon_name(weapon)), Some(weapon));
        }
        assert_eq!(weapon_for_distance(2.0), WeaponType::Scatter);
        assert_eq!(weapon_for_distance(20.0), WeaponType::Flechette);
        assert_eq!(weapon_for_distance(50.0), WeaponType::Rail);
    }

    #[test]
    fn fallback_rules_cover_each_stance() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        // Low HP with a pad: heal.
        let snap = snapshot(
            1,
            vec![
                player("me", me, 0.0, 0.0, 20, "flechette"),
                player("foe", foe, 4.0, 0.0, 90, "scatter"),
            ],
            vec![pad("health", "", 10.0, 0.0, true)],
        );
        let plan = fallback_plan(&telemetry_for(&snap, me), Source::Local);
        assert_eq!(plan.stance, Stance::FallBackHeal);
        assert_eq!(plan.danger, 4);
        assert_eq!(plan.weapon, None);
        assert_eq!(plan.source, Source::Local);
        assert_eq!(plan.confidence, 1.0);
        // Low HP, no pad, scatter enemy in the face: kite.
        let snap = snapshot(
            1,
            vec![
                player("me", me, 0.0, 0.0, 20, "flechette"),
                player("foe", foe, 4.0, 0.0, 90, "scatter"),
            ],
            vec![],
        );
        let plan = fallback_plan(&telemetry_for(&snap, me), Source::Failure);
        assert_eq!(plan.stance, Stance::KiteDistance);
        assert_eq!(plan.weapon, Some(WeaponType::Scatter));
        assert_eq!(plan.source, Source::Failure);
        // Healthy, enemy in push range: push, keep flechette (already held).
        let snap = snapshot(
            1,
            vec![
                player("me", me, 0.0, 0.0, 90, "flechette"),
                player("foe", foe, 15.0, 0.0, 90, "rail"),
            ],
            vec![],
        );
        let plan = fallback_plan(&telemetry_for(&snap, me), Source::Local);
        assert_eq!(plan.stance, Stance::PushEnemy);
        assert_eq!(plan.danger, 2);
        assert_eq!(plan.weapon, None, "already holding the right weapon");
        // Far enemy: hold and swap to rail.
        let snap = snapshot(
            1,
            vec![
                player("me", me, 0.0, 0.0, 90, "flechette"),
                player("foe", foe, 40.0, 0.0, 90, "rail"),
            ],
            vec![],
        );
        let plan = fallback_plan(&telemetry_for(&snap, me), Source::Local);
        assert_eq!(plan.stance, Stance::HoldAngle);
        assert_eq!(plan.weapon, Some(WeaponType::Rail));
        // Alone: hold, no swap.
        let snap = snapshot(1, vec![player("me", me, 0.0, 0.0, 90, "rail")], vec![]);
        let plan = fallback_plan(&telemetry_for(&snap, me), Source::Local);
        assert_eq!(plan.stance, Stance::HoldAngle);
        assert_eq!(plan.weapon, None);
        assert_eq!(plan.danger, 1);
    }

    #[test]
    fn fallback_marks_danger_under_fire() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let snap = snapshot(
            100,
            vec![
                player("me", me, 0.0, 0.0, 90, "flechette"),
                player("foe", foe, 15.0, 0.0, 90, "rail"),
            ],
            vec![],
        );
        let mut hits = RecentHits::default();
        hits.ingest(
            me,
            99,
            &fragr_server::protocol::GameEvent::Hit {
                shooter: "foe".into(),
                shooter_id: foe,
                target: "me".into(),
                target_id: me,
                damage: 10,
                target_hp_after: 90,
            },
        );
        let t = observe(me, &snap, &mut hits).unwrap();
        assert_eq!(fallback_plan(&t, Source::Local).danger, 3);
    }

    #[test]
    fn micro_push_hold_and_kite() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let snap = snapshot(
            0,
            vec![
                player("me", me, 0.0, 0.0, 90, "flechette"),
                player("foe", foe, 10.0, 0.0, 90, "rail"),
            ],
            vec![],
        );
        let push = Plan {
            stance: Stance::PushEnemy,
            weapon: Some(WeaponType::Rail),
            danger: 2,
            confidence: 0.9,
            source: Source::Remote,
        };
        let action = micro_action(&push, me, &snap);
        assert_eq!(action.look_at.as_ref().unwrap().player_id, Some(foe));
        assert!(action.forward);
        assert!(action.fire, "rail reaches 10 units");
        assert_eq!(action.weapon_swap, Some(WeaponType::Rail));
        assert!(!action.left && !action.right && !action.back);

        let hold = Plan {
            stance: Stance::HoldAngle,
            weapon: None,
            ..push.clone()
        };
        let action = micro_action(&hold, me, &snap);
        assert!(!action.forward);
        assert!(action.left && !action.right, "tick 0 strafes left");
        assert_eq!(action.weapon_swap, None);
        let mut later = snap.clone();
        later.tick = STRAFE_PERIOD_TICKS;
        let action = micro_action(&hold, me, &later);
        assert!(!action.left && action.right, "next period strafes right");

        let kite = Plan {
            stance: Stance::KiteDistance,
            ..hold.clone()
        };
        let action = micro_action(&kite, me, &snap);
        assert!(!action.back, "10 units is outside kite range");
        let mut close = snap.clone();
        close.players[1].x = 4.0;
        let action = micro_action(&kite, me, &close);
        assert!(action.back);
        assert!(action.fire);

        let swap_same = Plan {
            weapon: Some(WeaponType::Flechette),
            ..push.clone()
        };
        assert_eq!(
            micro_action(&swap_same, me, &snap).weapon_swap,
            None,
            "no swap to the held weapon"
        );
    }

    #[test]
    fn micro_fire_range_follows_the_weapon() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let snap = snapshot(
            0,
            vec![
                player("me", me, 0.0, 0.0, 90, "scatter"),
                player("foe", foe, 20.0, 0.0, 90, "rail"),
            ],
            vec![],
        );
        let push = Plan {
            stance: Stance::PushEnemy,
            weapon: None,
            danger: 2,
            confidence: 1.0,
            source: Source::Local,
        };
        assert!(
            !micro_action(&push, me, &snap).fire,
            "scatter is a 14 unit weapon"
        );
        let with_rail = Plan {
            weapon: Some(WeaponType::Rail),
            ..push
        };
        assert!(
            micro_action(&with_rail, me, &snap).fire,
            "the swapped weapon sets range"
        );
    }

    #[test]
    fn micro_heal_runs_to_the_nearest_pad_or_kites() {
        let me = Uuid::new_v4();
        let foe = Uuid::new_v4();
        let snap = snapshot(
            0,
            vec![
                player("me", me, 0.0, 0.0, 20, "flechette"),
                player("foe", foe, 5.0, 0.0, 90, "scatter"),
            ],
            vec![
                pad("health", "", 0.0, 12.0, true),
                pad("health", "", 0.0, 6.0, true),
                pad("health", "", 0.0, 1.0, false),
                pad("armor", "", 0.5, 0.0, true),
            ],
        );
        let heal = Plan {
            stance: Stance::FallBackHeal,
            weapon: None,
            danger: 4,
            confidence: 1.0,
            source: Source::Local,
        };
        let action = micro_action(&heal, me, &snap);
        let look = action.look_at.unwrap();
        assert_eq!(look.player_id, None);
        assert_eq!(look.z, Some(6.0), "nearest available health pad");
        assert!(action.forward);
        assert!(!action.fire);
        let mut on_pad = snap.clone();
        on_pad.players[0].z = 5.5;
        assert!(!micro_action(&heal, me, &on_pad).forward, "stop on the pad");
        let mut no_pads = snap.clone();
        no_pads.pickups.clear();
        let action = micro_action(&heal, me, &no_pads);
        assert_eq!(action.look_at.unwrap().player_id, Some(foe));
        assert!(action.back, "kite when there is nowhere to heal");
    }

    #[test]
    fn ctf_controller_pursues_flag_then_own_stand() {
        use fragr_server::protocol::{FlagState, FlagStatus, Team};
        let me = Uuid::from_u128(1);
        let mut mine = player("me", me, 0.0, 0.0, 90, "rail");
        mine.team = Some(Team::Coalition);
        let mut snap = snapshot(1, vec![mine], vec![]);
        snap.flags = Some([
            FlagState {
                team: Team::Union,
                stand: [-70.0, 0.0, 0.0],
                position: [-70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
            FlagState {
                team: Team::Coalition,
                stand: [70.0, 0.0, 0.0],
                position: [70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
        ]);
        let plan = Plan::default();
        let first = ctf_micro_action(&plan, me, &snap);
        assert!(first.forward);
        assert_eq!(first.look_at.unwrap().x, Some(-70.0));
        let mut blocker = player("foe", Uuid::from_u128(2), 5.0, 0.0, 100, "rail");
        blocker.team = Some(Team::Union);
        snap.players.push(blocker);
        let fight = ctf_micro_action(&plan, me, &snap);
        assert_eq!(fight.look_at.unwrap().player_id, Some(Uuid::from_u128(2)));
        snap.players.pop();
        snap.flags.as_mut().unwrap()[0].carrier = Some(me);
        snap.flags.as_mut().unwrap()[0].status = FlagStatus::Carried;
        let return_home = ctf_micro_action(&plan, me, &snap);
        assert_eq!(return_home.look_at.unwrap().x, Some(70.0));
    }

    fn ctf_team_scene() -> Snapshot {
        use fragr_server::protocol::{FlagState, FlagStatus, Team};
        let mut players = Vec::new();
        for id in 1..=8 {
            let team = if id <= 4 {
                Team::Union
            } else {
                Team::Coalition
            };
            let mut pawn = player(
                "same callsign",
                Uuid::from_u128(id),
                if team == Team::Union { -50.0 } else { 50.0 },
                (id % 4) as f32 * 16.0,
                100,
                "flechette",
            );
            pawn.team = Some(team);
            pawn.behavior = Some("hold_angle".into());
            players.push(pawn);
        }
        let mut scene = snapshot(1, players, vec![]);
        scene.flags = Some([
            FlagState {
                team: Team::Union,
                stand: [-70.0, 0.0, 0.0],
                position: [-70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
            FlagState {
                team: Team::Coalition,
                stand: [70.0, 0.0, 0.0],
                position: [70.0, 0.0, 0.0],
                status: FlagStatus::Home,
                carrier: None,
                return_ticks: None,
            },
        ]);
        scene
    }

    fn ctf_goal_x(scene: &Snapshot, id: u128) -> f32 {
        ctf_micro_action(&Plan::default(), Uuid::from_u128(id), scene)
            .look_at
            .unwrap()
            .x
            .unwrap()
    }

    #[test]
    fn ctf_brain_elects_one_defender_by_team_and_identity() {
        let mut scene = ctf_team_scene();
        assert_eq!(ctf_goal_x(&scene, 1), -70.0);
        assert_eq!(ctf_goal_x(&scene, 5), 70.0);
        for id in 2..=4 {
            assert_eq!(ctf_goal_x(&scene, id), 70.0);
        }
        for id in 6..=8 {
            assert_eq!(ctf_goal_x(&scene, id), -70.0);
        }
        scene.players.reverse();
        for pawn in &mut scene.players {
            pawn.name = "different callsign".into();
        }
        assert_eq!(ctf_goal_x(&scene, 1), -70.0);
        assert_eq!(ctf_goal_x(&scene, 5), 70.0);
        assert_eq!(ctf_goal_x(&scene, 2), 70.0);
        scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(1))
            .unwrap()
            .hp = 0;
        assert_eq!(ctf_goal_x(&scene, 2), -70.0, "dead defender yields");
        assert_eq!(
            ctf_goal_x(&scene, 3),
            70.0,
            "other attackers remain on attack"
        );
        assert!(
            ctf_micro_action(&Plan::default(), Uuid::from_u128(1), &scene)
                .look_at
                .is_none()
        );
    }

    #[test]
    fn ctf_carrier_returns_while_defender_recovers_and_escort_trails() {
        use fragr_server::protocol::{FlagStatus, Team};
        let mut scene = ctf_team_scene();
        let ally = scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(4))
            .unwrap();
        ally.x = -10.0;
        ally.z = 0.0;
        let flags = scene.flags.as_mut().unwrap();
        flags[Team::Coalition.index()].carrier = Some(Uuid::from_u128(4));
        flags[Team::Coalition.index()].status = FlagStatus::Carried;
        flags[Team::Coalition.index()].position = [-10.0, 0.0, 0.0];
        assert_eq!(ctf_goal_x(&scene, 4), -70.0);
        assert_eq!(ctf_goal_x(&scene, 1), -70.0);
        assert_eq!(ctf_goal_x(&scene, 2), -6.0, "one escort trails four units");
        assert_eq!(
            ctf_goal_x(&scene, 3),
            70.0,
            "attacker pressures enemy stand"
        );
        scene.flags.as_mut().unwrap()[Team::Union.index()].carrier = Some(Uuid::from_u128(5));
        scene.flags.as_mut().unwrap()[Team::Union.index()].status = FlagStatus::Carried;
        assert_eq!(
            ctf_goal_x(&scene, 4),
            -70.0,
            "carrier does not chase a thief"
        );
        assert_eq!(ctf_goal_x(&scene, 1), 50.0, "defender follows the thief");
        let flag = &mut scene.flags.as_mut().unwrap()[Team::Union.index()];
        flag.carrier = None;
        flag.status = FlagStatus::Dropped;
        flag.position = [-25.0, 0.0, 0.0];
        assert_eq!(ctf_goal_x(&scene, 1), -25.0, "only defender recovers");
        assert_eq!(ctf_goal_x(&scene, 2), -6.0, "escort remains with carrier");
        assert_eq!(ctf_goal_x(&scene, 3), 70.0);
        assert_eq!(ctf_goal_x(&scene, 4), -70.0);
        let ally = scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(4))
            .unwrap();
        ally.x = -67.0;
        assert_eq!(
            ctf_goal_x(&scene, 2),
            -64.0,
            "escort leaves scoring touch clear"
        );
        scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(1))
            .unwrap()
            .hp = 0;
        assert_eq!(
            ctf_goal_x(&scene, 2),
            -25.0,
            "defender seat transfers during a carry"
        );
        assert_eq!(
            ctf_goal_x(&scene, 3),
            -64.0,
            "escort seat also transfers uniquely"
        );
    }

    #[test]
    fn ctf_two_member_recovery_remains_and_enemy_cannot_be_an_escort() {
        use fragr_server::protocol::{FlagStatus, Team};
        let mut scene = ctf_team_scene();
        scene.players.retain(|p| {
            p.id == Uuid::from_u128(1)
                || p.id == Uuid::from_u128(2)
                || p.team == Some(Team::Coalition)
        });
        let flag = &mut scene.flags.as_mut().unwrap()[Team::Union.index()];
        flag.status = FlagStatus::Dropped;
        flag.position = [-25.0, 0.0, 0.0];
        assert_eq!(ctf_goal_x(&scene, 1), -25.0);
        assert_eq!(ctf_goal_x(&scene, 2), -25.0);
        let flag = &mut scene.flags.as_mut().unwrap()[Team::Coalition.index()];
        flag.status = FlagStatus::Carried;
        flag.carrier = Some(Uuid::from_u128(5));
        assert_eq!(
            ctf_goal_x(&scene, 2),
            -25.0,
            "enemy identity never elects an allied escort"
        );
    }

    #[test]
    fn ctf_humans_and_rule_bots_do_not_consume_coordination_roles() {
        use fragr_server::protocol::{FlagStatus, Team};
        let mut scene = ctf_team_scene();
        scene.players[0].behavior = None; // Human.
        scene.players[1].behavior = Some("Balanced".into()); // Server rule bot.
        let home = &mut scene.flags.as_mut().unwrap()[Team::Union.index()];
        home.status = FlagStatus::Dropped;
        home.position = [-25.0, 0.0, 0.0];
        assert_eq!(
            ctf_goal_x(&scene, 3),
            -25.0,
            "two compatible brains share recovery"
        );
        let mut peer = player("unrelated", Uuid::from_u128(9), -45.0, 70.0, 100, "rail");
        peer.team = Some(Team::Union);
        peer.behavior = Some("push_enemy".into());
        scene.players.push(peer);
        assert_eq!(
            ctf_goal_x(&scene, 3),
            -25.0,
            "lowest compatible brain defends"
        );
        assert_eq!(
            ctf_goal_x(&scene, 4),
            70.0,
            "other compatible brain attacks"
        );
        assert_eq!(ctf_goal_x(&scene, 9), 70.0);
    }

    #[test]
    fn ctf_lone_carrier_recovers_its_home_flag_without_a_compatible_defender() {
        use fragr_server::protocol::{FlagStatus, Team};
        let mut scene = ctf_team_scene();
        scene
            .players
            .retain(|p| p.id == Uuid::from_u128(4) || p.team == Some(Team::Coalition));
        let enemy = &mut scene.flags.as_mut().unwrap()[Team::Coalition.index()];
        enemy.status = FlagStatus::Carried;
        enemy.carrier = Some(Uuid::from_u128(4));
        let own = &mut scene.flags.as_mut().unwrap()[Team::Union.index()];
        own.status = FlagStatus::Dropped;
        own.position = [-25.0, 0.0, 0.0];
        assert_eq!(ctf_goal_x(&scene, 4), -25.0);
        let own = &mut scene.flags.as_mut().unwrap()[Team::Union.index()];
        own.status = FlagStatus::Carried;
        own.carrier = Some(Uuid::from_u128(5));
        assert_eq!(
            ctf_micro_action(&Plan::default(), Uuid::from_u128(4), &scene)
                .look_at
                .unwrap()
                .player_id,
            Some(Uuid::from_u128(5)),
            "sole carrier intercepts the thief"
        );
        for id in 1..=2 {
            let mut human = player("unrelated", Uuid::from_u128(id), -60.0, 70.0, 100, "rail");
            human.team = Some(Team::Union);
            scene.players.push(human);
        }
        assert_eq!(
            ctf_micro_action(&Plan::default(), Uuid::from_u128(4), &scene)
                .look_at
                .unwrap()
                .player_id,
            Some(Uuid::from_u128(5)),
            "human roster does not imply a defender"
        );
        for pawn in &mut scene.players {
            if pawn.team == Some(Team::Union) && pawn.id != Uuid::from_u128(4) {
                pawn.behavior = Some("hold_angle".into());
                pawn.hp = 0;
            }
        }
        assert_eq!(
            ctf_micro_action(&Plan::default(), Uuid::from_u128(4), &scene)
                .look_at
                .unwrap()
                .player_id,
            Some(Uuid::from_u128(5)),
            "dead compatible defenders cannot recover"
        );
    }

    #[test]
    fn ctf_lone_carrier_shoots_visible_thief_within_weapon_range_while_intercepting() {
        use fragr_server::protocol::{FlagStatus, Team};
        let id = Uuid::from_u128(4);
        let thief = Uuid::from_u128(5);
        let mut scene = ctf_team_scene();
        scene.players.retain(|p| p.id == id || p.id == thief);
        scene.players[0].x = 0.0;
        scene.players[0].z = 0.0;
        scene.players[0].weapon = "rail".into();
        scene.players[1].x = 30.0;
        scene.players[1].z = 0.0;
        let own = &mut scene.flags.as_mut().unwrap()[Team::Union.index()];
        own.status = FlagStatus::Carried;
        own.carrier = Some(thief);
        let enemy = &mut scene.flags.as_mut().unwrap()[Team::Coalition.index()];
        enemy.status = FlagStatus::Carried;
        enemy.carrier = Some(id);
        let open = Navigation::new(Arena {
            half: 100.0,
            solids: vec![],
        })
        .unwrap();
        let plan = Plan::default();
        let intercept = ctf_micro_action_in_world(&plan, id, &scene, &open);
        let mut navigator = fragr_server::navigation::Navigator::default();
        let routed = navigator.steer_snapshot(&open, id, &scene, intercept);
        assert_eq!(routed.look_at.unwrap().player_id, Some(thief));
        assert!(
            routed.forward && routed.fire,
            "visible rail target beyond the campaign radius remains a moving shot"
        );
        let short_weapon = Plan {
            weapon: Some(WeaponType::Fists),
            ..Plan::default()
        };
        let distant = ctf_micro_action_in_world(&short_weapon, id, &scene, &open);
        assert!(
            distant.forward && !distant.fire,
            "range refusal preserves interception movement"
        );
        assert_eq!(distant.look_at.unwrap().player_id, Some(thief));
        let wall = Navigation::new(Arena {
            half: 100.0,
            solids: vec![Solid::from_center(15.0, 0.0, 0.5, 3.0)],
        })
        .unwrap();
        let occluded = ctf_micro_action_in_world(&plan, id, &scene, &wall);
        assert!(occluded.forward && !occluded.fire);
        assert_eq!(
            occluded.look_at.unwrap().x,
            Some(30.0),
            "hidden thief remains a route goal without a shot"
        );
        for peer in 1..=2 {
            let mut ally = player(
                "compatible",
                Uuid::from_u128(peer),
                -60.0,
                70.0,
                100,
                "rail",
            );
            ally.team = Some(Team::Union);
            ally.behavior = Some("hold_angle".into());
            scene.players.push(ally);
        }
        let home = ctf_micro_action_in_world(&plan, id, &scene, &open);
        assert_eq!(home.look_at.unwrap().x, Some(-70.0));
        assert!(
            home.forward && !home.fire,
            "living compatible defender frees the carrier to return home"
        );
    }

    #[test]
    fn ctf_combat_uses_visible_hostiles_and_escort_does_not_chase() {
        use fragr_server::protocol::{FlagStatus, Team};
        let mut scene = ctf_team_scene();
        let mine = scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(2))
            .unwrap();
        mine.x = 0.0;
        mine.z = 0.0;
        let foe = scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(5))
            .unwrap();
        foe.x = 5.0;
        foe.z = 0.0;
        let wall = Navigation::new(Arena {
            half: 100.0,
            solids: vec![Solid::from_center(2.5, 0.0, 0.5, 3.0)],
        })
        .unwrap();
        let plan = Plan {
            stance: Stance::PushEnemy,
            ..Plan::default()
        };
        let blocked = ctf_micro_action_in_world(&plan, Uuid::from_u128(2), &scene, &wall);
        assert_eq!(
            blocked.look_at.unwrap().x,
            Some(70.0),
            "hidden opponent does not replace flag route"
        );
        let open = Navigation::new(Arena {
            half: 100.0,
            solids: vec![],
        })
        .unwrap();
        let fight = ctf_micro_action_in_world(&plan, Uuid::from_u128(2), &scene, &open);
        assert_eq!(fight.look_at.unwrap().player_id, Some(Uuid::from_u128(5)));
        let ally = scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(4))
            .unwrap();
        ally.x = -4.0;
        ally.z = 0.0;
        let flag = &mut scene.flags.as_mut().unwrap()[Team::Coalition.index()];
        flag.status = FlagStatus::Carried;
        flag.carrier = Some(Uuid::from_u128(4));
        let escort = ctf_micro_action_in_world(&plan, Uuid::from_u128(2), &scene, &open);
        assert_eq!(escort.look_at.unwrap().player_id, Some(Uuid::from_u128(5)));
        assert!(escort.fire);
        assert!(!escort.forward && !escort.back && !escort.left && !escort.right);
        scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(4))
            .unwrap()
            .x = -20.0;
        let resume = ctf_micro_action_in_world(&plan, Uuid::from_u128(2), &scene, &open);
        assert_eq!(
            resume.look_at.unwrap().x,
            Some(-16.0),
            "carrier leaving support radius resumes escort route"
        );
        scene
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(5))
            .unwrap()
            .team = Some(Team::Union);
        let allied = ctf_micro_action_in_world(&plan, Uuid::from_u128(2), &scene, &open);
        assert!(allied.look_at.unwrap().player_id.is_none());
    }

    #[test]
    fn micro_handles_missing_self_and_no_enemies() {
        let me = Uuid::new_v4();
        let plan = Plan::default();
        let empty = snapshot(0, vec![], vec![]);
        let action = micro_action(&plan, me, &empty);
        assert!(action.look_at.is_none() && !action.fire && !action.forward);
        let alone = snapshot(
            0,
            vec![
                player("me", me, 0.0, 0.0, 90, "rail"),
                player("corpse", Uuid::new_v4(), 1.0, 0.0, 0, "rail"),
            ],
            vec![],
        );
        let action = micro_action(&plan, me, &alone);
        assert!(action.look_at.is_none(), "dead fighters are not targets");
        assert!(!action.fire);
    }
}
