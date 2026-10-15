// AppCore's discussion-task detection.

import AppCore
import Testing

@Suite("Task titles")
struct TaskTitleTests {
    @Test(
        "Discussion titles and the name they carry",
        arguments: [
            ("Peter – to be discussed", "Peter"),
            ("Zoltán - TBD", "Zoltán"),
            ("Nora: to be discussed", "Nora"),
            ("Anna—tbd", "Anna"),
        ])
    func named(title: String, name: String) {
        #expect(TaskTitle.isDiscussion(title))
        #expect(TaskTitle.discussionName(title) == name)
    }

    @Test(
        "Discussion titles without a name",
        arguments: ["TBD", "Prepare TBD list", "Budget to be discussed"])
    func unnamed(title: String) {
        #expect(TaskTitle.isDiscussion(title))
        #expect(TaskTitle.discussionName(title) == nil)
    }

    @Test(
        "Other titles are not discussions",
        arguments: ["Call the bank", "Todo: be discussed later"])
    func notDiscussions(title: String) {
        #expect(!TaskTitle.isDiscussion(title))
        #expect(TaskTitle.discussionName(title) == nil)
    }
}
