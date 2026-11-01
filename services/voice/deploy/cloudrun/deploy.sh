#!/usr/bin/env bash
# Deploy pitline-voice (the AI front desk on calls, services/voice) to Cloud Run (project vitalos-workforce,
# europe-west2 London, scale to zero). Run by .github/workflows/voice-deploy.yml; `--dry-run` prints the
# plan and calls nothing. Moved from Azure Container Apps (`autofix-voice`) on 1 Nov 2026 (DECISIONS D25).
#
# Idempotent: deploys a new revision, deletes nothing. Secret values are never printed: they live in Secret
# Manager as pitline-voice--<name> and reach the container as secret references. The relay secret is kept,
# so a re-run does not break calls in flight; the Claude key and the Twilio auth token get a new version
# when given and different, else the existing ones are kept.
#
#   deploy.sh --dry-run
#   deploy.sh apply
#
# Environment (apply): IMAGE (ghcr.io/…, pulled through the Artifact Registry mirror) and gcloud signed in
# as the deploy identity. Optional: ANTHROPIC_API_KEY, TWILIO_AUTH_TOKEN, VOICE_CLAUDE_MODEL, MIN_REPLICAS
# (default 0: scale to zero; 1 keeps an instance warm, a monthly charge, Temitope's call). With
# DEPLOY_OUT_FILE, writes VOICE_RELAY_URL, VOICE_RELAY_SECRET, VOICE_ORIGIN and VOICE_CLAUDE_READY (yes/no)
# there (mode 0600) for the Vercel step.
set -euo pipefail

PROJECT="${GCP_PROJECT:-vitalos-workforce}"
PROJECT_NUMBER="${GCP_PROJECT_NUMBER:-447460690610}"
REGION="${GCP_REGION:-europe-west2}"
SERVICE="pitline-voice"
SECRET_PREFIX="$SERVICE"
RUNTIME_SA="apps-runtime@${PROJECT}.iam.gserviceaccount.com"
MIRROR="${REGION}-docker.pkg.dev/${PROJECT}/ghcr"
HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
AUTOFIX_BASE_URL="${AUTOFIX_BASE_URL:-https://pitline.co.uk}"
MIN_REPLICAS="${MIN_REPLICAS:-0}"
MAX_REPLICAS="${MAX_REPLICAS:-2}"

plan() {
  cat <<PLAN
pitline-voice deployment (project ${PROJECT}, ${REGION})
  Service                ${SERVICE}: public, :8080 (HTTPS and WebSockets), ${MIN_REPLICAS}-${MAX_REPLICAS} instances, 1 vCPU / 512 MiB,
                         20 concurrent calls per instance, timeout 3600 s (the longest a call's socket may stay
                         open), session affinity, runs as ${RUNTIME_SA}
  Endpoints              /readyz (woken by the voice webhook: Cloud Run answers /healthz itself and never passes
                         it on), wss://${HOST}/relay (Twilio ConversationRelay)
  Image                  ghcr.io private package through the Artifact Registry remote repository ${MIRROR}
  Talks to               ${AUTOFIX_BASE_URL} (/api/voice/v1/session, /api/agent/v1/*) and the Claude API
  Secrets                Secret Manager ${SECRET_PREFIX}--voice-relay-secret (kept), --anthropic-api-key,
                         --twilio-auth-token
  Expected cost          £0 at rest with scale to zero (Cloud Run free tier); Claude and Twilio usage per call
PLAN
}

secret_value() { # name -> latest value of pitline-voice--<name>, or empty when it has none
  gcloud secrets versions access latest --secret "${SECRET_PREFIX}--$1" --project "$PROJECT" 2>/dev/null || true
}

put_version() { # name, value: adds a version when the value changed. The secret itself must exist (D25).
  local current
  current="$(secret_value "$1")"
  [[ "$current" == "$2" ]] && return 0
  if ! printf '%s' "$2" | gcloud secrets versions add "${SECRET_PREFIX}--$1" --project "$PROJECT" --data-file=- >/dev/null; then
    echo "deploy: could not add a version to ${SECRET_PREFIX}--$1; if it does not exist, a project owner creates it once (docs/autofix/INFRA.md, Cloud Run)" >&2
    return 1
  fi
  echo "secret ${SECRET_PREFIX}--$1: new version"
}

case "${1:-}" in
  --dry-run)
    plan
    exit 0
    ;;
  apply) ;;
  *)
    echo "usage: deploy.sh --dry-run | apply" >&2
    exit 2
    ;;
esac

: "${IMAGE:?}"
[[ "$IMAGE" == ghcr.io/* ]] || { echo "deploy: IMAGE must be a ghcr.io image (pulled through ${MIRROR})" >&2; exit 2; }
[[ "$MIN_REPLICAS" =~ ^[01]$ ]] || { echo "deploy: MIN_REPLICAS must be 0 or 1" >&2; exit 2; }
RUN_IMAGE="${MIRROR}/${IMAGE#ghcr.io/}"
plan

RELAY_SECRET="$(secret_value voice-relay-secret)"
[[ -n "$RELAY_SECRET" ]] || { echo "deploy: Secret Manager has no ${SECRET_PREFIX}--voice-relay-secret (copied from Azure by migrate.sh stage)" >&2; exit 1; }
[[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$RELAY_SECRET"
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && put_version anthropic-api-key "$ANTHROPIC_API_KEY"
[[ -n "${TWILIO_AUTH_TOKEN:-}" ]] && put_version twilio-auth-token "$TWILIO_AUTH_TOKEN"

secrets=("VOICE_RELAY_SECRET=${SECRET_PREFIX}--voice-relay-secret:latest")
ready=no
if [[ -n "$(secret_value anthropic-api-key)" ]]; then
  secrets+=("ANTHROPIC_API_KEY=${SECRET_PREFIX}--anthropic-api-key:latest")
  ready=yes
fi
twilio=off
if [[ -n "$(secret_value twilio-auth-token)" ]]; then
  secrets+=("TWILIO_AUTH_TOKEN=${SECRET_PREFIX}--twilio-auth-token:latest")
  twilio=on
fi
# Twilio signs the relay URL as it dialled it; the service checks X-Twilio-Signature against this.
env_vars="NODE_ENV=production,AUTOFIX_BASE_URL=${AUTOFIX_BASE_URL},PUBLIC_RELAY_URL=wss://${HOST}/relay"
[[ -n "${VOICE_CLAUDE_MODEL:-}" ]] && env_vars+=",VOICE_CLAUDE_MODEL=${VOICE_CLAUDE_MODEL}"
refs="$(IFS=,; echo "${secrets[*]}")"

echo "== Service"
gcloud run deploy "$SERVICE" --project "$PROJECT" --region "$REGION" --image "$RUN_IMAGE" \
  --service-account "$RUNTIME_SA" --port 8080 --cpu 1 --memory 512Mi \
  --min-instances "$MIN_REPLICAS" --max-instances "$MAX_REPLICAS" --concurrency 20 --timeout 3600 \
  --session-affinity --set-env-vars "$env_vars" --set-secrets "$refs" --update-labels "app=pitline-voice" --quiet

echo "Deployed ${SERVICE}: https://${HOST} (relay wss://${HOST}/relay; Claude key: ${ready}; Twilio signature check: ${twilio}; min instances ${MIN_REPLICAS})"
if [[ -n "${DEPLOY_OUT_FILE:-}" ]]; then
  umask 077
  printf 'VOICE_ORIGIN=https://%s\nVOICE_RELAY_URL=wss://%s/relay\nVOICE_RELAY_SECRET=%s\nVOICE_CLAUDE_READY=%s\n' "$HOST" "$HOST" "$RELAY_SECRET" "$ready" > "$DEPLOY_OUT_FILE"
fi
