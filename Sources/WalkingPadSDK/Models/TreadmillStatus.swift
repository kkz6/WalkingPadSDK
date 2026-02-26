import Foundation

public struct TreadmillStatus: Sendable {
    public let raw: [UInt8]
    public let beltState: BeltState
    public let speed: Int
    public let mode: TreadmillMode
    public let time: Int
    public let distance: Int
    public let calories: Int
    public let appSpeed: Int
    public let controllerButton: Int
    public let timestamp: Date

    public var speedKmh: Double { Double(speed) / 10.0 }
    public var distanceKm: Double { Double(distance) / 100.0 }

    public var formattedTime: String {
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public init(
        raw: [UInt8],
        beltState: BeltState,
        speed: Int,
        mode: TreadmillMode,
        time: Int,
        distance: Int,
        calories: Int,
        appSpeed: Int,
        controllerButton: Int,
        timestamp: Date = .now
    ) {
        self.raw = raw
        self.beltState = beltState
        self.speed = speed
        self.mode = mode
        self.time = time
        self.distance = distance
        self.calories = calories
        self.appSpeed = appSpeed
        self.controllerButton = controllerButton
        self.timestamp = timestamp
    }
}
