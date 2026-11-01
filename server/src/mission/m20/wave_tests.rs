//! The pier hold's wave breaks: a cleared wave breathes before the next and
//! a checkpoint lands in the breath; a straggler cannot stall the hold.
use super::tests::{clear_enemies, place, reach_quay, session_run, tick};
use super::*;
use crate::protocol::Role;
use crate::session::GameSession;

fn waves(s: &GameSession) -> Vec<WaveBreak> {
    s.state
        .mission
        .as_ref()
        .unwrap()
        .m20
        .as_ref()
        .unwrap()
        .wave_breaks
        .clone()
}

fn hold_feet(s: &GameSession) -> [f32; 3] {
    let g = s.state.map.m20_geometry().unwrap();
    match g.objectives[3].action {
        MissionObjectiveAction::Arrival { feet, .. } => feet,
        _ => panic!("arrival expected"),
    }
}

/// One tick on the pier, kept standing: the hold's danger is measured by its
/// schedule here, not by the fixture's aim.
fn stand(s: &mut GameSession, id: Uuid) {
    let feet = hold_feet(s);
    place(s, id, feet);
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.hp = 100;
    tick(s);
}

#[test]
fn canonical_hold_breaks_four_times_between_its_waves() {
    let (s, _) = session_run(CampaignDifficulty::Standard, Role::Agent, true);
    let prepared = s.state.map.m20_objectives().unwrap();
    assert_eq!(prepared.breaks, vec![2_400, 4_600, 6_800, 9_200]);
    // Each break opens a wave, and no stretch of the hold between two saves
    // can exceed three minutes even with every break's bounded wait.
    let hold = prepared.geometry.hold_ticks;
    let mut edges = vec![0];
    edges.extend(prepared.breaks.iter().copied());
    edges.push(hold);
    for pair in edges.windows(2) {
        assert!(
            pair[1] - pair[0] + BREAK_LIMIT + BREAK_BREATH <= 3 * 60 * 20,
            "{pair:?}"
        );
    }
}

#[test]
fn a_cleared_wave_breathes_before_the_next_and_a_checkpoint_lands_in_the_breath() {
    let (mut s, id) = session_run(CampaignDifficulty::Standard, Role::Human, true);
    let reached = reach_quay(&mut s, id);
    let (start, _, _) = s.state.map.m20_geometry().unwrap().clock(reached);
    let prepared = s.state.map.m20_objectives().unwrap().clone();
    let first = prepared.breaks[0];
    let next: Vec<usize> = prepared
        .pressure
        .iter()
        .filter(|slot| slot.at >= first && slot.at < prepared.breaks[1])
        .map(|slot| slot.group)
        .collect();
    // Nobody fights back: the first wave still stands when its break comes.
    while s.state.tick < start + first + 40 {
        stand(&mut s, id);
    }
    assert!(!waves(&s)[0].released, "the next wave waits on the last");
    assert!(next.iter().all(|g| !s.state.encounters.is_awake(*g)));
    // Bring the wave down, including any group still deferred by the cap.
    while waves(&s)[0].cleared_at.is_none() {
        clear_enemies(&mut s);
        stand(&mut s, id);
        assert!(
            s.state.tick < start + first + BREAK_LIMIT,
            "the wave clears"
        );
    }
    let cleared = waves(&s)[0].cleared_at.unwrap();
    while s.state.tick < cleared + BREAK_BREATH {
        assert!(!waves(&s)[0].released, "a breath before the next wave");
        stand(&mut s, id);
    }
    stand(&mut s, id);
    assert!(
        waves(&s)[0].released,
        "the next wave walks in after the breath"
    );
    assert!(
        s.state
            .campaign_checkpoint_ticks()
            .iter()
            .any(|at| (cleared..=cleared + BREAK_BREATH).contains(at)),
        "a checkpoint lands in the breath: {:?} after {cleared}",
        s.state.campaign_checkpoint_ticks()
    );
    assert!(!waves(&s)[1].released, "later breaks stay closed");
}

#[test]
fn a_straggler_cannot_hold_the_next_wave_past_the_bounded_wait() {
    let (mut s, id) = session_run(CampaignDifficulty::Standard, Role::Human, true);
    let reached = reach_quay(&mut s, id);
    let (start, _, _) = s.state.map.m20_geometry().unwrap().clock(reached);
    let first = s.state.map.m20_objectives().unwrap().breaks[0];
    let due = start + first;
    while s.state.tick < due + BREAK_LIMIT - 1 {
        stand(&mut s, id);
        assert!(!waves(&s)[0].released, "released early at {}", s.state.tick);
    }
    assert!(
        waves(&s)[0].cleared_at.is_none(),
        "the first wave still stands"
    );
    stand(&mut s, id);
    stand(&mut s, id);
    assert!(
        waves(&s)[0].released,
        "the bounded wait lets the next wave in"
    );
}

#[test]
fn a_checkpoint_keeps_each_break_and_resumes_its_clear_time() {
    let map = crate::maps::RuntimeMap::Authored(super::tests::map());
    let mut p = M20Progress::new(map.m20_objectives().unwrap());
    p.wave_breaks[0] = WaveBreak {
        cleared_at: Some(100),
        released: true,
    };
    p.shift_ticks(40);
    assert_eq!(p.wave_breaks[0].cleared_at, Some(140));
    assert!(p.wave_breaks[1].cleared_at.is_none());
}
