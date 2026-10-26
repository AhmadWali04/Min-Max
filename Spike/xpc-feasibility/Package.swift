// swift-tools-version: 5.10
import PackageDescription

// PP-004 isolated XPC feasibility spike. Deliberately NOT part of the root
// MinMax package/Package.swift (reserved by Codex for PP-001). This package
// proves out NSXPCListener/NSXPCConnection mechanics between two genuinely
// separate processes before any production IPC contract is written. See
// ../../Docs/adr/ADR-0001-xpc-packaging.md.
let package = Package(
    name: "xpc-feasibility",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SpikeProtocol"),
        .executableTarget(name: "SpikeServer", dependencies: ["SpikeProtocol"]),
        .executableTarget(name: "SpikeClient", dependencies: ["SpikeProtocol"]),
        .executableTarget(name: "SpikeMachServer", dependencies: ["SpikeProtocol"]),
        .executableTarget(name: "SpikeMachClient", dependencies: ["SpikeProtocol"]),
    ]
)
