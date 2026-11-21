// Pitline's own phone line (DECISIONS A420). Pure.
//
// A number listed in AUTOFIX_PLATFORM_VOICE_NUMBERS (E.164, comma-separated)
// belongs to Pitline, not to a garage. The voice webhook answers it in
// Pitline's name and takes a voicemail: no ring-through, no text-back (the
// line has no SMS sender), no AI front desk. Calls go to `platform_calls`,
// which no garage can read; Vitalos staff see them on the super admin's
// Calls page as "Pitline (platform line)". SOB Autofix's numbers are never
// Pitline's line (D29): they are dropped even when the variable lists them.

import { isReservedNumber } from "@/lib/calls/reserved-numbers";
import { isE164 } from "@/lib/messaging/phone";

export const PLATFORM_VOICE_NUMBERS_ENV = "AUTOFIX_PLATFORM_VOICE_NUMBERS";

/** The name the greeting uses on the platform line. */
export const PLATFORM_LINE_NAME = "Pitline";

/** Platform numbers from the environment. Anything that is not E.164, or is reserved (D29), is ignored. */
export function platformVoiceNumbers(env: Readonly<Record<string, string | undefined>> = process.env): ReadonlySet<string> {
  const raw = env[PLATFORM_VOICE_NUMBERS_ENV] ?? "";
  return new Set(raw.split(",").map((value) => value.trim()).filter((value) => isE164(value) && !isReservedNumber(value)));
}
