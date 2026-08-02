# Product contract

- Private/self-hosted adaptive MP3 music system; public release is not assumed.
- Backend: Django 5.2, PostgreSQL, Redis/Celery, Docker, local or GFS-style storage abstraction.
- Client: Swift 5 SwiftUI targeting iPhone, iPad, and macOS. Production server is `https://umusic.muzammilpeer.uk/` through Cloudflare Zero Trust.
- Accept direct uploads as MP3 only. Remote import supports comma-separated direct MP3/YouTube URLs and writes useful ID3 metadata.
- Library metadata is local-first. Do not fetch it automatically at launch; the user presses Sync.
- Playback is offline-first. Prefer a cached MP3, restore the last track/queue/seek position paused, and stream only when unavailable locally.
- Use one shared offline cache manager across player and download views. Library and
  form content must remain scrollable above the mini player and keyboard.
- Offline downloads default to Wi-Fi-only and obey a hard user quota. Available quota choices include 100 MB and 500 MB. Evict least-recently-used rolling items first.
- Preserve listening history for learning. Batch telemetry and avoid unnecessary disk/network wakeups.
- Server song deletion is administrator-only, confirmed, deactivates the track, deletes its MP3, audits the action, and preserves history. Playlist removal does not delete the MP3. Offline deletion affects only the device.
- Personalization covers cycling, running, walking, gym, focus, relaxation, and future podcasts. Manual activity selection must always work.
- uMusic Low Energy Mode defaults on. Never silently broaden sensor, cellular, storage, deletion, or external-service scope.
- Offline session intensity currently uses an internal balanced target; avoid unlabeled
  or unexplained controls.
- YouTube downloading is for the owner's private learning setup. Keep import code isolated and honor upstream service/legal constraints in technical design.
- Multi-user isolation and playlist sharing are planned in Sprints 14 and 15 and are not
  current guarantees. Never expose personal history, fitness, location, contexts, or
  learned taste through sharing.
- Synchronized Listening Rooms are planned for Sprint 16 after isolation and sharing.
  Coordinate authorized local/cache playback with measured clock/drift handling; do not
  promise sample-accurate audio or continuous iOS background WebSockets without proof.
