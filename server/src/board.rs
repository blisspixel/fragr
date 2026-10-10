//! Process-local wire. The floor is the room's speak. Notices stay until this
//! process ends. Nothing here is a combat fact, and nothing is written to disk.

use std::collections::{HashMap, VecDeque};
use std::net::IpAddr;

use crate::sim::{SPEAK_COOLDOWN_TICKS, SPEAK_MAX_CHARS};

const NOTICE_ADDRESSES: usize = 256;
const NOTICES_PER_SECOND: usize = 8;
const NOTICE_WINDOW_TICKS: u64 = 20;

pub const BOARD_FLOOR: &str = "floor";
pub const BOARD_NOTICES: &str = "notices";
const MAX_LINES: usize = 40;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Line {
    pub tick: u64,
    pub name: String,
    pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fault {
    Unknown,
    Closed,
    Rejected,
    RateLimited,
}

impl Fault {
    pub fn code(self) -> &'static str {
        match self {
            Self::Unknown => "board_unknown",
            Self::Closed => "board_closed",
            Self::Rejected => "board_rejected",
            Self::RateLimited => "board_rate_limited",
        }
    }
}

#[derive(Debug, Default)]
pub struct Board {
    floor: Vec<Line>,
    notices: Vec<Line>,
    last_notice: HashMap<IpAddr, u64>,
    notice_ticks: VecDeque<u64>,
}

impl Board {
    pub fn note_floor(&mut self, name: &str, text: &str, tick: u64) {
        if name.is_empty() || text.is_empty() {
            return;
        }
        push(
            &mut self.floor,
            Line {
                tick,
                name: name.to_string(),
                text: text.to_string(),
            },
        );
    }

    pub fn list(&self) -> [(&'static str, usize); 2] {
        [
            (BOARD_FLOOR, self.floor.len()),
            (BOARD_NOTICES, self.notices.len()),
        ]
    }

    pub fn read(&self, board: &str) -> Result<&[Line], Fault> {
        match board {
            BOARD_FLOOR => Ok(&self.floor),
            BOARD_NOTICES => Ok(&self.notices),
            _ => Err(Fault::Unknown),
        }
    }

    pub fn post(
        &mut self,
        peer: IpAddr,
        name: &str,
        board: &str,
        raw: &str,
        tick: u64,
    ) -> Result<Line, Fault> {
        if board != BOARD_NOTICES {
            return Err(if board == BOARD_FLOOR {
                Fault::Closed
            } else {
                Fault::Unknown
            });
        }
        if name.is_empty() {
            return Err(Fault::Rejected);
        }
        let text = accept_line(raw)?;
        if let Some(last) = self.last_notice.get(&peer) {
            if tick.saturating_sub(*last) < SPEAK_COOLDOWN_TICKS {
                return Err(Fault::RateLimited);
            }
        }
        self.notice_ticks
            .retain(|posted| tick.saturating_sub(*posted) < NOTICE_WINDOW_TICKS);
        if self.notice_ticks.len() >= NOTICES_PER_SECOND {
            return Err(Fault::RateLimited);
        }
        let line = Line {
            tick,
            name: name.to_string(),
            text,
        };
        push(&mut self.notices, line.clone());
        if self.last_notice.len() >= NOTICE_ADDRESSES && !self.last_notice.contains_key(&peer) {
            if let Some(oldest) = self
                .last_notice
                .iter()
                .min_by_key(|(_, posted)| *posted)
                .map(|(ip, _)| *ip)
            {
                self.last_notice.remove(&oldest);
            }
        }
        self.last_notice.insert(peer, tick);
        self.notice_ticks.push_back(tick);
        Ok(line)
    }
}

fn accept_line(raw: &str) -> Result<String, Fault> {
    let trimmed: String = raw.trim().chars().take(SPEAK_MAX_CHARS + 1).collect();
    if trimmed.is_empty()
        || trimmed.chars().count() > SPEAK_MAX_CHARS
        || trimmed.chars().any(char::is_control)
    {
        return Err(Fault::Rejected);
    }
    Ok(trimmed)
}

fn push(buf: &mut Vec<Line>, line: Line) {
    if buf.len() == MAX_LINES {
        buf.remove(0);
    }
    buf.push(line);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notices_keep_a_trimmed_line_and_the_floor_does_not_take_posts() {
        let mut board = Board::default();
        let who: IpAddr = "203.0.113.10".parse().unwrap();
        let line = board
            .post(who, "Meat Proxy", BOARD_NOTICES, "  still here  ", 10)
            .unwrap();
        assert_eq!(line.text, "still here");
        assert_eq!(board.read(BOARD_NOTICES).unwrap(), &[line]);
        assert_eq!(
            board
                .post(who, "Meat Proxy", BOARD_FLOOR, "nope", 80)
                .unwrap_err(),
            Fault::Closed
        );
        assert!(board.read("mail").is_err());
        assert_eq!(board.list()[1], (BOARD_NOTICES, 1));
    }

    #[test]
    fn a_notice_waits_out_the_same_gap_as_a_callout() {
        let mut board = Board::default();
        let who: IpAddr = "203.0.113.10".parse().unwrap();
        let other: IpAddr = "203.0.113.11".parse().unwrap();
        board.post(who, "Probe", BOARD_NOTICES, "one", 0).unwrap();
        assert_eq!(
            board
                .post(who, "Probe", BOARD_NOTICES, "two", 59)
                .unwrap_err(),
            Fault::RateLimited
        );
        assert!(board
            .post(other, "Probe", BOARD_NOTICES, "side", 19)
            .is_ok());
        assert!(board.post(who, "Probe", BOARD_NOTICES, "two", 60).is_ok());
        let mut crowded = Board::default();
        for index in 0..NOTICES_PER_SECOND {
            let ip = IpAddr::from([203, 0, 113, index as u8 + 1]);
            crowded
                .post(ip, "Probe", BOARD_NOTICES, "burst", 100)
                .unwrap();
        }
        assert_eq!(
            crowded
                .post(
                    IpAddr::from([203, 0, 113, 200]),
                    "Probe",
                    BOARD_NOTICES,
                    "burst",
                    100
                )
                .unwrap_err(),
            Fault::RateLimited
        );
    }

    #[test]
    fn empty_control_and_long_lines_stay_off_the_board() {
        let mut board = Board::default();
        let who: IpAddr = "203.0.113.10".parse().unwrap();
        for raw in ["", "   ", "line\nbreak", &"x".repeat(SPEAK_MAX_CHARS + 1)] {
            assert_eq!(
                board.post(who, "Probe", BOARD_NOTICES, raw, 0).unwrap_err(),
                Fault::Rejected
            );
        }
        assert!(board.read(BOARD_NOTICES).unwrap().is_empty());
    }

    #[test]
    fn the_oldest_line_leaves_when_the_board_is_full() {
        let mut board = Board::default();
        for index in 0..MAX_LINES + 1 {
            board.note_floor("Fox", &format!("line {index}"), index as u64);
        }
        let floor = board.read(BOARD_FLOOR).unwrap();
        assert_eq!(floor.len(), MAX_LINES);
        assert_eq!(floor[0].text, "line 1");
        assert_eq!(floor.last().unwrap().text, format!("line {MAX_LINES}"));
    }
}
