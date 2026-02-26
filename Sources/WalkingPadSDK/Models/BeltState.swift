import Foundation

public enum BeltState: Int, Sendable {
    case idle = 0
    case running = 1
    case starting = 5

    public init(rawByte: UInt8) {
        self = BeltState(rawValue: Int(rawByte)) ?? .idle
    }

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .starting: "Starting"
        }
    }

    public var isActive: Bool {
        self == .running || self == .starting
    }
}
