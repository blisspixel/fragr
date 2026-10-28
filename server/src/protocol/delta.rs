//! Snapshot deltas (#434 stage 4). A world the reader already holds is the
//! base; a delta names that base's tick and carries only what changed.
//!
//! The transport is one ordered, reliable stream per reader, so the last world
//! a session writer put on the socket is the world that reader applied next:
//! the stream itself is the acknowledgement. The tick encodes each world once
//! as the delta from the previous tick's world, and a writer whose last world
//! is that base sends it. A writer whose reader holds an older world (its
//! unsent world was replaced) encodes its own delta from the world it last
//! sent. A world goes whole only when no base is held: the first world, and
//! the first after `MapInfo` or `Mission`. A reader that cannot apply a delta
//! closes the connection.
//!
//! Shape, beside `"type":"snapshot_delta"`:
//!
//! - `base`, `tick`: the world this applies to and the world it produces.
//! - `set`: every top-level snapshot field whose encoded value changed or
//!   appeared, whole. Omitted when empty.
//! - `unset`: top-level fields the new world omits. Omitted when empty.
//! - `players`: the new world's roster in order. An entry with an `id` is a
//!   whole participant the base does not hold. An entry without one carries
//!   a base roster entry forward: `at` is that entry's position in the base
//!   roster, omitted when it is one past the last carried entry's (the first
//!   carried entry's default is 0). It holds only the fields that changed or
//!   appeared, and an `unset` list of fields it no longer has. A base entry
//!   no entry carries has left the world. The rebuilt roster's ids are
//!   unique.
//!
//! Applying a delta to its base yields exactly the full snapshot's JSON value,
//! so every reader validates the same world it would have parsed in full,
//! with every fighter's full `id`.

use super::ServerMessage;
use serde_json::value::RawValue;
use serde_json::{Map, Value};

pub const DELTA_TYPE: &str = "snapshot_delta";
const SNAPSHOT_TYPE: &str = "snapshot";
/// Snapshot fields a delta carries outside `set`.
const FRAMED: [&str; 3] = ["type", "tick", "players"];
/// A carried roster entry's base position.
pub const AT: &str = "at";
/// Fields a roster entry has only inside a delta. A world whose roster uses
/// either name gets no delta.
const ENTRY_FRAMED: [&str; 2] = [AT, "unset"];

type Object = Map<String, Value>;

/// Why a delta could not be applied. Every one closes the reader's connection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeltaError {
    /// A delta arrived with no world to apply it to.
    NoBase,
    /// The delta names a different base than the world this reader holds.
    WrongBase { held: u64, named: u64 },
    /// The delta itself is malformed.
    Malformed(&'static str),
}

impl std::fmt::Display for DeltaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoBase => write!(f, "snapshot delta without a base world"),
            Self::WrongBase { held, named } => {
                write!(f, "snapshot delta for tick {named}, holding tick {held}")
            }
            Self::Malformed(why) => write!(f, "malformed snapshot delta: {why}"),
        }
    }
}

impl std::error::Error for DeltaError {}

fn tick_of(world: &Object) -> Option<u64> {
    world.get("tick").and_then(Value::as_u64)
}

/// Each roster entry with its unique string `id`, or `None` when an entry has
/// no such id, two share one, or an entry uses a delta's own entry field:
/// such a world gets no delta.
fn roster(world: &Object) -> Option<Vec<(&str, &Object)>> {
    let entries = world.get("players")?.as_array()?;
    let mut seen = std::collections::HashSet::with_capacity(entries.len());
    let mut roster = Vec::with_capacity(entries.len());
    for entry in entries {
        let entry = entry.as_object()?;
        let id = entry.get("id")?.as_str()?;
        if !seen.insert(id) || ENTRY_FRAMED.iter().any(|name| entry.contains_key(*name)) {
            return None;
        }
        roster.push((id, entry));
    }
    Some(roster)
}

/// One JSON object as its fields' exact text, borrowed from the frame. No
/// number is parsed and nothing is copied: two encodings of the same value by
/// the same serializer are the same text, so text equality is value equality.
/// A key with an escape cannot be borrowed; such a world gets no delta.
/// Fields stay in the order the serializer wrote them, so two worlds' fields
/// line up and a lookup is usually the next slot.
struct RawObject<'a>(Vec<(&'a str, &'a RawValue)>);

impl<'a> RawObject<'a> {
    /// The slot of `key`, trying `hint` first.
    fn position(&self, key: &str, hint: usize) -> Option<usize> {
        if self.0.get(hint).is_some_and(|(name, _)| *name == key) {
            return Some(hint);
        }
        self.0.iter().position(|(name, _)| *name == key)
    }

    fn get(&self, key: &str) -> Option<&'a RawValue> {
        self.position(key, 0).map(|at| self.0[at].1)
    }

    fn remove(&mut self, key: &str) -> Option<&'a RawValue> {
        let at = self.position(key, 0)?;
        Some(self.0.remove(at).1)
    }

    fn contains_key(&self, key: &str) -> bool {
        self.position(key, 0).is_some()
    }

    /// Fields of `self` whose key `other` lacks, in order.
    fn missing_from<'s>(&'s self, other: &'s RawObject<'_>) -> impl Iterator<Item = &'a str> + 's {
        let mut hint = 0;
        self.0
            .iter()
            .filter_map(move |(name, _)| match other.position(name, hint) {
                Some(at) => {
                    hint = at + 1;
                    None
                }
                None => Some(*name),
            })
    }
}

impl<'de: 'a, 'a> serde::Deserialize<'de> for RawObject<'a> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Fields;
        impl<'de> serde::de::Visitor<'de> for Fields {
            type Value = RawObject<'de>;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("a JSON object")
            }
            fn visit_map<M: serde::de::MapAccess<'de>>(
                self,
                mut map: M,
            ) -> Result<Self::Value, M::Error> {
                let mut fields = Vec::with_capacity(map.size_hint().unwrap_or(32));
                while let Some(field) = map.next_entry::<&'de str, &'de RawValue>()? {
                    fields.push(field);
                }
                Ok(RawObject(fields))
            }
        }
        deserializer.deserialize_map(Fields)
    }
}

/// A world as the encoder diffs it.
struct RawWorld<'a> {
    tick: u64,
    fields: RawObject<'a>,
    /// Each roster entry with its `id`'s exact text.
    players: Vec<(&'a str, RawObject<'a>)>,
}

impl<'a> RawWorld<'a> {
    /// A full snapshot's text, or `None` when it is not a world a delta can
    /// describe: not a snapshot, no tick, or a roster whose entries lack one
    /// unique string id or use a delta's own entry field.
    fn read(text: &'a str) -> Option<Self> {
        let mut fields: RawObject<'a> = serde_json::from_str(text).ok()?;
        if fields.remove("type")?.get() != concat!('"', "snapshot", '"') {
            return None;
        }
        let tick = fields.remove("tick")?.get().parse().ok()?;
        let entries: Vec<RawObject<'a>> =
            serde_json::from_str(fields.remove("players")?.get()).ok()?;
        let mut seen = std::collections::HashSet::with_capacity(entries.len());
        let mut players = Vec::with_capacity(entries.len());
        for entry in entries {
            let id = entry.get("id")?.get();
            if !id.starts_with('"')
                || !seen.insert(id)
                || ENTRY_FRAMED.iter().any(|name| entry.contains_key(name))
            {
                return None;
            }
            players.push((id, entry));
        }
        Some(Self {
            tick,
            fields,
            players,
        })
    }
}

/// Writes one delta's JSON text.
struct Writer {
    out: String,
}

impl Writer {
    /// `"key":value` after a separator when the object already has a field.
    fn field(&mut self, first: &mut bool, key: &str, value: &str) {
        if !std::mem::take(first) {
            self.out.push(',');
        }
        // A borrowed key held no escape in its source, so it needs none.
        self.out.push('"');
        self.out.push_str(key);
        self.out.push_str("\":");
        self.out.push_str(value);
    }

    /// Changed and added fields of `next` against `base`, then an `unset`
    /// list of the fields `next` dropped, skipping `id`.
    fn diff(&mut self, first: &mut bool, base: &RawObject<'_>, next: &RawObject<'_>, skip: &str) {
        self.changed(first, base, next, skip);
        self.unset(first, base.missing_from(next).filter(|key| *key != skip));
    }

    /// Changed and added fields of `next` against `base`, skipping `skip`.
    fn changed(
        &mut self,
        first: &mut bool,
        base: &RawObject<'_>,
        next: &RawObject<'_>,
        skip: &str,
    ) {
        let mut hint = 0;
        for (key, value) in &next.0 {
            if *key == skip {
                continue;
            }
            let held = base.position(key, hint).map(|at| {
                hint = at + 1;
                base.0[at].1.get()
            });
            if held != Some(value.get()) {
                self.field(first, key, value.get());
            }
        }
    }

    fn unset<'k>(&mut self, first: &mut bool, mut names: impl Iterator<Item = &'k str>) {
        let Some(name) = names.next() else {
            return;
        };
        if !std::mem::take(first) {
            self.out.push(',');
        }
        self.out.push_str("\"unset\":[\"");
        self.out.push_str(name);
        for name in names {
            self.out.push_str("\",\"");
            self.out.push_str(name);
        }
        self.out.push_str("\"]");
    }
}

/// The delta from `base` to `next`, both a full snapshot's JSON text, as wire
/// text, when there is one and it is shorter than `whole` bytes. The diff
/// reads both worlds' field text without parsing a number, so the delta
/// repeats exactly what the full world says.
pub fn encode_text(base: &str, next: &str, whole: usize) -> Option<String> {
    let capacity = whole.min(next.len()) / 2;
    let (base, next) = (RawWorld::read(base)?, RawWorld::read(next)?);
    if next.tick <= base.tick {
        return None;
    }
    let positions: std::collections::HashMap<&str, usize> = base
        .players
        .iter()
        .enumerate()
        .map(|(at, (id, _))| (*id, at))
        .collect();
    let mut writer = Writer {
        out: String::with_capacity(capacity),
    };
    writer.out.push_str(&format!(
        "{{\"type\":\"{DELTA_TYPE}\",\"base\":{},\"tick\":{}",
        base.tick, next.tick
    ));
    let mut set = Writer { out: String::new() };
    set.changed(&mut true, &base.fields, &next.fields, "");
    if !set.out.is_empty() {
        writer.out.push_str(",\"set\":{");
        writer.out.push_str(&set.out);
        writer.out.push('}');
    }
    writer.unset(&mut false, base.fields.missing_from(&next.fields));
    writer.out.push_str(",\"players\":[");
    let mut cursor = 0;
    for (index, (id, entry)) in next.players.iter().enumerate() {
        if index > 0 {
            writer.out.push(',');
        }
        writer.out.push('{');
        let mut first = true;
        match positions.get(id) {
            None => {
                for (key, value) in &entry.0 {
                    writer.field(&mut first, key, value.get());
                }
            }
            Some(&at) => {
                if at != cursor {
                    writer.field(&mut first, AT, &at.to_string());
                }
                cursor = at + 1;
                writer.diff(&mut first, &base.players[at].1, entry, "id");
            }
        }
        writer.out.push('}');
        if writer.out.len() >= whole {
            return None;
        }
    }
    writer.out.push_str("]}");
    (writer.out.len() < whole).then_some(writer.out)
}

/// The delta from `base` to `next`, both full snapshot JSON objects, or
/// `None` when either is not a world a delta can describe. The same encoder
/// as the wire's, for readers and tests that hold parsed worlds.
pub fn encode(base: &Object, next: &Object) -> Option<Object> {
    let (base, next) = (
        serde_json::to_string(base).ok()?,
        serde_json::to_string(next).ok()?,
    );
    match serde_json::from_str(&encode_text(&base, &next, usize::MAX)?).ok()? {
        Value::Object(delta) => Some(delta),
        _ => None,
    }
}

fn names(list: Option<&Value>) -> Result<Vec<&str>, DeltaError> {
    let Some(list) = list else {
        return Ok(Vec::new());
    };
    list.as_array()
        .ok_or(DeltaError::Malformed("unset is not a list"))?
        .iter()
        .map(|name| {
            name.as_str()
                .ok_or(DeltaError::Malformed("unset names a non-string"))
        })
        .collect()
}

/// The world `delta` produces from `base`. The result is checked only as far
/// as the delta's own shape; the caller validates it as a snapshot.
pub fn apply(base: &Object, delta: &Object) -> Result<Object, DeltaError> {
    if delta.get("type").and_then(Value::as_str) != Some(DELTA_TYPE) {
        return Err(DeltaError::Malformed("not a snapshot delta"));
    }
    let named = delta
        .get("base")
        .and_then(Value::as_u64)
        .ok_or(DeltaError::Malformed("base is not a tick"))?;
    let tick = delta
        .get("tick")
        .and_then(Value::as_u64)
        .ok_or(DeltaError::Malformed("tick is not a tick"))?;
    let held = tick_of(base).ok_or(DeltaError::NoBase)?;
    if named != held {
        return Err(DeltaError::WrongBase { held, named });
    }
    if tick <= held {
        return Err(DeltaError::Malformed("tick does not advance"));
    }
    if delta
        .keys()
        .any(|key| !["type", "base", "tick", "set", "unset", "players"].contains(&key.as_str()))
    {
        return Err(DeltaError::Malformed("unknown delta field"));
    }
    let mut world = base.clone();
    world.insert("tick".into(), tick.into());
    if let Some(set) = delta.get("set") {
        let set = set
            .as_object()
            .ok_or(DeltaError::Malformed("set is not an object"))?;
        for (key, value) in set {
            if FRAMED.contains(&key.as_str()) {
                return Err(DeltaError::Malformed("set names a framed field"));
            }
            world.insert(key.clone(), value.clone());
        }
    }
    for name in names(delta.get("unset"))? {
        if FRAMED.contains(&name) {
            return Err(DeltaError::Malformed("unset names a framed field"));
        }
        world.remove(name);
    }
    let held_roster = roster(base).ok_or(DeltaError::Malformed("base roster has no unique ids"))?;
    let entries = delta
        .get("players")
        .and_then(Value::as_array)
        .ok_or(DeltaError::Malformed("players is not a list"))?;
    let mut carried = vec![false; held_roster.len()];
    let mut cursor = 0;
    let mut players = Vec::with_capacity(entries.len());
    for entry in entries {
        let entry = entry
            .as_object()
            .ok_or(DeltaError::Malformed("a roster entry is not an object"))?;
        if let Some(id) = entry.get("id") {
            if !id.is_string() {
                return Err(DeltaError::Malformed("a roster id is not a string"));
            }
            if ENTRY_FRAMED.iter().any(|name| entry.contains_key(*name)) {
                return Err(DeltaError::Malformed("a whole entry carries delta fields"));
            }
            players.push(Value::Object(entry.clone()));
            continue;
        }
        let at = match entry.get(AT) {
            None => cursor,
            Some(at) => at
                .as_u64()
                .and_then(|at| usize::try_from(at).ok())
                .ok_or(DeltaError::Malformed("at is not a roster position"))?,
        };
        let Some(was_carried) = carried.get_mut(at) else {
            return Err(DeltaError::Malformed("at is outside the base roster"));
        };
        if std::mem::replace(was_carried, true) {
            return Err(DeltaError::Malformed("a base entry is carried twice"));
        }
        cursor = at + 1;
        let mut merged = held_roster[at].1.clone();
        for (key, value) in entry {
            if !ENTRY_FRAMED.contains(&key.as_str()) {
                merged.insert(key.clone(), value.clone());
            }
        }
        for name in names(entry.get("unset"))? {
            if name == "id" {
                return Err(DeltaError::Malformed("unset names the id"));
            }
            merged.remove(name);
        }
        players.push(Value::Object(merged));
    }
    let mut seen = std::collections::HashSet::with_capacity(players.len());
    for entry in &players {
        let id = entry.get("id").and_then(Value::as_str).unwrap_or_default();
        if !seen.insert(id) {
            return Err(DeltaError::Malformed("a roster id repeats"));
        }
    }
    world.insert("players".into(), Value::Array(players));
    Ok(world)
}

/// Why a reader refused a frame.
#[derive(Debug)]
pub enum ReadError {
    Json(serde_json::Error),
    Delta(DeltaError),
}

impl std::fmt::Display for ReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Json(error) => error.fmt(f),
            Self::Delta(error) => error.fmt(f),
        }
    }
}

impl std::error::Error for ReadError {}

impl From<serde_json::Error> for ReadError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

impl From<DeltaError> for ReadError {
    fn from(error: DeltaError) -> Self {
        Self::Delta(error)
    }
}

/// What a frame does to the world a reader holds.
enum Held {
    Keep,
    Forget,
    World(Object),
    Delta(Object),
}

/// The one way a Rust reader turns server frames into messages: it holds the
/// last world and applies deltas to it, so callers only ever see full
/// `Snapshot`s. One reader per connection; a new connection starts empty.
#[derive(Debug, Clone, Default)]
pub struct WorldReader {
    world: Option<Object>,
    /// Whether the last frame read was a delta, for harnesses that count.
    delta: bool,
}

impl WorldReader {
    pub fn new() -> Self {
        Self::default()
    }

    /// Parse one text frame. A delta becomes the full snapshot it describes.
    /// A world that is not a valid snapshot is refused and not held.
    pub fn read(&mut self, text: &str) -> Result<ServerMessage, ReadError> {
        let (value, held) = self.rebuild(text)?;
        let message = serde_json::from_value(value)?;
        self.hold(held);
        Ok(message)
    }

    /// Parse one text frame as JSON, a delta rebuilt into the full snapshot's
    /// value, for a reader that inspects fields rather than typed messages.
    pub fn read_value(&mut self, text: &str) -> Result<Value, ReadError> {
        let (value, held) = self.rebuild(text)?;
        self.hold(held);
        Ok(value)
    }

    fn rebuild(&self, text: &str) -> Result<(Value, Held), ReadError> {
        let value: Value = serde_json::from_str(text)?;
        let Value::Object(object) = value else {
            return Ok((value, Held::Keep));
        };
        match object.get("type").and_then(Value::as_str) {
            Some(DELTA_TYPE) => {
                let base = self.world.as_ref().ok_or(DeltaError::NoBase)?;
                let world = apply(base, &object)?;
                Ok((Value::Object(world.clone()), Held::Delta(world)))
            }
            Some(SNAPSHOT_TYPE) => Ok((Value::Object(object.clone()), Held::World(object))),
            // A new map or mission starts a new world: no delta reaches
            // across it.
            Some("map_info" | "mission") => Ok((Value::Object(object), Held::Forget)),
            _ => Ok((Value::Object(object), Held::Keep)),
        }
    }

    fn hold(&mut self, held: Held) {
        self.delta = matches!(held, Held::Delta(_));
        match held {
            Held::Keep => {}
            Held::Forget => self.world = None,
            Held::World(world) | Held::Delta(world) => self.world = Some(world),
        }
    }

    /// The tick of the world this reader holds.
    pub fn tick(&self) -> Option<u64> {
        self.world.as_ref().and_then(tick_of)
    }

    /// Whether the last frame this reader accepted arrived as a delta.
    pub fn last_was_delta(&self) -> bool {
        self.delta
    }
}

/// A tick's world as the encoder keeps it: its tick, and the delta from the
/// previous tick's world when there is one. The full text is the broadcast's.
#[derive(Debug)]
pub struct EncodedWorld {
    pub tick: u64,
    pub delta: Option<WorldDelta>,
}

#[derive(Debug)]
pub struct WorldDelta {
    pub base: u64,
    pub text: String,
}

/// Remembers the last world the tick encoded so the next one can be sent as
/// a delta. Lives with the tick loop; a map or mission message forgets it.
#[derive(Debug, Default)]
pub struct WorldEncoder {
    /// The last world's tick and full text.
    last: Option<(u64, String)>,
}

impl WorldEncoder {
    /// Note a broadcast's full text. For a snapshot, the world and its delta
    /// from the last one, when that delta is smaller than the full text.
    pub fn observe(&mut self, message: &ServerMessage, text: &str) -> Option<EncodedWorld> {
        match message {
            ServerMessage::Snapshot(snapshot) => {
                let delta = self.last.as_ref().and_then(|(base, last)| {
                    Some(WorldDelta {
                        base: *base,
                        text: encode_text(last, text, text.len())?,
                    })
                });
                // Reuse the held buffer: one copy of the world per tick.
                let (tick, last) = self.last.get_or_insert_with(Default::default);
                *tick = snapshot.tick;
                last.clear();
                last.push_str(text);
                Some(EncodedWorld {
                    tick: snapshot.tick,
                    delta,
                })
            }
            ServerMessage::MapInfo { .. } | ServerMessage::Mission { .. } => {
                self.last = None;
                None
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests;
