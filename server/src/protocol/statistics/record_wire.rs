//! Version-aware strict wire counts. Historical columns never gain new meaning.
use super::*;

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Counts {
    alive_ticks: u64,
    deaths: u64,
    hp_lost: u64,
    armor_lost: u64,
    dry_triggers: u64,
    #[serde(default, skip_serializing_if = "is_zero")]
    secrets: u64,
    #[serde(deserialize_with = "bounded_weapons")]
    weapons: Vec<WeaponCounts>,
    #[serde(default, skip_serializing_if = "empty_grenades")]
    grenades: WeaponCounts,
    #[serde(default, skip_serializing_if = "empty_grenades")]
    mines: WeaponCounts,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    remote_mines: Option<WeaponCounts>,
}

fn bounded_weapons<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Vec<WeaponCounts>, D::Error> {
    struct Columns;
    impl<'de> serde::de::Visitor<'de> for Columns {
        type Value = Vec<WeaponCounts>;
        fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter.write_str("at most eight weapon columns")
        }
        fn visit_seq<A: serde::de::SeqAccess<'de>>(
            self,
            mut sequence: A,
        ) -> Result<Self::Value, A::Error> {
            let mut weapons = Vec::with_capacity(WeaponType::ALL.len());
            for _ in 0..WeaponType::ALL.len() {
                let Some(value) = sequence.next_element()? else {
                    return Ok(weapons);
                };
                weapons.push(value);
            }
            if sequence.next_element::<serde::de::IgnoredAny>()?.is_some() {
                return Err(serde::de::Error::custom("too many weapon columns"));
            }
            Ok(weapons)
        }
    }
    deserializer.deserialize_seq(Columns)
}

impl Counts {
    fn from_counts(counts: CombatCounts, version: u32) -> Self {
        let width = if version == RECORD_VERSION {
            WeaponType::ALL.len()
        } else {
            counts
                .weapons
                .iter()
                .rposition(|count| *count != WeaponCounts::default())
                .map_or(5, |last| (last + 1).max(5))
        };
        Self {
            alive_ticks: counts.alive_ticks,
            deaths: counts.deaths,
            hp_lost: counts.hp_lost,
            armor_lost: counts.armor_lost,
            dry_triggers: counts.dry_triggers,
            secrets: counts.secrets,
            weapons: counts.weapons[..width].to_vec(),
            grenades: counts.grenades,
            mines: counts.mines,
            remote_mines: (counts.remote_mines != WeaponCounts::default())
                .then_some(counts.remote_mines),
        }
    }

    fn into_counts(self, version: u32) -> Result<CombatCounts, &'static str> {
        if version == LEGACY_RECORD_VERSION && self.remote_mines.is_some() {
            return Err("historical record cannot contain Remote Mine counters");
        }
        if !match version {
            LEGACY_RECORD_VERSION => (5..=7).contains(&self.weapons.len()),
            RECORD_VERSION => self.weapons.len() == WeaponType::ALL.len(),
            _ => false,
        } {
            return Err("unsupported record weapon-column shape");
        }
        let mut counts = CombatCounts {
            alive_ticks: self.alive_ticks,
            deaths: self.deaths,
            hp_lost: self.hp_lost,
            armor_lost: self.armor_lost,
            dry_triggers: self.dry_triggers,
            secrets: self.secrets,
            grenades: self.grenades,
            mines: self.mines,
            remote_mines: self.remote_mines.unwrap_or_default(),
            ..CombatCounts::default()
        };
        counts.weapons[..self.weapons.len()].copy_from_slice(&self.weapons);
        Ok(counts)
    }
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Wire {
    version: u32,
    session_id: Uuid,
    player_id: Uuid,
    round: u32,
    tick: u64,
    entered_at: u64,
    round_started_at: u64,
    ticks_per_second: u32,
    map_id: u32,
    map_name: String,
    role: Role,
    scope: RecordScope,
    status: RecordStatus,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "mission_elapsed"
    )]
    mission_elapsed_ticks: Option<u64>,
    total: Counts,
    attempt: Counts,
}

impl From<PlayerRecord> for Wire {
    fn from(record: PlayerRecord) -> Self {
        Self {
            version: record.version,
            session_id: record.session_id,
            player_id: record.player_id,
            round: record.round,
            tick: record.tick,
            entered_at: record.entered_at,
            round_started_at: record.round_started_at,
            ticks_per_second: record.ticks_per_second,
            map_id: record.map_id,
            map_name: record.map_name,
            role: record.role,
            scope: record.scope,
            status: record.status,
            mission_elapsed_ticks: record.mission_elapsed_ticks,
            total: Counts::from_counts(record.total, record.version),
            attempt: Counts::from_counts(record.attempt, record.version),
        }
    }
}

impl TryFrom<Wire> for PlayerRecord {
    type Error = &'static str;
    fn try_from(wire: Wire) -> Result<Self, Self::Error> {
        Ok(Self {
            version: wire.version,
            session_id: wire.session_id,
            player_id: wire.player_id,
            round: wire.round,
            tick: wire.tick,
            entered_at: wire.entered_at,
            round_started_at: wire.round_started_at,
            ticks_per_second: wire.ticks_per_second,
            map_id: wire.map_id,
            map_name: wire.map_name,
            role: wire.role,
            scope: wire.scope,
            status: wire.status,
            mission_elapsed_ticks: wire.mission_elapsed_ticks,
            total: wire.total.into_counts(wire.version)?,
            attempt: wire.attempt.into_counts(wire.version)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record() -> PlayerRecord {
        let mut game = crate::sim::GameState::new();
        game.start_round();
        let id = Uuid::from_u128(1);
        game.add_player(id, "Reader".into(), Role::Human);
        game.player_record(id).unwrap()
    }

    #[test]
    fn strict_versions_preserve_legacy_widths_and_refuse_forged_eighth_column() {
        let legacy = record().legacy_record().unwrap();
        let base = serde_json::to_value(&legacy).unwrap();
        for width in 5..=7 {
            let mut value = base.clone();
            for field in ["total", "attempt"] {
                let columns = value[field]["weapons"].as_array_mut().unwrap();
                columns.resize(
                    width,
                    serde_json::to_value(WeaponCounts::default()).unwrap(),
                );
            }
            let parsed: PlayerRecord = serde_json::from_value(value.clone()).unwrap();
            assert_eq!(parsed, legacy);
            value["total"]["weapons"]
                .as_array_mut()
                .unwrap()
                .resize(8, serde_json::to_value(WeaponCounts::default()).unwrap());
            assert!(serde_json::from_value::<PlayerRecord>(value).is_err());
        }
        let current = record();
        let base = serde_json::to_value(&current).unwrap();
        assert_eq!(base["total"]["weapons"].as_array().unwrap().len(), 8);
        assert_eq!(
            serde_json::from_value::<PlayerRecord>(base.clone()).unwrap(),
            current
        );
        for width in [0, 5, 6, 7, 9, 100] {
            let mut bad = base.clone();
            bad["attempt"]["weapons"].as_array_mut().unwrap().resize(
                width,
                serde_json::to_value(WeaponCounts::default()).unwrap(),
            );
            assert!(serde_json::from_value::<PlayerRecord>(bad).is_err());
        }
    }

    #[test]
    fn remote_counts_have_distinct_current_history_and_no_legacy_shape() {
        let mut current = record();
        current.tick = 20;
        current.total.alive_ticks = 20;
        current.total.remote_mines = WeaponCounts {
            attacks: 2,
            damaging_attacks: 1,
            kills: 1,
            hp_damage: 35,
            armor_damage: 20,
            ..WeaponCounts::default()
        };
        current.attempt = current.total.clone();
        current.validate_for(Some(current.player_id), None).unwrap();
        assert_eq!(current.total.attacks(), 2);
        assert_eq!(current.total.kills(), 1);
        assert_eq!(current.total.mines, WeaponCounts::default());
        assert_eq!(current.total.grenades, WeaponCounts::default());
        assert_eq!(
            serde_json::from_value::<PlayerRecord>(serde_json::to_value(&current).unwrap())
                .unwrap(),
            current
        );
        assert!(current.legacy_record().is_err());
        let legacy = record().legacy_record().unwrap();
        let mut forged = serde_json::to_value(&legacy).unwrap();
        forged["total"]["remote_mines"] = serde_json::to_value(WeaponCounts::default()).unwrap();
        assert!(serde_json::from_value::<PlayerRecord>(forged).is_err());
        let mut invalid = current.clone();
        invalid.attempt.remote_mines.attacks = 3;
        assert!(invalid
            .validate_for(Some(current.player_id), Some(&current))
            .is_err());
        let mut invalid = current.clone();
        invalid.total.remote_mines.damaging_attacks = 3;
        assert!(invalid.validate_for(Some(current.player_id), None).is_err());
        let mut invalid = current.clone();
        invalid.total.remote_mines.hp_damage = 1_u64 << 53;
        assert!(invalid.validate_for(Some(current.player_id), None).is_err());
        let mut next = current.clone();
        next.tick += 1;
        next.total.alive_ticks += 1;
        next.total.remote_mines.hp_damage += 1;
        assert!(next.total.contains(&current.total));
        assert!(!current.total.contains(&next.total));
    }

    #[test]
    fn downgrade_never_discards_actual_repeater_counts() {
        let mut record = record();
        assert_eq!(
            record.legacy_record().unwrap().version,
            LEGACY_RECORD_VERSION
        );
        assert!(record
            .validate_for(
                Some(record.player_id),
                Some(&record.legacy_record().unwrap())
            )
            .is_err());
        record.total.weapons[WeaponType::Repeater.index()].attacks = 1;
        assert!(record.legacy_record().is_err());
        assert!(
            serde_json::to_value(&record.total).is_err(),
            "unversioned standalone counts cannot silently acquire an eighth column"
        );
        assert_eq!(
            serde_json::from_value::<PlayerRecord>(serde_json::to_value(&record).unwrap()).unwrap(),
            record
        );
        record.total = CombatCounts::default();
        record.attempt.weapons[WeaponType::Repeater.index()].attacks = 1;
        assert!(record.legacy_record().is_err());
    }
}
