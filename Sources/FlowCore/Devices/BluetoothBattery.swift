import CoreBluetooth
import Foundation

/// Reads the standard GATT Battery Service (0x180F / 0x2A19) of the connected
/// XS Flow over Bluetooth LE. Requires the Bluetooth permission.
public final class BluetoothBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public var onLevel: ((Int?) -> Void)?
    public private(set) var level: Int?

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private let namePrefix: String

    public init(namePrefix: String = "XS Flow") {
        self.namePrefix = namePrefix
        super.init()
    }

    public func start() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) } else { findMouse() }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { findMouse() }
    }

    /// Call when the Bluetooth mouse (re)connects.
    public func findMouse() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        guard let mouse = connected.first(where: { $0.name?.hasPrefix(namePrefix) == true }) else {
            update(nil)
            return
        }
        peripheral = mouse
        mouse.delegate = self
        // Already connected at the system level; this just opens our GATT client.
        central.connect(mouse)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        update(nil)
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
        guard characteristic.uuid == Self.batteryLevel, let byte = characteristic.value?.first else { return }
        update(Int(byte))
    }

    private func update(_ value: Int?) {
        guard value != level else { return }
        level = value
        onLevel?(value)
    }
}
