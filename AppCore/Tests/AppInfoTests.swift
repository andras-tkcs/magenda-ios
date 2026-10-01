// AppCore's `AppInfo`: what the About section shows, read from an Info.plist dictionary.

import AppCore
import Testing

@Suite("Reading AppInfo from an Info.plist")
struct AppInfoTests {
    @Test("Every value comes from its Info.plist key")
    func readsEveryKey() {
        let info = AppInfo(infoDictionary: [
            "CFBundleDisplayName": "Display",
            "CFBundleName": "Bundle",
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "345",
        ])
        #expect(info == AppInfo(name: "Display", version: "1.2.0", build: "345"))
        #expect(info.displayVersion == "1.2.0 (345)")
    }

    @Test("The bundle name stands in when there is no display name")
    func fallsBackToTheBundleName() {
        let info = AppInfo(infoDictionary: ["CFBundleName": "Bundle"])
        #expect(info.name == "Bundle")
    }

    /// A build that lost its version must say so on screen rather than show an empty string.
    @Test("Missing values read as unknown")
    func missingValuesAreVisible() {
        let info = AppInfo(infoDictionary: nil)
        #expect(info == AppInfo(name: "unknown", version: "unknown", build: "unknown"))
    }

    @Test("A value of the wrong type is treated as missing")
    func wrongTypesAreMissing() {
        let info = AppInfo(infoDictionary: ["CFBundleVersion": 345])
        #expect(info.build == AppInfo.unknown)
    }
}
