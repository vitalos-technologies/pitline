import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { platformVoiceNumbers } from "@/lib/calls/platform-line";
import { isReservedNumber, RESERVED_NUMBERS } from "@/lib/calls/reserved-numbers";
import { isReservedNumber as scriptIsReserved, RESERVED_NUMBERS as SCRIPT_NUMBERS } from "../../scripts/ci/reserved-numbers.mjs";

// DECISIONS D29 (Temitope, 21 Nov 2026): SOB Autofix's lines are never Pitline's.

const root = process.cwd();
const read = (path: string) => readFileSync(join(root, path), "utf8");
const MIGRATION = "supabase/migrations/20261121000000_reserved_phone_numbers.sql";
const PLATFORM_LINE = "+441146974393";

// The only files where SOB's numbers may appear: SOB's own spec (context only), SOB's baseline migration
// (its invoice default was dropped by 20261026000100_tenancy.sql; applied migrations never change), and
// the guards themselves.
const ALLOWED = new Set([
  "docs/SOB_Autofix_Full_Codex_Architecture.md",
  "supabase/migrations/20261026000000_baseline.sql",
  "src/lib/calls/reserved-numbers.json",
  MIGRATION,
  "supabase/tests/database/042_reserved_phone_numbers.test.sql",
  "src/__tests__/reserved-numbers.test.ts",
  "src/__tests__/business-facts.test.ts",
]);

/** The numbers without +44 or the trunk 0, so any written form matches once separators are gone. */
const NATIONAL = [...RESERVED_NUMBERS].map((number) => number.replace(/^\+44/, ""));
function mentionsReserved(text: string) {
  const joined = text.replace(/(?<=\d)[ \t().\-]+(?=\d)/g, "");
  return NATIONAL.some((number) => joined.includes(number));
}

describe("SOB Autofix's numbers are never Pitline's (D29)", () => {
  it("lists both of SOB Autofix's numbers, in E.164", () => {
    expect([...RESERVED_NUMBERS].sort()).toEqual(["+447468273483", "+447469273483"]);
  });

  it("recognises them however they are written, and nothing else", () => {
    for (const value of ["+447469273483", "07469 273483", "07469273483", "+44 7469 273483", "+44 (0)7469 273483", "0044 7468 273483", "07468-273-483"]) {
      expect(isReservedNumber(value), value).toBe(true);
      expect(scriptIsReserved(value), value).toBe(true);
    }
    for (const value of [PLATFORM_LINE, "0114 697 4393", "+447700900123", "07469 273484", "", null, undefined]) {
      expect(isReservedNumber(value), String(value)).toBe(false);
      expect(scriptIsReserved(value), String(value)).toBe(false);
    }
  });

  it("drops them from Pitline's own line even when the variable lists them", () => {
    const numbers = platformVoiceNumbers({ AUTOFIX_PLATFORM_VOICE_NUMBERS: `${PLATFORM_LINE}, +447469273483 ,+447468273483` });
    expect([...numbers]).toEqual([PLATFORM_LINE]);
  });

  it("keeps Pitline's default line clear of them", () => {
    const workflow = read(".github/workflows/vercel-env.yml");
    const fallback = /AUTOFIX_PLATFORM_VOICE_NUMBERS \|\| '([^']+)'/.exec(workflow)?.[1];
    expect(fallback).toBe(PLATFORM_LINE);
    expect(fallback?.split(",").some((number) => isReservedNumber(number))).toBe(false);
  });

  it("uses one list for the app, the scripts and the database", () => {
    expect([...SCRIPT_NUMBERS].sort()).toEqual([...RESERVED_NUMBERS].sort());
    const migration = read(MIGRATION);
    expect(migration).toContain("garage_phone_numbers_not_reserved_check");
    for (const number of RESERVED_NUMBERS) expect(migration).toContain(`'${number}'`);
  });

  it("refuses them in Launch ops and Sync Vercel env", () => {
    const launch = read("scripts/ci/launch-ops.mjs");
    expect(launch).toContain("if (isReservedNumber(wanted)) return fail(");
    expect(launch).toContain("filter((number) => !isReservedNumber(number.phone_number))");
    const sync = read("scripts/ci/sync-vercel-env.mjs");
    expect(sync).toMatch(/AUTOFIX_PLATFORM_VOICE_NUMBERS[\s\S]*isReservedNumber/);
    expect(sync).toContain("if (failed > 0 || refused > 0) process.exit(1);");
  });

  it("appears nowhere else in the repository, in any format", () => {
    const listed = execFileSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], { cwd: root, encoding: "utf8" });
    const offending = listed.split("\0").filter(Boolean).filter((file) => {
      if (ALLOWED.has(file)) return false;
      let content: Buffer;
      try {
        content = readFileSync(join(root, file));
      } catch {
        return false; // listed but deleted in the working tree
      }
      if (content.includes(0)) return false; // binary
      return mentionsReserved(content.toString("utf8"));
    });
    expect(offending).toEqual([]);
  });
});
