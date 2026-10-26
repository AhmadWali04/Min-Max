import Foundation

/// A fixed-size, network-byte-order packet. No user payload or wall-clock time.
public struct ProbePacket: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case request = 0, reply = 1 }
    public static let byteCount = 32
    public let kind: Kind
    public let runID: UInt64
    public let sequence: UInt64
    public let sentAtNanoseconds: UInt64

    public init(kind: Kind, runID: UInt64, sequence: UInt64, sentAtNanoseconds: UInt64) {
        self.kind = kind
        self.runID = runID
        self.sequence = sequence
        self.sentAtNanoseconds = sentAtNanoseconds
    }

    public func encoded() -> Data {
        var bytes: [UInt8] = [0x4d, 0x4d, 0x58, 0x50, 1, kind.rawValue, 0, 0]
        for value in [runID, sequence, sentAtNanoseconds] {
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: value >> shift))
            }
        }
        return Data(bytes)
    }

    public init(decoding data: Data) throws {
        guard data.count == Self.byteCount else { throw ProbeError.invalidPacket }
        let bytes = Array(data)
        guard Array(bytes[0..<4]) == [0x4d, 0x4d, 0x58, 0x50],
              bytes[4] == 1, bytes[6] == 0, bytes[7] == 0,
              let kind = Kind(rawValue: bytes[5]) else {
            throw ProbeError.invalidPacket
        }
        func integer(at offset: Int) -> UInt64 {
            bytes[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        self.init(kind: kind, runID: integer(at: 8), sequence: integer(at: 16),
                  sentAtNanoseconds: integer(at: 24))
    }

    public var reply: Self {
        Self(kind: .reply, runID: runID, sequence: sequence, sentAtNanoseconds: sentAtNanoseconds)
    }
}

public enum ProbeError: Error, Equatable {
    case invalidPacket
    case invalidConfiguration
    case invalidSequence
    case capacityReached
}
