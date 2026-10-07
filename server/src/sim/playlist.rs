//! The built-in night list. One process stays up and changes map and mode
//! when a show ends. A playlist file is later work; this is the list a host
//! gets from `--playlist`.

use super::{GameState, MapKind, MatchConfig};
use crate::protocol::{GameMode, SabotageFormat};
use crate::rules::{SabotageConfig, CTF_CAPTURE_LIMIT};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct PlaylistSlot {
    pub map: MapKind,
    pub mode: GameMode,
}

/// Scrap, then a team round, then an objective, and Sabotage last so a short
/// match can finish before the night returns to Arena Duel.
pub(crate) const NIGHT: [PlaylistSlot; 8] = [
    PlaylistSlot {
        map: MapKind::ArenaDuel,
        mode: GameMode::Ffa,
    },
    PlaylistSlot {
        map: MapKind::ComplianceYard,
        mode: GameMode::Ffa,
    },
    PlaylistSlot {
        map: MapKind::Directive17,
        mode: GameMode::Tdm,
    },
    PlaylistSlot {
        map: MapKind::ArenaDuel,
        mode: GameMode::Ctf,
    },
    PlaylistSlot {
        map: MapKind::ReclamationGulch,
        mode: GameMode::Tdm,
    },
    PlaylistSlot {
        map: MapKind::Sector9,
        mode: GameMode::Ctf,
    },
    PlaylistSlot {
        map: MapKind::TripointWorks,
        mode: GameMode::Ffa,
    },
    PlaylistSlot {
        map: MapKind::Sector9,
        mode: GameMode::Sabotage,
    },
];

/// Capture the flag needs stands. Sabotage needs the Sector 9 layout.
pub(crate) fn slot_playable(map: MapKind, mode: GameMode) -> Result<(), &'static str> {
    match mode {
        GameMode::Ctf if map.ctf_stands().is_none() => {
            Err("capture the flag requires a map with validated flag stands")
        }
        GameMode::Sabotage if map.sabotage_map().is_none() => {
            Err("sabotage requires a map with validated sites (Sector 9)")
        }
        _ => Ok(()),
    }
}

/// The clocks and limits of one plain show. Warmup and the result delay are
/// the process's, so a host or a test that shortened them keeps them.
pub(crate) fn slot_config(mode: GameMode, warmup_ticks: u32, end_delay_ticks: u32) -> MatchConfig {
    let rules = crate::rules::RuleSet::new(mode, &[], false)
        .expect("a plain mode with no mutators is a valid rule set");
    let defaults = MatchConfig::default();
    let objective = mode.objective();
    MatchConfig {
        frag_limit: (!objective).then(|| rules.default_frag_limit()),
        capture_limit: (mode == GameMode::Ctf).then_some(CTF_CAPTURE_LIMIT),
        // Sabotage runs muster, live and charge clocks. Capture the flag keeps
        // the arena clock and is decided by captures when the clock ends.
        time_limit_ticks: (mode != GameMode::Sabotage)
            .then_some(defaults.time_limit_ticks)
            .flatten(),
        warmup_ticks,
        end_delay_ticks,
        boss_spawn_ticks: (!objective).then_some(defaults.boss_spawn_ticks).flatten(),
        compliance_ping_ticks: (!objective)
            .then_some(defaults.compliance_ping_ticks)
            .flatten(),
        rules,
        sabotage: SabotageConfig {
            format: SabotageFormat::Short,
            ..SabotageConfig::default()
        },
        ..defaults
    }
}

impl GameState {
    /// Refuse to bind a night whose own list names a mode the map cannot host.
    pub(crate) fn validate_night_playlist() -> Result<(), String> {
        for slot in NIGHT {
            slot_playable(slot.map, slot.mode).map_err(|error| {
                format!(
                    "{} on {} cannot start: {error}",
                    slot.mode.id(),
                    slot.map.name()
                )
            })?;
        }
        Ok(())
    }

    /// Start on the first show. Map rotation stays off so `next()` does not
    /// also walk the roster.
    pub(crate) fn arm_night_playlist(&mut self) {
        self.playlist = true;
        self.map_rotate = false;
        self.install_slot(0);
    }

    /// Called at the top of `start_round`, before Sabotage records the fallen.
    pub(super) fn advance_rotation(&mut self) {
        if self.playlist {
            if self.playlist_show_finished() {
                let next = (self.playlist_index + 1) % NIGHT.len();
                self.install_slot(next);
            }
            return;
        }
        if self.map_rotate && self.round_number > 0 {
            if let crate::maps::RuntimeMap::BuiltIn(kind) = self.map {
                self.map = crate::maps::RuntimeMap::BuiltIn(kind.next());
                self.clear_grenades();
                self.clear_mines();
                tracing::info!("Map rotate -> {} ({})", self.map.name(), self.map.id());
            }
        }
    }

    fn playlist_show_finished(&self) -> bool {
        if self.round_number == 0 {
            return false;
        }
        // Sabotage plays the short match, including the half-time swap.
        match self.sabotage.as_ref() {
            Some(sabotage) => sabotage
                .result
                .as_ref()
                .is_some_and(|result| result.match_over),
            None => true,
        }
    }

    fn install_slot(&mut self, index: usize) {
        let slot = NIGHT[index];
        let warmup_ticks = self.config.warmup_ticks;
        let end_delay_ticks = self.config.end_delay_ticks;
        let previous = self.map.clone();
        self.playlist_index = index;
        self.map = crate::maps::RuntimeMap::BuiltIn(slot.map);
        self.apply_config(slot_config(slot.mode, warmup_ticks, end_delay_ticks));
        // A team left on a free-for-all fighter blocks damage between them.
        if !slot.mode.teams() {
            for player in &mut self.players {
                player.team = None;
            }
        }
        if self.map != previous {
            self.clear_grenades();
            self.clear_mines();
        }
        // Sabotage carries a discovery arsenal. The next scrap show is the
        // map's own kit. An armed human keeps magazines, so the bag does not
        // fall back open after the match leaves Sector 9.
        self.refit_show_loadouts();
        tracing::info!("Playlist -> {} {}", self.map.name(), slot.mode.name());
    }

    fn refit_show_loadouts(&mut self) {
        let policy = self.equipment_policy();
        let only = self.config.rules.only_weapon();
        for player in &mut self.players {
            if player.is_boss || player.campaign.is_some() {
                continue;
            }
            let armed = player.inventory.armed();
            let (mut inventory, weapon) = match (policy, only) {
                (crate::protocol::EquipmentPolicy::Discovery, _) => (
                    crate::inventory::Inventory::new(crate::protocol::EquipmentPolicy::Discovery),
                    crate::protocol::WeaponType::Fists,
                ),
                (_, Some(weapon)) => (crate::inventory::Inventory::restricted(weapon), weapon),
                _ => (
                    crate::inventory::Inventory::new(crate::protocol::EquipmentPolicy::FullArsenal),
                    crate::protocol::WeaponType::default(),
                ),
            };
            if armed {
                inventory.arm_magazines();
            }
            player.inventory = inventory;
            player.weapon = weapon;
            player.golden = false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{
        EquipmentPolicy, Role, SabotageReason, SabotageResult, ServerMessage, Team, TeamScores,
        WeaponType,
    };
    use crate::session::GameSession;
    use uuid::Uuid;

    #[test]
    fn night_list_only_uses_maps_that_can_host_the_mode() {
        GameState::validate_night_playlist().unwrap();
        assert!(slot_playable(MapKind::ComplianceYard, GameMode::Ctf).is_err());
        assert!(slot_playable(MapKind::ReclamationGulch, GameMode::Ctf).is_err());
        assert!(slot_playable(MapKind::TripointWorks, GameMode::Ctf).is_err());
        assert!(slot_playable(MapKind::ArenaDuel, GameMode::Sabotage).is_err());
        assert!(slot_playable(MapKind::Directive17, GameMode::Ctf).is_ok());
        assert!(slot_playable(MapKind::Sector9, GameMode::Sabotage).is_ok());
        assert_eq!(
            NIGHT.map(|slot| (slot.map, slot.mode)),
            [
                (MapKind::ArenaDuel, GameMode::Ffa),
                (MapKind::ComplianceYard, GameMode::Ffa),
                (MapKind::Directive17, GameMode::Tdm),
                (MapKind::ArenaDuel, GameMode::Ctf),
                (MapKind::ReclamationGulch, GameMode::Tdm),
                (MapKind::Sector9, GameMode::Ctf),
                (MapKind::TripointWorks, GameMode::Ffa),
                (MapKind::Sector9, GameMode::Sabotage),
            ]
        );
    }

    #[test]
    fn map_rotate_moves_a_living_fighter_onto_the_next_map() {
        let mut state = GameState::with_map(MapKind::ArenaDuel, true);
        state.start_round();
        let id = Uuid::new_v4();
        state.add_player(id, "Survivor".into(), Role::Human);
        {
            let player = state
                .players
                .iter_mut()
                .find(|player| player.id == id)
                .unwrap();
            player.x = 65.0;
            player.z = 0.0;
            player.hp = 100;
            player.eliminated = false;
            player.respawn_timer = None;
        }
        state.test_insert_grenade(id);
        state.test_insert_mine(id);
        assert_eq!(state.snapshot().grenades.len(), 1);
        assert_eq!(state.snapshot().mines.len(), 1);
        state.end_round("test".into());
        state.start_round();
        assert_eq!(state.map, MapKind::ComplianceYard);
        let player = state.players.iter().find(|player| player.id == id).unwrap();
        let half = MapKind::ComplianceYard.half_extent();
        assert!(
            player.x.abs() <= half && player.z.abs() <= half,
            "survivor left the yard: {}, {}",
            player.x,
            player.z
        );
        assert!(
            (player.x - 65.0).abs() > 1.0 || player.z.abs() > 1.0,
            "survivor stayed at the old coordinates"
        );
        assert!(
            !super::super::circle_blocked_for_test(MapKind::ComplianceYard, player.x, player.z),
            "spawn is inside a solid at {}, {}",
            player.x,
            player.z
        );
        assert!(state.snapshot().grenades.is_empty());
        assert!(state.snapshot().mines.is_empty());
    }

    #[test]
    fn night_playlist_advances_map_and_mode_and_holds_sabotage_for_the_match() {
        let mut state = GameState::new();
        state.config.warmup_ticks = 4;
        state.config.end_delay_ticks = 7;
        state.arm_night_playlist();
        assert!(!state.map_rotate);
        assert_eq!(state.config.warmup_ticks, 4);
        assert_eq!(state.config.end_delay_ticks, 7);
        assert_eq!(state.map, MapKind::ArenaDuel);
        assert_eq!(state.config.rules.mode(), GameMode::Ffa);
        let id = Uuid::new_v4();
        state.add_player(id, "Survivor".into(), Role::Human);
        state.start_round();
        assert_eq!(state.round_number, 1);
        assert_eq!(state.map, MapKind::ArenaDuel);
        assert_eq!(state.config.rules.mode(), GameMode::Ffa);

        let mut saw_tdm = false;
        let mut saw_ctf = false;
        let mut sabotage_rounds = 0_u32;
        for _ in 0..12 {
            state.end_round("show over".into());
            state.start_round();
            assert_eq!(state.config.warmup_ticks, 4);
            assert_eq!(state.config.end_delay_ticks, 7);
            match state.config.rules.mode() {
                GameMode::Tdm => {
                    saw_tdm = true;
                    assert_eq!(state.config.frag_limit, Some(25));
                    assert!(state.config.time_limit_ticks.is_some());
                    assert!(state.players.iter().any(|player| player.team.is_some()));
                }
                GameMode::Ctf => {
                    saw_ctf = true;
                    assert_eq!(state.config.capture_limit, Some(CTF_CAPTURE_LIMIT));
                    assert!(state.config.frag_limit.is_none());
                    assert!(state.config.boss_spawn_ticks.is_none());
                    assert!(state.map.ctf_stands().is_some());
                }
                GameMode::Sabotage => {
                    sabotage_rounds += 1;
                    assert_eq!(state.map, MapKind::Sector9);
                    assert_eq!(state.config.sabotage.format, SabotageFormat::Short);
                    assert!(state.config.time_limit_ticks.is_none());
                    assert!(state.config.frag_limit.is_none());
                    let player = state.players.iter().find(|player| player.id == id).unwrap();
                    let layout = MapKind::Sector9.sabotage_layout().unwrap();
                    let placed = layout.spawns.iter().flatten().any(|spawn| {
                        (spawn[0] - player.x).abs() < 0.05 && (spawn[2] - player.z).abs() < 0.05
                    });
                    assert!(
                        placed,
                        "sabotage left the fighter at {}, {}",
                        player.x, player.z
                    );
                    assert_eq!(player.inventory.policy(), EquipmentPolicy::Discovery);
                    assert_eq!(player.weapon, WeaponType::Fists);
                    if sabotage_rounds == 1 {
                        let round = state.sabotage.as_ref().unwrap().round;
                        assert_eq!(round, 1);
                        state.end_round("half continues".into());
                        state.start_round();
                        assert_eq!(state.config.rules.mode(), GameMode::Sabotage);
                        assert_eq!(state.sabotage.as_ref().unwrap().round, 2);
                        state.sabotage.as_mut().unwrap().result = Some(SabotageResult {
                            reason: SabotageReason::Time,
                            round: 2,
                            score: TeamScores::default(),
                            sides_swap: false,
                            match_over: true,
                            match_winner: Some(Team::Union),
                        });
                    }
                }
                GameMode::Ffa => {
                    assert!(state.players.iter().all(|player| player.team.is_none()));
                    assert_eq!(state.config.frag_limit, Some(10));
                }
            }
            if state.config.rules.mode() == GameMode::Ffa
                && state.map == MapKind::ArenaDuel
                && state.round_number > 1
            {
                break;
            }
        }
        assert!(saw_tdm);
        assert!(saw_ctf);
        assert!(sabotage_rounds >= 1);
        assert_eq!(state.map, MapKind::ArenaDuel);
        assert_eq!(state.config.rules.mode(), GameMode::Ffa);
        assert!(state.players.iter().all(|player| player.team.is_none()));
        let player = state
            .players
            .iter_mut()
            .find(|player| player.id == id)
            .unwrap();
        assert_eq!(player.inventory.policy(), EquipmentPolicy::FullArsenal);
        assert_eq!(player.weapon, WeaponType::Flechette);
        assert!(player.inventory.try_fire(WeaponType::Rail));
    }

    #[test]
    fn a_show_change_reseeds_an_armed_humans_bag() {
        let mut state = GameState::new();
        state.arm_night_playlist();
        let id = Uuid::new_v4();
        state.add_player(id, "Proxy".into(), Role::Human);
        state.arm_joined_magazines(id);
        state.start_round();
        {
            let inventory = &mut state
                .players
                .iter_mut()
                .find(|player| player.id == id)
                .unwrap()
                .inventory;
            for _ in 0..80 {
                if !inventory.try_fire(WeaponType::Flechette) {
                    assert!(inventory.request_reload(WeaponType::Flechette, 1));
                    inventory.finish_reload(
                        1 + u64::from(WeaponType::Flechette.reload_ticks().unwrap()),
                    );
                    assert!(inventory.try_fire(WeaponType::Flechette));
                }
            }
            assert!(!inventory.try_fire(WeaponType::Flechette));
            assert!(!inventory.request_reload(WeaponType::Flechette, 2));
        }
        state.end_round("show over".into());
        state.start_round();
        assert_eq!(state.map, MapKind::ComplianceYard);
        let player = state.players.iter().find(|player| player.id == id).unwrap();
        assert!(player.inventory.armed());
        let loadout = player
            .inventory
            .state(id, WeaponType::Flechette, state.tick)
            .unwrap();
        assert_eq!(loadout.ammo(crate::protocol::AmmoPool::Bullets), 80);
        assert_eq!(loadout.shots(WeaponType::Flechette), Some(20));
        assert_eq!(loadout.ammo(crate::protocol::AmmoPool::Shells), 24);
        assert_eq!(loadout.ammo(crate::protocol::AmmoPool::Cells), 16);
    }

    #[test]
    fn a_mode_change_on_the_same_map_sends_map_info_again() {
        let mut session = GameSession::with_map(MapKind::ArenaDuel, false);
        let first = session.tick_messages(0.05);
        assert_eq!(map_mode(&first), Some(GameMode::Ffa));
        let mut config = session.state.config.clone();
        config.rules = crate::rules::RuleSet::new(GameMode::Tdm, &[], false).unwrap();
        session.state.apply_config(config);
        let second = session.tick_messages(0.05);
        assert_eq!(map_mode(&second), Some(GameMode::Tdm));
        let third = session.tick_messages(0.05);
        assert_eq!(map_mode(&third), None);
    }

    fn map_mode(messages: &[ServerMessage]) -> Option<GameMode> {
        messages.iter().find_map(|message| match message {
            ServerMessage::MapInfo { rules, .. } => rules.as_ref().map(|rules| rules.mode),
            _ => None,
        })
    }
}
