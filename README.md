# MinMax

MinMax is a macOS network-intelligence project for measuring latency during
controlled, cooperating workloads. It is intentionally being built in small
verified steps; this bootstrap contains only the Swift package and launchable
placeholders.

## Requirements

- macOS 14 or newer
- Swift 5.10 or newer (the package uses Swift Package Manager)

## Build and test

From the repository root:

```sh
swift --version
swift build
swift test
```

The package currently provides:

- `MinMaxCore`, the Foundation-only shared library
- `MinMaxGameClient`, a minimal executable placeholder
- `MinMaxEchoServer`, a minimal executable placeholder

Run the placeholders and their help output with:

```sh
swift run MinMaxGameClient --help
swift run MinMaxEchoServer --help
```

UDP probing, XPC, metrics, and persistent services are deliberately out of
scope for this bootstrap and will be added by later tickets.