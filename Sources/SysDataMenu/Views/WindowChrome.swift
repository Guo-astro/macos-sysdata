import SwiftUI

// The pieces the window is built from, so the header, the list and the footer
// share one shape language: round icon buttons, cards with a soft edge and a
// lift on hover, and one switch that slides rather than snaps.

/// A round, borderless icon button for the header. A faint disc appears under
/// the pointer, so a row of bare symbols still reads as buttons.
struct RoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundIconBody(configuration: configuration)
    }

    private struct RoundIconBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(.quaternary.opacity(configuration.isPressed ? 0.9 : isHovered ? 0.6 : 0))
                )
                .contentShape(Circle())
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }
}

/// Rescan, with the scan's progress drawn as a ring around it and the arrow
/// turning while it runs: one control that both starts the scan and shows it.
struct ScanButton: View {
    let isScanning: Bool
    /// Probes finished out of probes started; nil when the scan has not said.
    let progress: Double?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if isScanning {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: progress ?? 0.25)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 22, height: 22)
                        .animation(.easeOut(duration: 0.3), value: progress)
                }
                if isScanning && !reduceMotion {
                    TimelineView(.animation) { context in
                        let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(angle))
                    }
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: isScanning ? 10 : 13, weight: .medium))
                }
            }
        }
        .buttonStyle(RoundIconButtonStyle())
        .disabled(isScanning)
        .accessibilityLabel(isScanning ? L("Scanning") : L("Rescan"))
        .help(L("Rescan"))
    }
}

/// The two ways to read the list. A pill slides between them, so the change
/// of view is something seen happening rather than a swap.
struct ModeSwitch: View {
    @Binding var byProject: Bool
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            option(L("By category"), symbol: "square.grid.2x2.fill", value: false)
            option(L("By project"), symbol: "folder.fill", value: true)
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
        // The segmented picker it replaced was announced as one control with
        // a name; the two buttons keep that name as a group.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Group by"))
    }

    private func option(_ title: String, symbol: String, value: Bool) -> some View {
        let isOn = byProject == value
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) { byProject = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isOn {
                        // Lighter than the track in both appearances: white
                        // in light, a lifted grey in dark.
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The card every group in the list sits on: a soft fill, an edge that
/// catches the light, and a slight lift while it is pointed at.
struct ListCard: ViewModifier {
    var isRaised = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary.opacity(isRaised ? 0.42 : 0.24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.12), .white.opacity(0.03)],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                    .shadow(color: .black.opacity(isRaised ? 0.16 : 0), radius: 8, y: 3)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRaised)
    }
}

extension View {
    func listCard(raised: Bool = false) -> some View {
        modifier(ListCard(isRaised: raised))
    }
}
