//! Bounded last-seen search for the guided survey, after perception and its
//! reaction delay. Remember at most 64 hostile identities for less than 30s.
//! A missing target leaves its observed feet unchanged: no hidden-pose update,
//! extrapolation, injected actor or firing instruction. The caller routes to
//! the returned coordinate through the existing ordinary movement controller.
//! This is an explicit survey memory model. The server's private arcade
//! `sim::bot_senses` remains its separate runtime owner with its own timings.
use fragr_server::protocol::{PlayerState, Snapshot};
use fragr_server::sim::PLAYER_FLOOR_Y;
use std::collections::BTreeMap;
use uuid::Uuid;

const MEMORY_TICKS: u64 = 600;
const MAX_IDENTITIES: usize = 64;
const REACHED: f32 = 0.8;

#[derive(Default)]
pub(super) struct Search {
    seen: BTreeMap<Uuid, Observation>,
    owner: Option<Uuid>,
    last_tick: Option<u64>,
}

struct Observation {
    feet: [f32; 3],
    tick: u64,
}

fn feet(player: &PlayerState) -> [f32; 3] {
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

fn distance_squared(from: [f32; 3], to: [f32; 3]) -> f32 {
    from.into_iter()
        .zip(to)
        .map(|(a, b)| (a - b) * (a - b))
        .sum()
}

impl Search {
    /// `snapshot` must contain only delayed perceived actors. An observed
    /// corpse and the viewer's own public kill confirmation retire a memory;
    /// unrelated shot results never reveal an unseen actor's fate.
    fn retire(&mut self, snapshot: &Snapshot, id: Uuid) {
        if self.owner != Some(id) || self.last_tick.is_some_and(|tick| snapshot.tick < tick) {
            self.seen.clear();
        }
        self.owner = Some(id);
        self.last_tick = Some(snapshot.tick);
        self.seen.retain(|target, memory| {
            snapshot.tick.saturating_sub(memory.tick) < MEMORY_TICKS
                && !snapshot
                    .players
                    .iter()
                    .any(|p| p.id == *target && p.hp <= 0)
                && !snapshot.shot_results.iter().any(|shot| {
                    shot.shooter_id == id && shot.killed && shot.target_id == Some(*target)
                })
        });
    }

    pub(super) fn observe(&mut self, snapshot: &Snapshot, id: Uuid) {
        self.retire(snapshot, id);
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            self.seen.clear();
            return;
        };
        for target in &snapshot.players {
            let at = feet(target);
            if !me.is_hostile_to(target) {
                self.seen.remove(&target.id);
            } else if at.iter().all(|value| value.is_finite())
                && !snapshot.shot_results.iter().any(|shot| {
                    shot.shooter_id == id && shot.killed && shot.target_id == Some(target.id)
                })
            {
                self.seen.insert(
                    target.id,
                    Observation {
                        feet: at,
                        tick: snapshot.tick,
                    },
                );
            }
        }
        while self.seen.len() > MAX_IDENTITIES {
            // Evict the oldest; ties retire the lowest identity. The retained
            // set therefore does not depend on snapshot row ordering.
            let oldest = self
                .seen
                .iter()
                .min_by_key(|(id, memory)| (memory.tick, **id))
                .map(|(id, _)| *id)
                .unwrap();
            self.seen.remove(&oldest);
        }
    }

    /// Prefer the closest unseen memory, then the newest observation, then
    /// lowest identity. Reaching a remembered point ends that search even if
    /// the target never reappears; repeated reads cannot rediscover it.
    pub(super) fn destination(
        &mut self,
        me: &PlayerState,
        snapshot: &Snapshot,
    ) -> Option<[f32; 3]> {
        self.retire(snapshot, me.id);
        let from = feet(me);
        if me.hp <= 0 || !from.iter().all(|value| value.is_finite()) {
            self.seen.clear();
            return None;
        }
        self.seen
            .retain(|_, memory| distance_squared(from, memory.feet) >= REACHED * REACHED);
        self.seen
            .iter()
            .filter(|(id, _)| {
                !snapshot
                    .players
                    .iter()
                    .any(|p| p.id == **id && me.is_hostile_to(p))
            })
            .min_by(|(a_id, a), (b_id, b)| {
                distance_squared(from, a.feet)
                    .total_cmp(&distance_squared(from, b.feet))
                    .then_with(|| b.tick.cmp(&a.tick))
                    .then_with(|| a_id.cmp(b_id))
            })
            .map(|(_, memory)| memory.feet)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::campaign::{Perception, PROFILES};
    use fragr_server::movement::Arena;
    use fragr_server::protocol::{Role, ShotResult};
    use fragr_server::session::GameSession;

    fn scene() -> (Snapshot, Arena, Uuid, Uuid) {
        // Isolated observation fixture, not an earned campaign route.
        let mut session = GameSession::new();
        let id = Uuid::from_u128(1);
        let target = Uuid::from_u128(2);
        session.state.add_player(id, "Viewer".into(), Role::Human);
        session
            .state
            .add_player(target, "Seen guard".into(), Role::Agent);
        let mut snapshot = session.state.snapshot();
        for player in &mut snapshot.players {
            player.x = if player.id == id { 0.0 } else { 10.0 };
            player.y = PLAYER_FLOOR_Y;
            player.z = 0.0;
            player.yaw = 0.0;
            player.pitch = 0.0;
        }
        (
            snapshot,
            Arena {
                half: 64.0,
                solids: Vec::new(),
            },
            id,
            target,
        )
    }

    fn hidden(snapshot: &Snapshot, id: Uuid, tick: u64) -> Snapshot {
        let mut view = snapshot.clone();
        view.players.retain(|p| p.id == id);
        view.tick = tick;
        view
    }

    fn destination(search: &mut Search, view: &Snapshot, id: Uuid) -> Option<[f32; 3]> {
        let me = view.players.iter().find(|p| p.id == id).unwrap();
        search.destination(me, view)
    }

    fn shot(shooter: Uuid, target: Uuid, killed: bool) -> ShotResult {
        ShotResult {
            shooter_id: shooter,
            shooter: "Fixture".into(),
            hit: true,
            target_id: Some(target),
            target: Some("Seen guard".into()),
            damage: 10,
            target_hp_after: Some(if killed { 0 } else { 70 }),
            trace: None,
            killed,
        }
    }

    #[test]
    fn no_observation_or_unelapsed_reaction_produces_no_search_goal() {
        let (mut snapshot, arena, id, target) = scene();
        let mut search = Search::default();
        let empty = hidden(&snapshot, id, 0);
        search.observe(&empty, id);
        assert_eq!(destination(&mut search, &empty, id), None);
        let mut vision = Perception::default();
        for tick in 0..PROFILES[1].reaction_ticks {
            snapshot.tick = tick;
            let observed = vision.observe(&snapshot, id, &arena, PROFILES[1]);
            assert!(!observed.players.iter().any(|p| p.id == target));
            search.observe(&observed, id);
            assert_eq!(destination(&mut search, &observed, id), None);
        }
        snapshot.tick = PROFILES[1].reaction_ticks;
        let observed = vision.observe(&snapshot, id, &arena, PROFILES[1]);
        assert!(observed.players.iter().any(|p| p.id == target));
        search.observe(&observed, id);
        assert_eq!(
            destination(&mut search, &observed, id),
            None,
            "visible targets stay with combat"
        );
        snapshot.tick += 1;
        snapshot
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap()
            .x = -20.0;
        let observed = vision.observe(&snapshot, id, &arena, PROFILES[1]);
        search.observe(&observed, id);
        assert_eq!(
            destination(&mut search, &observed, id),
            Some([10.0, 0.0, 0.0])
        );
    }

    #[test]
    fn hidden_movement_cannot_update_the_remembered_coordinate() {
        let (mut snapshot, arena, id, target) = scene();
        let mut vision = Perception::default();
        let mut search = Search::default();
        let observed = vision.observe(&snapshot, id, &arena, PROFILES[0]);
        search.observe(&observed, id);
        for (tick, x) in [(1, -20.0), (2, -35.0), (3, 55.0)] {
            snapshot.tick = tick;
            snapshot
                .players
                .iter_mut()
                .find(|p| p.id == target)
                .unwrap()
                .x = x;
            let observed = vision.observe(&snapshot, id, &arena, PROFILES[0]);
            search.observe(&observed, id);
            assert_eq!(
                destination(&mut search, &observed, id),
                Some([10.0, 0.0, 0.0])
            );
        }
        snapshot.tick = 4;
        snapshot
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap()
            .x = 12.0;
        let observed = vision.observe(&snapshot, id, &arena, PROFILES[0]);
        search.observe(&observed, id);
        let hidden = hidden(&snapshot, id, 5);
        search.observe(&hidden, id);
        assert_eq!(
            destination(&mut search, &hidden, id),
            Some([12.0, 0.0, 0.0])
        );
    }

    #[test]
    fn memory_expires_at_thirty_seconds_and_rewind_forgets_the_previous_clock() {
        let (snapshot, _, id, _) = scene();
        let mut search = Search::default();
        search.observe(&snapshot, id);
        assert_eq!(
            destination(&mut search, &hidden(&snapshot, id, 599), id),
            Some([10.0, 0.0, 0.0])
        );
        assert_eq!(
            destination(&mut search, &hidden(&snapshot, id, 600), id),
            None
        );
        let mut later = snapshot.clone();
        later.tick = 700;
        search.observe(&later, id);
        assert_eq!(
            destination(&mut search, &hidden(&snapshot, id, 701), id),
            Some([10.0, 0.0, 0.0])
        );
        search.observe(&hidden(&snapshot, id, 2), id);
        assert_eq!(
            destination(&mut search, &hidden(&snapshot, id, 2), id),
            None
        );
    }

    #[test]
    fn observed_death_and_own_kill_retire_memory_but_unrelated_feedback_does_not() {
        let (snapshot, _, id, target) = scene();
        for cause in ["observed_death", "own_kill", "other_kill", "own_hit"] {
            let mut search = Search::default();
            search.observe(&snapshot, id);
            let mut next = hidden(&snapshot, id, 1);
            match cause {
                "observed_death" => {
                    let mut dead = snapshot
                        .players
                        .iter()
                        .find(|p| p.id == target)
                        .unwrap()
                        .clone();
                    dead.hp = 0;
                    next.players.push(dead);
                }
                "other_kill" => next
                    .shot_results
                    .push(shot(Uuid::from_u128(3), target, true)),
                _ => next
                    .shot_results
                    .push(shot(id, target, cause == "own_kill")),
            }
            search.observe(&next, id);
            assert_eq!(
                destination(&mut search, &next, id).is_none(),
                matches!(cause, "observed_death" | "own_kill"),
                "{cause}"
            );
        }
        // Even a stale alive row cannot immediately undo our own kill receipt.
        let mut stale = snapshot.clone();
        stale.shot_results.push(shot(id, target, true));
        let mut search = Search::default();
        search.observe(&stale, id);
        assert!(search.seen.is_empty());
    }

    #[test]
    fn reached_points_retire_without_same_tick_rediscovery_and_respect_height() {
        let (snapshot, _, id, _) = scene();
        let mut search = Search::default();
        search.observe(&snapshot, id);
        let mut next = hidden(&snapshot, id, 1);
        next.players[0].x = 10.0;
        next.players[0].y += 4.5;
        assert_eq!(
            destination(&mut search, &next, id),
            Some([10.0, 0.0, 0.0]),
            "another floor has not reached the point"
        );
        next.players[0].y = PLAYER_FLOOR_Y;
        next.players[0].x = 9.3;
        assert_eq!(destination(&mut search, &next, id), None);
        next.players[0].x = 0.0;
        search.observe(&next, id);
        assert_eq!(destination(&mut search, &next, id), None);
        assert_eq!(destination(&mut search, &next, id), None);
    }

    #[test]
    fn selection_is_closest_then_newest_then_identity() {
        let (snapshot, _, id, target) = scene();
        let mut search = Search::default();
        search.observe(&snapshot, id);
        let mut next = hidden(&snapshot, id, 1);
        for (identity, x, z) in [(3, -10.0, 0.0), (4, 0.0, 10.0)] {
            let mut guard = snapshot
                .players
                .iter()
                .find(|p| p.id == target)
                .unwrap()
                .clone();
            guard.id = Uuid::from_u128(identity);
            guard.x = x;
            guard.z = z;
            next.players.push(guard);
        }
        search.observe(&next, id);
        let mut hidden = hidden(&snapshot, id, 2);
        assert_eq!(
            destination(&mut search, &hidden, id),
            Some([-10.0, 0.0, 0.0]),
            "newest wins equal distance, then lower identity"
        );
        hidden.players[0].x = 6.0;
        assert_eq!(
            destination(&mut search, &hidden, id),
            Some([10.0, 0.0, 0.0]),
            "distance outranks freshness"
        );
    }

    #[test]
    fn memory_capacity_and_eviction_do_not_depend_on_row_order() {
        let (snapshot, _, id, target) = scene();
        let mut many = hidden(&snapshot, id, 0);
        for identity in 100..165 {
            let mut guard = snapshot
                .players
                .iter()
                .find(|p| p.id == target)
                .unwrap()
                .clone();
            guard.id = Uuid::from_u128(identity);
            many.players.push(guard);
        }
        let mut forward = Search::default();
        forward.observe(&many, id);
        many.players.reverse();
        let mut reverse = Search::default();
        reverse.observe(&many, id);
        assert_eq!(forward.seen.len(), MAX_IDENTITIES);
        assert_eq!(
            forward.seen.keys().collect::<Vec<_>>(),
            reverse.seen.keys().collect::<Vec<_>>()
        );
        assert!(!forward.seen.contains_key(&Uuid::from_u128(100)));
        let mut fresh = snapshot.clone();
        fresh.tick = 1;
        forward.observe(&fresh, id);
        assert_eq!(forward.seen.len(), MAX_IDENTITIES);
        assert!(forward.seen.contains_key(&target));
        assert!(!forward.seen.contains_key(&Uuid::from_u128(101)));
    }

    #[test]
    fn owner_loss_death_or_invalid_positions_do_not_produce_search_destinations() {
        let (snapshot, _, id, target) = scene();
        for missing in [false, true] {
            let mut search = Search::default();
            search.observe(&snapshot, id);
            let mut next = hidden(&snapshot, id, 1);
            if missing {
                next.players.clear();
            } else {
                next.players[0].hp = 0;
            }
            search.observe(&next, id);
            assert!(search.seen.is_empty());
        }
        let mut invalid = snapshot.clone();
        invalid
            .players
            .iter_mut()
            .find(|p| p.id == target)
            .unwrap()
            .x = f32::NAN;
        let mut search = Search::default();
        search.observe(&invalid, id);
        assert!(search.seen.is_empty());
        search.observe(&snapshot, id);
        let mut next = hidden(&snapshot, id, 1);
        next.players[0].id = Uuid::from_u128(99);
        assert_eq!(
            search.destination(&next.players[0], &next),
            None,
            "a new viewer inherits no memory"
        );
    }
}
