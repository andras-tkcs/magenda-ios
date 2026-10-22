// An `AgendaRendering` for tests: records every plan and file name, then returns a fixed URL or
// throws.

import AppCore
import Foundation

// `@unchecked Sendable` is safe because every access to the mutable state goes through `lock`.
final class FakeRenderer: AgendaRendering, @unchecked Sendable {
    struct Failure: Error {}

    let url: URL
    let fails: Bool

    private let lock = NSLock()
    private var recordedPlans: [RenderPlan] = []
    private var recordedInks: [[Data?]] = []
    private var recordedFileNames: [String] = []

    init(url: URL = URL(fileURLWithPath: "/tmp/agenda.pdf"), fails: Bool = false) {
        self.url = url
        self.fails = fails
    }

    /// Every plan rendered so far, oldest first.
    var plans: [RenderPlan] {
        locked { recordedPlans }
    }

    /// The handwriting passed with every render so far, oldest first.
    var inks: [[Data?]] {
        locked { recordedInks }
    }

    /// The file name of every render so far, oldest first.
    var fileNames: [String] {
        locked { recordedFileNames }
    }

    func render(_ plan: RenderPlan, ink: [Data?], fileName: String) async throws -> URL {
        record(plan, ink, fileName)
        if fails {
            throw Failure()
        }
        return url
    }

    private func record(_ plan: RenderPlan, _ ink: [Data?], _ fileName: String) {
        locked {
            recordedPlans.append(plan)
            recordedInks.append(ink)
            recordedFileNames.append(fileName)
        }
    }

    // `NSLock.lock()` is unavailable from async code, so `render` only locks through here.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
