use crate::movement::contact::ContactBody;
use crate::protocol::MissionPhase;
use crate::sim::{contact::civilian, GameState};

pub(super) fn move_on_route(
    key: &str,
    from: crate::movement::MoveState,
    proposed: crate::movement::MoveState,
    direction: [f32; 2],
    dt: f32,
    arena: &crate::movement::Arena,
    contacts: &[ContactBody],
) -> crate::movement::MoveState {
    let moved = crate::sim::contact::move_body(
        key,
        from,
        proposed,
        crate::movement::BODY_HEIGHT,
        dt,
        arena,
        contacts,
    );
    let step_x = moved.x - from.x;
    let step_z = moved.z - from.z;
    let lateral = step_x * direction[1] - step_z * direction[0];
    let forward = step_x * direction[0] + step_z * direction[1];
    if lateral.abs() > crate::movement::contact::EPSILON
        || forward < -crate::movement::contact::EPSILON
    {
        // Generic contacts slide around a circle. Fixed civilian routes have
        // no lateral corridor: wait for the living blocker to clear instead.
        crate::movement::integrate(
            crate::movement::MoveState {
                vx: 0.0,
                vz: 0.0,
                ..from
            },
            false,
            dt,
            arena,
        )
    } else {
        moved
    }
}

impl GameState {
    pub(crate) fn append_civilian_contacts(&self, bodies: &mut Vec<ContactBody>) {
        let Some(run) = self
            .mission
            .as_ref()
            .filter(|r| r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        if let Some(p) = run
            .m02
            .as_ref()
            .filter(|_| run.initial_map.has_m02_side_ward())
        {
            for (i, feet) in p.contact_feet().into_iter().enumerate() {
                bodies.push(civilian(format!("m02/captive/{i}"), feet));
            }
        }
        if let Some(p) = &run.m03 {
            for car in &p.cars {
                for (i, &feet) in car.captives.iter().enumerate() {
                    bodies.push(civilian(format!("m03/{}/{i}", car.id), feet));
                }
            }
        }
        if let Some(p) = &run.m04 {
            for patient in &p.patients {
                bodies.push(civilian(format!("m04/{}", patient.id), patient.feet));
            }
        }
        if let Some(p) = &run.m05 {
            for captive in &p.captives {
                bodies.push(civilian(format!("m05/{}", captive.id), captive.feet));
            }
        }
        if let Some(p) = &run.m08 {
            let presentation = self
                .map
                .presentation_ref()
                .expect("validated M08 presentation");
            let layout = crate::protocol::M08NeutralLayout::read(
                self.map.arena().half,
                &self.map.arena().solids,
                presentation,
            )
            .expect("validated M08 neutral layout");
            for (key, feet) in layout.people(p.index >= 2, p.custody_released) {
                bodies.push(civilian(key.into(), feet));
            }
        }
        if run.m06.is_some() || run.m07.is_some() {
            if let Some(presentation) = self.map.presentation_ref() {
                for (key, feet) in crate::protocol::moon_residents(
                    if run.m06.is_some() {
                        crate::protocol::MissionId::PortOfEntry
                    } else {
                        crate::protocol::MissionId::DeclaredGoods
                    },
                    self.map.arena().half,
                    &self.map.arena().solids,
                    presentation,
                )
                .expect("validated resident panel layout")
                {
                    bodies.push(civilian(key, feet));
                }
            }
        }
        if let Some(p) = &run.m09 {
            for crew in &p.crew {
                bodies.push(civilian(format!("m09/{}", crew.id), crew.feet));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::maps::AuthoredSource;
    use crate::protocol::{M05TramPhase, MissionId, MissionReady, Role};
    use crate::sim::PLAYER_FLOOR_Y;
    use uuid::Uuid;

    #[test]
    fn m08_neutral_contacts_follow_exact_visibility_release_and_lifecycle() {
        let map = AuthoredSource::Mission(MissionId::CustodianOfRecord)
            .load()
            .unwrap();
        let mut game = GameState::with_authored_map(map);
        let id = Uuid::from_u128(808);
        game.add_player(id, "archive visitor".into(), Role::Human);
        let mut bodies = Vec::new();
        game.append_civilian_contacts(&mut bodies);
        assert!(bodies.is_empty(), "briefing has no active neutral contacts");
        assert!(game.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::CustodianOfRecord,
                attempt: 1
            }
        ));
        game.tick(0.0);
        let layout = crate::protocol::M08NeutralLayout::read(
            game.map.arena().half,
            &game.map.arena().solids,
            game.map.presentation_ref().unwrap(),
        )
        .unwrap();
        for (index, released, count) in [
            (0, false, 4),
            (1, false, 4),
            (2, false, 5),
            (4, true, 5),
            (7, true, 5),
        ] {
            let p = game.mission.as_mut().unwrap().m08.as_mut().unwrap();
            p.index = index;
            p.custody_released = released;
            bodies.clear();
            game.append_civilian_contacts(&mut bodies);
            assert_eq!(bodies.len(), count);
            for (body, (key, feet)) in bodies.iter().zip(layout.people(index >= 2, released)) {
                assert_eq!(body.key, key);
                assert_eq!([body.from.x, body.from.y, body.from.z], feet);
                assert_eq!(body.from, body.proposed);
                assert_eq!(body.height, crate::movement::BODY_HEIGHT);
                assert_eq!(body.radius, crate::movement::RADIUS);
            }
            assert!(
                !bodies.iter().any(|b| b.key.contains("orrin")),
                "backup case is not a person body"
            );
        }
        game.mission.as_mut().unwrap().phase = MissionPhase::Departed;
        bodies.clear();
        game.append_civilian_contacts(&mut bodies);
        assert!(
            bodies.is_empty(),
            "departed mission freezes neutral contact participation"
        );
    }

    #[test]
    fn m08_neutral_registry_corner_retains_real_walking_clearance() {
        let map = AuthoredSource::Mission(MissionId::CustodianOfRecord)
            .load()
            .unwrap();
        let mut game = GameState::with_authored_map(map);
        let id = Uuid::from_u128(809);
        game.add_player(id, "registry walker".into(), Role::Human);
        assert!(game.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::CustodianOfRecord,
                attempt: 1
            }
        ));
        game.tick(0.0);
        game.mission.as_mut().unwrap().m08.as_mut().unwrap().index = 2;
        let walker = game.players.iter_mut().find(|p| p.id == id).unwrap();
        walker.x = -15.4;
        walker.y = 3.0 + PLAYER_FLOOR_Y;
        walker.z = -9.6;
        walker.vy = 0.0;
        game.set_action(
            id,
            crate::protocol::Action {
                forward: true,
                yaw: Some(0.0),
                ..Default::default()
            },
        );
        for _ in 0..20 {
            game.tick(0.05);
        }
        let walker = game.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            walker.x > -11.5,
            "ordinary contact integration walks past Renn beside the desk"
        );
        assert!(
            (walker.y - PLAYER_FLOOR_Y - 3.0).abs() < 0.001,
            "walker remains on actual gallery support"
        );
    }

    #[test]
    fn actor_contact_real_tram_refuses_rider_against_living_edge_body() {
        let map = AuthoredSource::Mission(MissionId::NoForwardingAddress)
            .load()
            .unwrap();
        let mut game = GameState::with_authored_map(map);
        let a = Uuid::from_u128(100);
        let b = Uuid::from_u128(200);
        for id in [a, b] {
            game.add_player(id, format!("visitor{id}"), Role::Human);
            assert!(game.acknowledge_mission(
                id,
                MissionReady {
                    id: MissionId::NoForwardingAddress,
                    attempt: 1
                }
            ));
        }
        let g = game.map.m05_geometry().unwrap().tram.clone();
        let solid = g.body(game.map.arena().solids[g.solid], g.start);
        for p in &mut game.players {
            p.clear_input();
            p.vy = 0.0;
            p.y = solid.top + PLAYER_FLOOR_Y;
        }
        let direction = (g.end[2] - g.start[2]).signum();
        let az = (solid.min_z + solid.max_z) * 0.5;
        let bx = solid.max_x + 0.1;
        let ax = solid.max_x - 0.1;
        let bz = az + direction * 1.0;
        for p in &mut game.players {
            if p.id == a {
                p.x = ax;
                p.z = az;
            } else if p.id == b {
                p.x = bx;
                p.z = bz;
            }
        }
        let progress = game.mission.as_mut().unwrap().m05.as_mut().unwrap();
        progress.group_released = true;
        progress.tram.phase = M05TramPhase::Moving;
        let before = progress.tram.feet;
        game.advance_m05_tram(0.05);
        assert_eq!(
            game.mission
                .as_ref()
                .unwrap()
                .m05
                .as_ref()
                .unwrap()
                .tram
                .feet,
            before
        );
        assert_eq!(
            game.mission
                .as_ref()
                .unwrap()
                .m05
                .as_ref()
                .unwrap()
                .tram
                .phase,
            M05TramPhase::Blocked
        );
        assert_eq!(game.players.iter().find(|p| p.id == a).unwrap().z, az);
        game.players
            .iter_mut()
            .find(|p| p.id == b)
            .unwrap()
            .detached = true;
        game.advance_m05_tram(0.05);
        assert_ne!(
            game.mission
                .as_ref()
                .unwrap()
                .m05
                .as_ref()
                .unwrap()
                .tram
                .feet,
            before
        );
    }
}
