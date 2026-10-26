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
        guard let presenter = Self.frontmostViewController() else { return nil }
        // A picker that went away without a delegate call must not leave the button dead.
        finish(nil)
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.isModalInPresentation = true
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
    nonisolated func contactPicker(
        _ picker: CNContactPickerViewController, didSelect contact: CNContact
    ) {
        let email =
            contact.isKeyAvailable(CNContactEmailAddressesKey)
            ? contact.emailAddresses.first.map { $0.value as String } : nil
        let picked = Self.picked(contact, email: email)
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
