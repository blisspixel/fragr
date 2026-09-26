//! Rule-set behaviour on top of the arena sim: sides, lives, the golden
//! Railgun and the Host's reactions. `crate::rules` decides what the rules
//! are; this is where the sim follows them.
use super::{GameState, Standing, PICKUP_CLAIM_HEIGHT, PICKUP_CLAIM_RADIUS, PLAYER_FLOOR_Y};
use crate::protocol::{GameEvent, HostReactionKind, Team, WeaponType, HOST_REACTION_VARIANTS};
use uuid::Uuid;

impl GameState {
    /// Fighters on each side, bosses and campaign combatants excluded.
    pub(crate) fn team_counts(&self) -> [usize; 2] {
        let mut counts = [0; 2];
        for player in self.players.iter().filter(|p| p.contestant()) {
            if let Some(team) = player.team {
                counts[team.index()] += 1;
            }
        }
        counts
    }

    /// Whether a hit from `shooter` damages `victim`: campaign allegiance
    /// first, then sides, where friendly fire decides.
    pub(super) fn damage_lands(&self, shooter: usize, victim: usize) -> bool {
        let (a, b) = (&self.players[shooter], &self.players[victim]);
        crate::protocol::hostile(a.campaign, b.campaign)
            && (a.team.is_none() || a.team != b.team || self.config.rules.friendly_fire())
    }

    /// At a round start: give any sideless contestant a side, then move
    /// fighters until the sides are within one. Rule bots move first, then
    /// the most recent joiners; a moved fighter respawns in its new half.
    pub(super) fn balance_teams(&mut self) {
        let unassigned: Vec<usize> = (0..self.players.len())
            .filter(|&i| self.players[i].contestant() && self.players[i].team.is_none())
            .collect();
        for index in unassigned {
            let team = crate::rules::choose_team(self.team_counts(), self.team_scores);
            self.players[index].team = Some(team);
        }
        loop {
            let [union, coalition] = self.team_counts();
            let (big, small) = if union >= coalition + 2 {
                (Team::Union, Team::Coalition)
            } else if coalition >= union + 2 {
                (Team::Coalition, Team::Union)
            } else {
                break;
            };
            let bots: Vec<Uuid> = self.bots.iter().map(|b| b.player_id).collect();
            let on_big = |p: &super::Player| p.contestant() && p.team == Some(big);
            let Some(index) = self
                .players
                .iter()
                .rposition(|p| on_big(p) && bots.contains(&p.id))
                .or_else(|| self.players.iter().rposition(on_big))
            else {
                break;
            };
            let player = &mut self.players[index];
            player.team = Some(small);
            let (id, name, placed) = (
                player.id,
                player.name.clone(),
                player.respawn_timer.is_none() && !player.eliminated,
            );
            tracing::info!("TEAM BALANCE: {} moves to {}", name, small.id());
            if placed {
                self.do_respawn(id);
            }
        }
    }

    /// Call a Host beat. The client owns the words; the server sends the
    /// kind, a rotating variant and the names.
    pub(super) fn react(
        &mut self,
        kind: HostReactionKind,
        player: Option<String>,
        other: Option<String>,
        team: Option<Team>,
    ) -> bool {
        if !kind.always() {
            if let Some(last) = self.reactions.last_tick {
                if self.tick < last + crate::rules::REACTION_GAP_TICKS {
                    return false;
                }
            }
            self.reactions.last_tick = Some(self.tick);
        }
        let slot = HostReactionKind::ALL
            .iter()
            .position(|k| *k == kind)
            .expect("every reaction kind is listed");
        let count = self.reaction_counts[slot];
        self.reaction_counts[slot] = count.wrapping_add(1);
        let variant = (count % u32::from(HOST_REACTION_VARIANTS)) as u8;
        tracing::info!(
            "HOST REACTION: {:?} {:?} {:?} {:?}",
            kind,
            player,
            other,
            team
        );
        self.events.push(GameEvent::HostReaction {
            kind,
            variant,
            player,
            other,
            team,
        });
        true
    }

    /// Count a side frag, remember the worst deficit each side has faced, and
    /// call a comeback when the side that was far behind draws level.
    pub(super) fn note_team_frag(&mut self, side: Team) {
        self.team_scores.add(side);
        for team in Team::ALL {
            let own = self.team_scores.get(team);
            let other = self.team_scores.get(team.other());
            let deficit = &mut self.reactions.deficit[team.index()];
            *deficit = (*deficit).max(other.saturating_sub(own));
        }
        if self.team_scores.leader().is_none()
            && self.reactions.deficit[side.index()] >= crate::rules::COMEBACK_DEFICIT
        {
            self.reactions.deficit[side.index()] = 0;
            self.react(HostReactionKind::Comeback, None, None, Some(side));
        }
    }

    /// Lives-limited team rounds: one fighter left on a side against two or more.
    pub(super) fn react_to_last_standing(&mut self) {
        if !self.config.rules.teams() || self.config.rules.lives().is_none() {
            return;
        }
        for team in Team::ALL {
            if self.reactions.last_standing[team.index()] {
                continue;
            }
            let side = |t: Team| {
                self.players
                    .iter()
                    .filter(move |p| p.contestant() && p.team == Some(t))
            };
            let members = side(team).count();
            let standing: Vec<String> = side(team)
                .filter(|p| !p.eliminated)
                .map(|p| p.name.clone())
                .collect();
            let against = side(team.other()).filter(|p| !p.eliminated).count();
            if members >= 2 && standing.len() == 1 && against >= 2 {
                self.reactions.last_standing[team.index()] = true;
                let name = standing.into_iter().next();
                self.react(HostReactionKind::LastStanding, name, None, Some(team));
            }
        }
    }

    /// A lives-limited round ends when one fighter (or one side) is left
    /// with a life, provided two were in it.
    pub(super) fn elimination(&self) -> Option<Standing> {
        self.config.rules.lives()?;
        let contestants: Vec<&super::Player> =
            self.players.iter().filter(|p| p.contestant()).collect();
        if self.config.rules.teams() {
            let present = |t: Team| contestants.iter().any(|p| p.team == Some(t));
            if !Team::ALL.into_iter().all(present) {
                return None;
            }
            let alive: Vec<Team> = Team::ALL
                .into_iter()
                .filter(|t| {
                    contestants
                        .iter()
                        .any(|p| p.team == Some(*t) && !p.eliminated)
                })
                .collect();
            (alive.len() <= 1).then(|| Standing::Side(alive.first().copied()))
        } else {
            if contestants.len() < 2 {
                return None;
            }
            let alive: Vec<&&super::Player> =
                contestants.iter().filter(|p| !p.eliminated).collect();
            (alive.len() <= 1).then(|| Standing::Fighter(alive.first().map(|p| p.name.clone())))
        }
    }

    /// The golden Railgun goes back to its pad when its holder dies or leaves.
    pub(super) fn return_golden_rail_from(&mut self, id: Uuid) {
        if let Some(gold) = self.golden_rail.as_mut() {
            if gold.holder == Some(id) {
                gold.holder = None;
                tracing::info!("Golden Railgun returned to its pad");
            }
        }
        if let Some(player) = self.players.iter_mut().find(|p| p.id == id) {
            player.golden = false;
        }
    }

    /// First living contestant on the golden pad takes it.
    pub(super) fn claim_golden_rail(&mut self) {
        let Some(gold) = self.golden_rail.clone() else {
            return;
        };
        if gold.holder.is_some() {
            return;
        }
        let taker = self.players.iter().position(|p| {
            p.contestant()
                && p.respawn_timer.is_none()
                && p.hp > 0
                && p.inventory.owns(WeaponType::Rail)
                && (p.y - PLAYER_FLOOR_Y - gold.floor).abs() <= PICKUP_CLAIM_HEIGHT
                && (p.x - gold.x).hypot(p.z - gold.z) <= PICKUP_CLAIM_RADIUS
        });
        let Some(index) = taker else {
            return;
        };
        let player = &mut self.players[index];
        player.golden = true;
        player.inventory.release_trigger();
        player.weapon = WeaponType::Rail;
        let (id, name, team) = (player.id, player.name.clone(), player.team);
        if let Some(gold) = self.golden_rail.as_mut() {
            gold.holder = Some(id);
        }
        self.events.push(GameEvent::Pickup {
            player: name.clone(),
            player_id: id,
            kind: super::GOLDEN_RAIL_PICKUP_ID.to_string(),
            weapon: WeaponType::Rail.name().to_string(),
            amount: None,
            pickup_id: super::GOLDEN_RAIL_PICKUP_ID.to_string(),
            secret: false,
        });
        tracing::info!("PICKUP: {} claimed the golden Railgun", name);
        self.react(HostReactionKind::GoldenRail, Some(name), None, team);
    }

    /// Where a rule bot should walk for the golden Railgun, if it is free and near.
    pub(super) fn golden_rail_goal(
        &self,
        bot: &super::Player,
        nearest_enemy: f32,
    ) -> Option<[f32; 3]> {
        let gold = self.golden_rail.as_ref()?;
        if gold.holder.is_some() || bot.is_boss || nearest_enemy < 8.0 {
            return None;
        }
        let distance = (gold.x - bot.x).hypot(gold.z - bot.z);
        (distance < 30.0).then_some([gold.x, gold.floor, gold.z])
    }
}
