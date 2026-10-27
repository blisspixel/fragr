//! What a joined agent can know about the map's pads. The snapshot carries
//! every pad's live availability for the renderer, and no return timer: the
//! live clocks go only to spectator connections (`spectator_facts`). A
//! fighter sees a pad only inside a 120 degree view, within 40 m and past the
//! map's solids, or underfoot, and remembers the published return clocks.
//! `observe` reports that belief for a joined agent. A spectator that never
//! joined keeps the snapshot's full availability view, and `round_state`
//! carries its booth clocks.
//!
//! A gun dropped on death (`dropped`) is not a pad: a joined agent learns of
//! it only once it has seen it, the way a rule bot does, and an unseen drop
//! is left out of `observe` altogether.
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

/// A dropped gun the joined fighter has seen, kept as it was last seen.
#[derive(Debug, Clone, PartialEq)]
struct DropBelief {
    row: PickupState,
    /// Past this tick the fighter assumes it is gone: first seen plus the
    /// published lifetime, the way a rule bot reckons it.
    gone_at: u64,
    in_view: bool,
}

#[derive(Debug, Clone, Default)]
pub struct PadView {
    solids: Vec<Solid>,
    teams: bool,
    /// Pads return on their clocks: an arcade map with a rule sheet.
    returns: bool,
    beliefs: HashMap<String, Belief>,
    drops: HashMap<String, DropBelief>,
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
    /// A new map: its solids, whether weapon pads keep the team clock,
    /// whether pads return at all, and every pad believed up, as at a round
    /// start.
    pub fn reset_map(&mut self, solids: Vec<Solid>, teams: bool, returns: bool) {
        self.solids = solids;
        self.teams = teams;
        self.returns = returns;
        self.beliefs.clear();
        self.drops.clear();
    }

    /// A round start puts every pad back and clears the floor.
    pub fn reset_round(&mut self) {
        self.beliefs.clear();
        self.drops.clear();
    }

    /// Fold one snapshot from the joined fighter's own eyes.
    pub fn observe(&mut self, snapshot: &Snapshot, me: Option<Uuid>) {
        let me = me.and_then(|id| snapshot.players.iter().find(|p| p.id == id && p.hp > 0));
        self.observe_drops(snapshot, me);
        for pad in snapshot.pickups.iter().filter(|pad| !pad.dropped) {
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
                } else if !self.returns {
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

    /// Learn dropped guns in view; forget one only when its spot is in view
    /// and empty, or its reckoned lifetime has run out. A gun taken out of
    /// view stays believed, exactly as for a rule bot.
    fn observe_drops(&mut self, snapshot: &Snapshot, me: Option<&PlayerState>) {
        let tick = snapshot.tick;
        let lifetime = u64::from(fragr_server::sim::drops::DROPPED_GUN_TICKS);
        for belief in self.drops.values_mut() {
            belief.in_view = false;
        }
        for row in snapshot.pickups.iter().filter(|pad| pad.dropped) {
            if !me.is_some_and(|me| sees(&self.solids, me, row)) {
                continue;
            }
            let gone_at = self
                .drops
                .get(&row.id)
                .map_or(tick.saturating_add(lifetime), |old| old.gone_at);
            self.drops.insert(
                row.id.clone(),
                DropBelief {
                    row: row.clone(),
                    gone_at,
                    in_view: true,
                },
            );
        }
        let solids = &self.solids;
        self.drops.retain(|id, belief| {
            if tick >= belief.gone_at {
                return false;
            }
            let present = snapshot
                .pickups
                .iter()
                .any(|pad| pad.dropped && &pad.id == id);
            present || !me.is_some_and(|me| sees(solids, me, &belief.row))
        });
    }

    /// The dropped guns this fighter believes are lying where it saw them.
    pub fn believed_drops(&self) -> Vec<PickupState> {
        let mut rows: Vec<PickupState> = self
            .drops
            .values()
            .map(|belief| belief.row.clone())
            .collect();
        rows.sort_by(|a, b| a.id.cmp(&b.id));
        rows
    }

    /// Whether the joined agent believes `pad` is up. A personal stash is the
    /// agent's own business and passes through.
    pub fn up(&self, pad: &PickupState) -> bool {
        if pad.claim == SupplyClaim::Personal {
            return pad.available;
        }
        if pad.dropped {
            // A dropped gun is known only once seen, until seen gone.
            return self.drops.contains_key(&pad.id);
        }
        self.beliefs.get(&pad.id).is_none_or(|belief| belief.up)
    }

    /// Whether a `pickup` event is something the joined fighter could know:
    /// every pad claim is public as before, but the claim of a dropped gun
    /// is heard only by the one who took it, or while the fighter sees it.
    pub fn hears_pickup(&self, pickup_id: &str, by_me: bool) -> bool {
        if by_me || !pickup_id.starts_with(fragr_server::sim::drops::DROPPED_GUN_PREFIX) {
            return true;
        }
        self.drops
            .get(pickup_id)
            .is_some_and(|belief| belief.in_view)
    }

    /// Rewrite a full observation's pickups to this belief: `available` is
    /// what the agent believes and `in_view` whether it can see the pad now.
    pub fn redact(&self, pickups: &mut Value) {
        let Some(rows) = pickups.as_array_mut() else {
            return;
        };
        // Drops come from belief, not the live floor: unseen ones are left
        // out and seen ones stay, as last seen, until seen gone.
        rows.retain(|row| row.get("dropped").and_then(Value::as_bool) != Some(true));
        let mut drops: Vec<&DropBelief> = self.drops.values().collect();
        drops.sort_by(|a, b| a.row.id.cmp(&b.row.id));
        for belief in drops {
            if let Ok(mut row) = serde_json::to_value(&belief.row) {
                if let Some(object) = row.as_object_mut() {
                    object.insert("in_view".into(), Value::Bool(belief.in_view));
                }
                rows.push(row);
            }
        }
        for row in rows
            .iter_mut()
            .filter(|row| row.get("dropped").and_then(Value::as_bool) != Some(true))
        {
            let Some(object) = row.as_object_mut() else {
                continue;
            };
            let personal = object.get("claim").and_then(Value::as_str) == Some("personal");
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
        view.reset_map(state.map.arena().solids.clone(), false, true);
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

        // Another pad taken out of view is still believed up, and the
        // snapshot carries no live timer to hide.
        state.pickups[1].available = false;
        state.pickups[1].respawn_timer = Some(50);
        view.observe(&state.snapshot(), Some(me));
        let other = state.snapshot().pickups[1].clone();
        assert!(view.up(&other));
        let mut rows = serde_json::to_value(&state.snapshot().pickups).unwrap();
        assert!(rows[1].get("respawn_in").is_none());
        view.redact(&mut rows);
        assert_eq!(rows[1]["available"], true);
        assert_eq!(rows[1]["in_view"], false);
        assert!(rows[1].get("respawn_in").is_none());
    }

    #[test]
    fn stock_that_never_restocks_stays_gone_until_seen_again() {
        let (mut state, me) = arena();
        // A campaign map: no rule sheet, so pads do not return on a clock.
        let mut view = PadView::default();
        view.reset_map(state.map.arena().solids.clone(), false, false);
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

    #[test]
    fn a_dropped_gun_is_in_observe_only_once_seen_and_stays_until_seen_gone() {
        let (mut state, me) = arena();
        let mut view = view_for(&state);
        stand_at(&mut state, me, 0, 0.0, 2.0);
        let mine = state
            .snapshot()
            .players
            .into_iter()
            .find(|p| p.id == me)
            .unwrap();
        let drop = |x: f32, z: f32| PickupState {
            claim: SupplyClaim::Contested,
            pool: None,
            id: "drop_1".into(),
            kind: "weapon".into(),
            weapon: "Rocket".into(),
            amount: Some(3),
            x,
            y: mine.y - fragr_server::sim::PLAYER_FLOOR_Y + PAD_LIFT,
            z,
            available: true,
            dropped: true,
        };
        let rows = |view: &PadView, snapshot: &Snapshot| {
            let mut rows = serde_json::to_value(&snapshot.pickups).unwrap();
            view.redact(&mut rows);
            rows.as_array()
                .unwrap()
                .iter()
                .filter(|row| row["id"] == "drop_1")
                .cloned()
                .collect::<Vec<Value>>()
        };
        // Behind the agent and far off: not seen, not in observe.
        let behind = drop(
            mine.x - mine.yaw.cos() * 20.0,
            mine.z - mine.yaw.sin() * 20.0,
        );
        let mut snapshot = state.snapshot();
        snapshot.pickups.push(behind);
        view.observe(&snapshot, Some(me));
        assert!(!view.up(snapshot.pickups.last().unwrap()));
        assert!(rows(&view, &snapshot).is_empty());
        assert!(
            !view.hears_pickup("drop_1", false),
            "an unseen claim is not heard"
        );
        assert!(view.hears_pickup("drop_1", true) && view.hears_pickup("pad_rail", false));

        // Underfoot: seen.
        let near = drop(mine.x + 1.0, mine.z);
        let mut seen = state.snapshot();
        seen.pickups.push(near.clone());
        view.observe(&seen, Some(me));
        let row = rows(&view, &seen);
        assert_eq!(row.len(), 1);
        assert_eq!(row[0]["dropped"], true);
        assert_eq!(row[0]["in_view"], true);
        assert!(view.up(&near));

        // Seen, turned away, taken: still observed, out of view.
        stand_at(&mut state, me, 0, 0.0, 39.0);
        state.players.iter_mut().find(|p| p.id == me).unwrap().yaw = PI;
        let mut away = state.snapshot();
        away.tick = seen.tick + 20;
        view.observe(&away, Some(me));
        let row = rows(&view, &away);
        assert_eq!(row.len(), 1, "a gun taken out of view is still believed");
        assert_eq!(row[0]["in_view"], false);
        assert_eq!(view.believed_drops().len(), 1);

        // The reckoned lifetime runs out unseen: forgotten.
        let mut later = state.snapshot();
        later.tick = seen.tick + u64::from(fragr_server::sim::drops::DROPPED_GUN_TICKS);
        view.observe(&later, Some(me));
        assert!(rows(&view, &later).is_empty());

        // Seen again, then its spot seen empty: forgotten at once.
        stand_at(&mut state, me, 0, 0.0, 2.0);
        let mut back = state.snapshot();
        back.pickups.push(near.clone());
        view.observe(&back, Some(me));
        assert_eq!(rows(&view, &back).len(), 1);
        let empty = state.snapshot();
        view.observe(&empty, Some(me));
        assert!(rows(&view, &empty).is_empty(), "seen gone is gone");
    }
}
