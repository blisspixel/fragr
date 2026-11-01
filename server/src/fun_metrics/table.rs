//! The disk shape of a per-gun table: a map from the gun's wire id, guns
//! with nothing to say left out. Reading refuses a key that is not a gun.
use super::record::WeaponTable;
use crate::protocol::WeaponType;
use serde::de::Error as _;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::collections::BTreeMap;

fn wire_id(weapon: WeaponType) -> String {
    serde_json::to_value(weapon)
        .ok()
        .and_then(|value| value.as_str().map(str::to_owned))
        .unwrap_or_default()
}

/// What a table entry needs to say whether it has anything in it.
pub trait Quiet {
    fn quiet(&self) -> bool;
}

impl Quiet for u64 {
    fn quiet(&self) -> bool {
        *self == 0
    }
}

impl Quiet for super::record::Samples {
    fn quiet(&self) -> bool {
        self.is_empty()
    }
}

impl<T: Serialize + Quiet> Serialize for WeaponTable<T> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let entries: BTreeMap<String, &T> = self
            .iter()
            .filter(|(_, value)| !value.quiet())
            .map(|(weapon, value)| (wire_id(weapon), value))
            .collect();
        entries.serialize(serializer)
    }
}

impl<'de, T: Deserialize<'de> + Default> Deserialize<'de> for WeaponTable<T> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let entries = BTreeMap::<String, T>::deserialize(deserializer)?;
        let mut table = WeaponTable::<T>::default();
        for (key, value) in entries {
            let weapon: WeaponType = serde_json::from_value(serde_json::Value::String(key.clone()))
                .map_err(|_| D::Error::custom(format!("{key:?} is not a gun")))?;
            *table.get_mut(weapon) = value;
        }
        Ok(table)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_table_writes_gun_ids_and_refuses_anything_else() {
        let mut table = WeaponTable::<u64>::default();
        *table.get_mut(WeaponType::ArticleBlade) = 2;
        *table.get_mut(WeaponType::Rail) = 5;
        let json = serde_json::to_value(&table).unwrap();
        assert_eq!(json, serde_json::json!({"article_blade": 2, "rail": 5}));
        let back: WeaponTable<u64> = serde_json::from_value(json).unwrap();
        assert_eq!(back, table);
        let refused =
            serde_json::from_value::<WeaponTable<u64>>(serde_json::json!({"Nightfall": 1}));
        assert!(refused.unwrap_err().to_string().contains("is not a gun"));
    }
}
