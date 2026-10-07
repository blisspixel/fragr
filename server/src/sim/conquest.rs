//! Capture, contest and ticket arithmetic on the ordinary simulation tick.
use super::{BotController, BotIntent, GameState, Player, RoundState, Standing, PLAYER_FLOOR_Y};
use crate::protocol::{CapturePoint, ConquestState, GameMode, Team, TeamScores};

pub(crate) const CAPTURE_TICKS: u16 = 160;
const START_TICKETS: u32 = 200;
pub(crate) const POINTS: [(&str, [f32; 3]); 5] = [
    ("harbour", [-105.0, 3.0, 65.0]),
    ("village", [-100.0, 3.0, -35.0]),
    ("airfield", [0.0, 3.0, -70.0]),
    ("server_halls", [100.0, 3.0, -35.0]),
    ("lighthouse", [105.0, 3.0, 65.0]),
];

pub(super) fn initial() -> ConquestState {
    ConquestState {
        tickets: TeamScores {
            union: START_TICKETS,
            coalition: START_TICKETS,
        },
        initial_tickets: START_TICKETS,
        capture_ticks: CAPTURE_TICKS,
        points: POINTS
            .iter()
            .map(|(id, position)| CapturePoint {
                id: (*id).into(),
                position: *position,
                radius: 8.0,
                owner: None,
                capturing: None,
                progress: 0,
                contested: false,
            })
            .collect(),
    }
}

fn debit(tickets: &mut TeamScores, team: Team, count: u32) {
    let value = match team {
        Team::Union => &mut tickets.union,
        Team::Coalition => &mut tickets.coalition,
    };
    *value = value.saturating_sub(count);
}

fn advance(point: &mut CapturePoint, presence: [bool; 2]) {
    point.contested = presence == [true, true];
    if point.contested {
        return;
    }
    let side = match presence {
        [true, false] => Some(Team::Union),
        [false, true] => Some(Team::Coalition),
        _ => None,
    };
    if side.is_none() || side == point.owner {
        point.progress = point.progress.saturating_sub(1);
        if point.progress == 0 {
            point.capturing = None;
        }
        return;
    }
    if point.capturing != side {
        if point.progress > 0 {
            point.progress -= 1;
            if point.progress == 0 {
                point.capturing = None;
            }
            return;
        }
        point.capturing = side;
    }
    point.progress += 1;
    if point.progress == CAPTURE_TICKS {
        point.owner = if point.owner.is_some() { None } else { side };
        point.progress = 0;
        point.capturing = None;
    }
}

impl GameState {
    pub(super) fn reset_conquest(&mut self) {
        self.conquest =
            (self.config.rules.mode() == GameMode::Conquest && self.map.id() == 7).then(initial);
    }

    pub(super) fn conquest_death(&mut self, team: Option<Team>) {
        if self.round_state != RoundState::Active {
            return;
        }
        if let (Some(state), Some(team)) = (&mut self.conquest, team) {
            debit(&mut state.tickets, team, 1);
        }
    }

    pub(super) fn tick_conquest(&mut self) {
        if self.round_state != RoundState::Active {
            return;
        }
        let presence: Vec<[bool; 2]> = self
            .conquest
            .as_ref()
            .map(|state| {
                state
                    .points
                    .iter()
                    .map(|point| {
                        let mut sides = [false; 2];
                        for player in &self.players {
                            if !self.contact_eligible(player)
                                || !player.contestant()
                                || player.role == crate::protocol::Role::Spectator
                            {
                                continue;
                            }
                            if let Some(team) = player.team {
                                if (player.y - PLAYER_FLOOR_Y - point.position[1]).abs() <= 3.0
                                    && (player.x - point.position[0])
                                        .hypot(player.z - point.position[2])
                                        <= point.radius
                                {
                                    sides[team.index()] = true;
                                }
                            }
                        }
                        sides
                    })
                    .collect()
            })
            .unwrap_or_default();
        let Some(state) = &mut self.conquest else {
            return;
        };
        for (point, presence) in state.points.iter_mut().zip(presence) {
            advance(point, presence);
        }
        if self.round_ticks.is_multiple_of(20) {
            for team in Team::ALL {
                let held = state
                    .points
                    .iter()
                    .filter(|point| point.owner == Some(team))
                    .count() as u32;
                debit(&mut state.tickets, team.other(), held.saturating_sub(2));
            }
        }
        if state.tickets.union == 0 || state.tickets.coalition == 0 {
            let winner = state.tickets.leader();
            self.finish_round("Tickets exhausted".into(), Some(Standing::Side(winner)));
        }
    }
}

impl BotController {
    pub(super) fn conquest_intent(&self, state: &GameState, bot: &Player) -> BotIntent {
        let (Some(team), Some(conquest)) = (bot.team, &state.conquest) else {
            return BotIntent::default();
        };
        let ordinal = state
            .bots
            .iter()
            .filter(|b| {
                state
                    .players
                    .iter()
                    .any(|p| p.id == b.player_id && p.team == Some(team))
            })
            .position(|b| b.player_id == self.player_id)
            .unwrap_or(0);
        let mut candidates: Vec<(usize, &CapturePoint)> = conquest
            .points
            .iter()
            .enumerate()
            .filter(|(_, point)| {
                point.owner != Some(team) || point.contested || point.capturing.is_some()
            })
            .collect();
        candidates.sort_by(|(a, left), (b, right)| {
            let distance = |p: &CapturePoint| (bot.x - p.position[0]).hypot(bot.z - p.position[2]);
            distance(left).total_cmp(&distance(right)).then(a.cmp(b))
        });
        let point = if candidates.is_empty() {
            &conquest.points[ordinal % conquest.points.len()]
        } else {
            candidates[ordinal % candidates.len().min(3)].1
        };
        let feet = point.position;
        let near = (bot.x - feet[0]).hypot(bot.z - feet[2]) < point.radius * 0.6;
        let mut action = super::face_flag_goal(bot, feet);
        action.forward = !near;
        if let Some(combat) = self.sensed_objective_aim(state, bot) {
            action.yaw = combat.yaw;
            action.pitch = combat.pitch;
            action.weapon_swap = combat.weapon_swap;
            action.turn_left = false;
            action.turn_right = false;
            action.fire = combat.fire;
        }
        BotIntent {
            action,
            goal: (!near).then_some(crate::navigation::NavigationGoal {
                feet,
                combat: false,
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capture_contest_neutralize_and_decay() {
        let mut point = initial().points.remove(0);
        for _ in 0..80 {
            advance(&mut point, [true, false]);
        }
        advance(&mut point, [true, true]);
        assert_eq!(point.progress, 80);
        assert!(point.contested);
        for _ in 0..80 {
            advance(&mut point, [true, false]);
        }
        assert_eq!(point.owner, Some(Team::Union));
        for _ in 0..160 {
            advance(&mut point, [false, true]);
        }
        assert_eq!(point.owner, None);
        for _ in 0..159 {
            advance(&mut point, [false, true]);
        }
        assert_eq!(point.owner, None);
        advance(&mut point, [false, false]);
        assert_eq!(point.progress, 158);
        advance(&mut point, [true, false]);
        assert_eq!(point.progress, 157, "switching side unwinds existing work");
        for _ in 0..157 {
            advance(&mut point, [false, false]);
        }
        assert_eq!(point.capturing, None);
    }

    #[test]
    fn ticket_debits_saturate() {
        let mut tickets = TeamScores {
            union: 1,
            coalition: 0,
        };
        debit(&mut tickets, Team::Union, 3);
        debit(&mut tickets, Team::Coalition, 1);
        assert_eq!(tickets, TeamScores::default());
    }

    fn game() -> GameState {
        let mut state = GameState::new();
        state.map = crate::maps::RuntimeMap::BuiltIn(super::super::MapKind::HoldfastAtoll);
        state.apply_config(super::super::MatchConfig {
            rules: crate::rules::RuleSet::new(GameMode::Conquest, &[], false).unwrap(),
            frag_limit: None,
            time_limit_ticks: None,
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            ..Default::default()
        });
        state.round_state = RoundState::Active;
        state.round_ticks = 1;
        state
    }

    #[test]
    fn live_presence_excludes_dead_parked_and_spectators() {
        let mut state = game();
        let id = uuid::Uuid::from_u128(1);
        state.add_player(id, "capturer".into(), crate::protocol::Role::Human);
        let player = &mut state.players[0];
        player.team = Some(Team::Union);
        player.x = POINTS[0].1[0];
        player.z = POINTS[0].1[2];
        player.y = PLAYER_FLOOR_Y + POINTS[0].1[1];
        state.tick_conquest();
        assert_eq!(state.conquest.as_ref().unwrap().points[0].progress, 1);
        state.players[0].detached = true;
        state.tick_conquest();
        assert_eq!(state.conquest.as_ref().unwrap().points[0].progress, 0);
        state.players[0].detached = false;
        state.players[0].hp = 0;
        state.tick_conquest();
        assert_eq!(state.conquest.as_ref().unwrap().points[0].progress, 0);
        state.players[0].hp = 100;
        state.players[0].role = crate::protocol::Role::Spectator;
        state.tick_conquest();
        assert_eq!(state.conquest.as_ref().unwrap().points[0].progress, 0);
    }

    #[test]
    fn majority_bleeds_once_per_second_and_reset_clears_facts() {
        let mut state = game();
        for point in state.conquest.as_mut().unwrap().points.iter_mut().take(4) {
            point.owner = Some(Team::Coalition);
        }
        state.round_ticks = 19;
        state.tick_conquest();
        assert_eq!(state.conquest.as_ref().unwrap().tickets.union, 200);
        state.round_ticks = 20;
        state.tick_conquest();
        assert_eq!(state.conquest.as_ref().unwrap().tickets.union, 198);
        state.conquest_death(Some(Team::Coalition));
        assert_eq!(state.conquest.as_ref().unwrap().tickets.coalition, 199);
        state.reset_conquest();
        assert_eq!(state.conquest.as_ref().unwrap(), &initial());
        state.config.rules = crate::rules::RuleSet::default();
        state.reset_conquest();
        assert!(state.conquest.is_none());
    }

    #[test]
    fn ticket_exhaustion_and_simultaneous_zero_have_exact_results() {
        for (union, coalition, expected) in [
            (0, 1, Some(Team::Coalition)),
            (1, 0, Some(Team::Union)),
            (0, 0, None),
        ] {
            let mut state = game();
            state.conquest.as_mut().unwrap().tickets = TeamScores { union, coalition };
            state.tick_conquest();
            assert_eq!(state.round_state, RoundState::Ended);
            assert!(state.events.iter().any(|event| matches!(event, crate::protocol::GameEvent::RoundEnd { winning_team, .. } if *winning_team == expected)));
            let retained = state.snapshot().conquest.unwrap();
            assert_eq!(retained.tickets, TeamScores { union, coalition });
        }
    }

    #[test]
    fn holdfast_sites_spawns_and_jeeps_have_connected_ground() {
        let map = super::super::MapKind::HoldfastAtoll;
        assert!(
            crate::maps::validate(map).is_empty(),
            "{:?}",
            crate::maps::validate(map)
        );
        let arena = crate::maps::arena(map);
        let navigation = crate::navigation::Navigation::shared(arena.clone()).unwrap();
        for (_, feet) in POINTS {
            assert!(!arena.blocked_at(feet[0], feet[2], feet[1] + crate::movement::STEP_UP));
            assert_eq!(
                arena.support_height(feet[0], feet[2], feet[1] + crate::movement::STEP_UP),
                feet[1]
            );
            // Actual route queries are bounded by the shared controller.
            assert_eq!(
                navigation
                    .route([0.0, 3.0, 0.0], feet, crate::navigation::SEARCH_LIMIT)
                    .status,
                crate::navigation::RouteStatus::Complete
            );
        }
    }
}
