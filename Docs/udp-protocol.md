# UDP protocol v1 (PP-002)

## Context and decision

The controlled game workload needs small sequenced probes and a matching echo,
without collecting packet payloads. A fixed binary layout was selected over
JSON to make lengths and validation explicit. Transport lives in `MinMaxUDP`;
encoding and injected-time tracking remain in the socket-free `MinMaxCore`.
This is a workload protocol, not the future XPC telemetry ABI.

All integers use network byte order (big endian). Exactly 32 bytes are required:

| Offset | Bytes | Value |
|---|---|---|
| 0 | 4 | ASCII `MMXP` magic |
| 4 | 1 | Version `1` |
| 5 | 1 | Kind: `0` request, `1` reply |
| 6 | 2 | Reserved, must be zero |
| 8 | 8 | Random run ID |
| 16 | 8 | Monotonically increasing sequence within the run |
| 24 | 8 | Client monotonic send timestamp in nanoseconds |

The server replies only to valid requests, preserving every field except kind.
It never interprets the client's timestamp. Malformed, oversized, unsupported,
and reply-kind input is rejected without response. Receive buffers have one
extra byte so an oversized datagram cannot masquerade as a valid 32-byte prefix.
Replies are no larger than requests. Kernel socket queues are OS-bounded;
the server creates no per-peer state, packet tasks, or application queues.

## Matching and measurements

The UDP-connected client accepts traffic only from its configured endpoint.
A reply must also match run ID, sequence and the retained local send timestamp.
The run ID separates runs; it is not authentication. This plaintext echo protocol
is for controlled endpoints and does not protect against an on-path attacker.

RTT is `(localReceiveMonotonicNs - retainedLocalSendMonotonicNs) / 1_000_000`.
It includes socket, application, output and OS scheduling overhead and is not
one-way delay. `DispatchTime.uptimeNanoseconds` supplies monotonic time; the
server's clock is irrelevant. Cadence is a minimum interval, with no catch-up
bursts after stalls. At most 128 probes may be pending; sending waits for space.

A probe expires when elapsed time is **greater than or equal to** its timeout.
A later reply remains lost for this run. It never turns into a successful RTT.
Received and timeout counts change at most once per probe. Recent completion
identities (256 by default) distinguish duplicates and late replies. Once an
identity is evicted, additional replies are unmatched; precise diagnostic counts
are limited to that bounded history. Requests are issued in sequence order, but
valid out-of-order replies are accepted independently.

The final JSON `lossPercent` is `timedOut / (received + timedOut) * 100`.
On cancellation, probes still pending appear as `cancelled`, not inferred loss.
If no probes completed, `lossPercent` is omitted. A full uninterrupted run has
`sent == received + timedOut`; a cancelled run additionally includes `cancelled`.
These are timeout-based measurements, not proof of permanent network loss.
RTT distribution, jitter, and rolling window definitions are deferred to PP-003.

## Lifecycle and limitations

The foreground server defaults to `127.0.0.1:9999` and a 60-second runtime.
Binding a non-loopback address exposes a UDP listener on that interface: only
use controlled networks/endpoints. No launchd registration, filesystem output,
privileges, signing entitlement, or global network changes are introduced.
IPv4 literals only are supported initially. CLI inputs have finite numeric
bounds; count is at most 100,000 and timeout at most 60 seconds. Errors exit
nonzero on stderr. Socket errors, including an unreachable endpoint reported
by the OS, terminate the run instead of being silently relabelled as loss.

Sockets have one foreground-thread owner and are closed on errors, completion,
duration expiry and SIGINT/SIGTERM. A dispatch signal handler updates only an
NSLock-protected cancellation flag. Poll waits are capped at 50 ms in workload
loops; there is no blocking actor path. Backpressure on stdout can delay work;
these tools are not a real-time packet generator. Do not use loopback results
to claim bufferbloat diagnosis or mitigation gains.

## Verification

`swift test` covers exact wire layout, invalid fields/lengths, matching, timeout
boundaries, wrong sessions/timestamps, duplicates, late replies, bounded history,
capacity, loopback request/reply, silence, oversize input, and idempotent close.
`Scripts/test-udp-loopback.py` checks actual separate processes, cancellation,
packet rejection and summary output using only ephemeral loopback ports.
