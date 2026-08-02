# Product specification

## Vision

uMusic is a personal music brain: it owns the playback history and recommendation
logic, works from a private MP3 collection, and prepares music for the situation
the user is about to enter.

## Primary experiences

### Library owner

The owner can upload MP3 files, correct metadata, organize tracks, inspect import
failures, find duplicates, and delete or replace files. Only MP3 is accepted in
the first release. Other audio formats return a clear validation error.

### Web listener

The listener can browse, search, play, pause, seek, change volume, queue tracks,
and use previous/next controls. Playback continues while navigating within the
web application. Every meaningful interaction produces a listening event.

### Context-aware listener

The listener chooses an activity such as cycling, running, gym, focus, walking,
commuting, relaxing, or a custom activity. They may optionally choose a saved
place/geofence, desired energy, duration, and discovery level. uMusic creates a
session playlist and explains the main reasons for its choices.

### Library trainer

The listener can explicitly teach the system:

- like or dislike a track;
- prefer or avoid it for an activity;
- associate or disassociate it with a saved place;
- request more or less of an artist, genre, mood, or tempo range;
- mark a track as unsuitable for workouts or focus;
- pin a track or playlist so exploration never removes it.

### Offline iPhone listener

The iPhone user prepares a session at home, downloads an immutable playlist
manifest plus MP3 files, and plays it with no network. Background audio, Lock
Screen controls, headphone controls, and deferred event upload are required.

If the prepared offline pool is exhausted and connectivity is available, the app
requests a continuation from the server. It streams the next selected track and
prefetches later tracks into a bounded local cache. Without connectivity, it
falls back to compatible tracks already cached on the device and then stops
gracefully when no playable files remain.

## Context model

A playback session may include:

- activity type;
- workout phase: warm-up, steady, intense, recovery, cooldown;
- user-entered energy target;
- saved place/geofence ID;
- time-of-day bucket;
- weekday/weekend;
- planned duration;
- familiar-versus-discovery preference;
- device and offline state.

Raw GPS coordinates are not recommendation features. The phone or backend maps a
coordinate to a user-defined geofence and records only that geofence ID unless
the user explicitly enables route history.

## Functional scope

### Version 1: backend and web

- Single-user deployment with a clean path to multiple users.
- MP3 upload and server-side directory import.
- ID3 metadata extraction and editable metadata.
- Album artwork upload/extraction.
- HTTP byte-range streaming.
- Local-volume and Docker-mounted shared-filesystem storage.
- Web player and persistent queue.
- Playlists, smart playlists, and session playlists.
- Listening event collection.
- Rule-based recommendations and explanations.
- Saved activities and geofences.
- Background learning jobs.
- Admin health and storage screens.

### Version 2: intelligence

- Feature extraction from metadata and listening behavior.
- Per-context affinity scores.
- Exploration versus familiarity control.
- Automatic playlist refresh.
- Evaluation dashboard and recommendation versioning.
- Import of taste signals from user-authorized exports.

### Version 3: iPhone

- SwiftUI client.
- Background and offline playback.
- Wi-Fi-only resumable sync.
- Activity session controls.
- Optional Core Location and HealthKit integration.
- On-device event queue and later reconciliation.

### Future

- Podcast/RSS ingestion and spoken-word queues.
- Apple Watch companion.
- Heart-rate zones when permission and hardware are available.
- CarPlay.
- Household/multi-user recommendations.

## Explicit non-goals for the first release

- Supporting FLAC, WAV, AAC, or video storage.
- Public music hosting or sharing.
- Social features.
- A large-language-model recommendation system.
- Continuous storage of exact location.
- Podcast support before music recommendations are validated.
- A microservice architecture.

## Success metrics

- A 60-minute generated playlist can play without interruption.
- At least 95% of valid MP3 uploads are indexed without manual repair.
- Playback event loss is below 1% during normal web usage.
- At least 80% of generated workout tracks are completed after sufficient data.
- Recommendation generation takes less than two seconds for 50,000 tracks.
- An offline iPhone session starts with no server connectivity.
- Every recommendation can return human-readable reason codes.
