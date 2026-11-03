# Key flows and security

Snapshot `82578f9`, 3 Nov 2026. Back to [README](README.md).

## Key flows

### 1. Online booking on a garage host

The host decides the garage before anything renders. Booking state between steps is a sealed, httpOnly cookie, so a registration never appears in a URL, analytics event or ordinary log.

```mermaid
sequenceDiagram
  autonumber
  actor C as Car owner
  participant P as Proxy
  participant B as Booking pages
  participant E as Booking engine
  participant DB as Postgres
  participant Q as Job queue
  C->>P: GET book.garage.co.uk
  P->>DB: Resolve host to garage, 60 s cache
  P->>B: Rewrite to /_site/garageId
  C->>B: Steps 1 to 4, vehicle, service, time, details
  Note over C,B: State lives in the sealed af_booking cookie,<br/>never in the URL
  B->>E: getAvailableSlots for the garage
  E->>DB: available_slots()
  C->>B: Confirm, with Turnstile token
  B->>E: createBooking with idempotency key
  E->>DB: create_booking() in one transaction
  alt Slot still free
    DB-->>E: booking, reference
    E->>Q: enqueue notifications.booking
    B-->>C: Confirmed page with reference
  else no_overlap or SLOT_UNAVAILABLE
    DB-->>E: SLOT_UNAVAILABLE
    B-->>C: Three nearest free slots
  end
  Q-->>C: Email with calendar file, text on chosen channel
```

### 2. MOT or service reminder that wins a booking back

Scheduling and consent checks live in SQL; the send respects quiet hours (09:00 to 19:00, Monday to Saturday, in the garage's time zone). A booking made from the reminder link is credited to that reminder in the same transaction.

```mermaid
sequenceDiagram
  autonumber
  participant VC as Vercel Cron
  participant R as Job runner
  participant DB as Postgres
  participant T as Twilio
  actor C as Customer
  participant B as Booking pages
  VC->>R: GET /api/cron/daily with bearer secret
  R->>DB: schedule_reminders() per active garage
  Note over R,DB: Only consenting, not opted-out customers,<br/>MOT rows only when mot_enabled
  R->>R: reminders.send, inside 09:00 to 19:00 Mon to Sat?
  alt Outside the send window
    R->>DB: Re-queue at the next window
  else Inside the window
    R->>DB: claim_reminder_sends() re-checks consent
    R->>T: Send SMS or WhatsApp with /r/token link
    T-->>R: Accepted, provider id
    T->>R: Delivery status webhook, signature checked
  end
  C->>B: Opens /r/token
  B->>DB: Hash token, mark opened
  B-->>C: Prefilled booking draft in sealed cookie
  C->>B: Completes booking
  B->>DB: create_booking() credits the reminder
```

### 3. Missed call answered by the AI voice desk (Pro)

Twilio rings the garage first. A missed call on a Pro garage with AI minutes left hears the disclosure and is connected to the voice desk, which can only use the agent tool API with a token scoped to that one call. Bookings it makes are always requests for staff to accept. Anything else falls back to voicemail and a text-back.

```mermaid
sequenceDiagram
  autonumber
  actor X as Caller
  participant T as Twilio
  participant W as Voice webhook
  participant V as Voice desk
  participant A as Agent tool API
  participant L as Claude
  X->>T: Calls the garage number
  T->>W: POST /api/webhooks/twilio/voice, signed
  W->>T: Ring the garage phone first
  alt Missed and Pro with AI minutes left
    W->>T: Disclosure, then ConversationRelay to the voice desk
    T->>V: WebSocket with signed claim
    V->>A: Exchange claim for a per-call agent token
    loop Each turn
      V->>L: Streamed turn with tools
      L-->>V: Tool call
      V->>A: available_slots, lookup_vehicle, create_booking
      A-->>V: Result, bookings stay requests
    end
    V->>A: report_usage, log_call_summary
  else Essentials, over allowance or desk down
    W->>T: Voicemail
    W->>W: Queue calls.text_back
  end
```

### 4. Connecting a garage's own booking domain

```mermaid
sequenceDiagram
  autonumber
  actor O as Garage owner
  participant AD as Garage admin
  participant DB as Postgres
  participant VD as Vercel Domains API
  participant R as Job runner
  O->>AD: Enter book.theirgarage.co.uk
  AD->>VD: Add domain to the project
  AD->>DB: garage_domains row, pending_dns
  AD-->>O: CNAME record to add at their DNS host
  loop domains.check, up to 48 hours
    R->>VD: Read domain config
    VD-->>R: Misconfigured, verifying or valid
    R->>DB: Update status
  end
  Note over DB: Once active, the proxy serves the<br/>garage on that host with its own CSP
```

### 5. A Vitalos staff change in the super admin

```mermaid
sequenceDiagram
  autonumber
  actor S as Vitalos staff
  participant P as Proxy
  participant D as Django super admin
  participant DB as Pitline Postgres
  S->>P: /superadmin/...
  P->>D: Forward with proxy secret, afsa cookies only
  D->>D: Password, axes lockout, TOTP
  S->>D: Change a garage plan, with reason
  D->>D: Fresh TOTP step-up, role check
  D->>DB: platform_update_garage() as linked platform admin
  DB->>DB: Write platform_audit_log and garage audit log
  DB-->>D: Updated
  D->>D: Append to its own audit trail
```

## Security

### Trust boundaries

```mermaid
flowchart LR
  subgraph pub["Untrusted: public internet"]
    browser(["Browsers"]):::person
    callers(["Callers"]):::person
    agentsx["AI agents with tokens"]:::ext
  end
  subgraph edgectl["Edge controls"]
    proxy["Proxy: host to garage,<br/>CSP, frame-ancestors"]:::sec
    turnstile["Turnstile and rate limits"]:::sec
    sig["Webhook signatures<br/>Twilio, Stripe, Resend, Cloudflare"]:::sec
  end
  subgraph app["Trusted: application"]
    nextjs["Next.js server code"]:::web
    voice["Voice desk"]:::svc
    sa["Super admin"]:::web
  end
  subgraph data["Restricted: data"]
    rls[("Tenant tables, RLS on garage_id")]:::db
    svcfn[("Service-role functions<br/>create_booking, claim_jobs")]:::db
    views[("superadmin views, masked")]:::db
  end
  browser --> proxy --> nextjs
  browser --> turnstile --> nextjs
  callers --> sig
  agentsx -- "hashed token, scopes" --> nextjs
  sig --> nextjs
  nextjs -- "user JWT plus x-garage-id" --> rls
  nextjs -- "service role, server only" --> svcfn
  voice -- "per-call token" --> nextjs
  sa -- "autofix_superadmin, read-only sessions" --> views
classDef person fill:#081a2a,stroke:#081a2a,color:#ffffff
classDef web fill:#dce4ff,stroke:#2457ff,color:#081a2a
classDef svc fill:#e6f4f2,stroke:#007e76,color:#081a2a
classDef db fill:#fff6e0,stroke:#9a6700,color:#081a2a
classDef ext fill:#f1f3f5,stroke:#536273,color:#26333f,stroke-dasharray:4 3
classDef sec fill:#fdecea,stroke:#c9372c,color:#081a2a
```

### Authentication

| Who | How |
| --- | --- |
| Car owners | No account. A booking is managed through an HMAC-signed link (stored hashed) or reference plus registration posted in a form, which opens a 30-minute signed session cookie |
| Garage staff | Supabase Auth email sign-in; TOTP is mandatory for owners by default, with recovery codes and trusted devices |
| Vitalos platform admins (Next.js `/admin`) | Listed in `platform_admins` and signed in at AAL2 (TOTP) for every platform function |
| Vitalos staff (Django super admin) | Own accounts with django-axes lockout and TOTP for every role, plus a fresh code for each change, personal-data view, voicemail playback or support session |
| AI agents | `Bearer afat_…` agent tokens, stored as an HMAC with a server-side pepper, scoped to named tools; `workforce` tokens need Pro, `askbridge` tokens may hold only read-only tools |
| Voice desk | Signed, 5-minute claim from the voice webhook, exchanged for a per-call agent token |
| Webhooks | Twilio signature on the raw request, Stripe and Resend signing secrets, HMAC-signed inbound email from Cloudflare; cron and drain calls need a bearer secret checked in constant time |

### Authorisation

- Row-level security on every tenant table; the garage comes from the host or the member's selected garage, never from the request body (a `garageId`, `source` or `reminderSendId` in a public body is rejected with 422).
- Roles per garage: owner, manager, technician (plus front desk for staff bookings). Owner-only actions are enforced in policies and in security-definer functions.
- Booking, scheduling, reminder and job functions are executable by the service role only and filter every statement by garage.
- Support sessions ("View as support") are read-only transactions, last at most two hours and are written to both audit logs.
- The super admin's database role reads masked views and can call four functions; the app refuses to migrate or write the Pitline database alias.

### Secrets

Server secrets live in Vercel environment variables (marked Sensitive), GitHub Actions secrets and variables, and Google Secret Manager for the Cloud Run services. Nothing secret uses a `NEXT_PUBLIC_` name. The deploy workflows sign in to Google Cloud with Workload Identity Federation instead of stored keys, and only add versions to secrets that already exist. Variable names are listed in `.env.example`, `superadmin/.env.example` and `docs/autofix/INFRA.md`.

### Data protection and privacy

- UK data residency: database, functions and containers all run in London.
- Registrations are kept out of URLs, analytics and ordinary logs; `vehicle_facts` stores only a peppered hash of the registration.
- Reminders and campaigns need stored consent with the exact wording agreed to; STOP is honoured at once and also cancels scheduled reminders; offers consent is separate from reminder consent.
- Retention: message bodies, reminder bodies and voicemail links are cleared after 12 months; vehicle facts after 30 days; finished jobs after 14 days.
- The super admin sees masked phones, emails and registrations; opening a customer's details or playing a voicemail is audited.
- Garages accept the DPA in the admin; the acceptance and the text hash are stored.

### Abuse controls

Turnstile and per-IP and per-garage rate limits on public booking and contact routes; idempotency keys on bookings; strict JSON bodies with size limits on webhooks and APIs; per-host CSP with `frame-ancestors` limited to the garage's own sites; `Referrer-Policy: no-referrer` on token links.

### Main risks

| Risk | Where it stands |
| --- | --- |
| Supabase Free plan has no point-in-time recovery and pauses when idle | Pro plus PITR to be decided before the first paying garage |
| Vercel Hobby allows one daily cron and is non-commercial | Reminders go out once a day; Vercel Pro decision is pending |
| Self-hosted CI runners depend on a single machine | AWS fallback runner scripts exist (`infrastructure/runner/`) |
| Scale-to-zero voice desk can drop the first call of a cold start to voicemail | Keeping one instance warm is an open cost decision |
| Twilio trial account limits who can call or receive texts | Upgrade and UK mobile number need owner approval |
| Two super admins (Next.js `/admin` and Django) | Both write the same platform audit log; retiring `/admin` is an open decision |
