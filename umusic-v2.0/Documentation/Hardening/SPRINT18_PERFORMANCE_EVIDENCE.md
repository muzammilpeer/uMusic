# Sprint 18 Performance Evidence

Date: 2026-08-10

## Local evidence

- Debug Swift test run: 121 tests passed on arm64 macOS.
- Cached 25,000-track search fixture completed in 0.532 seconds end-to-end test time.
- Cached 25,000-track recommendation reported p95 `83.076 ms` in the release run, passing the local 150 ms target. The debug run reported `199.206 ms`, confirming that release configuration is essential to this gate.
- `OSSignposter` intervals now cover catalog browse, playback preparation, model ranking, and research export so Instruments can attribute stalls to those operations.
- Catalog fetches use a 500-row batch size with indexes for ID, title, artist, album, genres, language, release year, and availability. SQLite requests WAL and `NORMAL` synchronous mode.

## Physical-device matrix required for release

The release gate requires a nominated minimum physical iPhone, but decision D-008 is still open. Record device model, OS, battery health, thermal state, catalog fixture, media, network profile, build commit, run count, median, and p95 for:

- cold/warm launch and mini-player restoration;
- cached and streamed tap-to-audible latency;
- 25,000-track search and recommendation, plus actual Core ML inference;
- Hangs, Allocations, Core Data fetch/save, Network, Energy Log, and Points of Interest traces;
- 60-minute cached playback under UI load with zero app-caused underruns;
- 60-minute screen-off A/B battery comparison with context disabled/enabled;
- archive download size and compressed model size;
- 1 GB streaming export with peak-memory delta.

The resident JSON learning/playlist/queue stores and the absence of an installed production Core ML model mean their large-data memory/inference budgets cannot yet pass. No budget revision or approval is recorded. Device-only rows remain open rather than inferred from simulator or source inspection.
