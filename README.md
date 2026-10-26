# MinMax

MinMax is a macOS network-intelligence project for measuring latency during
controlled, cooperating workloads. It is intentionally being built in small
verified steps. The current iteration provides a controlled UDP echo server
and probe client with RTT and timeout accounting.

## Requirements

- macOS 14 or newer
- Swift 5.10 or newer (the package uses Swift Package Manager)

## Build and test

From the repository root:

```sh
swift --version
swift build
swift test
python3 Scripts/test-udp-loopback.py
```

The package currently provides:

- `MinMaxCore`, the socket-free packet and probe-tracking library
- `MinMaxUDP`, a macOS POSIX socket adapter used by the workload executables
- `MinMaxGameClient`, a paced UDP probe client
- `MinMaxEchoServer`, a controlled UDP echo endpoint

Run their help output with:

```sh
swift run MinMaxGameClient --help
swift run MinMaxEchoServer --help
```

## Local probe

Build first, then start the server in one terminal:

```sh
.build/debug/MinMaxEchoServer --host 127.0.0.1 --port 9999 --duration-seconds 60
```

In a second terminal:

```sh
.build/debug/MinMaxGameClient --host 127.0.0.1 --port 9999 --count 20 --interval-ms 50 --timeout-ms 1000
```

The client prints one RTT line per successful probe and a final JSON object
with sent, received, timed-out, cancelled, duplicate, late, unmatched and
malformed counts. A successful loopback exchange should have `received`
equal to `sent`; timing and loss depend on scheduling and local conditions.
SIGINT (Ctrl-C) or SIGTERM stops either process cleanly. The server also
stops after its configured duration. Port `0` asks the server to choose and
print an ephemeral port.

The server binds only loopback by default. Numeric IPv4 addresses are supported;
DNS names and IPv6 are deferred. Use other addresses only for endpoints you
control or have permission to test. No service installation, privileges, or
entitlements are required. These foreground tools use synchronous, bounded
polling outside actors; do not embed their run loops in an actor.

See [the UDP protocol and measurement limits](Docs/udp-protocol.md) and
[agent coordination](Docs/coordination.md). Percentiles, jitter and rolling
metrics are PP-003; daemon/XPC and upload mitigation come in later tickets.
Loopback results do not establish congestion mitigation or router behavior.
