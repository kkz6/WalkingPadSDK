import Foundation

public enum PreferenceKey: Int, Sendable {
    case target = 1
    case maxSpeed = 3
    case startSpeed = 4
    case startIntel = 5
    case sensitivity = 6
    case display = 7
    case units = 8
    case childLock = 9
}

public enum SensitivityLevel: Int, Sendable {
    case high = 1
    case medium = 2
    case low = 3

    public var label: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

public enum TargetType: Int, Sendable {
    case none = 0
    case distance = 1
    case calories = 2
    case time = 3
}
