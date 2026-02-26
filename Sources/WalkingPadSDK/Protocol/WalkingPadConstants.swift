@preconcurrency import CoreBluetooth

public enum WalkingPadConstants {
    // Known service/characteristic UUID sets used by different KingSmith models.
    // Older WalkingPad models use FE00/FE01/FE02.
    // Newer KS-HD models use FFF0/FFF1/FFF2 or FFC0/FFC1/FFC2.
    public struct CharacteristicSet: Sendable {
        public let service: CBUUID
        public let notify: CBUUID
        public let write: CBUUID
    }

    public static let knownCharSets: [CharacteristicSet] = [
        CharacteristicSet(
            service: CBUUID(string: "FE00"),
            notify: CBUUID(string: "FE01"),
            write: CBUUID(string: "FE02")
        ),
        CharacteristicSet(
            service: CBUUID(string: "FFF0"),
            notify: CBUUID(string: "FFF1"),
            write: CBUUID(string: "FFF2")
        ),
        CharacteristicSet(
            service: CBUUID(string: "FFC0"),
            notify: CBUUID(string: "FFC1"),
            write: CBUUID(string: "FFC2")
        ),
    ]

    public static let frameStart: UInt8 = 0xF7
    public static let frameEnd: UInt8 = 0xFD

    public static let statusResponsePrefix: [UInt8] = [0xF8, 0xA2]
    public static let historyResponsePrefix: [UInt8] = [0xF8, 0xA7]

    public static let minCommandSpacing: TimeInterval = 0.69

    public static let deviceNamePrefixes = ["walkingpad", "ks-"]
}
