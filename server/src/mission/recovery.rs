//! One explicit solo run. Entry state contains no live controller or clock.
use super::*;
use crate::inventory::Inventory;
use crate::protocol::{
    CampaignRunState, CampaignRunStatus, MissionContinue, WeaponType, CAMPAIGN_CONTINUES,
};

#[cfg(test)]
mod tests;

pub(super) struct SoloRun {
    pub state: CampaignRunState,
    owner: Option<Uuid>,
    entry: Option<Entry>,
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
    }
}

impl GameState {
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
            },
            owner: None,
            entry: None,
        });
        Ok(())
    }

    /// The transport reserves one lifetime seat; the authority also prevents
    /// direct command injection from replacing its owner after departure.
    pub(crate) fn admit_campaign_owner(&mut self, id: Uuid) -> bool {
        let Some(solo) = self.mission.as_mut().and_then(|run| run.solo.as_mut()) else {
            return true;
        };
        if solo.owner.is_some() || !solo.playing() {
            return false;
        }
        solo.owner = Some(id);
        true
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
                player.inventory.cancel_reload();
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
        if self.map.mission().is_none_or(|map| map.id != request.id)
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
        self.shot_results.clear();
        tracing::info!(
            attempt = request.attempt + 1,
            "Campaign continue spent; mission entry restored"
        );
        true
    }
}
