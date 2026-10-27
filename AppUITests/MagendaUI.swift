// The steps every UI test class shares: launching on a fixture with animations off, finding an
// element by identifier, waiting on a property, and scrolling a container until an element shows.

import XCTest

extension XCUIApplication {
    /// Whether this test run has launched Magenda yet.
    @MainActor private static var hasLaunched = false

    /// Launches Magenda on `fixture` with animations off, plus `extra` arguments.
    ///
    /// The first launch on a freshly booted simulator can take a minute or more before the app
    /// answers accessibility queries, which would use up a test's own waits. So that launch first
    /// waits, for up to three minutes, until the app's window can be found.
    @MainActor
    static func launchMagenda(fixture: String = "standard", _ extra: [String] = [])
        -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments = ["-MagendaFixture", fixture, "-MagendaNoAnimations"] + extra
        app.launch()
        if !hasLaunched {
            hasLaunched = true
            _ = app.windows.firstMatch.waitForExistence(timeout: 180)
        }
        return app
    }

    /// The element with `identifier`, of any type.
    @MainActor
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }
}

extension XCUIElement {
    /// Waits until `keyPath` equals `value`. Xcode's `wait(for:toEqual:timeout:)` does not poll once
    /// a second, as an `XCTNSPredicateExpectation` does.
    @MainActor
    @discardableResult
    func waitUntil<V: Equatable>(
        _ keyPath: KeyPath<XCUIElement, V>, is value: V, timeout: TimeInterval = 30
    ) -> Bool {
        wait(for: keyPath, toEqual: value, timeout: timeout)
    }

    /// Scrolls the content of this container (positive `distance` shows what is further down) with
    /// one held drag that does not fling.
    @MainActor
    func scrollContent(by distance: CGFloat) {
        let start: XCUICoordinate
        let end: XCUICoordinate
        if distance > 0 {
            start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            end = start.withOffset(CGVector(dx: 0, dy: -distance))
        } else {
            start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            end = start.withOffset(CGVector(dx: 0, dy: -distance))
        }
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 600, thenHoldForDuration: 0.2)
    }

    /// Scrolls `container` until this element is hittable with its middle between `top` and
    /// `bottom`, or until the container cannot scroll further. Fails the test otherwise.
    @MainActor
    func reveal(
        in container: XCUIElement, top: CGFloat? = nil, bottom: CGFloat? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let containerFrame = container.frame
        let topLimit = top ?? containerFrame.minY + 60
        let bottomLimit = bottom ?? containerFrame.maxY - 20
        var lastMid: CGFloat?
        var stalled = 0
        for attempt in 0..<24 {
            guard exists else {
                lastMid = nil
                container.scrollContent(by: attempt < 12 ? 300 : -300)
                continue
            }
            let mid = frame.midY
            if mid >= topLimit && mid <= bottomLimit && isHittable { return }
            stalled = lastMid.map { abs($0 - mid) < 2 ? stalled + 1 : 0 } ?? 0
            lastMid = mid
            if stalled >= 2 && isHittable { return }  // the container cannot scroll any further
            if mid < topLimit {
                container.scrollContent(by: -min(max(topLimit - mid + 40, 100), 300))
            } else {
                container.scrollContent(by: min(max(mid - bottomLimit + 40, 100), 300))
            }
        }
        XCTFail("\(self) was never scrolled into view", file: file, line: line)
    }
}
