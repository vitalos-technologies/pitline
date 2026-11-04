// @vitest-environment jsdom

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { cleanup, render, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import MarketingLayout from "@/app/(marketing)/layout";
import { ASKBRIDGE_DEFAULT_SCRIPT_URL, pitlineAskbridgeWidget } from "@/lib/askbridge/config";

// D28: Pitline's own Askbridge chat on its marketing pages (/, /contact) only.

const KEY = "pk_0123456789abcdef0123456789abcdef";
const root = process.cwd();

afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
  document.getElementById("askbridge-widget")?.remove();
});

function files(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    return statSync(path).isDirectory() ? files(path) : /\.(ts|tsx)$/.test(entry) ? [path] : [];
  });
}

describe("Pitline's Askbridge site key", () => {
  it("loads only with a well-formed key and a valid loader URL", () => {
    expect(pitlineAskbridgeWidget({})).toBeNull();
    expect(pitlineAskbridgeWidget({ NEXT_PUBLIC_PITLINE_ASKBRIDGE_SITE_KEY: "pk_short" })).toBeNull();
    expect(pitlineAskbridgeWidget({ NEXT_PUBLIC_PITLINE_ASKBRIDGE_SITE_KEY: ` ${KEY} ` })).toEqual({
      scriptUrl: ASKBRIDGE_DEFAULT_SCRIPT_URL,
      origin: "https://askbridge.vitalos.co.uk",
      siteKey: KEY,
    });
    // A bad loader URL hides the chat rather than loading something else.
    expect(pitlineAskbridgeWidget({ NEXT_PUBLIC_PITLINE_ASKBRIDGE_SITE_KEY: KEY, NEXT_PUBLIC_ASKBRIDGE_WIDGET_URL: "http://evil.example/a.js" })).toBeNull();
  });
});

describe("marketing layout", () => {
  it("renders the chat with Pitline's key when it is set", async () => {
    vi.stubEnv("NEXT_PUBLIC_PITLINE_ASKBRIDGE_SITE_KEY", KEY);
    render(<MarketingLayout><p>Marketing</p></MarketingLayout>);
    const script = await waitFor(() => {
      const element = document.getElementById("askbridge-widget");
      expect(element).not.toBeNull();
      return element as HTMLScriptElement;
    });
    expect(script.getAttribute("src")).toBe(ASKBRIDGE_DEFAULT_SCRIPT_URL);
    expect(script.getAttribute("data-site")).toBe(KEY);
  });

  it("renders nothing extra without a key", () => {
    vi.stubEnv("NEXT_PUBLIC_PITLINE_ASKBRIDGE_SITE_KEY", "");
    const { container } = render(<MarketingLayout><p>Marketing</p></MarketingLayout>);
    expect(container.innerHTML).toBe("<p>Marketing</p>");
    expect(document.getElementById("askbridge-widget")).toBeNull();
  });
});

describe("where the chat can load", () => {
  const uses = (pattern: RegExp) =>
    files(join(root, "src/app"))
      .filter((path) => pattern.test(readFileSync(path, "utf8")))
      .map((path) => relative(root, path).replaceAll("\\", "/"))
      .sort();

  it("Pitline's chat is in the marketing layout and nowhere else", () => {
    expect(uses(/pitlineAskbridgeWidget/)).toEqual(["src/app/(marketing)/layout.tsx"]);
  });

  it("the widget renders only in the marketing layout and the garage booking site layout", () => {
    expect(uses(/<AskbridgeWidget\b/)).toEqual(["src/app/%5Fsite/[garageId]/layout.tsx", "src/app/(marketing)/layout.tsx"].sort());
  });

  it("the marketing group holds only the public marketing pages, not the admin, sign-up or super admin", () => {
    const routes = files(join(root, "src/app/(marketing)")).map((path) => relative(join(root, "src/app/(marketing)"), path).replaceAll("\\", "/")).sort();
    expect(routes).toEqual(["contact/contact-form.tsx", "contact/page.tsx", "layout.tsx", "page.tsx"]);
    // The root layout (shared with /app, /signup, /admin) never loads it.
    expect(readFileSync(join(root, "src/app/layout.tsx"), "utf8")).not.toMatch(/askbridge/i);
  });
});
