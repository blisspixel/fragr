//! One bounded infantry assignment pass, without navigation or outcome authority.
use super::{BotController, CapturePoint, ConquestState, GameState, Player, Team, PLAYER_FLOOR_Y};
use std::collections::{HashMap, HashSet};
use uuid::Uuid;

const SITES: usize = super::POINTS.len();

#[derive(Default)]
pub(in crate::sim) struct Orders {
    goals: HashMap<Uuid, usize>,
    #[cfg(test)]
    pub(super) evaluations: usize,
}

impl Orders {
    pub(super) fn point<'a>(&self, id: Uuid, state: &'a ConquestState) -> Option<&'a CapturePoint> {
        state.points.get(*self.goals.get(&id)?)
    }

    fn examine(&mut self) {
        #[cfg(test)]
        {
            self.evaluations += 1;
        }
    }
}

fn inside(player: &Player, point: &CapturePoint) -> bool {
    (player.y - PLAYER_FLOOR_Y - point.position[1]).abs() <= 3.0
        && (player.x - point.position[0]).hypot(player.z - point.position[2]) <= point.radius
}

struct Site {
    priority: u8,
    need: usize,
    present: usize,
    incoming: usize,
}

impl GameState {
    pub(crate) fn plan_conquest_orders(&mut self, controllers: &[BotController]) {
        let previous = std::mem::take(&mut self.conquest_orders);
        self.conquest_orders = plan(self, controllers, &previous);
    }
}

fn plan(state: &GameState, controllers: &[BotController], previous: &Orders) -> Orders {
    let mut orders = Orders::default();
    let Some(conquest) = &state.conquest else {
        return orders;
    };
    // Conquest's registered world has exactly five sites. Refuse malformed
    // internal input rather than expanding the per-tick planning budget.
    if conquest.points.len() != SITES {
        return orders;
    }
    let mut presence = [[0usize; 2]; SITES];
    let players: HashMap<_, _> = state
        .players
        .iter()
        .filter(|p| {
            state.contact_eligible(p)
                && p.contestant()
                && p.role != crate::protocol::Role::Spectator
                && p.team.is_some()
        })
        .map(|p| {
            for (i, point) in conquest.points.iter().enumerate() {
                orders.examine();
                if inside(p, point) {
                    presence[i][p.team.unwrap().index()] += 1;
                }
            }
            (p.id, p)
        })
        .collect();
    let mut seen = HashSet::new();
    let bots: Vec<_> = controllers
        .iter()
        .filter_map(|controller| players.get(&controller.player_id).copied())
        .filter(|p| seen.insert(p.id) && state.vehicle_seat(p.id).is_none())
        .collect();

    for team in Team::ALL {
        let mut sites: [Site; SITES] = std::array::from_fn(|i| {
            let point = &conquest.points[i];
            let present = presence[i][team.index()];
            let enemies = presence[i][team.other().index()];
            let threatened =
                point.owner == Some(team) && (enemies > 0 || point.capturing == Some(team.other()));
            let priority = if threatened {
                4
            } else if point.owner != Some(team) && present > 0 {
                3
            } else if point.owner != Some(team) {
                2
            } else {
                1
            };
            Site {
                priority,
                need: (enemies + 1).saturating_sub(present),
                present,
                incoming: 0,
            }
        });
        // A body already capturing or defending is useful regardless of roster
        // changes. Quiet guards can be reassigned when another site needs help.
        for bot in bots.iter().copied().filter(|p| p.team == Some(team)) {
            for (i, point) in conquest.points.iter().enumerate() {
                orders.examine();
                if sites[i].priority > 1 && inside(bot, point) {
                    orders.goals.insert(bot.id, i);
                    break;
                }
            }
        }
        for priority in (1..=4).rev() {
            // Existing incoming objectives keep their slot before a newly
            // spawned teammate chooses among equally important sites.
            for bot in bots.iter().copied().filter(|p| p.team == Some(team)) {
                if orders.goals.contains_key(&bot.id) {
                    continue;
                }
                if let Some(&i) = previous.goals.get(&bot.id) {
                    orders.examine();
                    if let Some(site) = sites.get_mut(i) {
                        if site.priority == priority && site.incoming < site.need {
                            orders.goals.insert(bot.id, i);
                            site.incoming += 1;
                        }
                    }
                }
            }
            for bot in bots.iter().copied().filter(|p| p.team == Some(team)) {
                if orders.goals.contains_key(&bot.id) {
                    continue;
                }
                let best = (0..SITES)
                    .filter(|&i| {
                        orders.examine();
                        sites[i].priority == priority && sites[i].incoming < sites[i].need
                    })
                    .min_by(|&a, &b| {
                        distance(bot, &conquest.points[a])
                            .total_cmp(&distance(bot, &conquest.points[b]))
                            .then(a.cmp(&b))
                    });
                if let Some(i) = best {
                    orders.goals.insert(bot.id, i);
                    sites[i].incoming += 1;
                }
            }
        }
        // Every minimum is covered. Keep spare reinforcements stable, then
        // distribute new spares by coverage and distance among useful sites.
        for bot in bots.iter().copied().filter(|p| p.team == Some(team)) {
            if orders.goals.contains_key(&bot.id) {
                continue;
            }
            let retained = previous.goals.get(&bot.id).copied().filter(|&i| i < SITES);
            let i = retained.unwrap_or_else(|| {
                (0..SITES)
                    .min_by(|&a, &b| {
                        orders.examine();
                        sites[b]
                            .priority
                            .cmp(&sites[a].priority)
                            .then(
                                (sites[a].present + sites[a].incoming)
                                    .cmp(&(sites[b].present + sites[b].incoming)),
                            )
                            .then_with(|| {
                                distance(bot, &conquest.points[a])
                                    .total_cmp(&distance(bot, &conquest.points[b]))
                            })
                            .then(a.cmp(&b))
                    })
                    .unwrap()
            });
            orders.goals.insert(bot.id, i);
            if !inside(bot, &conquest.points[i]) {
                sites[i].incoming += 1;
            }
        }
    }
    orders
}

fn distance(bot: &Player, point: &CapturePoint) -> f32 {
    (bot.x - point.position[0]).hypot(bot.z - point.position[2])
}
