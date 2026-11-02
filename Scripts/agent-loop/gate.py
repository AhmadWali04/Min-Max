#!/usr/bin/env python3
"""Merge-safety gate for the autonomous Codex/Claude ticket loop.

Checks a ticket branch's diff against main for anything that should force
a human-reviewed merge instead of an automatic one. Does NOT run swift
build/test -- run-once.sh does that separately and treats a failing build
the same as a gate failure.

Usage:
  gate.py <ticket-id> <tickets.json> <changed-files-file> <scoped-diff-file>

  changed-files-file: `git diff --name-only main...HEAD` output (one path/line)
  scoped-diff-file:    `git diff main...HEAD -- TASKS.md Scripts/agent-loop/tickets.json`
                        unified diff text (may be empty if neither changed)

Exit 0 and print "auto-merge-ok" if the diff is safe to auto-merge.
Exit 1 and print a reason if a human must merge instead.
"""
import json
import re
import sys
from pathlib import Path

def changed_pp_ids(diff_text: str) -> set[str]:
    """PP-### ids appearing on any added/removed line of a unified diff."""
    ids = set()
    for line in diff_text.splitlines():
        if line.startswith(("+++", "---")):
            continue  # file headers, not content
        if line.startswith(("+", "-")):
            ids.update(re.findall(r"PP-\d{3}", line))
    return ids

def main():
    if len(sys.argv) != 5:
        print("usage: gate.py <ticket-id> <tickets.json> <changed-files-file> <scoped-diff-file>", file=sys.stderr)
        return 2

    ticket_id = sys.argv[1]
    tickets_path = Path(sys.argv[2])
    changed_files_path = Path(sys.argv[3])
    scoped_diff_path = Path(sys.argv[4])

    data = json.loads(tickets_path.read_text())
    ticket = data["tickets"].get(ticket_id)
    if ticket is None:
        print(f"unknown ticket {ticket_id}")
        return 1

    changed = [l.strip() for l in changed_files_path.read_text().splitlines() if l.strip()]
    reserved = set(data.get("reserved_files", []))

    if ticket.get("human_gate"):
        print(f"{ticket_id} is flagged human_gate=true in tickets.json")
        return 1

    hit_reserved = sorted(set(changed) & reserved)
    if hit_reserved:
        print(f"diff touches reserved file(s) no automated ticket may edit: {hit_reserved}")
        return 1

    scoped_diff = scoped_diff_path.read_text() if scoped_diff_path.exists() else ""
    touched_ids = changed_pp_ids(scoped_diff)
    other_ids = touched_ids - {ticket_id}
    if other_ids:
        print(f"TASKS.md/tickets.json edit touches another ticket's entry: {sorted(other_ids)}")
        return 1

    print("auto-merge-ok")
    return 0

if __name__ == "__main__":
    sys.exit(main())
