# Independent review — PP-002 UDP echo protocol and loopback probe

**Reviewer:** Claude (read-only, per `Docs/coordination.md`'s PP-002 update
request: "review the PP-002 PR for packet validation, timeouts, socket
lifecycle, bounded state, macOS availability, and concurrency settings").
**Branch/commit reviewed:** `codex/PP-002-udp-probe` @ `9864460` ("Add
bounded UDP probe and echo workloads"), not yet merged to `main`.
**Verification performed:** `swift build` and `swift test` (15/15 tests
pass); manual end-to-end runs of `MinMaxEchoServer`/`MinMaxGameClient`
against each other and against an unoccupied port, including a real SIGINT
delivery.

## Summary

Core packet/tracker logic (`ProbePacket`, `ProbeTracker`) is careful and
well-tested — unsigned-subtraction-underflow guards, consistent "late"
classification across the two code paths that can discover a late reply,
bounded history, explicit backpressure (no catch-up bursts). One real,
100%-reproducible crash found by actually running the client against a
closed port; three lower-severity/informational items below.

## Findings

### High — `MinMaxGameClient` crashes instead of recording loss when nothing answers

**File/line:** `Sources/MinMaxUDP/UDPSocket.swift:128-130`

```swift
if count < 0 {
    if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return nil }
    throw UDPError("recvfrom")
}
```

**Failure scenario, reproduced 3/3 times:**

```
$ .build/debug/MinMaxGameClient --port 19191 --count 3 --interval-ms 20 --timeout-ms 200
MinMaxGameClient: recvfrom: Connection refused
$ echo $?
1
```

No `MinMaxEchoServer` was listening on that port. Mechanism: `runProbe`
calls `socket.connect(host:port:)` (`WorkloadCLI.swift:107`), so the
client's UDP socket is *connected*. On a connected UDP socket, a loopback
ICMP port-unreachable (triggered because nothing is listening) is
delivered back to the socket and surfaces as `ECONNREFUSED` on the next
socket call — here, inside `waitReadable`'s `poll()`, `POLLERR` is treated
as "readable" (`UDPSocket.swift:112`), so `WorkloadCLI` calls
`socket.receive()`, which calls `recvfrom`, which returns `-1` with
`errno == ECONNREFUSED`. That value isn't one of the three handled cases,
so it falls through to `throw UDPError("recvfrom")`, which is uncaught in
`runProbe` and terminates the whole process.

This isn't a corner case — "the server isn't there yet" or "the server
crashed/is overloaded" is exactly the condition this tool needs to survive
to be useful for its stated purpose (measuring RTT/loss, including under
the congestion scenarios PRD §4 Journey B describes). As written, the
probe client cannot run unattended against a server that might stop
responding, which is the whole point of a loss-measuring tool.

**Suggested fix:** treat `ECONNREFUSED` (and probably `ENETUNREACH`/
`EHOSTUNREACH`) the same way a timeout is treated — don't throw; let the
caller's existing `ProbeTracker.expire()` path account for it as loss, or
surface it as its own counted/logged condition rather than a fatal error.
**Suggested verification:** add a test standing up a `UDPSocket`, closing
it (or never binding a peer), connecting a client to that now-closed port,
and asserting `receive()`/the `runProbe` loop survives rather than throws.
None of the existing 15 tests exercise "connected to a port nothing is
listening on," which is how this was missed.

### Moderate — one bad outbound send kills the whole long-running workload

**File/line:** `Sources/MinMaxUDP/WorkloadCLI.swift:87` (`runEcho`) and
`:117` (`runProbe`)

```swift
try socket.reply(packet.reply.encoded(), to: datagram)   // runEcho
...
try socket.send(packet.encoded())                         // runProbe
```

Neither call is caught. A single transient `sendto`/`send` failure (rare
on loopback, but not impossible — e.g. `ENOBUFS` under load) ends the
entire echo server or probe run rather than being counted and continuing,
the same way malformed/rejected datagrams already are. For `MinMaxEchoServer`
specifically — meant to stay up for repeated benchmark trials per PRD §3 —
this means one bad outbound packet silently ends an in-progress trial.
**Suggested fix:** catch per-datagram send failures, increment a counter
(mirroring `rejected`/`malformed`), and keep the loop running.

### Low/informational — duplicate-of-a-late-reply is reported as `.late`, not `.duplicate`

**File/line:** `Sources/MinMaxCore/ProbeTracker.swift:62-64`

```swift
guard let (start, completion) = recent[packet.sequence],
      start == packet.sentAtNanoseconds else { return .unmatched }
return completion == .received ? .duplicate : .late
```

A second (re-delivered) copy of a reply that already timed out is reported
as `.late` again, not `.duplicate` — only repeats of a *successful* reply
get `.duplicate`. This is internally consistent and doesn't affect the
`sent`/`received`/`timedOut` counters (verified: `testExpiryBoundaryLateReplyAndNoDoubleCounting`
covers exactly this and passes), but it means `.duplicate` doesn't mean
"any repeated sequence" — worth a one-line doc comment on `ReplyResult`
saying so, so a future reader of `late`/`duplicate` counts in a report
doesn't conflate the two.

### Low/informational — protocol version isn't distinguished from "malformed"

**File/line:** `Sources/MinMaxCore/ProbePacket.swift:32-36`

Magic bytes, version byte (`bytes[4] == 1`), reserved bytes, and kind are
all checked in one `guard` and collapse to the same `ProbeError.invalidPacket`
on any mismatch. Fine for this ticket's loopback-only scope. Flagging only
because ARCHITECTURE.md §5 requires the eventual XPC envelope to reject
*unsupported versions* distinguishably from *malformed* payloads — don't
carry this merged error forward unchanged when this packet format (or its
validation pattern) feeds PP-006.

## Not independently re-verified

`SignalScope`'s restoration of the pre-existing SIGINT/SIGTERM disposition
on `deinit` (`WorkloadCLI.swift:35-36`, passing a possibly-`nil` `sig_t?`
through `signal()`). The primary path — first SIGINT stops the loop cleanly
— **was verified live** (`MinMaxEchoServer` exited with `echoed=10
rejected=0` after a real `kill -INT`). I did not verify the disposition
-restoration edge case (e.g., a second signal after the process would have
exited anyway) and am not flagging it as a finding, just noting it wasn't
exercised.
