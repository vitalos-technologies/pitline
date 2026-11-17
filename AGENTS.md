<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# Pitline agents

Any coding agent working here: read `CLAUDE.md` first. It lists the spec, build plan, design system and the rules that must never break (tenancy by host, no double bookings, registration privacy, secrets, messaging consent).

<!-- pulse:start (managed by vitalos-op pulse/kit/install.sh; edit there) -->

## Pulse: every session reports here

This repository reports to Vitalos Pulse through `.pulse/`. Every session and agent follows `.pulse/README.md`:

- **Start** with `.pulse/bin/pulse start "<one line: what you are doing>"`. It creates your session file in `.pulse/sessions/`.
- **Keep it current** after each major step, when blocked and before you stop (`pulse log`, `next`, `need`, `blocker`, `status`, `done`). Commit it with your work and push your branch at least once per work block, even unfinished.
- **Update `.pulse/STATUS.md`** when the project's stage, health, next steps, needs or blockers change.
- **Never put secret values in `.pulse/`**; name the variable instead.
- **This repository is public.** Nothing in `.pulse/` may hold security findings, internal hosts or IP addresses, email addresses, customer names, spend or unannounced plans; put those in a Pulse note (`create_note`) instead.

<!-- pulse:end -->
