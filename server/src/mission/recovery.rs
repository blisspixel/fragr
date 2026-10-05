//! One explicit solo run. Entry state contains no live controller or clock.
use super::*;
use crate::inventory::Inventory;
use crate::mission::run_file::{RunDocument, SavedEntry, SavedStep};
use crate::protocol::{
    BodyKind, CampaignRunState, CampaignRunStatus, MissionContinue, WeaponType, CAMPAIGN_CONTINUES,
};

#[cfg(test)]
mod tests;

pub(super) struct SoloRun {
    pub state: CampaignRunState,
    pub carried_recall_cars: Vec<String>,
    pub carried_patients: Vec<String>,
    pub carried_photos: u32,
    pub carried_released_workers: Vec<String>,
    pub carried_evacuated_workers: Vec<String>,
    /// M06's optional prisoner route, retained unchanged through M07.
    pub carried_prisoner_route_marked: bool,
    pub carried_archive: Option<crate::protocol::M08Outcome>,
    pub carried_berth: Option<super::run_file::M09Outcome>,
    pub carried_transit: Option<crate::protocol::M10Transit>,
    owner: Option<Uuid>,
    entry: Option<Entry>,
    saved_entry: Option<SavedEntry>,
    exit: Option<SavedEntry>,
    body: Option<BodyKind>,
}

struct Entry {
    position: [f32; 3],
    yaw: f32,
    pitch: f32,
    hp: i32,
    armor: i32,
    weapon: WeaponType,
    inventory: Inventory,
    score: u32,
}

impl SoloRun {
    pub fn owner(&self) -> Option<Uuid> {
        self.owner
    }

    pub fn saved_entry(&self) -> Option<SavedEntry> {
        self.entry
            .as_ref()
            .and_then(|entry| {
                let saved = SavedEntry {
                    hp: entry.hp,
                    armor: entry.armor,
                    equipment: entry.inventory.saved_equipment(entry.weapon)?,
                };
                Some(saved)
            })
            .or_else(|| self.saved_entry.clone())
    }

    pub fn saved_exit(&self) -> Option<&SavedEntry> {
        self.exit.as_ref()
    }

    pub fn body(&self) -> Option<BodyKind> {
        self.body
    }

    pub fn capture_exit(&mut self, exit: SavedEntry) {
        self.exit = Some(exit);
    }

    pub fn playing(&self) -> bool {
        self.state.status == CampaignRunStatus::Playing
    }

    pub fn capture_entry(&mut self, player: &Player, score: u32) {
        if self.owner != Some(player.id) || self.entry.is_some() {
            return;
        }
        self.entry = Some(Entry {
            position: [player.x, player.y, player.z],
            yaw: player.yaw,
            pitch: player.pitch,
            hp: player.hp,
            armor: player.armor,
            weapon: player.weapon,
            inventory: player.inventory.clone(),
            score,
        });
        self.saved_entry = self.saved_entry();
    }
}

impl GameState {
    pub(crate) fn campaign_run_body(&self) -> Option<BodyKind> {
        self.mission
            .as_ref()
            .and_then(|mission| mission.solo.as_ref())
            .and_then(SoloRun::body)
    }

    pub fn enable_campaign_run(&mut self) -> Result<(), &'static str> {
        if self.tick != 0 || !self.players.is_empty() {
            return Err("campaign run must be configured before admission");
        }
        let mission = self
            .mission
            .as_mut()
            .ok_or("campaign run requires a mission")?;
        if mission.solo.is_some() {
            return Err("campaign run is already configured");
        }
        mission.solo = Some(SoloRun {
            state: CampaignRunState {
                id: Uuid::new_v4(),
                status: CampaignRunStatus::Playing,
                continues: CAMPAIGN_CONTINUES,
                level_start_continues: CAMPAIGN_CONTINUES,
            },
            carried_berth: None,
            carried_transit: None,
            owner: None,
            carried_recall_cars: Vec::new(),
            carried_patients: Vec::new(),
            carried_photos: 0,
            carried_released_workers: Vec::new(),
            carried_evacuated_workers: Vec::new(),
            carried_prisoner_route_marked: false,
            carried_archive: None,
            entry: None,
            saved_entry: None,
            exit: None,
            body: None,
        });
        Ok(())
    }

    pub(crate) fn load_campaign_run(&mut self, document: &RunDocument) -> Result<(), &'static str> {
        if self.tick != 0 || !self.players.is_empty() {
            return Err("campaign run must be loaded before admission");
        }
        let hash = self
            .map
            .content_sha256()
            .ok_or("campaign run requires authored content")?;
        document.validate(hash)?;
        if self.map.campaign_mission_id() != Some(document.stage_mission()) {
            return Err("saved campaign run names another mission");
        }
        let (status, entry) = match &document.step {
            SavedStep::MissionEntry { entry, .. } => (CampaignRunStatus::Playing, entry),
            SavedStep::PendingContinue { entry, .. } => (CampaignRunStatus::Continue, entry),
            SavedStep::Failed { .. }
            | SavedStep::Abandoned { .. }
            | SavedStep::AwaitingMission { .. } => {
                return Err("saved campaign run is not playable")
            }
        };
        self.enable_campaign_run()?;
        let run = self.mission.as_mut().ok_or("campaign mission is missing")?;
        run.rules = document.rules;
        run.attempt = document.attempt();
        let solo = run.solo.as_mut().ok_or("campaign run is missing")?;
        solo.state = CampaignRunState {
            id: document.id,
            status,
            continues: document.remaining_continues,
            level_start_continues: document.level_start_continues,
        };
        solo.saved_entry = Some(entry.clone());
        solo.body = document.body;
        solo.carried_recall_cars = document
            .m03_outcome
            .as_ref()
            .map(|outcome| outcome.liberated_cars.clone())
            .unwrap_or_default();
        solo.carried_patients = document
            .m04_outcome
            .as_ref()
            .map_or_else(Vec::new, |outcome| outcome.rescued_patients.clone());
        solo.carried_photos = document
            .m04_outcome
            .as_ref()
            .map_or(0, |outcome| outcome.photos_completed);
        solo.carried_released_workers = document
            .m05_outcome
            .as_ref()
            .map_or_else(Vec::new, |outcome| outcome.released_workers.clone());
        solo.carried_evacuated_workers = document
            .m05_outcome
            .as_ref()
            .map_or_else(Vec::new, |outcome| outcome.evacuated_workers.clone());
        solo.carried_prisoner_route_marked = document
            .m06_outcome
            .as_ref()
            .is_some_and(|outcome| outcome.prisoner_route_marked);
        solo.carried_archive = document.m08_outcome.clone();
        solo.carried_berth = document.m09_outcome.clone();
        solo.carried_transit = document.m10_transit.clone();
        if let Some(progress) = &mut run.m09 {
            let g = run
                .initial_map
                .m09_geometry()
                .ok_or("M09 geometry missing")?;
            *progress = m09::M09Progress::new(
                &g,
                !solo.carried_patients.is_empty(),
                solo.carried_evacuated_workers
                    .iter()
                    .any(|id| id == "splice"),
            );
        }
        Ok(())
    }

    /// The transport reserves one lifetime seat; the authority also prevents
    /// direct command injection from replacing its owner after departure.
    pub(crate) fn admit_campaign_owner(&mut self, id: Uuid) -> bool {
        let Some(solo) = self.mission.as_mut().and_then(|run| run.solo.as_mut()) else {
            return true;
        };
        if solo.owner.is_some()
            || !matches!(
                solo.state.status,
                CampaignRunStatus::Playing | CampaignRunStatus::Continue
            )
        {
            return false;
        }
        solo.owner = Some(id);
        true
    }

    pub(crate) fn restore_campaign_owner(
        &mut self,
        player: &mut Player,
    ) -> Result<(), &'static str> {
        let Some(run) = self.mission.as_mut() else {
            return Ok(());
        };
        let Some(solo) = run.solo.as_mut() else {
            return Ok(());
        };
        if solo.owner != Some(player.id) {
            return Ok(());
        }
        if let Some(body) = solo.body {
            player.body = body;
        } else {
            solo.body = Some(player.body);
        }
        let Some(saved) = solo.saved_entry.as_ref() else {
            return Ok(());
        };
        player.hp = saved.hp;
        player.armor = saved.armor;
        player.weapon = saved.equipment.selected;
        player.inventory.restore_saved_equipment(&saved.equipment)?;
        solo.capture_entry(player, 0);
        if solo.state.status == CampaignRunStatus::Continue {
            player.hp = 0;
            player.respawn_timer = None;
            player.clear_input();
            run.phase = if run.m02.is_some()
                || run.m03.is_some()
                || run.m04.is_some()
                || run.m05.is_some()
                || run.m06.is_some()
                || run.m08.is_some()
                || run.m07.is_some()
                || run.m09.is_some()
                || run.m10.is_some()
                || run.m11.is_some()
            {
                MissionPhase::InProgress
            } else {
                MissionPhase::FindTransfer
            };
            run.ready.insert(player.id);
            run.started = true;
        }
        Ok(())
    }

    pub(crate) fn update_campaign_run(&mut self) {
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let Some(solo) = run.solo.as_mut() else {
            return;
        };
        if matches!(
            solo.state.status,
            CampaignRunStatus::Complete | CampaignRunStatus::Failed
        ) {
            return;
        }
        let Some(owner) = solo.owner else { return };
        let player = self.players.iter_mut().find(|p| p.id == owner);
        let status = match player {
            None => CampaignRunStatus::Abandoned,
            Some(player) if solo.playing() && player.hp <= 0 => {
                player.respawn_timer = None;
                player.clear_input();
                player.inventory.release_trigger();
                if solo.state.continues == 0 {
                    CampaignRunStatus::Failed
                } else {
                    CampaignRunStatus::Continue
                }
            }
            Some(_) => return,
        };
        if status == solo.state.status {
            return;
        }
        solo.state.status = status;
        run.changed_at = self.tick;
        for player in &mut self.players {
            player.clear_input();
            player.just_fired = false;
        }
        tracing::info!(
            ?status,
            remaining = solo.state.continues,
            "Campaign run stopped"
        );
    }

    pub(crate) fn campaign_run_frozen(&self) -> bool {
        self.mission
            .as_ref()
            .and_then(|run| run.solo.as_ref())
            .is_some_and(|solo| !solo.playing())
    }

    pub fn continue_mission(&mut self, player_id: Uuid, request: MissionContinue) -> bool {
        let Some(run) = self.mission.as_mut() else {
            return false;
        };
        let Some(solo) = run.solo.as_mut() else {
            return false;
        };
        if self.map.campaign_mission_id() != Some(request.id)
            || request.run_id != solo.state.id
            || request.attempt != run.attempt
            || solo.owner != Some(player_id)
            || solo.state.status != CampaignRunStatus::Continue
            || solo.state.continues == 0
        {
            return false;
        }
        let Some(entry) = &solo.entry else {
            return false;
        };
        let Some(player) = self
            .players
            .iter_mut()
            .find(|p| p.id == player_id && p.hp <= 0)
        else {
            return false;
        };
        [player.x, player.y, player.z] = entry.position;
        player.yaw = entry.yaw;
        player.pitch = entry.pitch;
        player.vy = 0.0;
        player.hp = entry.hp;
        player.armor = entry.armor;
        player.weapon = entry.weapon;
        player.inventory.restore_entry(&entry.inventory);
        player.clear_input();
        player.just_fired = false;
        player.fire_cooldown = 0;
        player.respawn_timer = None;
        player.killstreak = 0;
        self.scores.insert(player_id, entry.score);
        self.spawn_shields.clear();
        solo.state.continues -= 1;
        solo.state.status = CampaignRunStatus::Playing;
        self.reset_mission();
        self.reset_campaign_encounters();
        self.ensure_m03_companion();
        self.ensure_m04_companion();
        self.ensure_m05_companion();
        self.ensure_m06_companion();
        self.ensure_m08_companion();
        self.ensure_m07_companion();
        self.ensure_m09_companion();
        self.ensure_m10_companion();
        self.shot_results.clear();
        tracing::info!(
            attempt = request.attempt + 1,
            "Campaign continue spent; mission entry restored"
        );
        true
    }
}
