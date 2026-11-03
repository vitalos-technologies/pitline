# Pitline architecture

Pitline is Vitalos's multi-tenant garage booking platform. Each garage gets a phone-first booking page on its own domain (for example `book.theirgarage.co.uk`) or on a free link (`<slug>.pitline.co.uk`), and runs its diary, customers, reminders, messages and invoices in the garage admin at `pitline.co.uk`. One Next.js app on Vercel serves every garage, the request host decides which garage, and all state lives in one Supabase Postgres database in London with row-level security on `garage_id`. A Django super admin and an AI voice desk run as separate containers on Google Cloud Run.

This folder is a snapshot of the architecture, drawn from the code at `82578f9` on 3 Nov 2026.

## Views

| View | File | What it shows |
| --- | --- | --- |
| Visual page | [index.html](index.html) | Every view below on one page, with a hand-drawn container diagram, light and dark themes |
| System context and containers | [01-context-containers.md](01-context-containers.md) | Who uses Pitline, the outside services it depends on, and the deployable parts |
| Data model | [02-data-model.md](02-data-model.md) | Five domain ERDs, tenancy and RLS rules, and an inventory of all 93 tables |
| Deployment and CI/CD | [03-deployment-cicd.md](03-deployment-cicd.md) | Vercel, Cloud Run and Supabase topology, environments, workflows |
| Key flows and security | [04-flows-security.md](04-flows-security.md) | Booking, reminder, AI voice desk, custom domain and super admin flows; trust boundaries and controls |

## Key facts

| | |
| --- | --- |
| Stack | Next.js 16 (App Router, `src/proxy.ts`), React 19, Tailwind 4, zod, Supabase JS; Node 22 voice service; Python 3.12 Django 5.2 super admin |
| Hosting | Vercel (functions in London, `lhr1`); Google Cloud Run in London for the super admin and the voice desk |
| Data | Supabase Postgres 17 in London: 93 tables over 36 migrations, RLS on every tenant table, `btree_gist` exclusion constraint against double bookings; Supabase Auth with TOTP; Supabase Storage (3 buckets) |
| Providers | Twilio, Resend, DVLA, DVSA, Vehicle Data Global, Stripe (test mode), Vercel Domains API, Anthropic Claude, Xero, QuickBooks, Sage, Google Places, Cloudflare (Turnstile and inbound email), Sentry |
| Vitalos links | Askbridge chat widget on booking pages; Workforce agents through the agent tool API; product status for the Vitalos platform Product Pipeline; super admin modelled on the Vitalos platform Super Admin |
| Repo | `vitalos-technologies/pitline` (private) |
| Status | Phases 1 to 5 built and their gates passed in CI; Gate 4 (first garage live on its own domain) waits on owner steps listed in `docs/autofix/DECISIONS.md` |

## How to view

Open `index.html` in a browser. Every diagram is pre-rendered into the page in light and dark versions, so it works offline and in app file viewers; a diagram edited without re-baking renders live from jsDelivr (`mermaid@11.4.1`) instead. The Markdown files render on GitHub. After editing a Mermaid diagram, re-bake the page with the Vitalos archkit bake script so it keeps working offline.

## How to update

1. Read the change in `docs/autofix/ARCHITECTURE.md`, `supabase/migrations/` and `.github/workflows/`.
2. Edit the Mermaid block in the Markdown file and the matching `<script type="text/plain" class="mmd">` block in `index.html`; keep the two identical.
3. Update the counts in the overview and the snapshot commit in the footer.
4. Check both themes and a 390 px wide window before committing.

Source documents this snapshot reconciles: `docs/autofix/SPEC.md`, `docs/autofix/ARCHITECTURE.md`, `docs/autofix/INFRA.md`, `docs/autofix/DECISIONS.md`, `docs/autofix/BUILD-PLAN.md`, `docs/autofix/askbridge.md`, `docs/autofix/voice-desk.md`, `superadmin/README.md`, `infrastructure/RUNNER.md`.
