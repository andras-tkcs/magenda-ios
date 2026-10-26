// AppCore's routine trigger: validating the entered credentials, the fire request and how each
// answer maps to an error. Every trigger ID and token here is made up.

import Foundation
import Testing

@testable import AppCore

private let goodURL = "https://api.anthropic.com/v1/claude_code/routines/trig_abc123/fire"
private let goodToken = "sk-ant-oat01-abc_DEF-123"
private let sessionJSON =
    #"{"type":"routine_fire","claude_code_session_id":"s1","claude_code_session_url":"https://claude.ai/code/session_1"}"#

private struct Unrelated: Error {}

/// A store whose load always throws.
private struct BrokenStore: RoutineCredentialsStore {
    func load() throws -> RoutineCredentials? { throw Unrelated() }
    func save(_ credentials: RoutineCredentials) throws {}
    func delete() throws {}
}

private func client(
    _ http: FakeHTTPClient, stored: Bool = true
) -> RoutineTriggerClient {
    let credentials = stored ? RoutineCredentials(fireURL: goodURL, token: goodToken) : nil
    return RoutineTriggerClient(
        http: http, credentials: InMemoryRoutineCredentialsStore(credentials))
}

private func failure(of http: FakeHTTPClient, text: String = "x") async -> RoutineTriggerError? {
    do {
        _ = try await client(http).fire(text: text)
        return nil
    } catch {
        return error as? RoutineTriggerError
    }
}

@Suite("Routine trigger")
struct RoutineTriggerTests {
    @Test("A valid URL and token are accepted with surrounding whitespace trimmed")
    func accepted() throws {
        let credentials = try #require(
            RoutineCredentials(fireURL: "  \(goodURL)\n", token: "\t\(goodToken) \n"))
        #expect(credentials.triggerID == "trig_abc123")
        #expect(credentials.token == goodToken)
        #expect(credentials.fireURL.absoluteString == goodURL)
    }

    @Test(
        "Anything but the routine's fire URL is rejected",
        arguments: [
            "http://api.anthropic.com/v1/claude_code/routines/trig_abc/fire",
            "https://example.com/v1/claude_code/routines/trig_abc/fire",
            "https://api.anthropic.com:8443/v1/claude_code/routines/trig_abc/fire",
            "https://api.anthropic.com/v1/claude_code/routines/trig_abc/fire?x=1",
            "https://api.anthropic.com/v1/claude_code/routines/trig_abc/fire?",
            "https://api.anthropic.com/v1/claude_code/routines/trig_abc/fire#top",
            "https://user@api.anthropic.com/v1/claude_code/routines/trig_abc/fire",
            "https://user:pw@api.anthropic.com/v1/claude_code/routines/trig_abc/fire",
            "https://api.anthropic.com/v1/claude_code/routines/trig_abc",
            "https://api.anthropic.com/v1/claude_code/routines/trig_abc/fire/",
            "https://api.anthropic.com/v1/claude_code/routines/fire",
            "https://api.anthropic.com/v1/claude_code/routines//fire",
            "https://api.anthropic.com/v1/claude_code/routines/abc123/fire",
            "https://api.anthropic.com/v1/claude_code/routines/trig_/fire",
            "https://api.anthropic.com/v1/claude_code/routines/trig_a%C3%A9b/fire",
            "https://api.anthropic.com/v1/claude_code/routines/trig_ab-c/fire",
            "https://api.anthropic.com/v1/claude_code/routines/trig_\(String(repeating: "a", count: 65))/fire",
            "",
        ])
    func rejectedURL(url: String) {
        #expect(RoutineCredentials(fireURL: url, token: goodToken) == nil)
    }

    @Test("A trigger ID of 64 characters is accepted")
    func longestTriggerID() {
        let url =
            "https://api.anthropic.com/v1/claude_code/routines/trig_\(String(repeating: "a", count: 64))/fire"
        #expect(RoutineCredentials(fireURL: url, token: goodToken) != nil)
    }

    @Test(
        "A token without the routine token's shape is rejected",
        arguments: [
            "abc123",
            "sk-ant-api03-abc",
            "sk-ant-oat01-",
            "sk-ant-oat01-ab cd",
            "sk-ant-oat01-ab\u{FF21}cd",
            "sk-ant-oat01-ab.cd",
            "sk-ant-oat01-" + String(repeating: "a", count: 501),
            "",
        ])
    func rejectedToken(token: String) {
        #expect(RoutineCredentials(fireURL: goodURL, token: token) == nil)
    }

    @Test("A token of 513 characters is accepted")
    func longestToken() {
        let token = "sk-ant-oat01-" + String(repeating: "a", count: 500)
        #expect(token.count == 513)
        #expect(RoutineCredentials(fireURL: goodURL, token: token) != nil)
    }

    @Test("The in-memory store saves, loads and deletes")
    func inMemoryStore() throws {
        let credentials = try #require(RoutineCredentials(fireURL: goodURL, token: goodToken))
        let store = InMemoryRoutineCredentialsStore()
        #expect(store.load() == nil)
        store.save(credentials)
        #expect(store.load() == credentials)
        store.delete()
        #expect(store.load() == nil)
    }

    @Test("Fire sends the documented request and returns the session URL")
    func request() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: sessionJSON)
        let url = try await client(http).fire(text: "hello \"world\"")
        #expect(url.absoluteString == "https://claude.ai/code/session_1")
        let sent = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(sent.method == .post)
        #expect(sent.url.absoluteString == goodURL)
        #expect(
            sent.headers == [
                "Authorization": "Bearer \(goodToken)",
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            ])
        #expect(sent.body == Data(#"{"text":"hello \"world\""}"#.utf8))
        #expect(sent.timeout == 30)
    }

    @Test("The shared send gives the same request and answer as fire")
    func sharedSend() async throws {
        let routine = try #require(RoutineCredentials(fireURL: goodURL, token: goodToken))
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: sessionJSON)
        http.enqueue(status: 200, json: sessionJSON)
        let sent = try await RoutineTriggerClient.send(text: "x", to: routine, http: http)
        let fired = try await client(http).fire(text: "x")
        #expect(sent == fired)
        #expect(http.requests[0] == http.requests[1])
    }

    @Test("isConfigured follows the stored credentials")
    func configured() {
        #expect(client(FakeHTTPClient()).isConfigured())
        #expect(!client(FakeHTTPClient(), stored: false).isConfigured())
    }

    @Test("Without credentials, or when the store cannot be read, fire is not configured")
    func notConfigured() async {
        let http = FakeHTTPClient()
        let stores: [any RoutineCredentialsStore] = [
            InMemoryRoutineCredentialsStore(), BrokenStore(),
        ]
        for store in stores {
            let trigger = RoutineTriggerClient(http: http, credentials: store)
            #expect(!trigger.isConfigured())
            await #expect(throws: RoutineTriggerError.notConfigured) {
                try await trigger.fire(text: "x")
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test(
        "Each status maps to its case",
        arguments: [
            (400, RoutineTriggerError.notStarted),
            (401, .rejectedToken),
            (403, .forbidden),
            (404, .notFound),
            (500, .unavailable),
            (503, .unavailable),
            (599, .unavailable),
            (201, .unexpectedResponse),
            (302, .unexpectedResponse),
            (409, .unexpectedResponse),
            (600, .unexpectedResponse),
        ])
    func statuses(status: Int, expected: RoutineTriggerError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: "{}")
        #expect(await failure(of: http) == expected)
    }

    @Test(
        "A 429 carries Retry-After as whole seconds when it has one",
        arguments: [
            (["Retry-After": "120"], TimeInterval?.some(120)),
            (["retry-after": "0"], 0),
            (["Retry-After": "soon"], nil),
            (["Retry-After": "-5"], nil),
            (["Retry-After": "1.5"], nil),
            ([:], nil),
        ])
    func rateLimited(headers: [String: String], retryAfter: TimeInterval?) async {
        let http = FakeHTTPClient()
        http.enqueue(status: 429, json: "{}", headers: headers)
        #expect(await failure(of: http) == .rateLimited(retryAfter: retryAfter))
    }

    @Test("A transport error is .network")
    func network() async {
        let http = FakeHTTPClient([.failure(Unrelated())])
        #expect(await failure(of: http) == .network)
    }

    @Test(
        "A 200 that is not a routine fire on claude.ai is unexpected",
        arguments: [
            #"{"type":"other","claude_code_session_url":"https://claude.ai/code/s"}"#,
            #"{"type":"routine_fire","claude_code_session_url":"https://example.com/code/s"}"#,
            #"{"type":"routine_fire","claude_code_session_url":"http://claude.ai/code/s"}"#,
            #"{"type":"routine_fire","claude_code_session_url":"not a url"}"#,
            #"{"type":"routine_fire"}"#,
            "not json",
        ])
    func unexpectedBody(json: String) async {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: json)
        #expect(await failure(of: http) == .unexpectedResponse)
    }

    @Test("The messages are word for word and never mention a token")
    func messages() {
        let all: [RoutineTriggerError] = [
            .notConfigured, .summaryNotConfigured, .rejectedToken, .notFound, .notStarted, .forbidden,
            .rateLimited(retryAfter: 5), .rateLimited(retryAfter: nil), .unavailable, .network,
            .unexpectedResponse,
        ]
        for error in all {
            #expect(!error.userMessage.contains("sk-ant"))
        }
        #expect(
            RoutineTriggerError.notConfigured.userMessage
                == "Add the end-of-day routine in Settings to send this day for processing.")
        #expect(
            RoutineTriggerError.summaryNotConfigured.userMessage
                == "A summary routine's trigger is missing. Save it again under the same name in Settings → Summary routines."
        )
        #expect(
            RoutineTriggerError.rejectedToken.userMessage
                == "Claude rejected the routine token. Generate a new token at claude.ai/code/routines and enter it in Settings."
        )
        #expect(
            RoutineTriggerError.notFound.userMessage
                == "That routine no longer exists. Check the fire URL in Settings.")
        #expect(
            RoutineTriggerError.notStarted.userMessage
                == "Claude didn't start the routine. Check that it isn't paused at claude.ai/code/routines."
        )
        #expect(
            RoutineTriggerError.forbidden.userMessage
                == "Your Claude account can't start routines. Check your plan and your organization's settings."
        )
        #expect(
            RoutineTriggerError.rateLimited(retryAfter: nil).userMessage
                == "Claude is limiting routine runs right now. Try again later.")
        #expect(
            RoutineTriggerError.unavailable.userMessage
                == "Claude is unavailable right now. Try again in a few minutes.")
        #expect(
            RoutineTriggerError.network.userMessage
                == "Couldn't reach Claude. Check your connection and try again.")
        #expect(
            RoutineTriggerError.unexpectedResponse.userMessage
                == "Claude sent an unexpected response. Try again later.")
    }
}
