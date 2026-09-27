//! Authoritative flag transitions for a staged two-side league match.
use super::{GameState, RoundState, PLAYER_FLOOR_Y};
use crate::protocol::{
    FlagEventKind, FlagState, FlagStatus, GameEvent, GameMode, Team, TeamScores,
};
use uuid::Uuid;

const TOUCH_RADIUS_SQUARED: f32 = 2.5 * 2.5;
const RETURN_TICKS: u64 = 20 * 20;

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
            if flags[own].dropped_at.is_some() && touches(feet, flags[own].position) {
                flags[own].return_home();
                self.flag_event(FlagEventKind::Returned, side, Some(id));
            }
            if flags[enemy].carrier.is_none()
                && flags[enemy].dropped_at != Some(self.tick)
                && touches(feet, flags[enemy].position)
            {
                flags[enemy].carrier = Some(id);
                flags[enemy].dropped_at = None;
                flags[enemy].position = feet;
                self.flag_event(FlagEventKind::Taken, side.other(), Some(id));
            }
            if flags[enemy].carrier == Some(id)
                && flags[own].is_home()
                && touches(feet, flags[own].stand)
            {
                flags[enemy].return_home();
                self.capture_scores.add(side);
                self.flag_event(FlagEventKind::Captured, side.other(), Some(id));
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
