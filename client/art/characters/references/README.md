# M01 character references

Reviewed reference candidates, 2026-09-20. These establish useful silhouettes and
issued colors for the human Clerk and mechanical Sweeper. They are not runtime
sprites or accepted animation sets. The canonical articulated source remains
[`../rig.gd`](../rig.gd), with its existing bake and verification path.

These issued Union references apply to their human guard and controlled bot
roles. They are not a template for Latch or the free selectable bodies. Follow
the [character guide](../../../../docs/design/characters.md) for those references:
person-scale, individually repaired or chosen civilian utility details, with
free will and expressive personal behavior. Latch's roughly six-foot scrappy
robot body must not become a standardized military unit; the free human's
cultural inspiration does not introduce national flags or nationality costumes.

- `clerk-preview.webp`: the dashboard's compressed preview of the completed
  human Clerk request. Exposed face, cloth sleeves, light chest armor and a low
  service pistol distinguish the human security role. The original PNG and API
  polling identity have not been recovered. Do not regenerate this paid request.
- `sweeper.png`: the downloaded original bot reference. Broader shoulders, steel
  mechanisms, an amber status slit and an automatic rifle distinguish the bot.
  The human and bot share bone, institutional green and restrained red seals.

Both pictures contain a baked checkerboard. It is not transparency. Preserve
them as references; do not import their backgrounds into the game or treat a
single image as proof of eight-direction animation quality. Simplify small
details when adapting the rig and inspect silhouettes at actual combat distance.

The exact prompts and requested settings live in
[`m01-enemy-references.json`](../../../../tools/spritegen/specs/m01-enemy-references.json).
`receipts.json` records reviewed files, hashes, model and confirmed charges.
API request IDs and dashboard job IDs are different identifiers; never substitute
one for the other. Local recovery details remain in `.agents/spend/` and the
original durable provider ledger stays beside the raw outputs in `art/raw/`.

This directory is excluded from release exports with the rest of `client/art/`.
