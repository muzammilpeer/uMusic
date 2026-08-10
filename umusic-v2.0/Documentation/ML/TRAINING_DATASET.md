# Training Dataset Contract

Sprint 13 packages use manifest schema `1`. JSONL files contain one independently
decodable record per line; `training-features.csv` uses a fixed header and ISO-8601
timestamps. Feature construction sorts by timestamp and observation UUID, joins only
the observation's captured coarse context, clamps listened ratio to `0...1`, and uses
explicit completion/skip end reasons as labels.

Splitting is chronological by whole playback session. A session is assigned to exactly
one of training, validation, or test, preventing later observations from the same
session from leaking into evaluation. Record the actual split boundaries and baseline
metrics in `MODEL_CARD_TEMPLATE.md` for every trained artifact.

Sanitized packages omit track snapshots, sessions, consent strings, and learned
free-form artist/album/genre/language keys. They never contain credentials, server URL,
username, paths, coordinates, raw HealthKit values, or accessory identifiers. Full
packages require a fresh in-app preview token and remain local until explicitly shared.
