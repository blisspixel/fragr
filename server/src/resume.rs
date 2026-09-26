//! Pawn resume. A drop is not a leave: the body stays for a short grace,
//! input is cleared, and the same id can bind a new socket. The token is
//! minted here and is not the join ticket. Clients cannot forge one.

use crate::join_ticket::{hex_decode, hex_encode, hmac_sha256, mac_equal};
use crate::protocol::Role;
use rand::RngCore;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use tokio::sync::OwnedSemaphorePermit;
use uuid::Uuid;

/// Ten seconds at 20 Hz. Long enough for a route blip, short enough that a
/// frozen body is a fight instead of a parked spawn.
pub const RESUME_GRACE_TICKS: u64 = 200;

struct Arm {
    nonce: u64,
    role: Role,
    parked: Option<Parked>,
}

struct Parked {
    deadline: u64,
    seat: Option<OwnedSemaphorePermit>,
}

pub struct ResumeAccept {
    pub player_id: Uuid,
    pub token: String,
    pub seat: Option<OwnedSemaphorePermit>,
    /// The parked pawn's body. A resume never changes it.
    pub body: crate::protocol::BodyKind,
}

pub struct ResumeTable {
    key: [u8; 32],
    tick: AtomicU64,
    arms: Mutex<HashMap<Uuid, Arm>>,
}

impl Default for ResumeTable {
    fn default() -> Self {
        Self::new()
    }
}

impl ResumeTable {
    pub fn new() -> Self {
        let mut key = [0u8; 32];
        rand::rngs::OsRng.fill_bytes(&mut key);
        Self {
            key,
            tick: AtomicU64::new(0),
            arms: Mutex::new(HashMap::new()),
        }
    }

    pub fn note_tick(&self, tick: u64) {
        self.tick.store(tick, Ordering::Relaxed);
    }

    pub fn tick(&self) -> u64 {
        self.tick.load(Ordering::Relaxed)
    }

    /// Arm a new pawn and return the token the client must keep.
    pub fn arm(&self, player: Uuid, role: Role) -> String {
        let nonce = random_nonce();
        let token = mint(&self.key, player, role, nonce);
        self.arms.lock().expect("resume table").insert(
            player,
            Arm {
                nonce,
                role,
                parked: None,
            },
        );
        token
    }

    pub fn park(&self, player: Uuid, seat: Option<OwnedSemaphorePermit>, tick: u64) {
        let mut arms = self.arms.lock().expect("resume table");
        if let Some(arm) = arms.get_mut(&player) {
            arm.parked = Some(Parked {
                deadline: tick.saturating_add(RESUME_GRACE_TICKS),
                seat,
            });
        }
    }

    pub fn forget(&self, player: Uuid) {
        self.arms.lock().expect("resume table").remove(&player);
    }

    pub fn open(&self, token: &str) -> Option<(Uuid, Role, u64)> {
        open(&self.key, token)
    }

    /// Rebind only a parked pawn. Rotates the token so the presented one dies.
    pub fn claim(&self, player: Uuid, nonce: u64, role: Role) -> Option<ResumeAccept> {
        let mut arms = self.arms.lock().expect("resume table");
        let arm = arms.get_mut(&player)?;
        if arm.role != role || arm.nonce != nonce || arm.parked.is_none() {
            return None;
        }
        let parked = arm.parked.take()?;
        let nonce = random_nonce();
        arm.nonce = nonce;
        let token = mint(&self.key, player, role, nonce);
        Some(ResumeAccept {
            player_id: player,
            token,
            seat: parked.seat,
            body: crate::protocol::BodyKind::default(),
        })
    }

    /// Pawns whose grace ended. Their seats drop with the record.
    pub fn expire(&self, tick: u64) -> Vec<Uuid> {
        let mut arms = self.arms.lock().expect("resume table");
        let due: Vec<Uuid> = arms
            .iter()
            .filter_map(|(id, arm)| {
                arm.parked
                    .as_ref()
                    .is_some_and(|parked| tick >= parked.deadline)
                    .then_some(*id)
            })
            .collect();
        for id in &due {
            arms.remove(id);
        }
        due
    }
}

fn random_nonce() -> u64 {
    let mut raw = [0u8; 8];
    rand::rngs::OsRng.fill_bytes(&mut raw);
    u64::from_le_bytes(raw) | 1
}

fn mint(key: &[u8], player: Uuid, role: Role, nonce: u64) -> String {
    let role_name = role_name(role);
    let mac = hmac_sha256(key, payload(player, role_name, nonce).as_bytes());
    format!("v1.{player}.{role_name}.{nonce}.{}", hex_encode(&mac))
}

fn open(key: &[u8], token: &str) -> Option<(Uuid, Role, u64)> {
    let mut parts = token.split('.');
    let (version, player_text, role_text, nonce_text, mac_text, rest) = (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    );
    if rest.is_some() || version != Some("v1") {
        return None;
    }
    let player = Uuid::parse_str(player_text?).ok()?;
    let role = match role_text? {
        "human" => Role::Human,
        "agent" => Role::Agent,
        _ => return None,
    };
    let nonce = nonce_text?.parse::<u64>().ok()?;
    let mac = hex_decode(mac_text?).ok()?;
    if mac.len() != 32 {
        return None;
    }
    let expect = hmac_sha256(key, payload(player, role_name(role), nonce).as_bytes());
    mac_equal(&mac, &expect).then_some((player, role, nonce))
}

fn payload(player: Uuid, role: &str, nonce: u64) -> String {
    format!("fragr-resume-v1\n{player}\n{role}\n{nonce}")
}

fn role_name(role: Role) -> &'static str {
    match role {
        Role::Human => "human",
        Role::Agent => "agent",
        Role::Spectator => "spectator",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_parked_pawn_resumes_once_and_then_the_old_token_dies() {
        let table = ResumeTable::new();
        let player = Uuid::new_v4();
        let token = table.arm(player, Role::Human);
        let (_, _, nonce) = table.open(&token).unwrap();
        assert!(table.claim(player, nonce, Role::Human).is_none());
        table.park(player, None, 10);
        let accepted = table.claim(player, nonce, Role::Human).unwrap();
        assert!(table.open(&accepted.token).is_some());
        assert!(table.claim(player, nonce, Role::Human).is_none());
        assert!(table.open(&token).is_some());
        table.park(player, None, 10);
        assert!(table.claim(player, nonce, Role::Human).is_none());
    }

    #[test]
    fn grace_ends_on_the_tick_and_a_forged_mac_never_opens() {
        let table = ResumeTable::new();
        let player = Uuid::new_v4();
        let token = table.arm(player, Role::Agent);
        table.park(player, None, 0);
        assert!(table.expire(RESUME_GRACE_TICKS - 1).is_empty());
        assert_eq!(table.expire(RESUME_GRACE_TICKS), vec![player]);
        assert!(table.open(&token).is_some());
        let mut forged = token.into_bytes();
        let last = forged.len() - 1;
        forged[last] = if forged[last] == b'0' { b'1' } else { b'0' };
        let forged = String::from_utf8(forged).unwrap();
        assert!(table.open(&forged).is_none());
        table.forget(player);
        assert!(table.claim(player, 1, Role::Agent).is_none());
    }

    #[test]
    fn detach_keeps_the_pawn_and_grace_expiry_is_a_real_leave() {
        use crate::net::GameCommand;
        use crate::protocol::{Action, CampaignRunStatus};
        use crate::session::GameSession;

        let mut session = GameSession::new();
        let client = Uuid::new_v4();
        let player = Uuid::new_v4();
        session.apply_command(GameCommand::Connected {
            body: crate::protocol::BodyKind::Human,
            id: client,
            role: Role::Human,
            name: "Patch".into(),
            player_id: Some(player),
        });
        session.apply_command(GameCommand::Action {
            player_id: player,
            action: Action {
                fire: true,
                ..Action::default()
            },
        });
        let token = session.resume.arm(player, Role::Human);
        let (_, _, nonce) = session.resume.open(&token).unwrap();
        session.resume.park(player, None, 0);
        session.apply_command(GameCommand::Detached { id: client });
        assert_eq!(session.state.players.len(), 1);
        assert!(session.client_to_player.is_empty());
        assert!(!session.state.players[0].pending_action.fire);
        assert!(session
            .state
            .take_events()
            .iter()
            .all(|event| { !matches!(event, crate::protocol::GameEvent::PlayerLeft { .. }) }));

        let next = Uuid::new_v4();
        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
        session.apply_command(GameCommand::Resume {
            client_id: next,
            player_id: player,
            nonce,
            role: Role::Human,
            reply: reply_tx,
        });
        let accepted = reply_rx.blocking_recv().unwrap().unwrap();
        assert_eq!(accepted.player_id, player);
        assert_eq!(session.client_to_player.get(&next), Some(&player));
        assert_eq!(session.state.players.len(), 1);
        assert!(session
            .take_unicasts()
            .iter()
            .any(|(_, message)| matches!(message, crate::protocol::ServerMessage::MapInfo { .. })));

        let mut campaign = GameSession::with_authored_map(
            crate::maps::AuthoredSource::Mission(crate::protocol::MissionId::RecallNotice)
                .load()
                .unwrap(),
        );
        campaign.state.enable_campaign_run().unwrap();
        let owner_client = Uuid::new_v4();
        let owner = Uuid::new_v4();
        campaign.apply_command(GameCommand::Connected {
            body: crate::protocol::BodyKind::Human,
            id: owner_client,
            role: Role::Human,
            name: "Owner".into(),
            player_id: Some(owner),
        });
        campaign.resume.arm(owner, Role::Human);
        campaign.resume.park(owner, None, 0);
        campaign.apply_command(GameCommand::Detached { id: owner_client });
        assert_eq!(
            campaign.state.mission_state().unwrap().run.unwrap().status,
            CampaignRunStatus::Playing
        );
        let expired = campaign.resume.expire(RESUME_GRACE_TICKS);
        assert_eq!(expired, vec![owner]);
        campaign.drop_expired_pawn(owner);
        campaign.tick_messages(0.05);
        assert_eq!(
            campaign.state.mission_state().unwrap().run.unwrap().status,
            CampaignRunStatus::Abandoned
        );
    }
}
