# uMusic

uMusic is a private, self-hosted, activity-aware MP3 server with a web portal and a
native SwiftUI player for iPhone, iPad, and macOS. It keeps playback offline-first,
learns from listening behavior, and builds music sessions for cycling, running, walking,
gym, focus, relaxation, places, and custom activities.

> uMusic is a personal learning project, not a hosted music service. Import only audio
> you own or are authorized to download and store, and follow source-site terms and
> applicable law.

## Highlights

- MP3-only single and batch upload with metadata editing and ID3 support.
- Direct MP3 and YouTube URL import through isolated Celery workers.
- Web library, search, playlists, browser playback, devices, privacy controls, and
  recommendation evaluation.
- Swift 5 SwiftUI app shared across iPhone, iPad, and native macOS.
- Manual library Sync: cached metadata remains usable without an automatic launch fetch.
- Offline-first playback with SHA-256 verification, resumable files, configurable quota,
  Wi-Fi/charging policies, rolling prefetch, and LRU eviction.
- Restored song, queue, seek position, mini player, Now Playing metadata, media keys, and
  Lock Screen/Control Center commands.
- Compact iOS and macOS Share Extension that accepts a YouTube URL and queues MP3 import.
- Activity-aware recommendations, custom activities, workout phases, optional places,
  and battery-conscious context collection.
- Optional iPhone HealthKit workout and heart-rate metrics. macOS retains manual activity
  sessions; HealthKit and iPhone motion detection remain platform-specific.
- Local filesystem storage by default, with a filesystem abstraction suitable for a
  Docker-mounted GFS/GlusterFS-style shared volume.
- PostgreSQL, Redis, Celery, Docker health checks, backup/restore tooling, and deployment
  behind Cloudflare Zero Trust.

## Architecture

```text
iPhone / iPad / macOS / Browser
              │
      HTTPS + device tokens
              │
     Django + Django REST Framework
        │          │          │
   PostgreSQL    Redis     Celery workers
                              │
                  MP3/YouTube import + ID3
                              │
              Local or mounted shared storage
```

The backend is a modular Django monolith. Media is accessed through a storage abstraction;
database records never expose host filesystem paths to clients. The Apple app downloads
signed media, verifies its checksum, and always tries the local cached MP3 before requesting
a new stream.

## Technology

- Python 3.13, Django 5.2, Django REST Framework
- PostgreSQL 17, Redis 8, Celery 5
- FFmpeg/ffprobe, yt-dlp, Mutagen
- Django templates and browser audio
- Swift 5, SwiftUI, AVFoundation, MediaPlayer, HealthKit, Core Location, Core Motion
- Docker Compose and optional Cloudflare Zero Trust

## Quick start with Docker

Requirements: Docker with Compose and enough persistent storage for your MP3 collection.

```bash
cp .env.example .env
```

Replace `DJANGO_SECRET_KEY` and review hosts, origins, storage paths, import flags, and
limits before starting:

```bash
docker compose up --build -d
docker compose ps
curl -fsS http://127.0.0.1:8000/health/ready/
```

Create the first owner without putting a real password in source control:

```bash
export UMUSIC_OWNER_USERNAME=owner
export UMUSIC_OWNER_EMAIL=owner@example.test
export UMUSIC_OWNER_PASSWORD='replace-with-a-long-password'
docker compose exec web python manage.py bootstrap_owner
```

Open [http://localhost:8000/](http://localhost:8000/). For LAN access, add the server IP
to `DJANGO_ALLOWED_HOSTS` and its full origin to `DJANGO_CSRF_TRUSTED_ORIGINS`.

Named Docker volumes contain PostgreSQL, Redis, media, quarantine, and backups. Do not
remove them during normal upgrades.

## YouTube and remote imports

Set the import flags intentionally in `.env`:

```dotenv
UMUSIC_REMOTE_IMPORT_ENABLED=true
UMUSIC_YOUTUBE_IMPORT_ENABLED=true
```

Paste comma/newline-separated links in the web or Apple app, or use **Import to uMusic**
from the iOS/macOS Share menu. The server queues the job, extracts available source
metadata, converts authorized content to MP3, writes ID3 tags, and imports it into the
library. Press **Sync** in the Apple app after processing completes.

## Apple app

1. Open `clients/UMusic/UMusic.xcodeproj` in Xcode.
2. Select the `UMusic` scheme and an iPhone, iPad, or **My Mac** destination.
3. Select your development team and change bundle identifiers if necessary.
4. For physical iOS Health features, enable HealthKit for the app identifier.
5. Enable Keychain Sharing for the app and Share Extension identifiers. Keep their
   shared group aligned with the entitlements if you change the team or bundle IDs.
6. Run, enter the server URL, and sign in. The device token is stored in Keychain and can
   be revoked from the server portal.

The configured build currently defaults to `https://umusic.muzammilpeer.uk/`; the login
screen remains editable for another deployment. HTTPS is recommended outside local
development.

Platform notes:

- iPhone/iPad: background audio, Lock Screen controls, optional HealthKit, motion activity,
  coarse workout location, and Share Extension.
- macOS: equivalent library, search, playlists, online/offline playback, downloads,
  quotas, import, Share Extension, manual activities, places, player, and administration.
  HealthKit and iPhone motion classification are shown as unavailable instead of exposing
  inactive controls.
- Apple does not expose AirPods or generic Bluetooth-headset battery percentages to a
  normal third-party music app. uMusic reports the route and directs users to system UI.

See [the Apple client guide](clients/UMusic/README.md) for build and privacy details.

## Development and verification

For local Python development:

```bash
make bootstrap
make migrate
make check
```

Apple checks:

```bash
swift test --package-path clients/UMusic
xcodebuild -quiet -project clients/UMusic/UMusic.xcodeproj -scheme UMusic \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-ios \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project clients/UMusic/UMusic.xcodeproj -scheme UMusic \
  -destination 'generic/platform=macOS' -derivedDataPath /tmp/umusic-macos \
  CODE_SIGNING_ALLOWED=NO build
```

Physical iPhone testing is still required for HealthKit, locked-screen/background audio,
Bluetooth controls, real network transitions, and measured battery use.

## Documentation

- [Product specification](docs/01-product-specification.md)
- [Architecture](docs/02-architecture.md)
- [Data and learning](docs/03-data-and-learning.md)
- [API contract](docs/05-api-contract.md)
- [Deployment](docs/06-deployment.md)
- [Definition of done](docs/08-definition-of-done.md)
- [Cloudflare Zero Trust](docs/09-cloudflare-zero-trust.md)
- [Threat model](docs/10-threat-model.md)
- [Operations runbook](docs/11-operations-runbook.md)
- [Release checklist](docs/12-release-checklist.md)
- [Sprint workspace and implementation prompts](docs/sprints/README.md)

## Roadmap

The currently documented future sequence is:

- Sprint 14: multi-user accounts, private libraries, quotas, and strict tenant isolation.
- Sprint 15: private playlist sharing with owner/editor/viewer roles and invitations.
- Sprint 16: synchronized Listening Rooms with pre-caching, realtime coordination, and
  measured LAN/internet drift correction.

These roadmap items are not current security or product guarantees until their exit
criteria pass.

## Security and privacy

- Device tokens are stored in Keychain and are individually revocable.
- Raw workout routes are opt-in and locally erasable.
- Location defaults to one coarse workout-scoped fix rather than continuous tracking.
- Listening telemetry is batched to reduce network and battery cost.
- Secrets, `.env` files, media, databases, and signing material must never be committed.

Review the [threat model](docs/10-threat-model.md) and
[deployment guide](docs/06-deployment.md) before exposing a server outside your LAN.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), the active sprint folder, and
[AGENTS.md](AGENTS.md) before changing behavior. Preserve migrations and API contracts,
add tests for behavior changes, and validate both Apple targets after shared Swift edits.

## License

No open-source license has been selected yet. Until a `LICENSE` file is added, all rights
are reserved by the repository owner.
