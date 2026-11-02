# ADR-0001: XPC listener/service packaging for the MinMax agent

**Status:** Proposed — recommended arrangement identified; full end-to-end
verification blocked on a code-signing identity (see "Open blocker" below).
**Date:** 2026-10-25
**Ticket:** PP-004
**Author:** Claude (research/design)

## Context

PRD FR-02 and ARCHITECTURE.md §5/§9 require that at least three genuinely
independent macOS processes (game probe, cooperating uploader, path probe)
register with and submit telemetry to a long-lived MinMax agent over XPC,
without the agent being a child process of any client, and without client
IDs alone being treated as authentication. ARCHITECTURE.md §13 explicitly
flags XPC packaging/signing as an open risk to prove with a working spike
before any production IPC contract is written (PP-006). This ADR records
that spike's real, observed results — not speculative API behavior — per
AGENTS.md §6 ("Never claim a build, test, benchmark, or API verification
occurred unless it actually ran").

Spike code lives outside the shared package manifest, under
`Spike/xpc-feasibility/` (its own standalone `Package.swift`), so it does
not touch `Package.swift`, which is reserved for PP-001. See that
directory's README for exact reproduction commands.

Environment this was verified on: macOS 26.6 (25G72), Xcode 27.0 (Build
27A266a), Swift 6.4 (swiftlang-6.4.0.34.1), arm64.

## Options considered

### A. Anonymous `NSXPCListener` + out-of-band endpoint handoff
Server process creates `NSXPCListener.anonymous()` and tries to hand its
`.endpoint` to an unrelated client process through some external channel
(a file, in this spike).

**Result: not viable.** `NSKeyedArchiver.archivedData(withRootObject:
requiringSecureCoding:)` on an `NSXPCListenerEndpoint` throws at runtime:

```
Caught exception during archival: *** -[NSXPCListenerEndpoint encodeWithCoder:]:
This class may only be encoded by an NSXPCCoder.
```

`NSXPCListenerEndpoint` can only be encoded by the private `NSXPCCoder` used
internally when an endpoint is passed as a parameter/reply *over an already
-established XPC connection*. It cannot be archived, written to a file, or
sent through a plain socket/pipe to a process with no prior XPC
relationship. This rules out anonymous listeners as a bootstrap mechanism
between genuinely independent, unrelated processes — anonymous listeners
are only useful for *secondary* connections handed out over a connection
that already exists (e.g., a daemon handing a client a scoped worker
connection), not for first contact. Reproduction: `Spike/xpc-feasibility`,
targets `SpikeServer`/`SpikeClient`.

### B. Bundled XPC Service inside an app bundle
Classic `.xpc` service bundle, launched on demand by launchd only when its
*owning host app* connects via `NSXPCConnection(serviceName:)`.

**Rejected without a code spike.** This arrangement is scoped to one parent
app and its private embedded service — launchd will only start the service
for connections that originate from (or are explicitly authorized by) the
host app's bundle. It does not fit independent, separately-launched client
executables (game client, uploader, path probe) that have no shared host
app, so it was not prototyped further. Revisit only if MinMax's deployment
model changes to a single umbrella app.

### C. Named Mach service via a per-user LaunchAgent
Agent process calls `NSXPCListener(machServiceName:)` and `.resume()`.
A per-user LaunchAgent `.plist` declares the same name under
`MachServices`, so launchd owns the receive right, starts/keeps the agent
running, and hands out send rights to any process (related or not) that
looks the name up via `NSXPCConnection(machServiceName:options:)`. This
matches FR-01 (per-user LaunchAgent, no root) and the "independent
processes" requirement exactly.

**Result: mechanism registers correctly; execution is blocked by code
signing, not by the XPC/launchd design.**

Verified, in order:
1. Built `SpikeMachServer`/`SpikeMachClient` (same `SpikeServiceProtocol`
   as option A) via plain `swift build`. `codesign -dv` on the product
   shows `Signature=adhoc`, `TeamIdentifier=not set` — this is what
   unmodified SPM debug builds produce on this machine (0 identities are
   present in the keychain; see "Open blocker").
2. Wrote a temporary LaunchAgent plist (`Label
   com.minmax.spike.machserver`, `MachServices: {com.minmax.spike.xpc.pp004:
   true}`, `RunAtLoad: true`, explicit `StandardOutPath`/`StandardErrorPath`)
   to a scratch path (not `~/Library/LaunchAgents`, so nothing loads
   automatically at login).
3. `launchctl bootstrap gui/501 <plist>` — exit 0. `launchctl print
   gui/501/com.minmax.spike.machserver` shows `state = running`, a real pid,
   and the Mach service endpoint `com.minmax.spike.xpc.pp004` listed under
   `endpoints`. So launchd *does* accept an unsigned/ad-hoc binary as a
   per-user LaunchAgent and *does* register the Mach service name — the
   registration step itself has no signing requirement.
4. Ran the independent client (`SpikeMachClient`, started directly from a
   shell — not spawned by the server) against that service name. It timed
   out waiting for a reply; the server emitted no logs at all, including a
   line printed before `NSXPCListener(machServiceName:).resume()` with
   `setbuf(stdout, nil)` already forced on. `ps` showed the server process
   alive but with an abnormally small ~112–304 KB physical footprint.
   `sample 11062` showed every sampled thread stuck inside
   `dyld4::JustInTimeLoader::makeLaunchLoader` → `open` — i.e., the process
   was still being loaded by dyld, never reaching `main`.
5. The unified log explained why:
   `amfid[...]: .../SpikeMachServer not valid: Error Domain=
   AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or
   signed by an unknown certificate chain"` — logged for every one of the
   four spike executables when launchd (not a plain shell) was the one
   invoking them. The identical binaries ran fine as ordinary foreground
   processes in option A's spike; AMFI only enforces this check on the
   launchd-trampoline path, consistent with `launchctl print` showing
   `trampolined = 1`.
6. Cleaned up: `launchctl bootout gui/501/com.minmax.spike.machserver`
   confirmed removed (`launchctl print` now reports "Could not find
   service"); temp plist, logs, and sample output deleted; no stray
   processes.

## Decision

**Adopt option C — a named Mach service (`NSXPCListener(machServiceName:)`)
registered by a per-user LaunchAgent — as the production arrangement**, once
the open signing blocker below is resolved. It is the only option of the
three that fits independent, unrelated client processes, matches FR-01's
per-user-LaunchAgent requirement with no root, and — registration-wise — is
confirmed working on this exact toolchain/OS. Option A is rejected outright
(API-level impossibility, not a configuration issue). Option B is rejected
for not fitting the multi-independent-process requirement.

Client **authorization** still needs real design in PP-006: launchd's Mach
service lookup proves *name discovery*, not peer identity. Use
`NSXPCConnection.processIdentifier`/audit token-based checks
(`SecCodeCheckValidity` against the connecting process) at
`shouldAcceptNewConnection`, and never trust a client-supplied session ID
alone, per AGENTS.md §5 and ARCHITECTURE.md §5's validation rules. This ADR
does not resolve that design; it only clears the transport/packaging
question so PP-006 can proceed.

## Open blocker (must resolve before PP-006/PP-009 build on this)

This machine has **zero code-signing identities** (`security find-identity
-v -p codesigning` → "0 valid identities found"). Ad-hoc signing (what
`swift build` produces by default) is rejected by `amfid` specifically when
launchd trampolines the process — not when it's run directly. This is a
real platform constraint, not a spike bug. To unblock:

1. Add a personal Apple ID under Xcode → Settings → Accounts (free, no paid
   Developer Program enrollment required for local-only signing). This
   provisions a personal development signing identity.
2. Re-run `codesign -s "<identity>" .build/debug/SpikeMachServer` (and
   `SpikeMachClient`) and repeat steps 2–6 above to get one fully verified
   round trip (`ping` → `pong:<message>` observed in both process logs).
3. Record the resulting identity/signing requirement here and promote this
   ADR's status to "Accepted" only after that round trip is observed and
   logged — do not mark it accepted on documentation alone.

**Do not scale IPC (PP-006 and beyond) before that round trip is actually
observed**, per TASKS.md PP-004's explicit gate.

## Consequences

- PP-006's production listener should use `NSXPCListener(machServiceName:)`
  inside the `MinMaxDaemon` executable, with a per-user LaunchAgent plist
  under `Config/launchd/` declaring the matching `MachServices` entry
  (PP-009 scope for install/uninstall scripts).
- Every MinMax executable that ships (daemon, clients, CLI) will need a
  real signing identity from local dev onward, not just at distribution
  time — this changes the project's dev-environment setup, not just a late
  packaging step. Document this in README setup instructions once decided.
- Anonymous `NSXPCListener` remains useful *inside* the daemon for handing
  a scoped, narrower-interface connection to an already-registered client
  (e.g., a privilege-reduced sub-channel) — just not for first contact.
- No persistent registration exists after this spike: the LaunchAgent was
  booted out and all scratch files removed in the same session.

## Verification

- `cd Spike/xpc-feasibility && swift build` — succeeds (see directory
  README for exact commands run).
- Option A round trip: **not achieved** — fails at the archival step
  (expected; documents the API constraint, not a bug to fix).
- Option C round trip: **not yet achieved** — registration verified,
  execution blocked on signing (see "Open blocker").
- No ADR claim above is inferred from documentation alone; every numbered
  step under option C reflects an actual command run and its actual output
  in this session.
