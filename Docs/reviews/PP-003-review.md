# PP-003 independent review — bounded deterministic rolling metrics

**Reviewer:** Claude (read-only review per `AGENTS.md` §3/§8).
**Reviewed:** `codex/PP-003-metrics` at `d2cea9a` ("Implement bounded
deterministic rolling metrics for PP-003"), not yet merged/PR'd as of this
review. Scope: `Sources/MinMaxCore/RollingMetrics.swift`,
`Tests/MinMaxCoreTests/RollingMetricsTests.swift`, `Docs/metrics.md`.

## What I did to verify this

Checked out the commit in its existing worktree (`.worktrees/PP-003`), read
the full diff, and independently re-derived the percentile/jitter/eviction
arithmetic by hand against every test's expected literal (not just read the
assertions) before running anything. Then ran, myself, in that worktree:

- `swift build` — pass.
- `swift test` — pass, 7/7 (`RollingMetricsTests` ×6 + the pre-existing
  `MinMaxCoreTests.testPackageIdentity`; this worktree predates the PP-002
  merge, so `ProbeTests`/`UDPSocketTests` are not present here).

## Correctness

No defects found. Specifically checked:

- **Percentile formula** (`rank = (N*p + 99) / 100` via integer division,
  i.e. `ceil(N*p/100)`): verified by hand for N=1, N=4, N=7, N=20, N=100
  against the nearest-rank definition in `ARCHITECTURE.md` §7 and
  `Docs/metrics.md`. All of `testClaudePercentileAndJitterVectors` and
  `testOutlierAndCompletionOrder`'s expected p50/p95/p99 values reproduce
  correctly from the formula by hand, including the N=7 p95/p99 collision
  case (`70, 70` — expected, not a bug, per the metrics doc's own note).
- **Jitter** (mean absolute successive difference in completion order):
  hand-verified both test vectors (`[20,22,19,25,18,21] → 4.2`,
  `[70,10,60,20,50,30,40] → 35`) match the dividing-before-summing
  implementation exactly.
- **Capacity-vs-time eviction interaction**
  (`testExpirationBoundaryAndRingWraparound`, window=10ns/capacity=2,
  monotonically increasing insert times 0..99): traced the ring buffer by
  hand through the capacity-eviction steady state (oldest evicted every
  insert once full, since the 1ns insert cadence never triggers the
  10ns time-based expiry while capacity-bound) and through the boundary
  case afterward (`now - entry.time >= window` evicts *at* exact equality,
  consistent with `ProbeTracker`'s existing "late at deadline" convention
  from PP-002). `capacityEvictions == 98`, `retainedCount == 2`,
  `p50 == 98` at `snapshot(at:99)`, then `sampleCount` drops to 1 at
  `snapshot(at:108)` and 0 at `snapshot(at:109)` — all reproduce by hand.
- **Loss definition corrects a real error in my own PP-003 draft**
  (`Docs/metrics.md`'s prior version): the draft's worked example used
  `lossRate = permanently-lost / sent = 5%`; the implementation and its
  replacement doc correctly use `timeoutCount / (sampleCount + timeoutCount)`
  measured at the reply deadline (10%, per PRD/ARCHITECTURE §7's
  deadline-based definition), with late replies kept as a separate
  diagnostic that never un-counts a timeout. This is the right call —
  flagging it here so it's visible this was deliberate, not an unreviewed
  deviation from the draft I wrote.
- **Validation**: non-finite/negative RTTs, zero window, out-of-range
  capacity (`0` and presumably `>1_000_000`, not explicitly tested for the
  upper bound but the guard is a plain range check), and backward time all
  throw before mutating state — `testValidationDoesNotMutateState`
  confirms the throwing calls leave prior state intact.

## Design notes (not blocking, for whoever builds the PP-002→PP-003 adapter)

1. **The "exactly one completion per probe" invariant is a caller contract,
   not type-enforced.** `RollingMetrics` has no notion of a probe identity —
   it only records `.reply`/`.timeout`/`.lateReply` events as told. Nothing
   stops a buggy adapter from submitting two `.timeout`s for the same probe,
   or a `.lateReply` with no preceding `.timeout`. This is explicitly
   documented in both the handoff and `Docs/metrics.md` ("The caller must
   submit exactly one completion per probe") and is a reasonable scope
   boundary for a pure core type, but it means whoever wires PP-002's
   `ProbeTracker` into this (likely PP-007's telemetry store, or an adapter
   ahead of it) owns getting that exactly right — `ProbeTracker` currently
   exposes `timedOut` as a running counter via its `expire()` sweep, not as
   a discrete event stream, so translating "counter went up by N" into "feed
   N `.timeout` observations, each exactly once" needs explicit, tested
   logic at that boundary. Worth a scenario test at that integration point
   specifically for duplicate/missed timeout translation.
2. **`Sendable` value-type, single-owner by design** (per its own doc
   comment) — correct for this ticket's scope (pure core evaluator), but it
   means thread-safety is entirely deferred to whatever wraps it (an actor,
   per `ARCHITECTURE.md`). Not a defect now; flagging so PP-007 doesn't
   assume `RollingMetrics` itself is safe to share across isolation domains
   without that wrapper.
3. Minor: the "divide each term before summing to avoid overflow" comment
   on the jitter calculation overstates the risk for `Double` RTT
   magnitudes (no realistic overflow path), but the technique is harmless
   and doesn't need to change.

## Acceptance criteria check (TASKS.md PP-003)

"Tests cover empty windows, outliers, p50/p95/p99, lost/late packets,
expiration and max capacity" — all present and independently verified
above. No gaps found against the written acceptance criteria.

## Verdict

No blocking findings. Recommend merge once pushed/PR'd, same as PP-002's
path: human merge (not a reserved-file diff here — `RollingMetrics.swift`
is a new file in an existing target, `Package.swift` is untouched — so
this one *would* be eligible for the agent-loop's autonomous self-merge
criteria if claimed and run through it, modulo the loop's own gate
re-verifying build/test itself).
