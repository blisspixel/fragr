//! What a joined agent can know about the map's pads. The snapshot carries
//! every pad's live state and return timer for the renderer and the booth.
//! A fighter sees a pad only inside a 120 degree view, within 40 m and past
//! the map's solids, or underfoot, and remembers the published return clocks.
//! `observe` reports that belief for a joined agent, never the live timer. A
//! spectator that never joined keeps the booth's full view.
use fragr_server::movement::Solid;
use fragr_server::protocol::{PickupState, PlayerState, Snapshot, SupplyClaim};
use serde_json::Value;
use std::collections::HashMap;
use std::f32::consts::{FRAC_PI_3, PI, TAU};
use uuid::Uuid;

/// Pads further than this are remembered, not seen.
const PAD_SIGHT: f32 = 40.0;
/// A pad this close is seen whichever way the agent faces.
const UNDERFOOT: f32 = 2.5;
/// Drawn pads float this far above their surface.
const PAD_LIFT: f32 = 0.4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Belief {
    up: bool,
    /// Expected return tick from the published clock, when seen empty.
    back_at: Option<u64>,
    in_view: bool,
}

#[derive(Debug, Clone, Default)]
pub struct PadView {
    solids: Vec<Solid>,
    teams: bool,
    beliefs: HashMap<String, Belief>,
}

fn angle_difference(to: f32, from: f32) -> f32 {
    (to - from + PI).rem_euclid(TAU) - PI
}

fn sees(solids: &[Solid], me: &PlayerState, pad: &PickupState) -> bool {
    let dx = pad.x - me.x;
    let dz = pad.z - me.z;
    let distance = dx.hypot(dz);
    if !distance.is_finite() || distance > PAD_SIGHT {
        return false;
    }
    let feet = me.y - fragr_server::sim::PLAYER_FLOOR_Y;
    if distance <= UNDERFOOT && (feet - (pad.y - PAD_LIFT)).abs() <= 2.0 {
        return true;
    }
    if angle_difference(dz.atan2(dx), me.yaw).abs() > FRAC_PI_3 {
        return false;
    }
    let eye = [
        me.x,
        feet + fragr_server::combat::stance_eye(me.campaign, me.ducking),
        me.z,
    ];
    fragr_server::combat::line_of_sight(eye, [pad.x, pad.y - PAD_LIFT + 0.2, pad.z], solids)
}

impl PadView {
    /// A new map: its solids, whether weapon pads keep the team clock, and
    /// every pad believed up, as at a round start.
    pub fn reset_map(&mut self, solids: Vec<Solid>, teams: bool) {
        self.solids = solids;
        self.teams = teams;
        self.beliefs.clear();
    }

    /// A round start puts every pad back.
    pub fn reset_round(&mut self) {
        self.beliefs.clear();
    }

    /// Fold one snapshot from the joined fighter's own eyes.
    pub fn observe(&mut self, snapshot: &Snapshot, me: Option<Uuid>) {
        let me = me.and_then(|id| snapshot.players.iter().find(|p| p.id == id && p.hp > 0));
        for pad in &snapshot.pickups {
            let belief = self.beliefs.entry(pad.id.clone()).or_insert(Belief {
                up: true,
                back_at: None,
                in_view: false,
            });
            let seen = me.is_some_and(|me| sees(&self.solids, me, pad));
            belief.in_view = seen;
            if seen {
                if pad.available {
                    belief.up = true;
                    belief.back_at = None;
                } else if pad.respawn_in.is_none() {
                    // Campaign stock that is gone stays gone until the party
                    // reset; there is no clock to learn.
                    belief.up = false;
                    belief.back_at = None;
                } else {
                    let back_at = match belief.back_at {
                        Some(at) if !belief.up => at,
                        _ => snapshot
                            .tick
                            .saturating_add(u64::from(pad.clock_ticks(self.teams))),
                    };
                    belief.up = false;
                    belief.back_at = Some(back_at);
                }
            } else if belief.back_at.is_some_and(|at| snapshot.tick >= at) {
                belief.up = true;
                belief.back_at = None;
            }
        }
    }

    /// Whether the joined agent believes `pad` is up. A personal stash is the
    /// agent's own business and passes through.
    pub fn up(&self, pad: &PickupState) -> bool {
        if pad.claim == SupplyClaim::Personal {
            return pad.available;
        }
        self.beliefs.get(&pad.id).is_none_or(|belief| belief.up)
    }

    /// Rewrite a full observation's pickups to this belief: `available` is
    /// what the agent believes, `in_view` whether it can see the pad now, and
    /// the live `respawn_in` timer is removed.
    pub fn redact(&self, pickups: &mut Value) {
        let Some(rows) = pickups.as_array_mut() else {
            return;
        };
        for row in rows {
            let Some(object) = row.as_object_mut() else {
                continue;
            };
            let personal = object.get("claim").and_then(Value::as_str) == Some("personal");
            object.remove("respawn_in");
            let id = object.get("id").and_then(Value::as_str).unwrap_or_default();
            let belief = self.beliefs.get(id).copied();
            if !personal {
                object.insert(
                    "available".into(),
                    Value::Bool(belief.is_none_or(|belief| belief.up)),
                );
            }
            object.insert(
                "in_view".into(),
                Value::Bool(belief.is_some_and(|belief| belief.in_view)),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fragr_server::protocol::Role;
    use fragr_server::sim::GameState;

    fn arena() -> (GameState, Uuid) {
        let mut state = GameState::new();
        state.start_round();
        let me = Uuid::from_u128(7);
        state.add_player(me, "Agent".into(), Role::Agent);
        (state, me)
    }

    fn view_for(state: &GameState) -> PadView {
        let mut view = PadView::default();
        view.reset_map(state.map.arena().solids.clone(), false);
        view
    }

    fn stand_at(state: &mut GameState, me: Uuid, pad: usize, yaw: f32, back: f32) {
        let (x, floor, z) = (
            state.pickups[pad].x,
            state.pickups[pad].floor,
            state.pickups[pad].z,
        );
        let player = state.players.iter_mut().find(|p| p.id == me).unwrap();
        player.x = x - yaw.cos() * back;
        player.z = z - yaw.sin() * back;
        player.y = floor + fragr_server::sim::PLAYER_FLOOR_Y;
        player.yaw = yaw;
    }

    #[test]
    fn unseen_taken_pads_stay_believed_up_and_seen_ones_follow_the_clock() {
        let (mut state, me) = arena();
        let mut view = view_for(&state);
        // Facing away from the pad two metres off: underfoot reach sees it.
        stand_at(&mut state, me, 0, 0.0, 2.0);
        state.players.iter_mut().find(|p| p.id == me).unwrap().yaw = PI;
        state.pickups[0].available = false;
        state.pickups[0].respawn_timer = Some(100);
        view.observe(&state.snapshot(), Some(me));
        let pad = state.snapshot().pickups[0].clone();
        assert!(!view.up(&pad), "a pad underfoot is seen taken");
        // Walk far away facing elsewhere: the agent keeps its estimate.
        stand_at(&mut state, me, 0, 0.0, 39.0);
        state.players.iter_mut().find(|p| p.id == me).unwrap().yaw = PI;
        view.observe(&state.snapshot(), Some(me));
        assert!(!view.up(&pad));
        // The published clock runs out unseen: believed back.
        state.tick += u64::from(pad.clock_ticks(false));
        view.observe(&state.snapshot(), Some(me));
        assert!(view.up(&pad));

        // Another pad taken out of view is still believed up, and the full
        // observation hides the live timer.
        state.pickups[1].available = false;
        state.pickups[1].respawn_timer = Some(50);
        view.observe(&state.snapshot(), Some(me));
        let other = state.snapshot().pickups[1].clone();
        assert!(view.up(&other));
        let mut rows = serde_json::to_value(&state.snapshot().pickups).unwrap();
        assert!(rows[1].get("respawn_in").is_some());
        view.redact(&mut rows);
        assert_eq!(rows[1]["available"], true);
        assert_eq!(rows[1]["in_view"], false);
        assert!(rows[1].get("respawn_in").is_none());
    }

    #[test]
    fn stock_that_never_restocks_stays_gone_until_seen_again() {
        let (mut state, me) = arena();
        let mut view = view_for(&state);
        stand_at(&mut state, me, 0, 0.0, 1.0);
        state.pickups[0].available = false;
        state.pickups[0].respawn_timer = None;
        view.observe(&state.snapshot(), Some(me));
        let pad = state.snapshot().pickups[0].clone();
        assert!(!view.up(&pad));
        state.tick += 10_000;
        stand_at(&mut state, me, 0, 0.0, 39.0);
        state.players.iter_mut().find(|p| p.id == me).unwrap().yaw = PI;
        view.observe(&state.snapshot(), Some(me));
        assert!(!view.up(&pad), "no clock was published, so none runs out");
        // Restocked and seen: believed up again.
        state.pickups[0].available = true;
        stand_at(&mut state, me, 0, 0.0, 1.0);
        view.observe(&state.snapshot(), Some(me));
        assert!(view.up(&state.snapshot().pickups[0]));
    }

    #[test]
    fn a_view_cone_and_cover_limit_what_is_seen() {
        let (mut state, me) = arena();
        stand_at(&mut state, me, 0, 0.0, 6.0);
        let snapshot = state.snapshot();
        let mine = snapshot
            .players
            .iter()
            .find(|p| p.id == me)
            .unwrap()
            .clone();
        let pad = snapshot.pickups[0].clone();
        assert!(sees(&[], &mine, &pad), "an open pad ahead is seen");
        let mut away = mine.clone();
        away.yaw = PI;
        assert!(!sees(&[], &away, &pad), "a pad behind the agent is not");
        // Map 1's first pad (Larak Lot's Plate) sits on the Roof, so the wall
        // stands taller than the pad rather than at the default wall height.
        let wall = [Solid::from_center_top(
            pad.x - 3.0,
            pad.z,
            0.2,
            4.0,
            pad.y + 4.0,
        )];
        assert!(!sees(&wall, &mine, &pad), "a wall between hides the pad");
        let mut far = mine.clone();
        far.x = pad.x - 41.0;
        assert!(!sees(&[], &far, &pad), "beyond sight range");
        // A booth spectator never joined: nothing is in its fighter's view.
        let mut view = view_for(&state);
        view.observe(&snapshot, None);
        assert!(view
            .beliefs
            .values()
            .all(|belief| !belief.in_view && belief.up));
    }
}
