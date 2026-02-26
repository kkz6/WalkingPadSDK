@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = SDKLogger.make(category: "Connection")

public enum ConnectionState: Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case ready

    public var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning..."
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .ready: "Ready"
        }
    }

    public var isConnected: Bool {
        self == .connected || self == .ready
    }
}

public protocol WalkingPadConnectionDelegate: AnyObject {
    func connectionStateChanged(_ state: ConnectionState)
    func connectionDidBecomeReady(protocol: DeviceProtocol)
    func connectionDidReceiveData(_ data: [UInt8])
    func connectionDidReceiveFTMSStatus(_ data: [UInt8])
    func connectionDidFailWithError(_ error: Error)
}

public final class WalkingPadConnection: NSObject, @unchecked Sendable {
    public weak var delegate: WalkingPadConnectionDelegate?

    private let scanner: WalkingPadScanner
    private var peripheralWrapper: WalkingPadPeripheral?
    private var connectionTimeoutTask: Task<Void, Never>?
    private(set) public var activeProtocol: DeviceProtocol?
    private(set) public var state: ConnectionState = .disconnected {
        didSet {
            logger.info("Connection state: \(String(describing: oldValue)) -> \(String(describing: self.state))")
            delegate?.connectionStateChanged(state)
        }
    }

    public var hasKingSmithService: Bool {
        peripheralWrapper?.ksWriteChar != nil
    }

    public init(scanner: WalkingPadScanner) {
        self.scanner = scanner
        super.init()
        scanner.connectionDelegate = self
        logger.info("Connection initialized with scanner")
    }

    public func connect(to device: WalkingPadDevice) {
        logger.info("Connecting to device: \(device.name)")
        connectionTimeoutTask?.cancel()
        state = .connecting
        activeProtocol = nil
        let wrapper = WalkingPadPeripheral(peripheral: device.peripheral)
        wrapper.delegate = self
        peripheralWrapper = wrapper
        scanner.connect(device.peripheral)

        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            guard let self, self.state == .connecting || self.state == .connected else { return }
            logger.warning("Connection timeout — stuck at \(String(describing: self.state)) after 15s, retrying...")
            self.retryConnection(device)
        }
    }

    private func retryConnection(_ device: WalkingPadDevice) {
        if let wrapper = peripheralWrapper {
            scanner.disconnect(wrapper.peripheral)
        }
        peripheralWrapper = nil
        activeProtocol = nil

        let wrapper = WalkingPadPeripheral(peripheral: device.peripheral)
        wrapper.delegate = self
        peripheralWrapper = wrapper
        state = .connecting
        scanner.connect(device.peripheral)

        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            guard let self, self.state == .connecting || self.state == .connected else { return }
            logger.error("Connection timeout on retry — giving up")
            self.peripheralWrapper = nil
            self.activeProtocol = nil
            self.state = .disconnected
        }
    }

    public func disconnect() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        guard let wrapper = peripheralWrapper else {
            logger.warning("disconnect() called but no peripheral wrapper")
            return
        }
        logger.info("Disconnecting from device")
        scanner.disconnect(wrapper.peripheral)
        peripheralWrapper = nil
        activeProtocol = nil
        state = .disconnected
    }

    public func write(_ data: [UInt8]) {
        guard peripheralWrapper != nil else {
            logger.warning("write() called but no peripheral wrapper")
            return
        }
        peripheralWrapper?.write(data)
    }

    public func writeKS(_ data: [UInt8]) {
        peripheralWrapper?.writeKS(data)
    }

    public func unsubscribeAll() {
        peripheralWrapper?.unsubscribeAll()
    }
}

// MARK: - WalkingPadScannerConnectionDelegate

extension WalkingPadConnection: WalkingPadScannerConnectionDelegate {
    public func scannerDidConnect(_ peripheral: CBPeripheral) {
        guard peripheral.identifier == peripheralWrapper?.peripheral.identifier else {
            logger.debug("scannerDidConnect for unknown peripheral, ignoring")
            return
        }
        logger.info("Peripheral connected, discovering services...")
        state = .connected
        peripheralWrapper?.discoverServices()
    }

    public func scannerDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == peripheralWrapper?.peripheral.identifier else { return }
        logger.error("Peripheral failed to connect: \(error?.localizedDescription ?? "unknown")")
        peripheralWrapper = nil
        state = .disconnected
        if let error {
            delegate?.connectionDidFailWithError(error)
        }
    }

    public func scannerDidDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == peripheralWrapper?.peripheral.identifier else { return }
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        logger.info("Peripheral disconnected: \(error?.localizedDescription ?? "clean")")
        peripheralWrapper = nil
        activeProtocol = nil
        state = .disconnected
    }
}

// MARK: - WalkingPadPeripheralDelegate

extension WalkingPadConnection: WalkingPadPeripheralDelegate {
    public func peripheralDidBecomeReady(protocol deviceProtocol: DeviceProtocol) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        activeProtocol = deviceProtocol
        logger.info("Connection READY, protocol: \(String(describing: deviceProtocol))")
        state = .ready
        delegate?.connectionDidBecomeReady(protocol: deviceProtocol)
    }

    public func peripheralDidReceiveData(_ data: [UInt8]) {
        logger.debug("Received \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        delegate?.connectionDidReceiveData(data)
    }

    public func peripheralDidReceiveFTMSStatus(_ data: [UInt8]) {
        logger.debug("FTMS Status: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        delegate?.connectionDidReceiveFTMSStatus(data)
    }

    public func peripheralDidFailWithError(_ error: Error) {
        logger.error("Peripheral error: \(error.localizedDescription)")
        delegate?.connectionDidFailWithError(error)
    }
}
