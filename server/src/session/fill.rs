use super::*;
use crate::bot_fill::{AdmissionGate, AdmissionPhase, FillRefusal};
use tokio::sync::{oneshot, OwnedSemaphorePermit};

pub(super) enum ReservedSeat {
    Free(OwnedSemaphorePermit),
    Bot(Uuid),
}

pub(super) struct Reservation {
    gate: AdmissionGate,
    seat: ReservedSeat,
}

impl GameSession {
    pub(crate) fn set_auto_fill(&mut self, target: usize) {
        self.auto_fill_target = Some(target);
        self.min_bots = 0;
        self.reconcile_auto_fill();
    }

    fn occupied(&self) -> usize {
        self.state
            .players
            .iter()
            .filter(|p| p.is_participant())
            .count()
    }

    fn reserved_bot(&self, id: Uuid) -> bool {
        self.auto_reservations
            .values()
            .any(|r| matches!(r.seat, ReservedSeat::Bot(bot) if bot == id))
    }

    fn safe_bot(&self, id: Uuid) -> bool {
        if !self.bots.iter().any(|bot| bot.player_id == id) || self.state.owns_committed_devices(id)
        {
            return false;
        }
        let Some(player) = self.state.players.iter().find(|p| p.id == id) else {
            return false;
        };
        let Some(sab) = self.state.sabotage.as_ref().filter(|sab| {
            matches!(
                sab.phase,
                protocol::SabotagePhase::Live | protocol::SabotagePhase::Planted
            )
        }) else {
            return true;
        };
        if sab.hold.as_ref().is_some_and(|hold| hold.player == id)
            || sab
                .charge
                .as_ref()
                .is_some_and(|charge| charge.carrier == Some(id) && charge.planted.is_none())
        {
            return false;
        }
        !player.standing()
            || self
                .state
                .players
                .iter()
                .any(|other| other.id != id && other.team == player.team && other.standing())
    }

    fn yield_candidate(&self) -> Option<Uuid> {
        self.bots
            .iter()
            .filter_map(|bot| {
                let id = bot.player_id;
                let player = self.state.players.iter().find(|p| p.id == id)?;
                (!self.reserved_bot(id) && self.safe_bot(id)).then_some((player.standing(), id))
            })
            .min()
            .map(|(_, id)| id)
    }

    fn retire_bot(&mut self, id: Uuid) {
        self.state.remove_player(id);
        self.bots.retain(|bot| bot.player_id != id);
        self.state.bots.retain(|bot| bot.player_id != id);
        self.navigators.remove(&id);
        self.sent_loadouts.remove(&id);
        self.sent_records.remove(&id);
        self.bot_seats.remove(&id);
        self.refresh_roster_host_line();
    }

    pub(super) fn reconcile_auto_fill(&mut self) {
        let Some(target) = self.auto_fill_target else {
            return;
        };
        self.bot_seats
            .retain(|id, _| self.state.players.iter().any(|p| p.id == *id));
        while self.occupied() > target {
            let Some(id) = self.yield_candidate() else {
                break;
            };
            self.retire_bot(id);
        }
        let pending_free = self
            .auto_reservations
            .values()
            .filter(|r| matches!(r.seat, ReservedSeat::Free(_)))
            .count();
        let missing = target.saturating_sub(self.occupied() + pending_free);
        if missing > 0 {
            self.spawn_bots(missing);
        }
    }

    pub(super) fn expire_auto_reservations(&mut self) {
        self.auto_reservations.retain(|_, r| {
            let gate = r.gate.lock().unwrap_or_else(|error| error.into_inner());
            gate.phase == AdmissionPhase::Pending && std::time::Instant::now() < gate.deadline
        });
    }

    pub(super) fn prepare_auto_join(
        &mut self,
        client_id: Uuid,
        gate: AdmissionGate,
        reply: oneshot::Sender<Result<(), FillRefusal>>,
    ) {
        self.expire_auto_reservations();
        let status = gate.lock().unwrap_or_else(|error| error.into_inner());
        if reply.is_closed()
            || status.phase != AdmissionPhase::Pending
            || std::time::Instant::now() >= status.deadline
        {
            let _ = reply.send(Err(FillRefusal::Cancelled));
            return;
        }
        if self.auto_fill_target.is_none() || self.auto_reservations.contains_key(&client_id) {
            let _ = reply.send(Err(FillRefusal::Cancelled));
            return;
        }
        let Some(slots) = self.configure_sabotage_seats() else {
            let _ = reply.send(Err(FillRefusal::Cancelled));
            return;
        };
        let seat = match slots.try_acquire_owned() {
            Ok(seat) => ReservedSeat::Free(seat),
            Err(_) => {
                let Some(bot) = self
                    .yield_candidate()
                    .filter(|id| self.bot_seats.contains_key(id))
                else {
                    let any_bot = self
                        .bots
                        .iter()
                        .any(|b| self.bot_seats.contains_key(&b.player_id));
                    let _ = reply.send(Err(if any_bot {
                        FillRefusal::NextRound
                    } else {
                        FillRefusal::Full
                    }));
                    return;
                };
                ReservedSeat::Bot(bot)
            }
        };
        drop(status);
        self.auto_reservations
            .insert(client_id, Reservation { gate, seat });
        if reply.send(Ok(())).is_err() {
            self.auto_reservations.remove(&client_id);
        }
    }

    pub(super) fn commit_auto_join(
        &mut self,
        identity: crate::net::JoinIdentity,
        reply: oneshot::Sender<Result<OwnedSemaphorePermit, FillRefusal>>,
    ) {
        let Some(reservation) = self.auto_reservations.remove(&identity.client_id) else {
            let _ = reply.send(Err(FillRefusal::Cancelled));
            return;
        };
        let mut gate = reservation
            .gate
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if reply.is_closed()
            || gate.phase != AdmissionPhase::Pending
            || std::time::Instant::now() >= gate.deadline
        {
            let _ = reply.send(Err(FillRefusal::Cancelled));
            return;
        }
        let (seat, bot) = match reservation.seat {
            ReservedSeat::Free(seat) if self.occupied() < 10 => (seat, None),
            ReservedSeat::Bot(id) if self.safe_bot(id) => {
                let Some(seat) = self.bot_seats.remove(&id) else {
                    let _ = reply.send(Err(FillRefusal::Cancelled));
                    return;
                };
                (seat, Some(id))
            }
            _ => {
                let _ = reply.send(Err(FillRefusal::NextRound));
                return;
            }
        };
        if let Err(result) = reply.send(Ok(seat)) {
            if let (Some(id), Ok(seat)) = (bot, result) {
                self.bot_seats.insert(id, seat);
            }
            return;
        }
        // Successful grant linearizes admission. Drop now means ordinary leave.
        gate.phase = AdmissionPhase::Committed;
        if let Some(id) = bot {
            self.retire_bot(id);
        }
        self.apply_command(GameCommand::Connected {
            id: identity.client_id,
            role: identity.role,
            name: identity.name,
            player_id: Some(identity.player_id),
            body: identity.body,
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bot_fill::admission_gate;
    use crate::protocol::{BodyKind, GameMode, SabotagePhase, Team};
    use crate::rules::{RuleSet, SabotageConfig};
    use crate::sim::MatchConfig;

    fn room(mode: GameMode, target: usize) -> GameSession {
        let map = if mode == GameMode::Conquest {
            MapKind::HoldfastAtoll
        } else {
            MapKind::Sector9
        };
        let mut session = GameSession::with_map(map, false);
        session.state.apply_config(MatchConfig {
            rules: RuleSet::new(mode, &[], false).unwrap(),
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            frag_limit: None,
            time_limit_ticks: None,
            sabotage: SabotageConfig {
                five_vs_five: mode == GameMode::Sabotage,
                muster_ticks: 4,
                ..Default::default()
            },
            ..Default::default()
        });
        session.set_auto_fill(target);
        session
    }

    fn identity(n: u128, role: Role) -> crate::net::JoinIdentity {
        crate::net::JoinIdentity {
            client_id: Uuid::from_u128(n),
            player_id: Uuid::from_u128(n + 100),
            name: "Dead Air Dan".into(),
            role,
            body: BodyKind::Human,
        }
    }

    fn prepare(session: &mut GameSession, n: u128) -> Result<AdmissionGate, FillRefusal> {
        let gate = admission_gate();
        let (reply, mut receiver) = oneshot::channel();
        session.apply_command(GameCommand::PrepareAutoJoin {
            client_id: Uuid::from_u128(n),
            gate: Arc::clone(&gate),
            reply,
        });
        receiver.try_recv().unwrap().map(|()| gate)
    }

    fn commit(
        session: &mut GameSession,
        n: u128,
        role: Role,
    ) -> Result<OwnedSemaphorePermit, FillRefusal> {
        let (reply, mut receiver) = oneshot::channel();
        session.apply_command(GameCommand::CommitAutoJoin {
            identity: identity(n, role),
            reply,
        });
        receiver.try_recv().unwrap()
    }

    #[test]
    fn automatic_tdm_prioritizes_humans_and_external_agents_above_target() {
        assert_open_team_fill(GameMode::Tdm);
    }

    #[test]
    fn automatic_conquest_yields_bots_and_refills_after_real_departures() {
        assert_open_team_fill(GameMode::Conquest);
    }

    fn assert_open_team_fill(mode: GameMode) {
        let mut session = room(mode, 4);
        assert_eq!(session.state.config.rules.mode(), mode);
        assert_eq!(session.bots.len(), 4);
        assert_eq!(session.min_bots, 0);
        for n in 1..=5 {
            let who = identity(n, if n % 2 == 0 { Role::Agent } else { Role::Human });
            session.apply_command(GameCommand::Connected {
                id: who.client_id,
                player_id: Some(who.player_id),
                name: who.name,
                role: who.role,
                body: who.body,
            });
            session.ensure_min_bots();
            assert_eq!(session.bots.len(), 4usize.saturating_sub(n as usize));
            assert!(session.state.players.iter().any(|p| p.id == who.player_id));
        }
        assert_eq!(session.occupied(), 5);
        session.apply_command(GameCommand::Detached {
            id: Uuid::from_u128(1),
        });
        session.ensure_min_bots();
        assert_eq!(session.occupied(), 5);
        assert!(session.bots.is_empty());
        session.apply_command(GameCommand::Disconnected {
            id: Uuid::from_u128(2),
        });
        session.apply_command(GameCommand::Disconnected {
            id: Uuid::from_u128(3),
        });
        session.ensure_min_bots();
        assert_eq!((session.occupied(), session.bots.len()), (4, 1));
        session.drop_expired_pawn(Uuid::from_u128(101));
        session.ensure_min_bots();
        assert_eq!((session.occupied(), session.bots.len()), (4, 2));
        assert!(session
            .state
            .players
            .iter()
            .all(|player| player.team.is_some()));
    }

    #[test]
    fn strict_automatic_muster_transfers_exact_bot_seats_to_equal_participants() {
        let mut session = room(GameMode::Sabotage, 10);
        session.state.start_round();
        let slots = session.configure_sabotage_seats().unwrap();
        let before: Vec<_> = session.state.players.iter().map(|p| p.id).collect();
        let first = prepare(&mut session, 1).unwrap();
        let second = prepare(&mut session, 2).unwrap();
        assert_eq!(
            session.bots.len(),
            10,
            "prepare must leave every bot untouched"
        );
        assert_eq!(slots.available_permits(), 0);
        let human = commit(&mut session, 1, Role::Human).unwrap();
        let agent = commit(&mut session, 2, Role::Agent).unwrap();
        assert_eq!(first.lock().unwrap().phase, AdmissionPhase::Committed);
        assert_eq!(second.lock().unwrap().phase, AdmissionPhase::Committed);
        assert_eq!(
            (
                session.occupied(),
                session.bots.len(),
                slots.available_permits()
            ),
            (10, 8, 0)
        );
        assert_eq!(session.state.team_counts(), [5, 5]);
        assert!(
            before
                .iter()
                .filter(|id| !session.state.players.iter().any(|p| p.id == **id))
                .count()
                == 2
        );
        for n in [101, 102] {
            assert!(session
                .state
                .players
                .iter()
                .find(|p| p.id == Uuid::from_u128(n))
                .unwrap()
                .standing());
        }
        assert!(
            session
                .take_unicasts()
                .iter()
                .filter(|(_, message)| matches!(message, ServerMessage::MapInfo { .. }))
                .count()
                == 2
        );
        drop((human, agent));
    }

    #[test]
    fn cancelled_and_expired_preparation_never_removes_a_bot_or_steals_a_free_seat() {
        for target in [4, 10] {
            let mut session = room(GameMode::Sabotage, target);
            let slots = session.configure_sabotage_seats().unwrap();
            let original = slots.available_permits();
            let (reply, receiver) = oneshot::channel();
            drop(receiver);
            session.prepare_auto_join(Uuid::from_u128(1), admission_gate(), reply);
            assert_eq!(slots.available_permits(), original);
            assert!(session.auto_reservations.is_empty());
            let gate = prepare(&mut session, 2).unwrap();
            gate.lock().unwrap().deadline = std::time::Instant::now();
            session.ensure_min_bots();
            assert_eq!(slots.available_permits(), original);
            assert_eq!(session.bots.len(), target);
            assert!(session.auto_reservations.is_empty());
            assert!(matches!(
                commit(&mut session, 2, Role::Human),
                Err(FillRefusal::Cancelled)
            ));
            let gate = prepare(&mut session, 3).unwrap();
            gate.lock().unwrap().phase = AdmissionPhase::Cancelled;
            assert!(matches!(
                commit(&mut session, 3, Role::Agent),
                Err(FillRefusal::Cancelled)
            ));
            assert_eq!(slots.available_permits(), original);
            assert_eq!(session.bots.len(), target);
        }
    }

    #[test]
    fn closed_commit_receiver_preserves_exact_original_bot_and_permit() {
        let mut session = room(GameMode::Sabotage, 10);
        let original: Vec<_> = session.state.players.iter().map(|p| p.id).collect();
        prepare(&mut session, 1).unwrap();
        let (reply, receiver) = oneshot::channel();
        drop(receiver);
        session.commit_auto_join(identity(1, Role::Human), reply);
        assert_eq!(
            session
                .state
                .players
                .iter()
                .map(|p| p.id)
                .collect::<Vec<_>>(),
            original
        );
        assert_eq!(session.bot_seats.len(), 10);
        assert!(session.auto_reservations.is_empty());
    }

    #[test]
    fn delayed_commit_rechecks_live_carrier_and_last_standing_safety() {
        let mut session = room(GameMode::Sabotage, 10);
        session.state.start_round();
        prepare(&mut session, 1).unwrap();
        let reserved = match session.auto_reservations[&Uuid::from_u128(1)].seat {
            ReservedSeat::Bot(id) => id,
            _ => panic!("full bot room"),
        };
        let team = session
            .state
            .players
            .iter()
            .find(|p| p.id == reserved)
            .unwrap()
            .team;
        session.state.sabotage.as_mut().unwrap().phase = SabotagePhase::Live;
        for p in &mut session.state.players {
            if p.team == team && p.id != reserved {
                p.eliminated = true;
            }
        }
        let sab = session.state.sabotage.clone();
        assert!(matches!(
            commit(&mut session, 1, Role::Human),
            Err(FillRefusal::NextRound)
        ));
        assert_eq!(session.bots.len(), 10);
        assert_eq!(session.state.sabotage, sab);
        let candidate = session
            .state
            .players
            .iter()
            .find(|p| p.team != team)
            .unwrap()
            .id;
        session
            .state
            .sabotage
            .as_mut()
            .unwrap()
            .charge
            .as_mut()
            .unwrap()
            .carrier = Some(candidate);
        assert!(
            !session.safe_bot(candidate),
            "committed carrier cannot yield live"
        );
    }

    #[test]
    fn full_external_and_unsafe_bot_rooms_refuse_without_new_body_or_score() {
        let mut session = room(GameMode::Sabotage, 10);
        let mut permits = Vec::new();
        for n in 1..=10 {
            prepare(&mut session, n).unwrap();
            permits.push(commit(&mut session, n, Role::Agent).unwrap());
        }
        assert!(session.bots.is_empty());
        assert!(matches!(prepare(&mut session, 11), Err(FillRefusal::Full)));
        assert_eq!(session.occupied(), 10);

        let mut session = room(GameMode::Sabotage, 10);
        session.state.start_round();
        session.state.sabotage.as_mut().unwrap().phase = SabotagePhase::Live;
        // Only one bot each side remains, and all other owned slots are reserved.
        for team in [Team::Union, Team::Coalition] {
            let mut seen = false;
            for p in session
                .state
                .players
                .iter_mut()
                .filter(|p| p.team == Some(team))
            {
                p.eliminated = seen;
                seen = true;
            }
        }
        let carrier = session
            .state
            .players
            .iter()
            .find(|p| p.team == Some(Team::Coalition) && p.standing())
            .unwrap()
            .id;
        session
            .state
            .sabotage
            .as_mut()
            .unwrap()
            .charge
            .as_mut()
            .unwrap()
            .carrier = Some(carrier);
        for n in 1..=8 {
            prepare(&mut session, n).unwrap();
        }
        let sab = session.state.sabotage.clone();
        assert!(matches!(
            prepare(&mut session, 9),
            Err(FillRefusal::NextRound)
        ));
        assert_eq!(session.state.sabotage, sab);
        assert_eq!(session.occupied(), 10);
    }

    #[test]
    fn a_live_defuse_and_planted_clock_survive_an_unrelated_safe_bot_yield() {
        let mut session = room(GameMode::Sabotage, 10);
        session.state.start_round();
        session.state.sabotage.as_mut().unwrap().phase = SabotagePhase::Live;
        let carrier = session
            .state
            .sabotage
            .as_ref()
            .unwrap()
            .charge
            .as_ref()
            .unwrap()
            .carrier
            .unwrap();
        let defuser = session
            .state
            .players
            .iter()
            .find(|p| p.team == Some(Team::Union))
            .unwrap()
            .id;
        let at = [-38.0, 0.0, -27.0];
        for id in [carrier, defuser] {
            let player = session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == id)
                .unwrap();
            player.x = at[0] + if id == defuser { 1.0 } else { 0.0 };
            player.y = at[1] + crate::sim::PLAYER_FLOOR_Y;
            player.z = at[2];
            player.vy = 0.0;
        }
        session.state.set_action(
            carrier,
            protocol::Action {
                interact: true,
                ..Default::default()
            },
        );
        for _ in 0..=session.state.config.sabotage.plant_ticks {
            session.state.tick(0.05);
        }
        assert_eq!(
            session.state.sabotage.as_ref().unwrap().phase,
            SabotagePhase::Planted
        );
        session
            .state
            .set_action(carrier, protocol::Action::default());
        session.state.set_action(
            defuser,
            protocol::Action {
                interact: true,
                ..Default::default()
            },
        );
        session.state.tick(0.05);
        assert_eq!(
            session
                .state
                .sabotage
                .as_ref()
                .unwrap()
                .hold
                .as_ref()
                .unwrap()
                .player,
            defuser
        );
        assert!(!session.safe_bot(defuser));
        let before = session.state.sabotage.clone();
        session.state.take_events();
        prepare(&mut session, 1).unwrap();
        let _permit = commit(&mut session, 1, Role::Human).unwrap();
        assert_eq!(session.state.sabotage, before);
        assert!(session.state.players.iter().any(|p| p.id == defuser));
        let joined = session
            .state
            .players
            .iter()
            .find(|p| p.id == identity(1, Role::Human).player_id)
            .unwrap();
        assert!(joined.eliminated);
        assert_eq!(joined.lives, Some(0));
        assert!(!session
            .state
            .take_events()
            .iter()
            .any(|event| matches!(event, protocol::GameEvent::RoundEnd { .. })));
    }

    #[test]
    fn committed_device_owners_defer_administrative_retirement() {
        for mine in [false, true] {
            let mut session = room(GameMode::Tdm, 1);
            session.state.start_round();
            let owner = session.bots[0].player_id;
            let player = session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == owner)
                .unwrap();
            player.inventory.grant_grenades(1);
            player.inventory.grant_mines(1);
            session.state.set_action(
                owner,
                crate::protocol::Action {
                    throw_grenade: !mine,
                    place_mine: mine,
                    ..Default::default()
                },
            );
            session.state.tick(0.05);
            assert!(session.state.owns_committed_devices(owner));
            assert!(!session.safe_bot(owner));
            let who = identity(1, Role::Human);
            session.apply_command(GameCommand::Connected {
                id: who.client_id,
                player_id: Some(who.player_id),
                role: who.role,
                name: who.name,
                body: who.body,
            });
            session.ensure_min_bots();
            assert_eq!((session.occupied(), session.bots.len()), (2, 1));
            assert!(session.state.owns_committed_devices(owner));
            assert!(session.state.players.iter().any(|p| p.id == owner));
        }
    }
}
