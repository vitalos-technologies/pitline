// Phone numbers Pitline never holds (DECISIONS D29): SOB Autofix's lines. The same list as the app
// (src/lib/calls/reserved-numbers.json). Launch ops and Sync Vercel env use it to refuse them.

import { readFileSync } from "node:fs";

const list = JSON.parse(readFileSync(new URL("../../src/lib/calls/reserved-numbers.json", import.meta.url), "utf8"));

/** The reserved numbers in E.164. */
export const RESERVED_NUMBERS = Object.freeze([...list.numbers]);

// Each UK national number without +44 or the trunk 0 (ten digits starting 7).
const NATIONAL = RESERVED_NUMBERS.map((number) => number.replace(/^\+44/, ""));

/** True when one number, in any format (+44…, 0044…, 07…, spaces), is reserved. Split lists first. */
export function isReservedNumber(value) {
  const digits = String(value ?? "").replace(/\D/g, "");
  return digits.length >= 10 && NATIONAL.some((number) => digits.endsWith(number));
}
