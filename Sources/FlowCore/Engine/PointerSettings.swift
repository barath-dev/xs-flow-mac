import Foundation
import IOKit.hid

/// Applies per-device tracking speed / scroll acceleration through the HID event
/// system, leaving the trackpad and other mice alone. Remembers the original
/// values so they can be restored.
public final class PointerApplier {
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var originals: [String: CFTypeRef] = [:]

    static let trackingKey = kIOHIDMouseAccelerationTypeKey   // "HIDMouseAcceleration", 16.16 fixed point
    static let scrollKey = kIOHIDMouseScrollAccelerationKey   // "HIDMouseScrollAcceleration"

    public init() {}

    private func services() -> [IOHIDServiceClient] {
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return all.filter { service in
            let vid = IOHIDServiceClientCopyProperty(service, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let pid = IOHIDServiceClientCopyProperty(service, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let page = IOHIDServiceClientCopyProperty(service, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            let usage = IOHIDServiceClientCopyProperty(service, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
            return KnownDevices.match(vendorID: vid, productID: pid) != nil
                && page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Mouse
        }
    }

    /// Current tracking speed of the mouse (0…3), if connected.
    public var currentTrackingSpeed: Double? {
        guard let service = services().first,
              let raw = IOHIDServiceClientCopyProperty(service, Self.trackingKey as CFString) as? Int else { return nil }
        return Double(raw) / 65536
    }

    public func apply(_ settings: PointerSettings) {
        set(Self.trackingKey, settings.trackingSpeed)
        set(Self.scrollKey, settings.scrollAcceleration)
    }

    private func set(_ key: String, _ value: Double?) {
        for service in services() {
            if originals[key] == nil, let original = IOHIDServiceClientCopyProperty(service, key as CFString) {
                originals[key] = original
            }
            if let value {
                IOHIDServiceClientSetProperty(service, key as CFString, Int(value * 65536) as CFNumber)
            } else if let original = originals.removeValue(forKey: key) {
                IOHIDServiceClientSetProperty(service, key as CFString, original)
            }
        }
    }

    public func restore() {
        for (key, value) in originals {
            for service in services() { IOHIDServiceClientSetProperty(service, key as CFString, value) }
        }
        originals.removeAll()
    }
}
