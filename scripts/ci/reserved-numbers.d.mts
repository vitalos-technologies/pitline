/** The reserved numbers in E.164 (DECISIONS D29). */
export const RESERVED_NUMBERS: readonly string[];
/** True when one number, in any format (+44…, 0044…, 07…, spaces), is reserved. Split lists first. */
export function isReservedNumber(value: unknown): boolean;
