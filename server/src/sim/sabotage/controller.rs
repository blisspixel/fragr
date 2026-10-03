//! One Sabotage objective controller for wire clients: the playtest agents,
//! the adapter's scripted bot and any MCP client that reads the same snapshot
//! and `MapInfo`. It decides only what to do for the objective; equipment and
//! walking stay with the shared equipment controller and navigator, and the
//! server still decides every outcome.
use crate::protocol::{
    Action, ChargeStatus, LookAt, PlayerState, ProgressKind, SabotageMap, SabotagePhase, SiteId,
    Snapshot, Team,
};
use crate::sim::PLAYER_FLOOR_Y;
use uuid::Uuid;

/// What the objective asks of one fighter this snapshot.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Objective {
    /// Nothing for the objective now: muster, out of the round, or no charge.
    Idle,
    /// Walk to this point, feet height.
    Walk([f32; 3]),
    /// Stand still and hold Use: plant here.
    Plant,
    /// Stand still and hold Use: defuse here.
    Defuse,
}

/// A carrier stops this far inside the plant radius.
const PLANT_MARGIN: f32 = 0.8;
/// A defender this close to the charge stops and holds Use.
const DEFUSE_STOP: f32 = 1.2;
/// Attackers guard a planted charge from this far.
const GUARD: f32 = 5.0;

fn feet(player: &PlayerState) -> [f32; 3] {
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

fn horizontal(a: [f32; 3], b: [f32; 3]) -> f32 {
    (a[0] - b[0]).hypot(a[2] - b[2])
}

/// The site the attack takes this round: alternating by round, so a match
/// visits both.
pub fn attack_site(round: u32) -> SiteId {
    if round % 2 == 1 {
        SiteId::A
    } else {
        SiteId::B
    }
}

/// This fighter's place on its side, by callsign: stable across snapshots
/// without relying on process-local identities.
fn side_slot(snapshot: &Snapshot, me: &PlayerState, team: Team) -> usize {
    let mut names: Vec<&str> = snapshot
        .players
        .iter()
        .filter(|p| p.team == Some(team))
        .map(|p| p.name.as_str())
        .collect();
    names.sort_unstable();
    names.iter().position(|n| *n == me.name).unwrap_or(0)
}

fn nearest_of(snapshot: &Snapshot, team: Team, to: [f32; 3]) -> Option<&PlayerState> {
    snapshot
        .players
        .iter()
        .filter(|p| p.team == Some(team) && p.hp > 0)
        .min_by(|a, b| {
            horizontal(feet(a), to)
                .total_cmp(&horizontal(feet(b), to))
                .then_with(|| a.name.cmp(&b.name))
        })
}

/// The objective for `id` in this snapshot of a Sabotage server.
pub fn objective(id: Uuid, snapshot: &Snapshot, map: &SabotageMap) -> Objective {
    let Some(state) = snapshot.sabotage.as_ref() else {
        return Objective::Idle;
    };
    let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
        return Objective::Idle;
    };
    let Some(team) = me.team else {
        return Objective::Idle;
    };
    if !matches!(state.phase, SabotagePhase::Live | SabotagePhase::Planted) {
        return Objective::Idle;
    }
    let Some(charge) = state.charge.as_ref() else {
        return Objective::Idle;
    };
    let here = feet(me);
    let slot = side_slot(snapshot, me, team);
    if team == map.attackers {
        if charge.status == ChargeStatus::Planted {
            let defusing = state
                .progress
                .as_ref()
                .is_some_and(|p| p.kind == ProgressKind::Defuse);
            if defusing {
                return Objective::Walk(charge.position);
            }
            let angle = slot as f32 * std::f32::consts::TAU / 6.0;
            return Objective::Walk([
                charge.position[0] + angle.cos() * GUARD,
                charge.position[1],
                charge.position[2] + angle.sin() * GUARD,
            ]);
        }
        let site = &map.sites[attack_site(state.round).index()];
        if charge.carrier == Some(id) {
            if horizontal(here, site.center) <= site.radius - PLANT_MARGIN {
                return Objective::Plant;
            }
            return Objective::Walk(site.center);
        }
        if charge.status == ChargeStatus::Dropped
            && nearest_of(snapshot, team, charge.position).is_some_and(|p| p.id == id)
        {
            return Objective::Walk(charge.position);
        }
        return Objective::Walk(site.center);
    }
    if charge.status == ChargeStatus::Planted {
        if nearest_of(snapshot, team, charge.position).is_some_and(|p| p.id == id) {
            if horizontal(here, charge.position) <= DEFUSE_STOP {
                return Objective::Defuse;
            }
            return Objective::Walk(charge.position);
        }
        return Objective::Walk(charge.position);
    }
    let planting = state
        .progress
        .as_ref()
        .filter(|p| p.kind == ProgressKind::Plant)
        .map(|p| p.site);
    let anchor = if slot.is_multiple_of(2) {
        SiteId::A
    } else {
        SiteId::B
    };
    Objective::Walk(map.sites[planting.unwrap_or(anchor).index()].center)
}

/// The objective as ordinary input: a world-point walk for the navigator, or
/// a held Use standing still. None leaves the fighter to its own combat.
pub fn objective_action(id: Uuid, snapshot: &Snapshot, map: &SabotageMap) -> Option<Action> {
    match objective(id, snapshot, map) {
        Objective::Idle => None,
        Objective::Walk(point) => Some(Action {
            // Arrived: stand rather than circle the point.
            forward: snapshot
                .players
                .iter()
                .find(|p| p.id == id)
                .is_some_and(|me| horizontal(feet(me), point) > 1.0),
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Action::default()
        }),
        Objective::Plant | Objective::Defuse => Some(Action {
            interact: true,
            ..Action::default()
        }),
    }
}
