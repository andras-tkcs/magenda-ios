// An `AgendaRendering` for tests that wraps a `FakeRenderer` and holds its first render until the
// test releases it, so a test can load, sign out or edit while a PDF is being written.

import AppCore
import Foundation

actor GatedRenderer: AgendaRendering {
    nonisolated let base: FakeRenderer
    private var renders = 0
    private var isBlocked = false
    private var isReleased = false
    private var gate: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    init(_ base: FakeRenderer = FakeRenderer()) {
        self.base = base
    }

    /// Returns once the first render is waiting for `release()`.
    func waitUntilBlocked() async {
        if isBlocked {
            return
        }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the first render continue.
    func release() {
        isReleased = true
        gate?.resume()
        gate = nil
    }

    func render(_ plan: RenderPlan, fileName: String) async throws -> URL {
        renders += 1
        if renders == 1 {
            await block()
        }
        return try await base.render(plan, fileName: fileName)
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
