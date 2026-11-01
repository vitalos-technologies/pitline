# autofix-voice

The AI front desk on calls (DECISIONS D20, [docs/autofix/voice-desk.md](../../docs/autofix/voice-desk.md)). A small Node 22 service: Twilio ConversationRelay connects a missed call's audio-as-text to `wss://<host>/relay`; the desk answers with Claude and books through Pitline's agent tool API with a per-call token. The design comes from Answerd's desk (vitalos-technologies/workforce).

```bash
pnpm install
pnpm verify        # typecheck, tests, build
pnpm build && VOICE_RELAY_SECRET=… ANTHROPIC_API_KEY=… AUTOFIX_BASE_URL=http://localhost:3000 pnpm start
```

| Env | |
| --- | --- |
| `VOICE_RELAY_SECRET` | 32+ characters, the same value as the Pitline app's. Checks the relay claim; the key for `/api/voice/v1/session` |
| `ANTHROPIC_API_KEY` | Claude. Without it `/readyz` is 503 and calls are refused (Twilio then falls back to the voicemail) |
| `AUTOFIX_BASE_URL` | default `https://pitline.co.uk` |
| `VOICE_CLAUDE_MODEL` | default `claude-haiku-5-5` |
| `TWILIO_AUTH_TOKEN`, `PUBLIC_RELAY_URL` | optional: also check `X-Twilio-Signature` on the upgrade, against `PUBLIC_RELAY_URL` + query |
| `VOICE_MAX_CALL_SECONDS` | default 600 |
| `PORT` | default 8080 |

Endpoints: `GET /healthz` (always 200; local and container checks only, because Cloud Run answers `/healthz` itself and never passes it to the app), `GET /readyz` (the voice webhook fetches it to wake the service), `GET /relay` (WebSocket).

Logs are JSON lines with ids, tool names, outcomes and timings only: never a number, registration, transcript, token or key.

## Deploy

Actions > **Voice desk deploy**: `CHECK` lists which secrets are set and checks the GCP sign-in; `DEPLOY` verifies, builds `ghcr.io/vitalos-technologies/autofix-voice`, deploys it to the Cloud Run service `pitline-voice` (project `vitalos-workforce`, europe-west2; image pulled through the Artifact Registry mirror `europe-west2-docker.pkg.dev/vitalos-workforce/ghcr/…`; timeout 3600 s, session affinity; `deploy/cloudrun/deploy.sh`, `--dry-run` prints the plan), checks `/readyz` and that the relay refuses a socket without a claim, and, once it has a Claude key, sets `VOICE_RELAY_URL` and `VOICE_RELAY_SECRET` in Vercel (Production) and redeploys. It signs in with Workload Identity Federation (no key); its secrets live in Secret Manager as `pitline-voice--voice-relay-secret`, `--anthropic-api-key` and `--twilio-auth-token`. Repository secrets: `VERCEL_API_TOKEN`, plus `ANTHROPIC_API_KEY` and optionally `TWILIO_AUTH_TOKEN` (given values become new Secret Manager versions). Scale to zero by default (£0 at rest); `min_replicas=1` keeps one instance warm (a monthly charge, Temitope's call). Moved from Azure Container Apps on 1 Nov 2026 (DECISIONS D25).
