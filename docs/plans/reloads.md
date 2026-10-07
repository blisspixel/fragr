# Reloads inside the carried count

Status: **implemented** (2026-10-06). Local evidence is below. Not merged. The running night process does not have it. The finite arcade bag landed in the same source pass.

## Goal

A joined human reloads with R. The corner shows rounds in the gun and what is left to load, and those numbers add up with the other guns on the same ammunition type. Agents, rule bots and campaign enemies keep one count.

## Non-goals

- No second ammunition currency and no four-dart shell cost. The pool stays the total, including every magazine of that type.
- The loadout keys `reserves` and `reload` stay refused. The new field is `loaded`.
- The MCP act schema does not offer reload. In-process humans, agents, rule bots and campaign enemies stay unarmed, so existing spray and campaign routes keep pool fire.
- No campaign floor change and no `CAMPAIGN_RULES_REVISION` change.
- No new reload cue. Generated clips from the first magazine era stay unused.
- No tour republish, no commit, and no night-binary restart.
- Sidestep, the head band, radio and scope stay in [fight feel](fight-feel.md).

## Rules

- `GAMEPLAY_VERSION` is 37. A shared arcade room requires an exact 37 hello. Campaign and local missions keep their floors. Every door refuses a hello above 37.
- A real socket human is armed only after the player exists, and only when the noted hello is at least 37. Tests that build `Connected` without that note stay unarmed.
- Magazine size and reload ticks at 20 Hz: Tack 12 and 16, Flechette 20 and 22, Repeater 30 and 22, Scatter 6 and 14 (one press fills the tube), Rail 4 and 28, Sniper 5 and 28. Fists and the Shiv have none.
- Discovery: magazines plus the bag equal the pool. One shot spends one unit from the gun and from the pool. An armed arcade human gets the same accounting. The spawn kit, which includes the loaded magazine, is 80 bullets, 24 shells and 16 cells. Death puts that kit back. Walking over a gun adds its pickup amount to the bag, up to the pool cap, and does not load the magazine by itself. A weapon-only mutator still reloads one magazine from an unlimited reserve and sends three zero pool counts.
- `Action.reload` is a rising edge, omitted unless pressed. The client sends it only after a loadout includes `loaded`, and erases it when the control is up. A server that never sends `loaded` rejects the key.
- An empty magazine dry-fires and does not spend the bag. A gun that is reloading does not fire and does not count a dry click. Death and a real weapon change cancel the reload. A reload that finishes can shoot on that same tick. A newly found gun comes loaded. A later pickup adds to the bag only.
- The corner is `12|38` style whenever the bag is finite, arcade included. A zero-pool arcade loadout stays the magazine number alone, so a weapon-only gun does not look empty. A loadout with no `loaded` key keeps the old pool string. A show change and a Sabotage round restart keep magazines on a human who already had them. Bots and agents stay unarmed.

## Verification

Not merged. The night process does not have it.

Finite bag, checked 2026-10-06:

- `an_arcade_human_spends_a_finite_bag_and_reloads_from_what_is_left`, `an_armed_weapon_only_arsenal_reloads_without_a_finite_bag`, `a_reload_press_blocks_fire_until_the_magazine_is_full_again`, `an_armed_arcade_human_restocks_from_the_weapon_pad`, `a_show_change_reseeds_an_armed_humans_bag`, `a_human_magazine_survives_the_next_sabotage_round`, plus the older `human_magazines_share_one_pool_and_reload_moves_rounds_without_adding_any` and the two unlimited-arsenal tests that stay unarmed.
- Godot `test_equipment`: PASS. The zero-pool corner stays the magazine number. A finite bag reads `20|60`, `6|18` and `4|12`.
- `cargo fmt --all` and `cargo clippy -p fragr-server --all-targets --locked -- -D warnings`.
- `cargo test -p fragr-server --lib --locked` reported 1063 passed, 11 failed, 3 ignored. The failures are two M02 route stalls, repeater and M10 admission text, three scatter-damage assertions, the heavy burst, the long sniper lane, and one shot-trace kill. They name the head band or gameplay 37. This bag change does not touch that code, and the 11 were not bisected.

Magazine pass, earlier the same day, not re-run as a set for the bag:

- `venue_close_removes_a_resume_armed_human_and_says_why` sees the version note between the seat and the join. That hello omits the contract, so the note is legacy 1.
- `authored_map_is_shared_by_humans_agents_and_spectators`: one Tack shot leaves 11 in the gun and 49 in the pool. `reload: true` parses.
- `act_schema_error_sets_is_error` and `private_equipment_reaches_observation_and_invalid_updates_preserve_it`: agents still have no reload key.
- `solo_controller_finishes_actual_m01_with_combat_and_open_gate_retries` still departs at 2 deaths.
- Godot `test_keyboard_only`, `test_rebinding`, `test_frontend`, `test_server_book`, `test_host_menu`, `test_local_host`, `test_m08_mission`, and `test_m10_mission`.
- `cargo clippy --workspace --all-targets --locked -- -D warnings` on that earlier pass.

## Spend

None.
