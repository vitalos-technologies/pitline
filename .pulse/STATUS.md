---
pulse: status/1
project: pitline
name: Pitline
repo: vitalos-technologies/pitline
visibility: public
stage: Built – activation pending
health: amber
progress: 85
updated: 2026-11-17
updated_by: session_01Cr6fhcy2Ch1rivzTMCj8ek (engineering); seeded from the Pulse record of 14 Nov 2026, next session to verify
---

# Pitline: status

## Summary
Pitline (formerly Autofix, forked from SOB Autofix) is Vitalos's multi-tenant garage booking platform: phone-first booking pages on a garage's own domain, a garage admin with diary, MOT and service reminders and missed-call text-back, and an AI voice front desk on the higher plan. All build phases are done and green (Gates 1-3 and 5 passed). Gate 4, the first real garage live on its own domain, waits on owner steps.

## Now

## Next
- Connect the first founding garage's domain and pass Gate 4
- Merge or close PR #28
- Point the enquiry email worker at the reply domain once routing exists
- Decide when to retire the Next.js /admin in favour of the Django super admin

## Needs Temitope
- Tracked privately on Pulse (this repository is public).

## Blockers
- DVLA VES registrations closed; lookups use DVSA plus Vehicle Data Global meanwhile
- Vercel Hobby allows daily crons only, so reminders go out once a day
- Tracked privately on Pulse (this repository is public).

## Links
- Website: https://pitline.co.uk
