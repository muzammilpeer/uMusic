# Cloudflare Zero Trust deployment

uMusic uses a remotely managed Cloudflare Tunnel as its only ingress. `cloudflared`
makes outbound connections to Cloudflare; the server does not publish Nginx, Django,
PostgreSQL, or Redis ports. Cloudflare terminates public HTTPS and forwards traffic to
`http://proxy:8080` inside the Compose network. Nginx retains rate limiting and
authorized internal MP3 delivery.

## Dashboard setup

1. In Cloudflare Zero Trust, create a remotely managed tunnel and add a public
   hostname such as `music.example.com` whose service is `http://proxy:8080`.
2. Copy the tunnel token into the server-only `.env.prod` as
   `CLOUDFLARE_TUNNEL_TOKEN`. Anyone holding this token can run the tunnel, so never
   commit it, put it in an iPhone build, or include it in logs.
3. Set `DJANGO_ALLOWED_HOSTS=music.example.com` and
   `DJANGO_CSRF_TRUSTED_ORIGINS=https://music.example.com`.
4. Start the stack with `docker compose -f compose.prod.yaml up -d --build`.
5. Confirm that no application port is published with `docker compose ps`, then test
   `https://music.example.com/health/ready/`.

## Access policy and the iPhone API

Cloudflare Access browser login is suitable for the web dashboard, but an iOS
background client cannot complete an interactive Access redirect while syncing or
downloading. Use two Access applications on the same hostname:

- protect browser/admin paths with an identity Allow policy;
- configure the more-specific `/api/*` application for the intended mobile access
  model, while retaining uMusic's revocable Bearer device token on every JSON API
  request and signed, short-lived MP3 download authorization.

For a strictly private family deployment, prefer enrolling the iPhone in the Zero
Trust organization with the Cloudflare One Agent/WARP and restrict the API policy to
enrolled devices. If using an Access service token instead, treat it as an additional
edge credential and keep it in iOS Keychain; it does not replace the uMusic device
token. Never configure Access to consume the standard `Authorization` header because
uMusic uses that header for its Bearer token.

Create the Access application before publishing the tunnel hostname, enable tunnel
health notifications, and rotate a disclosed tunnel token in the dashboard.

## Verification

```bash
curl --fail https://music.example.com/health/ready/
curl --fail https://music.example.com/health/metrics/
docker compose -f compose.prod.yaml logs --tail=100 tunnel proxy web
```

The tunnel exposes metrics on port 20241 only inside the Compose network. Add a
second connector on another server later if tunnel high availability is required.
