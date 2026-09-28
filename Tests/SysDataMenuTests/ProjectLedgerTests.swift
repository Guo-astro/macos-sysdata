import Foundation
import Testing
@testable import SysDataMenu

/// The Projects view: everything one project costs, gathered from where the
/// scan found it, and the project each place is attributed to.
@Suite struct ProjectLedgerTests {
    private func tree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "sysdata-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func item(_ id: String, _ bytes: Int64, project: URL?, category: StorageCategory = .projects,
                      modified: Date? = nil, builtAt: Date? = nil) -> StorageItem {
        StorageItem(id: id, category: category, name: id, detail: "", sizeBytes: bytes, safety: .review,
                    action: .removePaths([URL(fileURLWithPath: "/tmp/\(id)")]),
                    revealURL: URL(fileURLWithPath: "/tmp/\(id)"), lastModified: modified, project: project,
                    builtAt: builtAt)
    }

    /// A project last built three days ago is being worked on: an archive
    /// would last until its next build, and the row says so. One whose build
    /// output is months old is not.
    @Test func aRecentBuildAndAWeeksGrowthAreShown() {
        let now = Date()
        let active = URL(fileURLWithPath: "/tmp/sysdata-active")
        let dormant = URL(fileURLWithPath: "/tmp/sysdata-dormant")
        let footprints = ProjectFootprint.group([
            item("active-next", 500, project: active, builtAt: now.addingTimeInterval(-3 * 86_400)),
            item("active-modules", 400, project: active, builtAt: now.addingTimeInterval(-200 * 86_400)),
            item("dormant-build", 300, project: dormant, builtAt: now.addingTimeInterval(-40 * 86_400)),
        ], changes: ["active-next": 120, "active-modules": -20], now: now)

        let byName = Dictionary(uniqueKeysWithValues: footprints.map { ($0.name, $0) })
        #expect(byName["sysdata-active"]?.builtRecently == true)
        #expect(byName["sysdata-active"]?.weeklyGrowth == 100)
        #expect(byName["sysdata-dormant"]?.builtRecently == false)
        // No history for it: nothing is claimed rather than zero.
        #expect(byName["sysdata-dormant"]?.weeklyGrowth == nil)
    }

    /// Only items both scans measured are compared. DerivedData became one
    /// row per project, and those rows must not read as a week's growth the
    /// first time they appear.
    @Test func aWeeksChangeLeavesOutWhatTheOldScanDidNotKnow() {
        let now = Date()
        var log = ScanHistory.Log()
        log.scans = [
            .init(date: now.addingTimeInterval(-8 * 86_400), totalBytes: 0, freeBytes: 0,
                  sizes: ["node_modules": 1_000], names: [:]),
            .init(date: now, totalBytes: 0, freeBytes: 0,
                  sizes: ["node_modules": 1_500, "xcode-deriveddata-new": 9_000], names: [:]),
        ]
        #expect(ScanHistory.itemChanges(overPastDays: 7, in: log) == ["node_modules": 500])
    }

    @Test func itemsAreGroupedPerProjectLargestFirst() {
        let app = URL(fileURLWithPath: "/tmp/sysdata-app")
        let site = URL(fileURLWithPath: "/tmp/sysdata-site")
        let old = Date(timeIntervalSinceNow: -90 * 86_400)
        let recent = Date(timeIntervalSinceNow: -2 * 86_400)
        let footprints = ProjectFootprint.group([
            item("node_modules", 400, project: site, modified: old),
            item("derived", 900, project: app, category: .xcode, modified: old),
            item(".build", 300, project: app, modified: recent),
            item("npm-cache", 5_000, project: nil),
        ])

        #expect(footprints.map(\.name) == ["sysdata-app", "sysdata-site"])
        #expect(footprints[0].totalBytes == 1_200)
        // The newest activity wins: someone built it two days ago.
        #expect(footprints[0].idleDays == 2)
        #expect(footprints[0].items.first?.partName == "DerivedData")
        // A project folder that is gone is marked so, and costs nothing to lose.
        #expect(footprints.allSatisfy { !$0.exists })
    }

    @Test func derivedDataIsTracedToTheFolderHoldingTheProject() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "Weather")
        try FileManager.default.createDirectory(at: project.appending(path: "Weather.xcodeproj/project.xcworkspace"),
                                                withIntermediateDirectories: true)

        for (name, workspace) in [
            ("a", "Weather/Weather.xcodeproj"),
            ("b", "Weather/Weather.xcodeproj/project.xcworkspace"),
        ] {
            let derived = root.appending(path: "DerivedData/\(name)")
            try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
            let info: NSDictionary = ["WorkspacePath": root.appending(path: workspace).path]
            info.write(to: derived.appending(path: "info.plist"), atomically: true)
            #expect(XcodeProbe.project(ofDerivedData: derived)?.standardizedFileURL.path == project.standardizedFileURL.path)
        }

        // The module cache and friends belong to no project.
        let shared = root.appending(path: "DerivedData/ModuleCache.noindex")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        #expect(XcodeProbe.project(ofDerivedData: shared) == nil)
    }

    @Test func aMonorepoIsOneProject() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appending(path: "platform")
        let web = repo.appending(path: "apps/web")
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)

        #expect(ProjectProbe.projectRoot(of: web, stoppingAt: [root]).path == repo.standardizedFileURL.path)
        // Without a repository the folder is its own project, and the search
        // never climbs past the folder projects are looked for in.
        let loose = root.appending(path: "loose")
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        #expect(ProjectProbe.projectRoot(of: loose, stoppingAt: [root]).path == loose.standardizedFileURL.path)
    }
}
