//! Head-to-head: who has fragged whom, by callsign. The server keeps it for
//! its own life; a desktop host also keeps it on disk, so the book on Larak
//! Lot carries from one night to the next. It is a local record, not an
//! account or a ledger anyone else can check: a callsign is whatever the
//! fighter typed.
//!
//! One schema. A file of any other version, or one that does not read, is
//! refused with a clear message and the book starts fresh; the next save
//! replaces it.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::io::{self, Read, Write};
use std::path::Path;

/// The only file version this build reads or writes.
pub const HEAD_TO_HEAD_VERSION: u32 = 1;
/// Pairs kept. A long-lived public host meets a lot of callsigns; past this
/// the book stops taking new pairs and keeps counting the ones it has.
pub const MAX_PAIRS: usize = 4096;
const MAX_BYTES: u64 = 512 * 1024;
const MAX_NAME_CHARS: usize = 32;

/// One callsign's frags on another.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HeadToHeadPair {
    pub killer: String,
    pub victim: String,
    pub frags: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    version: u32,
    pairs: Vec<HeadToHeadPair>,
}

/// Frags between callsigns. Names compare without case and without a rule
/// bot's `-N` overflow suffix, so Nightfall is Nightfall whichever seat.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HeadToHead {
    /// (killer, victim) keys to frags.
    pairs: BTreeMap<(String, String), u32>,
    /// Key to the callsign as last written.
    names: BTreeMap<String, String>,
    /// Changed since the last save.
    dirty: bool,
}

fn key(name: &str) -> String {
    crate::protocol::rule_bot_callsign_base(name.trim()).to_lowercase()
}

fn valid_name(name: &str) -> bool {
    let trimmed = name.trim();
    !trimmed.is_empty()
        && trimmed.chars().count() <= MAX_NAME_CHARS
        && !trimmed.chars().any(char::is_control)
}

impl HeadToHead {
    /// One frag by `killer` on `victim`. A fighter fragging a copy of its own
    /// callsign, or a name the book cannot hold, is not a meeting.
    pub fn record(&mut self, killer: &str, victim: &str) {
        if !valid_name(killer) || !valid_name(victim) {
            return;
        }
        let pair = (key(killer), key(victim));
        if pair.0 == pair.1 || (!self.pairs.contains_key(&pair) && self.pairs.len() >= MAX_PAIRS) {
            return;
        }
        for name in [killer, victim] {
            let base = crate::protocol::rule_bot_callsign_base(name.trim());
            self.names.insert(key(name), base.to_string());
        }
        let frags = self.pairs.entry(pair).or_insert(0);
        *frags = frags.saturating_add(1);
        self.dirty = true;
    }

    /// Frags `killer` has on `victim`.
    pub fn frags(&self, killer: &str, victim: &str) -> u32 {
        self.pairs
            .get(&(key(killer), key(victim)))
            .copied()
            .unwrap_or(0)
    }

    /// How far `name` is behind `opponent`: their frags on it less its own
    /// on them. Positive means `name` owes `opponent` one.
    pub fn deficit(&self, name: &str, opponent: &str) -> i64 {
        i64::from(self.frags(opponent, name)) - i64::from(self.frags(name, opponent))
    }

    /// The opponent among `present` that `name` owes most, if it owes anyone.
    pub fn grudge<'a>(
        &self,
        name: &str,
        present: impl IntoIterator<Item = &'a str>,
    ) -> Option<&'a str> {
        present
            .into_iter()
            .filter(|opponent| key(opponent) != key(name))
            .map(|opponent| (opponent, self.deficit(name, opponent)))
            .filter(|(_, owed)| *owed > 0)
            .max_by(|a, b| a.1.cmp(&b.1).then_with(|| b.0.cmp(a.0)))
            .map(|(opponent, _)| opponent)
    }

    pub fn is_dirty(&self) -> bool {
        self.dirty
    }

    fn document(&self) -> Document {
        Document {
            version: HEAD_TO_HEAD_VERSION,
            pairs: self
                .pairs
                .iter()
                .map(|((killer, victim), frags)| HeadToHeadPair {
                    killer: self
                        .names
                        .get(killer)
                        .cloned()
                        .unwrap_or_else(|| killer.clone()),
                    victim: self
                        .names
                        .get(victim)
                        .cloned()
                        .unwrap_or_else(|| victim.clone()),
                    frags: *frags,
                })
                .collect(),
        }
    }

    /// Read a book from JSON. Anything but the current version, a bad name,
    /// a repeated pair or too many pairs is refused whole.
    pub fn from_json(text: &str) -> Result<Self, String> {
        let document: Document = serde_json::from_str(text)
            .map_err(|error| format!("not a head-to-head file: {error}"))?;
        if document.version != HEAD_TO_HEAD_VERSION {
            return Err(format!(
                "head-to-head version {} is not {HEAD_TO_HEAD_VERSION}",
                document.version
            ));
        }
        if document.pairs.len() > MAX_PAIRS {
            return Err(format!("more than {MAX_PAIRS} head-to-head pairs"));
        }
        let mut book = Self::default();
        for pair in document.pairs {
            if !valid_name(&pair.killer) || !valid_name(&pair.victim) || pair.frags == 0 {
                return Err("a head-to-head pair has a bad name or no frags".into());
            }
            let keys = (key(&pair.killer), key(&pair.victim));
            if keys.0 == keys.1 || book.pairs.insert(keys.clone(), pair.frags).is_some() {
                return Err("a head-to-head pair repeats or names one fighter twice".into());
            }
            book.names.insert(keys.0, pair.killer.trim().to_string());
            book.names.insert(keys.1, pair.victim.trim().to_string());
        }
        Ok(book)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(&self.document()).expect("head-to-head document serializes")
    }

    /// Open the book at `path`. A missing file is an empty book; a file
    /// this build refuses is an empty book and the reason, for the log.
    pub fn load(path: &Path) -> (Self, Option<String>) {
        let file = match std::fs::File::open(path) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return (Self::default(), None)
            }
            Err(error) => {
                return (
                    Self::default(),
                    Some(format!("{} could not be opened: {error}", path.display())),
                )
            }
        };
        let mut text = String::new();
        if let Err(error) = file.take(MAX_BYTES + 1).read_to_string(&mut text) {
            return (
                Self::default(),
                Some(format!("{} could not be read: {error}", path.display())),
            );
        }
        if text.len() as u64 > MAX_BYTES {
            return (
                Self::default(),
                Some(format!(
                    "{} is larger than {MAX_BYTES} bytes",
                    path.display()
                )),
            );
        }
        match Self::from_json(&text) {
            Ok(book) => (book, None),
            Err(reason) => (
                Self::default(),
                Some(format!("{}: {reason}", path.display())),
            ),
        }
    }

    /// Write the book to `path` through a temporary file and a rename, so a
    /// crash leaves the last good book. Clears the changed mark on success.
    pub fn save(&mut self, path: &Path) -> io::Result<()> {
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            std::fs::create_dir_all(parent)?;
        }
        let temporary = path.with_extension(format!("json.{}.tmp", std::process::id()));
        let result = (|| {
            let mut file = std::fs::File::create(&temporary)?;
            file.write_all(self.to_json().as_bytes())?;
            file.write_all(b"\n")?;
            file.sync_all()?;
            std::fs::rename(&temporary, path)
        })();
        if result.is_err() {
            let _ = std::fs::remove_file(&temporary);
        } else {
            self.dirty = false;
        }
        result
    }
}

#[cfg(test)]
mod tests;
