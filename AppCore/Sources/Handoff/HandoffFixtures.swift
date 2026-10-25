import Foundation

/// What the fixture routine has been asked to do, per date for a day and per date and part for a
/// meeting. It stands in for the end-of-day
/// routine so UI tests and previews can walk a day through every Doc status.
public actor FixtureEndOfDay {
    private struct Fired {
        let step: String
        let hadSummarySkill: Bool
    }

    private var fired: [String: Fired] = [:]

    /// Creates a routine that has been asked for nothing.
    public init() {}

    /// Records the step in `payload` for its date, or its date and part. A payload that does not
    /// decode is recorded as nothing.
    public func record(payload: String) {
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: Data(payload.utf8)) else {
            return
        }
        let key = decoded.part.map { "\(decoded.date)-part-\($0)" } ?? decoded.date
        fired[key] = Fired(
            step: decoded.step,
            hadSummarySkill: decoded.pages.contains {
                $0.summarySkill != nil && $0.earlierPart == nil
            })
    }

    /// The text of a Doc as the routine would have left it; `key` is the date, or the date,
    /// "-part-" and the part's number.
    public func docText(forKey key: String) -> String {
        guard let last = fired[key] else { return "Status: Waiting for notes\n" }
        switch last.step {
        case "notes": return "Status: Notes ready for review\n"
        case "approve-notes":
            return last.hadSummarySkill
                ? "Status: Summary ready for review\n" : "Status: Closed\n"
        case "approve-summary": return "Status: Closed\n"
        default: return "Status: Waiting for notes\n"
        }
    }

    private struct Payload: Decodable {
        struct Page: Decodable {
            let summarySkill: String?
            let earlierPart: Int?
        }

        let date: String
        let step: String
        let part: Int?
        let pages: [Page]
    }
}

/// A Drive that files nothing and reports the Doc status the fixture routine would have left.
public struct FixtureDrive: DriveFiling {
    private let state: FixtureEndOfDay

    /// Creates a Drive whose Docs answer from `state`.
    public init(state: FixtureEndOfDay) {
        self.state = state
    }

    /// Always `folder-1`.
    public func folderID(named name: String) async throws -> String {
        "folder-1"
    }

    /// `file-<key>`, where the key is the date in `name` after `Magenda `, followed by `-part-<n>`
    /// for a meeting.
    public func uploadPDF(_ data: Data, name: String, folderID: String, replacing fileID: String?)
        async throws -> String
    {
        "file-" + Self.key(in: name)
    }

    /// `doc-<key>`, where the key is the date in `name` after `Magenda `, followed by `-part-<n>`
    /// for a meeting.
    public func createDoc(name: String, folderID: String, text: String) async throws -> String {
        "doc-" + Self.key(in: name)
    }

    /// The Doc's text from what the fixture routine has been asked to do for the Doc's key.
    public func exportText(ofDoc docID: String) async throws -> String {
        await state.docText(forKey: String(docID.dropFirst("doc-".count)))
    }

    /// `2026-10-26` for `Magenda 2026-10-26.pdf`, `2026-10-26-part-1` for
    /// `Magenda 2026-10-26 part 1 notes`.
    private static func key(in name: String) -> String {
        var key = String(name.dropFirst("Magenda ".count))
        for suffix in [".pdf", " notes"] where key.hasSuffix(suffix) {
            key.removeLast(suffix.count)
        }
        return key.replacingOccurrences(of: " part ", with: "-part-")
    }
}

/// A routine trigger that records what it is asked into a `FixtureEndOfDay`.
public struct FixtureRoutineTrigger: RoutineFiring {
    private let state: FixtureEndOfDay
    private let credentials: any RoutineCredentialsStore

    /// Creates a trigger that records into `state` while `credentials` holds a routine.
    public init(state: FixtureEndOfDay, credentials: any RoutineCredentialsStore) {
        self.state = state
        self.credentials = credentials
    }

    /// Whether `credentials` holds a routine right now.
    public func isConfigured() -> Bool {
        stored()
    }

    /// Records `text` and returns a made-up session URL; throws `notConfigured` without a routine.
    public func fire(text: String) async throws -> URL {
        guard stored() else { throw RoutineTriggerError.notConfigured }
        await state.record(payload: text)
        return GoogleAPI.url(host: "claude.ai", path: "/code/session_fixture")
    }

    // Read on every call so saving or forgetting the routine takes effect at once.
    private func stored() -> Bool {
        (try? credentials.load()) != nil
    }
}
