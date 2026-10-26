import Foundation
import SpikeProtocol

// PP-004 spike: an independently-launched client (started manually from the
// shell, not spawned by this spike's own code) that looks up the Mach
// service registered by SpikeMachServer/launchd purely by name.

setbuf(stdout, nil)
let serviceName = ProcessInfo.processInfo.environment["MINMAX_SPIKE_MACH_SERVICE"] ?? "com.minmax.spike.xpc.pp004"

print("[machclient pid \(ProcessInfo.processInfo.processIdentifier)] connecting to Mach service \(serviceName)")
let connection = NSXPCConnection(machServiceName: serviceName, options: [])
connection.remoteObjectInterface = NSXPCInterface(with: SpikeServiceProtocol.self)
connection.invalidationHandler = { print("[machclient] connection invalidated") }
connection.interruptionHandler = { print("[machclient] connection interrupted") }
connection.resume()

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    FileHandle.standardError.write(Data("[machclient] XPC error: \(error)\n".utf8))
} as? SpikeServiceProtocol

let semaphore = DispatchSemaphore(value: 0)
proxy?.ping(message: "hello from machclient pid \(ProcessInfo.processInfo.processIdentifier)") { reply in
    print("[machclient pid \(ProcessInfo.processInfo.processIdentifier)] received: \(reply)")
    semaphore.signal()
}

let waitResult = semaphore.wait(timeout: .now() + 5)
if waitResult == .timedOut {
    FileHandle.standardError.write(Data("[machclient] timed out waiting for reply\n".utf8))
    connection.invalidate()
    exit(1)
}

connection.invalidate()
exit(0)
