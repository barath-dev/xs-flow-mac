import CoreGraphics
import Foundation
import IOKit.hid
import Testing
@testable import FlowCore

@Suite struct PointingDeviceTests {
    func device(_ name: String, page: Int = kHIDPage_GenericDesktop, usage: Int = kHIDUsage_GD_Mouse,
                builtIn: Bool = false, vid: Int = 0x046D, pid: Int = 0xB015) -> PointingDevice {
        PointingDevice(registryID: 1, model: DeviceID(vendorID: vid, productID: pid, name: name),
                       transport: "Bluetooth Low Energy", isBuiltIn: builtIn, usagePage: page, usage: usage)
    }

    @Test func onlyExternalMiceAreManaged() {
        let config = Config.default
        #expect(config.manages(device("M720 Triathlon")))
        #expect(config.manages(device("Pointer", usage: kHIDUsage_GD_Pointer)))
        // The built-in trackpad reports as a digitizer (page 0x0D).
        #expect(!config.manages(device("Apple Internal Keyboard / Trackpad", page: kHIDPage_Digitizer, usage: 0x0C, builtIn: true)))
        #expect(!config.manages(device("Built-in mouse", builtIn: true)))
        #expect(!config.manages(device("Keyboard", usage: kHIDUsage_GD_Keyboard)))
    }

    @Test func excludedMiceAreLeftAlone() {
        let logitech = device("M720 Triathlon")
        let xsFlow = device("XS Flow S1", vid: 0x32C2, pid: 0x6621)
        let config = Config(profiles: [], excludedDevices: [logitech.model])
        #expect(!config.manages(logitech))
        #expect(config.manages(xsFlow))
        #expect(xsFlow.isXSFlow)
        #expect(!logitech.isXSFlow)
    }

    @Test func excludedDevicesRoundTripAndDefaultToEmpty() throws {
        let config = Config(profiles: [], excludedDevices: [DeviceID(vendorID: 1, productID: 2, name: "Mouse")])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
        // Configs saved by v0.1 have no excludedDevices key.
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"profiles":[]}"#.utf8))
        #expect(old.excludedDevices.isEmpty)
    }

    @Test func syntheticEventsHaveNoSender() throws {
        let event = try #require(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                         mouseCursorPosition: .zero, mouseButton: .center))
        #expect(PointingDeviceRegistry().device(for: event) == nil)
    }

    @Test func batteryNamesMatchLoosely() {
        let levels = ["XS Flow S1": 85]
        #expect(BluetoothBattery.level(in: levels, forDeviceNamed: "XS Flow S1") == 85)
        #expect(BluetoothBattery.level(in: levels, forDeviceNamed: "XS Flow") == 85)
        #expect(BluetoothBattery.level(in: levels, forDeviceNamed: "MX Master 3") == nil)
    }
}
