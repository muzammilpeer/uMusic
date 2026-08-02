# Sprint 04 report — activities, places, and contextual sessions

Status: complete

## Delivered

- Preset cycling, running, gym, focus, walking, relax, and commute activities,
  plus owner-defined custom activities.
- Owner-scoped named geofence CRUD with validated coordinates, radius, and
  manual-only or future device-matching privacy modes.
- Immutable context snapshots containing activity, workout phase, duration,
  target energy, discovery, time bucket, and weekend state.
- Warm-up, sustain, recovery, cooldown, rest, and steady workout phases.
- Manual session setup that works without location permission.
- Persistent browser context selection; new listening events include its
  snapshot ID and no raw coordinates.
- Playback-session and listening-event context relationships with owner checks.
- Activity/place filters on listening history.
- Audited place deletion and forget-learning markers. Deletion removes the
  coordinate-bearing geofence while preserving an opaque historical UUID.
- Context APIs and Django admin access.

## Privacy and deletion semantics

Coordinates exist only on the current `Geofence` record. A snapshot copies the
place name and UUID, never coordinates. Deleting a place deletes coordinates,
records both an audit event and learning cutoff, and leaves immutable playback
history structurally valid. Forget learning creates the cutoff without deleting
the place. Sprint 05 aggregation will exclude forgotten associations.

## Verification

- Manual, permission-free snapshots contain no coordinates.
- Context snapshots reject mutation.
- Places and snapshots are owner scoped.
- Place deletion, coordinate removal, history preservation, audit creation, and
  forget behavior are tested.
- Playback sessions and events carry an owned snapshot.
- Ruff, strict mypy, migrations, pytest, and branch coverage pass.

The project is ready for Sprint 05 deterministic preference learning.
