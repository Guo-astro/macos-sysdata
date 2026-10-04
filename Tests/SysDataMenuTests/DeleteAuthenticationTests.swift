import Testing

@testable import SysDataMenu

/// The prompt itself is the system's. What is ours is when it is asked for
/// and what each answer means.
struct DeleteAuthenticationTests {
    private func authorize(
        required: Bool, available: Bool = true, answer: Bool, asked: Counter = Counter()
    ) async -> Bool {
        await DeleteAuthentication.authorize(
            isRequired: required, isAvailable: available, reason: "Confirm the delete."
        ) { _ in
            asked.count += 1
            return answer
        }
    }

    final class Counter: @unchecked Sendable { var count = 0 }

    @Test func offMeansNobodyIsAsked() async {
        let asked = Counter()
        #expect(await authorize(required: false, answer: false, asked: asked))
        #expect(asked.count == 0)
    }

    @Test func aPassedPromptLetsTheDeleteRun() async {
        let asked = Counter()
        #expect(await authorize(required: true, answer: true, asked: asked))
        #expect(asked.count == 1)
    }

    @Test func aCancelledPromptStopsTheDelete() async {
        #expect(await authorize(required: true, answer: false) == false)
    }

    /// A Mac that can no longer ask must not be locked out of its own deletes.
    @Test func aMacThatCannotAskIsNotLockedOut() async {
        let asked = Counter()
        #expect(await authorize(required: true, available: false, answer: false, asked: asked))
        #expect(asked.count == 0)
    }
}
