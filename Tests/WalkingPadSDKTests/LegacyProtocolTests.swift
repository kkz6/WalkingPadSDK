import Testing
@testable import WalkingPadSDK

@Suite("Legacy Protocol")
struct LegacyProtocolTests {

    // MARK: - WalkingPadCommand

    @Test("askStats frame format")
    func askStatsFormat() {
        let cmd = WalkingPadCommand.askStats()
        #expect(cmd[0] == 0xF7)
        #expect(cmd[1] == 0xA2)
        #expect(cmd[2] == 0x00)
        #expect(cmd.last == 0xFD)
    }

    @Test("changeSpeed frame format")
    func changeSpeedFormat() {
        let cmd = WalkingPadCommand.changeSpeed(30) // 3.0 km/h
        #expect(cmd[0] == 0xF7)
        #expect(cmd[1] == 0xA2)
        #expect(cmd[2] == 0x01)
        #expect(cmd[3] == 30) // speed byte
        #expect(cmd.last == 0xFD)
    }

    @Test("startBelt frame format")
    func startBeltFormat() {
        let cmd = WalkingPadCommand.startBelt()
        #expect(cmd[0] == 0xF7)
        #expect(cmd[1] == 0xA2)
        #expect(cmd[2] == 0x04)
        #expect(cmd[3] == 0x01)
        #expect(cmd.last == 0xFD)
    }

    @Test("stopBelt is changeSpeed(0)")
    func stopBeltIsZeroSpeed() {
        let stop = WalkingPadCommand.stopBelt()
        let zero = WalkingPadCommand.changeSpeed(0)
        #expect(stop == zero)
    }

    // MARK: - CRC Verification

    @Test("fixCRC computes correct checksum")
    func fixCRC() {
        var cmd: [UInt8] = [0xF7, 0xA2, 0x01, 0x1E, 0x00, 0xFD]
        ByteUtils.fixCRC(&cmd)
        // CRC = sum of bytes[1..<4] = 0xA2 + 0x01 + 0x1E = 0xC1
        #expect(cmd[cmd.count - 2] == 0xC1)
    }

    @Test("fixCRC does nothing for too-short arrays")
    func fixCRCTooShort() {
        var cmd: [UInt8] = [0xF7, 0xFD]
        ByteUtils.fixCRC(&cmd)
        #expect(cmd == [0xF7, 0xFD]) // unchanged
    }

    // MARK: - WalkingPadParser

    @Test("Parse valid status response")
    func parseStatus() {
        // Minimal valid status: 18 bytes, prefix F8 A2
        var data: [UInt8] = Array(repeating: 0, count: 18)
        data[0] = 0xF8
        data[1] = 0xA2
        data[2] = 1     // belt state = running
        data[3] = 25    // speed = 25 (2.5 km/h)
        data[4] = 1     // mode = manual
        // time bytes [5..7] = 300 seconds
        let timeBytes = ByteUtils.int2byte(300)
        data[5] = timeBytes[0]; data[6] = timeBytes[1]; data[7] = timeBytes[2]
        // distance bytes [8..10] = 500
        let distBytes = ByteUtils.int2byte(500)
        data[8] = distBytes[0]; data[9] = distBytes[1]; data[10] = distBytes[2]
        data[14] = 25   // appSpeed
        data[16] = 0    // controllerButton

        let status = WalkingPadParser.parseStatus(data)
        #expect(status != nil)
        #expect(status?.beltState == .running)
        #expect(status?.speed == 25)
        #expect(status?.mode == .manual)
        #expect(status?.time == 300)
        #expect(status?.distance == 500)
        #expect(status?.appSpeed == 25)
    }

    @Test("Reject non-status prefix")
    func rejectBadPrefix() {
        var data: [UInt8] = Array(repeating: 0, count: 18)
        data[0] = 0xF8
        data[1] = 0xA3 // wrong prefix
        #expect(WalkingPadParser.parseStatus(data) == nil)
    }

    @Test("Reject too-short status data")
    func rejectShortStatus() {
        let data: [UInt8] = [0xF8, 0xA2, 0x00, 0x00]
        #expect(WalkingPadParser.parseStatus(data) == nil)
    }

    @Test("Parse last record")
    func parseLastRecord() {
        var data: [UInt8] = Array(repeating: 0, count: 17)
        data[0] = 0xF8
        data[1] = 0xA7
        let timeBytes = ByteUtils.int2byte(600)
        data[8] = timeBytes[0]; data[9] = timeBytes[1]; data[10] = timeBytes[2]
        let distBytes = ByteUtils.int2byte(1200)
        data[11] = distBytes[0]; data[12] = distBytes[1]; data[13] = distBytes[2]

        let record = WalkingPadParser.parseLastRecord(data)
        #expect(record != nil)
        #expect(record?.time == 600)
        #expect(record?.distance == 1200)
    }

    // MARK: - KingSmith Parser

    @Test("isKingSmithFrame detects WL prefix")
    func isKingSmithFrame() {
        #expect(KingSmithParser.isKingSmithFrame([0x57, 0x4C, 0x52]) == true)
        #expect(KingSmithParser.isKingSmithFrame([0x57, 0x4C, 0x56]) == true)
        #expect(KingSmithParser.isKingSmithFrame([0x57, 0x00, 0x52]) == false)
        #expect(KingSmithParser.isKingSmithFrame([0x57]) == false)
    }

    @Test("Parse KS status frame (WLR, 26 bytes)")
    func parseKSStatus() {
        var data: [UInt8] = Array(repeating: 0, count: 26)
        data[0] = 0x57 // 'W'
        data[1] = 0x4C // 'L'
        data[2] = 0x52 // 'R'
        data[3] = 0x01 // belt running
        data[5] = 30   // speed
        data[7] = 0x3C; data[8] = 0x00 // time = 60
        data[9] = 0xC8; data[10] = 0x00; data[11] = 0x00 // distance = 200
        data[24] = 0x41 // 'A'
        data[25] = 0x54 // 'T'

        let status = KingSmithParser.parseStatus(data)
        #expect(status != nil)
        #expect(status?.beltState == .running)
        #expect(status?.speed == 30)
        #expect(status?.time == 60)
        #expect(status?.distance == 200)
    }

    @Test("Reject KS frame with wrong header")
    func rejectBadKSHeader() {
        var data: [UInt8] = Array(repeating: 0, count: 26)
        data[0] = 0x57
        data[1] = 0x4C
        data[2] = 0x56 // 'V' not 'R'
        data[24] = 0x41
        data[25] = 0x54
        #expect(KingSmithParser.parseStatus(data) == nil)
    }

    @Test("Reject KS frame with wrong footer")
    func rejectBadKSFooter() {
        var data: [UInt8] = Array(repeating: 0, count: 26)
        data[0] = 0x57
        data[1] = 0x4C
        data[2] = 0x52
        data[24] = 0x00 // wrong footer
        data[25] = 0x00
        #expect(KingSmithParser.parseStatus(data) == nil)
    }
}
