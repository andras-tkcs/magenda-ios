// AppCore's Google Tasks client: the exact requests it sends and how it reads the recorded
// responses. Every name in the fixtures is made up.

import AppCore
import Foundation
import Testing

private let sep30 = CalendarDay(isoString: "2026-09-30") ?? CalendarDay.today(in: .gmt, now: .now)

@Suite("Google Tasks client")
struct GoogleTasksClientTests {
    @Test("The task list request asks for 100 lists")
    func listsRequest() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "task-lists")
        _ = try await GoogleTasksClient(sender: sender).taskLists()
        let request = try #require(sender.requests.first)
        #expect(
            request.url.absoluteString
                == "https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100")
        #expect(request.method == .get)
    }

    @Test("Task lists are read with their IDs and titles")
    func lists() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "task-lists")
        let lists = try await GoogleTasksClient(sender: sender).taskLists()
        #expect(
            lists == [
                GoogleTaskList(id: "list-claude-01", title: "Claude"),
                GoogleTaskList(id: "list-delegations-02", title: "Claude Delegations"),
            ])
    }

    @Test("The tasks request hides completed and hidden tasks and encodes the list ID")
    func tasksRequest() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "tasks")
        _ = try await GoogleTasksClient(sender: sender).openTasks(listID: "list#b")
        let request = try #require(sender.requests.first)
        #expect(
            request.url.absoluteString
                == "https://tasks.googleapis.com/tasks/v1/lists/list%23b/tasks"
                + "?showCompleted=false&showHidden=false&maxResults=100")
    }

    @Test("Tasks are read with the due day from the first ten characters")
    func tasks() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "tasks")
        let tasks = try await GoogleTasksClient(sender: sender).openTasks(listID: "list-claude-01")
        #expect(
            tasks == [
                GoogleTask(
                    id: "task-invoice", title: "Send the invoice", notes: "Use the new template",
                    status: "needsAction", due: sep30, position: "00000000000000000001"),
                GoogleTask(
                    id: "task-untitled", title: nil, notes: nil, status: "needsAction", due: nil,
                    position: "00000000000000000002"),
                GoogleTask(
                    id: "task-bad-due", title: "Ring the supplier", notes: nil,
                    status: "needsAction", due: nil, position: nil),
            ])
    }

    @Test("Two pages of tasks are read, the second asked for with the page token")
    func paging() async throws {
        let sender = FakeSender()
        sender.enqueue(
            json: #"{"items": [{"id": "t1", "status": "needsAction"}], "nextPageToken": "more"}"#)
        sender.enqueue(json: #"{"items": [{"id": "t2", "status": "needsAction"}]}"#)
        let tasks = try await GoogleTasksClient(sender: sender).openTasks(listID: "l")
        #expect(tasks.map(\.id) == ["t1", "t2"])
        let second = try #require(sender.requests.last).url.absoluteString
        #expect(second.hasSuffix("&maxResults=100&pageToken=more"))
    }

    @Test("A response with no items is an empty list")
    func empty() async throws {
        let sender = FakeSender()
        sender.enqueue(json: "{}")
        sender.enqueue(json: "{}")
        let client = GoogleTasksClient(sender: sender)
        #expect(try await client.taskLists().isEmpty)
        #expect(try await client.openTasks(listID: "l").isEmpty)
    }

    @Test("A task without an ID or status is an unexpected response")
    func malformed() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "tasks-malformed")
        await #expect(throws: GoogleAPIError.unexpectedResponse) {
            try await GoogleTasksClient(sender: sender).openTasks(listID: "l")
        }
    }

    @Test("An error from the sender passes through")
    func senderError() async throws {
        let sender = FakeSender([.failure(GoogleAPIError.forbidden)])
        await #expect(throws: GoogleAPIError.forbidden) {
            try await GoogleTasksClient(sender: sender).taskLists()
        }
    }

    @Test("Task lists and tasks are forwarded to the Tasks client")
    func forwards() async throws {
        let sender = FakeSender()
        try sender.enqueue(fixture: "task-lists")
        try sender.enqueue(fixture: "tasks")
        let source = LiveGoogleDataSource(
            calendar: GoogleCalendarClient(sender: sender),
            tasks: GoogleTasksClient(sender: sender))
        #expect(try await source.taskLists().count == 2)
        #expect(try await source.openTasks(listID: "list-claude-01").count == 3)
    }
}
