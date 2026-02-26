import Foundation

public struct TreadmillLastRecord: Sendable {
    public let raw: [UInt8]
    public let time: Int
    public let distance: Int
    public let timestamp: Date

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

    public init(raw: [UInt8], time: Int, distance: Int, timestamp: Date = .now) {
        self.raw = raw
        self.time = time
        self.distance = distance
        self.timestamp = timestamp
    }
}
