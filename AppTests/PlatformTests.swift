// The adapters that connect AppCore's protocols to Apple frameworks: Keychain, CryptoKit and
// UserDefaults. Hosted, because the Keychain needs the app's keychain-access group.

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
}
