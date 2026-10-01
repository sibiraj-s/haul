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
        #expect(ListCleanup.manually.age == nil)
        #expect(ListCleanup.whenFinished.age == 0)
        #expect(ListCleanup.day.age == TimeInterval(86_400))
        #expect(ListCleanup.week.age == TimeInterval(7 * 86_400))
        #expect(ListCleanup.month.age == TimeInterval(30 * 86_400))
    }
}
