import Foundation

public enum ByteUtils {
    public static func int2byte(_ val: Int, width: Int = 3) -> [UInt8] {
        (0..<width).map { i in
            UInt8((val >> (8 * (width - 1 - i))) & 0xFF)
        }
    }

    public static func byte2int(_ bytes: ArraySlice<UInt8>, width: Int = 3) -> Int {
        let arr = Array(bytes.prefix(width))
        return arr.enumerated().reduce(0) { result, pair in
            result + (Int(pair.element) << (8 * (width - 1 - pair.offset)))
        }
    }

    public static func byte2int(_ bytes: [UInt8], width: Int = 3) -> Int {
        byte2int(bytes[0...], width: width)
    }

    public static func fixCRC(_ cmd: inout [UInt8]) {
        guard cmd.count >= 3 else { return }
        let sum = cmd[1..<(cmd.count - 2)].reduce(0) { $0 + Int($1) }
        cmd[cmd.count - 2] = UInt8(sum % 256)
    }
}
