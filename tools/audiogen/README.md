# fragr-audiogen

Developer-only tool that produces sound effects and music beds for fragr through the ElevenLabs HTTP API and writes them as ordinary assets under `client/assets/audio/`. Players never run it. CI never runs it. The game never calls the API.

Crate: `tools/audiogen` (`fragr-audiogen`). Rust only, one HTTP dependency, tested without the network.

## Put in the key

Create an API key in the ElevenLabs dashboard, then pick one of these. Never commit the key.

PowerShell (current session only):

```powershell
$env:ELEVENLABS_API_KEY = "your-key"
```

Bash:

```bash
export ELEVENLABS_API_KEY="your-key"
```

Or put it in a `.env` file at the repository root. The tool reads `.env` automatically when the environment variable is unset and accepts `ELEVENLABS_API_KEY=...` or the shorter `elevenlabs=...`:

```text
elevenlabs=your-key
```

An existing key file outside the checkout can also be supplied explicitly:

```bash
cargo run -p fragr-audiogen -- --api-key-file /path/outside/checkout/elevenlabs.key quota
```

`.env` and `*.key` are gitignored. Keep credentials out of `.agents/`, which is disposable diagnostics and receipts. The tool never prints the key.

## Commands

Check remaining credits:

```bash
cargo run -p fragr-audiogen -- quota
```

The summary includes credit-extension eligibility, permission, maximum extension
and current overage when the API supplies them. Missing or null fields print
`unknown`, not `no` or zero. Inspect this alongside remaining quota before each
funded batch; the command does not change billing settings. The generator's
credit cap bounds estimates, not the provider's billing system.

One sound effect (24 kHz mono WAV by default, which Godot imports as a sample):

```bash
cargo run -p fragr-audiogen -- sfx --name fire_rail \
  --prompt "heavy railgun shot, electric charge crack then cold metallic ring, retro arcade, dry" \
  --seconds 0.9 --influence 0.6
```

One music bed (MP3 at 44.1 kHz and 128 kbps, which Godot streams):

```bash
cargo run -p fragr-audiogen -- music --name music/match_01 \
  --prompt "driving industrial synth-metal loop for a 90s arena shooter, 140 bpm, no vocals" \
  --length-ms 60000 --instrumental
```

Spoken lines for the news station and the Host (the default model is `eleven_v3`; `eleven_v4` is also accepted at the same one credit per character, and delivery tags such as `[sighs]` work on both):

```bash
cargo run -p fragr-audiogen -- voices
cargo run -p fragr-audiogen -- tts --name radio/news/generic-01-count --voice <voice_id> \
  --text "[sighs] Good evening. The Continuance lost count again." --stability 0.5
```

`voices` prints the account's default voices with ids. ElevenLabs states that every default voice expires on 2026-12-31, so a lasting role needs a voice the account keeps: a designed voice saved to the account, or a shared library voice with a long notice period (see Casting below). Spec items of kind `tts` take `text`, `voice`, optional `model`, `stability`, `format`, `title`. The scripts for the news station live in `specs/radio-news-scripts.json`. Cast the speakers and convert them into a batch spec (no credits spent), then generate:

```bash
cargo run -p fragr-audiogen -- scripts --scripts tools/audiogen/specs/radio-news-scripts.json \n  --voice host=<id> --voice tina=<id> --voice phil=<id> --voice caller=<id1>,<id2>,<id3> \n  --out tools/audiogen/specs/radio-news.json
cargo run -p fragr-audiogen -- batch --spec tools/audiogen/specs/radio-news.json --max-credits 20000
```

Caller clips (lines starting with `HOST:` and `CALLER:`) become multi-voice dialogues through the text-to-dialogue endpoint; spec items may also carry `lines` of `{voice_id, text}` directly. Match templates with `{placeholders}` are skipped until round-end data exists. Beds and the sung station ID are music items in `specs/radio-news-beds.json`.

Everything in a spec file (see `specs/sfx-core.json`):

```bash
cargo run -p fragr-audiogen -- batch --spec tools/audiogen/specs/sfx-core.json
cargo run -p fragr-audiogen -- batch --spec tools/audiogen/specs/sfx-core.json --only frag
```

## Casting

Search the shared voice library (a free GET; legacy custom-rate voices, which bill a credit multiplier, are excluded unless `--include-custom-rates` is passed):

```bash
cargo run -p fragr-audiogen -- library --search "narrator" --use-case narrative_story \
  --min-notice-days 365 --sort cloned_by_count --page-size 30
```

Each row prints the voice id, owner id, category, labels, notice period, rate, and preview URL. A library voice's owner can withdraw it; the notice period is how long the account keeps access afterwards.

Design a voice from a description, or remix one the account owns, into previews. Previews are candidates, so `--out-dir` is required and should sit outside `client/assets`. The request charges the preview text once for all previews, so it needs a finite `--max-credits` and leaves a pending receipt until the response is written:

```bash
cargo run -p fragr-audiogen -- --out-dir .agents/casting --max-credits 400 design \
  --name narrator/warm-a --description "..." --text "<100 to 1000 characters of a real line>" --seed 1
cargo run -p fragr-audiogen -- --out-dir .agents/casting --max-credits 400 design \
  --name narrator/warm-a-remix --remix <owned_voice_id> --description "slower, closer" --text "..."
```

This writes `<name>_<n>.mp3` previews and `<name>.design.json` with each `generated_voice_id`. The default design model is `eleven_ttv_v3`; `eleven_multilingual_ttv_v2` is also accepted. Keep one saved voice per role so every later line stays in the same voice:

```bash
cargo run -p fragr-audiogen -- save-voice --generated-voice-id <id> --voice-name "fragr narrator" \
  --description "..."
```

Saving charges no credits and uses one custom voice slot.

Useful flags on every command: `--dry-run` prints the exact request and the credit estimate and writes nothing, `--overwrite` replaces existing files (the default is to skip them), `--out-dir` changes the destination, `--max-credits N` refuses to start a run whose estimate exceeds N.

Batch runs work in waves: `--prefix radio/rock/` selects a folder, `--limit 5` generates at most five new files, and files that already exist are skipped, so re-running the same spec continues where it stopped. Every batch prints `batch: K to generate, ~N credits estimated` before it calls the API.

Spec items may carry a `title` (recorded in the manifest and shown by the in-game radio) and, for music, `length_range_ms: [lo, hi]` instead of `length_ms`; the tool then picks a fixed length per track name inside the range, so a spec of 2 to 6 minute tracks stays varied and reproducible.

## What it writes

- The audio file at `<out-dir>/<name>.<ext>`. `pcm_*` formats become `.wav`, `mp3_*` become `.mp3`.
- `<out-dir>/audiogen-manifest.json`, one entry per generated name with the prompt, model, format, duration, channel count, byte size, and generation time. That is how anyone regenerates or audits an asset later.

Names are lowercase with `_`, `-`, and `/` for folders, no extension. They should match what the client loads, for example `fire_rail`, `hit_scatter`, `frag`, `round_start`, or `music/match_01`.

## Formats and tiers

- Sound effects default to `pcm_24000`, available on every paid tier. `pcm_44100` and `pcm_48000` need Pro or higher (checked 2026-10-02); 24 kHz cannot carry anything above 12 kHz, so full-band effects such as gunshots should request `pcm_48000`. MP3 is available everywhere.
- Music defaults to `mp3_44100_128`. Higher bitrates exist on higher tiers.
- The API does not document the channel count of PCM output. Measured on 2026-09-18 it is stereo, and the MP3 variant carries a stereo frame header. When you pass `--seconds`, the tool infers mono or stereo from the byte count and records it in the manifest. Without a duration, mono is assumed, so pass `--seconds` for effects.
- Sound effects run 0.5 to 30 seconds. Music runs 3 seconds to 10 minutes. `--loop` asks for a seamless loop on sound effects.

## Cost and limits

Sound effects and music cost credits per second of audio. Music is only enabled on paid plans. The API rate limits concurrent requests per tier; the tool retries on 429 and 5xx with backoff and stops on any other error. Run `quota` before a big batch.

## Licensing of the output

Output use depends on the service, model and plan terms. A paid subscription does
not by itself establish unrestricted distribution or an Apache-2.0 grant for music.
The [music model terms](https://elevenlabs.io/eleven-music-model-specific-terms)
restrict music-library distribution and define separate commercial game rights.
See [the refresh plan](../../docs/plans/radio-refresh.md) before publishing new
music. Keep request manifests and the applicable distribution basis. Existing
third-party notices and procedural CC0 assets are unaffected.
