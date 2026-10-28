//! Snapshot deltas (#434 stage 4). A world the reader already holds is the
//! base; a delta names that base's tick and carries only what changed.
//!
//! The transport is one ordered, reliable stream per reader, so the last world
//! a session writer put on the socket is the world that reader applied next:
//! the stream itself is the acknowledgement. A writer sends a delta only when
//! its last world is the delta's base, and a full snapshot otherwise (the first
//! world, a world after `MapInfo` or `Mission`, and a world that replaced an
//! unsent one). A reader that cannot apply a delta closes the connection.
//!
//! Shape, beside `"type":"snapshot_delta"`:
//!
//! - `base`, `tick`: the world this applies to and the world it produces.
//! - `set`: every top-level snapshot field whose encoded value changed or
//!   appeared, whole. Omitted when empty.
//! - `unset`: top-level fields the new world omits. Omitted when empty.
//! - `players`: the new world's roster in order. An entry whose `id` the base
//!   holds carries that `id`, its changed or added fields, and an `unset` list
//!   of fields it no longer has; any other entry is a whole participant. A
//!   base entry whose `id` is missing has left the world.
//!
//! Applying a delta to its base yields exactly the full snapshot's JSON value,
//! so every reader validates the same world it would have parsed in full.

use super::ServerMessage;
use serde_json::{Map, Value};

pub const DELTA_TYPE: &str = "snapshot_delta";
const SNAPSHOT_TYPE: &str = "snapshot";
/// Snapshot fields a delta carries outside `set`.
const FRAMED: [&str; 3] = ["type", "tick", "players"];

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

/// Each roster entry by its unique string `id`, or `None` when a roster entry
/// has no such id or two share one: such a world gets no delta.
fn roster(world: &Object) -> Option<Vec<(&str, &Object)>> {
    let entries = world.get("players")?.as_array()?;
    let mut seen = std::collections::HashSet::with_capacity(entries.len());
    let mut roster = Vec::with_capacity(entries.len());
    for entry in entries {
        let entry = entry.as_object()?;
        let id = entry.get("id")?.as_str()?;
        if !seen.insert(id) {
            return None;
        }
        roster.push((id, entry));
    }
    Some(roster)
}

/// Changed and added fields of `next` against `base` into `into`, and the
/// fields `next` dropped, skipping `framed`.
fn diff_fields(base: &Object, next: &Object, framed: &[&str], into: &mut Object) -> Vec<Value> {
    for (key, value) in next {
        if !framed.contains(&key.as_str()) && base.get(key) != Some(value) {
            into.insert(key.clone(), value.clone());
        }
    }
    base.keys()
        .filter(|key| !framed.contains(&key.as_str()) && !next.contains_key(*key))
        .map(|key| Value::String(key.clone()))
        .collect()
}

/// The delta from `base` to `next`, both full snapshot JSON objects, or
/// `None` when either is not a world a delta can describe.
pub fn encode(base: &Object, next: &Object) -> Option<Object> {
    if base.get("type")?.as_str()? != SNAPSHOT_TYPE || next.get("type")?.as_str()? != SNAPSHOT_TYPE
    {
        return None;
    }
    let (base_tick, tick) = (tick_of(base)?, tick_of(next)?);
    if tick <= base_tick {
        return None;
    }
    let base_roster: std::collections::HashMap<&str, &Object> = roster(base)?.into_iter().collect();
    let next_roster = roster(next)?;
    let mut set = Object::new();
    let unset = diff_fields(base, next, &FRAMED, &mut set);
    let mut players = Vec::with_capacity(next_roster.len());
    for (id, entry) in next_roster {
        match base_roster.get(id) {
            Some(held) => {
                let mut partial = Object::new();
                partial.insert("id".into(), Value::String(id.into()));
                let dropped = diff_fields(held, entry, &["id"], &mut partial);
                if !dropped.is_empty() {
                    partial.insert("unset".into(), Value::Array(dropped));
                }
                players.push(Value::Object(partial));
            }
            None => players.push(Value::Object(entry.clone())),
        }
    }
    let mut delta = Object::new();
    delta.insert("type".into(), Value::String(DELTA_TYPE.into()));
    delta.insert("base".into(), base_tick.into());
    delta.insert("tick".into(), tick.into());
    if !set.is_empty() {
        delta.insert("set".into(), Value::Object(set));
    }
    if !unset.is_empty() {
        delta.insert("unset".into(), Value::Array(unset));
    }
    delta.insert("players".into(), Value::Array(players));
    Some(delta)
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
    let held_roster: std::collections::HashMap<&str, &Object> = roster(base)
        .ok_or(DeltaError::Malformed("base roster has no unique ids"))?
        .into_iter()
        .collect();
    let entries = delta
        .get("players")
        .and_then(Value::as_array)
        .ok_or(DeltaError::Malformed("players is not a list"))?;
    let mut seen = std::collections::HashSet::with_capacity(entries.len());
    let mut players = Vec::with_capacity(entries.len());
    for entry in entries {
        let entry = entry
            .as_object()
            .ok_or(DeltaError::Malformed("a roster entry is not an object"))?;
        let id = entry
            .get("id")
            .and_then(Value::as_str)
            .ok_or(DeltaError::Malformed("a roster entry has no id"))?;
        if !seen.insert(id) {
            return Err(DeltaError::Malformed("a roster id repeats"));
        }
        let Some(held) = held_roster.get(id) else {
            players.push(Value::Object(entry.clone()));
            continue;
        };
        let mut merged = (*held).clone();
        for (key, value) in entry {
            if key != "unset" {
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
}

/// The one way a Rust reader turns server frames into messages: it holds the
/// last world and applies deltas to it, so callers only ever see full
/// `Snapshot`s. One reader per connection; a new connection starts empty.
#[derive(Debug, Clone, Default)]
pub struct WorldReader {
    world: Option<Object>,
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
                Ok((Value::Object(world.clone()), Held::World(world)))
            }
            Some(SNAPSHOT_TYPE) => Ok((Value::Object(object.clone()), Held::World(object))),
            // A new map or mission starts a new world: no delta reaches
            // across it.
            Some("map_info" | "mission") => Ok((Value::Object(object), Held::Forget)),
            _ => Ok((Value::Object(object), Held::Keep)),
        }
    }

    fn hold(&mut self, held: Held) {
        match held {
            Held::Keep => {}
            Held::Forget => self.world = None,
            Held::World(world) => self.world = Some(world),
        }
    }

    /// The tick of the world this reader holds.
    pub fn tick(&self) -> Option<u64> {
        self.world.as_ref().and_then(tick_of)
    }
}

/// A tick's world as the encoder keeps it: the full text every reader can
/// take, and the delta from the previous tick's world when there is one.
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
    last: Option<Object>,
}

impl WorldEncoder {
    /// Note a broadcast's full text. For a snapshot, the world and its delta
    /// from the last one, when that delta is smaller than the full text.
    pub fn observe(&mut self, message: &ServerMessage, text: &str) -> Option<EncodedWorld> {
        match message {
            ServerMessage::Snapshot(snapshot) => {
                // Parsed from the text, so every number keeps its shortest
                // form and the delta repeats exactly what a full world says.
                let Ok(Value::Object(world)) = serde_json::from_str::<Value>(text) else {
                    self.last = None;
                    return Some(EncodedWorld {
                        tick: snapshot.tick,
                        delta: None,
                    });
                };
                let delta = self
                    .last
                    .as_ref()
                    .and_then(|last| Some((tick_of(last)?, encode(last, &world)?)))
                    .and_then(|(base, delta)| {
                        let delta = serde_json::to_string(&delta).ok()?;
                        (delta.len() < text.len()).then_some(WorldDelta { base, text: delta })
                    });
                self.last = Some(world);
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
