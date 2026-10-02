use super::{GameState, Player, PLAYER_FLOOR_Y};
use crate::movement::{
    contact::{resolve, ContactBody},
    Arena, MoveState, BODY_HEIGHT, RADIUS,
};

fn state(p: &Player) -> MoveState {
    MoveState {
        x: p.x,
        y: p.y - PLAYER_FLOOR_Y,
        z: p.z,
        vx: 0.0,
        vz: 0.0,
        vy: p.vy,
        yaw: p.yaw,
    }
}

impl GameState {
    pub(crate) fn contact_eligible(&self, p: &Player) -> bool {
        p.hp > 0
            && p.respawn_timer.is_none()
            && !p.eliminated
            && !p.detached
            && crate::mission::actor_active(self.mission.as_ref(), p.id, p.campaign)
    }

    pub(crate) fn contact_bodies(&self) -> Vec<ContactBody> {
        let mut bodies: Vec<_> = self
            .players
            .iter()
            .filter(|p| self.contact_eligible(p))
            .map(|p| {
                let from = state(p);
                ContactBody {
                    key: p.id.to_string(),
                    from,
                    proposed: from,
                    height: crate::combat::target_height(p.campaign),
                    radius: RADIUS,
                    jump: false,
                }
            })
            .collect();
        self.append_civilian_contacts(&mut bodies);
        bodies
    }

    pub(super) fn resolve_player_contacts(
        &mut self,
        mut bodies: Vec<ContactBody>,
        dt: f32,
        arena: &Arena,
    ) {
        for body in &mut bodies {
            let Ok(id) = uuid::Uuid::parse_str(&body.key) else {
                continue;
            };
            if let Some(p) = self.players.iter().find(|p| p.id == id) {
                body.proposed = state(p);
                body.jump = p.last_movement_tick == Some(self.tick) && p.last_jump_input;
                // Facing belongs to the current input, not the previous snapshot.
                body.from.yaw = p.yaw;
            }
        }
        let accepted = resolve(&bodies, dt, arena);
        for (body, moved) in bodies.iter().zip(accepted) {
            let Ok(id) = uuid::Uuid::parse_str(&body.key) else {
                continue;
            };
            if let Some(p) = self.players.iter_mut().find(|p| p.id == id) {
                p.x = moved.x;
                p.z = moved.z;
                p.y = moved.y + PLAYER_FLOOR_Y;
                p.vy = moved.vy;
                if p.last_movement_tick == Some(self.tick)
                    && dt > 0.0
                    && dt.is_finite()
                    && (moved.x != body.proposed.x || moved.z != body.proposed.z)
                {
                    p.last_move_vx = (p.x - body.from.x) / dt;
                    p.last_move_vz = (p.z - body.from.z) / dt;
                }
            }
        }
    }
}

pub(crate) fn civilian(key: String, feet: [f32; 3]) -> ContactBody {
    let from = MoveState {
        x: feet[0],
        y: feet[1],
        z: feet[2],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    ContactBody {
        key,
        from,
        proposed: from,
        height: BODY_HEIGHT,
        radius: RADIUS,
        jump: false,
    }
}

// This is one actor's map-integrated motion plus the immutable contact scene;
// keeping those inputs explicit prevents losing original support on a clip.
#[allow(clippy::too_many_arguments)]
pub(crate) fn move_body(
    key: &str,
    from: MoveState,
    proposed: MoveState,
    height: f32,
    dt: f32,
    arena: &Arena,
    blockers: &[ContactBody],
) -> MoveState {
    let mut bodies: Vec<_> = blockers
        .iter()
        .filter(|b| {
            b.key != key
                && b.from.x + RADIUS + b.radius >= from.x.min(proposed.x)
                && b.from.x - RADIUS - b.radius <= from.x.max(proposed.x)
                && b.from.z + RADIUS + b.radius >= from.z.min(proposed.z)
                && b.from.z - RADIUS - b.radius <= from.z.max(proposed.z)
        })
        .cloned()
        .collect();
    bodies.push(ContactBody {
        key: key.to_owned(),
        from,
        proposed,
        height,
        radius: RADIUS,
        jump: false,
    });
    resolve(&bodies, dt, arena).pop().unwrap_or(from)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{Action, Role};
    use uuid::Uuid;

    #[test]
    fn actor_contact_actual_tick_and_additive_wire_eligibility() {
        let mut game = GameState::new();
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        game.add_player(a, "walker".into(), Role::Human);
        game.add_player(b, "blocker".into(), Role::Agent);
        game.players[0].x = -1.2;
        game.players[0].z = 0.0;
        game.players[0].y = PLAYER_FLOOR_Y;
        game.players[1].x = 0.0;
        game.players[1].z = 0.0;
        game.players[1].y = PLAYER_FLOOR_Y;
        game.set_action(
            a,
            Action {
                forward: true,
                yaw: Some(0.0),
                ..Action::default()
            },
        );
        let world = Arena {
            half: 40.0,
            solids: vec![],
        };
        for tick in 1..=8 {
            game.tick = tick;
            game.tick_active(0.05, &world);
        }
        assert!(game.players[0].x <= -0.9999);
        assert_eq!(game.players[1].x, 0.0);
        assert!(game.players[0].last_move_vx.abs() < 0.001);
        assert!(game.snapshot().players.iter().all(|p| p.collidable));
        game.players[1].detached = true;
        assert!(
            !game
                .snapshot()
                .players
                .iter()
                .find(|p| p.id == b)
                .unwrap()
                .collidable
        );
        for tick in 9..=18 {
            game.tick = tick;
            game.tick_active(0.05, &world);
        }
        assert!(
            game.players[0].x > 0.0,
            "detached pawn must not trap walking"
        );
        game.players[1].detached = false;
        game.players[1].hp = -20;
        assert!(!game.contact_eligible(&game.players[1]));
        game.players[1].hp = 100;
        game.players[1].eliminated = true;
        assert!(!game.contact_eligible(&game.players[1]));
        game.players[1].eliminated = false;
        game.players[1].respawn_timer = Some(3);
        assert!(!game.contact_eligible(&game.players[1]));
        let mut value = serde_json::to_value(&game.snapshot().players[0]).unwrap();
        value.as_object_mut().unwrap().remove("collidable");
        assert!(
            serde_json::from_value::<crate::protocol::PlayerState>(value.clone())
                .unwrap()
                .collidable
        );
        value["collidable"] = serde_json::json!("false");
        assert!(serde_json::from_value::<crate::protocol::PlayerState>(value).is_err());
    }
}
