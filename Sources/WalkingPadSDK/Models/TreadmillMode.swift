import Foundation

public enum TreadmillMode: Int, Sendable {
    case automatic = 0
    case manual = 1
    case standby = 2

    public var label: String {
        switch self {
        case .automatic: "Auto"
        case .manual: "Manual"
        case .standby: "Standby"
        }
    }
}
