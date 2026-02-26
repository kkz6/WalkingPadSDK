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
        var offset = 2

        // Bit 0: More Data — 0 means instantaneous speed IS present
        var speed = 0
        if flags & 0x0001 == 0 {
            guard offset + 2 <= data.count else { return nil }
            let rawSpeed = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            speed = Int(rawSpeed) / 10 // Convert from 0.01 km/h to 0.1 km/h (tenths)
            offset += 2
        }

        // Bit 1: Average Speed
        if flags & 0x0002 != 0 {
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

        let beltState: BeltState = speed > 0 ? .running : .idle

        logger.debug("FTMS parsed: speed=\(speed) dist=\(distance)m time=\(elapsedTime)s cal=\(calories)")

        return TreadmillStatus(
            raw: data,
            beltState: beltState,
            speed: speed,
            mode: .manual,
            time: elapsedTime,
            distance: distance,
            calories: calories,
            appSpeed: speed,
            controllerButton: 0
        )
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
