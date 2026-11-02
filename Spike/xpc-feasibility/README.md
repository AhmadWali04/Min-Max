# PP-004 XPC feasibility spike

Standalone package, deliberately **not** part of the root `Package.swift`
(reserved by Codex for PP-001/PP-002). Exists only to retire the XPC
packaging risk flagged in ARCHITECTURE.md §13 before any production IPC
contract (PP-006) is written. Findings are written up in
[`../../Docs/adr/ADR-0001-xpc-packaging.md`](../../Docs/adr/ADR-0001-xpc-packaging.md).

Verified on macOS 26.6 (25G72), Xcode 27.0, Swift 6.4, arm64.

## Build

```bash
cd Spike/xpc-feasibility
swift build
```

## Spike A — anonymous listener + file handoff (`SpikeServer` / `SpikeClient`)

Demonstrates (negatively) that an `NSXPCListenerEndpoint` cannot be
serialized/handed to an unrelated process through an arbitrary side
channel.

```bash
HANDOFF=/tmp/minmax-spike-handoff.data
rm -f "$HANDOFF"
.build/debug/SpikeServer "$HANDOFF" &
sleep 1
.build/debug/SpikeClient "$HANDOFF"
```

Expected (actual observed) result: the server logs an `NSKeyedArchiver`
failure ("This class may only be encoded by an NSXPCCoder") and never
writes the handoff file; the client times out. This is the expected,
documented outcome of this spike, not a bug to fix — see ADR-0001, option A.

## Spike B — named Mach service via a per-user LaunchAgent (`SpikeMachServer` / `SpikeMachClient`)

This is the production-shaped arrangement. It requires a temporary
per-user launchd job — ask before running this against a shared machine.

```bash
SERVICE=com.minmax.spike.xpc.pp004
BIN="$(pwd)/.build/debug/SpikeMachServer"
PLIST=/tmp/com.minmax.spike.machserver.plist
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.minmax.spike.machserver</string>
    <key>ProgramArguments</key><array><string>$BIN</string></array>
    <key>MachServices</key><dict><key>$SERVICE</key><true/></dict>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>/tmp/minmax-spike-machserver.out.log</string>
    <key>StandardErrorPath</key><string>/tmp/minmax-spike-machserver.err.log</string>
</dict>
</plist>
EOF

launchctl bootstrap gui/$(id -u) "$PLIST"
launchctl print gui/$(id -u)/com.minmax.spike.machserver   # confirm state = running

MINMAX_SPIKE_MACH_SERVICE=$SERVICE .build/debug/SpikeMachClient

# cleanup — always run this after the test
launchctl bootout gui/$(id -u)/com.minmax.spike.machserver
rm -f "$PLIST" /tmp/minmax-spike-machserver.out.log /tmp/minmax-spike-machserver.err.log
```

**As of this writing, the client call times out.** `launchctl print` shows
the service correctly registered and the job `running`, but the server
process never reaches `main` — it is stuck in dyld under the launchd
trampoline. The unified log explains why:

```bash
log show --last 5m --predicate 'process == "amfid"' --style compact
# ... /SpikeMachServer not valid: Error Domain=AppleMobileFileIntegrityError
#     Code=-423 "The file is adhoc signed or signed by an unknown certificate chain"
```

`codesign -dv .build/debug/SpikeMachServer` confirms `Signature=adhoc`,
`TeamIdentifier=not set`. There are no code-signing identities in this
machine's keychain (`security find-identity -v -p codesigning` → "0 valid
identities found"). This is a real platform constraint, not a spike bug —
see ADR-0001's "Open blocker" for how to unblock it (an Apple ID added
under Xcode → Settings → Accounts, then `codesign -s "<identity>"` on the
binaries before `launchctl bootstrap`).

## Cleanup check

After running Spike B, always confirm nothing was left registered:

```bash
launchctl print gui/$(id -u)/com.minmax.spike.machserver
# expect: "Could not find service ... in domain for user gui"
```
