//! Retained capture-point facts. The server owns progress and ticket loss.
use super::{Team, TeamScores};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CapturePoint {
    pub id: String,
    pub position: [f32; 3],
    pub radius: f32,
    pub owner: Option<Team>,
    pub capturing: Option<Team>,
    pub progress: u16,
    pub contested: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConquestState {
    pub tickets: TeamScores,
    pub initial_tickets: u32,
    pub capture_ticks: u16,
    pub points: Vec<CapturePoint>,
}
