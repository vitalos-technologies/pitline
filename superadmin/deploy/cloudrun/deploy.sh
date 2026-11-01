#!/usr/bin/env bash
# Deploy the Pitline Super Admin to Cloud Run (project vitalos-workforce, europe-west2 London, scale to zero).
# Run by .github/workflows/superadmin-deploy.yml; `--dry-run` prints the plan and calls nothing.
#
# Served at https://pitline.co.uk/superadmin through the Pitline app's proxy (DECISIONS D18): the
# service's own run.app address is only Vercel's SUPERADMIN_ORIGIN and answers 404 without the proxy
# secret. Idempotent: deploys a new revision of what exists, deletes nothing. Secret values are never
# printed: they live in Secret Manager as pitline-superadmin--<name> and reach the containers as secret
# references. Existing secrets are kept, so a re-run changes no password (supabase_setup.py reuses the
# connection strings `existing-secrets` exports). Moved from Azure Container Apps on 1 Nov 2026 (D25).
#
#   deploy.sh --dry-run
#   deploy.sh existing-secrets <file>   write the current DATABASE_URL and AUTOFIX_DATABASE_URL (0600)
#   deploy.sh apply                      deploy IMAGE with the connection strings in $DB_ENV_FILE
#
# Environment (apply): IMAGE (ghcr.io/…, pulled through the Artifact Registry mirror), DB_ENV_FILE,
# PRIMARY_OWNER_EMAIL, and gcloud signed in as the deploy identity. Optional: SENTRY_DSN; TWILIO_ACCOUNT_SID
# and TWILIO_AUTH_TOKEN (voicemail playback). With DEPLOY_OUT_FILE, writes SUPERADMIN_ORIGIN and
# SUPERADMIN_PROXY_SECRET there (mode 0600) for the Vercel step.
set -euo pipefail

PROJECT="${GCP_PROJECT:-vitalos-workforce}"
PROJECT_NUMBER="${GCP_PROJECT_NUMBER:-447460690610}"
REGION="${GCP_REGION:-europe-west2}"
SERVICE="pitline-superadmin"
RELEASE_JOB="${SERVICE}-release"
NOTIFY_JOB="${SERVICE}-notify"
SECRET_PREFIX="$SERVICE"
RUNTIME_SA="apps-runtime@${PROJECT}.iam.gserviceaccount.com"
SCHEDULER_SA="apps-scheduler@${PROJECT}.iam.gserviceaccount.com"
MIRROR="${REGION}-docker.pkg.dev/${PROJECT}/ghcr"
ORIGIN="https://${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
PUBLIC_HOST="pitline.co.uk"
PREFIX="/superadmin"

plan() {
  cat <<PLAN
Pitline Super Admin deployment (project ${PROJECT}, ${REGION})
  Service                ${SERVICE}: public, :8000, 0-1 instances, 1 vCPU / 512 MiB, 50 concurrent, timeout 300 s
                         (scale to zero; billed only while serving), runs as ${RUNTIME_SA}
  Release job            ${RELEASE_JOB}: run on every deploy, bin/release.sh (migrates the super admin's own schema)
  Scheduled job          ${NOTIFY_JOB}: manage.py notify_attention, started by Cloud Scheduler job ${NOTIFY_JOB}
                         every 5 minutes (UTC) as ${SCHEDULER_SA}; its paused or running state is kept
  Image                  ghcr.io private package through the Artifact Registry remote repository ${MIRROR}
  Public address         https://${PUBLIC_HOST}${PREFIX} via the Pitline app (Vercel SUPERADMIN_ORIGIN=${ORIGIN},
                         SUPERADMIN_PROXY_SECRET); no DNS change
  Data                   Pitline's Supabase project: schema superadmin_app (role superadmin_app) for its own
                         data, autofix_superadmin for Pitline data (A415)
  Secrets                Secret Manager ${SECRET_PREFIX}--{django-secret-key, database-url, autofix-database-url,
                         superadmin-proxy-secret, autofix-status-token, bootstrap-admin-password}; optional
                         sentry-dsn, twilio-account-sid, twilio-auth-token. Kept; only the connection strings and
                         the optional ones get a new version when their value changes
  Expected cost          £0 at rest: Cloud Run free tier with scale to zero, Secret Manager and Scheduler free tiers
PLAN
}

secret_value() { # name -> latest value of pitline-superadmin--<name>, or empty when it has none
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
  existing-secrets)
    : "${2:?usage: deploy.sh existing-secrets <file>}"
    umask 077
    : > "$2"
    for pair in "DATABASE_URL:database-url" "AUTOFIX_DATABASE_URL:autofix-database-url"; do
      value="$(secret_value "${pair#*:}")"
      if [[ -n "$value" ]]; then
        [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$value"
        echo "EXISTING_${pair%%:*}=$value" >> "$2"
      fi
    done
    exit 0
    ;;
  apply) ;;
  *)
    echo "usage: deploy.sh --dry-run | existing-secrets <file> | apply" >&2
    exit 2
    ;;
esac

: "${IMAGE:?}" "${DB_ENV_FILE:?}" "${PRIMARY_OWNER_EMAIL:?}"
[[ "$IMAGE" == ghcr.io/* ]] || { echo "deploy: IMAGE must be a ghcr.io image (pulled through ${MIRROR})" >&2; exit 2; }
RUN_IMAGE="${MIRROR}/${IMAGE#ghcr.io/}"
plan

# The secrets generated when the super admin was first deployed; Cloud Run reads them by reference.
for name in django-secret-key superadmin-proxy-secret autofix-status-token bootstrap-admin-password; do
  [[ -n "$(secret_value "$name")" ]] || { echo "deploy: Secret Manager has no ${SECRET_PREFIX}--$name (copied from Azure by migrate.sh stage)" >&2; exit 1; }
done
PROXY_SECRET="$(secret_value superadmin-proxy-secret)"
[[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$PROXY_SECRET"

# Connection strings from supabase_setup.py (or the repository secrets).
DATABASE_URL="$(grep '^DATABASE_URL=' "$DB_ENV_FILE" | cut -d= -f2-)"
AUTOFIX_DATABASE_URL="$(grep '^AUTOFIX_DATABASE_URL=' "$DB_ENV_FILE" | cut -d= -f2-)"
[[ -n "$DATABASE_URL" && -n "$AUTOFIX_DATABASE_URL" ]] || { echo "deploy: $DB_ENV_FILE lacks a connection string" >&2; exit 1; }
put_version database-url "$DATABASE_URL"
put_version autofix-database-url "$AUTOFIX_DATABASE_URL"

secrets=(
  "DJANGO_SECRET_KEY=${SECRET_PREFIX}--django-secret-key:latest"
  "DATABASE_URL=${SECRET_PREFIX}--database-url:latest"
  "AUTOFIX_DATABASE_URL=${SECRET_PREFIX}--autofix-database-url:latest"
  "SUPERADMIN_PROXY_SECRET=${SECRET_PREFIX}--superadmin-proxy-secret:latest"
  "AUTOFIX_STATUS_TOKEN=${SECRET_PREFIX}--autofix-status-token:latest"
)
if [[ -n "${SENTRY_DSN:-}" ]]; then
  put_version sentry-dsn "$SENTRY_DSN" && secrets+=("SENTRY_DSN=${SECRET_PREFIX}--sentry-dsn:latest")
fi
# Voicemail playback (Calls). Optional: without them the Calls page works and playback says it is not set up.
if [[ -n "${TWILIO_ACCOUNT_SID:-}" && -n "${TWILIO_AUTH_TOKEN:-}" ]]; then
  put_version twilio-account-sid "$TWILIO_ACCOUNT_SID"
  put_version twilio-auth-token "$TWILIO_AUTH_TOKEN"
  secrets+=("TWILIO_ACCOUNT_SID=${SECRET_PREFIX}--twilio-account-sid:latest" "TWILIO_AUTH_TOKEN=${SECRET_PREFIX}--twilio-auth-token:latest")
fi
# The release job also creates the primary owner as the bootstrap SuperAdmin, with a password nobody
# knows; the owner sets their own with a one-time link (manage.py issue_setup_link).
release_secrets=("${secrets[@]}" "BOOTSTRAP_ADMIN_PASSWORD=${SECRET_PREFIX}--bootstrap-admin-password:latest")

# Plain settings, as YAML (Cloud Run sets PORT itself).
umask 077
ENV_FILE="$(mktemp)"
RELEASE_ENV_FILE="$(mktemp)"
trap 'rm -f "$ENV_FILE" "$RELEASE_ENV_FILE"' EXIT
env_vars=(
  "APP_ENVIRONMENT=production"
  "DJANGO_SETTINGS_MODULE=config.settings.prod"
  "SUPERADMIN_PATH_PREFIX=$PREFIX"
  "APP_BASE_URL=https://$PUBLIC_HOST"
  "AUTOFIX_SUPERADMIN_URL=https://$PUBLIC_HOST$PREFIX"
  "AUTOFIX_APP_URL=https://pitline.co.uk"
  "ALLOWED_HOSTS=$PUBLIC_HOST"
  "CSRF_TRUSTED_ORIGINS=https://$PUBLIC_HOST"
  "TRUSTED_PROXY_COUNT=1"
  # The Supabase pooler may refuse startup options; the role's own defaults (read-only, search_path) apply.
  "AUTOFIX_DB_STARTUP_OPTIONS=False"
  "LOG_FORMAT=json"
  "WEB_CONCURRENCY=2"
  "PRIMARY_OWNER_EMAIL=$PRIMARY_OWNER_EMAIL"
)
env_yaml() { # NAME=value... -> YAML on stdout
  local pair value
  for pair in "$@"; do
    value="${pair#*=}"
    value="${value//\\/\\\\}"
    printf '%s: "%s"\n' "${pair%%=*}" "${value//\"/\\\"}"
  done
}
env_yaml "${env_vars[@]}" > "$ENV_FILE"
env_yaml "${env_vars[@]}" "BOOTSTRAP_ADMIN_EMAIL=$PRIMARY_OWNER_EMAIL" > "$RELEASE_ENV_FILE"

where=(--project "$PROJECT" --region "$REGION")
job_deploy() { # name, env file, secrets (comma-separated), command args...
  local name="$1" env_file="$2" refs="$3"; shift 3
  gcloud run jobs deploy "$name" "${where[@]}" --image "$RUN_IMAGE" --service-account "$RUNTIME_SA" \
    --cpu 1 --memory 512Mi --task-timeout 900s --max-retries 0 --tasks 1 --parallelism 1 \
    --env-vars-file "$env_file" --set-secrets "$refs" "$@" --quiet
}
joined() { local IFS=,; echo "$*"; }

echo "== Release job (migrate the super admin's own schema, create the primary owner)"
job_deploy "$RELEASE_JOB" "$RELEASE_ENV_FILE" "$(joined "${release_secrets[@]}")" --command "bin/release.sh"
gcloud run jobs execute "$RELEASE_JOB" "${where[@]}" --wait --quiet \
  || { echo "deploy: the release job did not succeed (see its logs in Cloud Logging)" >&2; exit 1; }
echo "release job: succeeded"

echo "== Service"
gcloud run deploy "$SERVICE" "${where[@]}" --image "$RUN_IMAGE" --service-account "$RUNTIME_SA" \
  --port 8000 --cpu 1 --memory 512Mi --min-instances 0 --max-instances 1 --concurrency 50 --timeout 300 \
  --env-vars-file "$ENV_FILE" --set-secrets "$(joined "${secrets[@]}")" --update-labels "app=pitline-superadmin" --quiet

echo "== Scheduled job (Pitline alerts into the bell every 5 minutes)"
job_deploy "$NOTIFY_JOB" "$ENV_FILE" "$(joined "${secrets[@]}")" --command "python" --args "manage.py,notify_attention"
scheduler=(--schedule "*/5 * * * *" --time-zone UTC --http-method POST
  --uri "https://run.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/jobs/${NOTIFY_JOB}:run"
  --oauth-service-account-email "$SCHEDULER_SA")
if gcloud scheduler jobs describe "$NOTIFY_JOB" --project "$PROJECT" --location "$REGION" >/dev/null 2>&1; then
  # Updating keeps the job's state: it stays paused until migrate.sh cutover resumes it, so the
  # notifications never go out from Azure and Cloud Run at once.
  gcloud scheduler jobs update http "$NOTIFY_JOB" --project "$PROJECT" --location "$REGION" "${scheduler[@]}" --quiet >/dev/null
else
  gcloud scheduler jobs create http "$NOTIFY_JOB" --project "$PROJECT" --location "$REGION" "${scheduler[@]}" --quiet >/dev/null
fi
echo "scheduler ${NOTIFY_JOB}: $(gcloud scheduler jobs describe "$NOTIFY_JOB" --project "$PROJECT" --location "$REGION" --format='value(state)')"

echo "Deployed ${SERVICE}: origin ${ORIGIN}, public https://${PUBLIC_HOST}${PREFIX}"
if [[ -n "${DEPLOY_OUT_FILE:-}" ]]; then
  printf 'SUPERADMIN_ORIGIN=%s\nSUPERADMIN_PROXY_SECRET=%s\n' "$ORIGIN" "$PROXY_SECRET" > "$DEPLOY_OUT_FILE"
fi
