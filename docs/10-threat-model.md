# uMusic threat model

## Assets and trust boundaries

Protected assets are owner credentials, revocable device tokens, Cloudflare tunnel
credentials, MP3 files, signed download URLs, listening history, learned preferences,
named-place coordinates, HealthKit data, backups, and PostgreSQL data.

Trust boundaries are: Apple device → Cloudflare edge → outbound tunnel → Nginx →
Django; Django/Celery → Redis/PostgreSQL; application → local or mounted/GFS media;
and import workers → untrusted remote URLs and MP3 payloads.

## Primary threats and controls

| Threat | Controls | Residual risk |
|---|---|---|
| Password or session theft | HTTPS edge, secure cookies, CSRF, rate limits, no secrets in logs | Compromised client can act until credential rotation |
| Device-token theft | Random secret, SHA-256 server storage, scope checks, Keychain, immediate revocation | Token remains usable until revoked |
| MP3 URL sharing | Short-lived signed URL bound to a non-revoked device, no-store, 15-minute expiry | File may be copied after legitimate download |
| Cross-owner access | Owner filters on devices, contexts, playlists, sessions, exports, and evaluation | Shared catalog metadata is intentionally global |
| Location disclosure | Manual default, one-shot matching, opaque geofence IDs in events, raw route opt-in, local erase | Device/OS backups may contain opted-in local route |
| Health data disclosure | Optional explicit authorization; no Health samples sent to backend | Apple Health retains user-approved workouts |
| Malicious import | MP3-only content validation, size/item limits, quarantine, controlled adapters, checksum storage | Decoder vulnerabilities require timely FFmpeg/Mutagen updates |
| Path traversal | Logical checksum object keys and configured import roots | Misconfigured mounted filesystem permissions |
| SSRF/remote fetch abuse | Feature flag, URL validation, bounded jobs, owner authentication | Approved remote hosts can return malicious/large content |
| Backup theft or loss | Restricted backup directory, checksum manifest, off-host encryption requirement, restore drills | Operator must configure encryption and retention |
| Cloudflare misconfiguration | Outbound-only origin, separate browser/API policies, application Bearer auth retained | Edge bypass if origin ports are accidentally published |
| Recommendation manipulation | Append-only events, idempotent client event IDs, explicit dislikes as hard exclusions, versioned deterministic fallback | Single-owner self-hosted data poisoning is still possible |

## Logging rules

Never log passwords, device secrets, tunnel tokens, authorization headers, signed
download URLs, exact coordinates, HealthKit data, or full remote-source query strings.
Request IDs, opaque object IDs, status codes, latency, counts, and reason codes are
allowed.

## Security release review

Before each release: update pinned images/libraries, run dependency and container
scans, verify no origin ports in production Compose, test owner isolation and revoked
downloads, inspect logs for prohibited fields, rotate test credentials, and execute an
isolated restore. Any authentication, owner-isolation, arbitrary-file, or irreversible
data-loss defect blocks release.
