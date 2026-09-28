import Foundation

/// Everything one project costs on this disk, gathered from wherever the scan
/// found it: its own build folders, and its folder in DerivedData.
///
/// Every tool lists those places one at a time, so the question people
/// actually have — what is this old project still costing me — was left to
/// arithmetic. Only what the project's build recreates is counted here; its
/// source files are never an item, so archiving one can never touch them.
struct ProjectFootprint: Identifiable, Sendable {
    let folder: URL
    let items: [StorageItem]
    /// Whether the project folder is still there. DerivedData outlives the
    /// projects it was built for, and one whose project is gone is pure
    /// waste. Read once when grouping, not on every redraw.
    let exists: Bool
    /// How much its build output grew since a scan about a week old, from the
    /// items both scans measured; nil when the history does not reach back.
    var weeklyGrowth: Int64? = nil
    /// Whether any of its build output was written in the past week: it is
    /// being built, and an archive holds only until the next build. Read from
    /// the newest file the scan already found inside each build folder.
    var builtRecently = false

    var id: String { folder.path }
    var name: String { folder.lastPathComponent }
    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    /// The newest activity any of its items saw. Items are dated by the
    /// project's own files, so this is when someone last worked on it.
    var lastActivity: Date? { items.compactMap(\.lastModified).max() }

    var idleDays: Int? {
        guard let lastActivity else { return nil }
        return Calendar.current.dateComponents([.day], from: lastActivity, to: .now).day.map { max($0, 0) }
    }

    /// The items an archive deletes: all of them but anything that can only
    /// be done by hand.
    var archivableItems: [StorageItem] { items.filter { !$0.action.isManual } }

    /// Largest first; a project with a single tiny build folder is still a
    /// project, and dropping it would hide a place the person may look for.
    static let recentBuildDays = 7

    static func group(
        _ items: [StorageItem], changes: [String: Int64] = [:], now: Date = .now
    ) -> [ProjectFootprint] {
        let recent = now.addingTimeInterval(-Double(recentBuildDays) * 86_400)
        return Dictionary(grouping: items.filter { $0.project != nil }) { $0.project!.standardizedFileURL.path }
            .map { path, items in
                let folder = URL(fileURLWithPath: path)
                let known = items.compactMap { changes[$0.id] }
                return ProjectFootprint(
                    folder: folder,
                    items: items.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) },
                    exists: folder.exists,
                    weeklyGrowth: known.isEmpty ? nil : known.reduce(0, +),
                    builtRecently: items.contains { ($0.builtAt ?? .distantPast) > recent }
                )
            }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}

extension StorageItem {
    /// What this item is within its project, for a project's breakdown:
    /// "node_modules", ".next", "DerivedData", "Docker images".
    var partName: String {
        if category == .xcode { return "DerivedData" }
        if category == .docker { return name.components(separatedBy: ":").first ?? name }
        return revealURL?.lastPathComponent ?? name
    }
}
