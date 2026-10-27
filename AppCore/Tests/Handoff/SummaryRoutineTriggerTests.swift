// AppCore's summary routine trigger: which routine's credentials a fire uses and what happens
// when they are missing. Every trigger ID and token here is made up.

import Foundation
import Testing

@testable import AppCore

private let urlOne = "https://api.anthropic.com/v1/claude_code/routines/trig_one/fire"
private let tokenOne = "sk-ant-oat01-one"
private let urlTwo = "https://api.anthropic.com/v1/claude_code/routines/trig_two/fire"
private let tokenTwo = "sk-ant-oat01-two"
private let sessionJSON =
    #"{"type":"routine_fire","claude_code_session_id":"s1","claude_code_session_url":"https://claude.ai/code/session_1"}"#

private struct Unrelated: Error {}

/// A store whose load always throws.
private struct BrokenStore: SummaryRoutineCredentialsStore {
    func load(id: String) throws -> RoutineCredentials? { throw Unrelated() }
    func save(_ credentials: RoutineCredentials, id: String) throws {}
    func delete(id: String) throws {}
}

@Suite("Summary routine trigger")
struct SummaryRoutineTriggerTests {
    @Test("A fire uses the routine's own URL and token")
    func ownToken() async throws {
        let store = InMemorySummaryRoutineCredentialsStore([
            "a": try #require(RoutineCredentials(fireURL: urlOne, token: tokenOne)),
            "b": try #require(RoutineCredentials(fireURL: urlTwo, token: tokenTwo)),
        ])
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: sessionJSON)
        let url = try await SummaryRoutineTriggerClient(http: http, credentials: store)
            .fire(text: "hi", routineID: "b")
        #expect(url.absoluteString == "https://claude.ai/code/session_1")
        let sent = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(sent.url.absoluteString == urlTwo)
        #expect(sent.headers["Authorization"] == "Bearer \(tokenTwo)")
        #expect(sent.body == Data(#"{"text":"hi"}"#.utf8))
    }

    @Test("An unknown routine or a store that cannot be read is not configured")
    func notConfigured() async {
        let http = FakeHTTPClient()
        let stores: [any SummaryRoutineCredentialsStore] = [
            InMemorySummaryRoutineCredentialsStore(), BrokenStore(),
        ]
        for store in stores {
            let client = SummaryRoutineTriggerClient(http: http, credentials: store)
            await #expect(throws: RoutineTriggerError.summaryNotConfigured) {
                try await client.fire(text: "x", routineID: "a")
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test("The in-memory store saves, loads and deletes by routine ID")
    func inMemoryStore() throws {
        let one = try #require(RoutineCredentials(fireURL: urlOne, token: tokenOne))
        let two = try #require(RoutineCredentials(fireURL: urlTwo, token: tokenTwo))
        let store = InMemorySummaryRoutineCredentialsStore()
        #expect(store.load(id: "a") == nil)
        store.save(one, id: "a")
        store.save(two, id: "b")
        #expect(store.load(id: "a") == one)
        #expect(store.load(id: "b") == two)
        store.delete(id: "a")
        #expect(store.load(id: "a") == nil)
        #expect(store.load(id: "b") == two)
    }
}
