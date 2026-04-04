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
    public var vendorSteps: Int = 0

    public var onStatusUpdate: ((TreadmillStatus) -> Void)?
    public var onConnectionStateChange: ((ConnectionState) -> Void)?

    /// Optional calorie calculator — set a UserProfile to enable ACSM-based calorie tracking
    public var calorieCalculator: CalorieCalculator?

    /// Accumulated ACSM-calculated calories for the current session
    public private(set) var calculatedCalories: Double = 0.0

    private let scanner: WalkingPadScanner
    private let connection: WalkingPadConnection
    private var pollingTask: Task<Void, Never>?
    private var lastCommandTime: Date?
    private var ftmsControlRequested = false
    private var targetSpeedHundredths: UInt16 = 0
    private var pendingStartSpeed: UInt16?
    private var lastCalorieTimestamp: Date?

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
        pendingStartSpeed = nil
        calculatedCalories = 0
        lastCalorieTimestamp = nil
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
        pendingStartSpeed = nil
        vendorSteps = 0
        lastCalorieTimestamp = nil
    }

    /// Reset accumulated calculated calories for a new session
    public func resetCalculatedCalories() {
        calculatedCalories = 0
        lastCalorieTimestamp = nil
    }

    // MARK: - Controls

    public func startBelt() async {
        logger.info("Controller: startBelt")

        switch activeProtocol {
        case .ftms:
            ftmsControlRequested = false
            pendingStartSpeed = targetSpeedHundredths > 0 ? targetSpeedHundredths : 100 // default 1.0 km/h
            await sendFTMSControlAndStart()
        default:
            await sendCommand(WalkingPadCommand.startBelt())
        }
    }

    public func stopBelt() async {
        logger.info("Controller: stopBelt")
        pendingStartSpeed = nil

        switch activeProtocol {
        case .ftms:
            await sendCommand(FTMSCommand.stop())
        default:
            await sendCommand(WalkingPadCommand.stopBelt())
        }
    }

    public func pauseBelt() async {
        logger.info("Controller: pauseBelt")
        pendingStartSpeed = nil

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
        guard connection.hasKingSmithService else {
            logger.warning("Controller: No KS service — cannot sleep")
            return
        }
        connection.writeKS(KSCommand.initDevice())
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            connection.writeKS(KSCommand.sleep())
        }
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
            logger.info("Controller: FTMS — data via notifications, polling vendor steps only")
            // For FTMS, only poll vendor characteristics for step count
            if connection.hasVendorWriteChars {
                pollingTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self else { return }
                        self.queryVendorSteps()
                        try? await Task.sleep(for: .seconds(interval))
                    }
                }
            }
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
        // FTMS mode: skip legacy handshake — KS service is only needed for sleep/wake
        if activeProtocol == .ftms {
            logger.info("Controller: FTMS mode — skipping KS handshake (sleep/wake still available)")
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

    // MARK: - Private: Vendor Step Queries

    private func queryVendorSteps() {
        connection.writeVendor(FTMSCommand.vendorStepQuery())
    }

    // MARK: - Private: Calorie Accumulation

    private func accumulateCalories(speedKmh: Double) {
        guard let calculator = calorieCalculator, speedKmh > 0.5 else {
            lastCalorieTimestamp = nil
            return
        }

        let now = Date()
        if let lastTs = lastCalorieTimestamp {
            let dt = now.timeIntervalSince(lastTs)
            if dt > 0 && dt < 5 {
                calculatedCalories += calculator.calories(atSpeedKmh: speedKmh, forSeconds: dt)
            }
        }
        lastCalorieTimestamp = now
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
        // Auto-start vendor step polling for FTMS devices
        if deviceProtocol == .ftms {
            startPolling()
        }
    }

    public func connectionDidReceiveData(_ data: [UInt8]) {
        if activeProtocol == .ftms {
            if let status = FTMSParser.parseTreadmillData(data) {
                logger.debug("Controller: FTMS — speed=\(status.speed), belt=\(String(describing: status.beltState))")

                // Smart start: send pending speed once belt starts moving
                if status.beltState == .running, let pending = pendingStartSpeed {
                    pendingStartSpeed = nil
                    logger.info("Controller: Belt running, sending pending speed \(pending)")
                    connection.write(FTMSCommand.requestControl())
                    Task {
                        try? await Task.sleep(for: .seconds(0.3))
                        self.connection.write(FTMSCommand.setTargetSpeed(pending))
                    }
                }

                // Merge vendor steps into status if available
                var enrichedStatus = status
                if vendorSteps > 0 {
                    enrichedStatus = TreadmillStatus(
                        raw: status.raw,
                        beltState: status.beltState,
                        speed: status.speed,
                        mode: status.mode,
                        time: status.time,
                        distance: status.distance,
                        calories: status.calories,
                        appSpeed: status.appSpeed,
                        controllerButton: status.controllerButton,
                        timestamp: status.timestamp,
                        steps: vendorSteps,
                        avgSpeed: status.avgSpeed
                    )
                }

                // Accumulate ACSM calories
                accumulateCalories(speedKmh: enrichedStatus.speedKmh)

                currentStatus = enrichedStatus
                onStatusUpdate?(enrichedStatus)
            }
            return
        }

        // Legacy F7 parser
        if let status = WalkingPadParser.parseStatus(data) {
            logger.debug("Controller: F7 — speed=\(status.speed), belt=\(String(describing: status.beltState))")
            accumulateCalories(speedKmh: status.speedKmh)
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
            case .stoppedByUser, .pausedByUser, .controlPermissionLost:
                ftmsControlRequested = false
                pendingStartSpeed = nil
            default:
                break
            }
        }
    }

    public func connectionDidReceiveVendorData(_ data: [UInt8]) {
        if let steps = FTMSParser.parseVendorStepCount(data) {
            logger.debug("Controller: vendor steps = \(steps)")
            vendorSteps = steps
        }
    }

    public func connectionDidFailWithError(_ error: Error) {
        logger.error("Controller: connection error — \(error.localizedDescription)")
    }
}
