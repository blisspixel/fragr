//! A conservative visual model of the painted floor, independent of whether
//! the projector's owner is visible. Fifteen fixed interior samples use the
//! profile's range, field of view and solid occlusion. A narrow visible sliver
//! between samples may be missed; light spill and audio are not recognition.
//! This is a declared controller model, not a rendered-legibility measurement.
use super::{visible, Profile};
use fragr_server::movement::Arena;
use fragr_server::protocol::{PaverStripState, PlayerState, Snapshot};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

#[derive(Default)]
pub(super) struct Perception {
    seen: BTreeMap<Uuid, Observation>,
}

struct Observation {
    strip: PaverStripState,
    since: u64,
    last_tick: u64,
}

impl Observation {
    fn continues(&self, strip: &PaverStripState, tick: u64) -> bool {
        let old = &self.strip;
        let same_geometry = old.origin == strip.origin
            && old.yaw == strip.yaw
            && old.length == strip.length
            && old.half_width == strip.half_width;
        let same_phase = old.working == strip.working
            && old.phase_started == strip.phase_started
            && old.phase_ends == strip.phase_ends;
        let began_work = !old.working && strip.working && strip.phase_started == old.phase_ends;
        // The survey observes every live tick. A gap or rewind cannot stand
        // in for continued observation; duplicate reads earn no elapsed time.
        let consecutive = tick == self.last_tick || self.last_tick.checked_add(1) == Some(tick);
        same_geometry && consecutive && (same_phase || began_work)
    }
}

fn floor_visible(
    strip: &PaverStripState,
    me: &PlayerState,
    arena: &Arena,
    profile: Profile,
) -> bool {
    let forward = [strip.yaw.cos(), strip.yaw.sin()];
    let lateral = [-forward[1], forward[0]];
    [0.05, 0.25, 0.5, 0.75, 0.95].into_iter().any(|along| {
        [-0.75, 0.0, 0.75].into_iter().any(|across| {
            visible(
                me,
                [
                    strip.origin[0]
                        + forward[0] * strip.length * along
                        + lateral[0] * strip.half_width * across,
                    // Same floor lift as the presenter's painted strip.
                    strip.origin[1] + 0.03,
                    strip.origin[2]
                        + forward[1] * strip.length * along
                        + lateral[1] * strip.half_width * across,
                ],
                arena,
                profile,
            )
        })
    })
}

impl Perception {
    pub(super) fn filter(
        &mut self,
        snapshot: &mut Snapshot,
        me: &PlayerState,
        arena: &Arena,
        profile: Profile,
    ) {
        let tick = snapshot.tick;
        let mut visible_owners = BTreeSet::new();
        snapshot.paver_strips.retain(|strip| {
            if !floor_visible(strip, me, arena, profile) {
                return false;
            }
            visible_owners.insert(strip.owner_id);
            let observation = self.seen.entry(strip.owner_id).or_insert(Observation {
                strip: *strip,
                since: tick,
                last_tick: tick,
            });
            if !observation.continues(strip, tick) {
                observation.since = tick;
            }
            observation.strip = *strip;
            observation.last_tick = tick;
            tick.saturating_sub(observation.since) >= profile.reaction_ticks
        });
        self.seen.retain(|owner, _| visible_owners.contains(owner));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::campaign::{constrain, visible_aim, PROFILES};
    use fragr_server::maps::AuthoredSource;
    use fragr_server::mission::MissionClient;
    use fragr_server::movement::Solid;
    use fragr_server::navigation::Navigator;
    use fragr_server::protocol::{Action, MissionId, MissionReady, Role};
    use fragr_server::session::GameSession;
    use fragr_server::sim::PLAYER_FLOOR_Y;
    use std::f32::consts::FRAC_PI_2;

    fn scene() -> (Snapshot, PlayerState, Arena, PaverStripState) {
        // Isolated perception facts, not earned campaign progress.
        let mut session = GameSession::new();
        let id = Uuid::from_u128(1);
        session.state.add_player(id, "Viewer".into(), Role::Human);
        let mut snapshot = session.state.snapshot();
        let me = snapshot.players.iter_mut().find(|p| p.id == id).unwrap();
        me.x = 0.0;
        me.y = PLAYER_FLOOR_Y;
        me.z = 0.0;
        me.yaw = 0.0;
        me.pitch = 0.0;
        let me = me.clone();
        let strip = PaverStripState {
            owner_id: Uuid::from_u128(2),
            origin: [8.0, 0.0, 0.0],
            yaw: 0.0,
            length: 10.0,
            half_width: 1.6,
            working: false,
            phase_started: 0,
            phase_ends: 34,
        };
        (
            snapshot,
            me,
            Arena {
                half: 64.0,
                solids: Vec::new(),
            },
            strip,
        )
    }

    fn sees(
        perception: &mut Perception,
        snapshot: &Snapshot,
        me: &PlayerState,
        arena: &Arena,
        strip: Option<PaverStripState>,
        tick: u64,
        profile: Profile,
    ) -> bool {
        let mut observed = snapshot.clone();
        observed.tick = tick;
        observed.paver_strips = strip.into_iter().collect();
        perception.filter(&mut observed, me, arena, profile);
        !observed.paver_strips.is_empty()
    }

    fn wall() -> Solid {
        Solid {
            min_x: 4.0,
            max_x: 5.0,
            min_z: -3.0,
            max_z: 3.0,
            bottom: 0.0,
            top: 4.0,
        }
    }

    #[test]
    fn floor_recognition_refuses_cover_rear_range_and_vertical_view() {
        let (snapshot, me, mut arena, strip) = scene();
        let mut perception = Perception::default();
        assert!(sees(
            &mut perception,
            &snapshot,
            &me,
            &arena,
            Some(strip),
            0,
            PROFILES[0]
        ));
        arena.solids.push(wall());
        assert!(!sees(
            &mut perception,
            &snapshot,
            &me,
            &arena,
            Some(strip),
            1,
            PROFILES[0]
        ));
        arena.solids.clear();
        for origin in [[-20.0, 0.0, 0.0], [49.0, 0.0, 0.0], [8.0, 40.0, 0.0]] {
            let hidden = PaverStripState { origin, ..strip };
            assert!(!sees(
                &mut perception,
                &snapshot,
                &me,
                &arena,
                Some(hidden),
                2,
                PROFILES[0]
            ));
        }
    }

    #[test]
    fn exposed_floor_is_seen_even_when_the_owner_is_obscured_or_filtered_out() {
        let (snapshot, me, mut arena, strip) = scene();
        let mut owner = me.clone();
        owner.id = strip.owner_id;
        owner.x = 10.0;
        let mut narrow = wall();
        narrow.min_z = -0.3;
        narrow.max_z = 0.3;
        arena.solids.push(narrow);
        assert!(visible_aim(&me, &owner, &arena, PROFILES[0]).is_none());
        assert!(!snapshot.players.iter().any(|p| p.id == strip.owner_id));
        let mut perception = Perception::default();
        for tick in 0..=PROFILES[1].reaction_ticks {
            assert_eq!(
                sees(
                    &mut perception,
                    &snapshot,
                    &me,
                    &arena,
                    Some(strip),
                    tick,
                    PROFILES[1]
                ),
                tick == PROFILES[1].reaction_ticks
            );
        }
    }

    #[test]
    fn absence_or_occlusion_requires_a_fresh_continuous_reaction() {
        let (snapshot, me, arena, strip) = scene();
        let profile = PROFILES[1];
        for absent in [false, true] {
            let mut perception = Perception::default();
            for tick in 0..=profile.reaction_ticks {
                sees(
                    &mut perception,
                    &snapshot,
                    &me,
                    &arena,
                    Some(strip),
                    tick,
                    profile,
                );
            }
            let mut blocked = arena.clone();
            if !absent {
                blocked.solids.push(wall());
            }
            assert!(!sees(
                &mut perception,
                &snapshot,
                &me,
                &blocked,
                (!absent).then_some(strip),
                6,
                profile
            ));
            for tick in 7..=12 {
                assert_eq!(
                    sees(
                        &mut perception,
                        &snapshot,
                        &me,
                        &arena,
                        Some(strip),
                        tick,
                        profile
                    ),
                    tick == 12
                );
            }
        }
    }

    #[test]
    fn an_old_offscreen_tell_does_not_skip_the_observed_reaction_delay() {
        let (snapshot, me, arena, strip) = scene();
        let strip = PaverStripState {
            phase_started: 80,
            phase_ends: 114,
            ..strip
        };
        let mut perception = Perception::default();
        for tick in 100..=105 {
            assert_eq!(
                sees(
                    &mut perception,
                    &snapshot,
                    &me,
                    &arena,
                    Some(strip),
                    tick,
                    PROFILES[1]
                ),
                tick == 105
            );
        }
    }

    #[test]
    fn continuous_preparation_to_work_keeps_the_same_observation_age() {
        let (snapshot, me, arena, strip) = scene();
        let mut strip = PaverStripState {
            phase_ends: 3,
            ..strip
        };
        let mut perception = Perception::default();
        for tick in 0..=6 {
            if tick == 3 {
                strip.working = true;
                strip.phase_started = 3;
                strip.phase_ends = 15;
            }
            assert_eq!(
                sees(
                    &mut perception,
                    &snapshot,
                    &me,
                    &arena,
                    Some(strip),
                    tick,
                    PROFILES[1]
                ),
                tick >= 5
            );
        }
    }

    #[test]
    fn a_new_tell_or_changed_geometry_restarts_reaction_despite_a_visible_owner() {
        let (mut snapshot, me, arena, strip) = scene();
        let mut owner = me.clone();
        owner.id = strip.owner_id;
        owner.x = 8.0;
        snapshot.players.push(owner);
        for fresh in [
            PaverStripState {
                phase_started: 6,
                phase_ends: 40,
                ..strip
            },
            PaverStripState {
                origin: [8.5, 0.0, 0.0],
                ..strip
            },
            PaverStripState { yaw: 0.1, ..strip },
            PaverStripState {
                length: 9.0,
                ..strip
            },
        ] {
            let mut perception = Perception::default();
            for tick in 0..=5 {
                sees(
                    &mut perception,
                    &snapshot,
                    &me,
                    &arena,
                    Some(strip),
                    tick,
                    PROFILES[1],
                );
            }
            for tick in 6..=11 {
                assert_eq!(
                    sees(
                        &mut perception,
                        &snapshot,
                        &me,
                        &arena,
                        Some(fresh),
                        tick,
                        PROFILES[1]
                    ),
                    tick == 11
                );
            }
        }
    }

    #[test]
    fn skipped_observations_and_duplicate_reads_cannot_earn_reaction_time() {
        let (snapshot, me, arena, strip) = scene();
        let mut perception = Perception::default();
        for _ in 0..10 {
            assert!(!sees(
                &mut perception,
                &snapshot,
                &me,
                &arena,
                Some(strip),
                0,
                PROFILES[1]
            ));
        }
        assert!(!sees(
            &mut perception,
            &snapshot,
            &me,
            &arena,
            Some(strip),
            20,
            PROFILES[1]
        ));
        for tick in 21..=25 {
            assert_eq!(
                sees(
                    &mut perception,
                    &snapshot,
                    &me,
                    &arena,
                    Some(strip),
                    tick,
                    PROFILES[1]
                ),
                tick == 25
            );
        }
        assert!(!sees(
            &mut perception,
            &snapshot,
            &me,
            &arena,
            Some(strip),
            0,
            PROFILES[1]
        ));
    }

    #[test]
    fn actual_m19_controller_gets_no_strip_escape_before_recognition() {
        // Isolated public-input fixture. No campaign clear or earned strip is
        // claimed: the synthetic tell tests the real MissionClient boundary.
        let mut session = GameSession::with_authored_map(
            AuthoredSource::Mission(MissionId::PlannedWorks)
                .load()
                .unwrap(),
        );
        let id = Uuid::from_u128(19);
        session
            .state
            .add_player(id, "Strip calibration".into(), Role::Human);
        assert!(session.state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::PlannedWorks,
                attempt: 1
            }
        ));
        let map = &session.state.map;
        let state = session.state.mission_state().unwrap();
        let snapshot = session.state.snapshot();
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        let strip = PaverStripState {
            owner_id: Uuid::from_u128(1919),
            origin: [me.x - 5.0, me.y - PLAYER_FLOOR_Y, me.z],
            yaw: 0.0,
            length: 10.0,
            half_width: 1.6,
            working: false,
            phase_started: 0,
            phase_ends: 34,
        };
        let drive = |view: &Snapshot| {
            let mut client = MissionClient::default();
            client
                .replace_map_with_id(
                    map.id(),
                    None,
                    false,
                    None,
                    map.half_extent(),
                    &map.arena().solids,
                    map.presentation_ref(),
                )
                .unwrap();
            client
                .replace_map_with_m19(
                    map.m19_geometry().as_ref(),
                    map.half_extent(),
                    &map.arena().solids,
                    map.presentation_ref(),
                )
                .unwrap();
            client.observe(view.tick, state.clone()).unwrap();
            client.steer_with_equipment(
                &mut Navigator::default(),
                map.navigation(),
                id,
                view,
                Action::default(),
                None,
            )
        };
        let baseline = drive(&snapshot);
        let mut perception = Perception::default();
        for tick in 0..=PROFILES[1].reaction_ticks {
            let mut observed = snapshot.clone();
            observed.tick = tick;
            observed.paver_strips.push(strip);
            perception.filter(&mut observed, me, map.arena(), PROFILES[1]);
            let wanted = drive(&observed);
            if tick < PROFILES[1].reaction_ticks {
                assert_eq!(
                    serde_json::to_value(&wanted).unwrap(),
                    serde_json::to_value(&baseline).unwrap(),
                    "hidden strip cannot change ordinary route input"
                );
            } else {
                assert!(wanted.forward);
                assert!((wanted.yaw.unwrap() - FRAC_PI_2).abs() < 0.0001);
                assert_ne!(
                    serde_json::to_value(&wanted).unwrap(),
                    serde_json::to_value(&baseline).unwrap()
                );
                let action = constrain(wanted, me, &observed, PROFILES[1], 42, map.arena());
                assert!(action.look_at.is_none());
                assert!(!action.fire);
                assert!((action.yaw.unwrap() - me.yaw).abs() <= 9_f32.to_radians() + 0.0001);
            }
        }
    }
}
