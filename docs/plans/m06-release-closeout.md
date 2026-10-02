# M06 release closeout

**Status:** in flight, 2026-10-02. The implementation shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317) at `a87a1cc9089bfd81e4c6cadad3cb21f0b3b6c34c`, with passing [final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and [three desktop package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).

## Goal and scope

Publish the verified v0.66.0 desktop increment, bring current plan statuses and the sole roadmap sequence up to date, and end the authorized round on a clean passing main. The four README gameplay stills are already refreshed and inspected. Change documentation only; no new mission, asset generation, runtime behavior, protocol or API changes.

## Delivery and verification

1. Require all jobs in [source-main CI](https://github.com/blisspixel/fragr/actions/runs/36983591511) to pass before tagging its exact source commit.
2. Create an annotated v0.66.0 tag and a draft release. Require the tag workflow's three packages, install checks and checksum attachment to pass before publishing.
3. Merge this documentation closeout only after the release is actually public and its own full PR CI passes. README availability wording in this branch is proposed until that publication gate.
4. Verify final main CI, clean local main, release assets and checksums, and removal of this round's temporary branches. Preserve open fresh-player, difficulty, listening, character-art and hardware gates in the existing plans. M07 remains unbuilt.

The tagged runtime tree must match final main outside documentation. Historical failed receipts remain evidence. No checks, thresholds or author identities change. No additional billable operation is needed; current round cash charges remain $0.

## Completion record

Source-main CI, tagged package publication and final documentation integration are pending. Record their actual receipts here before handoff.
