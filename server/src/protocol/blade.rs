//! Article Blade plinth and possession facts.
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArticleBladePhase {
    Available,
    Held,
    Cooling,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArticleBladeInfo {
    pub pickup_id: String,
    pub feet: [f32; 3],
    pub return_ticks: u32,
}

impl ArticleBladeInfo {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.pickup_id.is_empty()
            || self.pickup_id.len() > 64
            || !self
                .pickup_id
                .bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
        {
            return Err("invalid article blade pickup id");
        }
        if !self.feet.iter().all(|c| c.is_finite()) {
            return Err("invalid article blade coordinates");
        }
        if self.return_ticks == 0 || self.return_ticks > 3600 {
            return Err("invalid article blade return ticks");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArticleBladeState {
    pub pickup_id: String,
    pub phase: ArticleBladePhase,
    pub uses_left: u16,
    pub changed_at: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub holder: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub return_in: Option<u32>,
}

impl ArticleBladeState {
    pub fn validate(&self, return_ticks: u32) -> Result<(), &'static str> {
        if self.pickup_id.is_empty()
            || self.pickup_id.len() > 64
            || !self
                .pickup_id
                .bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
        {
            return Err("invalid article blade pickup id");
        }
        match self.phase {
            ArticleBladePhase::Available => {
                if self.uses_left != 0 || self.holder.is_some() || self.return_in.is_some() {
                    return Err("available article blade cannot have holder, uses or return timer");
                }
            }
            ArticleBladePhase::Held => {
                if !(1..=12).contains(&self.uses_left)
                    || self.holder.is_none()
                    || self.return_in.is_some()
                {
                    return Err(
                        "held article blade requires holder and 1..=12 uses with no return timer",
                    );
                }
            }
            ArticleBladePhase::Cooling => {
                if self.uses_left != 0 || self.holder.is_some() {
                    return Err("cooling article blade cannot have holder or uses");
                }
                let Some(remaining) = self.return_in else {
                    return Err("cooling article blade requires return timer");
                };
                if remaining == 0 || remaining > return_ticks {
                    return Err("cooling article blade return timer out of bounds");
                }
            }
        }
        Ok(())
    }
}
