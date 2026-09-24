import CoreBluetooth
import Foundation

/// Reads the standard GATT Battery Service (0x180F / 0x2A19) of connected
/// Bluetooth LE mice. Requires the Bluetooth permission.
public final class BluetoothBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public var onChange: (() -> Void)?
    /// Battery percentage by peripheral name.
    public private(set) var levels: [String: Int] = [:]

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// Only peripherals with one of these names are read, so we don't open
    /// connections to keyboards or headphones.
    private var names: Set<String> = []

    public override init() {
        super.init()
    }

    /// Starts (or refreshes) reading the battery of the Bluetooth mice with these names.
    public func track(names: [String]) {
        self.names = Set(names)
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) } else { findDevices() }
    }

    /// The battery level for a device, matching names loosely because the HID
    /// product name and the Bluetooth name can differ in their suffix.
    public func level(forDeviceNamed name: String) -> Int? {
        Self.level(in: levels, forDeviceNamed: name)
    }

    public static func level(in levels: [String: Int], forDeviceNamed name: String) -> Int? {
        levels[name] ?? levels.first { name.hasPrefix($0.key) || $0.key.hasPrefix(name) }?.value
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { findDevices() }
    }

    private func matches(_ peripheral: CBPeripheral) -> Bool {
        guard let name = peripheral.name else { return false }
        return names.contains { name.hasPrefix($0) || $0.hasPrefix(name) }
    }

    private func findDevices() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService]).filter(matches)
        let ids = Set(connected.map(\.identifier))
        for (id, peripheral) in peripherals where !ids.contains(id) {
            peripherals[id] = nil
            if let name = peripheral.name { levels[name] = nil }
        }
        for peripheral in connected where peripherals[peripheral.identifier] == nil {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            // Already connected at the system level; this just opens our GATT client.
            central.connect(peripheral)
        }
        onChange?()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peripherals[peripheral.identifier] = nil
        if let name = peripheral.name { levels[name] = nil }
        onChange?()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else { return }
        peripheral.readValue(for: characteristic)
        if characteristic.properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.batteryLevel, let byte = characteristic.value?.first,
              let name = peripheral.name, levels[name] != Int(byte) else { return }
        levels[name] = Int(byte)
        onChange?()
    }
}
