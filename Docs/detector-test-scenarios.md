# Congestion detector test scenarios (PP-005 input)

**Status:** Draft specification for PP-005 (congestion detector and policy
state machine). Authored by Claude per TASKS.md's explicit note that "Claude
can author test scenario specifications read-only or in a separate
nonconflicting path" alongside PP-005. These are **inputs to Codex's
deterministic clock-driven tests**, not an implementation — no detector code
exists yet, and none of these files are consumed by anything until PP-005
reads them.

Lives under `Scenarios/`, independent of `Package.swift` and any
Codex-owned source directory, so there is nothing here to conflict with.

## Why these scenarios exist

ARCHITECTURE.md §7 and PRD FR-06/§8 require the detector to use a minimum
sample count, sustained violation across multiple windows, and separate
enter/exit thresholds (hysteresis) — specifically so that a short spike does
not trigger mitigation and a persistent one does. TASKS.md PP-005's
acceptance criteria name five cases explicitly: short spikes, sustained
congestion, insufficient data, recovery, cooldown, and false positives. Each
scenario file below targets one or more of those directly, so PP-005's test
suite has concrete, pre-agreed fixtures instead of inventing thresholds
ad hoc per test.

**These starter threshold values are deliberately the same prototype
numbers PRD §8 already uses as examples** (50 ms degrade / 25 ms recover /
three and two sustained windows) — they are configuration to calibrate, not
validated universal defaults, exactly as PRD §8 says. PP-005 should treat
`config` in each file as the input to the state machine under test, not as
a claim about real-world network behavior.

## Scenario file format

Each `Scenarios/*.json` file is a flat, self-contained fixture:

```jsonc
{
  "scenarioId": "string, matches the filename stem",
  "description": "one sentence: what this proves",
  "targetsAcceptanceCase": "short-spike | sustained-congestion | insufficient-data | recovery | cooldown | false-positive",
  "config": {
    "baselineWindowSeconds": 60,     // trailing window used to compute baseline p50
    "rollingWindowSeconds": 10,      // size of each evaluation window
    "minSamplesPerWindow": 5,        // windows with fewer samples are not evaluated (insufficient data)
    "degradeInflationMs": 50,        // enter DEGRADED if rolling p95 - baseline p50 exceeds this...
    "degradeSustainedWindows": 3,    // ...for this many consecutive rolling windows
    "recoverInflationMs": 25,        // exit toward RECOVERING once inflation drops below this...
    "recoverSustainedWindows": 2,    // ...for this many consecutive windows
    "cooldownSeconds": 20            // minimum dwell time in RECOVERING before returning to HEALTHY
  },
  "timeline": [
    // Ordered, monotonic-clock-relative events. "rttSamples" gives every
    // successful RTT sample (ms) that arrived within that one rolling
    // window; "probeTimeout" records a lost probe (counts toward loss, not
    // toward RTT percentiles); "sessionGap" means no telemetry arrived at
    // all for that window (distinct from "all probes timed out": upstream
    // client/session telemetry itself stopped, e.g. PP-006/PP-007 session
    // expiry case, not a detector-level loss case).
    { "atSeconds": 0, "kind": "rttSamples", "valuesMs": [18, 19, 21, 20, 18] }
  ],
  "expectedStates": [
    // What PP-005's evaluator must report at/after this timestamp, and why.
    // A test should assert the state holds from this timestamp until the
    // next entry's timestamp, not just at isolated instants.
    { "atSeconds": 60, "state": "healthy", "reason": "baseline window complete, no inflation" }
  ],
  "notes": "Rationale, known limitations, anything a reviewer should not assume this scenario proves."
}
```

`state` values are the ARCHITECTURE.md §7 set: `unknown`, `healthy`,
`degraded`, `recovering`. (`mitigating` is out of scope for PP-005 — it
requires opt-in and a cooperating uploader, which is PP-012.)

## Scenarios provided

| File | Targets | Summary |
|---|---|---|
| `idle.json` | insufficient-data, baseline formation | Stable low RTT from a cold start; proves `unknown` while the baseline window is still filling, then `healthy` once it's complete and stays flat. No false `degraded` ever. |
| `short-spike.json` | short-spike (false-positive guard) | A single rolling window spikes well past the degrade threshold, then immediately returns to baseline. Must **stay `healthy`** throughout — proves `degradeSustainedWindows` actually requires consecutive violations, not just one. |
| `upload-congestion.json` | sustained-congestion, recovery, cooldown | Baseline forms, then inflation holds above threshold for more than `degradeSustainedWindows` windows (→ `degraded`), then drops and holds below the recovery threshold for `recoverSustainedWindows` windows (→ `recovering`), and must stay `recovering` for the full `cooldownSeconds` dwell before the test may assert `healthy` again. |
| `client-restart.json` | insufficient-data, false-positive guard | Healthy baseline, then a `sessionGap` (not a timeout — telemetry stops arriving entirely, as if the client process restarted per PRD Journey C) for several windows, then telemetry resumes at the same healthy rate. Must drop to `unknown` during the gap (not `degraded` — a gap is not evidence of congestion) and recover to `healthy` without needing a fresh full baseline window, since the prior baseline is still recent. |

## What PP-005 still needs to decide (not answered here)

- Exact rolling-window percentile method (nearest-rank vs interpolation) —
  ARCHITECTURE.md §7 requires picking one and using it consistently; these
  fixtures give raw per-window sample lists precisely so either method can
  be applied and checked against `expectedStates`.
- Whether a `sessionGap` of fewer than `minSamplesPerWindow` windows should
  immediately drop to `unknown` or tolerate a short gap before doing so —
  `client-restart.json`'s `notes` field states the assumption this fixture
  encodes and flags it as a decision, not a fact.
- Multi-client corroboration (PRD FR-06: "single-client spikes should not
  automatically imply shared congestion") is out of scope for every
  scenario here, since PP-005 is specified as a pure single-stream
  evaluator; that corroboration logic belongs with PP-006/PP-007's
  multi-session aggregation.
