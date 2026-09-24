import Foundation
import IOKit.hid

/// One HID interface of a recognised XS Flow mouse. A dongle exposes several
/// interfaces (mouse, keyboard, vendor), each shows up as its own `HIDInterface`.
public final class HIDInterface: @unchecked Sendable, Hashable {
    public let device: IOHIDDevice
    public let known: KnownDevice

    init(device: IOHIDDevice, known: KnownDevice) {
        self.device = device
        self.known = known
    }

    public var product: String { property(kIOHIDProductKey) ?? "Unknown" }
    public var transportName: String { property(kIOHIDTransportKey) ?? "?" }
    public var primaryUsagePage: Int { property(kIOHIDPrimaryUsagePageKey) ?? 0 }
    public var primaryUsage: Int { property(kIOHIDPrimaryUsageKey) ?? 0 }
    public var maxFeatureReportSize: Int { property(kIOHIDMaxFeatureReportSizeKey) ?? 0 }
    public var reportDescriptor: Data { property(kIOHIDReportDescriptorKey) ?? Data() }

    /// The Elan vendor interface: the one declaring feature report 6 (the command channel).
    public var isConfigInterface: Bool {
        known.supportsHardwareConfig && maxFeatureReportSize > 1
            && ReportDescriptor.featureReportIDs(in: reportDescriptor).contains(6)
    }

    func property<T>(_ key: String) -> T? {
        IOHIDDeviceGetProperty(device, key as CFString) as? T
    }

    public static func == (lhs: HIDInterface, rhs: HIDInterface) -> Bool { lhs.device == rhs.device }
    public func hash(into hasher: inout Hasher) { hasher.combine(CFHash(device)) }
}

/// A single HID input value change from one of our mice.
public struct HIDInputEvent: Sendable {
    public let usagePage: Int
    public let usage: Int
    public let value: Int
    /// Mach absolute time, same clock as `CGEvent.timestamp`.
    public let timestamp: UInt64
    public let transport: Transport

    public var isButton: Bool { usagePage == kHIDPage_Button }
    public var isWheel: Bool { usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Wheel }
    public var isHorizontalWheel: Bool { usagePage == kHIDPage_Consumer && usage == kHIDUsage_Csmr_ACPan }
    public var isConsumer: Bool { usagePage == kHIDPage_Consumer && !isHorizontalWheel }

    public var description: String {
        if isButton { return "button \(usage) \(value != 0 ? "down" : "up")" }
        if isWheel { return "wheel \(value)" }
        if isHorizontalWheel { return "hwheel \(value)" }
        if usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_X { return "x \(value)" }
        if usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Y { return "y \(value)" }
        return String(format: "page 0x%02X usage 0x%02X value %d", usagePage, usage, value)
    }
}

/// Watches for XS Flow mice via IOHIDManager and reports their raw input.
/// Must be used from the main thread (callbacks are scheduled on the main run loop).
public final class DeviceMonitor {
    public private(set) var interfaces: Set<HIDInterface> = []

    public var onChange: (() -> Void)?
    public var onInput: ((HIDInputEvent) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    public init() {}

    /// Connected transports, one entry per physical connection.
    public var transports: [Transport] {
        Array(Set(interfaces.map(\.known.transport))).sorted { $0.rawValue < $1.rawValue }
    }

    public var configInterface: HIDInterface? { interfaces.first(where: \.isConfigInterface) }

    /// Starts matching. Pass `readInput: false` to only enumerate devices, which
    /// works without the Input Monitoring permission.
    @discardableResult
    public func start(readInput: Bool = true) -> IOReturn {
        IOHIDManagerSetDeviceMatchingMultiple(manager, KnownDevices.matchingDictionaries as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.deviceAdded(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, sender, value in
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.inputValue(value, sender: sender)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        guard readInput else { return kIOReturnSuccess }
        return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        interfaces.removeAll()
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        guard let known = KnownDevices.match(vendorID: vid, productID: pid) else { return }
        interfaces.insert(HIDInterface(device: device, known: known))
        onChange?()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        interfaces = interfaces.filter { $0.device != device }
        onChange?()
    }

    private func inputValue(_ value: IOHIDValue, sender: UnsafeMutableRawPointer?) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let iface = interfaces.first(where: { $0.device == device }) else { return }
        // Ignore array/padding elements and relative values that report zero.
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        guard usage != 0, usage != 0xFFFFFFFF else { return }
        let intValue = IOHIDValueGetIntegerValue(value)
        if IOHIDElementIsRelative(element) && intValue == 0 { return }
        onInput?(HIDInputEvent(
            usagePage: page,
            usage: usage,
            value: intValue,
            timestamp: IOHIDValueGetTimeStamp(value),
            transport: iface.known.transport
        ))
    }
}
