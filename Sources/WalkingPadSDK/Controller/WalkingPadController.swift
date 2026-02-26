@preconcurrency import CoreBluetooth
import Foundation
import Observation
import os

private let logger = SDKLogger.make(category: "Controller")

@Observable
public final class WalkingPadController: @unchecked Sendable {
    public var connectionState: ConnectionState = .disconnected
    public var discoveredDevices: [WalkingPadDevice] = []
    public var currentStatus: TreadmillStatus?
    public var lastRecord: TreadmillLastRecord?
    public var deviceName: String?
    public var activeProtocol: DeviceProtocol?

    public var onStatusUpdate: ((TreadmillStatus) -> Void)?
    public var onConnectionStateChange: ((ConnectionState) -> Void)?

    private let scanner: WalkingPadScanner
    private let connection: WalkingPadConnection
    private var pollingTask: Task<Void, Never>?
    private var lastCommandTime: Date?
    private var ftmsControlRequested = false
    private var targetSpeedHundredths: UInt16 = 0

    public init() {
        scanner = WalkingPadScanner()
        connection = WalkingPadConnection(scanner: scanner)
        scanner.delegate = self
        connection.delegate = self
        logger.info("WalkingPadController initialized")
    }

    // MARK: - Scanning

    public func startScanning() {
        logger.info("Controller: startScanning")
        discoveredDevices = []
        connectionState = .scanning
        scanner.startScanning()
    }

    public func stopScanning() {
        logger.info("Controller: stopScanning")
        scanner.stopScanning()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    // MARK: - Connection

    public func connect(to device: WalkingPadDevice) {
        logger.info("Controller: connecting to \(device.name)")
        scanner.stopScanning()
        deviceName = device.name
        ftmsControlRequested = false
        connection.connect(to: device)
    }

    public func disconnect() {
        logger.info("Controller: disconnecting")
        stopPolling()
        connection.unsubscribeAll()
        connection.disconnect()
        deviceName = nil
        currentStatus = nil
        activeProtocol = nil
        ftmsControlRequested = false
    }

    // MARK: - Controls

    public func startBelt() async {
        logger.info("Controller: startBelt")

        switch activeProtocol {
        case .ftms:
            await sendFTMSControlAndStart()
        default:
            await sendCommand(WalkingPadCommand.startBelt())
        }
    }

    public func stopBelt() async {
        logger.info("Controller: stopBelt")

        switch activeProtocol {
        case .ftms:
            await sendCommand(FTMSCommand.stop())
        default:
            await sendCommand(WalkingPadCommand.stopBelt())
        }
    }

    public func pauseBelt() async {
        logger.info("Controller: pauseBelt")

        switch activeProtocol {
        case .ftms:
            await sendCommand(FTMSCommand.pause())
        default:
            await sendCommand(WalkingPadCommand.changeSpeed(0))
        }
    }

    /// Speed in tenths of km/h (e.g. 30 = 3.0 km/h)
    public func setSpeed(_ kmhTenths: Int) async {
        let clamped = max(0, min(60, kmhTenths))
        logger.info("Controller: setSpeed \(clamped) tenths")
        targetSpeedHundredths = UInt16(clamped * 10)
        switch activeProtocol {
        case .ftms:
            await sendFTMSControlAndStart()
            await sendCommand(FTMSCommand.setTargetSpeed(targetSpeedHundredths))
        default:
            await sendCommand(WalkingPadCommand.changeSpeed(clamped))
        }
    }

    public func sleepDevice() {
        logger.info("Controller: sleepDevice")
        connection.writeKS(KSCommand.sleep())
    }

    public func wakeDevice() {
        logger.info("Controller: wakeDevice")
        connection.writeKS(KSCommand.wake())
    }

    public func switchMode(_ mode: TreadmillMode) async {
        logger.info("Controller: switchMode \(String(describing: mode))")
        if activeProtocol == .legacy {
            await sendCommand(WalkingPadCommand.switchMode(mode))
        }
    }

    // MARK: - Status Polling

    public func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        if activeProtocol == .ftms {
            logger.info("Controller: FTMS — data via notifications, no polling needed")
            return
        }
        logger.info("Controller: starting polling every \(interval)s")
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.askStats()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func askStats() async {
        guard activeProtocol == .legacy else { return }
        await sendCommand(WalkingPadCommand.askStats())
    }

    public func askHistory() async {
        guard activeProtocol == .legacy else { return }
        await sendCommand(WalkingPadCommand.askHistory())
    }

    // MARK: - Preferences (legacy only)

    public func setMaxSpeed(_ kmhTenths: Int) async {
        guard activeProtocol == .legacy else { return }
        await sendCommand(WalkingPadCommand.setMaxSpeed(kmhTenths))
    }

    public func setStartSpeed(_ kmhTenths: Int) async {
        guard activeProtocol == .legacy else { return }
        await sendCommand(WalkingPadCommand.setStartSpeed(kmhTenths))
    }

    public func setSensitivity(_ level: SensitivityLevel) async {
        guard activeProtocol == .legacy else { return }
        await sendCommand(WalkingPadCommand.setSensitivity(level))
    }

    public func setChildLock(_ enabled: Bool) async {
        guard activeProtocol == .legacy else { return }
        await sendCommand(WalkingPadCommand.setChildLock(enabled))
    }

    public func setUnitsToMiles(_ enabled: Bool) async {
        guard activeProtocol == .legacy else { return }
        await sendCommand(WalkingPadCommand.setUnitsMiles(enabled))
    }

    // MARK: - Private: KS Handshake

    private func sendKSHandshake() {
        guard connection.hasKingSmithService else {
            logger.info("Controller: No KingSmith service found, skipping handshake")
            return
        }
        logger.info("Controller: Sending KS init handshake")
        Task {
            connection.writeKS(KSCommand.initDevice())
            try? await Task.sleep(for: .seconds(0.3))
            connection.writeKS(KSCommand.initTimestamp())
            try? await Task.sleep(for: .seconds(0.3))
            connection.writeKS(KSCommand.queryStatus())
            try? await Task.sleep(for: .seconds(0.3))
            connection.writeKS(KSCommand.queryConfig())
            logger.info("Controller: KS handshake complete")
        }
    }

    // MARK: - Private: Command Dispatch

    private func sendFTMSControlAndStart() async {
        guard !ftmsControlRequested else {
            logger.debug("Controller: FTMS control already requested, skipping")
            return
        }
        logger.info("Controller: Sending FTMS Request Control + Start/Resume")
        connection.write(FTMSCommand.requestControl())
        connection.write(FTMSCommand.startOrResume())
        ftmsControlRequested = true
    }

    private func sendCommand(_ cmd: [UInt8]) async {
        if activeProtocol == .legacy {
            await enforceCommandSpacing()
        }
        let hex = cmd.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("Sending command: \(hex)")
        connection.write(cmd)
        lastCommandTime = .now
    }

    private func enforceCommandSpacing() async {
        guard let lastTime = lastCommandTime else { return }
        let elapsed = Date.now.timeIntervalSince(lastTime)
        let remaining = WalkingPadConstants.minCommandSpacing - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
    }

}

// MARK: - WalkingPadScannerDelegate

extension WalkingPadController: WalkingPadScannerDelegate {
    public func scannerDidDiscover(_ device: WalkingPadDevice) {
        logger.info("Controller: discovered device '\(device.name)' (\(device.id))")
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)
        }
    }

    public func scannerBluetoothStateChanged(_ state: CBManagerState) {
        logger.info("Controller: bluetooth state = \(state.rawValue)")
        if state == .poweredOn && connectionState == .scanning {
            scanner.startScanning()
        }
    }
}

// MARK: - WalkingPadConnectionDelegate

extension WalkingPadController: WalkingPadConnectionDelegate {
    public func connectionStateChanged(_ state: ConnectionState) {
        logger.info("Controller: connection state -> \(String(describing: state))")
        connectionState = state
        onConnectionStateChange?(state)
    }

    public func connectionDidBecomeReady(protocol deviceProtocol: DeviceProtocol) {
        activeProtocol = deviceProtocol
        logger.info("Controller: device protocol = \(String(describing: deviceProtocol))")
        sendKSHandshake()
    }

    public func connectionDidReceiveData(_ data: [UInt8]) {
        if activeProtocol == .ftms {
            if let status = FTMSParser.parseTreadmillData(data) {
                logger.debug("Controller: FTMS — speed=\(status.speed), belt=\(String(describing: status.beltState))")
                currentStatus = status
                onStatusUpdate?(status)
            }
            return
        }

        // Legacy F7 parser
        if let status = WalkingPadParser.parseStatus(data) {
            logger.debug("Controller: F7 — speed=\(status.speed), belt=\(String(describing: status.beltState))")
            currentStatus = status
            onStatusUpdate?(status)
        } else if let record = WalkingPadParser.parseLastRecord(data) {
            logger.debug("Controller: parsed last record")
            lastRecord = record
        }
    }

    public func connectionDidReceiveFTMSStatus(_ data: [UInt8]) {
        if let event = FTMSParser.parseMachineStatus(data) {
            logger.info("Controller: FTMS event = \(String(describing: event))")
            switch event {
            case .stoppedByUser, .controlPermissionLost:
                ftmsControlRequested = false
            default:
                break
            }
        }
    }

    public func connectionDidFailWithError(_ error: Error) {
        logger.error("Controller: connection error — \(error.localizedDescription)")
    }
}
