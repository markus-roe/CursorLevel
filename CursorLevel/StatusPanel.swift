import AppKit
import SwiftUI

private enum Instrument {
    static let aligned = Color(red: 0.20, green: 0.43, blue: 0.40)
    static let warning = Color(red: 0.72, green: 0.45, blue: 0.16)
    static let off = Color(red: 0.45, green: 0.45, blue: 0.47)
}

private func setHandCursor(_ hovering: Bool) {
    if hovering {
        NSCursor.pointingHand.push()
    } else {
        NSCursor.pop()
    }
}

struct StatusPanel: View {
    @ObservedObject var state: AppState
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: $state.enabled) {
                    Text("Correction")
                        .font(.system(size: 13))
                }
                .toggleStyle(.switch)
                .disabled(!state.accessibilityTrusted)
                .padding(.vertical, 8)

                panelButton("Rediscover displays") {
                    state.resolveDisplays()
                }
                panelButton("Accessibility settings…") {
                    state.openAccessibilitySettings()
                }

                Toggle(isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLoginEnabled($0) }
                )) {
                    Text("Open at login")
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 6)
            }
            .padding(.top, 4)

            DisclosureGroup(isExpanded: $showDiagnostics) {
                Text(state.debugLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            } label: {
                Text("Diagnostics")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 10)

            panelButton("Quit CursorLevel") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CursorLevel")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                Text(state.statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(state.statusTitle)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.14), in: Capsule())
    }

    private var statusColor: Color {
        if !state.accessibilityTrusted {
            return Instrument.warning
        }
        if state.enabled, state.layout != nil {
            return Instrument.aligned
        }
        return Instrument.off
    }

    private func panelButton(_ title: String, action: @escaping () -> Void) -> some View {
        HoverableRow(title: title, action: action)
    }
}

private struct HoverableRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.06) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hovering = hovering
            setHandCursor(hovering)
        }
    }
}
