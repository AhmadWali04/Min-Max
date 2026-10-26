import Darwin
import Foundation
import MinMaxCore

public struct UDPError: Error, CustomStringConvertible {
    public let description: String
    init(_ operation: String) { description = "\(operation): \(String(cString: strerror(errno)))" }
    init(message: String) { description = message }
}

public struct UDPDatagram {
    public let data: Data
    fileprivate let peer: sockaddr_in
}

/// Synchronous adapter for dedicated foreground processes. One thread owns
/// each socket; do not share across tasks or call on an actor path. Receives
/// are nonblocking and polling waits are explicitly bounded.
public final class UDPSocket {
    private var descriptor: Int32 = -1

    public init(bindHost: String = "127.0.0.1", port: UInt16 = 0) throws {
        descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw UDPError("socket") }
        do {
            var address = try Self.address(host: bindHost, port: port)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else { throw UDPError("bind") }
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw UDPError("fcntl")
            }
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }
    public func close() {
        if descriptor >= 0 {
            _ = Darwin.close(descriptor)
            descriptor = -1
        }
    }

    public var localPort: UInt16 {
        get throws {
            try requireOpen()
            var address = sockaddr_in()
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let result = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(descriptor, $0, &size)
                }
            }
            guard result == 0 else { throw UDPError("getsockname") }
            return UInt16(bigEndian: address.sin_port)
        }
    }

    /// UDP connect filters incoming traffic to this peer; it is not a handshake.
    public func connect(host: String, port: UInt16) throws {
        try requireOpen()
        var address = try Self.address(host: host, port: port)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw UDPError("connect") }
    }

    public func send(_ data: Data) throws {
        try requireOpen()
        let count = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
        guard count == data.count else { throw UDPError("send") }
    }

    public func reply(_ data: Data, to datagram: UDPDatagram) throws {
        try requireOpen()
        var peer = datagram.peer
        let count = withUnsafePointer(to: &peer) { address in
            address.withMemoryRebound(to: sockaddr.self, capacity: 1) { destination in
                data.withUnsafeBytes {
                    sendto(descriptor, $0.baseAddress, $0.count, 0, destination,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard count == data.count else { throw UDPError("sendto") }
    }

    public func waitReadable(milliseconds: Int32) throws -> Bool {
        try requireOpen()
        guard (0...1000).contains(milliseconds) else {
            throw UDPError(message: "poll wait must be between 0 and 1000 ms")
        }
        var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let result = poll(&item, 1, milliseconds)
        if result < 0 {
            if errno == EINTR { return false }
            throw UDPError("poll")
        }
        if item.revents & Int16(POLLNVAL | POLLHUP) != 0 {
            throw UDPError(message: "socket became unavailable")
        }
        return result > 0 && item.revents & Int16(POLLIN | POLLERR) != 0
    }

    public func receive() throws -> UDPDatagram? {
        try requireOpen()
        // Extra byte ensures oversized/truncated datagrams fail validation.
        var buffer = [UInt8](repeating: 0, count: ProbePacket.byteCount + 1)
        var peer = sockaddr_in()
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &peer) { address in
            address.withMemoryRebound(to: sockaddr.self, capacity: 1) { source in
                buffer.withUnsafeMutableBytes {
                    recvfrom(descriptor, $0.baseAddress, $0.count, 0, source, &size)
                }
            }
        }
        if count < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return nil }
            throw UDPError("recvfrom")
        }
        return UDPDatagram(data: Data(buffer.prefix(count)), peer: peer)
    }

    private func requireOpen() throws {
        guard descriptor >= 0 else { throw UDPError(message: "socket is closed") }
    }

    private static func address(host: String, port: UInt16) throws -> sockaddr_in {
        var result = sockaddr_in()
        result.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        result.sin_family = sa_family_t(AF_INET)
        result.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &result.sin_addr) }) == 1 else {
            throw UDPError(message: "host must be a numeric IPv4 address (use 127.0.0.1 for loopback)")
        }
        return result
    }
}
