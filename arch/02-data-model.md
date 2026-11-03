# Data model

Snapshot `82578f9`, 3 Nov 2026. Back to [README](README.md).

One Supabase Postgres 17 database in London holds every garage's data. The schema comes from 36 migrations in `supabase/migrations/` (SOB Autofix baseline, then tenancy, scheduling, reminders and the Phase 5 features). There are 93 tables in `public`, 20 masked views in the `superadmin` schema, and three Storage buckets. The diagrams show only primary keys, foreign keys, the tenant key and the most telling columns.

## Tenancy rules

- **Tenant key.** 75 of the 93 tables carry `garage_id uuid not null default public.current_garage_id()` with a foreign key to `garages` (`on delete cascade`) and an index that leads with `garage_id`. Child tables carry `garage_id` too and reference their parent through a composite key `(garage_id, parent_id)`, so a row can never point into another garage.
- **Row-level security.** RLS is on for every tenant table. Policies are `using (garage_id = (select public.current_garage_id()))`, with `with check` on writes and an owner check for owner-only actions. `anon` has no grants on tenant tables.
- **Where the garage comes from.** `current_garage_id()` returns the `x-garage-id` request header only for the service role or a member of that garage. The app sets the header from the request host (public pages) or from the signed-in member's selected garage (admin), never from a body or query string.
- **Platform tables.** The other 18 tables have no garage key: platform admins and their audit log, MFA and trusted-device tables, rate-limit buckets, webhook event ledgers (Twilio, Stripe, Resend, inbound email), platform enquiries and calls to Pitline's own line, and `vehicle_facts`. They are service-role only or narrowly granted.
- **Proof.** `tests/integration/tenancy.test.ts` enumerates every table with `garage_id` from `information_schema` and checks select, insert, update, delete and move for anon and for staff of two garages; a new table without a fixture fails the suite.

## Tenancy, access and audit

```mermaid
erDiagram
  GARAGES ||--o{ GARAGE_DOMAINS : "served on"
  GARAGES ||--o{ GARAGE_MEMBERS : "staffed by"
  GARAGES ||--o{ GARAGE_INVITES : "invites"
  GARAGES ||--o{ GARAGE_AGREEMENTS : "accepts DPA"
  GARAGES ||--o{ GARAGE_SUBSCRIPTIONS : "billed by"
  GARAGES ||--o{ AGENT_TOKENS : "issues"
  AGENT_TOKENS ||--o{ AGENT_CALL_LOG : "logged in"
  GARAGES ||--o{ ADMIN_AUDIT_LOG : "audited in"
  GARAGES ||--o{ PLATFORM_IMPERSONATIONS : "support sessions"
  PLATFORM_ADMINS ||--o{ PLATFORM_IMPERSONATIONS : "opens"
  PLATFORM_ADMINS ||--o{ PLATFORM_AUDIT_LOG : "acts in"
  GARAGES {
    uuid id PK
    text slug UK
    text plan
    text status
    boolean mot_enabled
    text timezone
  }
  GARAGE_DOMAINS {
    uuid id PK
    uuid garage_id FK
    text hostname UK
    text kind
    text status
  }
  GARAGE_MEMBERS {
    uuid id PK
    uuid garage_id FK
    uuid user_id FK
    text role
  }
  GARAGE_INVITES {
    uuid id PK
    uuid garage_id FK
    text role
    text token_hash
  }
  GARAGE_AGREEMENTS {
    uuid id PK
    uuid garage_id FK
    text text_hash
  }
  GARAGE_SUBSCRIPTIONS {
    uuid id PK
    uuid garage_id FK
    text plan
    text status
  }
  AGENT_TOKENS {
    uuid id PK
    uuid garage_id FK
    text token_hash UK
    text audience
    text_array scopes
  }
  AGENT_CALL_LOG {
    uuid id PK
    uuid garage_id FK
    uuid token_id FK
    text tool
    text outcome
  }
  ADMIN_AUDIT_LOG {
    uuid id PK
    uuid garage_id FK
    text action
  }
  PLATFORM_ADMINS {
    uuid user_id PK
  }
  PLATFORM_IMPERSONATIONS {
    uuid id PK
    uuid garage_id FK
    uuid admin_user_id FK
    timestamptz expires_at
  }
  PLATFORM_AUDIT_LOG {
    uuid id PK
    uuid actor_id FK
    uuid target_garage_id FK
    text action
    text reason
  }
```

`garage_role()` returns the caller's role in a garage, or `owner` for a Vitalos support session (`platform_impersonations`) in read-only transactions only. Platform actions are written to the append-only `platform_audit_log` and to the garage's own `admin_audit_log`.

## Booking engine

```mermaid
erDiagram
  GARAGES ||--o{ RESOURCES : "has bays and vans"
  GARAGES ||--o{ OPENING_HOURS : "opens"
  GARAGES ||--o{ CLOSURES : "closes"
  GARAGES ||--o{ SERVICES : "offers"
  GARAGES ||--o{ CUSTOMERS : "serves"
  CUSTOMERS ||--o{ VEHICLES : "owns"
  CUSTOMERS ||--o{ BOOKINGS : "makes"
  VEHICLES ||--o{ BOOKINGS : "booked for"
  SERVICES ||--o{ BOOKINGS : "booked as"
  RESOURCES ||--o{ BOOKINGS : "blocked by"
  BOOKINGS ||--o{ BOOKING_EVENTS : "history"
  BOOKINGS ||--o{ BOOKING_ASSIGNMENTS : "assigned"
  BOOKINGS ||--o{ BOOKING_NOTIFICATION_EVENTS : "notified"
  GARAGES {
    uuid id PK
    text slug UK
    int slot_step_min
    boolean approve_online
  }
  RESOURCES {
    uuid id PK
    uuid garage_id FK
    text kind
    boolean active
  }
  OPENING_HOURS {
    uuid id PK
    uuid garage_id FK
    smallint weekday
    time opens
    time closes
  }
  CLOSURES {
    uuid id PK
    uuid garage_id FK
    date starts_on
    date ends_on
  }
  SERVICES {
    uuid id PK
    uuid garage_id FK
    int duration_min
    text resource_kind
    boolean is_mot
  }
  CUSTOMERS {
    uuid id PK
    uuid garage_id FK
    text phone UK
    boolean reminder_consent
    boolean offers_consent
  }
  VEHICLES {
    uuid id PK
    uuid garage_id FK
    uuid customer_id FK
    text registration UK
    date mot_expiry
  }
  BOOKINGS {
    uuid id PK
    uuid garage_id FK
    uuid resource_id FK
    text reference UK
    tstzrange during
    text status
    text source
    text idempotency_key UK
  }
  BOOKING_EVENTS {
    uuid id PK
    uuid garage_id FK
    uuid booking_id FK
    text type
    text actor
  }
  BOOKING_ASSIGNMENTS {
    uuid id PK
    uuid garage_id FK
    uuid booking_id FK
    uuid technician_id
  }
  BOOKING_NOTIFICATION_EVENTS {
    uuid id PK
    uuid booking_id FK
    text kind
  }
```

- `bookings.during` is the time a resource is blocked (travel, duration, buffer). The constraint `no_overlap exclude using gist (resource_id with =, during with &&) where (status not in ('cancelled','no_show'))` is the last line of defence against double bookings.
- `create_booking(p_garage_id, p_booking)` (service role only) upserts the customer by phone and the vehicle by registration, picks the least-busy free resource under a per-garage advisory lock, inserts the booking and its first `booking_events` row, and replays the same booking for a repeated idempotency key.
- `available_slots()` builds candidate starts in the garage's time zone from opening hours, closures, notice and horizon, and returns how many resources are free at each.
- A trigger writes a `status_changed` event for every status change, naming the member or the system.

## Reminders, messaging and jobs

```mermaid
erDiagram
  GARAGES ||--o{ REMINDER_RULES : "configures"
  REMINDER_RULES ||--o{ REMINDER_SENDS : "schedules"
  VEHICLES ||--o{ REMINDER_SENDS : "due for"
  CUSTOMERS ||--o{ REMINDER_SENDS : "sent to"
  REMINDER_SENDS |o--o{ BOOKINGS : "wins back"
  CUSTOMERS ||--o{ MESSAGES : "texts and email"
  CALLS |o--o{ MESSAGES : "text-back"
  GARAGES ||--o{ GARAGE_PHONE_NUMBERS : "routes"
  GARAGES ||--o{ CALLS : "receives"
  GARAGES ||--o{ CAMPAIGNS : "runs"
  CAMPAIGNS ||--o{ CAMPAIGN_SENDS : "sends"
  CUSTOMERS ||--o{ CAMPAIGN_SENDS : "receives"
  REMINDER_RULES {
    uuid id PK
    uuid garage_id FK
    text kind UK
    int_array offset_days
    text channel
  }
  REMINDER_SENDS {
    uuid id PK
    uuid garage_id FK
    uuid vehicle_id FK
    date due_date
    timestamptz send_at
    text status
    text link_token_hash
  }
  BOOKINGS {
    uuid id PK
    uuid reminder_send_id FK
    text source
  }
  MESSAGES {
    uuid id PK
    uuid garage_id FK
    text channel
    text direction
    text provider_msg_id UK
    text status
  }
  CALLS {
    uuid id PK
    uuid garage_id FK
    text provider_call_sid UK
    boolean missed
  }
  GARAGE_PHONE_NUMBERS {
    uuid id PK
    uuid garage_id FK
    text number UK
    text purpose
  }
  CAMPAIGNS {
    uuid id PK
    uuid garage_id FK
    text segment
    text status
  }
  CAMPAIGN_SENDS {
    uuid id PK
    uuid campaign_id FK
    text status
    text skip_reason
  }
  JOBS {
    uuid id PK
    text kind
    text dedupe_key UK
    timestamptz run_at
    text status
    timestamptz locked_until
  }
  TWILIO_WEBHOOK_EVENTS {
    text event_key PK
    text kind
    text processing_status
  }
  VEHICLE_FACTS {
    text reg_hash PK
    jsonb facts
    timestamptz fetched_at
  }
```

- `schedule_reminders()` creates idempotent `reminder_sends` rows only for customers with stored consent who have not opted out; MOT rows only while `garages.mot_enabled`.
- `claim_reminder_sends()` re-checks consent, opt-out, rule and due date at send time and records a `skip_reason` when a send should not go.
- `jobs` is the platform queue: `enqueue_job()` with a dedupe key, `claim_jobs()` with `for update skip locked` and a 5-minute lock, `fail_job()` with exponential backoff.
- `vehicle_facts` is keyed by an HMAC of the registration with a server-side pepper and holds no customer data; it expires after 30 days.
- `apply_message_retention()` clears message bodies, reminder bodies and voicemail links older than 12 months.

## Invoices, payments, plans and accounting

```mermaid
erDiagram
  BOOKINGS ||--o{ INVOICES : "invoiced as"
  INVOICES ||--o{ INVOICE_ITEMS : "lines"
  INVOICES ||--o{ INVOICE_PAYMENTS : "paid by"
  BOOKINGS ||--o{ PAYMENTS : "deposit or no-show fee"
  INVOICES ||--o{ PAYMENTS : "pay-by-link"
  GARAGES ||--o| PAYMENT_ACCOUNTS : "Stripe Connect"
  GARAGES ||--o{ SERVICE_PLANS : "sells"
  SERVICE_PLANS ||--o{ CUSTOMER_PLAN_SUBSCRIPTIONS : "subscribed"
  CUSTOMERS ||--o{ CUSTOMER_PLAN_SUBSCRIPTIONS : "pays by Direct Debit"
  GARAGES ||--o{ BUSINESS_ACCOUNTS : "fleet and trade"
  BUSINESS_ACCOUNTS ||--o{ BUSINESS_ACCOUNT_VEHICLES : "covers"
  BUSINESS_ACCOUNTS ||--o{ ACCOUNT_STATEMENTS : "statements"
  GARAGES ||--o{ ACCOUNTING_CONNECTIONS : "connects"
  ACCOUNTING_CONNECTIONS ||--o{ ACCOUNTING_SYNC_ITEMS : "syncs"
  GARAGES ||--o{ USAGE_EVENTS : "meters"
  INVOICES {
    uuid id PK
    uuid garage_id FK
    uuid booking_id FK
    text invoice_number
    int revision
  }
  INVOICE_ITEMS {
    uuid id PK
    uuid invoice_id FK
    int unit_price_pence
  }
  INVOICE_PAYMENTS {
    uuid id PK
    uuid invoice_id FK
    int amount_pence
  }
  PAYMENTS {
    uuid id PK
    uuid garage_id FK
    text kind
    text status
    int amount_pence
    text token_hash
  }
  PAYMENT_ACCOUNTS {
    uuid id PK
    uuid garage_id FK
    text account_ref
    boolean charges_enabled
  }
  SERVICE_PLANS {
    uuid id PK
    uuid garage_id FK
    int price_pence
    text status
  }
  CUSTOMER_PLAN_SUBSCRIPTIONS {
    uuid id PK
    uuid plan_id FK
    uuid customer_id FK
    text status
    text mandate_ref
  }
  BUSINESS_ACCOUNTS {
    uuid id PK
    uuid garage_id FK
    text kind
    int payment_terms_days
  }
  BUSINESS_ACCOUNT_VEHICLES {
    uuid id PK
    uuid account_id FK
    uuid vehicle_id FK
  }
  ACCOUNT_STATEMENTS {
    uuid id PK
    uuid account_id FK
  }
  ACCOUNTING_CONNECTIONS {
    uuid id PK
    uuid garage_id FK
    text provider
    text status
  }
  ACCOUNTING_SYNC_ITEMS {
    uuid id PK
    uuid connection_id FK
    text entity
    text remote_id
    text status
  }
  USAGE_EVENTS {
    uuid id PK
    uuid garage_id FK
    text metric
    int quantity
    text source_key UK
  }
```

`payments` and `customer_plan_subscriptions` only ever reference Stripe objects by id (`checkout_ref`, `mandate_ref`, `subscription_ref`); card and bank details never reach Pitline. Accounting tokens are encrypted in `accounting_connection_secrets` with a server-side key. `usage_events` meter SMS and AI minutes per month with a unique `source_key` so retries count once.

## Pro operations

```mermaid
erDiagram
  BOOKINGS ||--o{ HEALTH_CHECKS : "inspected in"
  HEALTH_CHECKS ||--o{ HEALTH_CHECK_ITEMS : "items"
  HEALTH_CHECK_ITEMS ||--o{ HEALTH_CHECK_MEDIA : "photos"
  GARAGES ||--o{ COURTESY_CARS : "keeps"
  COURTESY_CARS ||--o{ COURTESY_CAR_LOANS : "lent"
  BOOKINGS ||--o{ COURTESY_CAR_LOANS : "with car"
  BOOKINGS ||--o{ COURTESY_CAR_REQUESTS : "asks for car"
  BOOKINGS ||--o{ COLLECTION_DELIVERY_LEGS : "collect and deliver"
  RESOURCES ||--o{ COLLECTION_DELIVERY_LEGS : "van or driver"
  GARAGE_GROUPS ||--o{ GARAGE_GROUP_SITES : "sites"
  GARAGES ||--o{ GARAGE_GROUP_SITES : "member site"
  HEALTH_CHECKS {
    uuid id PK
    uuid garage_id FK
    uuid booking_id FK
    text status
    text token_hash
  }
  HEALTH_CHECK_ITEMS {
    uuid id PK
    uuid check_id FK
    text rating
    text decision
    int price_pence
  }
  HEALTH_CHECK_MEDIA {
    uuid id PK
    uuid item_id FK
    text object_path
  }
  COURTESY_CARS {
    uuid id PK
    uuid garage_id FK
    text name
    boolean active
  }
  COURTESY_CAR_LOANS {
    uuid id PK
    uuid car_id FK
    uuid booking_id FK
    tstzrange during
    text status
  }
  COURTESY_CAR_REQUESTS {
    uuid id PK
    uuid booking_id FK
    text status
  }
  COLLECTION_DELIVERY_LEGS {
    uuid id PK
    uuid booking_id FK
    uuid resource_id FK
    text kind
  }
  GARAGE_GROUPS {
    uuid id PK
    uuid garage_id FK
    text name
  }
  GARAGE_GROUP_SITES {
    uuid id PK
    uuid group_id FK
    uuid home_garage_id FK
  }
```

Health-check photos and videos live in the private `health-check-media` bucket and are served only through short-lived signed URLs; the customer opens the check through a link whose token is stored hashed. `courtesy_car_loans` and `collection_delivery_legs` have their own exclusion constraints on `during`, so a car, van or driver cannot be double-booked either.

## Super admin views

The `superadmin` schema exposes 20 views to the least-privilege role `autofix_superadmin` (migrations `20261028004000_superadmin_role.sql`, `20261029002200_superadmin_calls.sql`, `20261029003000_platform_enquiries.sql`). Phones, emails and registrations are masked in the database; message bodies, payloads and token hashes are left out. The role can call only four write functions (`platform_update_garage`, `platform_retry_job`, `platform_request_domains_check`, `platform_update_enquiry`), each of which re-checks the linked platform admin and writes the audit logs.

## Table inventory

| Domain | Tables | What they hold |
| --- | --- | --- |
| Tenancy and staff (8) | `garages`, `garage_domains`, `garage_members`, `garage_invites`, `garage_agreements`, `admin_profiles`, `site_settings`, `media_assets` | Garages, their hosts, members, invites, DPA acceptance and site settings |
| Security, admin and audit (9) | `admin_audit_log`, `admin_mfa_policy`, `admin_mfa_recovery_codes`, `admin_mfa_recovery_sessions`, `admin_trusted_devices`, `rate_limit_buckets`, `platform_admins`, `platform_impersonations`, `platform_audit_log` | MFA, trusted devices, rate limits, platform admins, support sessions and audit logs |
| Booking engine (14) | `resources`, `opening_hours`, `closures`, `services`, `service_prices`, `customers`, `vehicles`, `bookings`, `booking_events`, `booking_assignments`, `booking_audit_log`, `booking_notification_events`, `customer_imports`, `vehicle_facts` | Resources, hours, services, customers, vehicles, bookings and their history; imports and the vehicle facts cache |
| Reminders, messaging and calls (10) | `reminder_rules`, `reminder_sends`, `messages`, `calls`, `garage_phone_numbers`, `platform_calls`, `twilio_webhook_events`, `notification_attempts`, `campaigns`, `campaign_sends` | Reminder rules and sends, messages, calls, numbers, campaigns and the Twilio event ledger |
| Enquiries and email (8) | `enquiries`, `enquiry_attachments`, `enquiry_conversations`, `enquiry_messages`, `inbound_email_events`, `unmatched_inbound_emails`, `resend_webhook_events`, `platform_enquiries` | Customer enquiries and their email threads, inbound mail ledgers and contact-page enquiries |
| Invoices and payments (10) | `invoices`, `invoice_items`, `invoice_payments`, `invoice_number_sequences`, `invoice_email_sends`, `invoice_email_attempts`, `payments`, `payment_accounts`, `payment_settings`, `payment_webhook_events` | Invoices and their email, deposits, pay-by-link and no-show fees through Stripe Connect |
| Plans and billing (5) | `garage_subscriptions`, `plan_requests`, `usage_events`, `billing_usage_reports`, `billing_webhook_events` | Garage subscriptions, plan requests and metered usage |
| Pro operations (9) | `health_checks`, `health_check_items`, `health_check_media`, `courtesy_cars`, `courtesy_car_loans`, `courtesy_car_requests`, `collection_delivery_legs`, `garage_groups`, `garage_group_sites` | Digital health checks, courtesy cars, collection and delivery, multi-site groups |
| Fleet accounts and service plans (11) | `business_accounts`, `business_account_customers`, `business_account_vehicles`, `business_account_bookings`, `business_account_invoices`, `account_statements`, `service_plans`, `service_plan_inclusions`, `service_plan_uses`, `service_plan_invoice_applications`, `customer_plan_subscriptions` | Trade and fleet accounts with statements; customer service plans by Direct Debit |
| Accounting sync (3) | `accounting_connections`, `accounting_connection_secrets`, `accounting_sync_items` | Connections to Xero, QuickBooks and Sage, encrypted tokens and the sync ledger |
| AI front desk and agents (3) | `agent_tokens`, `agent_call_log`, `ai_front_desk_settings` | Agent tokens, the agent call log and per-garage AI desk settings |
| Platform jobs (1) | `jobs` | The background job queue |
| Carried over from SOB (2) | `offers`, `reviews` | Marketing content tables kept from the fork |

Dropped during the fork from SOB: `booking_service_types`, `service_catalogue_systems`, `provider_webhook_events` (Cal.com leftovers).
