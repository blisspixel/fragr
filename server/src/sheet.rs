//! The night card for one process: rounds that finished, and the busiest room.
//!
//! The public probe receives the three counts. Callsigns stay on the desk
//! and in the `SHEET` log line this module returns.

use crate::protocol::NightTotals;
use std::collections::VecDeque;

/// Shows kept for the desk. The finished-round count is not capped.
const RETAINED: usize = 32;

/// One finished show. The log line is this value as JSON.
#[derive(Debug, Clone, serde::Serialize)]
pub(crate) struct RoundNote {
    pub round: u32,
    pub map: String,
    pub mode: String,
    pub reason: String,
    pub mvp: Option<String>,
    pub frags: u32,
    pub humans: u32,
    pub fighters: u32,
}

#[derive(Debug, Default)]
pub(crate) struct NightSheet {
    rounds_finished: u64,
    peak_humans: u32,
    peak_fighters: u32,
    rows: VecDeque<RoundNote>,
}

impl NightSheet {
    pub(crate) fn note_presence(&mut self, humans: u32, fighters: u32) {
        self.peak_humans = self.peak_humans.max(humans);
        self.peak_fighters = self.peak_fighters.max(fighters);
    }

    /// Record the show that just ended. Returns the `SHEET` JSON line.
    pub(crate) fn finish(&mut self, note: RoundNote) -> String {
        self.rounds_finished = self.rounds_finished.saturating_add(1);
        self.rows.push_back(note);
        while self.rows.len() > RETAINED {
            self.rows.pop_front();
        }
        self.rows
            .back()
            .and_then(|note| serde_json::to_string(note).ok())
            .unwrap_or_default()
    }

    pub(crate) fn totals(&self) -> NightTotals {
        NightTotals {
            rounds_finished: self.rounds_finished,
            peak_humans: self.peak_humans,
            peak_fighters: self.peak_fighters,
        }
    }

    pub(crate) fn desk_text(&self) -> String {
        let mut lines = vec![
            "Night sheet".to_string(),
            format!("rounds {}", self.rounds_finished),
            format!("peak humans {}", self.peak_humans),
            format!("peak fighters {}", self.peak_fighters),
        ];
        if self.rounds_finished == 0 {
            lines.push("No round has finished.".to_string());
            return lines.join("\n");
        }
        if self.rounds_finished > self.rows.len() as u64 {
            lines.push(format!(
                "showing latest {} of {}",
                self.rows.len(),
                self.rounds_finished
            ));
        }
        for note in self.rows.iter().rev() {
            let podium = note.mvp.as_deref().unwrap_or("no podium");
            lines.push(format!(
                "{}  {}  {}  {}  {}  {}  humans {}  fighters {}",
                note.round,
                note.map,
                note.mode,
                note.reason,
                podium,
                note.frags,
                note.humans,
                note.fighters
            ));
        }
        lines.join("\n")
    }
}

/// Campaign maps have no arcade rule set. An arcade map uses its mode id.
pub(crate) fn mode_label(campaign: bool, mode_id: Option<&str>) -> String {
    if campaign {
        "campaign".to_string()
    } else {
        mode_id.unwrap_or("ffa").to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn note(round: u32, map: &str, mvp: Option<&str>) -> RoundNote {
        RoundNote {
            round,
            map: map.to_string(),
            mode: "ffa".to_string(),
            reason: "Frag limit reached".to_string(),
            mvp: mvp.map(str::to_string),
            frags: 12,
            humans: 1,
            fighters: 5,
        }
    }

    #[test]
    fn peaks_stay_at_the_busiest_room() {
        let mut sheet = NightSheet::default();
        sheet.note_presence(1, 4);
        sheet.note_presence(0, 1);
        let totals = sheet.totals();
        assert_eq!(totals.peak_humans, 1);
        assert_eq!(totals.peak_fighters, 4);
        assert_eq!(totals.rounds_finished, 0);
        assert_eq!(
            sheet.desk_text(),
            "Night sheet\nrounds 0\npeak humans 1\npeak fighters 4\nNo round has finished."
        );
    }

    #[test]
    fn a_finished_show_names_the_podium_on_the_desk_only() {
        let mut sheet = NightSheet::default();
        sheet.note_presence(2, 6);
        let line = sheet.finish(note(1, "Arena Duel", Some("Meat Proxy")));
        assert!(line.contains("\"map\":\"Arena Duel\""), "{line}");
        assert!(line.contains("\"mvp\":\"Meat Proxy\""), "{line}");
        assert!(line.contains("\"mode\":\"ffa\""), "{line}");
        assert!(!line.contains("203.0.113"), "{line}");
        let text = sheet.desk_text();
        assert!(text.contains("Meat Proxy"), "{text}");
        assert!(
            text.contains("1  Arena Duel  ffa  Frag limit reached"),
            "{text}"
        );
        assert!(!text.contains("203.0.113"), "{text}");
        assert!(!text.contains("192.168"), "{text}");
        let public = serde_json::to_string(&sheet.totals()).unwrap();
        assert!(!public.contains("mvp"), "{public}");
        assert!(!public.contains("Meat"), "{public}");
        assert!(public.contains("\"rounds_finished\":1"), "{public}");
    }

    #[test]
    fn a_show_without_a_score_says_no_podium() {
        let mut sheet = NightSheet::default();
        sheet.finish(note(4, "Sector 9", None));
        let text = sheet.desk_text();
        assert!(text.contains("no podium"), "{text}");
        assert!(!text.contains("No round has finished."), "{text}");
    }

    #[test]
    fn the_card_keeps_the_latest_shows_and_the_full_count() {
        let mut sheet = NightSheet::default();
        for round in 1..=33 {
            let map = if round == 1 { "Gone" } else { "Kept" };
            sheet.finish(note(round, map, None));
        }
        assert_eq!(sheet.totals().rounds_finished, 33);
        let text = sheet.desk_text();
        assert!(text.contains("showing latest 32 of 33"), "{text}");
        assert!(text.contains("33  Kept"), "{text}");
        assert!(!text.contains("Gone"), "{text}");
        assert!(!text.lines().any(|line| line.starts_with("1  ")), "{text}");
    }

    #[test]
    fn campaign_keeps_its_own_label() {
        assert_eq!(mode_label(true, Some("ffa")), "campaign");
        assert_eq!(mode_label(false, Some("tdm")), "tdm");
        assert_eq!(mode_label(false, None), "ffa");
    }
}
