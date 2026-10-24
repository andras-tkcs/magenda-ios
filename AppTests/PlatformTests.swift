// The adapters that connect AppCore's protocols to Apple frameworks: Keychain, CryptoKit and
// UserDefaults, and the binder's files. Hosted, because the Keychain needs the app's
// keychain-access group.

import AppCore
import Foundation
import Testing

@testable import Magenda

@Suite("Platform adapters", .serialized)
struct PlatformTests {
    private static let tokens = OAuthTokens(
        accessToken: "access-1", refreshToken: "refresh-1",
        expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
    private static let clientID = "123456789012-test.apps.googleusercontent.com"

    @Test("The token store saves, overwrites, loads and deletes")
    func tokenStoreRoundTrip() throws {
        let store = KeychainTokenStore(service: "name.tkcs.magenda.tests")
        try store.delete()
        defer { try? store.delete() }

        #expect(try store.load() == nil)
        try store.save(Self.tokens)
        #expect(try store.load() == Self.tokens)

        let newer = OAuthTokens(
            accessToken: "access-2", refreshToken: "refresh-2",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        try store.save(newer)
        #expect(try store.load() == newer)

        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }

    @Test("The client credentials store round-trips with and without a secret")
    func clientStoreRoundTrip() throws {
        let store = KeychainClientCredentialsStore(
            service: "name.tkcs.magenda.tests-client")
        try store.delete()
        defer { try? store.delete() }

        #expect(try store.load() == nil)
        let withSecret = GoogleClientCredentials(clientID: Self.clientID, clientSecret: "s3cret")
        try store.save(withSecret)
        #expect(try store.load() == withSecret)

        let withoutSecret = GoogleClientCredentials(clientID: Self.clientID, clientSecret: nil)
        try store.save(withoutSecret)
        #expect(try store.load() == withoutSecret)

        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("The routine credentials store saves, loads and deletes")
    func routineStoreRoundTrip() throws {
        let store = KeychainRoutineCredentialsStore(service: "name.tkcs.magenda.tests-routine")
        try store.delete()
        defer { try? store.delete() }

        #expect(try store.load() == nil)
        let routine = try #require(
            RoutineCredentials(
                fireURL: "https://api.anthropic.com/v1/claude_code/routines/trig_test/fire",
                token: "sk-ant-oat01-test"))
        try store.save(routine)
        #expect(try store.load() == routine)

        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("Settings round-trip through UserDefaults and garbage loads as defaults")
    func settingsRoundTrip() throws {
        let suite = "name.tkcs.magenda.tests.settings"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults: defaults)

        #expect(store.load() == AgendaSettings())

        var settings = AgendaSettings()
        settings.todoListTitle = "Another list"
        store.save(settings)
        #expect(store.load() == settings)

        defaults.set(Data("not json".utf8), forKey: "agendaSettings")
        #expect(store.load() == AgendaSettings())
    }

    @Test("SHA-256 gives the RFC 7636 challenge")
    func hasherMatchesRFC7636() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let digest = CryptoKitHasher().sha256(Data(verifier.utf8))
        let challenge = digest.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(digest.count == 32)
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("The binder store saves, replaces and deletes days and handwriting")
    func binderStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "binder-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileBinderStore(directory: directory)
        let content = AgendaContentFixtures.typical
        let day = BinderDay(content: content, theme: Theme())

        #expect(try store.day(content.date) == nil)
        try store.saveDay(day)
        #expect(try store.day(content.date) == day)

        let extra = ExtraPage(id: "a", after: .overview, source: .notes)
        let replacement = BinderDay(content: content, theme: Theme(), extras: [extra])
        try store.saveDay(replacement)
        #expect(try store.day(content.date) == replacement)

        #expect(try store.ink(on: content.date).isEmpty)
        try store.saveInk(Data("first".utf8), for: .overview, on: content.date)
        try store.saveInk(Data("notes".utf8), for: .notes, on: content.date)
        #expect(try store.ink(on: content.date).count == 2)
        #expect(try store.ink(on: content.date)[.overview] == Data("first".utf8))

        try store.saveInk(Data("second".utf8), for: .overview, on: content.date)
        #expect(try store.ink(on: content.date)[.overview] == Data("second".utf8))
        #expect(try store.ink(on: content.date)[.notes] == Data("notes".utf8))

        try store.saveInk(Data(), for: .overview, on: content.date)
        let remaining = try store.ink(on: content.date)
        #expect(remaining[.overview] == nil)
        #expect(remaining[.notes] == Data("notes".utf8))
    }

    @Test("The binder store writes with complete-unless-open protection")
    func protectedBinderStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "binder-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileBinderStore(directory: directory, protection: FileProtection.writingOptions)
        let content = AgendaContentFixtures.typical
        let day = BinderDay(content: content, theme: Theme())

        try store.saveDay(day)
        try store.saveInk(Data("ink".utf8), for: .overview, on: content.date)

        #expect(try store.day(content.date) == day)
        #expect(try store.ink(on: content.date)[.overview] == Data("ink".utf8))
    }
}
