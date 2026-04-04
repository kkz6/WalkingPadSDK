import Testing
@testable import WalkingPadSDK

@Suite("CalorieCalculator")
struct CalorieCalculatorTests {

    @Test("Default profile produces reasonable calories at walking speed")
    func defaultProfileWalking() {
        let calc = CalorieCalculator(profile: UserProfile())
        let cpm = calc.caloriesPerMinute(atSpeedKmh: 3.0)
        // Walking at 3 km/h should burn roughly 2-5 kcal/min for a 70kg person
        #expect(cpm > 1.0)
        #expect(cpm < 10.0)
    }

    @Test("Higher speed produces more calories")
    func higherSpeedMoreCalories() {
        let calc = CalorieCalculator(profile: UserProfile())
        let slow = calc.caloriesPerMinute(atSpeedKmh: 2.0)
        let fast = calc.caloriesPerMinute(atSpeedKmh: 5.0)
        #expect(fast > slow)
    }

    @Test("Very slow speed returns zero")
    func verySlowSpeedZero() {
        let calc = CalorieCalculator(profile: UserProfile())
        #expect(calc.caloriesPerMinute(atSpeedKmh: 0.3) == 0)
        #expect(calc.caloriesPerMinute(atSpeedKmh: 0.0) == 0)
    }

    @Test("Heavier person burns more calories")
    func heavierPersonMoreCalories() {
        let light = CalorieCalculator(profile: UserProfile(weightKg: 50))
        let heavy = CalorieCalculator(profile: UserProfile(weightKg: 100))
        let lightCpm = light.caloriesPerMinute(atSpeedKmh: 4.0)
        let heavyCpm = heavy.caloriesPerMinute(atSpeedKmh: 4.0)
        #expect(heavyCpm > lightCpm)
    }

    @Test("Running speed uses higher VO2 coefficient")
    func runningVsWalking() {
        let calc = CalorieCalculator(profile: UserProfile())
        let walking = calc.caloriesPerMinute(atSpeedKmh: 5.9)
        let running = calc.caloriesPerMinute(atSpeedKmh: 6.1)
        // Running coefficient (0.2) should produce significantly more than walking (0.1)
        #expect(running > walking * 1.5)
    }

    @Test("Calories over duration")
    func caloriesOverDuration() {
        let calc = CalorieCalculator(profile: UserProfile())
        let cpm = calc.caloriesPerMinute(atSpeedKmh: 4.0)
        let calories10min = calc.calories(atSpeedKmh: 4.0, forSeconds: 600)
        #expect(abs(calories10min - cpm * 10.0) < 0.001)
    }

    @Test("Gender affects BMR and calories")
    func genderAffectsCalories() {
        let male = CalorieCalculator(profile: UserProfile(weightKg: 70, heightCm: 170, age: 30, isMale: true))
        let female = CalorieCalculator(profile: UserProfile(weightKg: 70, heightCm: 170, age: 30, isMale: false))
        let maleCpm = male.caloriesPerMinute(atSpeedKmh: 4.0)
        let femaleCpm = female.caloriesPerMinute(atSpeedKmh: 4.0)
        // Male has higher BMR offset (+5 vs -161)
        #expect(maleCpm > femaleCpm)
    }

    @Test("UserProfile default values")
    func userProfileDefaults() {
        let profile = UserProfile()
        #expect(profile.weightKg == 70.0)
        #expect(profile.heightCm == 170.0)
        #expect(profile.age == 30)
        #expect(profile.isMale == true)
    }
}
