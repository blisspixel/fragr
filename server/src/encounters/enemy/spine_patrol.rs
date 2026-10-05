//! One shared authored march cadence, before the file notices actual combat.
use crate::maps::SpinePatrol;

pub(super) struct SpineMarch {
    parameters: SpinePatrol,
    member: usize,
    started: Option<u64>,
}

impl SpineMarch {
    pub(super) fn new(parameters: SpinePatrol, member: usize) -> Self {
        Self {
            parameters,
            member,
            started: None,
        }
    }

    pub(super) fn start(&mut self, tick: u64) {
        self.started.get_or_insert(tick);
    }

    pub(super) fn destination(&self, tick: u64) -> Option<[f32; 3]> {
        let elapsed = tick.checked_sub(self.started?)?;
        let period = u64::from(self.parameters.cycle_ticks);
        let phase = (elapsed % period) as f32 / period as f32;
        let progress = if phase <= 0.5 {
            phase * 2.0
        } else {
            (1.0 - phase) * 2.0
        };
        Some([
            self.parameters.from[0],
            self.parameters.from[1],
            self.parameters.from[2] + (self.parameters.to[2] - self.parameters.from[2]) * progress
                - self.member as f32 * self.parameters.spacing,
        ])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn m11_spine_march_shares_activation_and_cadence_without_restarting_on_dispatch() {
        let parameters = SpinePatrol {
            from: [0.0, 0.3, -22.0],
            to: [0.0, 0.3, -13.0],
            cycle_ticks: 320,
            spacing: 1.4,
        };
        let mut marches: Vec<_> = (0..3)
            .map(|member| SpineMarch::new(parameters.clone(), member))
            .collect();
        for march in &mut marches {
            assert!(march.destination(20).is_none());
            march.start(20);
            march.start(50);
        }
        for (tick, lead) in [
            (20, -22.0),
            (100, -17.5),
            (180, -13.0),
            (260, -17.5),
            (340, -22.0),
        ] {
            for (member, march) in marches.iter().enumerate() {
                let actual = march.destination(tick).unwrap();
                assert!((actual[2] - (lead - member as f32 * 1.4)).abs() < 0.001);
                assert_eq!(actual[0], 0.0);
                assert_eq!(actual[1], 0.3);
            }
        }
        assert!(marches[0].destination(19).is_none());
    }

    #[test]
    fn m11_spine_march_uses_actual_session_movement_contact_then_visible_combat() {
        use crate::protocol::{Action, CampaignActor, EnemyPhase, Role};
        use crate::session::GameSession;
        use crate::sim::PLAYER_FLOOR_Y;
        let map = crate::maps::AuthoredMap::read(
            include_bytes!("../../../maps/m11_right_of_search.json").as_slice(),
        )
        .unwrap();
        let mut session = GameSession::with_authored_map(map);
        let eye = [-4.0, 1.9, -24.3];
        for enemy in &session.state.map.encounters()[0].enemies {
            let target = [enemy.feet[0], enemy.feet[1] + 0.9, enemy.feet[2]];
            assert!(
                !crate::combat::line_of_sight(eye, target, &session.state.map.arena().solids),
                "the authored armory stance must really be sheltered"
            );
        }
        let id = uuid::Uuid::from_u128(1115);
        session
            .state
            .add_player(id, "Tender patrol witness".into(), Role::Human);
        session.state.start_round();
        // Supported isolated encounter setup behind actual armory cover. Every
        // subsequent guard/player displacement is ordinary session integration.
        session.state.players[0].x = -4.0;
        session.state.players[0].z = -24.3;
        session.state.players[0].y = 0.3 + PLAYER_FLOOR_Y;
        session.state.players[0].yaw = 0.0;
        let mut previous: Option<f32> = None;
        let mut forwards = false;
        let mut backwards = false;
        let mut stopped = false;
        for _ in 0..720 {
            session.tick_messages(0.05);
            let mut file: Vec<_> = session
                .state
                .players
                .iter()
                .filter(|p| p.id != id)
                .collect();
            file.sort_by(|a, b| a.z.total_cmp(&b.z));
            assert_eq!(file.len(), 3);
            for guard in &file {
                assert!(guard.x.abs() < 0.1);
                assert!((guard.y - PLAYER_FLOOR_Y - 0.3).abs() < 0.001);
                assert!(!guard.just_fired);
            }
            for pair in file.windows(2) {
                assert!((1.0..=1.8).contains(&(pair[1].z - pair[0].z)));
            }
            let lead = file[2].z;
            assert!((-22.07..=-12.93).contains(&lead));
            if let Some(previous) = previous {
                let displacement = lead - previous;
                assert!(
                    displacement.abs() <= 0.126,
                    "no displacement bypasses live walking"
                );
                forwards |= displacement > 0.01;
                backwards |= displacement < -0.01;
                stopped |= displacement.abs() < 0.001;
            }
            previous = Some(lead);
            assert_eq!(session.state.players[0].hp, 100);
        }
        assert!(
            forwards && backwards && stopped,
            "real file must walk, pause and return"
        );
        assert!(
            session.state.encounters.is_awake(0),
            "patrol not awake, tick {}, players {:?}",
            session.state.tick,
            session.state.snapshot().players
        );
        assert!(!session.state.encounters.is_awake(1));
        let guards: Vec<_> = session
            .state
            .players
            .iter()
            .filter(|p| {
                matches!(
                    p.campaign,
                    Some(CampaignActor::Union {
                        kind: crate::protocol::EnemyKind::Clerk,
                        ..
                    })
                )
            })
            .collect();
        assert_eq!(guards.len(), 3);
        for guard in &guards {
            assert!((guard.y - PLAYER_FLOOR_Y - 0.3).abs() < 0.001);
            assert!(
                guard.x.abs() < 0.1,
                "file lane drift: {:?}",
                session.state.snapshot().players
            );
            assert!(matches!(
                guard.campaign,
                Some(CampaignActor::Union {
                    phase: EnemyPhase::Moving,
                    ..
                })
            ));
            assert!(!guard.just_fired);
        }
        let mut z: Vec<_> = guards.iter().map(|p| p.z).collect();
        z.sort_by(f32::total_cmp);
        assert!(
            z[2] > -20.0,
            "the file must really walk, not just change an animation"
        );
        for pair in z.windows(2) {
            assert!(
                (1.0..=1.8).contains(&(pair[1] - pair[0])),
                "file must respect actual body contact and spacing: {z:?}"
            );
        }
        assert_eq!(
            session.state.players[0].hp, 100,
            "hidden file cannot attack through the armory wall"
        );
        // Ordinary return through the real armory doorway, not through its wall.
        session.state.set_action(
            id,
            Action {
                forward: true,
                yaw: Some(std::f32::consts::PI * 1.5),
                ..Action::default()
            },
        );
        for _ in 0..9 {
            session.tick_messages(0.05);
        }
        assert!((session.state.players[0].z + 26.55).abs() < 0.02);
        session.state.set_action(
            id,
            Action {
                forward: true,
                yaw: Some(0.0),
                ..Action::default()
            },
        );
        let mut committed = false;
        for _ in 0..20 {
            session.tick_messages(0.05);
            committed |= session.state.players.iter().any(|p| {
                matches!(
                    p.campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Windup | EnemyPhase::Firing,
                        ..
                    })
                )
            });
        }
        assert!(
            committed,
            "an actually visible participant interrupts the fixed file into ordinary combat"
        );
        assert!(session
            .state
            .encounters
            .enemies
            .iter()
            .filter(|(group, _)| *group == 0)
            .all(|(_, enemy)| enemy.spine_march.is_none()));
    }

    #[test]
    fn m11_spine_march_damage_interrupt_removes_cadence_without_restarting() {
        use crate::encounters::enemy::EnemyController;
        use crate::protocol::{EnemyKind, EnemyPhase};
        let mut guard = EnemyController::new(
            uuid::Uuid::nil(),
            EnemyKind::Clerk,
            [0.0, 0.3, -22.0],
            std::f32::consts::FRAC_PI_2,
            0,
            false,
        )
        .with_spine_march(
            Some(SpinePatrol {
                from: [0.0, 0.3, -22.0],
                to: [0.0, 0.3, -13.0],
                cycle_ticks: 320,
                spacing: 1.4,
            }),
            0,
        );
        guard.alarm([-4.0, 0.3, -24.3], 1);
        assert!(guard
            .spine_march
            .as_ref()
            .unwrap()
            .destination(20)
            .is_some());
        guard.hit(20, false);
        assert!(guard.spine_march.is_none());
        assert_eq!(guard.phase(), EnemyPhase::Hit);
        guard.alarm([-4.0, 0.3, -24.3], 30);
        assert!(guard.spine_march.is_none());
        guard.hit(31, true);
        assert_eq!(guard.phase(), EnemyPhase::Dead);
    }
}
