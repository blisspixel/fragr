//! Grudges: a rule bot remembers who has fragged it, from the head-to-head
//! book (`statistics::HeadToHead`), so the memory outlives one life and, on a
//! desktop host, one night. The fighter it owes most among those present is
//! the one it looks for first and the one it has words for when it settles.
use super::GameState;
use crate::protocol::Role;
use uuid::Uuid;

impl GameState {
    /// The fighter present that `name` owes most in the book, if any: rule
    /// bots and people alike can be owed, nobody owes a spectator.
    pub(crate) fn grudge_of(&self, name: &str) -> Option<Uuid> {
        let present = self
            .players
            .iter()
            .filter(|player| player.is_participant() && player.role != Role::Spectator);
        let owed = self
            .head_to_head
            .grudge(name, present.clone().map(|player| player.name.as_str()))?;
        present
            .filter(|player| player.name == owed)
            .map(|player| player.id)
            .next()
    }

    /// Whether `killer`, a named rule bot, fragging `victim` settles the
    /// grudge it held: the victim was the fighter it owed most.
    pub(crate) fn settles_grudge(
        &self,
        killer: Uuid,
        killer_name: &str,
        victim_name: &str,
    ) -> bool {
        self.is_named_rule_bot(killer)
            && self
                .grudge_of(killer_name)
                .and_then(|id| self.players.iter().find(|player| player.id == id))
                .is_some_and(|owed| owed.name == victim_name)
    }

    /// Say the callsign's grudge line to the fighter it settled with. NODS
    /// have none; the speak cooldown still applies.
    pub(crate) fn try_rule_bot_grudge(&mut self, killer: Uuid, victim_name: &str, victim: Uuid) {
        let Some(name) = self
            .players
            .iter()
            .find(|player| player.id == killer)
            .map(|player| player.name.clone())
        else {
            return;
        };
        let salt = self.tick ^ (killer.as_u128() as u64);
        if let Some(line) = crate::roster::grudge_line(&name, victim_name, salt) {
            let _ = self.try_speak_to(killer, &line, Some(victim));
        }
    }
}

#[cfg(test)]
mod tests;
