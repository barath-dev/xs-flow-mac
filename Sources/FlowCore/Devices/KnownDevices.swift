import Foundation
import IOKit.hid

/// How the mouse is attached to this Mac.
public enum Transport: String, Codable, Sendable {
    case bluetooth = "Bluetooth"
    case dongle = "2.4G"
    case wired = "USB"
}

/// A VID/PID pair we recognise as an XS Flow mouse.
public struct KnownDevice: Sendable, Hashable {
    public let vendorID: Int
    public let productID: Int
    public let transport: Transport

    /// Only the Elan dongle/cable exposes the vendor feature-report channel
    /// used for onboard configuration. The BLE descriptor has no feature reports.
    public var supportsHardwareConfig: Bool { transport != .bluetooth }
}

public enum KnownDevices {
    /// Elan Microelectronics — the vendor the Amkette web app filters on.
    public static let elanVendorID = 0x04F3

    public static let all: [KnownDevice] = [
        KnownDevice(vendorID: 0x32C2, productID: 0x6621, transport: .bluetooth), // "XS Flow S1" over BLE
        KnownDevice(vendorID: elanVendorID, productID: 0x026F, transport: .dongle),
        KnownDevice(vendorID: elanVendorID, productID: 0x026E, transport: .wired),
    ]

    public static func match(vendorID: Int, productID: Int) -> KnownDevice? {
        all.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    /// IOHIDManager matching dictionaries for every known device.
    static var matchingDictionaries: [[String: Any]] {
        all.map { [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID] }
    }
}
