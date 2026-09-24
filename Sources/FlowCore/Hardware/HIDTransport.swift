import Foundation
import IOKit.hid

/// Talks to the Elan config interface: feature report 6 for commands/acks,
/// feature report 5 for a status poke, input report 4 for pushed status.
public final class HardwareController {
    public enum HardwareError: Error, CustomStringConvertible {
        case openFailed(IOReturn)
        case setReportFailed(IOReturn)
        case notAcknowledged(command: UInt8)

        public var description: String {
            switch self {
            case .openFailed(let r): String(format: "could not open the dongle's config interface (0x%08X)", r)
            case .setReportFailed(let r): String(format: "SetReport failed (0x%08X)", r)
            case .notAcknowledged(let c): String(format: "mouse did not acknowledge command 0x%02X", c)
            }
        }
    }

    public let interface: HIDInterface
    public private(set) var status: DeviceStatus?
    public var onStatus: ((DeviceStatus) -> Void)?
    /// Log hook for every packet sent/received.
    public var trace: ((String) -> Void)?

    private var seq = CommandSequence()
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private let inputBufferSize = 64
    private var isOpen = false

    public init(interface: HIDInterface) {
        self.interface = interface
        inputBuffer = .allocate(capacity: inputBufferSize)
    }

    deinit {
        close()
        inputBuffer.deallocate()
    }

    public func open() throws {
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(interface.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HardwareError.openFailed(result) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(interface.device, inputBuffer, inputBufferSize, { context, _, _, _, reportID, report, length in
            let me = Unmanaged<HardwareController>.fromOpaque(context!).takeUnretainedValue()
            me.inputReport(id: reportID, bytes: Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)
        IOHIDDeviceScheduleWithRunLoop(interface.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        IOHIDDeviceUnscheduleFromRunLoop(interface.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(interface.device, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }

    private func inputReport(id: UInt32, bytes: [UInt8]) {
        guard id == 4 else { return }
        // With report IDs, IOKit includes the ID byte at the front.
        let body = bytes.first == 4 ? Array(bytes.dropFirst()) : bytes
        trace?("← in 4: \(Packet.hex(body))")
        if let parsed = DeviceStatus(report: body) {
            status = parsed
            onStatus?(parsed)
        }
    }

    // MARK: Raw reports

    public func getFeature(_ id: UInt8, length: Int = 64) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: length)
        buffer[0] = id
        var size = CFIndex(length)
        let result = IOHIDDeviceGetReport(interface.device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &size)
        guard result == kIOReturnSuccess else {
            trace?(String(format: "← feature %d failed: 0x%08X", id, result))
            return nil
        }
        let data = Array(buffer.prefix(size))
        trace?("← feature \(id): \(Packet.hex(data))")
        return data
    }

    private func setFeature(_ body: [UInt8]) throws {
        let report = [Packet.reportID] + body
        trace?("→ feature 6: \(Packet.hex(body))")
        let result = IOHIDDeviceSetReport(interface.device, kIOHIDReportTypeFeature, CFIndex(Packet.reportID), report, report.count)
        guard result == kIOReturnSuccess else { throw HardwareError.setReportFailed(result) }
    }

    /// Byte 1 of feature report 6 is 1 when the last command succeeded.
    private func acknowledged() async -> Bool {
        try? await Task.sleep(for: .milliseconds(60))
        guard let reply = getFeature(Packet.reportID, length: 32) else { return false }
        // IOKit puts the report ID at [0], matching WebHID's DataView — so the flag is at [1].
        return reply.count > 1 && reply[1] == 1
    }

    /// Send one command packet with the web app's retry policy (3 tries, 100 + 50n ms).
    public func send(_ packet: [UInt8]) async throws {
        try open()
        var lastError: Error = HardwareError.notAcknowledged(command: packet[0])
        for attempt in 0..<3 {
            try? await Task.sleep(for: .milliseconds(100 + attempt * 50))
            do {
                try setFeature(packet)
            } catch {
                lastError = error
                continue
            }
            if await acknowledged() { return }
        }
        throw lastError
    }

    public func send(_ packets: [[UInt8]]) async throws {
        for packet in packets { try await send(packet) }
    }

    /// Pokes feature report 5; the mouse answers with input report 4.
    @discardableResult
    public func refreshStatus() async -> [UInt8]? {
        try? open()
        try? await Task.sleep(for: .milliseconds(50))
        return getFeature(5)
    }

    // MARK: High-level commands

    public func setPollingRate(_ rate: PollingRate) async throws {
        try await send(MouseProtocol.pollingRate(rate, seq: &seq))
    }

    public func setDPI(levels: [Int], currentLevel: Int, colors: [RGB]? = nil) async throws {
        let sensor = status?.sensorType ?? 3
        try await send(MouseProtocol.dpi(axis: .x, levels: levels, currentLevel: currentLevel, sensorType: sensor, seq: &seq))
        try await Task.sleep(for: .milliseconds(200))
        try await send(MouseProtocol.dpi(axis: .y, levels: levels, currentLevel: currentLevel, sensorType: sensor, seq: &seq))
        if let colors { try await send(MouseProtocol.dpiColors(colors, seq: &seq)) }
    }

    public func setButtons(_ codes: [ButtonCode]) async throws {
        try await send(MouseProtocol.buttons(codes, seq: &seq))
    }

    public func setLighting(mode: LightingMode, brightness: Int = 4, speed: Int = 3, direction: UInt8 = 0) async throws {
        try await send(MouseProtocol.lighting(mode: mode, brightness: brightness, speed: speed, direction: direction, seq: &seq))
    }

    public func setLiftOff(millimetres: UInt8) async throws {
        try await send(MouseProtocol.liftOff(millimetres: millimetres, seq: &seq))
    }

    public func setPower(sleepMinutes: Int, moveWakeup: Bool, moveLighting: Bool) async throws {
        try await send(MouseProtocol.power(sleepMinutes: sleepMinutes, moveWakeup: moveWakeup, moveLighting: moveLighting, seq: &seq))
    }

    public func setSensor(angleSnap: Bool, motionSync: Bool, ripple: Bool) async throws {
        try await send(MouseProtocol.sensor(angleSnap: angleSnap, motionSync: motionSync, ripple: ripple, seq: &seq))
    }

    public func factoryReset() async throws {
        try await send(MouseProtocol.factoryReset(seq: &seq))
    }
}
