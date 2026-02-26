import Foundation

public enum WalkingPadParser {
    public static func isStatusResponse(_ data: [UInt8]) -> Bool {
        data.count >= 2 && data[0] == 0xF8 && data[1] == 0xA2
    }

    public static func isHistoryResponse(_ data: [UInt8]) -> Bool {
        data.count >= 2 && data[0] == 0xF8 && data[1] == 0xA7
    }

    public static func parseStatus(_ data: [UInt8]) -> TreadmillStatus? {
        guard isStatusResponse(data), data.count >= 18 else { return nil }

        let beltState = BeltState(rawByte: data[2])
        let speed = Int(data[3])
        let mode = TreadmillMode(rawValue: Int(data[4])) ?? .standby
        let time = ByteUtils.byte2int(Array(data[5...7]))
        let distance = ByteUtils.byte2int(Array(data[8...10]))
        let appSpeed = Int(data[14])
        let controllerButton = Int(data[16])

        return TreadmillStatus(
            raw: data,
            beltState: beltState,
            speed: speed,
            mode: mode,
            time: time,
            distance: distance,
            calories: 0,
            appSpeed: appSpeed,
            controllerButton: controllerButton
        )
    }

    public static func parseLastRecord(_ data: [UInt8]) -> TreadmillLastRecord? {
        guard isHistoryResponse(data), data.count >= 17 else { return nil }

        let time = ByteUtils.byte2int(Array(data[8...10]))
        let distance = ByteUtils.byte2int(Array(data[11...13]))

        return TreadmillLastRecord(
            raw: data,
            time: time,
            distance: distance
        )
    }
}
