//! Host-owned ban and allow lists. Entries are addresses or CIDR ranges, never
//! callsigns: without accounts anyone can take any name. A malformed file stops
//! the process at start. A later bad edit keeps the last good list and logs why.

use std::net::IpAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::watch;

/// A list is a text file a host edits by hand. One megabyte is far beyond that.
const MAX_FILE_BYTES: u64 = 1024 * 1024;
const MAX_ENTRIES: usize = 10_000;
const MAX_REASON_CHARS: usize = 200;
/// How often the files are read again. An edit takes effect within this time.
pub const RELOAD_EVERY: Duration = Duration::from_secs(5);

/// Paths the host passed on the command line. Both empty means no list.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AccessConfig {
    pub ban_list: Option<PathBuf>,
    pub allow_list: Option<PathBuf>,
}

impl AccessConfig {
    pub fn is_empty(&self) -> bool {
        self.ban_list.is_none() && self.allow_list.is_none()
    }
}

/// An address with a prefix length. A bare address is a full-length prefix.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Network {
    base: IpAddr,
    prefix: u8,
}

impl Network {
    pub fn parse(raw: &str) -> Result<Self, String> {
        let (address, prefix) = match raw.split_once('/') {
            Some((address, prefix)) => (address, Some(prefix)),
            None => (raw, None),
        };
        let base: IpAddr = address
            .parse()
            .map_err(|_| format!("{raw:?} is not an IP address or CIDR range"))?;
        if let IpAddr::V6(v6) = base {
            if v6.to_ipv4_mapped().is_some() {
                return Err(format!(
                    "{raw:?} is an IPv4-mapped address; write the IPv4 form"
                ));
            }
        }
        let max = match base {
            IpAddr::V4(_) => 32,
            IpAddr::V6(_) => 128,
        };
        let prefix = match prefix {
            None => max,
            Some(text) => {
                if text.is_empty() || !text.bytes().all(|byte| byte.is_ascii_digit()) {
                    return Err(format!("{raw:?} has an invalid prefix length"));
                }
                let value: u8 = text
                    .parse()
                    .map_err(|_| format!("{raw:?} has an invalid prefix length"))?;
                if value > max {
                    return Err(format!("{raw:?} prefix is longer than {max}"));
                }
                value
            }
        };
        let network = Self { base, prefix };
        if network.masked(base) != Some(bits(base)) {
            return Err(format!("{raw:?} has bits set past the prefix length"));
        }
        Ok(network)
    }

    fn masked(&self, ip: IpAddr) -> Option<u128> {
        let (value, width) = match (self.base, ip) {
            (IpAddr::V4(_), IpAddr::V4(_)) => (bits(ip), 32u32),
            (IpAddr::V6(_), IpAddr::V6(_)) => (bits(ip), 128u32),
            _ => return None,
        };
        let prefix = u32::from(self.prefix);
        if prefix == 0 {
            return Some(0);
        }
        let mask = (u128::MAX >> (128 - prefix)) << (width - prefix);
        Some(value & mask)
    }

    pub fn contains(&self, ip: IpAddr) -> bool {
        self.masked(ip.to_canonical()) == Some(bits(self.base))
    }
}

fn bits(ip: IpAddr) -> u128 {
    match ip {
        IpAddr::V4(v4) => u128::from(u32::from(v4)),
        IpAddr::V6(v6) => u128::from(v6),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub network: Network,
    /// Unix seconds. The entry stops matching at this instant.
    pub expires: Option<u64>,
    pub reason: Option<String>,
    pub line: usize,
}

impl Entry {
    fn active(&self, now: u64) -> bool {
        self.expires.is_none_or(|expires| now < expires)
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AccessList {
    entries: Vec<Entry>,
}

impl AccessList {
    /// Strict: every non-comment line must be one well-formed entry.
    pub fn parse(text: &str) -> Result<Self, String> {
        let mut entries: Vec<Entry> = Vec::new();
        for (index, raw) in text.lines().enumerate() {
            let line = index + 1;
            let body = raw.trim();
            if body.is_empty() || body.starts_with('#') {
                continue;
            }
            let entry = parse_entry(body, line).map_err(|error| format!("line {line}: {error}"))?;
            if let Some(previous) = entries.iter().find(|seen| seen.network == entry.network) {
                return Err(format!("line {line}: duplicate of line {}", previous.line));
            }
            if entries.len() == MAX_ENTRIES {
                return Err(format!("line {line}: more than {MAX_ENTRIES} entries"));
            }
            entries.push(entry);
        }
        Ok(Self { entries })
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    fn matching(&self, ip: IpAddr, now: u64) -> Option<&Entry> {
        self.entries
            .iter()
            .find(|entry| entry.active(now) && entry.network.contains(ip))
    }
}

fn parse_entry(body: &str, line: usize) -> Result<Entry, String> {
    let (address, mut rest) = body.split_once(char::is_whitespace).unwrap_or((body, ""));
    let network = Network::parse(address)?;
    let mut expires = None;
    let mut reason = None;
    loop {
        rest = rest.trim_start();
        if rest.is_empty() {
            break;
        }
        if let Some(text) = rest.strip_prefix("reason=") {
            let text = text.trim_end();
            if text.is_empty() {
                return Err("reason is empty".into());
            }
            if text.chars().count() > MAX_REASON_CHARS {
                return Err(format!(
                    "reason is longer than {MAX_REASON_CHARS} characters"
                ));
            }
            if text.chars().any(char::is_control) {
                return Err("reason contains a control character".into());
            }
            reason = Some(text.to_string());
            break;
        }
        let (token, tail) = rest.split_once(char::is_whitespace).unwrap_or((rest, ""));
        rest = tail;
        let Some(value) = token.strip_prefix("expires=") else {
            return Err(format!(
                "unknown field {token:?}; expected expires= or reason="
            ));
        };
        if expires.is_some() {
            return Err("expires is given twice".into());
        }
        expires = Some(parse_expiry(value)?);
    }
    Ok(Entry {
        network,
        expires,
        reason,
        line,
    })
}

/// `YYYY-MM-DD` (midnight UTC) or `YYYY-MM-DDTHH:MM:SSZ`. Nothing else.
pub fn parse_expiry(value: &str) -> Result<u64, String> {
    let invalid = || format!("expires={value:?} is not YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ");
    let bytes = value.as_bytes();
    let (date, time) = match bytes.len() {
        10 => (bytes, None),
        20 if bytes[10] == b'T' && bytes[19] == b'Z' => (&bytes[..10], Some(&bytes[11..19])),
        _ => return Err(invalid()),
    };
    if date[4] != b'-' || date[7] != b'-' {
        return Err(invalid());
    }
    let number = |slice: &[u8]| -> Result<u32, String> {
        if slice.is_empty() || !slice.iter().all(u8::is_ascii_digit) {
            return Err(invalid());
        }
        std::str::from_utf8(slice)
            .ok()
            .and_then(|text| text.parse().ok())
            .ok_or_else(invalid)
    };
    let year = number(&date[..4])?;
    let month = number(&date[5..7])?;
    let day = number(&date[8..10])?;
    if !(1970..=9999).contains(&year) || !(1..=12).contains(&month) {
        return Err(invalid());
    }
    if day == 0 || day > days_in_month(year, month) {
        return Err(invalid());
    }
    let mut seconds = 0u64;
    if let Some(time) = time {
        if time[2] != b':' || time[5] != b':' {
            return Err(invalid());
        }
        let hour = number(&time[..2])?;
        let minute = number(&time[3..5])?;
        let second = number(&time[6..8])?;
        if hour > 23 || minute > 59 || second > 59 {
            return Err(invalid());
        }
        seconds = u64::from(hour * 3600 + minute * 60 + second);
    }
    let days = days_from_civil(i64::from(year), month, day);
    Ok(u64::try_from(days).map_err(|_| invalid())? * 86_400 + seconds)
}

fn days_in_month(year: u32, month: u32) -> u32 {
    match month {
        2 if (year.is_multiple_of(4) && !year.is_multiple_of(100)) || year.is_multiple_of(400) => {
            29
        }
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// Days since 1970-01-01 for a proleptic Gregorian date.
fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let month_index = i64::from((month + 9) % 12);
    let day_of_year = (153 * month_index + 2) / 5 + i64::from(day) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verdict {
    Admit,
    Banned { line: usize, reason: Option<String> },
    NotAllowed,
}

impl Verdict {
    /// The stable wire code for a refusal. `None` admits.
    pub fn code(&self) -> Option<&'static str> {
        match self {
            Verdict::Admit => None,
            Verdict::Banned { .. } => Some("address_banned"),
            Verdict::NotAllowed => Some("address_not_allowed"),
        }
    }
}

/// One consistent snapshot of both lists. A ban wins over an allow entry.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AccessPolicy {
    ban: Option<AccessList>,
    allow: Option<AccessList>,
}

impl AccessPolicy {
    pub fn new(ban: Option<AccessList>, allow: Option<AccessList>) -> Self {
        Self { ban, allow }
    }

    pub fn check(&self, ip: IpAddr, now: u64) -> Verdict {
        let ip = ip.to_canonical();
        if let Some(entry) = self.ban.as_ref().and_then(|list| list.matching(ip, now)) {
            return Verdict::Banned {
                line: entry.line,
                reason: entry.reason.clone(),
            };
        }
        match &self.allow {
            Some(list) if list.matching(ip, now).is_none() => Verdict::NotAllowed,
            _ => Verdict::Admit,
        }
    }
}

fn read_limited(path: &Path) -> Result<String, String> {
    let shown = path.display();
    let size = std::fs::metadata(path)
        .map_err(|error| format!("{shown}: {error}"))?
        .len();
    if size > MAX_FILE_BYTES {
        return Err(format!("{shown}: larger than {MAX_FILE_BYTES} bytes"));
    }
    let bytes = std::fs::read(path).map_err(|error| format!("{shown}: {error}"))?;
    String::from_utf8(bytes).map_err(|_| format!("{shown}: not UTF-8 text"))
}

fn load_list(path: &Path, label: &str) -> Result<(AccessList, String), String> {
    let text = read_limited(path).map_err(|error| format!("{label} {error}"))?;
    let list =
        AccessList::parse(&text).map_err(|error| format!("{label} {}: {error}", path.display()))?;
    Ok((list, text))
}

/// Check both files without starting anything. The binary calls this before
/// binding so a typo is a clear startup error rather than an open door.
pub fn validate(config: &AccessConfig) -> Result<(), String> {
    AccessControl::load(config.clone()).map(|_| ())
}

/// Owns the files and publishes each good version to every connection.
#[derive(Debug)]
pub struct AccessControl {
    config: AccessConfig,
    texts: (Option<String>, Option<String>),
    current: watch::Sender<Arc<AccessPolicy>>,
}

impl AccessControl {
    pub fn load(config: AccessConfig) -> Result<Self, String> {
        let ban = config
            .ban_list
            .as_deref()
            .map(|path| load_list(path, "ban list"))
            .transpose()?;
        let allow = config
            .allow_list
            .as_deref()
            .map(|path| load_list(path, "allow list"))
            .transpose()?;
        let texts = (
            ban.as_ref().map(|(_, text)| text.clone()),
            allow.as_ref().map(|(_, text)| text.clone()),
        );
        let policy = AccessPolicy::new(ban.map(|(list, _)| list), allow.map(|(list, _)| list));
        let (current, _) = watch::channel(Arc::new(policy));
        Ok(Self {
            config,
            texts,
            current,
        })
    }

    pub fn subscribe(&self) -> watch::Receiver<Arc<AccessPolicy>> {
        self.current.subscribe()
    }

    pub fn policy(&self) -> Arc<AccessPolicy> {
        Arc::clone(&self.current.borrow())
    }

    /// Read both files again. `Ok(true)` published a new policy, `Ok(false)`
    /// found no change. An error keeps the previous policy in force.
    pub fn reload(&mut self) -> Result<bool, String> {
        let ban = self
            .config
            .ban_list
            .as_deref()
            .map(|path| read_limited(path).map_err(|error| format!("ban list {error}")))
            .transpose()?;
        let allow = self
            .config
            .allow_list
            .as_deref()
            .map(|path| read_limited(path).map_err(|error| format!("allow list {error}")))
            .transpose()?;
        if (ban.as_ref(), allow.as_ref()) == (self.texts.0.as_ref(), self.texts.1.as_ref()) {
            return Ok(false);
        }
        let parse = |text: Option<&String>, path: Option<&PathBuf>, label: &str| {
            text.map(|text| {
                AccessList::parse(text).map_err(|error| {
                    let shown = path
                        .map(|path| path.display().to_string())
                        .unwrap_or_default();
                    format!("{label} {shown}: {error}")
                })
            })
            .transpose()
        };
        let ban_list = parse(ban.as_ref(), self.config.ban_list.as_ref(), "ban list")?;
        let allow_list = parse(
            allow.as_ref(),
            self.config.allow_list.as_ref(),
            "allow list",
        )?;
        self.current
            .send_replace(Arc::new(AccessPolicy::new(ban_list, allow_list)));
        self.texts = (ban, allow);
        Ok(true)
    }

    pub fn summary(&self) -> (Option<usize>, Option<usize>) {
        let policy = self.current.borrow();
        (
            policy.ban.as_ref().map(AccessList::len),
            policy.allow.as_ref().map(AccessList::len),
        )
    }

    /// Poll the files until the task is aborted. File reads run off the executor.
    pub async fn watch(self, every: Duration) {
        let mut control = self;
        let mut interval = tokio::time::interval(every);
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        interval.tick().await;
        loop {
            interval.tick().await;
            let result = tokio::task::spawn_blocking(move || {
                let outcome = control.reload();
                (control, outcome)
            })
            .await;
            let Ok((returned, outcome)) = result else {
                tracing::warn!("access list reload task failed; lists are no longer reloaded");
                return;
            };
            control = returned;
            match outcome {
                Ok(true) => {
                    let (bans, allows) = control.summary();
                    tracing::info!(
                        target: crate::net::AUDIT_TARGET,
                        event = "lists_reloaded",
                        bans = ?bans,
                        allows = ?allows,
                    );
                }
                Ok(false) => {}
                Err(error) => {
                    tracing::warn!(
                        target: crate::net::AUDIT_TARGET,
                        event = "lists_rejected",
                        error = %error,
                        "access list edit rejected; the previous list stays in force"
                    );
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(text: &str) -> IpAddr {
        text.parse().unwrap()
    }

    #[test]
    fn networks_match_by_prefix_and_family() {
        let range = Network::parse("198.51.100.0/24").unwrap();
        assert!(range.contains(ip("198.51.100.7")));
        assert!(!range.contains(ip("198.51.101.7")));
        assert!(!range.contains(ip("2001:db8::1")));
        assert!(
            range.contains(ip("::ffff:198.51.100.9")),
            "mapped peers are IPv4"
        );
        let host = Network::parse("203.0.113.7").unwrap();
        assert!(host.contains(ip("203.0.113.7")));
        assert!(!host.contains(ip("203.0.113.8")));
        let everything = Network::parse("0.0.0.0/0").unwrap();
        assert!(everything.contains(ip("8.8.8.8")));
        let v6 = Network::parse("2001:db8::/32").unwrap();
        assert!(v6.contains(ip("2001:db8:1::5")));
        assert!(!v6.contains(ip("2001:db9::5")));
        assert!(Network::parse("::/0").unwrap().contains(ip("::1")));
    }

    #[test]
    fn networks_reject_loose_forms() {
        for bad in [
            "",
            "host.example",
            "10.0.0.1/33",
            "10.0.0.1/",
            "10.0.0.1/+8",
            "10.0.0.5/24",
            "::ffff:10.0.0.1",
            "2001:db8::/129",
            "10.0.0.0/2x",
        ] {
            assert!(Network::parse(bad).is_err(), "{bad:?} must not parse");
        }
    }

    #[test]
    fn expiry_accepts_two_utc_forms_only() {
        assert_eq!(parse_expiry("1970-01-01").unwrap(), 0);
        assert_eq!(parse_expiry("2000-03-01").unwrap(), 951_868_800);
        assert_eq!(parse_expiry("2026-10-01T12:30:05Z").unwrap(), 1_790_857_805);
        assert_eq!(parse_expiry("2024-02-29").unwrap(), 1_709_164_800);
        for bad in [
            "2026-10-01T12:30:05",
            "2026-10-01 12:30:05Z",
            "2026-13-01",
            "2026-02-29",
            "2026-04-31",
            "2026-10-00",
            "1969-12-31",
            "2026-10-01T24:00:00Z",
            "2026-10-01T23:60:00Z",
            "2026-10-01T23:59:60Z",
            "2026/10/01",
            "26-10-01",
            "tomorrow",
            "2026-1x-01",
            "2026-10-01T1x:00:00Z",
            "2026-10-01T12-30-05Z",
        ] {
            assert!(parse_expiry(bad).is_err(), "{bad:?} must not parse");
        }
    }

    #[test]
    fn list_parses_comments_expiry_and_reason() {
        let list = AccessList::parse(
            "# host notes\n\n203.0.113.7\n198.51.100.0/24 expires=2026-10-01 reason=flooded the lobby # twice\n  2001:db8::/32   reason=v6 range\n",
        )
        .unwrap();
        assert_eq!(list.len(), 3);
        assert!(!list.is_empty());
        let range = &list.entries[1];
        assert_eq!(range.line, 4);
        assert_eq!(range.expires, Some(1_790_812_800));
        assert_eq!(range.reason.as_deref(), Some("flooded the lobby # twice"));
        assert!(AccessList::parse("").unwrap().is_empty());
    }

    #[test]
    fn list_errors_name_the_line() {
        let cases = [
            ("10.0.0.1\nnot-an-address\n", "line 2:"),
            ("10.0.0.1 expires=soon\n", "line 1:"),
            (
                "10.0.0.1 expires=2026-10-01 expires=2026-10-02\n",
                "given twice",
            ),
            ("10.0.0.1 note=hi\n", "unknown field"),
            ("10.0.0.1 reason=\n", "reason is empty"),
            ("10.0.0.1\n10.0.0.1\n", "duplicate of line 1"),
            ("10.0.0.1 reason=a\u{7}b\n", "control character"),
        ];
        for (text, expected) in cases {
            let error = AccessList::parse(text).unwrap_err();
            assert!(error.contains(expected), "{text:?} gave {error:?}");
        }
        let long = format!("10.0.0.1 reason={}\n", "r".repeat(MAX_REASON_CHARS + 1));
        assert!(AccessList::parse(&long).unwrap_err().contains("longer"));
        let many: String = (0..=MAX_ENTRIES)
            .map(|index| {
                format!(
                    "10.{}.{}.{}\n",
                    index / 65_536,
                    (index / 256) % 256,
                    index % 256
                )
            })
            .collect();
        assert!(AccessList::parse(&many).unwrap_err().contains("more than"));
    }

    #[test]
    fn ban_wins_and_allow_list_closes_everything_else() {
        let ban = AccessList::parse("198.51.100.7 reason=spam\n10.9.0.0/16 expires=2000-01-01\n")
            .unwrap();
        let allow = AccessList::parse("198.51.100.0/24\n10.9.0.0/16\n").unwrap();
        let policy = AccessPolicy::new(Some(ban.clone()), Some(allow));
        let now = 1_790_000_000;
        assert_eq!(
            policy.check(ip("198.51.100.7"), now),
            Verdict::Banned {
                line: 1,
                reason: Some("spam".into())
            }
        );
        assert_eq!(policy.check(ip("198.51.100.8"), now), Verdict::Admit);
        assert_eq!(
            policy.check(ip("10.9.1.1"), now),
            Verdict::Admit,
            "ban expired"
        );
        assert_eq!(policy.check(ip("203.0.113.1"), now), Verdict::NotAllowed);
        let only_bans = AccessPolicy::new(Some(ban), None);
        assert_eq!(only_bans.check(ip("203.0.113.1"), now), Verdict::Admit);
        assert_eq!(
            only_bans.check(ip("10.9.1.1"), 900_000_000),
            Verdict::Banned {
                line: 2,
                reason: None
            },
            "an unexpired ban applies"
        );
        assert_eq!(Verdict::Admit.code(), None);
        assert_eq!(Verdict::NotAllowed.code(), Some("address_not_allowed"));
        assert_eq!(
            AccessPolicy::default().check(ip("::1"), now),
            Verdict::Admit
        );
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "fragr-access-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir.join(name)
    }

    #[test]
    fn load_refuses_bad_files_and_reload_keeps_the_last_good_list() {
        let ban_path = scratch("bans.txt");
        std::fs::write(&ban_path, "203.0.113.7 reason=spam\n").unwrap();
        let config = AccessConfig {
            ban_list: Some(ban_path.clone()),
            allow_list: None,
        };
        assert!(!config.is_empty());
        assert!(AccessConfig::default().is_empty());
        validate(&config).unwrap();
        let mut control = AccessControl::load(config.clone()).unwrap();
        let mut watcher = control.subscribe();
        assert_eq!(control.summary(), (Some(1), None));
        assert!(
            !control.reload().unwrap(),
            "unchanged file is not a new list"
        );

        std::fs::write(&ban_path, "203.0.113.7\n203.0.113.8/33\n").unwrap();
        let error = control.reload().unwrap_err();
        assert!(error.contains("line 2"), "{error}");
        assert!(validate(&config).unwrap_err().contains("line 2"));
        assert_eq!(
            control.policy().check(ip("203.0.113.7"), 0).code(),
            Some("address_banned"),
            "a bad edit keeps the previous list"
        );
        assert!(!watcher.has_changed().unwrap());

        std::fs::write(&ban_path, "203.0.113.8\n").unwrap();
        assert!(control.reload().unwrap());
        assert!(watcher.has_changed().unwrap());
        let policy = Arc::clone(&watcher.borrow_and_update());
        assert_eq!(policy.check(ip("203.0.113.7"), 0), Verdict::Admit);
        assert_eq!(
            policy.check(ip("203.0.113.8"), 0).code(),
            Some("address_banned")
        );

        std::fs::remove_file(&ban_path).unwrap();
        assert!(control.reload().unwrap_err().starts_with("ban list "));
        assert!(
            AccessControl::load(config).is_err(),
            "a missing file refuses to start"
        );
    }

    #[test]
    fn load_rejects_oversized_and_non_utf8_files() {
        let big = scratch("big.txt");
        std::fs::write(&big, vec![b'#'; MAX_FILE_BYTES as usize + 1]).unwrap();
        let error = validate(&AccessConfig {
            ban_list: None,
            allow_list: Some(big),
        })
        .unwrap_err();
        assert!(
            error.starts_with("allow list ") && error.contains("larger"),
            "{error}"
        );
        let binary = scratch("binary.txt");
        std::fs::write(&binary, [0xff, 0xfe, 0x00]).unwrap();
        let error = validate(&AccessConfig {
            ban_list: Some(binary),
            allow_list: None,
        })
        .unwrap_err();
        assert!(error.contains("UTF-8"), "{error}");
    }

    #[tokio::test]
    async fn watcher_publishes_an_edit_within_its_interval() {
        let allow_path = scratch("allow.txt");
        std::fs::write(&allow_path, "127.0.0.1\n").unwrap();
        let control = AccessControl::load(AccessConfig {
            ban_list: None,
            allow_list: Some(allow_path.clone()),
        })
        .unwrap();
        let mut watcher = control.subscribe();
        let task = tokio::spawn(control.watch(Duration::from_millis(20)));
        std::fs::write(&allow_path, "127.0.0.1\nnot valid\n").unwrap();
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(
            !watcher.has_changed().unwrap(),
            "invalid edit is not published"
        );
        std::fs::write(&allow_path, "10.0.0.0/8\n").unwrap();
        tokio::time::timeout(Duration::from_secs(2), watcher.changed())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            watcher.borrow().check(ip("127.0.0.1"), 0),
            Verdict::NotAllowed
        );
        task.abort();
    }
}
