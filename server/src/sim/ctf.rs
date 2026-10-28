//! Authoritative flag transitions for a staged two-side league match.
use super::{GameState, RoundState, PLAYER_FLOOR_Y};
use crate::protocol::{
    FlagEventKind, FlagState, FlagStatus, GameEvent, GameMode, HostReactionKind, PlayerState, Team,
    TeamScores,
};
use uuid::Uuid;

const TOUCH_RADIUS_SQUARED: f32 = 2.5 * 2.5;
const RETURN_TICKS: u64 = 20 * 20;
const DROP_TOUCH_GRACE_TICKS: u64 = 10;

#[derive(Debug, Clone)]
pub(super) struct Flag {
    pub team: Team,
    pub stand: [f32; 3],
    pub position: [f32; 3],
    pub carrier: Option<Uuid>,
    pub dropped_at: Option<u64>,
}

impl Flag {
    fn home(team: Team, stand: [f32; 3]) -> Self {
        Self {
            team,
            stand,
            position: stand,
            carrier: None,
            dropped_at: None,
        }
    }

    fn is_home(&self) -> bool {
        self.carrier.is_none() && self.dropped_at.is_none()
    }

    fn wire(&self, tick: u64) -> FlagState {
        FlagState {
            team: self.team,
            stand: self.stand,
            position: self.position,
            status: if self.carrier.is_some() {
                FlagStatus::Carried
            } else if self.dropped_at.is_some() {
                FlagStatus::Dropped
            } else {
                FlagStatus::Home
            },
            carrier: self.carrier,
            return_ticks: self
                .dropped_at
                .map(|at| RETURN_TICKS.saturating_sub(tick.saturating_sub(at)) as u32),
        }
    }

    fn return_home(&mut self) {
        self.position = self.stand;
        self.carrier = None;
        self.dropped_at = None;
    }
}

fn touches(a: [f32; 3], b: [f32; 3]) -> bool {
    let dx = a[0] - b[0];
    let dz = a[2] - b[2];
    dx * dx + dz * dz <= TOUCH_RADIUS_SQUARED && (a[1] - b[1]).abs() <= 2.5
}

impl GameState {
    pub(super) fn reset_ctf(&mut self) {
        self.capture_scores = TeamScores::default();
        self.flags = if self.config.rules.mode() == GameMode::Ctf {
            self.map.ctf_stands().map(|stands| {
                [
                    Flag::home(Team::Union, stands[0]),
                    Flag::home(Team::Coalition, stands[1]),
                ]
            })
        } else {
            None
        };
    }

    fn flag_event(&mut self, kind: FlagEventKind, flag: Team, player: Option<Uuid>) {
        let name = player.and_then(|id| {
            self.players
                .iter()
                .find(|p| p.id == id)
                .map(|p| p.name.clone())
        });
        self.events.push(GameEvent::Flag {
            kind,
            flag,
            player: name,
            player_id: player,
            capture_scores: self.capture_scores,
        });
        if let (FlagEventKind::Taken, Some(id)) = (kind, player) {
            self.queue_callout(id, crate::roster::ObjectiveCall::HaveFlag);
        }
    }

    pub(crate) fn drop_flag_from(&mut self, player: Uuid) {
        if self.round_state != RoundState::Active {
            return;
        }
        let feet = self.players.iter().find(|p| p.id == player).map(|p| {
            let feet_y = p.y - PLAYER_FLOOR_Y;
            [p.x, self.map.arena().support_height(p.x, p.z, feet_y), p.z]
        });
        let Some(flags) = self.flags.as_mut() else {
            return;
        };
        for flag in flags {
            if flag.carrier == Some(player) {
                flag.carrier = None;
                flag.dropped_at = Some(self.tick);
                flag.position = feet.unwrap_or(flag.stand);
                let team = flag.team;
                self.flag_event(FlagEventKind::Dropped, team, Some(player));
                break;
            }
        }
    }

    pub(super) fn tick_ctf(&mut self) {
        if self.round_state != RoundState::Active {
            return;
        }
        let Some(mut flags) = self.flags.take() else {
            return;
        };

        // Combat has already resolved. A dead carrier cannot score on this tick.
        for flag in &mut flags {
            if let Some(carrier) = flag.carrier {
                if let Some(p) = self.players.iter().find(|p| {
                    p.id == carrier
                        && p.hp > 0
                        && p.respawn_timer.is_none()
                        && !p.detached
                        && p.team == Some(flag.team.other())
                }) {
                    flag.position = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
                } else {
                    flag.carrier = None;
                    flag.dropped_at = Some(self.tick);
                    flag.position[1] = self.map.arena().support_height(
                        flag.position[0],
                        flag.position[2],
                        flag.position[1],
                    );
                    self.flag_event(FlagEventKind::Dropped, flag.team, Some(carrier));
                }
            }
            if flag
                .dropped_at
                .is_some_and(|at| self.tick.saturating_sub(at) >= RETURN_TICKS)
            {
                flag.return_home();
                self.flag_event(FlagEventKind::Returned, flag.team, None);
            }
        }

        let mut actors: Vec<(usize, Uuid)> = self
            .players
            .iter()
            .filter(|p| {
                p.contestant()
                    && p.hp > 0
                    && p.respawn_timer.is_none()
                    && !p.eliminated
                    && !p.detached
                    && p.team.is_some()
            })
            .map(|p| (p.team.expect("filtered side").index(), p.id))
            .collect();
        actors.sort_unstable();
        for (_, id) in actors {
            let Some(p) = self.players.iter().find(|p| p.id == id) else {
                continue;
            };
            let side = p.team.expect("filtered side");
            let feet = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
            let own = side.index();
            let enemy = side.other().index();
            // Keep a combat drop in replicated state before either side touches
            // it. Otherwise an overlapping defender can return it in one tick.
            if flags[own]
                .dropped_at
                .is_some_and(|at| self.tick.saturating_sub(at) >= DROP_TOUCH_GRACE_TICKS)
                && touches(feet, flags[own].position)
            {
                flags[own].return_home();
                self.flag_event(FlagEventKind::Returned, side, Some(id));
            }
            if flags[enemy].carrier.is_none()
                && flags[enemy]
                    .dropped_at
                    .is_none_or(|at| self.tick.saturating_sub(at) >= DROP_TOUCH_GRACE_TICKS)
                && touches(feet, flags[enemy].position)
            {
                flags[enemy].carrier = Some(id);
                flags[enemy].dropped_at = None;
                flags[enemy].position = feet;
                self.flag_event(FlagEventKind::Taken, side.other(), Some(id));
                let name = self.name_of(id);
                self.react(HostReactionKind::FlagTaken, name, None, Some(side));
            }
            if flags[enemy].carrier == Some(id)
                && flags[own].is_home()
                && touches(feet, flags[own].stand)
            {
                flags[enemy].return_home();
                self.capture_scores.add(side);
                self.flag_event(FlagEventKind::Captured, side.other(), Some(id));
                // The capture is the call; the lead it may change is only noted.
                self.note_lead();
                let name = self.name_of(id);
                self.react(HostReactionKind::FlagCaptured, name, None, Some(side));
                if self.capture_scores.get(side)
                    >= self
                        .config
                        .capture_limit
                        .unwrap_or(crate::rules::CTF_CAPTURE_LIMIT)
                {
                    self.flags = Some(flags);
                    self.end_round("Capture limit reached".to_string());
                    return;
                }
            }
        }
        self.flags = Some(flags);
    }

    pub(super) fn wire_flags(&self) -> Option<[FlagState; 2]> {
        self.flags
            .as_ref()
            .map(|flags| [flags[0].wire(self.tick), flags[1].wire(self.tick)])
    }
}

/// Maximum distance for close-contact carrier self-defense.
pub const CARRIER_CONTACT_DISTANCE: f32 = 1.5;

/// Bounded ticks allowed for a single close-contact defensive opportunity.
pub const CARRIER_DEFENSIVE_OPPORTUNITY_TICKS: u8 = 8;

/// A living enemy physically obstructing the immediate return route of an armed carrier.
///
/// Returns true if `other` is a living, collidable hostile, visible to `carrier`,
/// within the 1.5 m contact scale, and physically obstructing the carrier's forward path to `goal`.
pub fn carrier_contact_blocker_eligible(
    carrier: &PlayerState,
    goal: [f32; 3],
    other: &PlayerState,
    visible: bool,
) -> bool {
    if carrier.hp <= 0
        || other.hp <= 0
        || !other.collidable
        || !carrier.is_hostile_to(other)
        || !visible
    {
        return false;
    }
    let dx = other.x - carrier.x;
    let dz = other.z - carrier.z;
    let dist = dx.hypot(dz);
    if dist > CARRIER_CONTACT_DISTANCE {
        return false;
    }
    let gx = goal[0] - carrier.x;
    let gz = goal[2] - carrier.z;
    let goal_dist = gx.hypot(gz);
    if goal_dist <= CARRIER_CONTACT_DISTANCE {
        // At the goal / stand; any hostile at contact distance is contesting.
        return true;
    }
    // Check if the enemy is in the forward direction towards the goal and
    // within the physical corridor (lateral offset where player cylinders would collide).
    let dir_x = gx / goal_dist;
    let dir_z = gz / goal_dist;
    let along = dx * dir_x + dz * dir_z;
    let perp = (dx * dir_z - dz * dir_x).abs();
    // Two players collide at 0.8m center-to-center. Allow a 0.85m corridor.
    along > 0.0 && perp <= 0.85
}

/// Find the nearest eligible blocking hostile physically obstructing the carrier's immediate return.
pub fn find_carrier_contact_blocker<'a>(
    carrier: &PlayerState,
    goal: [f32; 3],
    players: &'a [PlayerState],
    visible: impl Fn(&PlayerState, &PlayerState) -> bool,
) -> Option<&'a PlayerState> {
    players
        .iter()
        .filter(|other| {
            carrier_contact_blocker_eligible(carrier, goal, other, visible(carrier, other))
        })
        .min_by(|a, b| {
            let da = (a.x - carrier.x).hypot(a.z - carrier.z);
            let db = (b.x - carrier.x).hypot(b.z - carrier.z);
            da.total_cmp(&db)
        })
}

/// Small retained state for close-contact carrier defense.
///
/// Bounded to prevent unbounded stationary fights while retaining the flag
/// return as the objective.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct CarrierContactDefense {
    pub target: Option<Uuid>,
    pub ticks_remaining: u8,
}

impl CarrierContactDefense {
    pub fn clear(&mut self) {
        self.target = None;
        self.ticks_remaining = 0;
    }

    /// Update defense state for one tick. Returns the target to defend against,
    /// or None if no eligible blocker exists or the opportunity is exhausted.
    pub fn update(
        &mut self,
        carrier: &PlayerState,
        goal: [f32; 3],
        players: &[PlayerState],
        visible: impl Fn(&PlayerState, &PlayerState) -> bool,
    ) -> Option<Uuid> {
        if let Some(target_id) = self.target {
            let active = players
                .iter()
                .find(|p| p.id == target_id)
                .is_some_and(|other| {
                    carrier_contact_blocker_eligible(carrier, goal, other, visible(carrier, other))
                });
            if active {
                if self.ticks_remaining > 0 {
                    self.ticks_remaining -= 1;
                    return Some(target_id);
                } else {
                    // Defensive opportunity exhausted for this target: return to flag return.
                    return None;
                }
            } else {
                // Target died, cleared contact, or broke LOS.
                self.target = None;
                self.ticks_remaining = 0;
            }
        }

        if let Some(blocker) = find_carrier_contact_blocker(carrier, goal, players, visible) {
            self.target = Some(blocker.id);
            self.ticks_remaining = CARRIER_DEFENSIVE_OPPORTUNITY_TICKS.saturating_sub(1);
            Some(blocker.id)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_player(id: u128, team: Team, x: f32, z: f32, hp: i32) -> PlayerState {
        PlayerState {
            collidable: true,
            campaign: None,
            id: Uuid::from_u128(id),
            name: format!("p-{id}"),
            x,
            y: 1.5,
            z,
            yaw: 0.0,
            pitch: 0.0,
            hp,
            armor: 0,
            just_fired: false,
            behavior: None,
            score: 0,
            deaths: 0,
            attacks: 0,
            connects: 0,
            heads: 0,
            damage: 0,
            weapon: "flechette".into(),
            team: Some(team),
            lives: None,
            golden: false,
            ducking: false,
            body: None,
            ping: None,
        }
    }

    #[test]
    fn carrier_contact_blocker_eligible_requires_hostile_living_visible_contact_and_corridor() {
        let carrier = test_player(1, Team::Coalition, 0.0, 0.0, 100);
        let goal = [70.0, 0.0, 0.0];

        // Directly in front on homeward path (+X) at 1.25m: eligible.
        let blocker = test_player(2, Team::Union, 1.25, 0.0, 100);
        assert!(carrier_contact_blocker_eligible(
            &carrier, goal, &blocker, true
        ));

        // Behind carrier (-X) at 1.25m: not obstructing return.
        let behind = test_player(3, Team::Union, -1.25, 0.0, 100);
        assert!(!carrier_contact_blocker_eligible(
            &carrier, goal, &behind, true
        ));

        // In front (+X) at 1.25m, but wide lateral offset (> 0.85m): not obstructing.
        let wide = test_player(4, Team::Union, 0.5, 1.3, 100);
        assert!(!carrier_contact_blocker_eligible(
            &carrier, goal, &wide, true
        ));

        // Outside 1.5m contact distance: not eligible.
        let distant = test_player(5, Team::Union, 2.0, 0.0, 100);
        assert!(!carrier_contact_blocker_eligible(
            &carrier, goal, &distant, true
        ));

        // Dead enemy (hp 0): not eligible.
        let dead = test_player(6, Team::Union, 1.25, 0.0, 0);
        assert!(!carrier_contact_blocker_eligible(
            &carrier, goal, &dead, true
        ));

        // Non-collidable: not eligible.
        let mut ghost = test_player(7, Team::Union, 1.25, 0.0, 100);
        ghost.collidable = false;
        assert!(!carrier_contact_blocker_eligible(
            &carrier, goal, &ghost, true
        ));

        // Teammate: not eligible.
        let ally = test_player(8, Team::Coalition, 1.25, 0.0, 100);
        assert!(!carrier_contact_blocker_eligible(
            &carrier, goal, &ally, true
        ));

        // Obstructed by cover (visible = false): not eligible.
        assert!(!carrier_contact_blocker_eligible(
            &carrier, goal, &blocker, false
        ));

        // Dead carrier: not eligible.
        let dead_carrier = test_player(9, Team::Coalition, 0.0, 0.0, 0);
        assert!(!carrier_contact_blocker_eligible(
            &dead_carrier,
            goal,
            &blocker,
            true
        ));

        // At goal (goal_dist <= 1.5): hostile at contact from any angle is contesting stand.
        let at_goal_carrier = test_player(10, Team::Coalition, 69.5, 0.0, 100);
        let stand_contest = test_player(11, Team::Union, 69.0, 0.5, 100);
        assert!(carrier_contact_blocker_eligible(
            &at_goal_carrier,
            goal,
            &stand_contest,
            true
        ));
    }

    #[test]
    fn carrier_contact_defense_bounds_opportunity_and_resumes_return() {
        let carrier = test_player(1, Team::Coalition, 0.0, 0.0, 100);
        let goal = [70.0, 0.0, 0.0];
        let foe_id = Uuid::from_u128(2);
        let mut foe = test_player(2, Team::Union, 1.2, 0.0, 100);

        let mut defense = CarrierContactDefense::default();

        // First tick: encounters blocker, starts bounded defense.
        let target = defense.update(&carrier, goal, &[foe.clone()], |_, _| true);
        assert_eq!(target, Some(foe_id));
        assert_eq!(
            defense.ticks_remaining,
            CARRIER_DEFENSIVE_OPPORTUNITY_TICKS - 1
        );

        // Advance through all remaining ticks.
        for _ in 1..CARRIER_DEFENSIVE_OPPORTUNITY_TICKS {
            let t = defense.update(&carrier, goal, &[foe.clone()], |_, _| true);
            assert_eq!(t, Some(foe_id));
        }

        // Exhausted: returns None while foe is still present so return resumes.
        assert_eq!(defense.ticks_remaining, 0);
        let exhausted = defense.update(&carrier, goal, &[foe.clone()], |_, _| true);
        assert_eq!(exhausted, None, "exhausted defense yields to flag return");

        // Foe steps away: defense clears.
        foe.x = 2.5;
        let cleared = defense.update(&carrier, goal, &[foe.clone()], |_, _| true);
        assert_eq!(cleared, None);
        assert_eq!(defense.target, None);

        // Foe re-enters contact: new defense opportunity begins.
        foe.x = 1.2;
        let fresh = defense.update(&carrier, goal, &[foe.clone()], |_, _| true);
        assert_eq!(fresh, Some(foe_id));

        // Foe dies: defense clears immediately.
        foe.hp = 0;
        let dead = defense.update(&carrier, goal, &[foe.clone()], |_, _| true);
        assert_eq!(dead, None);
        assert_eq!(defense.target, None);
    }
}
