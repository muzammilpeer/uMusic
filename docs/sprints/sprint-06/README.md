# Sprint 06 — Context-aware playlist generation

## Goal

Generate explainable, well-sequenced playlists for activities and places.

## Deliverables

- Eligibility filters, candidate sources, scoring, and penalties.
- Activity energy curves and duration-aware sequencing.
- Artist/album spacing and recently-played protection.
- Familiarity/discovery control and cold-start behavior.
- Immutable generated versions, deterministic seeds, and reason codes.
- Regenerate and replace-track UI.

## Exit criteria

- Requested duration is met within one average track length.
- Equal inputs, version, and seed reproduce a playlist.
- Every selected track has a human-readable explanation.
- Hard exclusions and explicit dislikes always win.

## Start

Use [PROMPT.md](PROMPT.md).

