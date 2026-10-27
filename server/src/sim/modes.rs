//! Rule-set behaviour on top of the arena sim: sides, lives, the golden
//! Railgun and the Host's reactions. `crate::rules` decides what the rules
//! are; this is where the sim follows them.
use super::{
    GameState, Leader, Standing, PICKUP_CLAIM_HEIGHT, PICKUP_CLAIM_RADIUS, PLAYER_FLOOR_Y,
};
use crate::protocol::{
    GameEvent, GameMode, HostReactionKind, Team, WeaponType, HOST_REACTION_VARIANTS,
};
use uuid::Uuid;

/// What one scored frag tells the Host.
pub(super) struct FragFacts {
    pub killer: Uuid,
    pub killer_name: String,
    pub killer_team: Option<Team>,
    pub victim_name: String,
    pub victim_team: Option<Team>,
    /// The killer's streak including this frag.
    pub killer_streak: u32,
    /// The streak the victim's death ended.
    pub ended_streak: u32,
    /// The side credited with a team deathmatch frag.
    pub team_frag: Option<Team>,
}

/// One Host call: kind, the fighter it is about, the other fighter, the side.
type Call = (
    HostReactionKind,
    Option<String>,
    Option<String>,
    Option<Team>,
);

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

    /// The side the next admitted participant takes, or `None` without
    /// sides. A Sabotage joiner evens the sides, then joins the side behind
    /// on rounds. Rule-bot fill reads this to name a seat before admission.
    pub(crate) fn joining_team(&self) -> Option<crate::protocol::Team> {
        let standings = self
            .sabotage
            .as_ref()
            .map_or(self.team_scores, |sab| sab.score);
        (self.config.rules.teams() && !self.map.is_campaign())
            .then(|| crate::rules::choose_team(self.team_counts(), standings))
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
            let is_bot = |p: &super::Player| bots.contains(&p.id);
            // A league regular crosses sides without a name change.
            let fits_small = |p: &super::Player| {
                crate::roster::find(&p.name).is_none_or(|f| f.allegiance.fits(Some(small)))
            };
            let Some(index) = self
                .players
                .iter()
                .rposition(|p| on_big(p) && is_bot(p) && fits_small(p))
                .or_else(|| self.players.iter().rposition(|p| on_big(p) && is_bot(p)))
                .or_else(|| self.players.iter().rposition(on_big))
            else {
                break;
            };
            let id = self.players[index].id;
            self.drop_flag_from(id);
            self.drop_charge_from(id);
            self.rename_transferred_bot(index, small);
            let player = &mut self.players[index];
            player.team = Some(small);
            let (id, name, placed) = (
                player.id,
                player.name.clone(),
                player.respawn_timer.is_none() && !player.eliminated,
            );
            tracing::info!(target: crate::logging::FEED_TARGET, "TEAM BALANCE: {} moves to {}", name, small.id());
            if placed {
                self.do_respawn(id);
            }
        }
    }

    /// A rule bot moved onto a side its callsign cannot sit on (a free
    /// agent onto Union seats, or the reverse) takes a fitting callsign, so
    /// the killfeed never shows Formerly 4471 wearing Union colors.
    pub(super) fn rename_transferred_bot(&mut self, index: usize, team: Team) {
        let id = self.players[index].id;
        let Some(behavior) = self
            .bots
            .iter()
            .find(|bot| bot.player_id == id)
            .map(|bot| bot.behavior)
        else {
            return;
        };
        let taken: Vec<&str> = self.players.iter().map(|p| p.name.as_str()).collect();
        let current = self.players[index].name.as_str();
        let Some((fighter, name)) =
            crate::roster::transfer(current, behavior, team, self.rng_state, &taken)
        else {
            return;
        };
        tracing::info!("TEAM BALANCE: {current} signs on as {name}");
        let player = &mut self.players[index];
        player.name = name;
        player.body = fighter.body;
    }

    /// Call a Host beat. The client owns the words; the server sends the
    /// kind, a rotating variant and the names. Calls are rare: a big one
    /// waits out the gap after the last big one, a caption the gap after any
    /// call, so voices never stack. Returns whether the call landed.
    pub(crate) fn react(
        &mut self,
        kind: HostReactionKind,
        player: Option<String>,
        other: Option<String>,
        team: Option<Team>,
    ) -> bool {
        let big = kind.big();
        let since = if big {
            self.reactions.last_big_tick
        } else {
            self.reactions.last_tick
        };
        if !kind.always()
            && since.is_some_and(|last| self.tick < last + crate::rules::REACTION_GAP_TICKS)
        {
            return false;
        }
        self.reactions.last_tick = Some(self.tick);
        if big {
            self.reactions.last_big_tick = Some(self.tick);
        }
        let slot = HostReactionKind::ALL
            .iter()
            .position(|k| *k == kind)
            .expect("every reaction kind is listed");
        let count = self.reaction_counts[slot];
        self.reaction_counts[slot] = count.wrapping_add(1);
        let variant = (count % u32::from(HOST_REACTION_VARIANTS)) as u8;
        tracing::info!(target: crate::logging::FEED_TARGET,
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
            big,
        });
        true
    }

    pub(crate) fn name_of(&self, id: Uuid) -> Option<String> {
        self.players
            .iter()
            .find(|p| p.id == id)
            .map(|p| p.name.clone())
    }

    /// After a scored frag: advance the killer's multikill chain, keep the
    /// side and lead memory current, and make at most one call, the biggest
    /// thing the frag did. First blood, then a multikill of three or more, a
    /// comeback, a spree tier, an ended spree, a double, a new leader.
    pub(super) fn react_to_frag(&mut self, frag: FragFacts) {
        let tick = self.tick;
        let chain = self
            .reactions
            .chains
            .entry(frag.killer)
            .or_insert((0, tick));
        chain.0 = if chain.0 > 0
            && tick.saturating_sub(chain.1) <= crate::rules::MULTIKILL_WINDOW_TICKS
        {
            chain.0 + 1
        } else {
            1
        };
        chain.1 = tick;
        let multikill = HostReactionKind::multikill(chain.0);
        let comeback = frag.team_frag.and_then(|side| self.note_team_frag(side));
        let lead = self.note_lead();
        let step = crate::rules::spree_step(self.config.rules.mode());
        let first = !std::mem::replace(&mut self.reactions.first_blood, true);
        let lot_spike = self.note_lot_frag();
        let by_killer = |kind: HostReactionKind| -> Call {
            (
                kind,
                Some(frag.killer_name.clone()),
                Some(frag.victim_name.clone()),
                frag.killer_team,
            )
        };
        let call: Option<Call> = if first {
            Some(by_killer(HostReactionKind::FirstBlood))
        } else if let Some(kind) = multikill.filter(|kind| kind.big()) {
            Some(by_killer(kind))
        } else if let Some(side) = comeback {
            Some((HostReactionKind::Comeback, None, None, Some(side)))
        } else if let Some(kind) = HostReactionKind::spree(frag.killer_streak, step) {
            Some(by_killer(kind))
        } else if frag.ended_streak >= step {
            Some((
                HostReactionKind::StreakEnded,
                Some(frag.victim_name.clone()),
                Some(frag.killer_name.clone()),
                frag.victim_team,
            ))
        } else if lot_spike {
            // Frags spread across the lot; one fighter's run is a multikill.
            Some(by_killer(HostReactionKind::LarakLotSpecial))
        } else if let Some(kind) = multikill {
            Some(by_killer(kind))
        } else {
            lead.map(|(player, other, team)| (HostReactionKind::LeadChange, player, other, team))
        };
        match call {
            Some((HostReactionKind::LarakLotSpecial, player, _, team)) => {
                self.call_lot_special(player, team);
            }
            Some((kind, player, other, team)) => {
                self.react(kind, player, other, team);
            }
            None => {}
        }
    }

    /// Count a side frag and remember the worst deficit each side has faced.
    /// Returns the side when one that was far behind has just drawn level.
    pub(super) fn note_team_frag(&mut self, side: Team) -> Option<Team> {
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
            return Some(side);
        }
        None
    }

    /// The sole front of the round: a side ahead on frags or captures, or
    /// the one free-for-all fighter on the top score. None when level.
    fn current_leader(&self) -> Option<(Leader, u32)> {
        match self.config.rules.mode() {
            GameMode::Tdm => self
                .team_scores
                .leader()
                .map(|side| (Leader::Side(side), self.team_scores.max())),
            GameMode::Ctf => self
                .capture_scores
                .leader()
                .map(|side| (Leader::Side(side), self.capture_scores.max())),
            GameMode::Ffa | GameMode::Duel => {
                let mut best: Option<(Uuid, u32)> = None;
                let mut level = false;
                for player in self.players.iter().filter(|p| p.contestant()) {
                    let score = self.scores.get(&player.id).copied().unwrap_or(0);
                    match best {
                        Some((_, top)) if score < top => {}
                        Some((_, top)) if score == top => level = true,
                        _ => {
                            best = Some((player.id, score));
                            level = false;
                        }
                    }
                }
                best.filter(|_| !level)
                    .map(|(id, score)| (Leader::Fighter(id), score))
            }
            GameMode::Sabotage | GameMode::Conquest => None,
        }
    }

    /// Remember the front. Returns the new leader's name, the one they passed
    /// and the side when the lead has just changed hands. A free-for-all or
    /// team deathmatch lead is only worth a line once it is a few frags deep.
    pub(super) fn note_lead(&mut self) -> Option<(Option<String>, Option<String>, Option<Team>)> {
        let (now, score) = self.current_leader()?;
        let before = self.reactions.leader.replace(now)?;
        let deep = match now {
            Leader::Fighter(_) => score >= crate::rules::LEAD_CHANGE_MIN_FRAGS,
            Leader::Side(_) if self.config.rules.mode() == GameMode::Tdm => {
                score >= crate::rules::LEAD_CHANGE_MIN_FRAGS
            }
            Leader::Side(_) => true,
        };
        if before == now || !deep {
            return None;
        }
        Some(match (now, before) {
            (Leader::Fighter(id), Leader::Fighter(previous)) => {
                let team = self
                    .players
                    .iter()
                    .find(|p| p.id == id)
                    .and_then(|p| p.team);
                (self.name_of(id), self.name_of(previous), team)
            }
            (Leader::Side(side), _) | (_, Leader::Side(side)) => (None, None, Some(side)),
        })
    }

    /// Whether the clock ran out on a level front that somebody has scored
    /// on, so the next score decides. A scoreless clock simply ends.
    pub(super) fn level_at_the_clock(&self) -> bool {
        let level =
            |scores: crate::protocol::TeamScores| scores.leader().is_none() && scores.max() > 0;
        match self.config.rules.mode() {
            GameMode::Sabotage => false,
            GameMode::Tdm => level(self.team_scores),
            GameMode::Ctf => level(self.capture_scores),
            GameMode::Conquest => self
                .conquest
                .as_ref()
                .is_some_and(|state| state.tickets.leader().is_none()),
            GameMode::Ffa | GameMode::Duel => {
                let mut scores: Vec<u32> = self
                    .players
                    .iter()
                    .filter(|p| p.contestant())
                    .map(|p| self.scores.get(&p.id).copied().unwrap_or(0))
                    .collect();
                scores.sort_unstable_by(|a, b| b.cmp(a));
                scores.len() >= 2 && scores[0] == scores[1] && scores[0] > 0
            }
        }
    }

    /// The round clock ran out level: stop it and let the next score decide.
    pub(super) fn begin_sudden_death(&mut self) {
        self.sudden_death = Some(self.tick);
        tracing::info!(target: crate::logging::FEED_TARGET, "SUDDEN DEATH: level at the clock, the next score decides");
    }

    /// Once per round each: sudden death the tick it starts, and match point
    /// for every side (or the first free-for-all fighter) one score from the
    /// limit. A call held back by the gap is tried again on a later tick
    /// while the position still holds.
    pub(super) fn react_to_match_point(&mut self) {
        if self.solo_broadcast.enabled || self.map.is_campaign() {
            return;
        }
        if self.sudden_death.is_some() {
            if !self.reactions.sudden_death_called {
                self.reactions.sudden_death_called = true;
                self.react(HostReactionKind::SuddenDeath, None, None, None);
            }
            return;
        }
        let mode = self.config.rules.mode();
        let one_short = |scores: crate::protocol::TeamScores, limit: u32| {
            (limit >= 2).then(|| Team::ALL.map(|side| scores.get(side) + 1 == limit))
        };
        let sides: Option<[bool; 2]> = match mode {
            GameMode::Tdm => self
                .config
                .frag_limit
                .and_then(|limit| one_short(self.team_scores, limit)),
            GameMode::Ctf => one_short(
                self.capture_scores,
                self.config
                    .capture_limit
                    .unwrap_or(crate::rules::CTF_CAPTURE_LIMIT),
            ),
            GameMode::Sabotage => self.sabotage.as_ref().map(|sab| {
                let side =
                    crate::rules::match_point(self.config.sabotage.format, sab.round, sab.score);
                Team::ALL.map(|team| side == Some(team))
            }),
            GameMode::Ffa | GameMode::Duel | GameMode::Conquest => None,
        };
        if let Some(sides) = sides {
            for side in Team::ALL {
                if sides[side.index()]
                    && !self.reactions.match_point[side.index()]
                    && self.react(HostReactionKind::MatchPoint, None, None, Some(side))
                {
                    self.reactions.match_point[side.index()] = true;
                }
            }
            return;
        }
        if !mode.free_for_all() || self.reactions.match_point_fighter {
            return;
        }
        let Some(limit) = self.config.frag_limit.filter(|limit| *limit >= 2) else {
            return;
        };
        // Callsign order picks one when several reach it on the same tick.
        let fighter = self
            .players
            .iter()
            .filter(|p| p.contestant() && self.scores.get(&p.id).copied() == Some(limit - 1))
            .min_by(|a, b| a.name.cmp(&b.name))
            .map(|p| (p.name.clone(), p.team));
        if let Some((name, team)) = fighter {
            if self.react(HostReactionKind::MatchPoint, Some(name), None, team) {
                self.reactions.match_point_fighter = true;
            }
        }
    }

    /// Larak Lot: count the frag, and say whether enough have landed across
    /// the lot inside the window, off the special's cooldown, for the Host to
    /// call the Larak Lot special. Every other map stays quiet.
    pub(crate) fn note_lot_frag(&mut self) -> bool {
        if self.map != super::MapKind::ArenaDuel {
            return false;
        }
        let tick = self.tick;
        let frags = &mut self.reactions.lot_frags;
        frags.push_back(tick);
        while frags
            .front()
            .is_some_and(|&at| at + crate::rules::LOT_SPECIAL_WINDOW_TICKS <= tick)
        {
            frags.pop_front();
        }
        frags.len() >= crate::rules::LOT_SPECIAL_FRAGS
            && !self
                .reactions
                .lot_special
                .is_some_and(|at| tick < at + crate::rules::LOT_SPECIAL_COOLDOWN_TICKS)
    }

    /// The Larak Lot special for the fighter whose frag tipped the spike. A
    /// text caption under the usual spacing; once called it cools down.
    pub(crate) fn call_lot_special(&mut self, killer: Option<String>, team: Option<Team>) -> bool {
        let called = self.react(HostReactionKind::LarakLotSpecial, killer, None, team);
        if called {
            self.reactions.lot_special = Some(self.tick);
            self.reactions.lot_frags.clear();
        }
        called
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
                tracing::info!(target: crate::logging::FEED_TARGET, "Golden Railgun returned to its pad");
            }
        }
        if let Some(player) = self.players.iter_mut().find(|p| p.id == id) {
            player.golden = false;
        }
    }

    /// First living contestant on the golden pad takes it. A parked pawn
    /// keeps its last position and does not take the gun while gone.
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
                && !p.detached
                && (p.inventory.owns(WeaponType::Rail)
                    || (p.inventory.policy() == crate::protocol::EquipmentPolicy::Discovery
                        && p.inventory.only().is_none()))
                && (p.y - PLAYER_FLOOR_Y - gold.floor).abs() <= PICKUP_CLAIM_HEIGHT
                && (p.x - gold.x).hypot(p.z - gold.z) <= PICKUP_CLAIM_RADIUS
        });
        let Some(index) = taker else {
            return;
        };
        let player = &mut self.players[index];
        player.golden = true;
        // Under discovery equipment the golden pad is also the Railgun.
        player.inventory.grant_weapon(WeaponType::Rail);
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
        tracing::info!(target: crate::logging::FEED_TARGET, "PICKUP: {} claimed the golden Railgun", name);
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
