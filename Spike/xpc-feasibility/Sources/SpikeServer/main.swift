import Foundation
import SpikeProtocol

// PP-004 spike server: hosts an anonymous NSXPCListener in its own process
// and hands its endpoint to an unrelated client process via a handoff file.
// No launchd registration, no Mach service name, no code signing involved —
// this isolates the NSXPCConnection/NSXPCListener protocol mechanics from the
// separate packaging/signing/service-registration question (see ADR-0001).

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: SpikeServer <handoff-file-path>\n".utf8))
    exit(1)
}
let handoffURL = URL(fileURLWithPath: CommandLine.arguments[1])

final class SpikeService: NSObject, SpikeServiceProtocol {
    func ping(message: String, withReply reply: @escaping (String) -> Void) {
        print("[server pid \(ProcessInfo.processInfo.processIdentifier)] received: \(message)")
        reply("pong:\(message)")
    }
}

final class SpikeListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SpikeServiceProtocol.self)
        connection.exportedObject = SpikeService()
        connection.invalidationHandler = {
            print("[server] connection invalidated")
        }
        connection.resume()
        return true
    }
}

let listener = NSXPCListener.anonymous()
let delegate = SpikeListenerDelegate()
listener.delegate = delegate
listener.resume()

do {
    let data = try SpikeHandoff.archive(listener.endpoint)
    try data.write(to: handoffURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("failed to write handoff file: \(error)\n".utf8))
    exit(1)
}

print("[server pid \(ProcessInfo.processInfo.processIdentifier)] listening, endpoint written to \(handoffURL.path)")
RunLoop.main.run()
