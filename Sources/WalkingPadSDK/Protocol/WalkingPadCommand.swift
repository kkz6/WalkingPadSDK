import Foundation

public enum WalkingPadCommand {
    public static func askStats() -> [UInt8] {
        var cmd: [UInt8] = [0xF7, 0xA2, 0x00, 0x00, 0x00, 0xFD]
        ByteUtils.fixCRC(&cmd)
        return cmd
    }

    public static func changeSpeed(_ speed: Int) -> [UInt8] {
        var cmd: [UInt8] = [0xF7, 0xA2, 0x01, UInt8(speed & 0xFF), 0x00, 0xFD]
        ByteUtils.fixCRC(&cmd)
        return cmd
    }

    public static func switchMode(_ mode: TreadmillMode) -> [UInt8] {
        var cmd: [UInt8] = [0xF7, 0xA2, 0x02, UInt8(mode.rawValue), 0x00, 0xFD]
        ByteUtils.fixCRC(&cmd)
        return cmd
    }

    public static func startBelt() -> [UInt8] {
        var cmd: [UInt8] = [0xF7, 0xA2, 0x04, 0x01, 0x00, 0xFD]
        ByteUtils.fixCRC(&cmd)
        return cmd
    }

    public static func stopBelt() -> [UInt8] {
        changeSpeed(0)
    }

    public static func askHistory(mode: Int = 0) -> [UInt8] {
        if mode == 0 {
            var cmd: [UInt8] = [0xF7, 0xA7, 0xAA, 0xFF, 0x00, 0xFD]
            ByteUtils.fixCRC(&cmd)
            return cmd
        } else {
            var cmd: [UInt8] = [0xF7, 0xA7, 0xAA, 0x00, 0x00, 0xFD]
            ByteUtils.fixCRC(&cmd)
            return cmd
        }
    }

    public static func setPreference(key: PreferenceKey, value: Int, subtype: Int = 0) -> [UInt8] {
        let valueBytes = ByteUtils.int2byte(value)
        var cmd: [UInt8] = [
            0xF7, 0xA6, UInt8(key.rawValue),
            UInt8(subtype), valueBytes[0], valueBytes[1], valueBytes[2],
            0x00, 0xFD
        ]
        ByteUtils.fixCRC(&cmd)
        return cmd
    }

    public static func setMaxSpeed(_ speedTenths: Int) -> [UInt8] {
        setPreference(key: .maxSpeed, value: speedTenths)
    }

    public static func setStartSpeed(_ speedTenths: Int) -> [UInt8] {
        setPreference(key: .startSpeed, value: speedTenths)
    }

    public static func setIntelligentStart(_ enabled: Bool) -> [UInt8] {
        setPreference(key: .startIntel, value: enabled ? 1 : 0)
    }

    public static func setSensitivity(_ level: SensitivityLevel) -> [UInt8] {
        setPreference(key: .sensitivity, value: level.rawValue)
    }

    public static func setDisplay(_ bitMask: Int) -> [UInt8] {
        setPreference(key: .display, value: bitMask)
    }

    public static func setChildLock(_ enabled: Bool) -> [UInt8] {
        setPreference(key: .childLock, value: enabled ? 1 : 0)
    }

    public static func setUnitsMiles(_ enabled: Bool) -> [UInt8] {
        setPreference(key: .units, value: enabled ? 1 : 0)
    }

    public static func setTarget(type: TargetType, value: Int = 0) -> [UInt8] {
        setPreference(key: .target, value: value, subtype: type.rawValue)
    }
}
