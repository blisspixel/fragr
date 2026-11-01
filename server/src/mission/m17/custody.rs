//! Level 17's custody beat: Voss stands beside her rostrum through the core
//! fight, alive and nobody's target. When the party secures her, two free
//! coalition people come in from beyond the chamber's east door, stand at her
//! side, and walk her out together to where they wait. Every position is the
//! server's, along walks authored on the concluded floor; the client gives
//! the beat its lines.
use super::*;
use crate::maps::{Custody, CUSTODY_IN_PACE, CUSTODY_OUT_PACE};
use crate::movement::RADIUS;
use crate::protocol::{EquipmentPolicy, FigureKind, Role, WeaponType, M17_CUSTODY_TAKEN_TICKS};
use crate::sim::Player;

/// Server yaw from `from` toward `to` (the convention `atan2(dz, dx)`).
fn facing(from: [f32; 3], to: [f32; 3]) -> f32 {
    (to[2] - from[2]).atan2(to[0] - from[0])
}

/// The clock at which the coalition walks Voss out: after the escort has
/// reached her side and not before her last word.
fn taken_at(custody: &Custody) -> u64 {
    Custody::duration(&custody.in_starts(), &custody.walk_in, CUSTODY_IN_PACE)
        .max(M17_CUSTODY_TAKEN_TICKS)
}

impl GameState {
    fn m17_custody(&self) -> Option<Custody> {
        self.map.m17_objectives().map(|p| p.custody.clone())
    }

    fn figure_ids(&self, kind: FigureKind) -> Vec<Uuid> {
        self.players
            .iter()
            .filter(|p| p.campaign == Some(CampaignActor::Figure { kind }))
            .map(|p| p.id)
            .collect()
    }

    fn spawn_figure(&mut self, kind: FigureKind, name: String, feet: [f32; 3], yaw: f32) {
        let id = self.new_entity_id();
        let [x, floor, z] = feet;
        let mut body = Player::at_spawn(
            id,
            name,
            Role::Agent,
            (x, z, yaw, floor),
            EquipmentPolicy::Discovery,
        );
        body.weapon = WeaponType::Fists;
        body.campaign = Some(CampaignActor::Figure { kind });
        self.players.push(body);
    }

    /// Voss is in the Office for the whole attempt, beside her rostrum and
    /// facing the core seal she is waiting behind.
    pub(crate) fn ensure_m17_figures(&mut self) {
        if !self
            .mission
            .as_ref()
            .is_some_and(|r| r.m17.is_some() && r.phase == MissionPhase::InProgress)
            || !self.figure_ids(FigureKind::Voss).is_empty()
        {
            return;
        }
        let Some(custody) = self.m17_custody() else {
            return;
        };
        let yaw = facing(custody.voss, [0.0, 0.0, 19.0]);
        self.spawn_figure(FigureKind::Voss, "Voss".into(), custody.voss, yaw);
    }

    /// The two coalition people appear beyond the east door when the party
    /// secures her.
    pub(super) fn spawn_m17_escort(&mut self) {
        if !self.figure_ids(FigureKind::Coalition).is_empty() {
            return;
        }
        let Some(custody) = self.m17_custody() else {
            return;
        };
        for (index, (start, route)) in custody.escort.iter().zip(&custody.walk_in).enumerate() {
            let yaw = facing(*start, route[0]);
            self.spawn_figure(
                FigureKind::Coalition,
                format!("Coalition {}", index + 1),
                *start,
                yaw,
            );
        }
    }

    /// One tick of the custody walk. Returns true on the tick the coalition
    /// starts to walk Voss out, which is when she is in their custody.
    pub(super) fn advance_m17_custody(&mut self) -> bool {
        let Some((started, clock, captured)) = self
            .mission
            .as_ref()
            .and_then(|r| r.m17.as_ref())
            .map(|p| (p.custody_started, p.custody_clock, p.voss_captured))
        else {
            return false;
        };
        // The walk starts on the tick after the party secured her.
        let (Some(started), Some(custody)) = (started, self.m17_custody()) else {
            return false;
        };
        if started >= self.tick {
            return false;
        }
        let voss = self.figure_ids(FigureKind::Voss);
        let escort = self.figure_ids(FigureKind::Coalition);
        if voss.len() != 1 || escort.len() != 2 {
            return false;
        }
        let taken = taken_at(&custody);
        let in_starts = custody.in_starts();
        let out_starts = custody.out_starts();
        let out_length = Custody::duration(&out_starts, &custody.walk_out, CUSTODY_OUT_PACE);
        let place = |clock: u64| -> Vec<[f32; 3]> {
            if clock < taken {
                let mut at = vec![custody.voss];
                at.extend(Custody::along(
                    &in_starts,
                    &custody.walk_in,
                    CUSTODY_IN_PACE,
                    clock,
                ));
                at
            } else {
                Custody::along(
                    &out_starts,
                    &custody.walk_out,
                    CUSTODY_OUT_PACE,
                    clock - taken,
                )
            }
        };
        let ids = [voss[0], escort[0], escort[1]];
        let now = place(clock);
        let next = place(clock + 1);
        // Nobody walks through a person: the whole walk waits for anyone
        // standing where a moving body is about to step.
        let blocked = now.iter().zip(&next).any(|(from, to)| {
            from != to
                && self.players.iter().any(|p| {
                    !p.campaign.is_some_and(CampaignActor::is_figure)
                        && p.hp > 0
                        && p.respawn_timer.is_none()
                        && (p.x - to[0]).hypot(p.z - to[2]) < 2.0 * RADIUS
                        && (p.y - PLAYER_FLOOR_Y - to[1]).abs() < 1.5
                })
        });
        let clock = if blocked || clock > taken + out_length {
            clock
        } else {
            clock + 1
        };
        if let Some(p) = self.mission.as_mut().and_then(|r| r.m17.as_mut()) {
            p.custody_clock = clock;
        }
        let at = place(clock);
        let ahead = place(clock + 1);
        // Before she is taken Voss faces whoever secured her.
        let party = self
            .players
            .iter()
            .filter(|p| p.is_participant() && p.hp > 0)
            .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
            .min_by(|a, b| {
                (a[0] - custody.voss[0])
                    .hypot(a[2] - custody.voss[2])
                    .total_cmp(&(b[0] - custody.voss[0]).hypot(b[2] - custody.voss[2]))
            });
        for (i, id) in ids.iter().enumerate() {
            let walking = at[i] != ahead[i];
            let yaw = if walking {
                Some(facing(at[i], ahead[i]))
            } else if i == 0 && clock < taken {
                party.map(|feet| facing(at[0], feet))
            } else if i > 0 {
                Some(facing(at[i], at[0]))
            } else {
                None
            };
            if let Some(body) = self.players.iter_mut().find(|p| p.id == *id) {
                body.x = at[i][0];
                body.y = at[i][1] + PLAYER_FLOOR_Y;
                body.z = at[i][2];
                body.vx = 0.0;
                body.vy = 0.0;
                body.vz = 0.0;
                if let Some(yaw) = yaw {
                    body.yaw = yaw;
                }
            }
        }
        !captured && clock >= taken
    }
}
