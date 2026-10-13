import Foundation

/// "I need 20 GB": the least worrying set of items that frees that much.
///
/// The list answers what is taking space. The question people arrive with is
/// the other way round — an update needs 14 GB, a video 30 — and answering it
/// by hand means reading two hundred rows and adding them up. The plan does
/// the adding, in the order a careful person would: everything marked Safe
/// first, largest first so it takes the fewest rows; then, only if that is
/// not enough, the Review items that have sat untouched longest, because an
/// item nobody has touched in a year is the cheapest thing to be wrong about.
///
/// It selects. Nothing is deleted by it: the result goes through the same
/// confirmation as any other batch, with every command shown.
struct SpacePlan: Equatable, Sendable {
    let target: Int64
    /// What the plan selects. When the target is out of reach this is only
    /// the Safe items, never everything: a batch of sixty rows including what
    /// was used this morning is not something to pre-select on someone's
    /// behalf for a goal it cannot meet.
    let items: [StorageItem]
    /// Everything this app could free in all, selected or not.
    let available: Int64

    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    var safeCount: Int { items.filter { $0.safety == .safe }.count }
    var reviewCount: Int { items.count - safeCount }
    /// How far short of the target everything the app could free falls.
    var shortfall: Int64 { max(target - available, 0) }
    var reachesTarget: Bool { target > 0 && totalBytes >= target }

    static func == (lhs: SpacePlan, rhs: SpacePlan) -> Bool {
        lhs.target == rhs.target && lhs.items.map(\.id) == rhs.items.map(\.id)
    }

    /// What may be offered at all: measured, and something this app can
    /// delete. Manual items are instructions, not actions. The Trash is
    /// eligible but always last, because emptying it forgets files for good.
    static func isEligible(_ item: StorageItem) -> Bool {
        guard let bytes = item.sizeBytes, bytes > 0 else { return false }
        return !item.action.isManual && item.safety != .manual
    }

    /// Eligible items in the order they would be taken.
    static func preferenceOrder(_ items: [StorageItem]) -> [StorageItem] {
        func tier(_ item: StorageItem) -> Int {
            if item.category == .trash { return 2 }
            return item.safety == .safe ? 0 : 1
        }
        return items.filter(isEligible).sorted { a, b in
            let (ta, tb) = (tier(a), tier(b))
            if ta != tb { return ta < tb }
            if ta == 1 {
                // Review: longest untouched first. An item with no age is
                // treated as in use, which is the cautious reading.
                let (ia, ib) = (a.idleDays ?? 0, b.idleDays ?? 0)
                if ia != ib { return ia > ib }
            }
            return (a.sizeBytes ?? 0) > (b.sizeBytes ?? 0)
        }
    }

    static func build(freeing target: Int64, from items: [StorageItem]) -> SpacePlan {
        let ordered = preferenceOrder(items)
        let available = ordered.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        guard target > 0 else { return SpacePlan(target: target, items: [], available: available) }
        guard available >= target else {
            let safe = ordered.filter { $0.safety == .safe && $0.category != .trash }
            return SpacePlan(target: target, items: safe, available: available)
        }

        var chosen: [StorageItem] = []
        var sum: Int64 = 0
        for item in ordered {
            chosen.append(item)
            sum += item.sizeBytes ?? 0
            if sum >= target { break }
        }

        // Taking items in order can overshoot: a small item early on that the
        // large one after it made unnecessary. Drop the least preferred first.
        if sum >= target {
            for item in chosen.reversed() {
                let size = item.sizeBytes ?? 0
                if sum - size >= target {
                    chosen.removeAll { $0.id == item.id }
                    sum -= size
                }
            }
        }
        return SpacePlan(target: target, items: chosen, available: available)
    }
}
