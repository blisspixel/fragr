//! Versioned solo-run document. Disk transport is local-only and separate.
use crate::inventory::{Inventory, SavedEquipment};
use crate::protocol::{
    CampaignRules, CampaignRunStatus, EquipmentPolicy, MissionId, WeaponType, CAMPAIGN_CONTINUES,
    CAMPAIGN_RULES_REVISION,
};
use crate::sim::{GameState, Player, PLAYER_MAX_ARMOR, PLAYER_MAX_HP};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub(crate) mod store;

pub(super) const RUN_FILE_VERSION: u32 = 1;
const NEXT_MISSION: &str = "persons_unknown";

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SavedEntry {
    pub hp: i32,
    pub armor: i32,
    pub equipment: SavedEquipment,
}

impl SavedEntry {
    pub fn initial() -> Self {
        Self {
            hp: PLAYER_MAX_HP,
            armor: 0,
            equipment: Inventory::new(EquipmentPolicy::Discovery)
                .saved_equipment(WeaponType::Fists)
                .expect("initial discovery equipment is valid"),
        }
    }

    pub fn from_player(player: &Player) -> Result<Self, &'static str> {
        let entry = Self {
            hp: player.hp,
            armor: player.armor,
            equipment: player
                .inventory
                .saved_equipment(player.weapon)
                .ok_or("player equipment cannot be saved")?,
        };
        entry.validate()?;
        Ok(entry)
    }

    fn validate(&self) -> Result<(), &'static str> {
        if !(1..=PLAYER_MAX_HP).contains(&self.hp) || !(0..=PLAYER_MAX_ARMOR).contains(&self.armor)
        {
            return Err("invalid campaign entry health or armor");
        }
        self.equipment.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum SavedStep {
    MissionEntry {
        mission: MissionId,
        entry: SavedEntry,
    },
    PendingContinue {
        mission: MissionId,
        entry: SavedEntry,
    },
    Failed {
        mission: MissionId,
        entry: SavedEntry,
    },
    Abandoned {
        mission: MissionId,
        entry: SavedEntry,
    },
    AwaitingMission {
        completed_mission: MissionId,
        next_mission: String,
        exit: SavedEntry,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RunDocument {
    pub version: u32,
    pub id: Uuid,
    pub starting_continues: u8,
    pub remaining_continues: u8,
    pub rules: CampaignRules,
    pub content_sha256: [u8; 32],
    pub step: SavedStep,
}

impl RunDocument {
    pub fn new(id: Uuid, rules: CampaignRules, content_sha256: [u8; 32]) -> Self {
        Self {
            version: RUN_FILE_VERSION,
            id,
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: CAMPAIGN_CONTINUES,
            rules,
            content_sha256,
            step: SavedStep::MissionEntry {
                mission: MissionId::RecallNotice,
                entry: SavedEntry::initial(),
            },
        }
    }

    pub fn validate(&self, content_sha256: [u8; 32]) -> Result<(), &'static str> {
        if self.version != RUN_FILE_VERSION
            || self.id.is_nil()
            || self.starting_continues != CAMPAIGN_CONTINUES
            || self.remaining_continues > self.starting_continues
            || self.rules.revision != CAMPAIGN_RULES_REVISION
            || self.content_sha256 != content_sha256
        {
            return Err("incompatible campaign run identity, rules, or content");
        }
        match &self.step {
            SavedStep::MissionEntry { mission, entry } => self.validate_mission(*mission, entry),
            SavedStep::PendingContinue { mission, entry } => {
                if self.remaining_continues == 0 {
                    return Err("pending continue has no allowance");
                }
                self.validate_mission(*mission, entry)
            }
            SavedStep::Failed { mission, entry } => {
                if self.remaining_continues != 0 {
                    return Err("failed run retains a continue");
                }
                self.validate_mission(*mission, entry)
            }
            SavedStep::Abandoned { mission, entry } => self.validate_mission(*mission, entry),
            SavedStep::AwaitingMission {
                completed_mission,
                next_mission,
                exit,
            } => {
                if *completed_mission != MissionId::RecallNotice || next_mission != NEXT_MISSION {
                    return Err("unsupported saved campaign transition");
                }
                exit.validate()
            }
        }
    }

    fn validate_mission(&self, mission: MissionId, entry: &SavedEntry) -> Result<(), &'static str> {
        if mission != MissionId::RecallNotice {
            return Err("unsupported saved mission");
        }
        entry.validate()
    }

    pub fn attempt(&self) -> u32 {
        u32::from(self.starting_continues - self.remaining_continues) + 1
    }
}

impl GameState {
    pub(crate) fn campaign_run_document(&self) -> Result<Option<RunDocument>, &'static str> {
        let Some(run) = self.mission.as_ref() else {
            return Ok(None);
        };
        let Some(solo) = run.solo.as_ref() else {
            return Ok(None);
        };
        let content_sha256 = self
            .map
            .content_sha256()
            .ok_or("campaign run requires authored content")?;
        let entry = solo.saved_entry().unwrap_or_else(SavedEntry::initial);
        let mission = self
            .map
            .mission()
            .ok_or("campaign run requires mission geometry")?
            .id;
        let step = match solo.state.status {
            CampaignRunStatus::Playing => SavedStep::MissionEntry { mission, entry },
            CampaignRunStatus::Continue => SavedStep::PendingContinue { mission, entry },
            CampaignRunStatus::Failed => SavedStep::Failed { mission, entry },
            CampaignRunStatus::Complete => SavedStep::AwaitingMission {
                completed_mission: mission,
                next_mission: NEXT_MISSION.into(),
                exit: solo
                    .saved_exit()
                    .ok_or("completed run has no saved exit")?
                    .clone(),
            },
            CampaignRunStatus::Abandoned => SavedStep::Abandoned { mission, entry },
        };
        let document = RunDocument {
            version: RUN_FILE_VERSION,
            id: solo.state.id,
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: solo.state.continues,
            rules: run.rules,
            content_sha256,
            step,
        };
        document.validate(content_sha256)?;
        Ok(Some(document))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::Inventory;
    use crate::maps::AuthoredMap;
    use crate::protocol::{CampaignDifficulty, EquipmentPolicy, MissionContinue, Role, WeaponType};

    fn state_with_map() -> GameState {
        let map = AuthoredMap::read(
            serde_json::to_vec(&super::super::tests::definition())
                .unwrap()
                .as_slice(),
        )
        .unwrap();
        GameState::with_authored_map(map)
    }

    fn document() -> RunDocument {
        let inventory = Inventory::new(EquipmentPolicy::Discovery);
        RunDocument {
            version: RUN_FILE_VERSION,
            id: Uuid::from_u128(1),
            starting_continues: CAMPAIGN_CONTINUES,
            remaining_continues: CAMPAIGN_CONTINUES,
            rules: CampaignRules::new(CampaignDifficulty::Standard),
            content_sha256: [5; 32],
            step: SavedStep::MissionEntry {
                mission: MissionId::RecallNotice,
                entry: SavedEntry {
                    hp: 100,
                    armor: 0,
                    equipment: inventory.saved_equipment(WeaponType::Fists).unwrap(),
                },
            },
        }
    }

    #[test]
    fn run_document_round_trips_and_rejects_invalid_transitions() {
        let original = document();
        let bytes = serde_json::to_vec(&original).unwrap();
        let decoded: RunDocument = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(decoded, original);
        decoded.validate([5; 32]).unwrap();
        assert_eq!(decoded.attempt(), 1);
        let mut pending = original.clone();
        pending.remaining_continues = 1;
        let SavedStep::MissionEntry { mission, entry } = original.step else {
            panic!("fixture must start at mission entry");
        };
        pending.step = SavedStep::PendingContinue { mission, entry };
        pending.validate([5; 32]).unwrap();
        assert_eq!(pending.attempt(), 3);
        pending.remaining_continues = 0;
        assert!(pending.validate([5; 32]).is_err());
        pending.step = SavedStep::Failed {
            mission,
            entry: match pending.step {
                SavedStep::PendingContinue { entry, .. } => entry,
                _ => unreachable!(),
            },
        };
        pending.validate([5; 32]).unwrap();
        pending.remaining_continues = 1;
        assert!(pending.validate([5; 32]).is_err());

        let mut abandoned = document();
        abandoned.step = SavedStep::Abandoned {
            mission: MissionId::RecallNotice,
            entry: SavedEntry::initial(),
        };
        abandoned.validate([5; 32]).unwrap();
        assert_eq!(abandoned.remaining_continues, CAMPAIGN_CONTINUES);
    }

    #[test]
    fn completed_m01_is_a_distinct_pending_m02_boundary() {
        let mut saved = document();
        let SavedStep::MissionEntry { mission, entry } = saved.step else {
            panic!("fixture must start at mission entry");
        };
        saved.step = SavedStep::AwaitingMission {
            completed_mission: mission,
            next_mission: NEXT_MISSION.into(),
            exit: entry,
        };
        saved.validate([5; 32]).unwrap();
        assert!(saved.validate([6; 32]).is_err());
        if let SavedStep::AwaitingMission { next_mission, .. } = &mut saved.step {
            *next_mission = "recall_notice".into();
        }
        assert!(saved.validate([5; 32]).is_err());
        let mut value = serde_json::to_value(&saved).unwrap();
        value["unexpected"] = true.into();
        assert!(serde_json::from_value::<RunDocument>(value).is_err());
    }

    #[test]
    fn resumed_pending_continue_restores_dead_owner_then_spends_once() {
        let mut state = state_with_map();
        let hash = state.map.content_sha256().unwrap();
        let mut document = RunDocument::new(
            Uuid::new_v4(),
            CampaignRules::new(CampaignDifficulty::Severe),
            hash,
        );
        document.remaining_continues = 1;
        document.step = SavedStep::PendingContinue {
            mission: MissionId::RecallNotice,
            entry: SavedEntry::initial(),
        };
        state.load_campaign_run(&document).unwrap();
        let owner = Uuid::new_v4();
        state.add_player(owner, "Free agent".into(), Role::Agent);
        let mission = state.mission_state().unwrap();
        mission.validate(state.tick).unwrap();
        assert_eq!(mission.attempt, 3);
        assert_eq!(mission.run.unwrap().status, CampaignRunStatus::Continue);
        assert!(!mission.party[0].alive);
        assert_eq!(
            state.campaign_run_document().unwrap(),
            Some(document.clone())
        );
        let request = MissionContinue {
            id: MissionId::RecallNotice,
            run_id: document.id,
            attempt: 3,
        };
        assert!(state.continue_mission(owner, request));
        assert!(!state.continue_mission(owner, request));
        let resumed = state.campaign_run_document().unwrap().unwrap();
        assert_eq!(resumed.id, document.id);
        assert_eq!(resumed.remaining_continues, 0);
        assert_eq!(resumed.attempt(), 4);
        assert!(matches!(resumed.step, SavedStep::MissionEntry { .. }));
    }

    #[test]
    fn completed_m01_projects_live_exit_equipment_instead_of_entry() {
        let mut state = state_with_map();
        let hash = state.map.content_sha256().unwrap();
        let initial = RunDocument::new(Uuid::new_v4(), CampaignRules::default(), hash);
        state.load_campaign_run(&initial).unwrap();
        let owner = Uuid::new_v4();
        state.add_player(owner, "Run owner".into(), Role::Human);
        state.acknowledge_mission(
            owner,
            crate::protocol::MissionReady {
                id: MissionId::RecallNotice,
                attempt: 1,
            },
        );
        let player = state.players.iter_mut().find(|p| p.id == owner).unwrap();
        player.inventory.grant_weapon(WeaponType::Tack);
        player.inventory.try_fire(WeaponType::Tack);
        player.weapon = WeaponType::Tack;
        player.hp = 54;
        player.armor = 12;
        let saved_exit = SavedEntry::from_player(player).unwrap();
        let run = state.mission.as_mut().unwrap();
        run.phase = crate::protocol::MissionPhase::Departed;
        let solo = run.solo.as_mut().unwrap();
        solo.capture_exit(saved_exit);
        solo.state.status = CampaignRunStatus::Complete;
        let completed = state.campaign_run_document().unwrap().unwrap();
        completed.validate(hash).unwrap();
        match &completed.step {
            SavedStep::AwaitingMission {
                completed_mission,
                next_mission,
                exit,
            } => {
                assert_eq!(*completed_mission, MissionId::RecallNotice);
                assert_eq!(next_mission, NEXT_MISSION);
                assert_eq!((exit.hp, exit.armor), (54, 12));
                assert_eq!(exit.equipment.selected, WeaponType::Tack);
                assert_eq!(exit.equipment.weapons.len(), 2);
            }
            _ => panic!("completed run did not retain its live exit"),
        }
        let directory =
            std::env::temp_dir().join(format!("fragr-completed-run-{}", Uuid::new_v4()));
        let store = store::RunStore::open(&directory, hash).unwrap();
        store.save(&completed).unwrap();
        assert!(matches!(
            store::RunStore::inspect(&directory, hash).unwrap(),
            store::RunProbe::Compatible(document) if document == completed
        ));
        assert!(state_with_map().load_campaign_run(&completed).is_err());
        state.remove_player(owner);
        assert_eq!(state.campaign_run_document().unwrap(), Some(completed));
        drop(store);
        std::fs::remove_dir_all(directory).unwrap();
    }
}
