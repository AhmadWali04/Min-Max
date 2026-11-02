import Foundation
import SpikeProtocol

// PP-004 spike client: an independently-launched process (own PID, own
// executable) that reads the handoff file written by SpikeServer, rebuilds
// the NSXPCListenerEndpoint, and issues a real cross-process XPC call.

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: SpikeClient <handoff-file-path>\n".utf8))
    exit(1)
}
let handoffURL = URL(fileURLWithPath: CommandLine.arguments[1])

var data: Data?
for _ in 0..<50 {
    if let d = try? Data(contentsOf: handoffURL) {
        data = d
        break
    }
    Thread.sleep(forTimeInterval: 0.1)
}

guard let data else {
    FileHandle.standardError.write(Data("timed out waiting for handoff file\n".utf8))
    exit(1)
}

let endpoint: NSXPCListenerEndpoint
do {
    endpoint = try SpikeHandoff.unarchive(data)
} catch {
    FileHandle.standardError.write(Data("failed to unarchive endpoint: \(error)\n".utf8))
    exit(1)
}

let connection = NSXPCConnection(listenerEndpoint: endpoint)
connection.remoteObjectInterface = NSXPCInterface(with: SpikeServiceProtocol.self)
connection.invalidationHandler = { print("[client] connection invalidated") }
connection.interruptionHandler = { print("[client] connection interrupted") }
connection.resume()

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    FileHandle.standardError.write(Data("[client] XPC error: \(error)\n".utf8))
} as? SpikeServiceProtocol

let semaphore = DispatchSemaphore(value: 0)
proxy?.ping(message: "hello from client pid \(ProcessInfo.processInfo.processIdentifier)") { reply in
    print("[client pid \(ProcessInfo.processInfo.processIdentifier)] received: \(reply)")
    semaphore.signal()
}

let waitResult = semaphore.wait(timeout: .now() + 5)
if waitResult == .timedOut {
    FileHandle.standardError.write(Data("[client] timed out waiting for reply\n".utf8))
    connection.invalidate()
    exit(1)
}

connection.invalidate()
exit(0)
