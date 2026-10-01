// The built app's bundle: the values the build stamps into Info.plist are there.
//
// Runs inside the app on a simulator (a hosted unit test), so `Bundle.main` is the real app bundle
// and not a test runner's. The version and build number come from build settings that build.yml
// overrides from the release tag (ADR 0004); this proves the path from build setting to bundle
// exists at all. Reading the bundle into `AppInfo` is AppCore's to test.

import Foundation
import Testing

@Suite("The app bundle's Info.plist")
struct BundleInfoTests {
    private func value(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    @Test("The display name is the app's name")
    func displayNameIsSet() {
        let expected = "Magenda"
        #expect(value("CFBundleDisplayName") == expected)
    }

    @Test("The version and the build number are stamped in")
    func versionIsStamped() {
        #expect(value("CFBundleShortVersionString")?.isEmpty == false)
        #expect(value("CFBundleVersion")?.isEmpty == false)
    }
}
