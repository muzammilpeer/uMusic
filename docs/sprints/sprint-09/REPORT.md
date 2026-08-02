# Sprint 09 report — Production deployment and mobile API freeze

## Delivered

- Production Compose topology with private Django, workers, PostgreSQL, and Redis.
- Cloudflare Tunnel as the only ingress; no host application port is published.
- Nginx internal MP3 delivery, edge/origin rate limits, and forwarded HTTPS handling.
- Local directory and mounted GFS/GlusterFS-style media configuration.
- Hashed, scoped, revocable device tokens with rotation and last-seen tracking.
- Immutable offline sync plans, checksum manifests, 15-minute signed downloads, and
  device-revocation enforcement.
- Sync acknowledgements and the existing owner-scoped idempotent 500-event batch API.
- Structured request logs with request IDs, dependency health, and Prometheus text metrics.
- Frozen OpenAPI 1.0.0 contract and Swift-consumable JSON/model fixtures.

## Frozen mobile contract

The authoritative contract is [openapi-v1.yaml](../../api/openapi-v1.yaml). Breaking
changes require a new API version. Device secrets are returned only when issued or
rotated and must be stored in iOS Keychain. The database stores only SHA-256 token
hashes. MP3 manifests retain stable identity while their signed download URLs expire.

## Verification

- 75 tests pass, including token revocation, manifest checksums, acknowledgement,
  signed download, expired authorization behavior, and event idempotency.
- Coverage is 86%, above the 85% gate.
- Ruff, strict mypy, migration consistency, and production Compose validation pass.
- Backup/restore tests include the new device and sync records through Django fixtures.

## Deployment gate

Local container deployment can be verified without Cloudflare. The final public HTTPS
smoke test requires the operator's Cloudflare hostname, remotely managed tunnel token,
and Access policy; none belong in source control. Follow
[09-cloudflare-zero-trust.md](../../09-cloudflare-zero-trust.md), then record the
hostname readiness result before declaring the external deployment complete.

## Sprint 10 readiness

Sprint 10 can consume the frozen fixtures to implement onboarding, Keychain storage,
online catalog/playback, background audio, and event upload. Cloudflare Access must be
configured so background iOS API/download requests do not receive interactive browser
redirects.
