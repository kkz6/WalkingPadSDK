@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = SDKLogger.make(category: "FTMS")

// MARK: - FTMS UUIDs

public enum FTMSConstants {
    nonisolated(unsafe) public static let serviceUUID = CBUUID(string: "1826")
    nonisolated(unsafe) public static let treadmillDataUUID = CBUUID(string: "2ACD")
    nonisolated(unsafe) public static let controlPointUUID = CBUUID(string: "2AD9")
    nonisolated(unsafe) public static let machineStatusUUID = CBUUID(string: "2ADA")
    nonisolated(unsafe) public static let machineFeatureUUID = CBUUID(string: "2ACC")
    nonisolated(unsafe) public static let supportedSpeedRangeUUID = CBUUID(string: "2AD4")
    nonisolated(unsafe) public static let trainingStatusUUID = CBUUID(string: "2AD3")

    // Vendor services for KingSmith step count (optional)
    nonisolated(unsafe) public static let vendorService1UUID = CBUUID(string: "FFC0")
    nonisolated(unsafe) public static let vendorNotify1UUID = CBUUID(string: "FFC1")
    nonisolated(unsafe) public static let vendorWrite1UUID = CBUUID(string: "FFC2")
    nonisolated(unsafe) public static let vendorService2UUID = CBUUID(string: "FFF0")
    nonisolated(unsafe) public static let vendorNotify2UUID = CBUUID(string: "FFF1")
    nonisolated(unsafe) public static let vendorWrite2UUID = CBUUID(string: "FFF2")
}

// MARK: - FTMS Control Point Commands

public enum FTMSCommand {
    public static func requestControl() -> [UInt8] {
        [0x00]
    }

    public static func reset() -> [UInt8] {
        [0x01]
    }

    /// Speed in 0.01 km/h units (e.g. 300 = 3.0 km/h)
    public static func setTargetSpeed(_ speedHundredths: UInt16) -> [UInt8] {
        [0x02, UInt8(speedHundredths & 0xFF), UInt8(speedHundredths >> 8)]
    }

    public static func startOrResume() -> [UInt8] {
        [0x07]
    }

    public static func stop() -> [UInt8] {
        [0x08, 0x01]
    }

    public static func pause() -> [UInt8] {
        [0x08, 0x02]
    }

    /// Vendor step count query command (for FFC2/FFF2 characteristics)
    public static func vendorStepQuery() -> [UInt8] {
        let sub: UInt8 = 0x01
        let checksum = UInt8((UInt16(0xA2) ^ UInt16(sub)) & 0xFF)
        return [0xF7, 0xA2, sub, checksum, 0xFD]
    }
}

// MARK: - FTMS Treadmill Data Parser

public enum FTMSParser {
    /// Parse FTMS Treadmill Data (characteristic 0x2ACD) into TreadmillStatus
    public static func parseTreadmillData(_ data: [UInt8]) -> TreadmillStatus? {
        guard data.count >= 4 else {
            logger.warning("Treadmill data too short: \(data.count) bytes")
            return nil
        }

        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)

        // FTMS spec: bits 14-15 are reserved and must be 0
        if flags & 0xC000 != 0 {
            logger.debug("FTMS: Rejecting data with reserved flag bits set (flags=0x\(String(flags, radix: 16)))")
            return nil
        }

        var offset = 2

        // Bit 0: More Data — 0 means instantaneous speed IS present
        var speed = 0
        if flags & 0x0001 == 0 {
            guard offset + 2 <= data.count else { return nil }
            let rawSpeed = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            speed = Int(rawSpeed) / 10 // Convert from 0.01 km/h to 0.1 km/h (tenths)
            offset += 2
        }

        // Bit 1: Average Speed (uint16, 0.01 km/h units)
        var avgSpeed: Int?
        if flags & 0x0002 != 0 {
            if offset + 2 <= data.count {
                let rawAvg = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                avgSpeed = Int(rawAvg) / 10 // Convert to tenths
            }
            offset += 2
        }

        // Bit 2: Total Distance (uint24, meters)
        var distance = 0
        if flags & 0x0004 != 0 {
            guard offset + 3 <= data.count else { return nil }
            distance = Int(data[offset]) | (Int(data[offset + 1]) << 8) | (Int(data[offset + 2]) << 16)
            offset += 3
        }

        // Bit 3: Inclination + Ramp Angle
        if flags & 0x0008 != 0 {
            offset += 4 // int16 + int16
        }

        // Bit 4: Elevation Gain (positive + negative)
        if flags & 0x0010 != 0 {
            offset += 4 // uint16 + uint16
        }

        // Bit 5: Instantaneous Pace
        if flags & 0x0020 != 0 {
            offset += 1
        }

        // Bit 6: Average Pace
        if flags & 0x0040 != 0 {
            offset += 1
        }

        // Bit 7: Expended Energy (total + per hour + per minute)
        var calories = 0
        if flags & 0x0080 != 0 {
            guard offset + 5 <= data.count else { return nil }
            calories = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            offset += 5 // uint16 + uint16 + uint8
        }

        // Bit 8: Heart Rate
        if flags & 0x0100 != 0 {
            offset += 1
        }

        // Bit 9: Metabolic Equivalent
        if flags & 0x0200 != 0 {
            offset += 1
        }

        // Bit 10: Elapsed Time (uint16, seconds)
        var elapsedTime = 0
        if flags & 0x0400 != 0 {
            guard offset + 2 <= data.count else { return nil }
            elapsedTime = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            offset += 2
        }

        // Sanity check: walking pad speeds above 120 tenths (12.0 km/h) are clearly invalid
        if speed > 120 {
            logger.warning("FTMS: Rejecting implausible speed \(speed) tenths (\(Double(speed) / 10.0) km/h)")
            return nil
        }

        let beltState: BeltState = speed > 0 ? .running : .idle

        logger.debug("FTMS parsed: speed=\(speed) avg=\(avgSpeed ?? 0) dist=\(distance)m time=\(elapsedTime)s cal=\(calories)")

        return TreadmillStatus(
            raw: data,
            beltState: beltState,
            speed: speed,
            mode: .manual,
            time: elapsedTime,
            distance: distance,
            calories: calories,
            appSpeed: speed,
            controllerButton: 0,
            avgSpeed: avgSpeed
        )
    }

    /// Parse vendor step count data from FFC1/FFF1 notifications
    public static func parseVendorStepCount(_ data: [UInt8]) -> Int? {
        guard data.count >= 18, data[0] == 0xF7, data[1] == 0xA2 else { return nil }
        let s = Int(UInt16(data[7]) | (UInt16(data[8]) << 8))
            | (Int(UInt16(data[9]) | (UInt16(data[10]) << 8)) << 16)
        guard s > 0, s < 1_000_000 else { return nil }
        return s
    }

    /// Parse FTMS Machine Status (characteristic 0x2ADA)
    public static func parseMachineStatus(_ data: [UInt8]) -> FTMSMachineEvent? {
        guard !data.isEmpty else { return nil }
        let opCode = data[0]

        switch opCode {
        case 0x02:
            let reason = data.count > 1 ? data[1] : 0
            logger.info("FTMS: Machine stopped/paused (reason=\(reason))")
            return reason == 0x01 ? .stoppedByUser : .pausedByUser
        case 0x04:
            logger.info("FTMS: Machine started/resumed")
            return .startedByUser
        case 0x05:
            if data.count >= 3 {
                let newSpeed = UInt16(data[1]) | (UInt16(data[2]) << 8)
                logger.info("FTMS: Target speed changed to \(newSpeed)")
                return .targetSpeedChanged(Int(newSpeed))
            }
            return nil
        case 0x08:
            logger.info("FTMS: Control permission lost")
            return .controlPermissionLost
        default:
            logger.debug("FTMS: Unknown machine status op=\(opCode)")
            return nil
        }
    }
}

// MARK: - FTMS Machine Events

public enum FTMSMachineEvent: Sendable {
    case stoppedByUser
    case pausedByUser
    case startedByUser
    case targetSpeedChanged(Int)
    case controlPermissionLost
}
