import Foundation
import Testing
@testable import WalkingPadSDK

@Suite("KingSmith Commands")
struct KSCommandTests {

    @Test("Checksum is sum of preceding bytes & 0xFF")
    func checksumCalculation() {
        // sleep() = frame(0x72, 0x01, [0x0A, 0x40, 0x00])
        // data before checksum: [0x72, 0x01, 0x03, 0x0A, 0x40, 0x00]
        // sum = 0x72 + 0x01 + 0x03 + 0x0A + 0x40 + 0x00 = 0xC0
        let cmd = KSCommand.sleep()
        let sum = cmd.dropLast().reduce(0) { $0 + Int($1) } & 0xFF
        #expect(cmd.last == UInt8(sum))
    }

    @Test("initDevice frame format")
    func initDeviceFormat() {
        let cmd = KSCommand.initDevice()
        #expect(cmd[0] == 0x71) // type
        #expect(cmd[1] == 0x00) // subCmd
        #expect(cmd[2] == 0x05) // payload length
        // payload: [0x64, 0x91, 0x5A, 0x31, 0x44] = model "Z1D" prefix
        #expect(cmd[3] == 0x64)
        #expect(cmd[4] == 0x91)
        #expect(cmd[5] == 0x5A) // 'Z'
        #expect(cmd[6] == 0x31) // '1'
        #expect(cmd[7] == 0x44) // 'D'
        #expect(cmd.count == 9) // 3 header + 5 payload + 1 checksum
    }

    @Test("initTimestamp contains 4-byte LE timestamp")
    func initTimestampFormat() {
        let before = UInt32(Date().timeIntervalSince1970)
        let cmd = KSCommand.initTimestamp()
        let after = UInt32(Date().timeIntervalSince1970)

        #expect(cmd[0] == 0x71) // type
        #expect(cmd[1] == 0x01) // subCmd
        #expect(cmd[2] == 0x08) // payload length (4 ts + 4 extra)

        // Extract timestamp from payload bytes 3..6
        let ts = UInt32(cmd[3]) | (UInt32(cmd[4]) << 8) | (UInt32(cmd[5]) << 16) | (UInt32(cmd[6]) << 24)
        #expect(ts >= before)
        #expect(ts <= after)
    }

    @Test("queryStatus format")
    func queryStatusFormat() {
        let cmd = KSCommand.queryStatus()
        #expect(cmd[0] == 0x72)
        #expect(cmd[1] == 0x00)
        #expect(cmd[2] == 0x00) // empty payload
        #expect(cmd.count == 4) // 3 header + 0 payload + 1 checksum
    }

    @Test("queryConfig format")
    func queryConfigFormat() {
        let cmd = KSCommand.queryConfig()
        #expect(cmd[0] == 0x75)
        #expect(cmd[1] == 0x00)
        #expect(cmd[2] == 0x00)
        #expect(cmd.count == 4)
    }

    @Test("sleep command payload is [0x0A, 0x40, 0x00]")
    func sleepPayload() {
        let cmd = KSCommand.sleep()
        #expect(cmd[0] == 0x72)
        #expect(cmd[1] == 0x01)
        #expect(cmd[2] == 0x03) // payload length
        #expect(cmd[3] == 0x0A)
        #expect(cmd[4] == 0x40)
        #expect(cmd[5] == 0x00)
    }

    @Test("wake command payload is [0x0A, 0x00, 0x00]")
    func wakePayload() {
        let cmd = KSCommand.wake()
        #expect(cmd[0] == 0x72)
        #expect(cmd[1] == 0x01)
        #expect(cmd[2] == 0x03) // payload length
        #expect(cmd[3] == 0x0A)
        #expect(cmd[4] == 0x00)
        #expect(cmd[5] == 0x00)
    }

    @Test("wake and sleep differ only in payload byte 4")
    func wakeVsSleep() {
        let wake = KSCommand.wake()
        let sleep = KSCommand.sleep()
        // Same header
        #expect(wake[0] == sleep[0])
        #expect(wake[1] == sleep[1])
        #expect(wake[2] == sleep[2])
        // Same byte 3
        #expect(wake[3] == sleep[3])
        // Different byte 4
        #expect(wake[4] == 0x00)
        #expect(sleep[4] == 0x40)
    }
}
