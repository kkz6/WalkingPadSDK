@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = SDKLogger.make(category: "Scanner")

public protocol WalkingPadScannerDelegate: AnyObject {
    func scannerDidDiscover(_ device: WalkingPadDevice)
    func scannerBluetoothStateChanged(_ state: CBManagerState)
}

public protocol WalkingPadScannerConnectionDelegate: AnyObject {
    func scannerDidConnect(_ peripheral: CBPeripheral)
    func scannerDidFailToConnect(_ peripheral: CBPeripheral, error: Error?)
    func scannerDidDisconnect(_ peripheral: CBPeripheral, error: Error?)
}

public final class WalkingPadScanner: NSObject, @unchecked Sendable {
    public weak var delegate: WalkingPadScannerDelegate?
    public weak var connectionDelegate: WalkingPadScannerConnectionDelegate?

    private var centralManager: CBCentralManager!
    private let queue = DispatchQueue(label: "walkingpad.ble.scanner")
    private var isScanning = false
    private var discoveredIDs = Set<UUID>()

    public var bluetoothState: CBManagerState { centralManager.state }

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: queue)
        logger.info("Scanner initialized, waiting for Bluetooth state...")
    }

    public func startScanning() {
        isScanning = true
        discoveredIDs.removeAll()
        guard centralManager.state == .poweredOn else {
            logger.notice("startScanning called but BLE not powered on (state=\(self.centralManager.state.rawValue)). Will auto-start when ready.")
            return
        }
        logger.info("Starting BLE scan (nil services, filtering by name)...")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func stopScanning() {
        logger.info("Stopping BLE scan")
        isScanning = false
        centralManager.stopScan()
    }

    public func connect(_ peripheral: CBPeripheral) {
        logger.info("Connecting to peripheral: \(peripheral.name ?? "unknown") (\(peripheral.identifier))")
        centralManager.connect(peripheral, options: nil)
    }

    public func disconnect(_ peripheral: CBPeripheral) {
        logger.info("Disconnecting from peripheral: \(peripheral.name ?? "unknown")")
        centralManager.cancelPeripheralConnection(peripheral)
    }
}

extension WalkingPadScanner: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("Bluetooth state changed: \(central.state.rawValue) (\(central.state.debugDescription))")
        delegate?.scannerBluetoothStateChanged(central.state)
        if central.state == .poweredOn && isScanning {
            logger.info("BLE powered on and scan was pending, starting scan now...")
            startScanning()
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let lower = name.lowercased()
        let isMatch = WalkingPadConstants.deviceNamePrefixes.contains { lower.hasPrefix($0) }

        guard isMatch else { return }
        guard !discoveredIDs.contains(peripheral.identifier) else { return }
        discoveredIDs.insert(peripheral.identifier)

        logger.notice("Found WalkingPad device: '\(name)' RSSI=\(RSSI) id=\(peripheral.identifier)")
        let device = WalkingPadDevice(peripheral: peripheral)
        delegate?.scannerDidDiscover(device)
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to peripheral: \(peripheral.name ?? "unknown")")
        connectionDelegate?.scannerDidConnect(peripheral)
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        logger.error("Failed to connect to peripheral: \(peripheral.name ?? "unknown"), error: \(error?.localizedDescription ?? "none")")
        connectionDelegate?.scannerDidFailToConnect(peripheral, error: error)
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        logger.info("Disconnected from peripheral: \(peripheral.name ?? "unknown"), error: \(error?.localizedDescription ?? "none")")
        connectionDelegate?.scannerDidDisconnect(peripheral, error: error)
    }
}

extension CBManagerState {
    var debugDescription: String {
        switch self {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}
