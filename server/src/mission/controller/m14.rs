use super::*;
use crate::protocol::{M14MapGeometry, WalkerPhase, WeaponType, M14_OBJECTIVE_IDS};

impl MissionClient {
    pub(super) fn m14_visibility_solids(&self, snapshot: &Snapshot) -> Option<Vec<Solid>> {
        let g = self.m14_map.as_ref()?;
        let mut actual = self.m14_solids.clone();
        if let Some(w) = snapshot.walker.as_ref() {
            let origin = actual[g.walker_solids[0]];
            let start = [
                (origin.min_x + origin.max_x) * 0.5,
                0.0,
                (origin.min_z + origin.max_z) * 0.5,
            ];
            for i in g.walker_solids {
                let s = &mut actual[i];
                s.min_x += w.feet[0] - start[0];
                s.max_x += w.feet[0] - start[0];
                s.min_z += w.feet[2] - start[2];
                s.max_z += w.feet[2] - start[2];
            }
        }
        actual.extend(snapshot.vehicles.iter().map(crate::vehicles::hull));
        Some(actual)
    }
    pub fn replace_map_with_m14(
        &mut self,
        geometry: Option<&M14MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m14_map = None;
            self.m14_point = None;
            self.m14_solids.clear();
            self.m14_intact_solids.clear();
            self.m14_half = None;
            self.m14_presentation = None;
            self.m14_pending = false;
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
        {
            return Err("M14 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m14_map {
            let mut comparison = old.clone();
            comparison.fallen = g.fallen;
            if comparison != *g
                || self.m14_half != Some(half)
                || self.m14_presentation.as_ref() != presentation
                || self.m14_solids.len() != solids.len()
                || self
                    .m14_solids
                    .iter()
                    .zip(solids)
                    .enumerate()
                    .any(|(i, (a, b))| {
                        (!g.walker_solids.contains(&i) || old.fallen == g.fallen) && a != b
                    })
                || !g.fallen
                    && !self.m14_intact_solids.is_empty()
                    && self.m14_intact_solids != solids
            {
                return Err("M14 static contract changed");
            }
        }
        self.m14_point = g
            .departure
            .point(presentation.ok_or("M14 presentation missing")?, solids);
        if !g.fallen {
            self.m14_intact_solids = solids.to_vec();
        }
        self.m14_half = Some(half);
        self.m14_presentation = presentation.cloned();
        self.m14_map = Some(g.clone());
        self.m14_solids = solids.to_vec();
        self.m14_pending = true;
        self.press_down = false;
        Ok(())
    }
    pub(super) fn validate_m14_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m14_map.as_ref().ok_or("M14 geometry missing")?;
        let f = state.m14.as_ref().ok_or("M14 facts missing")?;
        let n = f.completed.len();
        let expected = if n < 6 {
            Some(g.objectives[n].clone())
        } else if n == 6 {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected || f.machine_fallen != g.fallen {
            return Err("M14 facts disagree with map");
        }
        if let Some(old) = self
            .state
            .as_ref()
            .filter(|s| s.id == state.id && s.attempt == state.attempt)
        {
            let previous = old.m14.as_ref().ok_or("M14 previous facts missing")?;
            if n < previous.completed.len()
                || f.support_stage < previous.support_stage
                || previous.first_cycle_complete && !f.first_cycle_complete
                || previous.machine_fallen && !f.machine_fallen
                || !previous.challenges.jeep_preserved && f.challenges.jeep_preserved
                || !previous.challenges.on_foot && f.challenges.on_foot
                || previous.challenges.walker_disabled && !f.challenges.walker_disabled
                || previous.challenges.walker_disabled
                    && (previous.challenges.jeep_preserved != f.challenges.jeep_preserved
                        || previous.challenges.on_foot != f.challenges.on_foot)
                || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing
            {
                return Err("M14 attempt moved backwards");
            }
        }
        Ok(())
    }
    pub(super) fn steer_m14_equipped(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        mut action: Action,
        loadout: Option<&crate::protocol::LoadoutState>,
    ) -> Action {
        if !self.participating(id) || self.m14_pending {
            navigator.clear();
            return Action::default();
        }
        if action.look_at.is_none()
            && snapshot
                .walker
                .as_ref()
                .is_some_and(|w| w.hp > 0 && w.phase != WalkerPhase::Dormant)
        {
            let Some(loadout) = loadout else {
                return Action::default();
            };
            if snapshot.walker.as_ref().unwrap().phase == WalkerPhase::Recovery
                && loadout.owns(WeaponType::Rocket)
                && loadout.ammo(crate::protocol::AmmoPool::Rockets) > 0
            {
                action.weapon_swap = Some(WeaponType::Rocket);
                action.reload = loadout.shots(WeaponType::Rocket) == Some(0);
            } else {
                let Some(equipped) =
                    crate::inventory::control_ray_objective(id, snapshot, loadout, action)
                else {
                    return Action::default();
                };
                action = equipped;
            }
        }
        self.steer(navigator, world, id, snapshot, action)
    }
    pub(super) fn steer_m14(
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
        let Some(g) = self.m14_map.clone() else {
            return Action::default();
        };
        let Some(f) = self.state.as_ref().and_then(|s| s.m14.as_ref()) else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let actual = self.m14_visibility_solids(snapshot).unwrap();
        // Keep moving clear of the locked line until its committed shells finish.
        // Returning to a target at the end of the launch animation would run into
        // shells that are still genuinely in flight.
        let dodge = snapshot
            .walker
            .as_ref()
            .filter(|w| {
                matches!(
                    w.phase,
                    WalkerPhase::ArtilleryWarning | WalkerPhase::Artillery
                ) || !w.shells.is_empty()
            })
            .map(|w| {
                let dx = w.target[0] - w.feet[0];
                let dz = w.target[2] - w.feet[2];
                let length = dx.hypot(dz).max(0.001);
                let perpendicular = [-dz / length, dx / length];
                [8.0, -8.0, 12.0, -12.0]
                    .into_iter()
                    .map(|offset| {
                        [
                            w.target[0] + perpendicular[0] * offset,
                            0.0,
                            w.target[2] + perpendicular[1] * offset,
                        ]
                    })
                    .filter(|p| world.floor_below(*p).is_some_and(|y| y.abs() < 0.01))
                    .min_by(|a, b| {
                        (!world.walkable(feet, *a))
                            .cmp(&(!world.walkable(feet, *b)))
                            .then(
                                (a[0] - feet[0])
                                    .hypot(a[2] - feet[2])
                                    .total_cmp(&(b[0] - feet[0]).hypot(b[2] - feet[2])),
                            )
                    })
                    .unwrap_or([w.target[0] - 8.0, 0.0, w.target[2]])
            });
        if let Some(goal) = dodge {
            self.press_down = false;
            let mut moved = navigator.steer_with_visibility(
                world,
                feet,
                NavigationGoal {
                    feet: goal,
                    combat: false,
                },
                Action {
                    weapon_swap: action.weapon_swap,
                    reload: action.reload,
                    ..Default::default()
                },
                snapshot.tick,
                true,
                &actual,
            );
            if let Some(target) = action
                .look_at
                .as_ref()
                .and_then(|a| a.player_id)
                .and_then(|id| {
                    snapshot
                        .players
                        .iter()
                        .find(|p| p.id == id && me.is_hostile_to(p))
                })
            {
                let aim_yaw = (target.z - me.z).atan2(target.x - me.x);
                if moved.forward {
                    let relative = moved.yaw.unwrap_or(me.yaw) - aim_yaw;
                    moved.forward = relative.cos() > 0.38;
                    moved.back = relative.cos() < -0.38;
                    moved.right = relative.sin() > 0.38;
                    moved.left = relative.sin() < -0.38;
                }
                moved.yaw = None;
                moved.look_at = action.look_at;
                moved.fire = action.fire
                    && crate::combat::line_of_sight(
                        [feet[0], feet[1] + crate::movement::EYE_HEIGHT, feet[2]],
                        [
                            target.x,
                            target.y - PLAYER_FLOOR_Y
                                + crate::combat::target_height(target.campaign) * 0.5,
                            target.z,
                        ],
                        &actual,
                    );
            }
            return moved;
        }
        if action.look_at.is_some() {
            self.press_down = false;
            return navigator
                .route_snapshot_with_visibility(world, id, snapshot, action, true, &actual);
        }
        if f.completed.len() == 4 {
            if let Some(w) = snapshot
                .walker
                .as_ref()
                .filter(|w| w.hp > 0 && w.phase != WalkerPhase::Dormant)
            {
                let goal = dodge.unwrap_or([w.feet[0] - 12.0, 0.0, w.feet[2] + 5.0]);
                let eye = [
                    me.x,
                    me.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
                    me.z,
                ];
                let target = g.walker_solids[1..].iter().find_map(|i| {
                    let s = actual[*i];
                    let aim = [s.min_x, 1.4, (s.min_z + s.max_z) * 0.5];
                    let cover: Vec<_> = actual
                        .iter()
                        .enumerate()
                        .filter(|(index, _)| index != i)
                        .map(|(_, s)| *s)
                        .collect();
                    crate::combat::line_of_sight(eye, aim, &cover).then_some(aim)
                });
                // Aim at the visible west face of a registered joint, not through its closed box.
                let s = actual[g.walker_solids[1]];
                let aim = target.unwrap_or([s.min_x, 1.4, (s.min_z + s.max_z) * 0.5]);
                let weapon = action
                    .weapon_swap
                    .or_else(|| WeaponType::ALL.into_iter().find(|w| w.name() == me.weapon));
                let in_range = weapon.is_some_and(|weapon| {
                    (aim[0] - me.x).hypot(aim[2] - me.z) < weapon.range_units()
                });
                if target.is_none() || !in_range {
                    return navigator.steer_with_visibility(
                        world,
                        feet,
                        NavigationGoal {
                            feet: goal,
                            combat: false,
                        },
                        Action {
                            weapon_swap: action.weapon_swap,
                            reload: action.reload,
                            ..Default::default()
                        },
                        snapshot.tick,
                        true,
                        &actual,
                    );
                }
                navigator.clear();
                return Action {
                    weapon_swap: action.weapon_swap,
                    reload: action.reload,
                    fire: !action.reload,
                    look_at: Some(LookAt {
                        x: Some(aim[0]),
                        y: Some(aim[1]),
                        z: Some(aim[2]),
                        player_id: None,
                    }),
                    ..Default::default()
                };
            }
        }
        let current = if f.completed.len() == M14_OBJECTIVE_IDS.len() {
            Some(g.departure_objective())
        } else {
            f.current.clone()
        };
        match current.map(|o| o.action) {
            Some(MissionObjectiveAction::Arrival {
                feet: destination, ..
            }) => navigator.steer_with_visibility(
                world,
                feet,
                NavigationGoal {
                    feet: destination,
                    combat: false,
                },
                Action {
                    weapon_swap: action.weapon_swap,
                    ..Default::default()
                },
                snapshot.tick,
                true,
                &actual,
            ),
            Some(MissionObjectiveAction::Use { target }) => {
                self.m14_point.map_or(Action::default(), |point| {
                    self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
                })
            }
            _ => Action::default(),
        }
    }
}
