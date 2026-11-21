// Phone numbers that are never Pitline's (DECISIONS D29, Temitope, 21 Nov 2026). Pure.
//
// SOB Autofix, the single-garage site Pitline was forked from, keeps its own
// phone and WhatsApp lines. Pitline never answers, routes, buys or shows them:
// - AUTOFIX_PLATFORM_VOICE_NUMBERS drops them (platform-line.ts);
// - Sync Vercel env and Launch ops refuse them (scripts/ci/reserved-numbers.mjs);
// - garage_phone_numbers refuses them in SQL (20261121000000_reserved_phone_numbers.sql);
// - src/__tests__/reserved-numbers.test.ts fails if either appears anywhere else in the repo.
// The list itself is reserved-numbers.json, shared with the scripts.

import { toE164UK } from "@/lib/messaging/phone";
import reserved from "./reserved-numbers.json";

/** The reserved numbers in E.164. */
export const RESERVED_NUMBERS: ReadonlySet<string> = new Set(reserved.numbers);

/** True when the number, in E.164 or any UK format (`07…`, `+44 7…`, `0044 7…`), is one Pitline must never hold. */
export function isReservedNumber(value: string | null | undefined): boolean {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (RESERVED_NUMBERS.has(trimmed)) return true;
  const e164 = toE164UK(trimmed, { allowLandline: true });
  return e164 !== null && RESERVED_NUMBERS.has(e164);
}
