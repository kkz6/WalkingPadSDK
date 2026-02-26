import Testing
@testable import WalkingPadSDK

@Suite("Models")
struct ModelTests {

    // MARK: - BeltState

    @Test("BeltState from raw bytes")
    func beltStateFromRaw() {
        #expect(BeltState(rawByte: 0) == .idle)
        #expect(BeltState(rawByte: 1) == .running)
        #expect(BeltState(rawByte: 5) == .starting)
        #expect(BeltState(rawByte: 99) == .idle) // unknown defaults to idle
    }

    @Test("BeltState isActive")
    func beltStateIsActive() {
        #expect(BeltState.idle.isActive == false)
        #expect(BeltState.running.isActive == true)
        #expect(BeltState.starting.isActive == true)
    }

    @Test("BeltState labels")
    func beltStateLabels() {
        #expect(BeltState.idle.label == "Idle")
        #expect(BeltState.running.label == "Running")
        #expect(BeltState.starting.label == "Starting")
    }

    // MARK: - TreadmillMode

    @Test("TreadmillMode labels")
    func treadmillModeLabels() {
        #expect(TreadmillMode.automatic.label == "Auto")
        #expect(TreadmillMode.manual.label == "Manual")
        #expect(TreadmillMode.standby.label == "Standby")
    }

    // MARK: - TreadmillStatus

    @Test("speedKmh conversion")
    func speedKmhConversion() {
        let status = TreadmillStatus(
            raw: [], beltState: .running, speed: 35, mode: .manual,
            time: 0, distance: 0, calories: 0, appSpeed: 35, controllerButton: 0
        )
        #expect(status.speedKmh == 3.5)
    }

    @Test("distanceKm conversion")
    func distanceKmConversion() {
        let status = TreadmillStatus(
            raw: [], beltState: .idle, speed: 0, mode: .manual,
            time: 0, distance: 250, calories: 0, appSpeed: 0, controllerButton: 0
        )
        #expect(status.distanceKm == 2.5)
    }

    @Test("formattedTime without hours")
    func formattedTimeNoHours() {
        let status = TreadmillStatus(
            raw: [], beltState: .idle, speed: 0, mode: .manual,
            time: 125, distance: 0, calories: 0, appSpeed: 0, controllerButton: 0
        )
        #expect(status.formattedTime == "02:05")
    }

    @Test("formattedTime with hours")
    func formattedTimeWithHours() {
        let status = TreadmillStatus(
            raw: [], beltState: .idle, speed: 0, mode: .manual,
            time: 3725, distance: 0, calories: 0, appSpeed: 0, controllerButton: 0
        )
        #expect(status.formattedTime == "1:02:05")
    }

    // MARK: - TreadmillLastRecord

    @Test("TreadmillLastRecord distanceKm and formattedTime")
    func lastRecordConversions() {
        let record = TreadmillLastRecord(raw: [], time: 3600, distance: 500)
        #expect(record.distanceKm == 5.0)
        #expect(record.formattedTime == "1:00:00")
    }

    // MARK: - ByteUtils

    @Test("int2byte and byte2int roundtrip")
    func byteRoundtrip() {
        let values = [0, 1, 255, 256, 65535, 16777215]
        for val in values {
            let bytes = ByteUtils.int2byte(val)
            let back = ByteUtils.byte2int(bytes)
            #expect(back == val, "Roundtrip failed for \(val)")
        }
    }

    @Test("int2byte produces correct bytes")
    func int2byteCorrect() {
        // 300 = 0x00012C → [0x00, 0x01, 0x2C]
        let bytes = ByteUtils.int2byte(300)
        #expect(bytes == [0x00, 0x01, 0x2C])
    }

    // MARK: - ConnectionState

    @Test("ConnectionState labels")
    func connectionStateLabels() {
        #expect(ConnectionState.disconnected.label == "Disconnected")
        #expect(ConnectionState.scanning.label == "Scanning...")
        #expect(ConnectionState.connecting.label == "Connecting...")
        #expect(ConnectionState.connected.label == "Connected")
        #expect(ConnectionState.ready.label == "Ready")
    }

    @Test("ConnectionState isConnected")
    func connectionStateIsConnected() {
        #expect(ConnectionState.disconnected.isConnected == false)
        #expect(ConnectionState.scanning.isConnected == false)
        #expect(ConnectionState.connecting.isConnected == false)
        #expect(ConnectionState.connected.isConnected == true)
        #expect(ConnectionState.ready.isConnected == true)
    }
}
