import Foundation
import Testing

@testable import SysDataMenu

/// The terminal form of the weekly clean. What matters is that nothing is
/// deleted unless `--apply` is spelled out, and that the plan names every
/// command before it runs.
@MainActor
struct CleanCommandTests {
    private func item(_ name: String, _ bytes: Int64, safety: Safety = .safe) -> StorageItem {
        let url = URL(fileURLWithPath: "/tmp/sysdata-clean/\(name)")
        return StorageItem(
            id: name, category: .packages, name: name, detail: "", sizeBytes: bytes, safety: safety,
            action: .removePaths([url]), revealURL: url
        )
    }

    @Test func noFlagsMeansTheAppRunsNormally() {
        #expect(CleanCommand.parse(["SysDataMenu"]) == .notRequested)
        #expect(CleanCommand.parse(["SysDataMenu", "--json"]) == .notRequested)
    }

    @Test func cleanAloneOnlyPlans() {
        #expect(CleanCommand.parse(["SysDataMenu", "--clean"]) == .plan)
    }

    @Test func deletingHasToBeAskedForByName() {
        #expect(CleanCommand.parse(["SysDataMenu", "--clean", "--apply"]) == .apply)
        guard case .invalid = CleanCommand.parse(["SysDataMenu", "--apply"]) else {
            Issue.record("--apply without --clean must be refused")
            return
        }
    }

    @Test func anUnknownOptionIsRefusedRatherThanIgnored() {
        guard case .invalid(let message) = CleanCommand.parse(["SysDataMenu", "--clean", "--force"]) else {
            Issue.record("an unknown option must be refused")
            return
        }
        #expect(message.contains("--force"))
    }

    @Test func thePlanNamesEveryItemAndItsCommand() {
        let text = CleanCommand.plan(for: [item("npm cache", 2_000_000_000), item("pip cache", 500_000_000)])
        #expect(text.hasPrefix("2 Safe items, "))
        #expect(text.contains("npm cache"))
        #expect(text.contains("Delete /tmp/sysdata-clean/pip cache"))
    }

    @Test func anEmptyPlanSaysSo() {
        #expect(CleanCommand.plan(for: []) == "Nothing marked Safe is taking space right now.")
    }
}
