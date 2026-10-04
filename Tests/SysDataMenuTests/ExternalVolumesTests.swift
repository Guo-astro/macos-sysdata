import Foundation
import Testing

@testable import SysDataMenu

/// Which drives the project search may walk, and that it finds a project on one.
struct ExternalVolumesTests {
    private func facts(
        _ path: String = "/Volumes/Work", internal isInternal: Bool = false, local: Bool = true,
        readOnly: Bool = false, startup: Bool = false, timeMachine: Bool = false
    ) -> ExternalVolumes.Facts {
        .init(url: URL(fileURLWithPath: path), isInternal: isInternal, isLocal: local, isReadOnly: readOnly,
              isStartupVolume: startup, holdsTimeMachineBackups: timeMachine)
    }

    @Test func aPluggedInWritableDriveQualifies() {
        #expect(ExternalVolumes.isScannable(facts()))
    }

    @Test func nothingElseDoes() {
        #expect(!ExternalVolumes.isScannable(facts(internal: true)), "the Mac's own disks are scanned already")
        #expect(!ExternalVolumes.isScannable(facts(local: false)), "a network share is slow and not this Mac's data")
        #expect(!ExternalVolumes.isScannable(facts(readOnly: true)), "a mounted installer cannot be cleaned")
        #expect(!ExternalVolumes.isScannable(facts(startup: true)))
        #expect(!ExternalVolumes.isScannable(facts(timeMachine: true)), "a backup disk holds hard links by the million")
        #expect(!ExternalVolumes.isScannable(facts("/System/Volumes/Data")))
    }

    @Test func onlyTheFoldersPeopleKeepCodeInAreSearched() throws {
        let volume = FileManager.default.temporaryDirectory.appending(path: "sysdata-drive-\(UUID().uuidString)")
        for name in ["Developer", "Movies", "dev"] {
            try FileManager.default.createDirectory(at: volume.appending(path: name), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: volume) }
        #expect(ExternalVolumes.projectRoots(on: volume).map(\.lastPathComponent) == ["Developer", "dev"])
    }

    @Test func aBuildFolderOnADriveIsFoundAndBelongsToItsProject() async throws {
        let drive = FileManager.default.temporaryDirectory.appending(path: "sysdata-drive-\(UUID().uuidString)")
        let code = drive.appending(path: "Developer")
        let modules = code.appending(path: "site/node_modules")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data(count: 40 * 1_048_576).write(to: modules.appending(path: "big.bin"))
        defer { try? FileManager.default.removeItem(at: drive) }

        let items = await ProjectProbe(externalRoots: [code]).probe()
        let item = try #require(items.first { $0.revealURL?.standardizedFileURL == modules.standardizedFileURL })
        #expect(item.project?.lastPathComponent == "site")
        #expect(item.category == .projects)
    }

    @Test func withoutDrivesTheProbeSearchesOnlyHome() async {
        let items = await ProjectProbe(externalRoots: []).probe()
        #expect(items.allSatisfy { !($0.revealURL?.path.hasPrefix("/Volumes/") ?? false) })
    }
}
