import LocalAuthentication

/// Asks for Touch ID, an Apple Watch or the Mac's password before a delete
/// the person has just confirmed on screen.
///
/// It is for the moment someone else is at an unlocked Mac, or a click lands
/// on the wrong button: one more step that only the owner can take. It only
/// guards deletes confirmed in the window. The automatic weekly clean and the
/// Shortcuts actions run without anyone present and never ask.
enum DeleteAuthentication {
    /// Whether this Mac can ask at all: a password, a Watch or Touch ID has
    /// to exist. Without one the setting would lock every delete.
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Whether the delete may go ahead. Not required, or not possible to
    /// ask, means yes: a switch left on after the last password was removed
    /// must not make deleting impossible. A cancelled or failed prompt means
    /// no, and nothing is deleted.
    ///
    /// The system prompt is a parameter so the rule above can be tested
    /// without a person at the keyboard.
    static func authorize(
        isRequired: Bool,
        isAvailable: Bool = DeleteAuthentication.isAvailable,
        reason: String,
        evaluate: (String) async -> Bool = DeleteAuthentication.askSystem
    ) async -> Bool {
        guard isRequired, isAvailable else { return true }
        return await evaluate(reason)
    }

    static func askSystem(reason: String) async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
