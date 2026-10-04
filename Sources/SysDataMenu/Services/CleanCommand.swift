import Foundation

/// `SysDataMenu --clean`: the weekly clean of Safe items, from a terminal.
///
/// It touches exactly what the automatic clean and the Shortcuts action
/// touch: Safe items that need no administrator password. Nothing under
/// Review or Manual is ever in it. Without `--apply` it only prints what it
/// would do, command by command, and deletes nothing; the destructive form
/// has to be asked for by name.
@MainActor
enum CleanCommand {
    enum Request: Equatable {
        case notRequested
        case plan
        case apply
        case invalid(String)
    }

    static func parse(_ arguments: [String]) -> Request {
        let flags = Set(arguments.dropFirst().filter { $0.hasPrefix("--") })
        let known: Set<String> = ["--clean", "--apply"]
        if let unknown = flags.subtracting(known).sorted().first,
           flags.contains("--clean") || flags.contains("--apply") {
            return .invalid("Unknown option \(unknown). Usage: SysDataMenu --clean [--apply]")
        }
        guard flags.contains("--clean") else {
            return flags.contains("--apply")
                ? .invalid("--apply only works with --clean. Usage: SysDataMenu --clean [--apply]")
                : .notRequested
        }
        return flags.contains("--apply") ? .apply : .plan
    }

    /// What a run is about to do, one item and one command per line, so the
    /// output can be read before anything is allowed to run.
    static func plan(for items: [StorageItem]) -> String {
        guard !items.isEmpty else { return "Nothing marked Safe is taking space right now." }
        let total = items.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        var lines = ["\(items.count) Safe items, \(total.byteString):"]
        for item in items {
            lines.append("  \((item.sizeBytes ?? 0).byteString)  \(item.name)")
            for operation in item.action.plan { lines.append("      \(operation)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Returns the exit status: 0 when it finished, 1 when something failed
    /// or the scan did not complete, so a script can tell.
    static func run(apply: Bool) async -> Int32 {
        let model = ScanModel(scansAutomatically: false)
        await model.scan()
        guard !model.isScanning else {
            printError("The scan did not finish. Try again.")
            return 1
        }
        let items = model.safeAutoItems.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        print(plan(for: items))
        guard apply, !items.isEmpty else {
            if !apply, !items.isEmpty {
                print("\nDry run: nothing was deleted. Run again with --apply to delete these.")
            }
            return 0
        }
        let before = model.reclaimedBytes
        await model.reclaimSafeNow()
        let freed = model.reclaimedBytes - before
        if let message = model.errorMessage {
            printError(message)
            return 1
        }
        print("\nFreed \(freed.byteString).")
        return 0
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
