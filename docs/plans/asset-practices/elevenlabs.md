# ElevenLabs: current practice vs fragr audiogen (2026-10-24)

Read-only research. No paid calls. Free calls made: GET /v1/models, GET /v1/audio-effects/catalog,
GET /v1/voices/{id} (2 ids), GET /v1/user/subscription, public OpenAPI (https://api.elevenlabs.io/openapi.json).
Compared against origin/wave2/integration tools/audiogen (lib.rs, casting.rs, README) and the
.agents/asset-round-20261023/audio selection sheets (E-1..E-15, E-R*).

## 1. Primary sources (fetched 2026-10-24)

| Topic | URL | Date / version |
|---|---|---|
| Models list | https://elevenlabs.io/docs/overview/models | live page; v4, v4_turbo, music_v2_5 listed |
| Eleven v4 | https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4 | launched changelog 2026-09-28 |
| TTS best practices (v4 prompting, IPA, dictionaries) | https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices | live |
| TTS API | https://elevenlabs.io/docs/api-reference/text-to-speech/convert | live + OpenAPI |
| Dialogue | https://elevenlabs.io/docs/overview/capabilities/text-to-dialogue , https://elevenlabs.io/docs/api-reference/text-to-dialogue/convert | 2,000-char guidance from changelog 2026-04-20 |
| Audio effects on TTS/dialogue | changelog https://elevenlabs.io/docs/changelog/2026/10/12.md | 2026-10-12 |
| Voice Design guide | https://elevenlabs.io/docs/eleven-creative/voices/voice-design | live |
| Voice Design / Remix API | https://elevenlabs.io/docs/api-reference/text-to-voice/design , .../remix | OpenAPI |
| Default voices expire | https://elevenlabs.io/docs/help-center/product/voices/my-voices/what-are-default-voices | "expire on December 31, 2026", replacement table |
| Pronunciation dictionaries | https://elevenlabs.io/docs/eleven-api/guides/how-to/text-to-speech/pronunciation-dictionaries | phoneme rules work on eleven_v4, eleven_v3, eleven_flash_v2 |
| SFX overview | https://elevenlabs.io/docs/overview/capabilities/sound-effects | live |
| SFX API | https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert | model enum now `eleven_text_to_sound_v2`, `eleven_text_to_sound_v3` |
| SFX WAV output | changelog https://elevenlabs.io/docs/changelog/2026/10/19.md | 2026-10-19 (`wav_48000` etc.) |
| Music overview / best practices | https://elevenlabs.io/docs/overview/capabilities/music , .../music/best-practices | live |
| Music compose API | https://elevenlabs.io/docs/api-reference/music/compose | OpenAPI |
| Composition plans (v2 chunks) | https://elevenlabs.io/docs/eleven-api/guides/how-to/music/composition-plans | v2 2026-06-15, v2.5 2026-09-14 |
| Inpainting (keep/regenerate/loop glue, conditioning) | https://elevenlabs.io/docs/eleven-api/guides/how-to/music/inpainting | live |
| Stem separation | https://elevenlabs.io/docs/api-reference/music/separate-stems | `two_stems_v1`, `six_stems_v1` (default) per OpenAPI |
| Music finetunes | https://elevenlabs.io/docs/eleven-creative/products/music/finetunes | API 2026-07-20 |
| Music output formats | changelog https://elevenlabs.io/docs/changelog/2026/6/22.md | `mp3_48000_320`; v2 auto = mp3_48000_192; v2 section durations always enforced |
| `generation_mode` track/loop/ambience | changelog https://elevenlabs.io/docs/changelog/2026/5/25.md + OpenAPI | hidden (`x-fern-ignore`) field, prompt-only |
| Godot audio import | https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html | 4.7 docs |
| Godot synced stems | https://docs.godotengine.org/en/stable/classes/class_audiostreamsynchronized.html | MAX_STREAMS 32 |

Live account (GET /v1/user/subscription, 2026-10-24): Pro, 855,588 / 1,185,132 used, ~329,500 left,
reset 1793976680 (2026-11-06 14:51 UTC). The 10-23 audit had 26,318 used; budget has been mostly spent.

Live /v1/models: eleven_v4 (10,000 chars, cost multiplier 1.0), eleven_v4_turbo (0.5), eleven_v3 (5,000, 1.0).

## 2. What changed that audiogen does not know about

1. **SFX v3 model exists** (`eleven_text_to_sound_v3` in the API enum). audiogen hardcodes
   `SFX_MODEL = eleven_text_to_sound_v2` with the comment "the only sound effects model".
   v3 is not yet on the models page or changelog; treat as undocumented-new, pilot before switching.
2. **Eleven v4 is the recommended TTS/dialogue model** ("net upgrade over v3 in almost every case").
   audiogen default is still `eleven_v3`. v4 settings are Stability + Similarity (no style/speed,
   no SSML). audiogen sends only `stability` with the comment "v3 ignores the others".
   Caveat from the v4 page: "Voice Design voices work with Eleven v4, but they may not be as
   performative or sound as good as with earlier models." v4 reproduces source flaws faithfully.
3. **Default voices expire 2026-12-31.** River (`SAz9…`, all narration), Bill (`pqHf…`, radio Host),
   Daniel, Brian, Callum (E-1 casting) are all default voices. Official replacements:
   River -> Elowen `dvbL7qkNGZY1IqPGZAjM`, Bill -> Wyatt `FrS6cKLB1wg4WYgPa9GW`,
   Daniel -> Finley `fnYMz3F5gMEDGMWcH1ex`, Brian -> Sawyer `8dEUmyPMdDdK91vboYih`,
   Callum -> Callum Husky Trickster `fs2OqxduwXgp9foh2xjK` ("not a strict 1-to-1 replacement").
   Elowen is already in the account (copied, notice_period 4015 days); Wyatt is not.
4. **Music v2/v2.5 composition plans are chunk-based**: up to 30 chunks, each 3-120 s, with
   `positive_styles`/`negative_styles` (max 50 each), `context_adherence`, section durations
   always enforced on v2.x. First chunk sets genre/tone for the whole song.
   `seed` only works with `composition_plan`, not with `prompt`. `force_instrumental` only with `prompt`
   (with a plan, put "instrumental", "no vocals" in styles/negatives).
5. **Inpainting**: `store_for_inpainting=true` returns a `song_id` (response header / detailed body);
   later plans can keep exact ranges (`AudioRefChunk`), regenerate a section, or condition a new chunk on
   up to 30 s of a stored song (`conditioning_ref`, `condition_strength` low..xhigh).
   Documented **seamless loop recipe**: [slice A][3 s glue chunk][slice A again].
6. **Stem separation** endpoint `/v1/music/stem-separation` (`six_stems_v1` default, `two_stems_v1`), ZIP.
7. **Music formats**: `pcm_48000` and `mp3_48000_320` available; audiogen default `mp3_44100_128`.
8. **Music finetunes** (`finetune_id`, `finetune_strength`): train on our own original approved cues for a
   consistent score voice. Upload must be original and owned; screened.
9. **TTS continuity fields** audiogen never sends: `seed` (0..4294967295, best effort),
   `previous_text`/`next_text`, `previous_request_ids`/`next_request_ids` (needs the `request-id`
   response header, which audiogen does not record), `language_code`, `apply_text_normalization`,
   `pronunciation_dictionary_locators` (<=3). Dialogue has `previous_text`/`future_text` (<=100 chars), seed.
10. **audio_effects** on TTS/dialogue (2026-10-12): filter presets (old_radio, phone...), reverb environments,
    noise beds, pan. Reverb/pan are rejected for pcm_* output. For a game keep voices dry and do space in Godot;
    `old_radio`/`phone` could be a cheap pre-baked radio colour but in-engine bus FX is better (reversible).
11. **SFX `loop`**: docs frame it for ambience/background ("30s of soft rain then loop it endlessly");
    this matches E-14 (loop flag works for 30 s ambience) and E-4 (fails on short gunfire loops).
12. **SFX duration**: API minimum 0.5 s (overview page says 0.1; the API reference and OpenAPI say 0.5).
    Prompt max 450 chars (help centre).

## 3. Gap table (audiogen on wave2/integration)

| Gap | Evidence | Fix | Effort |
|---|---|---|---|
| SFX model fixed at v2 | lib.rs:25 | `model` field on sfx items, allow v2/v3; A/B pilot of 6 cues x 2 models on the worst E-4/E-7 cues (clipping, dark rocket, near-silent single shots) | S |
| TTS default v3, no similarity_boost | lib.rs:43, tts_request | default `eleven_v4` after a 10-line A/B; add `similarity_boost`, `seed`, `language_code: en`, `apply_text_normalization`, `previous_text/next_text` | S |
| No request-id / song-id capture | lib.rs send path reads only content-type | record `request-id`, `song-id`, `character-cost`, `x-character-count` headers into manifest | S |
| Music is prompt-only | music_request | add `composition_plan` items (v2.5 chunks), `seed`, `store_for_inpainting`, `/v1/music/detailed` to keep plan + song_id; plan-first workflow via free? (`/v1/music/plan` — check billing) | M |
| No stems | none | `stems` command: POST stem-separation, unzip to candidate dir, record in manifest | S |
| Music format 44.1k MP3 128 | lib.rs DEFAULT_MUSIC_FORMAT | request `pcm_48000` masters (Pro), encode to Ogg Vorbis for Godot | S |
| Expiring voices | E-1 and E-9 use default voices | recast on owned/library voices before 12-31; record voice id + model + settings per role | M (casting) |
| No pronunciation dictionary | none | one fragr PLS lexicon (Latch, Tern, Edda, Splice, Mara, Unmetered, Continuance, place names) uploaded once, locator in every TTS item | S |
| Loudness/clip unaddressed at source | E-3/E-4/E-7 every take near 0 dBFS with clip runs | not an API parameter for SFX; keep the offline gate (already good), add v3 pilot; never ask for "headroom" in prompt (proven no effect in E-4) | - |
| `wav_*` not parsed | parse_format | accept `wav_*` (file already has header) | XS |

## 4. Recipes by goal

### SFX that cut through combat
- Generate at `pcm_48000` (already done). One event per request; the docs recommend generating parts
  separately and layering ("generate individual sound effects and then combining them").
- Layer guns offline: transient/crack + body/thump + mechanical tail, each its own request. This is how
  the 10-02 Shotgun was made (cut from generations, tanh soft clip, -1 dBTP) and it is the best result so far.
- Use audio vocabulary from the docs: "impact", "one-shot", "whoosh", "stem", "dry", "close-mic'd".
  Ask for "one-shot" and set duration to the real event length (>=0.5 s) instead of describing silence.
  For sub-0.5 s events (Repeater shot at 0.10 s cooldown) generate a 1-2 s burst and slice, as E-4 did.
- prompt_influence 0.5-0.65 (current) is reasonable for literal effects; docs default 0.3.
- Clipping/DC: unsolvable in the request; keep adeclip + DC removal + K50 ladder. Pilot SFX v3 on this.

### Seamless loops
- Ambience beds 20-30 s: `loop: true` (works, E-14 seam jump 0.1-0.45 of p99).
- Short mechanical loops (hum, thrust, heartbeat, Repeater): generate 6-8 s steady, cut offline with
  equal-power crossfade at zero crossings (done in E-4/E-7/E-13). Keep.
- Music loops: composition plan, then the documented glue recipe ([A][glue][A]) or a plan whose last chunk
  is written to lead back into the first (context_adherence high), cut at a bar line from the known BPM.
  `generation_mode: "loop"` exists but is undocumented; pilot only.
- Godot: WAV supports loop begin/end in samples; Ogg/MP3 support only a loop offset. Use Ogg Vorbis for
  music (Godot 4.7 recommends Ogg for music/speech) and WAV for short SFX.

### Consistent character voice
- One owned voice per role (designed + saved, or library voice with long notice). Default voices die 12-31.
- Fixed model, fixed settings (stability, similarity), fixed seed per role, `language_code: en`.
- Pronunciation dictionary for proper nouns; v4 also reads inline IPA `/.../`.
- `previous_text`/`next_text` or `previous_request_ids` for multi-part narration so prosody joins.
- Explicit descriptive tags on v4 (`[low, dry, relaxed]`), not ambiguous single words that might
  be read as SFX. Short barks: capitals + punctuation steer emphasis.
- Voice Design prompts: "Native English, <variant>. <Gender>, <age>. Studio quality. Persona: ...
  Emotion: ..." and no FX words (reverb, phone, tape). Preview text should be a real in-register line,
  100-1000 chars. Design with eleven_ttv_v3, save, then test the saved voice on v3 vs v4 (v4 may be less
  performative on designed voices).

### Music with controlled structure and clean endings
- Use composition plans on music_v2_5: explicit chunk durations (enforced), an `[Outro]` or `[Ending]`
  chunk with positives "final held chord rings out, natural decay to silence" and negatives
  "abrupt ending, cut off, fade continues, building". Add 3-5 s of decay in the plan.
- First chunk: 6-7 styles including BPM, key, era, instrumentation, "instrumental"; negatives "vocals, lyrics".
- Use `store_for_inpainting` so a cut ending or a dropout (ep4 c, ep5 a, dark-night a) can be repaired by
  regenerating only that chunk instead of the whole 150 s track (saves ~90% of a retake).
- Home motif consistency: generate the motif once, store it, then `conditioning_ref` on <=30 s of it in the
  first chunk of each cue (condition_strength medium/high). Later, a Finetune on approved original cues.

### Stems for adaptive score
- Problem seen: L20 hold layers 1-3 were three independent prompts; tempo/phase/key alignment is not guaranteed.
- Fix: one composition plan for the full-intensity hold (128 BPM, D minor), store it, separate with
  `six_stems_v1`; the stems are sample-aligned by construction. Build layers from stem sums
  (drums+bass = layer 1, +harmony = 2, +lead = 3) and play them in Godot `AudioStreamSynchronized`
  (up to 32 sub-streams, per-stream volume) for intensity changes.
- Alternative for distinct sections: inpainting plan [calm][glue][intense] from the same song_id.

## 5. Lore and consistency findings in generated takes
- E-1 host casting spec voices "DOUBLE FREQUENCY", "FREQUENCY RAMPAGE", "TRIPLE SCRAP", "FLAG TAKEN",
  "CHARGE ARMED". The 2026-10-23 correction in asset-round-20261023.md line 7 says plain arena calls,
  never "frequency" puns; the plan list is FIRST BLOOD, TRIPLE FRAG, QUAD FRAG, RAMPAGE, FLAG CAPTURED,
  CHARGE PLANTED, ...; "flag taken" and "double frag" are captions only. Those selected takes should not ship.
- E-1 cast only default voices (Bill, Daniel, Brian, Callum), all expiring 12-31. Recast on replacements or a
  designed Host before E-2 (70 lines x 4).
- E-9 narration continues River (expiring). Shipped files stay valid, but no pickups or new lines after 12-31.
  Decide: finish every River line before 12-31 or migrate narration to Elowen/designed voice and regenerate
  the set for one consistent narrator.
- voice.md / characters.md: Latch is not a battle-unit voice; no FX filter on Latch; Host never explains.
  Keep `audio_effects` filters off character voices.

## 6. Cheap pilots before the next batch (all paid, need Nick's go)
1. SFX v2 vs v3: 6 worst cues x 2 takes x 2 models, pcm_48000 (~1,000 credits).
2. TTS v3 vs v4 on the chosen replacement Host voice and Elowen: 10 lines x 2 (~300 credits).
3. Music plan pilot: one 60 s menu loop via v2.5 plan + store_for_inpainting + glue loop + stems
   (~1,000-2,000 credits + stem separation cost, unknown; check before).
