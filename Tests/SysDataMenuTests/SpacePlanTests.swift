import Foundation
import Testing

@testable import SysDataMenu

/// The set of items that frees "this much", in the order a careful person
/// would take them.
struct SpacePlanTests {
    private let gigabyte: Int64 = 1_000_000_000

    private func item(
        _ id: String, _ gigabytes: Int64, _ safety: Safety = .safe,
        idle: Int? = nil, category: StorageCategory = .packages, manual: Bool = false
    ) -> StorageItem {
        StorageItem(
            id: id, category: category, name: id, detail: "", sizeBytes: gigabytes * gigabyte, safety: safety,
            action: manual ? .manual("by hand") : .removePaths([URL(fileURLWithPath: "/tmp/\(id)")]),
            lastModified: idle.map { Calendar.current.date(byAdding: .day, value: -$0, to: .now)! }
        )
    }

    @Test func safeItemsComeFirstLargestFirst() {
        let plan = SpacePlan.build(freeing: 6 * gigabyte, from: [
            item("small", 1), item("big", 5), item("review", 40, .review, idle: 400), item("medium", 3),
        ])
        #expect(plan.items.map(\.id) == ["big", "medium"], "largest first, so the fewest rows")
        #expect(plan.reachesTarget)
        #expect(plan.reviewCount == 0, "Safe items were enough, so nothing to review is offered")
    }

    @Test func reviewItemsAreTakenLongestUntouchedFirstOnlyWhenSafeIsNotEnough() {
        let plan = SpacePlan.build(freeing: 12 * gigabyte, from: [
            item("safe", 4),
            item("recent", 30, .review, idle: 3),
            item("old", 9, .review, idle: 500),
        ])
        #expect(plan.items.map(\.id) == ["safe", "old"])
        #expect(plan.safeCount == 1 && plan.reviewCount == 1)
    }

    @Test func anItemThePlanNoLongerNeedsIsDropped() {
        // Taking the 1 GB item first and then the 10 GB one meets 10 GB, and
        // the small one is then surplus.
        let plan = SpacePlan.build(freeing: 10 * gigabyte, from: [
            item("tiny", 1, .review, idle: 900),
            item("large", 10, .review, idle: 400),
        ])
        #expect(plan.items.map(\.id) == ["large"])
    }

    /// A goal that cannot be met is not a reason to tick sixty rows. Only the
    /// Safe ones are selected; what is left is the person's to choose.
    @Test func whenEverythingIsNotEnoughOnlyTheSafeItemsAreSelected() {
        let plan = SpacePlan.build(freeing: 100 * gigabyte, from: [item("a", 4), item("b", 6, .review, idle: 90)])
        #expect(!plan.reachesTarget)
        #expect(plan.available == 10 * gigabyte)
        #expect(plan.shortfall == 90 * gigabyte)
        #expect(plan.items.map(\.id) == ["a"])
        #expect(plan.reviewCount == 0)
    }

    @Test func instructionsAndUnmeasuredItemsAreNeverOffered() {
        var unmeasured = item("unmeasured", 5)
        unmeasured = StorageItem(
            id: "unmeasured", category: .packages, name: "x", detail: "", sizeBytes: nil, safety: .safe,
            action: .removePaths([])
        )
        let plan = SpacePlan.build(freeing: gigabyte, from: [
            item("manual", 50, .manual, manual: true), unmeasured, item("snapshots", 9, .review, manual: true),
        ])
        #expect(plan.items.isEmpty)
    }

    /// Emptying the Trash forgets files for good, so it is the last resort
    /// and never ahead of an item that can simply be rebuilt.
    @Test func theTrashComesLast() {
        let plan = SpacePlan.build(freeing: 8 * gigabyte, from: [
            item("trash", 20, .safe, category: .trash),
            item("review", 9, .review, idle: 100),
        ])
        #expect(plan.items.map(\.id) == ["review"])
    }

    @Test func nothingIsAskedForNothing() {
        #expect(SpacePlan.build(freeing: 0, from: [item("a", 5)]).items.isEmpty)
    }
}

/// The plan is the selection: it lasts exactly as long as the selection is
/// still what it chose, and it ends without anything having to clear it.
@MainActor
struct SpacePlanSelectionTests {
    private func item(_ id: String, _ gigabytes: Int64, _ safety: Safety = .safe, category: StorageCategory = .packages) -> StorageItem {
        StorageItem(
            id: id, category: category, name: id, detail: "", sizeBytes: gigabytes * 1_000_000_000,
            safety: safety, action: .removePaths([URL(fileURLWithPath: "/tmp/\(id)")])
        )
    }

    @Test func planningSelectsTheItemsAndUnfoldsTheirGroups() {
        let model = ScanModel(scansAutomatically: false, items: [
            item("a", 8), item("b", 3, category: .tools), item("c", 1),
        ])
        model.collapsedCategories = [.packages, .tools]
        model.planSpace(freeing: 10_000_000_000)

        #expect(model.selectedIDs == ["a", "b"])
        #expect(model.activeSpacePlan?.reachesTarget == true)
        #expect(!model.collapsedCategories.contains(.packages) && !model.collapsedCategories.contains(.tools))
    }

    @Test func changingTheSelectionEndsThePlan() {
        let model = ScanModel(scansAutomatically: false, items: [item("a", 8), item("b", 3)])
        model.planSpace(freeing: 10_000_000_000)
        #expect(model.activeSpacePlan != nil)

        model.selectedIDs.remove("b")
        #expect(model.activeSpacePlan == nil)
    }

    @Test func aHiddenItemIsNeverPlanned() {
        let model = ScanModel(scansAutomatically: false, items: [item("keep", 50), item("other", 2)])
        model.unhideAll()
        defer { model.unhideAll() }
        model.hide(model.visibleItems.first { $0.id == "keep" }!)

        model.planSpace(freeing: 1_000_000_000)
        #expect(model.selectedIDs == ["other"])
    }
}
