# Audiogen voice casting: library search, Voice Design, eleven_v4

**Status:** implemented on `feat/audiogen-voice-design`. No paid call was made
to build or test it.

## Goal

Give `tools/audiogen` the calls a lasting voice cast needs, so the narrator and
the Host can each keep one voice the account owns for every later line:

- `library`: search the shared voice library (`GET /v1/shared-voices`), free.
- `design`: Voice Design (`POST /v1/text-to-voice/design`) or remix of a voice
  the account owns (`POST /v1/text-to-voice/{voice_id}/remix`), written as
  candidate previews plus a `.design.json` record.
- `save-voice`: save one chosen preview as an account voice
  (`POST /v1/text-to-voice`), no credits, one voice slot.
- `eleven_v4` accepted for `tts` and dialogue items, priced like `eleven_v3`.

## Why now

ElevenLabs states that every default voice expires on 2026-12-31. River
(`SAz9YHcvj6GT2YYXdXww`, the shipped neutral narrator) and Callum (the Host
candidate in the 2026-10-23 casting round) are default voices. Shipped files stay
on disk, but no new line could match them after that date. A designed voice saved
to the account, or a library voice with a long notice period, avoids that.

## Non-goals

No new runtime integration, no player-facing change, no voice cloning, no default
model change (`eleven_v3` stays the default), no generated assets in this PR, no
`eleven_v4_turbo` (a real-time model; assets do not need it).

## API facts used, checked 2026-10-23

| Fact | Source |
|---|---|
| `eleven_v4` and `eleven_v4_turbo` are current TTS models; v4 allows 10,000 characters per request | [Models](https://elevenlabs.io/docs/overview/models) |
| v4 launched 2026-09-28 (post updated 2026-10-19); it supports audio tags and PVC | [Eleven v4](https://elevenlabs.io/blog/eleven-v4), [changelog 2026-09-28](https://elevenlabs.io/docs/changelog/2026/9/28) |
| Same audio tags on v3 and v4; use `eleven_v4` or `eleven_v3` on Create speech | [Audio tags FAQ](https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/how-do-audio-tags-work-with-eleven-v3-and-v4.md) |
| v4 and v3 cost the same per character ($0.08 per 1,000 API characters) | [API pricing](https://elevenlabs.io/pricing/api) |
| Design body: `voice_description`, `text` 100 to 1000 characters, `model_id` `eleven_multilingual_ttv_v2` (default) or `eleven_ttv_v3`, `seed`, `guidance_scale`, `loudness`, `prompt_strength` (ttv_v3 only); response `previews[].audio_base_64` and `generated_voice_id` | [Design a voice](https://elevenlabs.io/docs/api-reference/text-to-voice/design) |
| Remix takes the same fields on `/v1/text-to-voice/{voice_id}/remix` with no model field; it works on voices the account owns | [Remix a voice](https://elevenlabs.io/docs/api-reference/text-to-voice/remix), [Voices](https://elevenlabs.io/docs/overview/capabilities/voices) |
| Voice Design charges only the preview text, once for all three previews; saving uses one voice slot | [Voice Design guide](https://elevenlabs.io/docs/eleven-creative/voices/voice-design.md) |
| Save: `voice_name`, `voice_description`, `generated_voice_id` | [Create voice from preview](https://elevenlabs.io/docs/api-reference/text-to-voice/create) |
| Library filters include `search`, `gender`, `age`, `accent`, `language`, `use_cases`, `category`, `min_notice_period_days`, `include_custom_rates`, `sort`, `page_size` (max 100), `page` | [List shared voices](https://elevenlabs.io/docs/api-reference/voices/voice-library/get-shared.md) |
| Notice periods run 30 days to 2 years; custom rates multiply credits and are legacy | [Voice Library](https://elevenlabs.io/docs/eleven-creative/voices/voice-library.md) |
| Default voices expire 2026-12-31, with suggested replacements | [Default voices](https://elevenlabs.io/docs/help-center/product/voices/my-voices/what-are-default-voices.md) |

## Architecture

`tools/audiogen/src/casting.rs` holds the request builders, parsers and runners.
They use the existing `Transport` seam, `validate_name`, symlink-refusing writes
and the pending receipt. `lib.rs` adds three `Command` variants and exposes the
receipt helpers to the crate. `main.rs` adds the subcommands. The HTTP read cap
grows only for these paths: design previews come back as base64 JSON (32 MiB)
and library pages are large JSON (4 MiB).

## Spend gate

- `library` and `save-voice` charge no credits. `design` needs a finite
  `--max-credits` covering the preview text length, refuses without
  `--out-dir`, and leaves a pending receipt on any failure. That receipt blocks a
  second charge until someone reconciles it. Design requests are never retried.
- `--dry-run` prints the exact request and estimate and sends nothing.
- Live quota before and after, explicit caps and ledger entries still apply to
  every paid run (AGENTS.md).

## Verification

Fake-transport tests cover request shapes, filter encoding, validation, the
dry run, the cap refusal, preview and record writing, the receipt kept on
failure, malformed previews, save-voice and CLI parsing. Command:
`cargo test -p fragr-audiogen`, plus `cargo clippy -p fragr-audiogen --all-targets -- -D warnings`
and `cargo fmt --check`.

## Success criteria

A developer can find a lasting candidate, design or remix one, save it and cast
`tts` items with that voice id and `eleven_v4`, without a new HTTP dependency or
an uncapped paid path.
