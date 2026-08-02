# Sprint 02 report — streaming and web playback

Status: complete

## Delivered

- Authenticated MP3 delivery with full responses, HTTP single byte ranges,
  suffix/open-ended ranges, `206`, `416`, `Content-Range`, `Accept-Ranges`,
  private cache headers, content length, and checksum ETags.
- Storage routing uses the backend recorded on each audio object and supports
  both local and mounted filesystem implementations.
- Optional `X-Accel-Redirect` delivery for a production reverse proxy; Django
  streams bounded 64 KiB chunks by default and always handles range fallback.
- Search across track, artist, and album names plus track, artist, and album
  detail pages.
- A shared browser audio player with saved queue/index/position, automatic next
  track, refresh restoration, seeking, and Media Session lock-screen actions.
- Owner-scoped playback sessions, editable persistent queues, playback position,
  current-track state, and revision tracking.
- Owner-scoped manual playlist CRUD with ordered tracks.
- Migrations for the playback and playlist domains.

## Verification

- Ruff: passed.
- Strict mypy: passed for 67 source files.
- Pytest: 34 passed.
- Branch coverage: 88% (minimum 85%).
- Streaming tests cover anonymous rejection, full delivery, byte seeking, and
  invalid ranges.
- API tests cover queue restoration/state changes and playlist owner isolation.

## Deployment settings

- `UMUSIC_USE_INTERNAL_REDIRECT=false` keeps safe Django streaming for local use.
- Set it to `true` behind Nginx and map the internal-only
  `UMUSIC_INTERNAL_MEDIA_PREFIX` to the configured media root.

The codebase is ready for Sprint 03 context and activity modeling.
