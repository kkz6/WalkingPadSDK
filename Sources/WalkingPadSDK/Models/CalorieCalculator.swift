import Foundation

/// User profile for calorie calculation
public struct UserProfile: Sendable, Codable {
    public var weightKg: Double
    public var heightCm: Double
    public var age: Int
    public var isMale: Bool

    public init(weightKg: Double = 70.0, heightCm: Double = 170.0, age: Int = 30, isMale: Bool = true) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        self.isMale = isMale
    }
}

/// ACSM metabolic equation-based calorie calculator for treadmill walking/running.
///
/// Uses the Mifflin-St Jeor BMR formula combined with ACSM exercise VO2 equations
/// to provide accurate calorie calculations based on user profile and walking speed.
public struct CalorieCalculator: Sendable {
    public let profile: UserProfile

    public init(profile: UserProfile) {
        self.profile = profile
    }

    /// Calculate calories burned per minute at the given speed.
    ///
    /// - Parameter kmh: Walking/running speed in km/h
    /// - Returns: Calories per minute (kcal/min)
    public func caloriesPerMinute(atSpeedKmh kmh: Double) -> Double {
        guard kmh > 0.5 else { return 0 }

        let speedMpm = kmh * 1000.0 / 60.0 // meters per minute

        // Mifflin-St Jeor BMR
        let bmr = 10.0 * profile.weightKg
            + 6.25 * profile.heightCm
            - 5.0 * Double(profile.age)
            + (profile.isMale ? 5.0 : -161.0)

        // Resting VO2 derived from personal BMR
        let restingVO2 = (bmr / 1440.0) * 1000.0 / (profile.weightKg * 5.0)

        // ACSM exercise VO2: 0.1 for walking (<=6 km/h), 0.2 for running (>6 km/h)
        let exerciseVO2 = (kmh <= 6.0 ? 0.1 : 0.2) * speedMpm

        let totalVO2 = exerciseVO2 + restingVO2

        return totalVO2 * profile.weightKg / 1000.0 * 5.0
    }

    /// Calculate calories burned over a time interval at the given speed.
    ///
    /// - Parameters:
    ///   - kmh: Walking/running speed in km/h
    ///   - seconds: Duration in seconds
    /// - Returns: Total calories burned (kcal)
    public func calories(atSpeedKmh kmh: Double, forSeconds seconds: Double) -> Double {
        caloriesPerMinute(atSpeedKmh: kmh) * seconds / 60.0
    }
}
