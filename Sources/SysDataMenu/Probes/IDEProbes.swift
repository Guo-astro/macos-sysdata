import Foundation

// MARK: - JetBrains IDEs

/// Every JetBrains IDE keeps one caches folder and one settings folder per
/// version, and an update leaves the old pair behind once it has imported the
/// settings. A few versions in, the leftovers outweigh the IDE itself.
struct JetBrainsProbe: StorageProbe {
    var cachesRoot = URL.home("Library/Caches/JetBrains")
    var settingsRoot = URL.home("Library/Application Support/JetBrains")

    /// One versioned folder name, such as `PyCharmCE2024.3`.
    struct Version: Comparable, Hashable, Sendable {
        let product: String
        let year: Int
        let minor: Int

        static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.year, lhs.minor) < (rhs.year, rhs.minor)
        }

        var label: String { "\(product) \(year).\(minor)" }
        var folderName: String { "\(product)\(year).\(minor)" }
    }

    /// Nil for anything that is not a product name followed by a
    /// `year.minor` version: Toolbox, consent options and the shared folders
    /// belong to every version at once and are never offered.
    static func version(ofFolder name: String) -> Version? {
        guard let match = name.wholeMatch(of: /([A-Za-z]+)(\d{4})\.(\d{1,2})/),
              let year = Int(match.2), let minor = Int(match.3)
        else { return nil }
        return Version(product: String(match.1), year: year, minor: minor)
    }

    func probe() async -> [StorageItem] {
        var versions: Set<Version> = []
        for root in [cachesRoot, settingsRoot] {
            for folder in root.children() where folder.isDirectory {
                if let version = Self.version(ofFolder: folder.lastPathComponent) { versions.insert(version) }
            }
        }
        let newest = Dictionary(grouping: versions, by: \.product).compactMapValues { $0.max() }

        var items: [StorageItem] = []
        for version in versions.sorted(by: { ($0.product, $0) < ($1.product, $1) }) {
            let caches = cachesRoot.appending(path: version.folderName)
            let settings = settingsRoot.appending(path: version.folderName)

            if newest[version.product] == version {
                if let item = await ProbeSupport.directoryItem(
                    id: "jetbrains-caches-\(version.folderName)", category: .tools,
                    name: "\(version.label) caches",
                    detail: "Indexes and local history of the current version. Rebuilt on the next launch, which takes a while on a large project.",
                    url: caches, safety: .safe, action: .emptyDirectories([caches]),
                    minimumBytes: 20 * ProbeSupport.megabyte
                ) {
                    items.append(item)
                }
                continue
            }

            // An old version: its caches and its settings go together, since
            // nothing reads either once the newer version has imported them.
            let paths = [caches, settings].filter(\.exists)
            var bytes: Int64 = 0
            var lastModified: Date?
            for path in paths {
                let measured = await DiskSize.measure(at: path)
                bytes += measured.bytes
                if let date = measured.lastModified, date > (lastModified ?? .distantPast) { lastModified = date }
            }
            guard bytes >= 20 * ProbeSupport.megabyte else { continue }
            items.append(StorageItem(
                id: "jetbrains-old-\(version.folderName)", category: .tools,
                name: "\(version.label) (older version)",
                detail: "Caches, settings and plugins of a version a newer \(version.product) has replaced. Keep it if you still launch this version.",
                sizeBytes: bytes, safety: .review, action: .removePaths(paths),
                revealURL: paths.first, lastModified: lastModified
            ))
        }
        return items.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
    }
}

// MARK: - Unity

/// Unity's package and Asset Store caches, and the editors Unity Hub has
/// installed: a few gigabytes each, one per project's version.
struct UnityProbe: StorageProbe {
    var unityRoot = URL.home("Library/Unity")
    var editorsRoot = URL(fileURLWithPath: "/Applications/Unity/Hub/Editor")

    func probe() async -> [StorageItem] {
        var items: [StorageItem] = []

        let packages = unityRoot.appending(path: "cache")
        if let item = await ProbeSupport.directoryItem(
            id: "unity-cache", category: .tools, name: "Unity package cache",
            detail: "Packages the Package Manager downloaded. Fetched again when a project needs them.",
            url: packages, safety: .safe, action: .emptyDirectories([packages]),
            minimumBytes: 20 * ProbeSupport.megabyte
        ) {
            items.append(item)
        }

        for store in unityRoot.children() where store.isDirectory && store.lastPathComponent.hasPrefix("Asset Store") {
            if let item = await ProbeSupport.directoryItem(
                id: "unity-\(store.lastPathComponent)", category: .tools, name: "Unity Asset Store downloads",
                detail: "Asset packages downloaded from the Asset Store. Imported assets stay in their projects; these download again from My Assets.",
                url: store, safety: .review, action: .removePaths([store]),
                minimumBytes: 20 * ProbeSupport.megabyte
            ) {
                items.append(item)
            }
        }

        // Unity Hub keeps its own list of installs; deleting the folder
        // behind its back leaves a broken entry in it.
        for editor in editorsRoot.children() where editor.isDirectory {
            if let item = await ProbeSupport.directoryItem(
                id: "unity-editor-\(editor.lastPathComponent)", category: .tools,
                name: "Unity \(editor.lastPathComponent)",
                detail: "An editor installed by Unity Hub. Projects made with this version ask for it again.",
                url: editor, safety: .manual,
                action: .manual("Unity Hub > Installs > the ⋯ button next to \(editor.lastPathComponent) > Uninstall."),
                minimumBytes: 100 * ProbeSupport.megabyte
            ) {
                items.append(item)
            }
        }
        return items.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
    }
}
