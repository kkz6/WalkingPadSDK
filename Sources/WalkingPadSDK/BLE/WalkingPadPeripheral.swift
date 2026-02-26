@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = SDKLogger.make(category: "Peripheral")

public enum DeviceProtocol: Sendable {
    case legacy    // F7 protocol via FE00/FFF0/FFC0
    case ftms      // Bluetooth FTMS via 1826
}

public protocol WalkingPadPeripheralDelegate: AnyObject {
    func peripheralDidBecomeReady(protocol: DeviceProtocol)
    func peripheralDidReceiveData(_ data: [UInt8])
    func peripheralDidReceiveFTMSStatus(_ data: [UInt8])
    func peripheralDidFailWithError(_ error: Error)
}

public final class WalkingPadPeripheral: NSObject, @unchecked Sendable {
    public weak var delegate: WalkingPadPeripheralDelegate?

    let peripheral: CBPeripheral
    private(set) var notifyCharacteristic: CBCharacteristic?
    private(set) var writeCharacteristic: CBCharacteristic?
    private(set) var detectedProtocol: DeviceProtocol?

    // FTMS-specific characteristics (recorded during discovery, subscribed later)
    private var ftmsTreadmillData: CBCharacteristic?
    private var ftmsControlPoint: CBCharacteristic?
    private var ftmsMachineStatus: CBCharacteristic?
    private var ftmsFeature: CBCharacteristic?
    private var ftmsSupportedSpeedRange: CBCharacteristic?

    // Legacy matching state (recorded during discovery, subscribed later)
    private var legacyMatchedSetIndex: Int?
    private var legacyNotifyChar: CBCharacteristic?
    private var legacyWriteChar: CBCharacteristic?

    // KingSmith custom service write characteristic (for sleep/wake commands)
    private(set) var ksWriteChar: CBCharacteristic?

    // ALL discovered notify/write characteristics across ALL services
    private var allNotifyChars: [CBCharacteristic] = []
    private var allWriteChars: [CBCharacteristic] = []

    private var pendingServiceCount = 0
    private var isReady = false
    private var pendingSubscriptions = 0

    public init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self
        logger.info("Peripheral wrapper created for: \(peripheral.name ?? "unknown")")
    }

    public var name: String? { peripheral.name }
    public var identifier: UUID { peripheral.identifier }

    public func discoverServices() {
        logger.info("Discovering ALL services for \(self.peripheral.name ?? "unknown")...")
        peripheral.discoverServices(nil)
    }

    public func write(_ data: [UInt8]) {
        guard let char = writeCharacteristic else {
            logger.warning("write() called but writeCharacteristic is nil")
            return
        }
        let writeType: CBCharacteristicWriteType = detectedProtocol == .ftms ? .withResponse : .withoutResponse
        logger.debug("Writing \(data.count) bytes to \(char.uuid.uuidString) (type=\(writeType == .withResponse ? "withResponse" : "withoutResponse"))")
        peripheral.writeValue(Data(data), for: char, type: writeType)
    }

    public func writeKS(_ data: [UInt8]) {
        guard let char = ksWriteChar else {
            logger.warning("writeKS() called but KS write characteristic not available")
            return
        }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("KS Write: \(hex)")
        peripheral.writeValue(Data(data), for: char, type: .withoutResponse)
    }

    public func unsubscribeAll() {
        logger.info("Unsubscribing from all \(self.allNotifyChars.count) notify characteristics")
        for char in allNotifyChars {
            if char.isNotifying {
                peripheral.setNotifyValue(false, for: char)
            }
        }
    }
}

extension WalkingPadPeripheral: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            logger.error("Service discovery failed: \(error.localizedDescription)")
            delegate?.peripheralDidFailWithError(error)
            return
        }

        guard let services = peripheral.services else {
            logger.warning("No services found on peripheral")
            return
        }

        // Log all service UUIDs in full form for diagnostics
        logger.info("Discovered \(services.count) service(s):")
        for service in services {
            logger.info("  Service: \(service.uuid.uuidString) (full: \(service.uuid))")
        }

        pendingServiceCount = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        pendingServiceCount -= 1

        if let error {
            logger.error("Characteristic discovery failed for \(service.uuid): \(error.localizedDescription)")
            delegate?.peripheralDidFailWithError(error)
            checkAllServicesProcessed()
            return
        }

        guard let characteristics = service.characteristics else {
            logger.warning("No characteristics found for service \(service.uuid)")
            checkAllServicesProcessed()
            return
        }

        // Log all characteristics with their properties for diagnostics
        logger.info("Service \(service.uuid.uuidString) has \(characteristics.count) characteristic(s):")
        for char in characteristics {
            let props = describeProperties(char.properties)
            logger.info("  Char: \(char.uuid.uuidString) [\(props)]")
        }

        // Collect ALL notify and write characteristics across ALL services
        for char in characteristics {
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                allNotifyChars.append(char)
            }
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                allWriteChars.append(char)
            }
        }

        // Record FTMS characteristics (DO NOT subscribe yet)
        if service.uuid == FTMSConstants.serviceUUID {
            recordFTMS(characteristics: characteristics)
        }

        // Record KingSmith custom service write characteristic (for sleep command)
        if service.uuid == KingSmithConstants.serviceUUID {
            if let writeChar = characteristics.first(where: { $0.uuid == KingSmithConstants.writeUUID }) {
                ksWriteChar = writeChar
                logger.info("KS: Found write characteristic for sleep command")
            }
        }

        // Record legacy F7 characteristics (DO NOT subscribe yet)
        recordLegacy(service: service, characteristics: characteristics)

        checkAllServicesProcessed()
    }

    /// Record FTMS characteristics without subscribing - subscriptions happen after ALL services are discovered
    private func recordFTMS(characteristics: [CBCharacteristic]) {
        for char in characteristics {
            switch char.uuid {
            case FTMSConstants.treadmillDataUUID:
                ftmsTreadmillData = char
                logger.info("FTMS: Found Treadmill Data (2ACD) [\(self.describeProperties(char.properties))]")
            case FTMSConstants.controlPointUUID:
                ftmsControlPoint = char
                logger.info("FTMS: Found Control Point (2AD9) [\(self.describeProperties(char.properties))]")
            case FTMSConstants.machineStatusUUID:
                ftmsMachineStatus = char
                logger.info("FTMS: Found Machine Status (2ADA) [\(self.describeProperties(char.properties))]")
            case FTMSConstants.machineFeatureUUID:
                ftmsFeature = char
                logger.info("FTMS: Found Fitness Machine Feature (2ACC) [\(self.describeProperties(char.properties))]")
            case FTMSConstants.supportedSpeedRangeUUID:
                ftmsSupportedSpeedRange = char
                logger.info("FTMS: Found Supported Speed Range (2AD4) [\(self.describeProperties(char.properties))]")
            default:
                break
            }
        }
    }

    /// Record legacy characteristics without subscribing
    private func recordLegacy(service: CBService, characteristics: [CBCharacteristic]) {
        let charSets = WalkingPadConstants.knownCharSets
        for (index, charSet) in charSets.enumerated() {
            guard charSet.service == service.uuid else { continue }
            if let current = legacyMatchedSetIndex, current <= index { continue }

            let notify = characteristics.first { $0.uuid == charSet.notify }
            let write = characteristics.first { $0.uuid == charSet.write }
            guard let notifyChar = notify, let writeChar = write else { continue }

            legacyMatchedSetIndex = index
            legacyNotifyChar = notifyChar
            legacyWriteChar = writeChar
            logger.info("Matched legacy service \(service.uuid.uuidString): notify=\(notifyChar.uuid.uuidString), write=\(writeChar.uuid.uuidString) (priority \(index))")
        }
    }

    /// Called after each service's characteristics are discovered
    private func checkAllServicesProcessed() {
        guard pendingServiceCount <= 0 && !isReady else { return }
        logger.info("All \(self.peripheral.services?.count ?? 0) services fully discovered.")
        logger.info("Total notify characteristics: \(self.allNotifyChars.count), write characteristics: \(self.allWriteChars.count)")

        // Determine protocol: prefer FTMS > Legacy
        if ftmsControlPoint != nil && ftmsTreadmillData != nil {
            detectedProtocol = .ftms
            writeCharacteristic = ftmsControlPoint
            notifyCharacteristic = ftmsTreadmillData
            logger.info("Primary protocol: FTMS (control=2AD9, data=2ACD)")
        } else if let notifyChar = legacyNotifyChar, let writeChar = legacyWriteChar {
            detectedProtocol = .legacy
            notifyCharacteristic = notifyChar
            writeCharacteristic = writeChar
            logger.info("Primary protocol: Legacy F7 (notify=\(notifyChar.uuid.uuidString), write=\(writeChar.uuid.uuidString))")
        } else {
            logger.error("No known protocol detected!")
        }

        // Read FTMS feature characteristics for diagnostics
        if let feature = ftmsFeature {
            logger.info("Reading FTMS Feature (2ACC)...")
            peripheral.readValue(for: feature)
        }
        if let speedRange = ftmsSupportedSpeedRange {
            logger.info("Reading FTMS Supported Speed Range (2AD4)...")
            peripheral.readValue(for: speedRange)
        }

        // Subscribe to ALL notify/indicate characteristics across ALL services
        subscribeToAll()
    }

    /// Subscribe to ALL notify/indicate characteristics from every service (promiscuous mode)
    private func subscribeToAll() {
        pendingSubscriptions = allNotifyChars.count
        logger.info("Subscribing to ALL \(self.pendingSubscriptions) notify/indicate characteristics...")

        if pendingSubscriptions == 0 {
            declareReady()
            return
        }

        for char in allNotifyChars {
            let mode = char.properties.contains(.indicate) ? "indicate" : "notify"
            let svcUUID = char.service?.uuid.uuidString ?? "?"
            logger.info("  Subscribing: \(char.uuid.uuidString) (\(mode)) on service \(svcUUID)")
            peripheral.setNotifyValue(true, for: char)
        }
    }

    /// Final step: declare peripheral ready and inform delegate
    private func declareReady() {
        guard !isReady, let proto = detectedProtocol else { return }
        isReady = true
        logger.info("Peripheral READY — protocol: \(String(describing: proto))")
        delegate?.peripheralDidBecomeReady(protocol: proto)
    }

    private func describeProperties(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read) { parts.append("read") }
        if props.contains(.write) { parts.append("write") }
        if props.contains(.writeWithoutResponse) { parts.append("writeNoResp") }
        if props.contains(.notify) { parts.append("notify") }
        if props.contains(.indicate) { parts.append("indicate") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Characteristic value updates

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            logger.error("Characteristic \(characteristic.uuid.uuidString) update error: \(error.localizedDescription)")
            delegate?.peripheralDidFailWithError(error)
            return
        }

        guard let data = characteristic.value else {
            logger.warning("Characteristic \(characteristic.uuid.uuidString) update with nil value")
            return
        }

        let bytes = Array(data)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let svcUUID = characteristic.service?.uuid.uuidString ?? "?"

        // Log ALL incoming data with service context for diagnostics
        logger.info("BLE data from \(characteristic.uuid.uuidString) (svc: \(svcUUID)): \(hex) (\(bytes.count) bytes)")

        if characteristic.uuid == FTMSConstants.treadmillDataUUID {
            delegate?.peripheralDidReceiveData(bytes)
        } else if characteristic.uuid == FTMSConstants.machineStatusUUID {
            delegate?.peripheralDidReceiveFTMSStatus(bytes)
        } else if characteristic.uuid == FTMSConstants.controlPointUUID {
            logger.info("FTMS Control Point response: \(hex)")
        } else if characteristic.uuid == FTMSConstants.machineFeatureUUID {
            logger.info("FTMS Feature (2ACC): \(hex)")
        } else if characteristic.uuid == FTMSConstants.supportedSpeedRangeUUID {
            logger.info("FTMS Supported Speed Range (2AD4): \(hex)")
        } else if detectedProtocol != .ftms {
            // Data from legacy F7 or other unknown service — only forward for legacy protocol
            logger.info("Other data from \(characteristic.uuid.uuidString) on service \(svcUUID)")
            delegate?.peripheralDidReceiveData(bytes)
        } else {
            logger.debug("Ignoring non-FTMS data from \(characteristic.uuid.uuidString) on service \(svcUUID)")
        }
    }

    // MARK: - Write confirmation

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            logger.error("Write to \(characteristic.uuid.uuidString) failed: \(error.localizedDescription)")
        } else {
            logger.debug("Write to \(characteristic.uuid.uuidString) succeeded")
        }
    }

    // MARK: - Subscription confirmation

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            logger.error("Subscribe to \(characteristic.uuid.uuidString) FAILED: \(error.localizedDescription)")
        } else {
            let mode = characteristic.properties.contains(.indicate) ? "indication" : "notification"
            logger.info("Subscribe to \(characteristic.uuid.uuidString) \(characteristic.isNotifying ? "OK" : "STOPPED") (mode: \(mode))")
        }

        // Track subscription completions and declare ready when all are done
        if pendingSubscriptions > 0 {
            pendingSubscriptions -= 1
            if pendingSubscriptions == 0 {
                logger.info("All subscriptions confirmed. Declaring peripheral ready.")
                declareReady()
            }
        }
    }
}
