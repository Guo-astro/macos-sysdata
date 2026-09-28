import AppKit
import SwiftUI

/// An image of what this Mac's projects cost, sized for a post.
///
/// It names no project: people's project names are often their clients',
/// and a card meant to be pasted anywhere should carry nothing that has to be
/// checked first. What it shows is the totals and what they are made of.
struct ProjectShareCard: View {
    let projects: [ProjectFootprint]

    private var total: Int64 { projects.reduce(0) { $0 + $1.totalBytes } }
    private var idle: [ProjectFootprint] {
        projects.filter { !$0.exists || ($0.idleDays ?? 0) >= ScanModel.idleProjectDays }
    }

    /// Build output by kind across every project, largest first, the tail
    /// folded into one part so the bar stays readable.
    private var parts: [(name: String, bytes: Int64)] {
        var byName: [String: Int64] = [:]
        for item in projects.flatMap(\.items) {
            byName[item.partName, default: 0] += item.sizeBytes ?? 0
        }
        let sorted = byName.sorted { $0.value > $1.value }.map { (name: $0.key, bytes: $0.value) }
        guard sorted.count > 4 else { return sorted }
        let rest = sorted.dropFirst(3).reduce(0) { $0 + $1.bytes }
        return Array(sorted.prefix(3)) + [(name: L("Other"), bytes: rest)]
    }

    private static let palette: [Color] = [.green, .blue, .orange, .pink, .purple]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                Text("System Data Unpacked")
                    .font(.headline)
            }
            .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("My Mac keeps"))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Text(total.byteString)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
                Text(projects.count == 1
                     ? L("of build output for 1 project")
                     : L("of build output for %lld projects", projects.count))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if !idle.isEmpty {
                Text(L("%@ of it belongs to projects nobody has touched in %lld+ days.",
                       idle.reduce(0) { $0 + $1.totalBytes }.byteString, ScanModel.idleProjectDays))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }

            bar
            legend

            Spacer(minLength: 0)
            HStack {
                Text("macos-sysdata.yigitech.dev")
                Spacer()
                Text(L("Free and open source"))
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
        .padding(28)
        .frame(width: 600, height: 338, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(red: 0.07, green: 0.10, blue: 0.16), Color(red: 0.12, green: 0.17, blue: 0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .dark)
    }

    private var bar: some View {
        GeometryReader { geometry in
            let whole = CGFloat(max(total, 1))
            HStack(spacing: 3) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    Capsule()
                        .fill(Self.palette[index % Self.palette.count])
                        .frame(width: max((geometry.size.width - 3 * CGFloat(parts.count)) * CGFloat(part.bytes) / whole, 4))
                }
            }
        }
        .frame(height: 10)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Self.palette[index % Self.palette.count])
                        .frame(width: 8, height: 8)
                    Text(part.name)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(part.bytes.byteString)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .font(.caption)
                .lineLimit(1)
            }
        }
    }

    /// The card as a picture, at twice its size so it stays sharp in a post.
    @MainActor
    static func image(for projects: [ProjectFootprint]) -> NSImage? {
        let renderer = ImageRenderer(content: ProjectShareCard(projects: projects))
        renderer.scale = 2
        return renderer.nsImage
    }
}
