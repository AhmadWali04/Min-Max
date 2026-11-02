# Metrics (PP-003)

`RollingMetrics` implements nearest-rank percentiles and mean absolute
successive RTT differences, adopting Claude's proposed formulas. It takes
monotonic nanoseconds supplied by its caller, so tests do not sleep. Use
`DispatchTime.now().uptimeNanoseconds` in adapters; wall time is only for logs.
This is a core library, not an XPC contract or a claim of network performance.

RTT is elapsed local monotonic time between a sequenced request and its matching
reply, including application scheduling overhead. Only finite, nonnegative
successful RTTs belong in the distribution. For N sorted samples, percentile p
is the sample at one-based rank `ceil(N*p/100)`. Empty distributions return nil.
For 1..20 ms, p50/p95/p99 are 10/19/20 ms. For 10,20,...,70 ms they are 40/70/70.
Small samples cannot resolve tail percentiles well; report sampleCount.

Jitter is the mean absolute difference between successive successful RTTs in
completion order, across intervening timeouts. It is not RFC 3550 jitter.
Fewer than two samples return nil. The sequence 20,22,19,25,18,21 ms gives
4.2 ms. Sorting occurs only for percentiles, never for jitter.

Loss is `timeoutCount / (sampleCount + timeoutCount) * 100` over completed
observations in the window. Pending and cancelled probes are excluded. The
caller must submit exactly one completion per probe; sequence matching,
deduplication, and timeout detection belong to PP-002's ProbeTracker. A late
reply adds only a diagnostic observation and never reverses a timeout or adds
another completion. Repeated late packets may contribute repeated diagnostics.
Eighteen successes and two timeouts, one of which later replies, yield 10%
timeout loss and one late-reply diagnostic. This corrects the draft's 5% loss
example: the PRD defines loss by the reply deadline, not permanent packet loss.
With no completed probes, lossPercent is nil.

Windows are trailing completion-time intervals `(now-duration, now]`. Before
monotonic uptime reaches duration, the lower bound is clamped to zero and
observations at zero are retained until they reach the declared age. Snapshots
include both bounds, counts, and lifetime capacity evictions. Events at exactly
the duration expire. New observations and snapshots reject backward time.
Capacity is configured between 1 and 1,000,000 observations. A circular buffer
stores at most that many entries; full buffers evict oldest observations and
increment a saturating lifetime counter. Normal time expiration is separate.
Capacity truncation can bias statistics; consumers must disclose evictions.
Snapshot construction uses bounded O(capacity) temporary storage and sorts
successful RTTs. Mutating state needs one owner (for example an actor).

The baseline and sustained-window detector are PP-005 work; RollingMetrics does
not infer congestion or implement policy. Throughput will use acknowledged
application bytes divided by the measured monotonic interval, not link capacity.
