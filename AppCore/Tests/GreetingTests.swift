// AppCore's `Greeting`: the text the main screen shows for a typed name.

import AppCore
import Testing

@Suite("Greeting a typed name")
struct GreetingTests {
    @Test("A name is greeted with surrounding whitespace removed")
    func greetsTheTrimmedName() {
        #expect(Greeting.message(for: "  Ada \n") == "Hello, Ada!")
    }

    @Test("A blank name gets the generic greeting", arguments: ["", "   ", "\n\t"])
    func blankNamesGetTheGenericGreeting(name: String) {
        #expect(Greeting.message(for: name) == "Hello!")
    }

    @Test("A long name is cut to the maximum length")
    func longNamesAreCut() {
        let long = String(repeating: "a", count: Greeting.maximumNameLength + 10)
        let expected = "Hello, \(String(repeating: "a", count: Greeting.maximumNameLength))!"
        #expect(Greeting.message(for: long) == expected)
    }
}
