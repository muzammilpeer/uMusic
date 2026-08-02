---
name: umusic-development
description: Develop, diagnose, plan, test, and deploy the uMusic private music server and SwiftUI iPhone, iPad, and macOS client. Use for uMusic backend, Django API, Docker, playback, offline caching, workout/HealthKit/location personalization, library sync, deletion, multi-user/sharing sprints, Apple client UI, or production troubleshooting in this repository.
---

# uMusic development

## Start

1. Inspect only files relevant to the request; the worktree may contain user changes.
2. Read [references/product.md](references/product.md) before changing behavior or UX.
3. Read [references/apple-client.md](references/apple-client.md) for Swift, playback, offline, HealthKit, location, or lifecycle work.
4. Read [references/backend-operations.md](references/backend-operations.md) for Django, API, storage, Docker, Cloudflare, deletion, or deployment work.
5. Read [references/troubleshooting.md](references/troubleshooting.md) only for playback,
   sync, UUID routing, cache, HTTP 4xx/5xx, or production incident diagnosis.
6. Read [../../../docs/PROJECT_MEMORY.md](../../../docs/PROJECT_MEMORY.md) only when the
   task requires overall project status or roadmap context.
7. Implement with `apply_patch`; avoid broad rewrites.
8. Run the proportional validations listed below.

## Validation

Apple core tests:

```sh
swift test --package-path clients/UMusic
```

iOS and macOS compile checks (use `/tmp` to avoid DerivedData sandbox failures):

```sh
xcodebuild -quiet -project clients/UMusic/UMusic.xcodeproj -scheme UMusic -destination 'generic/platform=iOS' -derivedDataPath /tmp/umusic-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project clients/UMusic/UMusic.xcodeproj -scheme UMusic -destination 'generic/platform=macOS' -derivedDataPath /tmp/umusic-macos CODE_SIGNING_ALLOWED=NO build
```

Backend checks:

```sh
python3 -m compileall -q umusic config
docker compose exec -T web python manage.py check
curl -fsS http://127.0.0.1:8000/health/ready/
```

The production Docker image does not include `pytest`; run pytest in the development environment when available. Rebuild/restart only changed services. Never remove Docker volumes.

For planning-only documentation changes, verify links/files and do not rebuild or deploy
unaffected services.

## Handoff

State behavior changed, important limitations, files changed, validations passed, and whether a Docker service was deployed. Do not claim an Apple API exposes data that it does not.
