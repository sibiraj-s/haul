import Foundation
import Testing
@testable import Haul

/// Pure settings logic only: `AppSettings.shared` writes to the app's real preferences.
struct ScheduleTests {
    @Test func daytimeWindow() {
        #expect(!AppSettings.inSchedule(hour: 0, from: 1, to: 7))
        #expect(AppSettings.inSchedule(hour: 1, from: 1, to: 7))
        #expect(AppSettings.inSchedule(hour: 6, from: 1, to: 7))
        #expect(!AppSettings.inSchedule(hour: 7, from: 1, to: 7))
    }

    @Test func windowAcrossMidnight() {
        #expect(AppSettings.inSchedule(hour: 22, from: 22, to: 6))
        #expect(AppSettings.inSchedule(hour: 23, from: 22, to: 6))
        #expect(AppSettings.inSchedule(hour: 3, from: 22, to: 6))
        #expect(!AppSettings.inSchedule(hour: 6, from: 22, to: 6))
        #expect(!AppSettings.inSchedule(hour: 12, from: 22, to: 6))
    }

    @Test func sameStartAndEndMeansAllDay() {
        for hour in 0..<24 { #expect(AppSettings.inSchedule(hour: hour, from: 5, to: 5)) }
    }
}

struct ListCleanupTests {
    @Test func ages() {
        #expect(ListCleanup.manually.age(days: 90) == nil)
        #expect(ListCleanup.whenFinished.age(days: 90) == 0)
        #expect(ListCleanup.afterDays.age(days: 1) == TimeInterval(86_400))
        #expect(ListCleanup.afterDays.age(days: 90) == TimeInterval(90 * 86_400))
    }

    @Test func oldFixedChoicesBecomeDays() {
        #expect(ListCleanup(rawValue: "week") == nil)
        #expect(ListCleanup.legacyDays == ["day": 1, "week": 7, "month": 30])
    }
}
