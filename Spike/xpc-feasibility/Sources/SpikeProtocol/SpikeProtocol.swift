import Foundation

/// Minimal @objc XPC protocol for the PP-004 feasibility spike only.
/// Not a production IPC contract: production DTOs/versioning are defined
/// under PP-006 once this spike's packaging decision is accepted.
@objc public protocol SpikeServiceProtocol {
    func ping(message: String, withReply reply: @escaping (String) -> Void)
}

public enum SpikeHandoff {
    /// Serializes an NSXPCListenerEndpoint so it can be handed to an
    /// independently-launched process over a plain file. This is a spike-only
    /// bootstrap mechanism, not a stand-in for launchd Mach service discovery.
    public static func archive(_ endpoint: NSXPCListenerEndpoint) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: endpoint, requiringSecureCoding: true)
    }

    public static func unarchive(_ data: Data) throws -> NSXPCListenerEndpoint {
        guard let endpoint = try NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSXPCListenerEndpoint.self],
            from: data
        ) as? NSXPCListenerEndpoint else {
            throw CocoaError(.coderReadCorrupt)
        }
        return endpoint
    }
}
