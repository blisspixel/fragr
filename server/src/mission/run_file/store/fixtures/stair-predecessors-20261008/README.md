# Stair geometry predecessors

These are exact original map bytes retained for strict local-run compatibility
tests and historical world identity. Runtime campaign launches use the canonical
maps in `server/maps/`.

| Mission | SHA-256 |
| --- | --- |
| M08 | `b9964704b9bf51e837118f25fbec9d93574d16634b1d281caf694181f44de666` |
| M09 | `4f45d0c5132dbc741537f83e541a97c8a4f8dd130ed0d74bde45f73eecff7381` |
| M09 enclosed intermediate, save version 15 only | `01471a5ff4d5c3861018efcc87a547a3b86305c5ecba6e02745457f69b4f5397` |
| M10 | `d767c07691a88d810d945db952b7cda6c67ab968b2e1b6161a1f00790eeda49d` |
| M12 | `8f84cca779909790d23c8af2fa59db38bb25c9b94f4422a969e79180a137c78d` |

Do not reformat these files. The geometry reader registers exact mission,
predecessor and successor identities separately from the save schema revision.
An entry may upgrade after whole-document validation; a completed or closed
history retains the actual original map identity.
