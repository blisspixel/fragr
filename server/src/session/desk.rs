//! Venue-desk decisions. The match owns names and seats. The desk loop owns
//! the ban file and the terminal. A roster bot is on the card for the night:
//! kicking one would only make the refill put them back.

use super::GameSession;
use crate::desk::{split_ban_query, BanReady, DeskOutcome, DeskVerb};
use crate::protocol::{GameEvent, Role};
use std::net::{IpAddr, SocketAddr};
use uuid::Uuid;

const VENUE_SAY_COOLDOWN_TICKS: u64 = 20;

struct SeatHit {
    name: String,
    kind: SeatKind,
}

enum SeatKind {
    Roster,
    Fighter {
        player_id: Uuid,
        client_id: Option<Uuid>,
        ip: Option<IpAddr>,
    },
    Spectator {
        client_id: Uuid,
        ip: Option<IpAddr>,
    },
}

impl GameSession {
    pub(crate) fn desk(&mut self, verb: DeskVerb) -> DeskOutcome {
        match verb {
            DeskVerb::Who => DeskOutcome::Text(self.desk_who()),
            DeskVerb::Kick { name } => self.desk_kick(&name),
            DeskVerb::PrepareBan { query } => self.desk_prepare_ban(&query),
            DeskVerb::FinishBan(ready) => self.desk_finish_ban(ready),
            DeskVerb::Say { text } => DeskOutcome::Text(self.desk_say(&text)),
            DeskVerb::Stats => DeskOutcome::Text(self.sheet.desk_text()),
        }
    }

    fn desk_who(&self) -> String {
        let mut rows: Vec<(u8, String, String)> = Vec::new();
        for hit in self.desk_seats() {
            let (rank, kind, score, ip) = match &hit.kind {
                SeatKind::Fighter {
                    player_id,
                    ip,
                    client_id,
                    ..
                } => {
                    let parked = client_id.is_none();
                    let role = self
                        .state
                        .players
                        .iter()
                        .find(|player| player.id == *player_id)
                        .map(|player| player.role);
                    let kind = if parked {
                        "parked"
                    } else if role == Some(Role::Agent) {
                        "agent"
                    } else {
                        "human"
                    };
                    let rank = if parked {
                        3
                    } else if kind == "agent" {
                        1
                    } else {
                        0
                    };
                    (rank, kind, self.score_of(*player_id), *ip)
                }
                SeatKind::Spectator { ip, .. } => (2, "spectator", 0, *ip),
                SeatKind::Roster => (4, "roster", 0, None),
            };
            let score = match &hit.kind {
                SeatKind::Roster => self
                    .bots
                    .iter()
                    .find(|bot| {
                        self.state
                            .players
                            .iter()
                            .any(|player| player.id == bot.player_id && player.name == hit.name)
                    })
                    .map(|bot| self.score_of(bot.player_id))
                    .unwrap_or(0),
                _ => score,
            };
            let line = match ip {
                Some(ip) => format!("{}  {kind}  {score}  {ip}", hit.name),
                None => format!("{}  {kind}  {score}", hit.name),
            };
            rows.push((rank, hit.name, line));
        }
        if rows.is_empty() {
            return "The room is empty.".into();
        }
        rows.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
        rows.into_iter()
            .map(|(_, _, line)| line)
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn desk_kick(&mut self, name: &str) -> DeskOutcome {
        let Some(hit) = self.one_seat(name) else {
            return missing_or_many(name, &self.desk_seats());
        };
        match hit.kind {
            SeatKind::Roster => DeskOutcome::Text(
                "That one is on the card. The desk does not pull the roster.".into(),
            ),
            SeatKind::Fighter {
                player_id,
                client_id,
                ..
            } => {
                self.drop_fighter(player_id);
                close_or_text(client_id, false, format!("{} is off the floor.", hit.name))
            }
            SeatKind::Spectator { client_id, .. } => {
                self.spectators.remove(&client_id);
                close_or_text(
                    Some(client_id),
                    false,
                    format!("{} is off the floor.", hit.name),
                )
            }
        }
    }

    fn desk_prepare_ban(&self, query: &str) -> DeskOutcome {
        let names: Vec<String> = self.desk_seats().into_iter().map(|hit| hit.name).collect();
        let Some((name, reason)) = split_ban_query(query.trim(), &names) else {
            return DeskOutcome::Text(format!("Nobody here is called {}.", clean_query(query)));
        };
        let Some(hit) = self.one_seat(name) else {
            return missing_or_many(name, &self.desk_seats());
        };
        let (client_id, player_id, ip) = match hit.kind {
            SeatKind::Roster => {
                return DeskOutcome::Text("That one is on the card and has no address.".into());
            }
            SeatKind::Fighter {
                player_id,
                client_id,
                ip,
            } => (client_id, Some(player_id), ip),
            SeatKind::Spectator { client_id, ip } => (Some(client_id), None, ip),
        };
        let Some(ip) = ip else {
            return DeskOutcome::Text(format!("The desk never saw an address for {}.", hit.name));
        };
        let reason = if reason.is_empty() {
            "venue desk".to_string()
        } else {
            reason.to_string()
        };
        DeskOutcome::BanReady(BanReady {
            client_id,
            player_id,
            ip,
            name: hit.name,
            reason,
        })
    }

    fn desk_finish_ban(&mut self, ready: BanReady) -> DeskOutcome {
        let still = if let Some(player_id) = ready.player_id {
            self.state
                .players
                .iter()
                .any(|player| player.id == player_id && player.name == ready.name)
        } else if let Some(client_id) = ready.client_id {
            self.spectators
                .get(&client_id)
                .is_some_and(|seat| seat.name == ready.name)
        } else {
            false
        };
        if !still {
            return DeskOutcome::Text(format!("{} stays out. They had already left.", ready.ip));
        }
        let client_id = if let Some(player_id) = ready.player_id {
            self.drop_fighter(player_id)
        } else {
            ready.client_id.filter(|id| {
                self.spectators.remove(id);
                true
            })
        };
        let text = format!("{} stays out. {} is off the floor.", ready.ip, ready.name);
        close_or_text(client_id, true, text)
    }

    fn desk_say(&mut self, text: &str) -> String {
        let trimmed: String = text
            .trim()
            .chars()
            .take(crate::sim::SPEAK_MAX_CHARS + 1)
            .collect();
        if trimmed.is_empty()
            || trimmed.chars().count() > crate::sim::SPEAK_MAX_CHARS
            || trimmed.chars().any(char::is_control)
        {
            return "That line does not go on the air.".into();
        }
        if self
            .venue_said_tick
            .is_some_and(|last| self.state.tick.saturating_sub(last) < VENUE_SAY_COOLDOWN_TICKS)
        {
            return "The venue just spoke. Wait a moment.".into();
        }
        self.venue_said_tick = Some(self.state.tick);
        self.state.push_event(GameEvent::VenueNotice {
            text: format!("The venue: {trimmed}"),
        });
        let tick = self.state.tick;
        self.board.note_floor("The venue", &trimmed, tick);
        "On the air.".into()
    }

    fn desk_seats(&self) -> Vec<SeatHit> {
        let mut hits = Vec::new();
        for player in &self.state.players {
            if player.is_boss || player.campaign.is_some() {
                continue;
            }
            let roster = self.bots.iter().any(|bot| bot.player_id == player.id);
            if roster {
                hits.push(SeatHit {
                    name: player.name.clone(),
                    kind: SeatKind::Roster,
                });
                continue;
            }
            let client_id = self.live_client.get(&player.id).copied();
            let ip = self.fighter_peers.get(&player.id).map(SocketAddr::ip);
            if client_id.is_none() && ip.is_none() {
                continue;
            }
            hits.push(SeatHit {
                name: player.name.clone(),
                kind: SeatKind::Fighter {
                    player_id: player.id,
                    client_id,
                    ip,
                },
            });
        }
        for (client_id, seat) in &self.spectators {
            hits.push(SeatHit {
                name: seat.name.clone(),
                kind: SeatKind::Spectator {
                    client_id: *client_id,
                    ip: seat.peer.map(|peer| peer.ip()),
                },
            });
        }
        hits
    }

    fn one_seat(&self, name: &str) -> Option<SeatHit> {
        let mut found = self.desk_seats().into_iter().filter(|hit| hit.name == name);
        let first = found.next()?;
        if found.next().is_some() {
            return None;
        }
        Some(first)
    }

    fn score_of(&self, player_id: Uuid) -> u32 {
        self.state.scores.get(&player_id).copied().unwrap_or(0)
    }

    fn drop_fighter(&mut self, player_id: Uuid) -> Option<Uuid> {
        let client_id = self.live_client.get(&player_id).copied();
        if let Some(client_id) = client_id {
            self.client_to_player.remove(&client_id);
        }
        self.resume.forget(player_id);
        if self
            .state
            .players
            .iter()
            .any(|player| player.id == player_id)
        {
            self.remove_pawn(player_id);
        }
        client_id
    }

    pub(crate) fn remember_peer(&mut self, client_id: Uuid, peer: SocketAddr) {
        let peer = SocketAddr::new(peer.ip().to_canonical(), peer.port());
        self.pending_peers.insert(client_id, peer);
    }

    pub(crate) fn take_pending_peer(&mut self, client_id: Uuid) -> Option<SocketAddr> {
        self.pending_peers.remove(&client_id)
    }
}

fn close_or_text(client_id: Option<Uuid>, banned: bool, text: String) -> DeskOutcome {
    match client_id {
        Some(client_id) => DeskOutcome::Close {
            client_id,
            banned,
            text,
        },
        None => DeskOutcome::Text(text),
    }
}

fn missing_or_many(name: &str, seats: &[SeatHit]) -> DeskOutcome {
    let count = seats.iter().filter(|hit| hit.name == name).count();
    if count > 1 {
        DeskOutcome::Text("That name is on more than one seat.".into())
    } else {
        DeskOutcome::Text(format!("Nobody here is called {}.", clean_query(name)))
    }
}

fn clean_query(name: &str) -> String {
    let cleaned: String = name.chars().filter(|c| !c.is_control()).take(48).collect();
    let cleaned = cleaned.trim();
    if cleaned.is_empty() {
        "that".to_string()
    } else {
        cleaned.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::net::GameCommand;
    use crate::protocol::BodyKind;
    use std::net::Ipv4Addr;

    fn peer(last: u8) -> SocketAddr {
        SocketAddr::from((Ipv4Addr::new(203, 0, 113, last), 40000))
    }

    fn sit(session: &mut GameSession, name: &str, role: Role, address: SocketAddr) -> (Uuid, Uuid) {
        let client_id = Uuid::new_v4();
        let player_id = Uuid::new_v4();
        session.apply_command(GameCommand::NoteSeat {
            client_id,
            peer: address,
        });
        session.apply_command(GameCommand::Connected {
            id: client_id,
            role,
            name: name.to_string(),
            player_id: Some(player_id),
            body: BodyKind::Human,
        });
        (client_id, player_id)
    }

    #[test]
    fn who_lists_the_room_and_the_public_status_does_not() {
        let mut session = GameSession::new();
        session.spawn_bots(1);
        sit(&mut session, "Patch", Role::Human, peer(7));
        let client_id = Uuid::new_v4();
        session.apply_command(GameCommand::NoteSeat {
            client_id,
            peer: peer(9),
        });
        session.apply_command(GameCommand::Connected {
            id: client_id,
            role: Role::Spectator,
            name: "Booth".into(),
            player_id: None,
            body: BodyKind::Human,
        });
        let text = session.desk(DeskVerb::Who).text().to_string();
        assert!(text.contains("Patch  human  0  203.0.113.7"), "{text}");
        assert!(text.contains("Booth  spectator  0  203.0.113.9"), "{text}");
        assert!(text.contains("Dead Air Dan  roster"), "{text}");
        let status = serde_json::to_string(&session.state.live_status(2)).unwrap();
        assert!(!status.contains("Patch"), "{status}");
        assert!(!status.contains("203.0.113"), "{status}");
        assert!(!status.contains("Booth"), "{status}");
    }

    #[test]
    fn stats_reads_the_sheet_and_leaves_the_address_off_it() {
        let mut session = GameSession::new();
        session.spawn_bots(1);
        sit(&mut session, "Meat Proxy", Role::Human, peer(7));
        let (humans, fighters) = session.state.participant_counts();
        let live = session.state.live_status(1);
        assert_eq!(humans as usize, live.humans);
        assert_eq!(fighters as usize, live.fighters);
        session.state.start_round();
        session.state.end_round("Frag limit reached".into());
        let messages = session.tick_messages(0.05);
        assert!(messages.iter().any(|message| {
            matches!(
                message,
                crate::protocol::ServerMessage::Event(crate::protocol::GameEvent::RoundEnd { .. })
            )
        }));
        let text = session.desk(DeskVerb::Stats).text().to_string();
        assert!(text.contains("rounds 1"), "{text}");
        assert!(text.contains("peak humans 1"), "{text}");
        assert!(text.contains("peak fighters 2"), "{text}");
        assert!(text.contains("1  Arena Duel"), "{text}");
        assert!(text.contains("ffa"), "{text}");
        assert!(text.contains("Dead Air Dan"), "{text}");
        assert!(!text.contains("203.0.113"), "{text}");
        let public = serde_json::to_string(&session.sheet.totals()).unwrap();
        assert!(!public.contains("Dead"), "{public}");
        assert!(!public.contains("Meat"), "{public}");
        assert!(!public.contains("203.0.113"), "{public}");
        assert!(!public.contains("mvp"), "{public}");
    }

    #[test]
    fn kick_removes_a_live_fighter_and_refuses_the_card() {
        let mut session = GameSession::new();
        session.spawn_bots(1);
        let (client_id, player_id) = sit(&mut session, "Patch", Role::Human, peer(7));
        let token = session.resume.arm(player_id, Role::Human);
        assert!(session.resume.holds(player_id), "the pawn can still resume");
        let outcome = session.desk(DeskVerb::Kick {
            name: "Patch".into(),
        });
        match outcome {
            DeskOutcome::Close {
                client_id: closed,
                banned,
                text,
            } => {
                assert_eq!(closed, client_id);
                assert!(!banned);
                assert_eq!(text, "Patch is off the floor.");
            }
            other => panic!("expected a close: {other:?}"),
        }
        assert!(session
            .state
            .players
            .iter()
            .all(|player| player.name != "Patch"));
        assert!(
            !session.resume.holds(player_id),
            "a kick must not leave a resume token: {token}"
        );
        assert!(matches!(
            session.desk(DeskVerb::Kick {
                name: "Patch".into(),
            }),
            DeskOutcome::Text(text) if text.contains("Nobody here")
        ));
        let roster = session.desk(DeskVerb::Kick {
            name: "Dead Air Dan".into(),
        });
        assert!(
            matches!(roster, DeskOutcome::Text(ref text) if text.contains("on the card")),
            "{roster:?}"
        );
        assert!(session
            .state
            .players
            .iter()
            .any(|player| player.name == "Dead Air Dan"));
    }

    #[test]
    fn a_duplicate_name_is_not_kicked_at_all() {
        let mut session = GameSession::new();
        let first = Uuid::new_v4();
        let second = Uuid::new_v4();
        session.spectators.insert(
            first,
            super::super::SpectatorSeat {
                name: "Same".into(),
                peer: Some(peer(1)),
            },
        );
        session.spectators.insert(
            second,
            super::super::SpectatorSeat {
                name: "Same".into(),
                peer: Some(peer(2)),
            },
        );
        let outcome = session.desk(DeskVerb::Kick {
            name: "Same".into(),
        });
        assert!(
            matches!(outcome, DeskOutcome::Text(ref text) if text.contains("more than one")),
            "{outcome:?}"
        );
        assert_eq!(session.spectators.len(), 2);
    }

    #[test]
    fn ban_resolves_one_address_and_finish_drops_them() {
        let mut session = GameSession::new();
        let (client_id, _) = sit(&mut session, "Patch #2", Role::Agent, peer(8));
        let ready = match session.desk(DeskVerb::PrepareBan {
            query: "Patch #2 camping the rail".into(),
        }) {
            DeskOutcome::BanReady(ready) => ready,
            other => panic!("expected a ready ban: {other:?}"),
        };
        assert_eq!(ready.ip, IpAddr::V4(Ipv4Addr::new(203, 0, 113, 8)));
        assert_eq!(ready.reason, "camping the rail");
        assert_eq!(ready.client_id, Some(client_id));
        match session.desk(DeskVerb::FinishBan(ready)) {
            DeskOutcome::Close { banned, text, .. } => {
                assert!(banned);
                assert!(text.contains("203.0.113.8 stays out"), "{text}");
            }
            other => panic!("expected a close: {other:?}"),
        }
        assert!(session
            .state
            .players
            .iter()
            .all(|player| player.name != "Patch #2"));
    }

    #[test]
    fn finish_after_they_leave_keeps_the_ban_and_does_not_invent_a_socket() {
        let mut session = GameSession::new();
        let (client_id, player_id) = sit(&mut session, "Patch", Role::Human, peer(7));
        session.apply_command(GameCommand::Disconnected { id: client_id });
        let outcome = session.desk_finish_ban(BanReady {
            client_id: Some(client_id),
            player_id: Some(player_id),
            ip: peer(7).ip(),
            name: "Patch".into(),
            reason: "venue desk".into(),
        });
        assert!(
            matches!(outcome, DeskOutcome::Text(ref text) if text.contains("already left")),
            "{outcome:?}"
        );
    }

    #[test]
    fn a_parked_fighter_can_still_be_sent_out() {
        let mut session = GameSession::new();
        let (client_id, player_id) = sit(&mut session, "Patch", Role::Human, peer(7));
        session.apply_command(GameCommand::Detached { id: client_id });
        let text = session.desk(DeskVerb::Who).text().to_string();
        assert!(text.contains("Patch  parked  0  203.0.113.7"), "{text}");
        let outcome = session.desk(DeskVerb::Kick {
            name: "Patch".into(),
        });
        assert!(
            matches!(outcome, DeskOutcome::Text(ref text) if text.contains("off the floor")),
            "{outcome:?}"
        );
        assert!(session
            .state
            .players
            .iter()
            .all(|player| player.id != player_id));
    }

    #[test]
    fn say_is_the_venue_and_waits_before_speaking_again() {
        let mut session = GameSession::new();
        assert_eq!(
            session.desk(DeskVerb::Say {
                text: "doors at the bell".into(),
            }),
            DeskOutcome::Text("On the air.".into())
        );
        let events = session.state.take_events();
        assert!(
            matches!(
                events.last(),
                Some(GameEvent::VenueNotice { text }) if text == "The venue: doors at the bell"
            ),
            "{events:?}"
        );
        assert_eq!(
            session
                .desk(DeskVerb::Say {
                    text: "again".into(),
                })
                .text(),
            "The venue just spoke. Wait a moment."
        );
        assert!(session.state.take_events().is_empty());
        session.state.tick += VENUE_SAY_COOLDOWN_TICKS;
        assert_eq!(
            session
                .desk(DeskVerb::Say {
                    text: "  next one  ".into(),
                })
                .text(),
            "On the air."
        );
        assert_eq!(
            session.desk(DeskVerb::Say { text: "\n".into() }).text(),
            "That line does not go on the air."
        );
        let long = "x".repeat(crate::sim::SPEAK_MAX_CHARS + 1);
        assert_eq!(
            session.desk(DeskVerb::Say { text: long }).text(),
            "That line does not go on the air."
        );
    }
}
