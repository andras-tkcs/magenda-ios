import Foundation

/// Reads task lists and tasks from the Google Tasks API.
public struct GoogleTasksClient: Sendable {
    private let sender: any AuthorizedHTTPSending

    /// Creates a client that sends through `sender`.
    public init(sender: any AuthorizedHTTPSending) {
        self.sender = sender
    }

    /// The person's task lists, in Google's order.
    public func taskLists() async throws -> [GoogleTaskList] {
        let pages = try await GoogleAPI.pages(
            TaskListsPage.self, sender: sender,
            url: GoogleAPI.url(host: "tasks.googleapis.com", path: "tasks/v1/users/@me/lists"),
            query: [URLQueryItem(name: "maxResults", value: "100")],
            nextPageToken: \.nextPageToken)
        return pages.flatMap { $0.items ?? [] }.map { GoogleTaskList(id: $0.id, title: $0.title) }
    }

    /// The tasks of `listID` that are neither completed nor hidden.
    public func openTasks(listID: String) async throws -> [GoogleTask] {
        let pages = try await GoogleAPI.pages(
            TasksPage.self, sender: sender,
            url: GoogleAPI.url(host: "tasks.googleapis.com", path: "tasks/v1/lists")
                .appending(path: listID).appending(path: "tasks"),
            query: [
                URLQueryItem(name: "showCompleted", value: "false"),
                URLQueryItem(name: "showHidden", value: "false"),
                URLQueryItem(name: "maxResults", value: "100"),
            ], nextPageToken: \.nextPageToken)
        return pages.flatMap { $0.items ?? [] }.map { item in
            GoogleTask(
                id: item.id, title: item.title, notes: item.notes, status: item.status,
                due: item.due.flatMap { CalendarDay(isoString: $0) }, position: item.position)
        }
    }
}

private struct TaskListsPage: Decodable {
    struct Item: Decodable {
        let id: String
        let title: String
    }

    let items: [Item]?
    let nextPageToken: String?
}

private struct TasksPage: Decodable {
    struct Item: Decodable {
        let id: String
        let title: String?
        let notes: String?
        let status: String
        let due: String?
        let position: String?
    }

    let items: [Item]?
    let nextPageToken: String?
}
