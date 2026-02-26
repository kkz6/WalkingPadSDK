import Testing
@testable import WalkingPadSDK

@Suite("FTMS Protocol")
struct FTMSTests {

    // MARK: - Treadmill Data Parsing

    @Test("Parse real KS-HD-Z1D treadmill data (flags 0x2484)")
    func parseRealTreadmillData() {
        // Real capture: flags=0x2484, speed=300 (3.0 km/h), distance=150m, calories=12, time=120s
        // Flags 0x2484 = 0010_0100_1000_0100:
        //   bit 0 = 0 → speed present
        //   bit 2 = 1 → total distance present
        //   bit 7 = 1 → expended energy present
        //   bit 10 = 1 → elapsed time present
        var data: [UInt8] = [0x84, 0x24] // flags
        data += [0x2C, 0x01]             // speed = 300 (0x012C) in 0.01 km/h
        data += [0x96, 0x00, 0x00]       // distance = 150m
        data += [0x0C, 0x00, 0x00, 0x00, 0x00] // calories=12, per-hour=0, per-min=0
        data += [0x78, 0x00]             // elapsed time = 120s

        let status = FTMSParser.parseTreadmillData(data)
        #expect(status != nil)
        #expect(status?.speed == 30) // 300 hundredths / 10 = 30 tenths
        #expect(status?.beltState == .running)
        #expect(status?.distance == 150)
        #expect(status?.calories == 12)
        #expect(status?.time == 120)
        #expect(status?.mode == .manual)
    }

    @Test("Parse speed-only flags (0x0000)")
    func parseSpeedOnly() {
        let data: [UInt8] = [0x00, 0x00, 0xF4, 0x01] // flags=0, speed=500 (5.0 km/h)
        let status = FTMSParser.parseTreadmillData(data)
        #expect(status != nil)
        #expect(status?.speed == 50) // 500 / 10 = 50 tenths
        #expect(status?.beltState == .running)
        #expect(status?.distance == 0)
        #expect(status?.calories == 0)
        #expect(status?.time == 0)
    }

    @Test("Too-short data returns nil")
    func parseTooShort() {
        #expect(FTMSParser.parseTreadmillData([0x00]) == nil)
        #expect(FTMSParser.parseTreadmillData([0x00, 0x00]) == nil)
        #expect(FTMSParser.parseTreadmillData([0x00, 0x00, 0x01]) == nil)
    }

    @Test("Zero speed produces idle belt state")
    func zerospeedIdle() {
        let data: [UInt8] = [0x00, 0x00, 0x00, 0x00] // speed = 0
        let status = FTMSParser.parseTreadmillData(data)
        #expect(status?.beltState == .idle)
    }

    @Test("Nonzero speed produces running belt state")
    func nonzeroSpeedRunning() {
        let data: [UInt8] = [0x00, 0x00, 0x0A, 0x00] // speed = 10 (0.1 km/h)
        let status = FTMSParser.parseTreadmillData(data)
        #expect(status?.beltState == .running)
    }

    @Test("Parse with average speed flag skips 2 bytes")
    func parseWithAverageSpeed() {
        // flags = 0x0002 (average speed present), bit 0 = 0 (instantaneous speed present)
        var data: [UInt8] = [0x02, 0x00]
        data += [0xC8, 0x00]       // instant speed = 200 (2.0 km/h)
        data += [0x64, 0x00]       // average speed = 100 (skipped)
        let status = FTMSParser.parseTreadmillData(data)
        #expect(status?.speed == 20) // 200 / 10
    }

    @Test("Parse data truncated mid-field returns nil")
    func parseTruncatedField() {
        // flags indicate distance present (bit 2), but data is too short
        let data: [UInt8] = [0x04, 0x00, 0x64, 0x00, 0x01] // only 1 byte of distance instead of 3
        #expect(FTMSParser.parseTreadmillData(data) == nil)
    }

    // MARK: - Machine Status Parsing

    @Test("Parse stopped by user event")
    func parseStoppedByUser() {
        let event = FTMSParser.parseMachineStatus([0x02, 0x01])
        #expect(event == .stoppedByUser)
    }

    @Test("Parse paused by user event")
    func parsePausedByUser() {
        let event = FTMSParser.parseMachineStatus([0x02, 0x02])
        #expect(event == .pausedByUser)
    }

    @Test("Parse started by user event")
    func parseStartedByUser() {
        let event = FTMSParser.parseMachineStatus([0x04])
        #expect(event == .startedByUser)
    }

    @Test("Parse target speed changed event")
    func parseTargetSpeedChanged() {
        let event = FTMSParser.parseMachineStatus([0x05, 0x2C, 0x01]) // 300
        if case .targetSpeedChanged(let speed) = event {
            #expect(speed == 300)
        } else {
            Issue.record("Expected targetSpeedChanged event")
        }
    }

    @Test("Parse control permission lost event")
    func parseControlLost() {
        let event = FTMSParser.parseMachineStatus([0x08])
        #expect(event == .controlPermissionLost)
    }

    @Test("Empty status data returns nil")
    func parseEmptyStatus() {
        #expect(FTMSParser.parseMachineStatus([]) == nil)
    }

    @Test("Unknown status opcode returns nil")
    func parseUnknownStatus() {
        #expect(FTMSParser.parseMachineStatus([0xFF]) == nil)
    }

    // MARK: - Command Builders

    @Test("Request control command")
    func requestControlCommand() {
        #expect(FTMSCommand.requestControl() == [0x00])
    }

    @Test("Start/resume command")
    func startCommand() {
        #expect(FTMSCommand.startOrResume() == [0x07])
    }

    @Test("Stop command")
    func stopCommand() {
        #expect(FTMSCommand.stop() == [0x08, 0x01])
    }

    @Test("Pause command")
    func pauseCommand() {
        #expect(FTMSCommand.pause() == [0x08, 0x02])
    }

    @Test("Set target speed command")
    func setTargetSpeedCommand() {
        let cmd = FTMSCommand.setTargetSpeed(300) // 3.0 km/h
        #expect(cmd == [0x02, 0x2C, 0x01])
    }

    @Test("Reset command")
    func resetCommand() {
        #expect(FTMSCommand.reset() == [0x01])
    }
}

// FTMSMachineEvent needs Equatable for test comparisons
extension FTMSMachineEvent: Equatable {
    public static func == (lhs: FTMSMachineEvent, rhs: FTMSMachineEvent) -> Bool {
        switch (lhs, rhs) {
        case (.stoppedByUser, .stoppedByUser),
             (.pausedByUser, .pausedByUser),
             (.startedByUser, .startedByUser),
             (.controlPermissionLost, .controlPermissionLost):
            return true
        case (.targetSpeedChanged(let a), .targetSpeedChanged(let b)):
            return a == b
        default:
            return false
        }
    }
}
