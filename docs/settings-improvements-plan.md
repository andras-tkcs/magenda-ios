# Settings improvements: visible delete, People from Contacts, a named Drive folder

> **Orchestrator: this plan's PR is stacked.** It runs at the same time as the
> `plan/send-meeting-early` plan (feature branch `feature/send-meeting-early`). Its last phase,
> `p6-stack`, merges that branch into this one, and the pull request opens with **base
> `feature/send-meeting-early`, not `main`**. Read "Stacked on send-meeting-early" below before
> section 5 (final review) and section 6 (finishing) of `/implement`; it overrides them where they
> say `main`.

## Goal

Three changes to Settings, asked for together:

1. **Deleting rules is discoverable.** Every list on Settings → Binder rules (Personal blocks,
   Title prefixes, Out-of-office words such as `PTO`, Short meeting names, Meeting summaries,
   People) can already be swiped left to delete, default and added entries alike, but nothing on
   screen says so. The screen gets an **Edit** button (red delete circles on every deletable row)
   and a long-press **Delete** menu on each row. Swipe stays.
2. **People from Contacts.** The People section (a name used in tasks → an attendee's email) gets a
   **Choose from Contacts…** button. It opens the system contact picker; picking an email fills
   the name and email fields, which the person can still edit before **Add**. No permission prompt,
   no new Google scope.
3. **The Drive folder is named in Settings.** Finished days upload to a folder called `Magenda`
   today, fixed in code, and Settings never says so. Settings gets a **Google Drive** section with
   an editable folder name and a footer saying where days go. A new name makes (or finds) a folder
   with that name; a day keeps the folder it was first uploaded to; the routine payload names the
   folder by ID.

## Current state

- **Rules editor** — `App/Screens/RulesView.swift` (320 lines). The three plain-string lists share
  `listSection(_:)` (`:102`) with `.onDelete` (`:109`); short names (`:170`), summaries (`:204`)
  and people (`:268`) each have their own `.onDelete`. There is no toolbar, `EditButton` or context
  menu anywhere in `App/`. `BinderRules.default` (`AppCore/Sources/Settings/BinderRules.swift:36`)
  holds the defaults (`outOfOfficeWords: ["OOO", "Out of Office", "Vacation", "PTO"]`); a deleted
  default stays deleted because the stored array is decoded as is (`:53`). **Reset rules**
  (`RulesView.swift:81`) restores them. `AppUITests/RulesUITests.swift` already deletes by swipe
  (`testDeletingAPersonalBlockBringsItsEventsBack`, `:167`) and has the helpers `element`,
  `waitUntil`, `openRules`, `closeSettings`, `reveal`, `enter` (`:144`).
- **People** — `RulesView.peopleSection` (`:261`) and `addPerson()` (`:294`): the key is
  `BinderText.fold` of the trimmed name, the email trimmed and lowercased, both required, saved to
  `BinderRules.personAliases`, which `TaskSelection` uses (`AppCore/Sources/Draft/TaskSelection.swift:93`).
  The app has no Contacts code, no `NSContactsUsageDescription`, and `App/PrivacyInfo.xcprivacy`
  lists no Contacts data.
- **Drive folder** — `HandoffController.folderName = "Magenda"` (`AppCore/Sources/Handoff/HandoffController.swift:28`)
  is the only folder input; `runPipeline` looks it up on every upload (`:222`) with
  `DriveFiling.folderID(named:)`, which finds the first non-trashed folder with that name that the
  app can see, anywhere in My Drive, or creates one in the root
  (`AppCore/Sources/Google/GoogleDriveClient.swift:32`). With `drive.file` (ADR 0027) Magenda sees
  only folders it created, so picking an existing folder of the person's is not possible without a
  broader scope. `DayHandoff` (`AppCore/Sources/Handoff/DayHandoff.swift:123`) records
  `driveFileID` and `docID` but no folder; its `Payload` (`:273`) is schema
  `magenda.end-of-day/1`. `docs/end-of-day-handoff.md:84` tells the routine to check that the PDF
  "sits in the `Magenda` folder". README.md `:77` says the same.
- **Settings** — `AgendaSettings` (`AppCore/Sources/Settings/AgendaSettings.swift`) is saved by
  `AgendaController.updateSettings` (`AgendaController.swift:258`), which clears the rendered PDF on
  every change (`invalidateRendered()`, `:264`). `HandoffController` has no access to settings; it
  is built in `App/AppEnvironment.swift:63` (fixtures) and `:92` (live), after the
  `AgendaController`.
- **Coverage** — `scripts/check_coverage_floor.py` has `OVERALL_FLOOR = 100.0`: every new AppCore
  line must be covered.
- **Work in flight on the same files** — PR https://github.com/andras-tkcs/magenda-ios/pull/14
  (Reset Hand-off, ADR 0032) and the plan on `plan/send-meeting-early` (ADRs 0033–0035, payload
  schema `/2`, meeting PDFs in Drive) both change `HandoffController.swift`, `DayHandoff.swift` and
  `docs/end-of-day-handoff.md`. This plan therefore takes ADRs **0036** and **0037**, and phase
  `p3` has stop conditions for when that work has landed first.

## Design

### D1. Discoverable delete (RulesView)

- `RulesView.ID` gains `static let editButton = "rulesEditButton"` and
  `static let deleteAction = "rulesDeleteAction"`.
- `body`'s `Form` gets
  `.toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton().accessibilityIdentifier(ID.editButton) } }`.
  SwiftUI's `EditButton` toggles the environment edit mode; rows with `.onDelete` show the red
  delete circles. (The settings sheet's own Done button belongs to `SettingsView`'s form and is not
  shown on the pushed rules screen, so the trailing slot is free.)
- Each `.onDelete` body moves into a private method taking `IndexSet`, so swipe, Edit and the menu
  share it:
  - `delete(_ offsets: IndexSet, from section: ListSection)` — `$0.rules[keyPath: section.keyPath].remove(atOffsets: offsets)`.
  - `deleteShortNames(_ offsets: IndexSet, in entries: [(key: String, name: String)])`
  - `deleteSummaries(_ offsets: IndexSet, in entries: [(title: String, skill: String)])`
  - `deletePeople(_ offsets: IndexSet, in entries: [(key: String, email: String)])`

  each with the body the closure has today, inside `Task { await controller.updateSettings { … } }`.
- One private helper on the view:

  ```swift
  /// A long-press menu with Delete, the same as swiping the row away.
  private func deleteMenu(_ delete: @escaping () -> Void) -> some View {
      Button("Delete", systemImage: "trash", role: .destructive, action: delete)
          .accessibilityIdentifier(ID.deleteAction)
  }
  ```

  and every row view inside the four `ForEach`es gets
  `.contextMenu { deleteMenu { <method>(IndexSet(integer: index), …) } }`, placed **before** its
  existing `.accessibilityIdentifier(...)`.
- No footer text changes. No AppCore change. No ADR.

### D2. People from Contacts

**AppCore** — new file `AppCore/Sources/Settings/PersonAlias.swift`:

```swift
import Foundation

/// One entry of the People rules: a name used in tasks and the attendee email it stands for.
public struct PersonAlias: Equatable, Sendable {
    /// `BinderText.fold` of the trimmed name; the key in `BinderRules.personAliases`.
    public let key: String
    /// The trimmed, lowercased email.
    public let email: String

    /// An alias from what the person typed; nil when the name or the email is blank once trimmed.
    public init?(name: String, email: String)
}

/// One email address picked from the person's contacts, with the contact's names.
public struct PickedContact: Equatable, Sendable {
    public let givenName: String
    public let nickname: String
    public let familyName: String
    public let email: String
    public init(givenName: String, nickname: String, familyName: String, email: String)

    /// The name to put in "Name in tasks": the nickname, else the given name, else the family
    /// name, trimmed; empty when the contact has none.
    public var suggestedName: String

    /// The contact the UI-test fixtures and previews pick.
    public static let fixture = PickedContact(
        givenName: "Nora", nickname: "", familyName: "Kim", email: "nora.kim@example.com")
}

/// Asks the person to pick one email address from their contacts.
public protocol ContactPicking: Sendable {
    /// The picked contact, or nil when the person cancels or no picker can be shown.
    @MainActor func pickContact() async -> PickedContact?
}

/// A picker for UI tests and previews that always picks `PickedContact.fixture`.
public struct FixtureContactPicker: ContactPicking {
    public init() {}
    public func pickContact() async -> PickedContact? { .fixture }
}
```

Every `public` declaration gets a `///` comment (the ones shown, plus one per `PickedContact`
property). Trimming is `.whitespacesAndNewlines` throughout.

**App** — new file `App/Platform/ContactPicker.swift`, the live picker and the environment value:

```swift
import AppCore
import ContactsUI
import SwiftUI
import UIKit

/// Presents the system contact picker over the frontmost view controller. The picker runs out of
/// process and needs no Contacts permission.
@MainActor
final class SystemContactPicker: NSObject, ContactPicking, CNContactPickerDelegate {
    private var continuation: CheckedContinuation<PickedContact?, Never>?

    func pickContact() async -> PickedContact? {
        guard continuation == nil, let presenter = Self.frontmostViewController() else {
            return nil
        }
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(format: "emailAddresses.@count == 1")
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'emailAddresses'")
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            presenter.present(picker, animated: true)
        }
    }

    // The delegate is called on the main thread; the methods are nonisolated so the conformance
    // compiles whether or not the SDK marks the protocol main-actor isolated.
    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let picked = Self.picked(contact, email: contact.emailAddresses.first.map { String($0.value) })
        MainActor.assumeIsolated { finish(picked) }
    }

    nonisolated func contactPicker(
        _ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty
    ) {
        let picked = Self.picked(contactProperty.contact, email: contactProperty.value as? String)
        MainActor.assumeIsolated { finish(picked) }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        MainActor.assumeIsolated { finish(nil) }
    }

    private func finish(_ picked: PickedContact?) {
        continuation?.resume(returning: picked)
        continuation = nil
    }

    /// Reads only the keys the picker fetched; reading another one would raise.
    private nonisolated static func picked(_ contact: CNContact, email: String?) -> PickedContact? {
        guard let email, !email.isEmpty else { return nil }
        func value(_ key: String, _ read: (CNContact) -> String) -> String {
            contact.isKeyAvailable(key) ? read(contact) : ""
        }
        return PickedContact(
            givenName: value(CNContactGivenNameKey) { $0.givenName },
            nickname: value(CNContactNicknameKey) { $0.nickname },
            familyName: value(CNContactFamilyNameKey) { $0.familyName },
            email: email)
    }

    private static func frontmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension EnvironmentValues {
    /// Picks an email from the person's contacts; nil in previews that have none.
    @Entry var contactPicker: (any ContactPicking)?
}
```

- `AppServices` (`App/AppEnvironment.swift:5`) gains `let contactPicker: any ContactPicking`; the
  fixture branch passes `FixtureContactPicker()`, the live branch `SystemContactPicker()`.
- `App/MagendaApp.swift` adds `.environment(\.contactPicker, services.contactPicker)` after the
  `\.allowsFingerDrawing` line.
- `RulesView`: `@Environment(\.contactPicker) private var contactPicker`; `ID` gains
  `static let peopleFromContacts = "peopleFromContacts"`. In `peopleSection`, between the Email
  field and the Add button:

  ```swift
  if let contactPicker {
      Button("Choose from Contacts…") {
          Task {
              guard let picked = await contactPicker.pickContact() else { return }
              personName = picked.suggestedName
              personEmail = picked.email
          }
      }
      .accessibilityIdentifier(ID.peopleFromContacts)
  }
  ```

  `addPerson()` becomes: `guard let alias = PersonAlias(name: personName, email: personEmail) else { return }`,
  clear both fields, then `$0.rules.personAliases[alias.key] = alias.email`. The People footer
  becomes: `"Matches “Name – to be discussed” tasks to meeting attendees whose first name differs. Choose from Contacts fills in a name and email you can still change."`
- The `#Preview` of `RulesView` adds `.environment(\.contactPicker, FixtureContactPicker())`.
- No `project.yml`, Info.plist or `PrivacyInfo.xcprivacy` change: `CNContactPickerViewController`
  needs no usage description, and the picked email stays on the device in the settings, as typed
  ones do today. ContactsUI is auto-linked by `import`.

Rejected (goes into ADR 0037): **live autocomplete from the Contacts database** (needs
`CNContactStore` access, the permission prompt, a usage string and App Store privacy answers, for
a list typed a handful of times); **Google People API / Workspace directory** (a fourth OAuth
scope, everyone signs in again as with ADR 0027, and a Cloud console change); **suggesting from
meeting attendees** (only covers people already met, and attendees carry no first names).

### D3. A named Drive folder

**AppCore** — new file `AppCore/Sources/Settings/DriveFolderName.swift`:

```swift
/// The name of the Google Drive folder finished days are uploaded to.
public enum DriveFolderName {
    /// The folder a fresh install uploads to.
    public static let `default` = "Magenda"
    /// The longest name accepted, in characters.
    public static let maxLength = 100
    /// What Settings shows when `validated` returns nil.
    public static let invalidMessage = "Use 1 to 100 characters, without a slash."

    /// `text` trimmed of whitespace and newlines; nil when that is empty, longer than
    /// `maxLength` characters, or contains "/", "\" or a control character.
    public static func validated(_ text: String) -> String?
}
```

A control character is any scalar in `CharacterSet.controlCharacters`. `/` and `\` are refused so
nobody types a path expecting nested folders.

- `AgendaSettings` gains `public var driveFolderName: String` ("The name of the Google Drive
  folder finished days are uploaded to."), init parameter `driveFolderName: String = DriveFolderName.default`
  as the last parameter, `CodingKeys.driveFolderName`, and in `init(from:)`:
  `driveFolderName: DriveFolderName.validated(try value(.driveFolderName, defaults.driveFolderName)) ?? defaults.driveFolderName`.
- `AgendaController.updateSettings` clears the rendered PDF only when something besides the folder
  name changed: replace the bare `invalidateRendered()` with

  ```swift
  var drawnBefore = before
  drawnBefore.driveFolderName = after.driveFolderName
  if after != drawnBefore {
      invalidateRendered()
  }
  ```

- `DayHandoff` gains `public var folderID: String?` ("The Drive folder holding the PDF and the
  Doc; set by the first upload."), `CodingKeys.folderID`, `folderID = try container.decodeIfPresent(String.self, forKey: .folderID)`
  in `init(from:)`. `formatVersion` stays 1: the field is optional and older records decode with
  nil. `Payload` gains `let folderID: String?` set from `handoff.folderID`; a nil optional is left
  out of the JSON like `driveFileID`. The schema string does not change: the key is additive.
- `HandoffController`:
  - delete `private static let folderName = "Magenda"`;
  - add `@ObservationIgnored private let folderName: @MainActor () -> String` and the init
    parameter `folderName: @escaping @MainActor () -> String = { DriveFolderName.default }` as the
    **last** parameter (after `removeFile`), documented in the init's comment as "`folderName` is
    read at each first upload of a day";
  - in `runPipeline`, replace `let folderID = try await drive.folderID(named: Self.folderName)` with

    ```swift
    let folderID: String
    if let known = handoff.folderID {
        folderID = known
    } else {
        folderID = try await drive.folderID(named: folderName())
        handoff.folderID = folderID
    }
    ```

  - in `finish`, next to `handoff.docID = earlier?.docID`, add `handoff.folderID = earlier?.folderID`.
- `App/AppEnvironment.swift`: both `HandoffController(...)` calls pass
  `folderName: { controller.settings.driveFolderName }`.

**Settings UI** — `SettingsView`:

- `ID` gains `driveFolderField = "driveFolderField"`, `driveFolderError = "driveFolderError"`,
  `driveFolderFooter = "driveFolderFooter"`.
- State: `@State private var folderDraft = ""`, `@State private var folderInvalid = false`.
- `body` puts `driveSection` between `clientSection` and `routineSection`; `.onAppear` also sets
  `folderDraft = controller.settings.driveFolderName`.
- The section:

  ```swift
  private var driveSection: some View {
      Section {
          TextField("Folder name", text: $folderDraft)
              .autocorrectionDisabled()
              .submitLabel(.done)
              .onSubmit(commitFolder)
              .onChange(of: folderDraft) { folderInvalid = false }
              .accessibilityIdentifier(ID.driveFolderField)
          if folderInvalid {
              Text(DriveFolderName.invalidMessage)
                  .font(.footnote)
                  .foregroundStyle(.red)
                  .accessibilityIdentifier(ID.driveFolderError)
          }
      } header: {
          Text("Google Drive")
      } footer: {
          Text(
              "Finished days upload to the “\(controller.settings.driveFolderName)” folder in your Google Drive, which Magenda creates. A new name makes a new folder; days already uploaded stay where they are."
          )
          .accessibilityIdentifier(ID.driveFolderFooter)
      }
  }

  private func commitFolder() {
      guard let name = DriveFolderName.validated(folderDraft) else {
          folderInvalid = true
          return
      }
      folderInvalid = false
      folderDraft = name
      Task { await controller.updateSettings { $0.driveFolderName = name } }
  }
  ```

  (`onChange` runs before `onSubmit` sets `folderInvalid`, so the error shows after a bad submit
  and goes away on the next keystroke.)
- The routine footer's first sentence becomes `"Finished days upload to Google Drive (see above)."`;
  the rest stays.

**Routine contract** (`docs/end-of-day-handoff.md`, retire phase): the Drive layout table's folder
row reads ``the folder named in Settings → Google Drive (`Magenda` unless changed)`` and "Where" is
"anywhere in the person's Drive; created in the root"; the payload example gains
`"folderID": "1FoLdErIdExampleXyZ"` between `driveFileID` and `pageCount`; the field list says
`folderID`: the Drive folder holding the PDF and the Doc, left out on days uploaded before Magenda
recorded it; the `notes` step says "check that the file's parent is `folderID` (on a day without
`folderID`, a folder named `Magenda`)".

Rejected (goes into ADR 0036): **picking an existing folder** (needs the full `drive` scope or
the Google Picker, which has no iOS SDK, and moves the trust boundary of ADR 0027); **a fixed name
with a Settings row only showing it** (the user asked to change it); **a path with `/` creating
nested folders** (more Drive calls for little gain; the person can move the folder anywhere in
Drive and `folderID(named:)` still finds it there); **moving earlier days when the name changes**
(the routine has already checked them in place); **bumping the schema to `/2`** (the key is
additive and optional).

## ADRs

Numbers 0032–0035 are claimed by https://github.com/andras-tkcs/magenda-ios/pull/14 and the
`plan/send-meeting-early` branch. If either number below already exists in `docs/adr/` when the
retire phase runs, it takes the next free numbers instead and says so in its commit message.

- **ADR 0036**: Finished days upload to a Drive folder named in Settings (default `Magenda`); a
  day keeps the folder of its first upload, and the routine payload carries its `folderID`. Amends
  ADR 0027 (decision 1, the fixed folder name). Rejected alternatives as in D3.
- **ADR 0037**: People rules are filled from the system contact picker, which needs no Contacts
  permission; no live autocomplete, no People API scope. Rejected alternatives as in D2.

D1 (Edit button and menu) is a UI detail and gets no ADR.

## Manual steps

Nothing before implementation. After the last phase merges, the user (see the
[step-by-step page](https://claude.ai/artifact/S74KrbcUnjutV3A6etXSo1)):

- **ma1** — on a real iPhone or iPad, Choose from Contacts picks a contact's email and fills the
  People fields (CI uses a fake picker; the simulator's system picker is out of process).
- **ma2** — rename the Drive folder in Settings, finish a day, and check Drive has the new folder
  holding the PDF and the Doc.
- **ma3** — update the end-of-day routine's skill (outside this repository) to check the PDF's
  parent against the payload's `folderID`, per `docs/end-of-day-handoff.md`.

## Risks and open questions

- **send-meeting-early or Reset Hand-off landed first.** `p3` then finds a different
  `HandoffController`/`DayHandoff`. The brief's stop conditions: more than one
  `drive.folderID(named:` call, or a `Payload` schema other than `magenda.end-of-day/1`, means
  stop with `status=blocked` and report what was found; the orchestrator re-plans `p3` against the
  new code.
- **`CNContactPickerDelegate` isolation.** The nonisolated methods plus `MainActor.assumeIsolated`
  compile whether or not the SDK marks the protocol `@MainActor`. If the `app` jobs still fail to
  compile `ContactPicker.swift` with a concurrency error, the worker stops with `status=blocked`
  and pastes the compiler error; it does not add `@preconcurrency`, `@unchecked Sendable` or
  `nonisolated(unsafe)` on its own.
- **Edit mode delete circles in UI tests.** Their accessibility labels differ between iOS
  versions, so the UI tests delete through the long-press menu (by identifier) and only check that
  Edit toggles; a worker that finds `rulesDeleteAction` never appears after a long press on the
  iPad shard stops with `status=blocked` rather than switching to coordinate taps.
- **Folder lookup by name across renames.** Renaming back to an earlier name finds that earlier
  folder again (it is still Magenda's). That is intended and covered by the footer's wording.

- **The stacking merge.** `p6-stack` merges another plan's hand-off work into this one; it is the
  one phase on Opus. If send-meeting-early is still being built, the PR is stacked on its current
  head and the orchestrator merges later commits in as they land ("Stacked on send-meeting-early",
  Finishing step 5).

## Stacked on send-meeting-early

The user runs this plan and `plan/send-meeting-early` in parallel overnight and wants two stacked
pull requests in the morning: send-meeting-early's PR to `main`, and this one on top of it.

**Phases p1–p5 are built on `main`** exactly as written; their stop conditions about "other
hand-off work landed first" refer to `main`. Only `p6-stack` brings the other branch in.

**When `p6-stack` can start** (it depends on `p5-retire`, and on the other branch existing):

1. `git ls-remote origin feature/send-meeting-early`. If it prints nothing, the other plan has
   not cut its feature branch yet: do not start `p6-stack`; arm a check-in in 30 minutes and look
   again. Keep doing this for up to 8 hours.
2. Start `p6-stack` as soon as the branch exists, even if send-meeting-early's PR is not open or
   its phases are not all merged: stack on what is there.
3. After 8 hours without the branch, skip `p6-stack`, open this PR to `main` as `/implement`
   normally does, and say in the PR's first line and in your final message that it could not be
   stacked because `feature/send-meeting-early` never appeared.

**Final review** (`/implement` section 5): in the review prompt, replace
`git diff origin/main...HEAD` with `git diff origin/feature/send-meeting-early...HEAD`, and add:
"The branch is stacked on feature/send-meeting-early; review only this plan's changes and the
conflict resolutions of the `Plan-Phase: settings-improvements/p6-stack` merge."

**Finishing** (`/implement` section 6), in this order:

1. Look for the other PR: GitHub MCP `list_pull_requests` with `head:
   andras-tkcs:feature/send-meeting-early`, state open.
2. `git fetch origin feature/send-meeting-early`. If it has commits the feature branch lacks
   (`git rev-list --count HEAD..origin/feature/send-meeting-early` is not 0), merge it again into
   the feature branch with a merge commit (never a rebase), resolving conflicts by the rules in
   `p6-stack`'s brief, re-run the fast checks, and push.
3. Open this PR with `base: feature/send-meeting-early`. The body's first lines are:
   `Stacked on <other PR URL> — merge that first; GitHub then retargets this PR to main.` (or,
   without an open PR, `Stacked on the feature/send-meeting-early branch; its PR is not open yet.`).
   The rest of the body is as `/implement` says.
4. If the other PR exists, add one comment on it: `<this PR URL> is stacked on this one.` ending
   with the attribution footer.
5. Drive this PR to green as usual. Whenever `feature/send-meeting-early` gets new commits (a
   check-in, or a notice on the PR), merge it in again as in step 2 and push. When the other PR
   merges, GitHub retargets this PR to `main`; then merge `origin/main` in and push.
6. The final message names both PR URLs, in merge order.

## Implementation manifest

```yaml
plan_slug: settings-improvements
feature_branch: feature/settings-improvements
max_parallel: 2
manual_steps_artifact: https://claude.ai/artifact/S74KrbcUnjutV3A6etXSo1
manual_steps_source: docs/settings-improvements-plan-manual-steps.html
manual_before: []
manual_after:
  - id: ma1-contact-picker-on-device
    title: On a real iPhone or iPad, Settings → Binder rules → People → Choose from Contacts… fills the name and email of a picked contact
    why: CI swaps in FixtureContactPicker; only a device shows the real system picker and real contacts
  - id: ma2-renamed-drive-folder
    title: Rename the Drive folder in Settings, finish a day on iPad, and find its PDF and Doc in the new folder in Google Drive
    why: CI has no Google account (ADR 0013); only a real upload proves the folder is created and used
  - id: ma3-routine-checks-folder-id
    title: Update the end-of-day routine's skill to check the PDF's parent against the payload's folderID
    why: The routine lives outside this repository; with a renamed folder its old check for a folder named Magenda would stop every day
verify_after_merge:
  - swift test --package-path AppCore --filter "Settings|Handoff|AgendaController"
  - swift format lint --strict --parallel --recursive App AppTests AppUITests AppCore/Package.swift AppCore/Sources AppCore/Tests
  - python3 -m unittest discover -s scripts/tests
final_checks:
  - docs/settings-improvements-plan.md and docs/settings-improvements-plan-manual-steps.html are deleted and nothing links to them
  - docs/adr/0036-*.md and docs/adr/0037-*.md (or the next free numbers, as the retire commit says) exist, are Accepted, and are in docs/adr/README.md's index
  - ADR 0027 has exactly one added Status line pointing to the folder ADR, and no other change
  - CHANGELOG.md has [Unreleased] entries for all three changes and no version heading
  - tests.yml is green on the feature branch head, all core, lint, scripts, app and ui jobs
  - origin/feature/send-meeting-early is an ancestor of the feature branch head (`git merge-base --is-ancestor origin/feature/send-meeting-early HEAD`), unless the plan's 8-hour fallback applied
  - the PR opens with base feature/send-meeting-early and its body starts with the "Stacked on" line from the plan's "Stacked on send-meeting-early" section
phases:
  - id: p1-rules-delete
    title: Edit button and long-press Delete on every Binder rules list
    depends_on: []
    complexity: S
    touches:
      - App/Screens/RulesView.swift
      - AppUITests/RulesUITests.swift
    brief: |
      Implement the plan's Design section D1 exactly. No AppCore change.
      1. In App/Screens/RulesView.swift add `editButton` and `deleteAction` to `ID` with the
         values in D1.
      2. Move the bodies of the four `.onDelete` closures (listSection, shortNamesSection,
         summariesSection, peopleSection) into the private methods `delete(_:from:)`,
         `deleteShortNames(_:in:)`, `deleteSummaries(_:in:)` and `deletePeople(_:in:)` named in
         D1, and make each `.onDelete` call its method. Behavior stays identical.
      3. Add the `deleteMenu(_:)` helper from D1, and give each row view inside the four
         `ForEach`es `.contextMenu { deleteMenu { <its method>(IndexSet(integer: index), ...) } }`
         before its `.accessibilityIdentifier`. For listSection the row is the `Text(item)`; for
         the other three it is the existing row view (the `VStack` or `Text`).
      4. Add the `.toolbar` with the `EditButton` from D1 to the `Form` in `body`, next to
         `.navigationTitle`.
      5. In AppUITests/RulesUITests.swift add two tests, using the file's existing helpers
         (`launch`, `openRules`, `element`, `reveal`, `waitUntil`):
         a. `testLongPressDeletesADefaultOutOfOfficeWord`: open the rules, `reveal` the row
            `rulesRow.outOfOfficeWords.3`, assert its label is "PTO", `press(forDuration: 1.2)`
            on it, wait up to 10 s for `app.buttons["rulesDeleteAction"].firstMatch` and tap it,
            then wait (XCTNSPredicateExpectation, 30 s) until `rulesRow.outOfOfficeWords.3`
            does not exist, and assert `rulesRow.outOfOfficeWords.2` still has label "Vacation".
            Retry the press at most 3 times if the menu button does not appear, like the swipe
            loop at `testDeletingAPersonalBlockBringsItsEventsBack`.
         b. `testEditTogglesTheRulesIntoEditing`: open the rules, wait for
            `app.buttons["rulesEditButton"].firstMatch`, tap it, then `waitUntil(button,
            "label == %@", "Done")`; tap it again and `waitUntil(button, "label == %@", "Edit")`.
         Give each a `///` comment saying what it guards.
      6. Commit with a message saying the rules lists get an Edit button and a long-press Delete.
      Do not add a CHANGELOG line; the retire phase writes it.
      Stop condition: if after a long press on the iPad `ui` shard `rulesDeleteAction` never
      appears, stop with status=blocked and include the job log excerpt; do not switch to
      coordinate taps or remove the test.
    acceptance:
      - "`grep -c 'contextMenu' App/Screens/RulesView.swift` prints 4"
      - "`grep -c 'onDelete' App/Screens/RulesView.swift` prints 4"
      - "`grep -n 'EditButton()' App/Screens/RulesView.swift` finds one line"
      - swift format lint --strict passes over App and AppUITests (the tests.yml lint job on the phase branch)
      - tests.yml dispatched on the phase branch is green, including RulesUITests testLongPressDeletesADefaultOutOfOfficeWord and testEditTogglesTheRulesIntoEditing on every ui shard that runs RulesUITests

  - id: p2-contact-picker
    title: Choose from Contacts in the People rules
    depends_on: [p1-rules-delete]
    complexity: M
    touches:
      - AppCore/Sources/Settings/PersonAlias.swift
      - AppCore/Tests/Settings/PersonAliasTests.swift
      - App/Platform/ContactPicker.swift
      - App/AppEnvironment.swift
      - App/MagendaApp.swift
      - App/Screens/RulesView.swift
      - AppUITests/RulesUITests.swift
    brief: |
      Implement the plan's Design section D2 exactly; every name, string and the full
      SystemContactPicker code are there.
      1. Create AppCore/Sources/Settings/PersonAlias.swift with `PersonAlias`, `PickedContact`,
         `ContactPicking` and `FixtureContactPicker` as in D2, `///` on every public declaration.
         `PersonAlias.init?(name:email:)`: key = `BinderText.fold(name trimmed)`, email = trimmed
         and lowercased; nil when either is empty.
      2. Create AppCore/Tests/Settings/PersonAliasTests.swift (Swift Testing, opening comment
         naming what it tests) with a `@Suite("Person aliases")` covering: a name and email are
         folded and lowercased ("  Zoë ", " Zoe.K@Example.COM " → key `BinderText.fold("Zoë")`,
         email "zoe.k@example.com"); a blank name or a blank email gives nil (parameterized);
         `suggestedName` prefers the nickname, then the given name, then the family name, trims,
         and is "" with none (parameterized); `FixtureContactPicker().pickContact()` returns
         `PickedContact.fixture`. Every new AppCore line must be covered (OVERALL_FLOOR is 100).
      3. Create App/Platform/ContactPicker.swift with the D2 code verbatim (SystemContactPicker
         and the `contactPicker` environment entry).
      4. App/AppEnvironment.swift: add `let contactPicker: any ContactPicking` to `AppServices`;
         pass `FixtureContactPicker()` in the fixture branch and `SystemContactPicker()` in the
         live branch.
      5. App/MagendaApp.swift: add `.environment(\.contactPicker, services.contactPicker)` after
         `.environment(\.allowsFingerDrawing, ...)`.
      6. App/Screens/RulesView.swift: add the environment property, `ID.peopleFromContacts`, the
         button, the new `addPerson()` using `PersonAlias`, the new People footer string, and the
         preview's `.environment(\.contactPicker, FixtureContactPicker())`, all as in D2.
      7. AppUITests/RulesUITests.swift: add `testChoosingAContactFillsThePerson`: open the rules,
         `reveal` and tap `app.buttons["peopleFromContacts"].firstMatch`, then
         `waitUntil(element(app, "peopleName"), "value == %@", "Nora")` and
         `waitUntil(element(app, "peopleEmail"), "value == %@", "nora.kim@example.com")`, tap
         `peopleAdd` (the retry loop of `testAddingAPersonShowsTheAlias`), and wait until
         `rulesRow.people.0` has `label == "nora → nora.kim@example.com"`.
      8. Dispatch tests.yml on the phase branch and read the app and ui jobs.
      9. Commit with a message saying People can be filled from the system contact picker.
      No project.yml, Info.plist or PrivacyInfo.xcprivacy change. No CHANGELOG line.
      Stop conditions: a concurrency compile error in ContactPicker.swift on the app jobs → stop
      with status=blocked and paste the error (do not add @preconcurrency, @unchecked Sendable or
      nonisolated(unsafe)). A compile error that the SDK requires NSContactsUsageDescription for
      the picker → stop with status=blocked.
    acceptance:
      - swift test --package-path AppCore --filter PersonAliasTests passes (or the tests.yml core job on the phase branch)
      - tests.yml core job's coverage floor step passes on the phase branch
      - "`grep -rn 'NSContactsUsageDescription' project.yml App` finds nothing"
      - tests.yml dispatched on the phase branch is green, including RulesUITests testChoosingAContactFillsThePerson and testAddingAPersonShowsTheAlias

  - id: p3-drive-folder-core
    title: A Drive folder name in the settings, remembered per day and sent as folderID
    depends_on: []
    complexity: M
    touches:
      - AppCore/Sources/Settings/DriveFolderName.swift
      - AppCore/Tests/Settings/DriveFolderNameTests.swift
      - AppCore/Sources/Settings/AgendaSettings.swift
      - AppCore/Tests/Settings/AgendaSettingsTests.swift
      - AppCore/Sources/Controller/AgendaController.swift
      - AppCore/Tests/Controller/AgendaControllerTests.swift
      - AppCore/Sources/Handoff/DayHandoff.swift
      - AppCore/Tests/Handoff/DayHandoffTests.swift
      - AppCore/Sources/Handoff/HandoffController.swift
      - AppCore/Tests/Handoff/HandoffControllerTests.swift
    brief: |
      Implement the AppCore half of the plan's Design section D3 exactly. Do not touch App/.
      0. Check first: `grep -c 'drive.folderID(named:' AppCore/Sources/Handoff/HandoffController.swift`
         must print 1, and `grep -n 'magenda.end-of-day/1' AppCore/Sources/Handoff/DayHandoff.swift`
         must find the Payload's schema. If either differs, stop with status=blocked and report
         what you found (other work on the hand-off landed first).
      1. Create AppCore/Sources/Settings/DriveFolderName.swift as in D3.
      2. Create AppCore/Tests/Settings/DriveFolderNameTests.swift: `validated` trims ("  Work
         notes \n" → "Work notes"); accepts exactly 100 characters and refuses 101; refuses "",
         "   ", "a/b", "a\\b" and "a\u{0007}b" (parameterized); the default is "Magenda" and
         passes `validated`.
      3. AgendaSettings: add `driveFolderName` as in D3. In AgendaSettingsTests add: a fresh
         `AgendaSettings()` has "Magenda"; settings round-trip with "Work notes"; JSON without
         the key decodes to "Magenda"; JSON with `"driveFolderName":"a/b"` decodes to "Magenda".
      4. AgendaController.updateSettings: the `drawnBefore` change from D3. In
         AgendaControllerTests add `@Test("changing only the Drive folder keeps the rendered PDF")`:
         `started(.standard)`, `render()`, `updateSettings { $0.driveFolderName = "Work notes" }`,
         expect `rendered != nil` and `settingsStore.load().driveFolderName == "Work notes"`.
         The existing `editsClearRendered` test must still pass unchanged.
      5. DayHandoff: add `folderID` (property, CodingKeys, decodeIfPresent, Payload) as in D3. In
         DayHandoffTests add: a hand-off with `folderID = "folder-9"` round-trips through
         JSONEncoder/JSONDecoder; a saved hand-off without the key decodes with nil; the payload
         contains `"folderID":"folder-9"` when set and no `folderID` key when nil.
      6. HandoffController: the `folderName` init parameter (last, with the default), the
         `runPipeline` change and the `finish` line, as in D3; delete `static let folderName`.
         In HandoffControllerTests extend the context's `make`/init (around line 183) with an
         optional `folderName: (@MainActor () -> String)? = nil` passed through when non-nil, and
         add:
         a. "the first upload uses the folder the setting names": folderName returns
            "Work notes"; after `finish`, `await drive.calls` contains
            `.folderID(named: "Work notes")` and the stored day's `folderID == "folder-1"`.
         b. "a day keeps the folder of its first upload": a `@MainActor final class` box holding
            `var name = "Magenda"` feeds folderName; make `createDoc` fail
            (`drive.setError(..., for: .createDoc)`), `finish`; set box name to "Other", clear
            the error, `refresh(excluding:)` a different day; expect exactly one `.folderID` call
            in `drive.calls` and the `.createDoc` call's folderID is "folder-1".
         c. "finishing again before sending keeps the folder": extend or mirror the existing
            "finishing again before sending keeps the Drive IDs and replaces the PDF" test to also
            expect the second hand-off's `folderID` equals the first's.
      7. Run swift test with coverage and scripts/check_coverage_floor.py (or dispatch tests.yml
         and read core and lint). Every new line must be covered.
      8. Commit with a message saying the Drive folder name is a setting, remembered per day and
         sent to the routine as folderID.
      No docs, no CHANGELOG line; the retire phase writes them.
    acceptance:
      - swift test --package-path AppCore --filter "DriveFolderNameTests|AgendaSettingsTests|AgendaControllerTests|DayHandoffTests|HandoffControllerTests" passes (or the tests.yml core job)
      - python3 scripts/check_coverage_floor.py on the coverage report passes (tests.yml core job)
      - "`grep -n 'static let folderName' AppCore/Sources/Handoff/HandoffController.swift` finds nothing"
      - "`grep -n 'folderID' AppCore/Sources/Handoff/DayHandoff.swift` finds the property, the coding key, the decode and the Payload field"

  - id: p4-drive-folder-settings
    title: The Google Drive section in Settings, wired to the hand-off
    depends_on: [p2-contact-picker, p3-drive-folder-core]
    complexity: S
    touches:
      - App/AppEnvironment.swift
      - App/Screens/SettingsView.swift
      - AppUITests/SettingsUITests.swift
    brief: |
      Implement the App half of the plan's Design section D3 exactly.
      1. App/AppEnvironment.swift: pass `folderName: { controller.settings.driveFolderName }` as
         the last argument of both `HandoffController(...)` calls.
      2. App/Screens/SettingsView.swift: the three `ID`s, the two `@State`s, `driveSection` and
         `commitFolder()` from D3; put `driveSection` between `clientSection` and
         `routineSection` in `body`; in `.onAppear` also set
         `folderDraft = controller.settings.driveFolderName` (wrap it with `resetHexDrafts` in a
         closure); change the routine footer's first sentence to the D3 string.
      3. AppUITests/SettingsUITests.swift: add `testAFolderNameIsSavedAndAnInvalidOneShowsAnError`
         using the file's helpers (`launch`, `openSettings`, `element`, `reveal`, `enterHex`,
         which clears the field and presses return): `reveal` `driveFolderFooter` and assert its
         label contains "“Magenda”"; `enterHex(app, element(app, "driveFolderField"), "a/b")`
         and wait for `driveFolderError` to exist; `enterHex(... "Work notes")`, wait until
         `driveFolderError` does not exist and until `driveFolderFooter`'s label CONTAINS
         "“Work notes”" (XCTNSPredicateExpectation, 30 s). Give it a `///` comment.
      4. Dispatch tests.yml on the phase branch; read the app and ui jobs.
      5. Commit with a message saying Settings names the Drive folder finished days upload to.
      Stop condition: if `HandoffController.init` has no `folderName` parameter, p3 did not
      merge; stop with status=blocked.
    acceptance:
      - "`grep -c 'folderName:' App/AppEnvironment.swift` prints 2"
      - "`grep -n 'driveSection' App/Screens/SettingsView.swift` finds the property and its use in body"
      - tests.yml dispatched on the phase branch is green, including SettingsUITests testAFolderNameIsSavedAndAnInvalidOneShowsAnError on all three settings shards

  - id: p5-retire
    title: ADRs, docs, changelog, and retire the plan
    depends_on: [p1-rules-delete, p2-contact-picker, p3-drive-folder-core, p4-drive-folder-settings]
    complexity: S
    touches:
      - docs/adr/0036-finished-days-upload-to-a-drive-folder-named-in-settings.md
      - docs/adr/0037-people-rules-are-filled-from-the-system-contact-picker.md
      - docs/adr/0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md
      - docs/adr/README.md
      - docs/end-of-day-handoff.md
      - docs/release-testing.md
      - README.md
      - CHANGELOG.md
      - docs/settings-improvements-plan.md
      - docs/settings-improvements-plan-manual-steps.html
    brief: |
      1. Merge origin/main into the feature branch first if it moved. Then `ls docs/adr`: if 0036
         or 0037 is taken, use the next free numbers for the two ADRs below (and in every link
         and the touches' file names) and say so in the commit message.
      2. Write ADR 0036 (`docs/adr/0036-finished-days-upload-to-a-drive-folder-named-in-settings.md`)
         and ADR 0037 (`docs/adr/0037-people-rules-are-filled-from-the-system-contact-picker.md`)
         with the template in docs/adr/README.md, Status `Accepted — <today>. Implemented.`, the
         decisions in the plan's ADRs section and the rejected alternatives listed at the end of
         D3 and D2. ADR 0036's Status also has `Amends [ADR 0027](0027-finished-days-are-uploaded-to-google-drive-with-drive-file.md): the fixed folder name.`
         Verification lists the source and test files p2/p3 created or changed. Link no plan.
      3. Add one Status line to ADR 0027: `Amended by [ADR 0036](0036-finished-days-upload-to-a-drive-folder-named-in-settings.md): the folder is named in Settings.`
         Change nothing else in it.
      4. Add both ADRs to the index table in docs/adr/README.md, after the last row.
      5. docs/end-of-day-handoff.md: the four routine-contract edits in D3's "Routine contract"
         paragraph; add ADR 0036 to the opening list of decisions.
      6. README.md: in "Finishing a day" replace "to a `Magenda` folder in your Drive" with "to a
         folder in your Drive, `Magenda` unless you rename it in Settings → Google Drive
         (ADR 0036)"; where People is mentioned (line ~49) add "or choose them from Contacts".
      7. docs/release-testing.md "What stays manual": add a bullet "the system contact picker
         behind Choose from Contacts, which runs out of process and is replaced by a fixture in
         the UI tests (ADR 0037);".
      8. CHANGELOG.md under `## [Unreleased]` → `### Added` (create the subheading only if
         missing), three lines:
         - "Settings → Binder rules has an Edit button, and a long press on a rule offers Delete,
           for the built-in entries such as PTO as well as the ones you added."
         - "Settings → Binder rules → People can fill in a name and email from your contacts with
           Choose from Contacts…."
         - "Settings → Google Drive shows and lets you rename the folder finished days are
           uploaded to. Days already uploaded stay in their folder."
      9. Delete docs/settings-improvements-plan.md and
         docs/settings-improvements-plan-manual-steps.html; `grep -rn 'settings-improvements-plan'`
         must find nothing.
      10. Run `python3 -m unittest discover -s scripts/tests` (includes the no-project-history
          guard). Commit with a message saying the decisions are recorded and the plan retired.
    acceptance:
      - "`ls docs/adr/0036-*.md docs/adr/0037-*.md` lists two files (or the renumbered ones), each containing 'Accepted'"
      - "`git diff origin/main -- docs/adr/0027-*.md` shows only one added Status line"
      - "`grep -rn 'settings-improvements-plan' .` finds nothing"
      - "`grep -n 'folderID' docs/end-of-day-handoff.md` finds the example, the field description and the notes step"
      - python3 -m unittest discover -s scripts/tests passes

  - id: p6-stack
    title: Stack on feature/send-meeting-early by merging it in and resolving the overlap
    depends_on: [p5-retire]
    complexity: M
    worker_model: opus
    worker_model_reason: Merging another plan's hand-off changes (payload schema, meeting uploads, ADRs) into this one is conflict resolution across HandoffController, DayHandoff and the routine contract that cannot be written down line by line in advance.
    touches:
      - AppCore/**
      - App/**
      - AppUITests/**
      - docs/**
      - README.md
      - CHANGELOG.md
    brief: |
      The orchestrator starts this only once origin/feature/send-meeting-early exists (see the
      plan's "Stacked on send-meeting-early" section). It merges that branch into this one so the
      PR can be stacked on it. Do not change what the other branch does; only make this plan's
      three changes sit correctly on top of it. p5 deleted the plan from this branch: read D3 with
      `git fetch origin plan/settings-improvements && git show FETCH_HEAD:docs/settings-improvements-plan.md`.
      1. `git fetch origin feature/send-meeting-early` and
         `git merge --no-ff origin/feature/send-meeting-early` (a merge commit; never rebase).
      2. Resolve conflicts by these rules:
         a. HandoffController.swift: keep every change from the other branch. Every
            `Self.folderName` or literal `"Magenda"` folder lookup it adds becomes `folderName()`.
            Where a day's upload runs, keep D3's `handoff.folderID` reuse. If the other branch
            uploads a meeting into the folder and stores a record with `driveFileID`, give that
            record `folderID: String?` the same way D3 gives it to DayHandoff (optional, decoded
            with decodeIfPresent) and reuse it the same way.
         b. DayHandoff.swift (and any meeting payload type the other branch adds): keep the other
            branch's schema string and keys; add `folderID` next to `driveFileID` in every payload
            that has `driveFileID`.
         c. docs/end-of-day-handoff.md: keep the other branch's text, then apply D3's routine
            contract edits on top of it (folder row, `folderID` in each payload example and field
            list, the folder check in each step that checks the folder).
         d. CHANGELOG.md, docs/adr/README.md, README.md: keep both sides' lines, theirs first.
         e. ADR 0027's Status: keep both added lines. If the other branch also uses ADR numbers
            0036 or 0037, renumber this plan's two ADRs to the next free numbers and fix every
            link (`grep -rn '0036\|0037' docs README.md`).
         f. App/AppEnvironment.swift, App/MagendaApp.swift and any other App file: keep both
            sides' additions.
      3. Run `swift build`/`swift test --package-path AppCore` with coverage and the coverage
         floor, `swift format lint --strict` and `python3 -m unittest discover -s scripts/tests`
         (or dispatch tests.yml on the phase branch for core and lint). Fix failures only in this
         plan's code or in the merge resolution. Never weaken, skip or delete a test from either
         branch. Add tests only where rule 2a or 2b added `folderID` to a type of the other
         branch (round-trip, decode without the key, payload with and without it).
      4. Dispatch tests.yml on the phase branch and read every app and ui job.
      5. Commit the merge with a message saying this branch is stacked on
         feature/send-meeting-early and how the overlap was resolved.
      Stop conditions: the other branch removed or replaced `DriveFiling.folderID(named:)`, the
      Settings screen, or the People rules in a way that rules 2a–2f do not cover → stop with
      status=blocked and describe the conflict. A test of the other branch fails after the merge
      and its fix would change that branch's behavior → stop with status=blocked.
    acceptance:
      - "`git merge-base --is-ancestor origin/feature/send-meeting-early HEAD` exits 0"
      - "`grep -rn 'Self.folderName' AppCore/Sources` finds nothing"
      - "`git diff --name-only --diff-filter=U` prints nothing and `grep -rln '^<<<<<<<' AppCore App AppUITests docs README.md CHANGELOG.md` finds nothing"
      - tests.yml dispatched on the phase branch is green on every core, lint, scripts, app and ui job
```
