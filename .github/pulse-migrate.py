#!/usr/bin/env python3
"""Pulse migrate: check or apply this repo's Supabase migrations with the access
the repo already has. Either:
  - SUPABASE_ACCESS_TOKEN + the project ref (SUPABASE_PROJECT_REF, or SUPABASE_URL=https://<ref>.supabase.co):
    the Supabase Management API, no database password; or
  - DATABASE_URL: a Postgres connection string whose login can run migrations (psql must be installed).
The token is used when both are set, unless PULSE_DB=url.

Env: MODE=plan|apply, CONFIRM, EXPECTED, the access above, MIGRATIONS_DIR (default supabase/migrations).
Prints one line Pulse reads:  PULSE_RESULT {"mode","tool","pending","destructive","applied","error"}
Apply runs only with CONFIRM=APPLY, when the pending list equals EXPECTED, and never with destructive SQL.
Each file is applied in one transaction together with its schema_migrations row (as `supabase db push` records it).
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

MODE = os.environ.get("MODE", "plan")
API = os.environ.get("PULSE_SUPABASE_API", "https://api.supabase.com")
DESTRUCTIVE = re.compile(
    r"\b(drop\s+(table|column|schema|type|function|view|materialized\s+view|index|policy|trigger)|"
    r"rename\s+(column|to)|alter\s+column\s+[^;]*?\btype\b|truncate\b|delete\s+from)",
    re.IGNORECASE,
)
state = {"pending": [], "destructive": [], "applied": []}
TOOL = "supabase-api"


def result(error=None):
    print(
        "PULSE_RESULT "
        + json.dumps({"mode": MODE, "tool": TOOL, **state, "error": error})
    )
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(f"### Pulse migrate: {MODE}\n")
            f.write(
                "".join(f"- pending: `{p}`\n" for p in state["pending"])
                or "Nothing pending.\n"
            )
            f.write("".join(f"- destructive: `{d}`\n" for d in state["destructive"]))
            f.write("".join(f"- applied: `{a}`\n" for a in state["applied"]))
            if error:
                f.write(f"\n**Error:** {error}\n")


def fail(msg):
    result(msg)
    print(f"::error::{msg}")
    sys.exit(1)


def project_ref():
    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    if not ref:
        m = re.match(
            r"^https://([a-z0-9]+)\.supabase\.co/?$",
            os.environ.get("SUPABASE_URL", "").strip(),
        )
        ref = m.group(1) if m else ""
    return ref


def query_url(sql):

    # psql in one transaction for writes; JSON rows out for reads.
    wrapped = (
        f"select coalesce(json_agg(t), '[]') from ({sql.rstrip().rstrip(';')}) t"
        if sql.lstrip().lower().startswith("select")
        else sql
    )
    r = subprocess.run(
        [
            "psql",
            os.environ["DATABASE_URL"],
            "-X",
            "-q",
            "-At",
            "-v",
            "ON_ERROR_STOP=1",
            "-c",
            wrapped,
        ],
        capture_output=True,
        text=True,
        timeout=600,
        check=False,
    )
    if r.returncode:
        raise RuntimeError(f"psql: {(r.stderr or r.stdout).strip()[-300:]}")
    return json.loads(r.stdout.strip() or "[]") if wrapped is not sql else []


def query(ref, sql):
    if ref == "url":
        return query_url(sql)
    req = urllib.request.Request(
        f"{API}/v1/projects/{ref}/database/query",
        data=json.dumps({"query": sql}).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['SUPABASE_ACCESS_TOKEN']}",
            "Content-Type": "application/json",
            "User-Agent": "vitalos-pulse-migrate",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(
            f"Supabase API {e.code}: {e.read().decode(errors='replace')[:300]}"
        ) from None


def quote(text):
    return "'" + text.replace("'", "''") + "'"


def strip_comments(sql):
    return re.sub(r"--[^\n]*|/\*.*?\*/", "", sql, flags=re.DOTALL)


def main():
    use_url = os.environ.get("DATABASE_URL") and (
        os.environ.get("PULSE_DB") == "url"
        or not os.environ.get("SUPABASE_ACCESS_TOKEN")
    )
    if use_url:
        global TOOL
        TOOL = "postgres-url"
        run("url")
        return
    if not os.environ.get("SUPABASE_ACCESS_TOKEN"):
        fail(
            "No database access: set SUPABASE_ACCESS_TOKEN (with a project ref) or DATABASE_URL from this repo's secrets."
        )
    ref = project_ref()
    if not ref:
        fail(
            "No project ref: set SUPABASE_PROJECT_REF in the workflow (it is not secret) or a SUPABASE_URL secret."
        )
    run(ref)


def run(ref):
    folder = Path(os.environ.get("MIGRATIONS_DIR", "supabase/migrations"))
    if not folder.is_dir():
        fail(f"Migrations folder {folder} not found.")
    files = []
    for f in sorted(folder.glob("*.sql")):
        m = re.match(r"^(\d+)_(.+)\.sql$", f.name)
        if m:
            files.append((m.group(1), m.group(2), f))
    try:
        applied = {
            str(r["version"])
            for r in query(
                ref, "select version from supabase_migrations.schema_migrations"
            )
        }
    except (RuntimeError, OSError, ValueError, KeyError) as e:
        fail(f"Could not read the migration history: {e}")
    todo = [(v, n, f) for v, n, f in files if v not in applied]
    state["pending"] = [f.name for _, _, f in todo]
    for _, _, f in todo:
        hit = DESTRUCTIVE.search(strip_comments(f.read_text()))
        if hit:
            state["destructive"].append(f"{f.name}: {hit.group(0)[:80]}")
    if MODE != "apply":
        result()
        return
    if os.environ.get("CONFIRM") != "APPLY":
        fail("Apply needs CONFIRM=APPLY.")
    if state["destructive"]:
        fail(
            "Destructive migrations pending; run them by hand after review and a backup."
        )
    if ",".join(state["pending"]) != os.environ.get("EXPECTED", ""):
        fail("The pending list changed since the Check. Check again.")
    for version, name, f in todo:
        record = f"insert into supabase_migrations.schema_migrations (version, name, statements) values ({quote(version)}, {quote(name)}, array[]::text[]);"
        try:
            query(ref, f"begin;\n{f.read_text()}\n{record}\ncommit;")
        except (RuntimeError, OSError, ValueError, KeyError) as e:
            state["pending"] = [
                x for x in state["pending"] if x not in state["applied"]
            ]
            fail(f"{f.name} failed and was rolled back: {e}")
        state["applied"].append(f.name)
        print(f"applied {f.name}")
    state["pending"] = []
    result()


if __name__ == "__main__":
    main()
