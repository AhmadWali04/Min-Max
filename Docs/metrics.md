# Metric definitions (PP-003 draft input)

**Status:** Draft, not a frozen contract. ARCHITECTURE.md §7 requires metric
definitions, sample counts, and the exclusion of any limitation to be
recorded here "before publishing benchmark claims," and explicitly leaves
one method choice open ("nearest-rank or documented interpolation method
... use consistent method in tests/reports"). This document proposes
concrete formulas and worked numeric examples Codex can adopt, amend, or
replace outright when implementing PP-003 — nothing here is implemented
yet, and nothing here touches `Package.swift` or any source directory.
Same spirit as the PP-005 scenario fixtures: a concrete, checkable
proposal instead of restating ARCHITECTURE.md's prose.

The worked examples below are designed as golden test vectors — paste the
inputs into a unit test and assert the exact outputs, the same way the
PP-005 `Scenarios/*.json` fixtures are meant to be used.

## RTT

Elapsed **monotonic** time between sending a sequenced UDP probe and
receiving its matching reply (by sequence number), per ARCHITECTURE.md §7.
Includes application scheduling overhead; this is intentional — it is the
latency the game-probe workload actually experiences, not a kernel-only
figure. Use `ContinuousClock`/`DispatchTime`, never `Date`, for the
subtraction itself; `Date` is for correlating events across processes in
logs/reports only.

## Percentiles (p50 / p95 / p99) — nearest-rank method (proposed)

**This is the one open decision PP-003 needs to confirm or override.**
Proposing nearest-rank over interpolation because it never invents a value
that wasn't actually observed, which matters when a single outlier sample
(e.g. one real timeout-adjacent RTT) needs to be traceable back to a real
measurement during debugging/benchmark review.

For a window of `N` valid RTT samples sorted ascending, the p-th percentile
is the sample at 1-indexed rank:

```
rank(p, N) = ceil(p / 100 * N), clamped to [1, N]
percentile(p, N) = sorted[rank(p, N) - 1]   // 0-indexed array access
```

### Worked example A — N = 20, samples = 1..20 ms (already sorted)

| p | p/100 * N | ceil | rank | value |
|---|---|---|---|---|
| 50 | 10.0 | 10 | 10 | **10 ms** |
| 95 | 19.0 | 19 | 19 | **19 ms** |
| 99 | 19.8 | 20 | 20 | **20 ms** |

p95 here is an exact-boundary case (`19.0` already an integer — confirms
`ceil` must not add 1 when the product is already exact) and p99 is a
rounding-up case (`19.8 → 20`). Both must be checked; a common off-by-one
bug is applying `ceil` only when there's a remainder, or using `round`
instead of `ceil`.

### Worked example B — N = 7, samples = [10, 20, 30, 40, 50, 60, 70] ms

| p | p/100 * N | ceil | rank | value |
|---|---|---|---|---|
| 50 | 3.5 | 4 | 4 | **40 ms** |
| 95 | 6.65 | 7 | 7 | **70 ms** |
| 99 | 6.93 | 7 | 7 | **70 ms** |

p95 and p99 are identical here — with only 7 samples, the method cannot
distinguish them. This is expected, not a bug, and is exactly why FR-06 and
the PP-005 scenarios require a `minSamplesPerWindow` floor: below some
sample count, p95/p99 stop being meaningful and the detector should prefer
`unknown` over a false percentile reading. Report the sample count
alongside every percentile per ARCHITECTURE.md §7 — a reader must be able
to tell worked example B's p95 apart from example A's.

## Jitter — mean absolute successive difference (proposed)

ARCHITECTURE.md §7 gives this as the example formula and requires it be
documented explicitly rather than presented as RFC 3550 jitter (which uses
a different, exponentially-smoothed estimator) unless that algorithm is
actually implemented. Proposing the simpler mean-absolute-successive-diff
version for PP-003 v1:

```
jitter(samples) = (1 / (N - 1)) * sum(|samples[i] - samples[i-1]| for i in 1..<N)
```

Only defined for `N >= 2`; report `unknown`/omit for single-sample windows
rather than returning 0, which would silently imply "no jitter observed"
instead of "not enough data."

### Worked example — samples = [20, 22, 19, 25, 18, 21] ms

Successive absolute differences: `|22-20|=2, |19-22|=3, |25-19|=6,
|18-25|=7, |21-18|=3` → sum = 21, N-1 = 5 → **jitter = 4.2 ms**.

## Loss and late replies

Given `N` probes sent in a window with a declared timeout `T`:
- **Successful sample:** reply arrives within `T` → contributes to the RTT
  distribution above.
- **Loss:** no reply arrives within `T`. `lossRate = lostCount / N`.
- **Late reply:** a reply arrives *after* `T` has already elapsed and the
  probe was already counted as lost. Per ARCHITECTURE.md §7, this must be
  tracked and reported **separately** from permanent loss — do not
  silently fold late replies back into the RTT distribution (that would
  understate real loss) and do not drop them with no record (that would
  hide a signal that the timeout itself may be mistuned).

### Worked example — 20 probes sent, T = 100 ms

18 replies arrive within 100 ms (→ RTT distribution, use worked example A's
method on these 18 values); 1 reply arrives at 130 ms (→ counted as late,
excluded from the RTT distribution, tracked in its own counter); 1 probe
never replies (→ lost).

`lossRate = 1/20 = 5%`, `lateRate = 1/20 = 5%`, `sampledRate = 18/20 = 90%`.
All three should be reported together — a reader comparing two windows
needs sample count and all three rates, not just loss rate alone, to tell
"the network got worse" apart from "the timeout is too tight."

## Baseline and latency inflation

Per ARCHITECTURE.md §7 / PRD §8:

```
baseline = p50(RTT samples over the trailing baselineWindowSeconds, while HEALTHY)
inflation = p95(RTT samples over the current rollingWindowSeconds) - baseline
```

Report the sample counts and exact window boundaries (start/end monotonic
timestamps) used for both the baseline and the current window alongside
any inflation figure — an inflation number with no window metadata cannot
be checked or reproduced later. See `Docs/detector-test-scenarios.md` for
how this combines with sustained-window hysteresis in the detector itself
(PP-005) — that document owns the state-machine behavior; this one owns
only the arithmetic the state machine consumes.

## Throughput

Acknowledged application-layer bytes transferred over a measured interval
— `bytesAcked / intervalSeconds`. Not an inferred link-capacity estimate;
do not extrapolate from one short interval to a sustained-rate claim
without reporting the interval length and variance across repeated trials,
per PRD §3's benchmark protocol.
