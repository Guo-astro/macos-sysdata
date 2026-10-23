import Foundation
import Testing
@testable import SysDataMenu

/// The leftovers of IDE updates, game-engine caches and sound libraries.
/// Getting the version split wrong would offer the settings of the IDE the
/// person opens every day.
@Suite struct IDEAndStudioProbeTests {
    private let megabyte = ProbeSupport.megabyte

    private func folder(_ root: URL, _ relative: String, megabytes: Int) throws {
        let url = root.appending(path: relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(count: megabytes * Int(megabyte)).write(to: url.appending(path: "blob"))
    }

    private func temporaryRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sysdata-\(label)-\(UUID().uuidString)")
    }

    @Test func versionedFoldersAreReadAndEverythingElseIsNot() {
        let version = JetBrainsProbe.version(ofFolder: "PyCharmCE2024.3")
        #expect(version?.product == "PyCharmCE")
        #expect(version?.year == 2024)
        #expect(version?.minor == 3)
        #expect(JetBrainsProbe.version(ofFolder: "Toolbox") == nil)
        #expect(JetBrainsProbe.version(ofFolder: "consentOptions") == nil)
        #expect(JetBrainsProbe.version(ofFolder: "IntelliJIdea2024.3-backup") == nil)
    }

    /// 2024.10 is newer than 2024.9, which a string comparison gets wrong.
    @Test func versionsCompareAsNumbers() throws {
        let nine = try #require(JetBrainsProbe.version(ofFolder: "WebStorm2024.9"))
        let ten = try #require(JetBrainsProbe.version(ofFolder: "WebStorm2024.10"))
        #expect(nine < ten)
    }

    @Test func onlyOlderVersionsAreOfferedWhole() async throws {
        let root = temporaryRoot("jetbrains")
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appending(path: "Caches")
        let settings = root.appending(path: "Support")
        try folder(caches, "PyCharm2024.3", megabytes: 30)
        try folder(settings, "PyCharm2024.3", megabytes: 1)
        try folder(caches, "PyCharm2023.2", megabytes: 25)
        try folder(settings, "PyCharm2023.2", megabytes: 5)
        try folder(caches, "Toolbox", megabytes: 40)

        let items = await JetBrainsProbe(cachesRoot: caches, settingsRoot: settings).probe()
        #expect(items.count == 2)

        let current = try #require(items.first { $0.id == "jetbrains-caches-PyCharm2024.3" })
        #expect(current.safety == .safe)
        #expect(current.action.paths == [caches.appending(path: "PyCharm2024.3")],
                "the current version's settings must never be touched")

        let old = try #require(items.first { $0.id == "jetbrains-old-PyCharm2023.2" })
        #expect(old.safety == .review)
        #expect(Set(old.action.paths.map(\.lastPathComponent)) == ["PyCharm2023.2"])
        #expect(old.action.paths.count == 2)
        #expect((old.sizeBytes ?? 0) >= 30 * megabyte)
    }

    /// Two editions of one IDE are two products: Community is not an old
    /// version of Professional.
    @Test func editionsAreSeparateProducts() async throws {
        let root = temporaryRoot("jetbrains-editions")
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appending(path: "Caches")
        try folder(caches, "PyCharm2024.3", megabytes: 25)
        try folder(caches, "PyCharmCE2023.1", megabytes: 25)

        let items = await JetBrainsProbe(cachesRoot: caches, settingsRoot: root.appending(path: "none")).probe()
        #expect(Set(items.map(\.id)) == ["jetbrains-caches-PyCharm2024.3", "jetbrains-caches-PyCharmCE2023.1"])
    }

    @Test func unityEditorsAreLeftToUnityHub() async throws {
        let root = temporaryRoot("unity")
        defer { try? FileManager.default.removeItem(at: root) }
        try folder(root, "Library/Unity/cache/packages", megabytes: 25)
        try folder(root, "Editor/2022.3.20f1", megabytes: 110)

        let items = await UnityProbe(
            unityRoot: root.appending(path: "Library/Unity"), editorsRoot: root.appending(path: "Editor")
        ).probe()
        let editor = try #require(items.first { $0.id == "unity-editor-2022.3.20f1" })
        #expect(editor.action.isManual, "deleting behind Unity Hub's back leaves a broken install")
        #expect(items.first { $0.id == "unity-cache" }?.safety == .safe)
    }

    @Test func soundLibrariesAreNeverDeletedHere() async throws {
        let root = temporaryRoot("sound")
        defer { try? FileManager.default.removeItem(at: root) }
        try folder(root, "Application Support/Logic", megabytes: 110)
        try folder(root, "Audio/Apple Loops/Apple", megabytes: 110)

        let items = await SoundLibraryProbe(root: root).probe()
        #expect(Set(items.map(\.id)) == ["sound-logic", "sound-apple-loops"])
        #expect(items.allSatisfy { $0.action.isManual && $0.revealURL != nil })
    }
}
