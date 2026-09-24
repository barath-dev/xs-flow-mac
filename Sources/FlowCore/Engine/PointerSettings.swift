import Foundation
import IOKit.hid

/// Applies per-device tracking speed / scroll acceleration through the HID event
/// system, leaving the trackpad and unselected mice alone. Remembers each
/// device's original values so they can be restored.
public final class PointerApplier {
    private let registry: PointingDeviceRegistry
    private var originals: [UInt64: [String: CFTypeRef]] = [:]

    static let trackingKey = kIOHIDMouseAccelerationTypeKey   // "HIDMouseAcceleration", 16.16 fixed point
    static let scrollKey = kIOHIDMouseScrollAccelerationKey   // "HIDMouseScrollAcceleration"

    public init(registry: PointingDeviceRegistry = PointingDeviceRegistry()) {
        self.registry = registry
    }

    /// Current tracking speed (0…3) of the first matching mouse, if one is connected.
    public func currentTrackingSpeed(where include: (PointingDevice) -> Bool = { $0.isExternalMouse }) -> Double? {
        guard let service = registry.services().first(where: { include($0.device) })?.service,
              let raw = IOHIDServiceClientCopyProperty(service, Self.trackingKey as CFString) as? Int else { return nil }
        return Double(raw) / 65536
    }

    /// Applies `settings` to the mice `managed` accepts and restores every other mouse.
    public func apply(_ settings: PointerSettings, managed: (PointingDevice) -> Bool) {
        for (service, device) in registry.services() where device.isExternalMouse {
            let on = managed(device)
            set(service, device.registryID, Self.trackingKey, on ? settings.trackingSpeed : nil)
            set(service, device.registryID, Self.scrollKey, on ? settings.scrollAcceleration : nil)
        }
    }

    private func set(_ service: IOHIDServiceClient, _ id: UInt64, _ key: String, _ value: Double?) {
        if let value {
            if originals[id]?[key] == nil, let original = IOHIDServiceClientCopyProperty(service, key as CFString) {
                originals[id, default: [:]][key] = original
            }
            IOHIDServiceClientSetProperty(service, key as CFString, Int(value * 65536) as CFNumber)
        } else if let original = originals[id]?.removeValue(forKey: key) {
            IOHIDServiceClientSetProperty(service, key as CFString, original)
        }
    }

    public func restore() {
        for (service, device) in registry.services() {
            for (key, value) in originals[device.registryID] ?? [:] {
                IOHIDServiceClientSetProperty(service, key as CFString, value)
            }
        }
        originals.removeAll()
    }
}
