import CoreGraphics
import Foundation
import IOKit.hid

/// Identifies a model of mouse across reconnects. Registry IDs change every time
/// a device connects, so settings are keyed on this instead.
public struct DeviceID: Codable, Hashable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var name: String

    public init(vendorID: Int, productID: Int, name: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
    }
}

/// One pointing device as the HID event system sees it.
public struct PointingDevice: Hashable, Sendable, Identifiable {
    public let registryID: UInt64
    public let model: DeviceID
    /// "Bluetooth Low Energy", "USB", "SPI"…, as reported by the driver.
    public let transport: String
    public let isBuiltIn: Bool
    public let usagePage: Int
    public let usage: Int

    public var id: UInt64 { registryID }
    public var name: String { model.name }
    public var isBluetooth: Bool { transport.hasPrefix("Bluetooth") }
    /// Short connection name for display.
    public var transportLabel: String { isBluetooth ? "Bluetooth" : transport.isEmpty ? "Wired" : transport }

    /// A mouse or other external pointer. Trackpads report as digitizers, so they're left out.
    public var isExternalMouse: Bool {
        !isBuiltIn && usagePage == kHIDPage_GenericDesktop
            && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer)
    }

    public var isXSFlow: Bool { KnownDevices.match(vendorID: model.vendorID, productID: model.productID) != nil }

    public init(registryID: UInt64, model: DeviceID, transport: String, isBuiltIn: Bool, usagePage: Int, usage: Int) {
        self.registryID = registryID
        self.model = model
        self.transport = transport
        self.isBuiltIn = isBuiltIn
        self.usagePage = usagePage
        self.usage = usage
    }
}

/// Finds pointing devices through the HID event system, and tells which one sent a CGEvent.
///
/// CGEvents carry the sender's service registry ID in an undocumented field (87).
/// Synthetic events, such as the ones we post, have 0 there. Main-thread only.
public final class PointingDeviceRegistry {
    public static let senderIDField = CGEventField(rawValue: 87)!

    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var cache: [UInt64: PointingDevice] = [:]
    private var misses: Set<UInt64> = []

    public init() {}

    /// Every external mouse currently connected.
    public func mice() -> [PointingDevice] {
        services().map(\.device).filter(\.isExternalMouse).sorted { $0.name < $1.name }
    }

    /// The device that sent `event`, or nil for synthetic events.
    public func device(for event: CGEvent) -> PointingDevice? {
        let id = UInt64(bitPattern: event.getIntegerValueField(Self.senderIDField))
        guard id != 0 else { return nil }
        if let device = cache[id] { return device }
        guard !misses.contains(id) else { return nil }
        refresh()
        if let device = cache[id] { return device }
        misses.insert(id)
        return nil
    }

    /// Call when devices connect or disconnect. Registry IDs are never reused
    /// within a boot, so cached entries for removed devices can stay.
    public func invalidate() {
        misses.removeAll()
    }

    func services() -> [(service: IOHIDServiceClient, device: PointingDevice)] {
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return all.map { service in
            func property<T>(_ key: String) -> T? { IOHIDServiceClientCopyProperty(service, key as CFString) as? T }
            let device = PointingDevice(
                registryID: (IOHIDServiceClientGetRegistryID(service) as? UInt64) ?? 0,
                model: DeviceID(
                    vendorID: property(kIOHIDVendorIDKey) ?? 0,
                    productID: property(kIOHIDProductIDKey) ?? 0,
                    name: property(kIOHIDProductKey) ?? "Unknown Mouse"
                ),
                transport: property(kIOHIDTransportKey) ?? "",
                isBuiltIn: property(kIOHIDBuiltInKey) ?? false,
                usagePage: property(kIOHIDPrimaryUsagePageKey) ?? 0,
                usage: property(kIOHIDPrimaryUsageKey) ?? 0
            )
            return (service, device)
        }
    }

    private func refresh() {
        for (_, device) in services() { cache[device.registryID] = device }
    }
}
