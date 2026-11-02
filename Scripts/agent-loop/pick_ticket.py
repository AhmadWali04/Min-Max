#!/usr/bin/env python3
"""Pick the next eligible ticket for an agent from tickets.json.

Eligibility:
  - ticket.owner == agent
  - ticket.status in ("pending", "branch_exists")   # "blocked"/"done"/"pr_open_needs_human" never auto-picked
  - every ticket in depends_on has status == "done"
  - no live lock directory for this ticket id

Prints the ticket id and its JSON on stdout (two lines: id, then JSON blob)
and exits 0 if one is found. Exits 1 with nothing on stdout if none is
eligible right now (not an error -- just "nothing to do this cycle").
"""
import json
import sys
from pathlib import Path

def main():
    if len(sys.argv) != 4:
        print("usage: pick_ticket.py <codex|claude> <tickets.json path> <locks dir>", file=sys.stderr)
        sys.exit(2)

    agent, tickets_path, locks_dir = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    data = json.loads(tickets_path.read_text())
    tickets = data["tickets"]
    done = {tid for tid, t in tickets.items() if t["status"] == "done"}

    for tid, t in tickets.items():  # insertion order == critical-path priority order
        if t["owner"] != agent:
            continue
        if t["status"] not in ("pending", "branch_exists"):
            continue
        deps = t.get("depends_on", [])
        if not all(d in done for d in deps):
            continue
        if (locks_dir / tid).exists():
            continue
        print(tid)
        print(json.dumps(t))
        return 0

    return 1

if __name__ == "__main__":
    sys.exit(main())
