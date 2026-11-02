import Foundation
import SpikeProtocol

// PP-004 spike: a named Mach-service NSXPCListener, intended to be launched
// by launchd with a matching `MachServices` entry in its LaunchAgent plist.
// This is the production-shaped arrangement: genuinely independent client
// processes look up the service by name via launchd, with no prior
// relationship to this process. See Docs/adr/ADR-0001-xpc-packaging.md.

setbuf(stdout, nil)
let serviceName = ProcessInfo.processInfo.environment["MINMAX_SPIKE_MACH_SERVICE"] ?? "com.minmax.spike.xpc.pp004"

final class SpikeService: NSObject, SpikeServiceProtocol {
    func ping(message: String, withReply reply: @escaping (String) -> Void) {
        print("[machserver pid \(ProcessInfo.processInfo.processIdentifier)] received: \(message)")
        reply("pong:\(message)")
    }
}

final class SpikeListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        print("[machserver] accepting connection from audit token pid \(connection.processIdentifier)")
        connection.exportedInterface = NSXPCInterface(with: SpikeServiceProtocol.self)
        connection.exportedObject = SpikeService()
        connection.invalidationHandler = {
            print("[machserver] connection invalidated")
        }
        connection.resume()
        return true
    }
}

print("[machserver pid \(ProcessInfo.processInfo.processIdentifier)] registering Mach service \(serviceName)")
let listener = NSXPCListener(machServiceName: serviceName)
let delegate = SpikeListenerDelegate()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
