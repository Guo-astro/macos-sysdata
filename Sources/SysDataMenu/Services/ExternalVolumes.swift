import Foundation

/// Plugged-in drives whose project folders the Projects view can look in.
///
/// Off unless asked for: a scan that wandered onto every drive would be slow,
/// and a drive that is not the Mac's own is not System Data. It is also
/// narrow. Only local, writable, non-internal volumes qualify, so Time
/// Machine disks, network shares and read-only disk images are never
/// walked, and on a qualifying drive only the folders people keep code in
/// are searched, not the whole volume.
enum ExternalVolumes {
    static let preferenceKey = "scansExternalDrives"

    /// Folders searched at the top of each drive, like Developer and
    /// Projects under the home folder.
    static let projectFolderNames = ["Developer", "Projects", "Projeler", "Code", "dev"]

    /// What the system says about a mounted volume.
    struct Facts: Equatable {
        var url: URL
        var isInternal: Bool
        var isLocal: Bool
        var isReadOnly: Bool
        var isStartupVolume: Bool
        var holdsTimeMachineBackups: Bool
    }

    static func isScannable(_ facts: Facts) -> Bool {
        facts.url.path.hasPrefix("/Volumes/")
            && !facts.isStartupVolume && !facts.isInternal && facts.isLocal
            && !facts.isReadOnly && !facts.holdsTimeMachineBackups
    }

    /// The code folders on every drive that qualifies right now.
    static func projectRoots() -> [URL] {
        mounted().filter(isScannable).flatMap { projectRoots(on: $0.url) }
    }

    /// The folders from `projectFolderNames` that exist at the top of a drive.
    static func projectRoots(on volume: URL) -> [URL] {
        projectFolderNames.map { volume.appending(path: $0) }.filter(\.isDirectory)
    }

    static func mounted() -> [Facts] {
        let keys: [URLResourceKey] = [
            .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Facts(
                url: url,
                isInternal: values?.volumeIsInternal ?? true,
                isLocal: values?.volumeIsLocal ?? false,
                isReadOnly: values?.volumeIsReadOnly ?? true,
                isStartupVolume: values?.volumeIsRootFileSystem ?? true,
                holdsTimeMachineBackups: url.appending(path: "Backups.backupdb").exists
            )
        }
    }
}
