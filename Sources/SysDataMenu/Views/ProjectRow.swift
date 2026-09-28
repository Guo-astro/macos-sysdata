import SwiftUI

/// One project in the Projects view: what it costs in total, what that is
/// made of, how long it has sat untouched, and the one button that frees it.
struct ProjectRow: View {
    let project: ProjectFootprint
    let isBusy: Bool
    let onArchive: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CategoryIcon(category: .projects)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    badge
                }
                Text(project.folder.abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(breakdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(project.totalBytes.byteString)
                    .monospacedDigit()
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("Archive"), action: onArchive)
                        .controlSize(.small)
                        .disabled(project.archivableItems.isEmpty)
                        .help(L("Delete what this project's build recreates. Its source files are never touched."))
                }
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(L("Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([project.folder])
            }
            .disabled(!project.exists)
        }
        .accessibilityElement(children: .contain)
    }

    /// "node_modules 4.1 GB · DerivedData 2.3 GB"
    private var breakdown: String {
        project.items
            .map { "\($0.partName) \(($0.sizeBytes ?? 0).byteString)" }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var badge: some View {
        if !project.exists {
            // The build output of a project that is gone is the easiest space
            // on the disk: nothing will ever use it again.
            label(L("Project deleted"), tint: .red)
                .help(L("The project folder no longer exists, so nothing will rebuild or use this."))
        } else if let days = project.idleDays, let phrase = StorageItem.idlePhrase(days: days) {
            label(phrase, tint: days >= ScanModel.idleProjectDays ? .accentColor : .secondary)
                .help(L("Nobody has changed this project's own files in %lld days.", days))
        }
    }

    private func label(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
            .fixedSize()
    }
}
