import Foundation

/// Command packets for the Elan dongle/cable's feature report 6.
///
/// Mirrors the Amkette web app (`setCheckSum` in index-*.js): build
/// `[cmd, seq, sub, payload…]`, pad to 30 bytes, then insert
/// `(6 + Σ bytes) & 0xFF` at index 3, giving a 31-byte report body.
public enum Packet {
    public static let reportID: UInt8 = 6
    public static let bodyLength = 30

    public static func build(cmd: UInt8, seq: UInt8, sub: UInt8, payload: [UInt8], pad: UInt8, length: Int = bodyLength) -> [UInt8] {
        var bytes = [cmd, seq, sub] + payload
        precondition(bytes.count <= length, "payload too long for command 0x\(String(cmd, radix: 16))")
        bytes += Array(repeating: pad, count: length - bytes.count)
        return withChecksum(bytes)
    }

    public static func withChecksum(_ bytes: [UInt8]) -> [UInt8] {
        let sum = bytes.reduce(6) { ($0 + Int($1)) & 0xFF }
        var out = bytes
        out.insert(UInt8(sum), at: 3)
        return out
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// Rolling 8-bit command sequence number (the web app starts at 1 and pre-increments).
public struct CommandSequence {
    private var value: UInt8 = 1
    public init() {}
    public mutating func next() -> UInt8 {
        value &+= 1
        return value
    }
}
