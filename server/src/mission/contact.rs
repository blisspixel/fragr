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
