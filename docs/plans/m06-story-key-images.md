# M06 story key images

**Status:** shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317), 2026-10-02. Two inspected lunar story illustrations are integrated with reader-paced captions, narration and fallback.
Parent integration: [M06 Port of Entry](m06-port-of-entry-prototype.md).
**Spend:** two image requests only, new batch cap $1.50 equivalent within the
existing $3 image allocation. The prior possession batch reserves $0.114 and the
historical unresolved reservation remains $0.107. Owner-confirmed API credit was
$14.40; conservative available credit before this batch is $14.179. No cash,
top-up, overage, subscription or cloud operation is authorized by this plan.

Merged in [PR #317](https://github.com/blisspixel/fragr/pull/317), with passing
[final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and
[package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).
Local gates pass 1244 workspace tests, 94.31 percent unfiltered line coverage and
188 scripts/88 harnesses. The [inspected capture evidence](../evidence/2026-10-01-m06-textures.md)
records the current routes. Source-main CI and desktop publication receipts
are tracked in [release closeout](m06-release-closeout.md). Fresh-player, difficulty,
subjective listening and final character acceptance remain open.

## Purpose and exact ownership

Add two original retro story illustrations to the frozen M06 arrival and
M06-to-M07 transit scenes. They establish the inhabited cargo port, recognizable
impounded Common Carrier, Earth, lunar settlement and custody depot. They do not
prove moving transport, pressure damage, new gameplay or final character casting.
The accepted [Moon](../design/moon.md), [ship](../design/space.md) and
[art bible](../ART_STORY_BIBLE.md) guide silhouettes, materials and hard utility
light. The Common Carrier preserves its broad rectangular transport hull,
left cockpit, bone shell, gunmetal ribs and warm passenger windows.

Own the new `tools/spritegen/specs/m06-story-key-images.json`, source/provenance
under `client/art/story/m06-key-images-20261001/`, runtime PNGs under
`client/assets/story/images/m06/`, existing `m06_arrival.json` and `l06_l07.json`
image fields, and useful resource checks in the existing story/audio harnesses.
Preserve every current caption, narration path, timing, readiness and dismissal
barrier. A missing image keeps the existing text fallback.

## Priced bounded operation

Use the existing built `fragr-spritegen` binary, `marketing-studio/image`, direct
text requests (`enhance_prompt: false`), medium quality, 2k, 16:9, one request per
image. Current official [model documentation](https://console.higgsfield.ai/models/marketing-studio/image)
was checked 2026-10-01: direct generation accepts 1k/2k/4k and 16:9. The shared
[documentation index](https://docs.higgsfield.ai/docs/llms.txt) makes that model
page authoritative over the supplementary OpenAPI list. Model-page access was
verified through its public HTML because the text browser could not fetch it.
Price the exact whole spec before submission; record individual estimates and
submit only when both total and conservative shared balance fit. Retain known
request identity and all reservations through interruptions; recovery polls the
same ID on the official API origin and never duplicates a paid POST.

## Composition and preparation

The arrival image uses a readable impounded rectangular ship at a maintained
cargo port with pressure shells, warm lived windows, handling gantries and a small
recognizable Earth in black sky. The transit image views a purposeful pressure
passage toward an occupied lunar town, with the custody tower across the crater.
Hard directional light and broad deep shade belong in these story illustrations,
not flat environmental albedos. Keep the primary silhouettes in the upper
three quarters clear of the caption band. Use chunky purposeful pixel clusters,
bone/gray dust, basalt, warm gunmetal, muted sage/cyan and sparse rust accents.
No HUD, words, logos, named portraits, moving tug, airlock action, space fighter,
rocket, outdoor water, photorealism or neon corridor.

Store metadata-free decoded originals and exact prompts/parameters/request IDs,
unknown provider billing, source hashes and prepared hashes. Use the existing
local Rust reducer and shared palette, no trim, then nearest pixel display.
Inspect reduced resolution before selecting a keeper; do not mistake completion
for visual quality. Do not regenerate or enlarge the batch without root's shared
allocation. Validate loadable resources, exact source/caption continuity, absent
image fallback and actual rendered scene framing with readable caption/control
bands. Final broad checker and tours follow the shared contact/source freeze.

### Exact preflight

`price.log` on 2026-10-01 priced both medium/2k/16:9 requests at $0.080 each,
$0.160 total, exit 0, with no generation. This fits the explicit $1.50 new-batch
cap and $3 aggregate image cap: $0.274 including the prior possession batch.
Conservative credit after both new reservations and the retained historical
$0.107 would be $14.019. These values are reservations, not confirmed billing.
The assembled exact prompts are recorded by the spec and diagnostic prompt log.


### Integration and inspected evidence

Exactly two requests completed, IDs `f0dc658a-78e1-4206-bf0c-57ec538c5c89`
(arrival) and `8f636ead-7ff8-4ec7-9f29-0e91d1ff504d` (transit). Each reserved
$0.080. The initial response supplied a polling origin outside the authenticated
allowlist; the tool preserved each accepted identity, and the documented local
recovery command resumed the same ID through the official API origin. No duplicate
submission occurred. Total new reservation is $0.160; combined new image
reservation is $0.274 including possessions. Provider billing and cash deduction
remain unknown, not reported as measured charges.

Metadata-free original images are 2688x1520. Trimming four pixels from their top
and bottom makes an exact 2688x1512 frame; the existing Rust reducer then reduces
by four to 672x378 and quantizes to the shared palette. The new source manifest
records both received and clean-source hashes, prompt/parameters/request identity,
crop, palette hash and exact runtime hashes. Runtime imports are lossless without
mipmaps; ScenePlayer keeps nearest filtering. No original Moon bake was replaced.

The arrival keeper visibly shows the broad gunmetal/bone transport, squared left
cockpit, passenger windows, gantry, pressure buildings and Earth. The transit
keeper shows enclosed passage framing, warm utility lights, occupied town and
square custody tower across dry crater terrain. They are story illustrations,
not measured playable geometry or vehicle-motion evidence. No named face is cast.
Arrival's two pages share the establishing image; departure uses the transit
image. Frozen captions, neutral narration byte paths, one-second holds and final
reader waits remain exact. The packaged install check now requires both story
illustrations. Missing images continue through the actual text-only fallback.

`import-final.log`, `campaign-audio-key-images.log`, `test_story_scene.log` and
`test_scene_player.log` under `.agents/m06-story-art-20261001/` passed with exit0
and no script/engine errors. The shared audio harness verifies source/runtime
hashes, displayed nearest textures, exact submitted translated narration, actual
finished events, final reader hold, skip/stop and combined missing-image/audio
fallback. The scene-player harness deliberately emits its existing invalid-scene
warning; that is its tested fallback case, not a suppressed error.

`render-story-1280-final.log` passed actual Compatibility playback at 1280x720,
with all three voice clips playing through Voice and actual final completion
retaining captions and waiting for the reader. Inspected frames are
`m06_arrival-0.png`, `m06_arrival-1.png` and `l06_l07-0.png` in the same diagnostic
directory. Earth/ship and town/depot read clearly above the controls. The existing
bounded caption band scrolls the long first/transit captions and shows its
keyboard/gamepad scroll hint; the short Port page fits completely. No human
listening audit, fresh-player acceptance or moving transport is claimed.
The final independent review also inspected these actual scene frames and
approved both current keepers: the arrival composition reads Earth and the
impounded transport, and transit reads the occupied crater settlement and depot.
The scrollbar and control hint remain visible for the long frozen captions.
All generation and renderer processes closed before handing back the lane.

Exact diagnostic receipts for the shared spend record are
`.agents/m06-story-art-20261001/price.log` (dry-run total $0.160),
`raw/ledger.jsonl` (two $0.080 reservations and retained request identities),
`generate-first.log`, `arrival-recover.log`, `arrival-resume.log`,
`departure-generate-first.log`, `departure-recover.log` and
`departure-resume.log`, all under the same directory. Resume operations reserved
zero additional credit. No further generation is authorized by this completed
batch.
