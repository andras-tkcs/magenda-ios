// A `GoogleDataSource` for tests that wraps another one and holds its first `events` call until
// the test releases it, so a test can start a second load while the first is still running.

import AppCore
import Foundation

actor GatedDataSource: GoogleDataSource {
    private let base: any GoogleDataSource
    private var eventsCalls = 0
    private var isBlocked = false
    private var isReleased = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    init(_ base: any GoogleDataSource) {
        self.base = base
    }

    /// Returns once the first `events` call is waiting for `release()`.
    func waitUntilBlocked() async {
        if isBlocked {
            return
        }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the first `events` call continue.
    func release() {
        isReleased = true
        gate?.resume()
        gate = nil
    }

    func calendars() async throws -> [GoogleCalendar] {
        try await base.calendars()
    }

    func events(calendarID: String, on day: CalendarDay, timeZone: TimeZone) async throws
        -> [GoogleEvent]
    {
        eventsCalls += 1
        if eventsCalls == 1 {
            await block()
        }
        return try await base.events(calendarID: calendarID, on: day, timeZone: timeZone)
    }

    func taskLists() async throws -> [GoogleTaskList] {
        try await base.taskLists()
    }

    func openTasks(listID: String) async throws -> [GoogleTask] {
        try await base.openTasks(listID: listID)
    }

    private func block() async {
        isBlocked = true
        arrival?.resume()
        arrival = nil
        if isReleased {
            return
        }
        await withCheckedContinuation { gate = $0 }
    }
}
