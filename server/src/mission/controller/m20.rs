use super::*;
use crate::protocol::{
    M20MapGeometry, MissionObjective, PickupState, WeaponType, M20_OBJECTIVE_IDS,
};

/// While holding, an agent leaves its post for a released crate only when
/// it needs what the crate holds and the crate is this close to the post.
const RESUPPLY_REACH: f32 = 17.0;
/// How far a hunt may pull the agent off its pier post.
const HOLD_LEASH: f32 = 10.0;
/// Below this health a holding agent keeps within `HURT_LEASH` of its post.
const HURT_HEALTH: i32 = 70;
const HURT_LEASH: f32 = 5.0;
/// Below this health a holding agent breaks off for a medical crate.
const URGENT_HEALTH: i32 = 50;
/// A crate is only worth breaking off a fight for when it is a few steps away.
const URGENT_REACH: f32 = 8.0;
/// Ammunition below this share of capacity counts as a need.
const LOW_AMMO_SHARE: f32 = 0.35;
/// Below this share the agent walks to any crate on the quay for it.
const STARVED_SHARE: f32 = 0.12;
const STARVED_REACH: f32 = 30.0;
/// A Surveyor this close to an agent in a lesson is the lesson's.
const LESSON_SEEK: f32 = 40.0;

impl MissionClient {
    pub fn replace_map_with_m20(
        &mut self,
        geometry: Option<&M20MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m20_map = None;
            self.m20_point = None;
            self.m20_pending = false;
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
            return Err("M20 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m20_map {
            let mut same = old.clone();
            same.gate_open = g.gate_open;
            if &same != g || old.gate_open && !g.gate_open {
                return Err("M20 static map contract changed");
            }
        }
        let present = presentation.ok_or("M20 presentation missing")?;
        self.m20_point = Some(
            g.departure
                .point(present, solids)
                .ok_or("M20 crossing control missing")?,
        );
        self.m20_map = Some(g.clone());
        self.m20_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m20_target(
        &self,
        tick: u64,
        state: &MissionState,
    ) -> Result<(), &'static str> {
        let g = self.m20_map.as_ref().ok_or("M20 geometry missing")?;
        let f = state.m20.as_ref().ok_or("M20 facts missing")?;
        if let Some(reached) = f.pier_reached_at {
            state.validate_with_clock(Some(g.clock(reached)), tick)?;
        }
        let done = f.completed.len();
        let expected = if done < M20_OBJECTIVE_IDS.len() {
            Some(g.objectives[done].clone())
        } else if done == M20_OBJECTIVE_IDS.len() {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected {
            return Err("M20 objective disagrees with map");
        }
        if f.gate_open != g.gate_open {
            return Err("M20 gate disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m20.as_ref().ok_or("M20 prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.challenges.mark_broken && !f.challenges.mark_broken
                    || old_f.challenges.crew_crossed && !f.challenges.crew_crossed
                    || !old_f.challenges.refuge_held && f.challenges.refuge_held
                    || f.refuge_integrity > old_f.refuge_integrity
                    || old_f.pier_reached_at.is_some()
                        && old_f.pier_reached_at != f.pier_reached_at
                    || old_f.reprieve_at.is_some() && old_f.reprieve_at != f.reprieve_at
                    || old_f.gate_open && !f.gate_open
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M20 attempt moved backwards");
            }
        }
        Ok(())
    }

    /// Remember the controlled body's equipment so the hold can judge need.
    pub(super) fn note_m20_loadout(&mut self, loadout: Option<&crate::protocol::LoadoutState>) {
        self.m20_loadout = loadout.cloned();
    }

    fn m20_needs(&self, me: &crate::protocol::PlayerState, pickup: &PickupState) -> bool {
        match pickup.kind.as_str() {
            "health" => me.hp < 60,
            "armor" => me.armor < 25,
            "ammo" => self.m20_loadout.as_ref().is_some_and(|loadout| {
                let Some(pool) = pickup.pool else {
                    return false;
                };
                loadout.weapons.iter().any(|w| w.ammo_pool() == Some(pool))
                    && loadout.ammo.iter().any(|count| {
                        count.pool == pool
                            && f32::from(count.rounds) < f32::from(pool.capacity()) * LOW_AMMO_SHARE
                    })
            }),
            _ => false,
        }
    }

    /// Nearly out of the ammunition a crate holds: worth a longer walk.
    fn m20_starved(&self, pickup: &PickupState) -> bool {
        pickup.kind == "ammo"
            && pickup.pool.is_some_and(|pool| {
                self.m20_loadout.as_ref().is_some_and(|loadout| {
                    loadout.ammo.iter().any(|count| {
                        count.pool == pool
                            && f32::from(count.rounds) < f32::from(pool.capacity()) * STARVED_SHARE
                    })
                })
            })
    }

    /// The holding objective's post, while the agent is holding the pier.
    fn m20_post(&self) -> Option<[f32; 3]> {
        match self
            .state
            .as_ref()
            .and_then(|s| s.m20.as_ref())
            .and_then(|f| f.current.as_ref())
        {
            Some(MissionObjective {
                id,
                action: MissionObjectiveAction::Arrival { feet, .. },
            }) if matches!(id.as_str(), "pier_hold" | "last_six") => Some(*feet),
            _ => None,
        }
    }

    /// A defender holding the pier fights from it: a hunt past this distance
    /// from the post is left for the line to meet. Returns the post.
    fn m20_leashed(&self, snapshot: &Snapshot, id: Uuid) -> Option<[f32; 3]> {
        let me = snapshot.players.iter().find(|p| p.id == id && p.hp > 0)?;
        let post = self.m20_post()?;
        let leash = if me.hp < HURT_HEALTH {
            HURT_LEASH
        } else {
            HOLD_LEASH
        };
        ((me.x - post[0]).hypot(me.z - post[2]) > leash).then_some(post)
    }

    /// A defender that does not chase must reach what it fights: a target
    /// beyond the gun in hand takes the first carried gun with rounds that
    /// does reach it. The shared choice keeps a short gun once it holds one.
    fn m20_reach_weapon(&self, snapshot: &Snapshot, id: Uuid, action: &mut Action) {
        let (Some(loadout), Some(me)) = (
            self.m20_loadout.as_ref(),
            snapshot.players.iter().find(|p| p.id == id && p.hp > 0),
        ) else {
            return;
        };
        let Some(target) = action
            .look_at
            .as_ref()
            .and_then(|look| look.player_id)
            .and_then(|target| snapshot.players.iter().find(|p| p.id == target))
        else {
            return;
        };
        let distance = (target.x - me.x).hypot(target.z - me.z);
        let held = action.weapon_swap.unwrap_or(loadout.selected);
        if distance <= held.range_units() * 0.9 {
            return;
        }
        let reach = [
            WeaponType::Repeater,
            WeaponType::Flechette,
            WeaponType::Rail,
            WeaponType::Tack,
            WeaponType::Arc,
        ]
        .into_iter()
        .find(|weapon| {
            loadout.owns(*weapon)
                && loadout.shots(*weapon).is_none_or(|shots| shots > 0)
                && weapon.range_units() * 0.9 >= distance
        });
        if let Some(weapon) = reach {
            action.weapon_swap = (weapon != loadout.selected).then_some(weapon);
        }
    }

    /// Keep shooting and step back toward the post. Movement keys are in the
    /// aim's frame, so the post's bearing is turned into that frame.
    fn m20_fall_back(action: Action, snapshot: &Snapshot, id: Uuid, post: [f32; 3]) -> Action {
        let Some(me) = snapshot.players.iter().find(|p| p.id == id) else {
            return action;
        };
        let aim = action.look_at.as_ref().and_then(|look| {
            look.player_id
                .and_then(|target| snapshot.players.iter().find(|p| p.id == target))
                .map(|p| (p.x, p.z))
                .or(look.x.zip(look.z))
        });
        let Some((ax, az)) = aim else {
            return action;
        };
        let facing = (az - me.z).atan2(ax - me.x);
        let bearing = (post[2] - me.z).atan2(post[0] - me.x) - facing;
        let (along, across) = (bearing.cos(), bearing.sin());
        Action {
            forward: along > 0.38,
            back: along < -0.38,
            right: across > 0.38,
            left: across < -0.38,
            ..action
        }
    }

    fn m20_urgent_care(&self, snapshot: &Snapshot, id: Uuid) -> bool {
        let (Some(me), Some(post)) = (
            snapshot.players.iter().find(|p| p.id == id && p.hp > 0),
            self.m20_post(),
        ) else {
            return false;
        };
        me.hp < URGENT_HEALTH
            && snapshot.pickups.iter().any(|p| {
                p.available
                    && p.kind == "health"
                    && (p.x - post[0]).hypot(p.z - post[2]) <= RESUPPLY_REACH
                    && (p.x - me.x).hypot(p.z - me.z) <= URGENT_REACH
            })
    }

    /// The Surveyor never walks, and its tower hides it from the lesson's
    /// exit, so a lesson can wait on a spotter nobody can see. With no
    /// target in sight, the agent walks to the nearest open floor that sees
    /// the closest standing Surveyor, then the ordinary fight takes over.
    fn m20_vantage(
        &self,
        world: &Navigation,
        me: &crate::protocol::PlayerState,
        snapshot: &Snapshot,
    ) -> Option<[f32; 3]> {
        let arena = world.planning_arena();
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let target = snapshot
            .players
            .iter()
            .filter(|other| {
                me.is_hostile_to(other)
                    && matches!(
                        other.campaign,
                        Some(crate::protocol::CampaignActor::Hostile {
                            kind: crate::protocol::EnemyKind::Surveyor,
                            ..
                        })
                    )
            })
            .filter(|other| (other.x - me.x).hypot(other.z - me.z) <= LESSON_SEEK)
            .min_by(|a, b| {
                (a.x - me.x)
                    .hypot(a.z - me.z)
                    .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
            })?;
        let aim = [
            target.x,
            target.y - PLAYER_FLOOR_Y + crate::combat::aim_height(target.campaign),
            target.z,
        ];
        let mut best: Option<([f32; 3], f32)> = None;
        for ring in [8.0_f32, 12.0, 16.0] {
            for step in 0..16 {
                let angle = step as f32 * std::f32::consts::TAU / 16.0;
                let x = target.x + ring * angle.cos();
                let z = target.z + ring * angle.sin();
                if x.abs() > arena.half - 1.0 || z.abs() > arena.half - 1.0 {
                    continue;
                }
                let floor = arena.support_height(x, z, feet[1] + 1.5);
                let blocked = arena.solids.iter().any(|solid| {
                    solid.covers(x, z) && solid.bottom < floor + 1.8 && solid.top > floor + 0.05
                });
                if blocked
                    || !crate::combat::line_of_sight(
                        [x, floor + crate::movement::EYE_HEIGHT, z],
                        aim,
                        &arena.solids,
                    )
                {
                    continue;
                }
                let walk = (x - me.x).hypot(z - me.z);
                if best.is_none_or(|(_, d)| walk < d) {
                    best = Some(([x, floor, z], walk));
                }
            }
        }
        best.map(|(point, _)| point)
    }

    pub(super) fn steer_m20(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        // After the reprieve the machines walk around the refuge; nobody
        // chases them across the district.
        let mut action = action;
        if self
            .state
            .as_ref()
            .and_then(|s| s.m20.as_ref())
            .is_some_and(|f| f.reprieve_at.is_some())
        {
            action.look_at = None;
            action.fire = false;
        }
        // Badly hurt on the pier with a medical crate a few steps away: break
        // off and take it rather than trade shots to the end.
        if action.look_at.is_some() && self.m20_urgent_care(snapshot, id) {
            action.look_at = None;
            action.fire = false;
        }
        self.m20_reach_weapon(snapshot, id, &mut action);
        // Off its pier post, a defender does not chase: with a shot it fights
        // its way back, keeping the target in its sights; without one it
        // drops the hunt and returns to the post or a crate it needs. Hurt,
        // it keeps closer still.
        if action.look_at.is_some() {
            if let Some(post) = self.m20_leashed(snapshot, id) {
                navigator.clear();
                if action.fire {
                    return Self::m20_fall_back(action, snapshot, id, post);
                }
                action.look_at = None;
            }
        }
        if action.look_at.is_some() {
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
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            return Action::default();
        };
        let Some(current) = self
            .state
            .as_ref()
            .and_then(|s| s.m20.as_ref())
            .and_then(|f| f.current.as_ref())
            .cloned()
        else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        match current.action {
            MissionObjectiveAction::Arrival {
                feet: destination, ..
            } => {
                self.press_down = false;
                let holding = matches!(current.id.as_str(), "pier_hold" | "last_six");
                let lesson = matches!(current.id.as_str(), "sluice_crossing" | "crew_crossing");
                if let Some(vantage) = lesson
                    .then(|| self.m20_vantage(world, me, snapshot))
                    .flatten()
                {
                    return navigator.steer(
                        world,
                        feet,
                        NavigationGoal {
                            feet: vantage,
                            combat: false,
                        },
                        Action {
                            weapon_swap: action.weapon_swap,
                            throw_grenade: action.throw_grenade,
                            ..Action::default()
                        },
                        snapshot.tick,
                        true,
                    );
                }
                // Holding is not standing still at any cost: a needed crate
                // near the post is worth the walk.
                let resupply = holding
                    .then(|| {
                        snapshot
                            .pickups
                            .iter()
                            .filter(|p| p.available && self.m20_needs(me, p))
                            .filter(|p| {
                                let reach = if self.m20_starved(p) {
                                    STARVED_REACH
                                } else {
                                    RESUPPLY_REACH
                                };
                                (p.x - destination[0]).hypot(p.z - destination[2]) <= reach
                            })
                            .min_by(|a, b| {
                                (a.x - me.x)
                                    .hypot(a.z - me.z)
                                    .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
                            })
                            .map(|p| [p.x, p.y - 0.4, p.z])
                    })
                    .flatten();
                let goal = resupply.map_or(destination, |pickup| {
                    // A crate top is a step; route to the floor beside it and
                    // let the claim radius take it.
                    let floor = world.planning_arena().support_height(
                        pickup[0],
                        pickup[2],
                        pickup[1] + 1.0,
                    );
                    [pickup[0], floor, pickup[2]]
                });
                navigator.steer(
                    world,
                    feet,
                    NavigationGoal {
                        feet: goal,
                        combat: false,
                    },
                    Action {
                        weapon_swap: action.weapon_swap,
                        throw_grenade: action.throw_grenade,
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => {
                let Some(point) = self.m20_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
