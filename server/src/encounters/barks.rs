//! Campaign chatter on one spaced channel: Union squad radio and Latch's
//! callouts. Rare by construction: a Union line waits five seconds after any
//! line, one kind repeats at most every twenty, and each fact is offered
//! once. Latch outranks the radio: a callout waits five seconds after
//! Latch's last one but may cut across a Union line, because a warning about
//! a gun behind the participant is worth more than the gun's own chatter.
//! The client owns the words, captions and recordings.

use crate::protocol::{
    BarkRegister, CampaignActor, CompanionBarkKind, CompanionKind, CompanionPhase, ControlDomain,
    EnemyBarkKind, EnemyKind, GameEvent, BARK_VARIANTS,
};
use crate::sim::{GameState, Player, PLAYER_FLOOR_Y};
use std::collections::HashMap;
use uuid::Uuid;

/// Ticks between any two lines on the channel (5 s).
pub(crate) const BARK_GAP: u64 = 100;
/// Ticks between two lines of one kind (20 s).
pub(crate) const KIND_GAP: u64 = 400;
/// Ticks between two low-health warnings (30 s).
pub(crate) const LOW_HEALTH_GAP: u64 = 600;
/// A participant falling below this much health hears Latch.
pub(crate) const LOW_HEALTH: i32 = 35;
/// A raised gun this far from a participant, outside their front, is a flank.
pub(crate) const FLANK_WARNING_RANGE: f32 = 24.0;
/// Bearing from a participant's facing beyond which a gun is behind them.
pub(crate) const BEHIND: f32 = std::f32::consts::FRAC_PI_2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum Slot {
    Enemy(EnemyBarkKind, BarkRegister),
    Companion(CompanionBarkKind, Option<EnemyKind>),
}

impl Slot {
    fn gap(self) -> u64 {
        match self {
            Slot::Companion(CompanionBarkKind::LowHealth, _) => LOW_HEALTH_GAP,
            _ => KIND_GAP,
        }
    }

    /// Kinds share their spacing across registers and subjects, so a
    /// sighting from a Clerk and one from a Sweeper do not stack.
    fn family(self) -> Slot {
        match self {
            Slot::Enemy(kind, _) => Slot::Enemy(kind, BarkRegister::Personnel),
            Slot::Companion(kind, _) => Slot::Companion(kind, None),
        }
    }
}

#[derive(Debug, Default)]
pub(crate) struct Barks {
    last_line: Option<u64>,
    last_companion: Option<u64>,
    last_of: HashMap<Slot, u64>,
    turns: HashMap<Slot, u8>,
    health: HashMap<Uuid, i32>,
}

/// Who speaks for a Union body, if anyone. Human personnel give short
/// orders; issued units recite boilerplate. Equipment, Inheritance machines
/// and absorbed bots say nothing.
pub(crate) fn register(kind: EnemyKind, control: ControlDomain) -> Option<BarkRegister> {
    if control != ControlDomain::Union {
        return None;
    }
    match kind {
        EnemyKind::Clerk | EnemyKind::Auditor | EnemyKind::Enforcer | EnemyKind::Redactor => {
            Some(BarkRegister::Personnel)
        }
        EnemyKind::Sweeper | EnemyKind::HeavySweeper | EnemyKind::RangedSweeper => {
            Some(BarkRegister::Unit)
        }
        _ => None,
    }
}

fn feet(player: &Player) -> [f32; 3] {
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

/// Latch, alive and with the party.
fn latch(state: &GameState) -> Option<&Player> {
    state.players.iter().find(|p| {
        p.hp > 0
            && matches!(
                p.campaign,
                Some(CampaignActor::Companion {
                    kind: CompanionKind::Latch,
                    phase: CompanionPhase::Following | CompanionPhase::Firing,
                    ..
                })
            )
    })
}

impl Barks {
    pub(crate) fn reset(&mut self) {
        *self = Self::default();
    }

    /// Admit one line at `tick`, returning its variant.
    fn admit(&mut self, slot: Slot, tick: u64) -> Option<u8> {
        let spacing = match slot {
            Slot::Enemy(..) => self.last_line,
            Slot::Companion(..) => self.last_companion,
        };
        if spacing.is_some_and(|last| tick < last.saturating_add(BARK_GAP))
            || self
                .last_of
                .get(&slot.family())
                .is_some_and(|last| tick < last.saturating_add(slot.gap()))
        {
            return None;
        }
        self.last_line = Some(tick);
        if matches!(slot, Slot::Companion(..)) {
            self.last_companion = Some(tick);
        }
        self.last_of.insert(slot.family(), tick);
        let turn = self.turns.entry(slot).or_default();
        let variant = *turn;
        *turn = (*turn + 1) % BARK_VARIANTS;
        Some(variant)
    }

    /// A Union body says `kind`, if it speaks and the channel is free.
    pub(crate) fn enemy(
        &mut self,
        state: &mut GameState,
        kind: EnemyBarkKind,
        speaker: Uuid,
        speaker_kind: EnemyKind,
        control: ControlDomain,
    ) -> bool {
        let Some(register) = register(speaker_kind, control) else {
            return false;
        };
        let Some(position) = state
            .players
            .iter()
            .find(|p| p.id == speaker && p.hp > 0)
            .map(feet)
        else {
            return false;
        };
        let tick = state.tick;
        let Some(variant) = self.admit(Slot::Enemy(kind, register), tick) else {
            return false;
        };
        state.events.push(GameEvent::EnemyBark {
            kind,
            register,
            variant,
            speaker_id: speaker,
            position,
        });
        true
    }

    /// Latch says `kind`, if Latch is with the party and the channel is free.
    pub(crate) fn companion(
        &mut self,
        state: &mut GameState,
        kind: CompanionBarkKind,
        subject: Option<EnemyKind>,
    ) -> bool {
        let Some((speaker_id, position)) = latch(state).map(|p| (p.id, feet(p))) else {
            return false;
        };
        let tick = state.tick;
        let Some(variant) = self.admit(Slot::Companion(kind, subject), tick) else {
            return false;
        };
        state.events.push(GameEvent::CompanionBark {
            kind,
            subject,
            variant,
            speaker_id,
            position,
        });
        true
    }

    /// Latch's low-health warning, once per fall below the line.
    pub(crate) fn watch_health(&mut self, state: &mut GameState) {
        let fallen: Vec<Uuid> = state
            .players
            .iter()
            .filter(|p| p.campaign == Some(CampaignActor::Participant {}))
            .filter_map(|p| {
                let before = self.health.insert(p.id, p.hp).unwrap_or(p.hp);
                (p.hp > 0 && p.hp < LOW_HEALTH && before >= LOW_HEALTH).then_some(p.id)
            })
            .collect();
        if !fallen.is_empty() {
            self.companion(state, CompanionBarkKind::LowHealth, None);
        }
    }
}

/// Whether a gun at `from` is behind `participant`'s shoulder and near.
pub(crate) fn behind(participant: &Player, from: [f32; 3]) -> bool {
    let dx = from[0] - participant.x;
    let dz = from[2] - participant.z;
    dx.hypot(dz) <= FLANK_WARNING_RANGE
        && ((dz.atan2(dx) - participant.yaw + std::f32::consts::PI)
            .rem_euclid(std::f32::consts::TAU)
            - std::f32::consts::PI)
            .abs()
            > BEHIND
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Role;

    fn state_with(kinds: &[(u128, Option<CampaignActor>)]) -> GameState {
        let mut state = GameState::new();
        for (id, campaign) in kinds {
            state.add_player(Uuid::from_u128(*id), format!("p{id}"), Role::Agent);
            let player = state
                .players
                .iter_mut()
                .find(|p| p.id == Uuid::from_u128(*id))
                .unwrap();
            player.campaign = *campaign;
            player.hp = 100;
        }
        state
    }

    fn clerk() -> Option<CampaignActor> {
        Some(CampaignActor::Hostile {
            kind: EnemyKind::Clerk,
            phase: crate::protocol::EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
            control: ControlDomain::Union,
        })
    }

    fn latch_actor() -> Option<CampaignActor> {
        Some(CampaignActor::Companion {
            kind: CompanionKind::Latch,
            phase: CompanionPhase::Following,
            phase_started: 0,
        })
    }

    fn lines(state: &mut GameState) -> Vec<GameEvent> {
        std::mem::take(&mut state.events)
            .into_iter()
            .filter(|event| {
                matches!(
                    event,
                    GameEvent::EnemyBark { .. } | GameEvent::CompanionBark { .. }
                )
            })
            .collect()
    }

    #[test]
    fn the_channel_spaces_every_line_and_rotates_variants() {
        let mut state = state_with(&[(1, clerk())]);
        let speaker = Uuid::from_u128(1);
        let mut barks = Barks::default();
        let mut said = Vec::new();
        for tick in 0..2_000 {
            state.tick = tick;
            for kind in [EnemyBarkKind::Sighting, EnemyBarkKind::Flanking] {
                barks.enemy(
                    &mut state,
                    kind,
                    speaker,
                    EnemyKind::Clerk,
                    ControlDomain::Union,
                );
            }
            for event in lines(&mut state) {
                if let GameEvent::EnemyBark { kind, variant, .. } = event {
                    said.push((tick, kind, variant));
                }
            }
        }
        for pair in said.windows(2) {
            assert!(pair[1].0 - pair[0].0 >= BARK_GAP, "{said:?}");
        }
        let sightings: Vec<(u64, u8)> = said
            .iter()
            .filter(|(_, kind, _)| *kind == EnemyBarkKind::Sighting)
            .map(|(tick, _, variant)| (*tick, *variant))
            .collect();
        for pair in sightings.windows(2) {
            assert!(pair[1].0 - pair[0].0 >= KIND_GAP, "{sightings:?}");
        }
        let variants: Vec<u8> = sightings.iter().map(|(_, v)| *v).collect();
        assert_eq!(&variants[..4], &[0, 1, 2, 0]);
        // Two kinds on one channel over a hundred seconds: one line about
        // every ten seconds, never one a tick.
        assert!((8..=12).contains(&said.len()), "{}", said.len());
    }

    #[test]
    fn only_union_people_and_issued_units_speak() {
        assert_eq!(
            register(EnemyKind::Clerk, ControlDomain::Union),
            Some(BarkRegister::Personnel)
        );
        assert_eq!(
            register(EnemyKind::Auditor, ControlDomain::Union),
            Some(BarkRegister::Personnel)
        );
        assert_eq!(
            register(EnemyKind::HeavySweeper, ControlDomain::Union),
            Some(BarkRegister::Unit)
        );
        for silent in [
            EnemyKind::Turret,
            EnemyKind::Notary,
            EnemyKind::Assessor,
            EnemyKind::Jammer,
            EnemyKind::Crawler,
            EnemyKind::Paver,
            EnemyKind::Surveyor,
        ] {
            assert_eq!(register(silent, ControlDomain::Union), None, "{silent:?}");
        }
        assert_eq!(
            register(EnemyKind::Sweeper, ControlDomain::Absorbed),
            None,
            "an absorbed bot no longer answers on Union radio"
        );
        let mut state = state_with(&[(1, clerk())]);
        let mut barks = Barks::default();
        assert!(!barks.enemy(
            &mut state,
            EnemyBarkKind::Sighting,
            Uuid::from_u128(1),
            EnemyKind::Turret,
            ControlDomain::Union
        ));
        assert!(lines(&mut state).is_empty());
    }

    #[test]
    fn latch_warns_once_per_fall_below_the_line_and_only_when_present() {
        let participant = Some(CampaignActor::Participant {});
        let mut state = state_with(&[(1, participant), (2, latch_actor())]);
        let me = Uuid::from_u128(1);
        let mut barks = Barks::default();
        let mut warnings = 0;
        for (step, hp) in [100, 60, 30, 20, 10, 50, 30, 30].into_iter().enumerate() {
            state.tick = step as u64 * LOW_HEALTH_GAP;
            state.players.iter_mut().find(|p| p.id == me).unwrap().hp = hp;
            barks.watch_health(&mut state);
            warnings += lines(&mut state)
                .iter()
                .filter(|e| {
                    matches!(
                        e,
                        GameEvent::CompanionBark {
                            kind: CompanionBarkKind::LowHealth,
                            ..
                        }
                    )
                })
                .count();
        }
        assert_eq!(warnings, 2, "a fall to 30, then again after healing to 50");
        let mut alone = state_with(&[(1, participant)]);
        let mut barks = Barks::default();
        barks.watch_health(&mut alone);
        alone.players.iter_mut().find(|p| p.id == me).unwrap().hp = 10;
        barks.watch_health(&mut alone);
        assert!(
            lines(&mut alone).is_empty(),
            "without Latch nobody calls it"
        );
    }

    #[test]
    fn a_gun_behind_the_shoulder_is_a_flank_and_one_in_front_is_not() {
        let mut state = state_with(&[(1, Some(CampaignActor::Participant {}))]);
        let me = state
            .players
            .iter_mut()
            .find(|p| p.id == Uuid::from_u128(1))
            .unwrap();
        me.x = 0.0;
        me.z = 0.0;
        me.yaw = 0.0;
        let me = &*me;
        assert!(!behind(me, [10.0, 0.0, 0.0]));
        assert!(!behind(me, [5.0, 0.0, 5.0]));
        assert!(behind(me, [-10.0, 0.0, 0.0]));
        assert!(behind(me, [-3.0, 0.0, -8.0]));
        assert!(!behind(me, [-30.0, 0.0, 0.0]), "too far to matter");
    }
}
