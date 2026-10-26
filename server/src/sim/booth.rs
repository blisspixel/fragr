//! The booth's facts, built from the authoritative state. The session sends
//! them only to spectator connections (`protocol::SpectatorFacts`).
use super::{GameState, PickupKind, PLAYER_MAX_ARMOR};
use crate::protocol::{
    ChainFact, PadClock, PlateFact, SpectatorFacts, SpreeFact, MAX_SPECTATOR_PADS,
    MAX_SPECTATOR_RUNS,
};

impl GameState {
    /// What the booth may know this tick: every down pad's live clock, the
    /// Custody Plate and who wears plated armour, runs of two or more frags
    /// without dying, and multikill chains still open. Bodies that are dead,
    /// parked or eliminated hold no spree, chain or plate.
    pub fn spectator_facts(&self) -> SpectatorFacts {
        let standing = |id: uuid::Uuid| {
            self.players.iter().any(|p| {
                p.id == id
                    && p.hp > 0
                    && p.respawn_timer.is_none()
                    && !p.eliminated
                    && !p.detached
                    && p.is_participant()
            })
        };
        let mut pads: Vec<PadClock> = self
            .pickups
            .iter()
            .filter(|pad| pad.kind != PickupKind::Plate && !pad.available)
            .filter_map(|pad| {
                Some(PadClock {
                    id: pad.id.clone(),
                    kind: pad.kind.wire_name().to_string(),
                    weapon: pad
                        .kind
                        .weapon()
                        .map(|weapon| weapon.name().to_string())
                        .unwrap_or_default(),
                    power: pad.kind.is_power(),
                    back_in: pad.respawn_timer?,
                })
            })
            .collect();
        if let Some((id, back_in)) = self
            .article_blade
            .as_ref()
            .and_then(|blade| Some((blade.pickup_state().id, blade.return_in()?)))
        {
            pads.push(PadClock {
                id,
                kind: "weapon".to_string(),
                weapon: crate::protocol::WeaponType::ArticleBlade.name().to_string(),
                power: true,
                back_in,
            });
        }
        pads.sort_by(|a, b| a.back_in.cmp(&b.back_in).then_with(|| a.id.cmp(&b.id)));
        pads.truncate(MAX_SPECTATOR_PADS);

        let plate = self
            .pickups
            .iter()
            .find(|pad| pad.kind == PickupKind::Plate)
            .map(|pad| {
                let holder = self
                    .players
                    .iter()
                    .filter(|p| p.armor > PLAYER_MAX_ARMOR && standing(p.id))
                    .max_by(|a, b| a.armor.cmp(&b.armor).then_with(|| b.id.cmp(&a.id)));
                PlateFact {
                    id: pad.id.clone(),
                    up: pad.available,
                    back_in: if pad.available {
                        None
                    } else {
                        pad.respawn_timer
                    },
                    holder: holder.map(|p| p.id),
                    armor: holder.map(|p| p.armor),
                }
            });

        let mut sprees: Vec<SpreeFact> = self
            .players
            .iter()
            .filter(|p| p.killstreak >= 2 && standing(p.id))
            .map(|p| SpreeFact {
                id: p.id,
                frags: p.killstreak,
            })
            .collect();
        sprees.sort_by(|a, b| b.frags.cmp(&a.frags).then_with(|| a.id.cmp(&b.id)));
        sprees.truncate(MAX_SPECTATOR_RUNS);

        let window = crate::rules::MULTIKILL_WINDOW_TICKS;
        let mut chains: Vec<ChainFact> = self
            .reactions
            .chains
            .iter()
            .filter(|(id, (frags, last))| {
                *frags >= 2 && self.tick.saturating_sub(*last) <= window && standing(**id)
            })
            .map(|(id, (frags, last))| ChainFact {
                id: *id,
                frags: *frags,
                open_for: u32::try_from(window.saturating_sub(self.tick.saturating_sub(*last)))
                    .unwrap_or(u32::MAX),
            })
            .collect();
        chains.sort_by(|a, b| b.frags.cmp(&a.frags).then_with(|| a.id.cmp(&b.id)));
        chains.truncate(MAX_SPECTATOR_RUNS);

        SpectatorFacts {
            tick: self.tick,
            spree_step: crate::rules::spree_step(self.config.rules.mode()),
            pads,
            plate,
            sprees,
            chains,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Role;
    use uuid::Uuid;

    fn lot() -> GameState {
        let mut state = GameState::new();
        state.start_round();
        state
    }

    #[test]
    fn down_pads_report_their_live_clock_soonest_first() {
        let mut state = lot();
        assert!(
            state.spectator_facts().pads.is_empty(),
            "every pad is up at the bell"
        );
        let rail = state
            .pickups
            .iter()
            .position(|pad| pad.kind == PickupKind::Weapon(crate::protocol::WeaponType::Rail))
            .expect("Larak Lot lays a Rail");
        let health = state
            .pickups
            .iter()
            .position(|pad| pad.kind == PickupKind::Health)
            .expect("Larak Lot lays health");
        state.pickups[rail].available = false;
        state.pickups[rail].respawn_timer = Some(300);
        state.pickups[health].available = false;
        state.pickups[health].respawn_timer = Some(40);
        let facts = state.spectator_facts();
        assert_eq!(facts.pads.len(), 2);
        assert_eq!(facts.pads[0].kind, "health");
        assert_eq!(facts.pads[0].back_in, 40);
        assert!(!facts.pads[0].power);
        assert_eq!(facts.pads[1].weapon, "Rail");
        assert!(facts.pads[1].power);
        assert_eq!(facts.pads[1].back_in, 300);
        // Campaign stock that never returns has no clock to report.
        state.pickups[health].respawn_timer = None;
        assert_eq!(state.spectator_facts().pads.len(), 1);
    }

    #[test]
    fn the_plate_names_its_wearer_and_its_clock() {
        let mut state = lot();
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        state.add_player(a, "Nightfall".into(), Role::Agent);
        state.add_player(b, "Aunt Linda".into(), Role::Agent);
        let plate = state
            .pickups
            .iter()
            .position(|pad| pad.kind == PickupKind::Plate)
            .expect("Larak Lot lays the Custody Plate");
        let up = state.spectator_facts().plate.expect("plate fact");
        assert!(up.up && up.back_in.is_none() && up.holder.is_none());
        state.pickups[plate].available = false;
        state.pickups[plate].respawn_timer = Some(700);
        for player in &mut state.players {
            player.armor = if player.id == a { 143 } else { 100 };
        }
        let worn = state.spectator_facts().plate.expect("plate fact");
        assert_eq!(worn.back_in, Some(700));
        assert_eq!(worn.holder, Some(a));
        assert_eq!(worn.armor, Some(143));
        assert!(
            state
                .spectator_facts()
                .pads
                .iter()
                .all(|pad| pad.id != worn.id),
            "the Plate is reported once, on its own"
        );
        // A dead wearer holds nothing.
        state.players.iter_mut().find(|p| p.id == a).unwrap().hp = 0;
        assert!(state.spectator_facts().plate.unwrap().holder.is_none());
    }

    #[test]
    fn sprees_and_open_chains_rank_longest_first_and_close() {
        let mut state = lot();
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        let c = Uuid::from_u128(3);
        for (id, name) in [(a, "Nightfall"), (b, "Aunt Linda"), (c, "Static Kid")] {
            state.add_player(id, name.into(), Role::Agent);
        }
        for player in &mut state.players {
            player.killstreak = if player.id == a {
                6
            } else if player.id == b {
                2
            } else {
                1
            };
        }
        let facts = state.spectator_facts();
        assert_eq!(
            facts.sprees,
            vec![SpreeFact { id: a, frags: 6 }, SpreeFact { id: b, frags: 2 }],
            "a single frag is not a run"
        );
        assert_eq!(
            facts.spree_step,
            crate::rules::spree_step(state.config.rules.mode())
        );
        let now = state.tick;
        state.reactions.chains.insert(a, (3, now));
        state.reactions.chains.insert(b, (1, now));
        let facts = state.spectator_facts();
        assert_eq!(facts.chains.len(), 1);
        assert_eq!(facts.chains[0].id, a);
        assert_eq!(facts.chains[0].frags, 3);
        assert_eq!(
            u64::from(facts.chains[0].open_for),
            crate::rules::MULTIKILL_WINDOW_TICKS
        );
        state.tick += crate::rules::MULTIKILL_WINDOW_TICKS + 1;
        assert!(
            state.spectator_facts().chains.is_empty(),
            "the window closed"
        );
    }
}
