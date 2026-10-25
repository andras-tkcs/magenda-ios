// AppCore's Drive folder name rules.

import AppCore
import Testing

@Suite("Drive folder name")
struct DriveFolderNameTests {
    @Test("validated trims whitespace and newlines")
    func trims() {
        #expect(DriveFolderName.validated("  Work notes \n") == "Work notes")
    }

    @Test("validated accepts 100 characters and refuses 101")
    func length() {
        #expect(DriveFolderName.validated(String(repeating: "a", count: 100)) != nil)
        #expect(DriveFolderName.validated(String(repeating: "a", count: 101)) == nil)
    }

    @Test("validated refuses an empty name, a slash, a backslash and a control character",
        arguments: ["", "   ", "a/b", "a\\b", "a\u{0007}b"])
    func refuses(text: String) {
        #expect(DriveFolderName.validated(text) == nil)
    }

    @Test("The default is Magenda and is itself valid")
    func defaultName() {
        #expect(DriveFolderName.default == "Magenda")
        #expect(DriveFolderName.validated(DriveFolderName.default) == "Magenda")
    }

    @Test("The limit and the message")
    func constants() {
        #expect(DriveFolderName.maxLength == 100)
        #expect(DriveFolderName.invalidMessage == "Use 1 to 100 characters, without a slash.")
    }
}
