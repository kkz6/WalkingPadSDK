@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = SDKLogger.make(category: "KingSmith")

// MARK: - KingSmith Proprietary Protocol

/// Proprietary KingSmith BLE protocol found on KS-HD-Z1D and similar newer models.
/// Uses custom service 24E2521C-F63B-48ED-85BE-C5330A00FDF7
///
/// Frame types from treadmill:
///   WLR (26 bytes): Status report  — header 57 4C 52, footer 41 54 (AT)
///   WLV (11 bytes): Command ACK    — header 57 4C 56, footer 53 54 (ST)
///   WLU (9 bytes):  Init/Version   — header 57 4C 55, footer 56 54 (VT)
///   WLQ (8 bytes):  Query          — header 57 4C 51, footer 51 54 (QT)
public enum KingSmithConstants {
    nonisolated(unsafe) public static let serviceUUID = CBUUID(
        string: "24E2521C-F63B-48ED-85BE-C5330A00FDF7"
    )
    nonisolated(unsafe) public static let notifyUUID = CBUUID(
        string: "24E2521C-F63B-48ED-85BE-C5330B00FDF7"
    )
    nonisolated(unsafe) public static let writeUUID = CBUUID(
        string: "24E2521C-F63B-48ED-85BE-C5330D00FDF7"
    )

    // Frame header
    public static let headerPrefix: [UInt8] = [0x57, 0x4C] // "WL"

    // Known type bytes (3rd byte)
    public static let typeReport: UInt8 = 0x52   // 'R' — status report
    public static let typeAck: UInt8 = 0x56      // 'V' — command ack
    public static let typeInit: UInt8 = 0x55     // 'U' — init/version
    public static let typeQuery: UInt8 = 0x51    // 'Q' — query

    // Frame footers per type
    public static let footerAT: [UInt8] = [0x41, 0x54]  // "AT" — used by WLR (report)
    public static let footerST: [UInt8] = [0x53, 0x54]  // "ST" — used by WLV (ack)
    public static let footerVT: [UInt8] = [0x56, 0x54]  // "VT" — used by WLU (init)
    public static let footerQT: [UInt8] = [0x51, 0x54]  // "QT" — used by WLQ (query)

    public static let reportFrameLength = 26
}

// MARK: - KS Proprietary Commands
/// Commands sent to the KS custom write characteristic (0x0036).
/// Frame format: [type: 1B] [sub_cmd: 1B] [payload_len: 1B] [payload: NB] [checksum: 1B]
/// Checksum = (sum of all preceding bytes) & 0xFF
public enum KSCommand {

    /// Build a KS command frame with checksum
    private static func frame(_ type: UInt8, _ subCmd: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        var data: [UInt8] = [type, subCmd, UInt8(payload.count)] + payload
        let checksum = UInt8(data.reduce(0) { ($0 + Int($1)) } & 0xFF)
        data.append(checksum)
        return data
    }

    /// Init step 1 — identifies device model to the controller
    /// Payload: [2 model-derived bytes] + device model suffix (e.g. "Z1D")
    public static func initDevice() -> [UInt8] {
        frame(0x71, 0x00, [0x64, 0x91, 0x5A, 0x31, 0x44])
    }

    /// Init step 2 — sends current timestamp to sync the device
    public static func initTimestamp() -> [UInt8] {
        let ts = UInt32(Date().timeIntervalSince1970)
        let tsBytes: [UInt8] = [
            UInt8(ts & 0xFF),
            UInt8((ts >> 8) & 0xFF),
            UInt8((ts >> 16) & 0xFF),
            UInt8((ts >> 24) & 0xFF),
        ]
        return frame(0x71, 0x01, tsBytes + [0x32, 0xF6, 0x59, 0x00])
    }

    /// Status query — requests device state
    public static func queryStatus() -> [UInt8] {
        frame(0x72, 0x00)
    }

    /// Config query — requests device configuration
    public static func queryConfig() -> [UInt8] {
        frame(0x75, 0x00)
    }

    /// Sleep command — puts the device into standby
    public static func sleep() -> [UInt8] {
        frame(0x72, 0x01, [0x0A, 0x40, 0x00])
    }

    /// Wake command — wakes the device from standby
    public static func wake() -> [UInt8] {
        frame(0x72, 0x01, [0x0A, 0x00, 0x00])
    }
}

// MARK: - KingSmith Response Parser

public enum KingSmithParser {

    /// Check if data starts with "WL" (any KingSmith frame)
    public static func isKingSmithFrame(_ data: [UInt8]) -> Bool {
        data.count >= 3 && data[0] == 0x57 && data[1] == 0x4C
    }

    /// Parse a KingSmith status frame (WLR, 26 bytes)
    public static func parseStatus(_ data: [UInt8]) -> TreadmillStatus? {
        guard data.count >= KingSmithConstants.reportFrameLength else { return nil }
        guard data[0] == 0x57, data[1] == 0x4C, data[2] == 0x52 else { return nil }
        guard data[24] == 0x41, data[25] == 0x54 else { return nil }

        let statusBytes = Array(data[3...23])
        let hex = statusBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.info("KS STATUS: [\(hex)]")

        let beltByte = data[3]
        let beltState: BeltState = beltByte == 0 ? .idle : .running

        let speed = Int(data[5])
        let time = Int(data[7]) | (Int(data[8]) << 8)
        let distance = Int(data[9]) | (Int(data[10]) << 8) | (Int(data[11]) << 16)
        logger.info("KS PARSED: belt=\(beltByte) speed=\(speed) time=\(time) dist=\(distance) byte4=\(data[4])")

        return TreadmillStatus(
            raw: data,
            beltState: beltState,
            speed: speed,
            mode: .manual,
            time: time,
            distance: distance,
            calories: 0,
            appSpeed: speed,
            controllerButton: 0
        )
    }

    /// Describe a KingSmith frame by its type byte
    public static func describeFrame(_ data: [UInt8]) -> String {
        guard data.count >= 3, data[0] == 0x57, data[1] == 0x4C else {
            return "unknown"
        }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        switch data[2] {
        case 0x52: return "WLR (status, \(data.count)B): \(hex)"
        case 0x56: return "WLV (ack, \(data.count)B): \(hex)"
        case 0x55: return "WLU (init, \(data.count)B): \(hex)"
        case 0x51: return "WLQ (query, \(data.count)B): \(hex)"
        default:
            let ch = String(UnicodeScalar(data[2]))
            return "WL\(ch) (unknown, \(data.count)B): \(hex)"
        }
    }
}

