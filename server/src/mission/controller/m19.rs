//! Planned Works wire control: ordered objectives, authored jetpack hops and
//! stepping out of a marked strip before it is worked.
use super::*;
use crate::movement::jetpack::{hop_input, HOP_TICKS};
use crate::protocol::{M19MapGeometry, PaverStripState};

/// A hop starts only with this much fuel; a part-empty pack walks instead.
const HOP_FUEL: u16 = 40;
/// Walk-to-launch tolerance before thrust begins.
const LAUNCH_REACH: f32 = 0.45;
/// Margin beyond a strip edge the escape aims for.
const STRIP_CLEARANCE: f32 = 1.2;
/// A dormant guard farther than this does not stop objective travel.
const DISTANT_IDLE: f32 = 12.0;
/// Inside an arrival whose group still stands, close on hostiles this near.
const HUNT_RANGE: f32 = 60.0;

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub(super) struct HopState {
    /// Index of the hop in flight and the tick it began.
    flying: Option<(usize, u64)>,
    /// Hops abandoned in this attempt; the walking route takes over.
    failed: [bool; crate::protocol::M19_MAX_JET_HOPS],
    attempt: u32,
    /// A gating straggler being hunted, kept until it falls or the objective moves.
    hunt: Option<(Uuid, usize)>,
}

/// The direction out of a strip that contains `feet`: across its nearer
/// edge, or the farther one when the nearer side is walled within reach.
pub(crate) fn strip_escape(
    strip: &PaverStripState,
    feet: [f32; 3],
    solids: &[Solid],
) -> Option<f32> {
    let forward = [strip.yaw.cos(), strip.yaw.sin()];
    let lateral = [-forward[1], forward[0]];
    let dx = feet[0] - strip.origin[0];
    let dz = feet[2] - strip.origin[2];
    let along = dx * forward[0] + dz * forward[1];
    let across = dx * lateral[0] + dz * lateral[1];
    if !(0.0..=strip.length).contains(&along)
        || across.abs() > strip.half_width
        || (feet[1] - strip.origin[1]).abs() > crate::encounters::enemy::paver::STRIP_FLOOR_BAND
    {
        return None;
    }
    let side = if across >= 0.0 { 1.0 } else { -1.0 };
    let open = |sign: f32| {
        let reach = strip.half_width - across * sign + STRIP_CLEARANCE;
        let end = [
            feet[0] + lateral[0] * sign * reach,
            feet[1] + 1.0,
            feet[2] + lateral[1] * sign * reach,
        ];
        crate::combat::line_of_sight([feet[0], feet[1] + 1.0, feet[2]], end, solids)
    };
    let sign = if open(side) || !open(-side) {
        side
    } else {
        -side
    };
    Some((lateral[1] * sign).atan2(lateral[0] * sign).rem_euclid(TAU))
}

use std::f32::consts::TAU;

impl MissionClient {
    pub fn replace_map_with_m19(
        &mut self,
        geometry: Option<&M19MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m19_map = None;
            self.m19_points = None;
            self.m19_solids.clear();
            self.m19_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m05_map.is_some()
            || self.m06_map.is_some()
            || self.m07_map.is_some()
            || self.m08_map.is_some()
            || self.m09_map.is_some()
            || self.m10_map.is_some()
            || self.m11_map.is_some()
            || self.m12_map.is_some()
            || self.m13_map.is_some()
            || self.m14_map.is_some()
            || self.m15_map.is_some()
            || self.m16_map.is_some()
            || self.m17_map.is_some()
            || self.m18_map.is_some()
        {
            return Err("M19 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m19_map {
            let mut same = old.clone();
            same.gate_open = g.gate_open;
            if &same != g {
                return Err("M19 static map contract changed");
            }
        }
        let present = presentation.ok_or("M19 presentation missing")?;
        self.m19_points = Some([
            g.stores
                .point(present, solids)
                .ok_or("M19 stores counter missing")?,
            g.departure
                .point(present, solids)
                .ok_or("M19 waterworks hatch missing")?,
        ]);
        self.m19_map = Some(g.clone());
        self.m19_solids = solids.to_vec();
        self.m19_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m19_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m19_map.as_ref().ok_or("M19 geometry missing")?;
        let f = state.m19.as_ref().ok_or("M19 facts missing")?;
        let done = f.completed.len();
        let expected = if done < g.objectives.len() {
            Some(g.objectives[done].clone())
        } else if done == g.objectives.len() {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected || f.gate_open != g.gate_open {
            return Err("M19 objective or gate disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m19.as_ref().ok_or("M19 prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.challenges.paver_interrupted && !f.challenges.paver_interrupted
                    || old_f.challenges.strip_struck && !f.challenges.strip_struck
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M19 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m19(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let attempt = self.state.as_ref().map_or(0, |s| s.attempt);
        if self.m19_hops.attempt != attempt {
            self.m19_hops = HopState {
                attempt,
                ..HopState::default()
            };
        }
        // A marked strip is the most urgent fact on the floor: step across
        // its nearer edge, still aiming and firing at the chosen target.
        if let Some(yaw) = snapshot
            .paver_strips
            .iter()
            .find_map(|strip| strip_escape(strip, feet, &self.m19_solids))
        {
            self.m19_hops.flying = None;
            self.press_down = false;
            navigator.clear();
            return Action {
                yaw: Some(yaw),
                forward: true,
                back: false,
                left: false,
                right: false,
                jump: false,
                ..action
            };
        }
        // A dormant guard far down a sightline does not hold the party in
        // place: keep walking the objective while the aim stays on it.
        let distant_idle = action
            .look_at
            .as_ref()
            .and_then(|look| look.player_id)
            .and_then(|target| snapshot.players.iter().find(|p| p.id == target))
            .is_some_and(|target| {
                matches!(
                    target.campaign,
                    Some(crate::protocol::CampaignActor::Hostile {
                        phase: crate::protocol::EnemyPhase::Idle,
                        ..
                    })
                ) && (target.x - me.x).hypot(target.z - me.z) > DISTANT_IDLE
            });
        if action.look_at.is_some() && self.m19_hops.flying.is_none() && !distant_idle {
            self.press_down = false;
            return navigator.route_snapshot_with_visibility(
                world,
                id,
                snapshot,
                action,
                true,
                &world.planning_arena().solids,
            );
        }
        let aim = (action.look_at.clone(), action.fire);
        let Some(current) = self
            .state
            .as_ref()
            .and_then(|s| s.m19.as_ref())
            .and_then(|f| f.current.clone())
        else {
            return Action::default();
        };
        match current.action {
            MissionObjectiveAction::Arrival {
                region,
                feet: destination,
            } => {
                self.press_down = false;
                if let Some(input) = self.m19_hop(navigator, world, snapshot, id, feet, &region) {
                    return input;
                }
                // Arrived while the group that gates this objective still
                // stands: close on the nearest living hostile the snapshot
                // shows, and keep that hunt until it falls or the objective moves.
                let objective = self
                    .state
                    .as_ref()
                    .and_then(|s| s.m19.as_ref())
                    .map_or(0, |f| f.completed.len());
                let alive = |target: Uuid| {
                    snapshot
                        .players
                        .iter()
                        .find(|p| p.id == target && p.hp > 0 && me.is_hostile_to(p))
                };
                if self
                    .m19_hops
                    .hunt
                    .is_some_and(|(target, at)| at != objective || alive(target).is_none())
                {
                    self.m19_hops.hunt = None;
                }
                if self.m19_hops.hunt.is_none() && region.contains(feet) {
                    self.m19_hops.hunt = snapshot
                        .players
                        .iter()
                        .filter(|p| {
                            p.hp > 0
                                && me.is_hostile_to(p)
                                && matches!(
                                    p.campaign,
                                    Some(crate::protocol::CampaignActor::Hostile { .. })
                                )
                                && (p.x - feet[0]).hypot(p.z - feet[2]) <= HUNT_RANGE
                        })
                        .min_by(|a, b| {
                            (a.x - feet[0])
                                .hypot(a.z - feet[2])
                                .total_cmp(&(b.x - feet[0]).hypot(b.z - feet[2]))
                        })
                        .map(|p| (p.id, objective));
                }
                let goal = self
                    .m19_hops
                    .hunt
                    .and_then(|(target, _)| alive(target))
                    .map_or(
                        NavigationGoal {
                            feet: destination,
                            combat: false,
                        },
                        // Walk the route to it rather than holding on sight: a
                        // dormant straggler across an open market is visible
                        // long before it is in engagement range, and holding
                        // there would wait on it forever. Inside that range the
                        // combat route above takes over.
                        |p| NavigationGoal {
                            feet: [p.x, p.y - PLAYER_FLOOR_Y, p.z],
                            combat: false,
                        },
                    );
                let mut moved = navigator.steer(
                    world,
                    feet,
                    goal,
                    Action {
                        weapon_swap: action.weapon_swap,
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                );
                if aim.0.is_some() {
                    moved.look_at = aim.0;
                    moved.fire = aim.1;
                }
                moved
            }
            MissionObjectiveAction::Use { target } => {
                let Some(points) = self.m19_points else {
                    return Action::default();
                };
                let point = if current.id == "concourse_stores" {
                    points[0]
                } else {
                    points[1]
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }

    /// Walk to an authored launch whose landing lies inside the objective,
    /// then fly it. A hop that runs out of time is abandoned for walking.
    fn m19_hop(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        snapshot: &Snapshot,
        id: Uuid,
        feet: [f32; 3],
        region: &crate::protocol::Region3,
    ) -> Option<Action> {
        let g = self.m19_map.as_ref()?;
        let fuel = snapshot
            .jetpacks
            .iter()
            .find(|pack| pack.player_id == id)
            .map(|pack| pack.fuel)?;
        if let Some((index, started)) = self.m19_hops.flying {
            let hop = g.jet_hops.get(index)?;
            if region.contains(feet) || snapshot.tick.saturating_sub(started) > u64::from(HOP_TICKS)
            {
                if !region.contains(feet) {
                    self.m19_hops.failed[index] = true;
                }
                self.m19_hops.flying = None;
                navigator.clear();
                return None;
            }
            let input = hop_input(
                crate::movement::MoveState {
                    x: feet[0],
                    z: feet[2],
                    y: feet[1],
                    vx: 0.0,
                    vz: 0.0,
                    vy: 0.0,
                    yaw: 0.0,
                },
                hop.landing,
            );
            return Some(Action {
                forward: input.forward,
                jump: input.jump,
                yaw: Some(input.yaw),
                ..Action::default()
            });
        }
        let (index, hop) =
            g.jet_hops.iter().enumerate().find(|(index, hop)| {
                !self.m19_hops.failed[*index] && region.contains(hop.landing)
            })?;
        if fuel < HOP_FUEL {
            return None;
        }
        let at_launch = (feet[0] - hop.launch[0]).hypot(feet[2] - hop.launch[2]) <= LAUNCH_REACH
            && (feet[1] - hop.launch[1]).abs() <= 0.05;
        if at_launch {
            self.m19_hops.flying = Some((index, snapshot.tick));
            navigator.clear();
            let input = hop_input(
                crate::movement::MoveState {
                    x: feet[0],
                    z: feet[2],
                    y: feet[1],
                    vx: 0.0,
                    vz: 0.0,
                    vy: 0.0,
                    yaw: 0.0,
                },
                hop.landing,
            );
            return Some(Action {
                forward: input.forward,
                jump: input.jump,
                yaw: Some(input.yaw),
                ..Action::default()
            });
        }
        Some(navigator.steer(
            world,
            feet,
            NavigationGoal {
                feet: hop.launch,
                combat: false,
            },
            Action::default(),
            snapshot.tick,
            true,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_crosses_the_nearer_open_edge_and_ignores_bodies_outside() {
        let strip = PaverStripState {
            owner_id: Uuid::nil(),
            origin: [0.0, 0.0, 0.0],
            yaw: 0.0,
            length: 10.0,
            half_width: 1.6,
            working: false,
            phase_started: 0,
            phase_ends: 30,
        };
        // Strip runs +x; lateral is +z. Nearer edge is +z for a body at z 0.5.
        let yaw = strip_escape(&strip, [5.0, 0.0, 0.5], &[]).unwrap();
        assert!((yaw - std::f32::consts::FRAC_PI_2).abs() < 1e-4);
        let yaw = strip_escape(&strip, [5.0, 0.0, -0.5], &[]).unwrap();
        assert!((yaw - 3.0 * std::f32::consts::FRAC_PI_2).abs() < 1e-4);
        // A wall on the nearer side sends the body across the other edge.
        let wall = [Solid::from_center_top(5.0, 2.6, 4.0, 0.2, 4.5)];
        let yaw = strip_escape(&strip, [5.0, 0.0, 0.5], &wall).unwrap();
        assert!((yaw - 3.0 * std::f32::consts::FRAC_PI_2).abs() < 1e-4);
        for outside in [
            [5.0, 0.0, 2.0],
            [-1.0, 0.0, 0.0],
            [11.0, 0.0, 0.0],
            [5.0, 1.0, 0.0],
        ] {
            assert!(strip_escape(&strip, outside, &[]).is_none(), "{outside:?}");
        }
    }
}
