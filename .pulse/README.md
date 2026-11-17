# Pulse files

<!-- pulse-protocol: 1 -->

This folder is how work in this repository reaches **Vitalos Pulse** (pulse.vitalos.co.uk), Temitope's view of every
Vitalos project. Pulse reads it every hour from the default branch **and from every branch pushed in the last 14 days**,
so a session's work shows up before it merges, and work that never merges is not lost.

Every Claude session (any account; cloud, CLI, desktop or VM) and every other coding agent working in this repository
follows these rules. They sit alongside the repository's own CLAUDE.md or AGENTS.md; where those say more, follow both.

## What is here

| Path | Written by | When |
| --- | --- | --- |
| `.pulse/STATUS.md` | any session | When the project's stage, health, next steps, needs or blockers change |
| `.pulse/sessions/<date>-<slug>-<id>.md` | one session each | At the start, after each major step, when blocked, before stopping |
| `.pulse/bin/pulse` | (kit) | Helper that creates and updates your session file |
| `.pulse/bin/session-start` | (kit) | SessionStart hook that reminds each session of these rules |
| `.pulse/README.md` | (kit) | This file |

Files marked (kit) come from `vitalos-technologies/vitalos-op` `pulse/kit/` and are replaced when the kit is reinstalled;
change them there, not here.

## Your session file

One file per session, so parallel sessions never conflict.

1. **Start.** Before other work: `.pulse/bin/pulse start "<one line: what you are doing>"`. It creates your file with
   the session id, link, account, surface and branch filled in. Resuming an earlier session finds its file again.
2. **Keep it current** after each major step, and whenever something changes:
   - `pulse log "<what happened>"`: a dated line in the log
   - `pulse next "<step>"`, `pulse need "<what only Temitope can do>"`, `pulse blocker "<what is stopping you>"`
   - `pulse drop need "<start of the item>"` (or `next`, `blocker`) when an item is dealt with
   - `pulse pr <url>` when you open a pull request
   - `pulse status blocked "<why>"` or `pulse status active`
3. **Before you stop** (end of a work block, usage limit, handover): `pulse status paused "<where it stopped and how to
   resume>"`, or `pulse done "<outcome>"` when the task is finished.
4. **Commit and push.** Commit the file with your work and push your branch at least once per work block, even when the
   work is unfinished. Pulse cannot see a file that was never pushed.

Statuses: `active`, `blocked` (waiting on someone), `paused` (stopped, can resume), `done`, `abandoned`.
A session that is active, blocked or paused and unchanged for 3 days is shown on Pulse as **possibly forgotten**.
A branch pushed in the last 14 days with no session file and no open pull request is shown as **untracked work**.

Editing the files by hand is fine: keep the front matter keys and the `## ` section headings, and keep list items as
`- ` lines. `pulse check` validates every file here.

## STATUS.md

The project's current state in one page: summary, now, next, needs Temitope, blockers, links. Update it (and its
`updated` and `updated_by` lines) when any of these change, in the same commit as the change. When the stage or health
changes, say why in the summary. Pulse prefers it over its own generated summary when it is newer.

Stages: `Live`, `Launch-ready`, `Built – activation pending`, `In build`, `Planning`, `Paused`.
Health: `green`, `amber` (working but something needs attention), `red` (broken or stuck).

## Never in these files

- Secret values of any kind (keys, tokens, passwords, connection strings, webhook secrets), even partly. Name the
  variable instead (`STRIPE_SECRET_KEY`).
- Personal data of customers, users or members of the public.

## Public repositories

STATUS.md says `visibility: public` when anyone can read this repository. Then also keep out of `.pulse/`:
security findings and exposed or unrotated credentials, internal hostnames and IP addresses, email addresses, customer
or prospect names, spend and pricing not yet published, and unannounced plans. Write a neutral line such as
"Security follow-up recorded privately on Pulse" and put the detail in a Pulse note (`create_note` in the Pulse
connector) or in a private repository. `pulse check` flags emails and IP addresses in public repositories.

## Without the helper

If `bash` is not available, write the file by hand from this shape and name it
`.pulse/sessions/<YYYY-MM-DD>-<short-slug>-<last 6 characters of the session id>.md`:

```markdown
---
pulse: session/1
session: session_01AbC...        # cloud: session_<id>; CLI: local_<id>; otherwise any stable id
url: https://claude.ai/code/session_01AbC...   # empty when there is no link
account: engineering             # Claude account (engineering, design, research, temitope.agbola) or agent name
surface: cloud                   # cloud, cli, desktop, vm, other
agent: claude-code
branch: claude/some-branch
title: One line on what this session is doing
status: active
started: 2026-11-17T09:20Z
updated: 2026-11-17T10:05Z
prs:
---

## Goal
What this session set out to do.

## Next

## Needs Temitope

## Blockers

## Log
- 2026-11-17 09:20Z: Started: One line on what this session is doing
```
