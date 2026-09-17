import AppKit
import ApplicationServices
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let config = AppConfig()

    @Published private(set) var layout: ResolvedLayout?
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "enabled")
            MouseCorrector.shared.setEnabled(enabled)
            refreshStatus()
        }
    }

    @Published private(set) var accessibilityTrusted = false
    @Published var launchAtLogin = false

    @Published private(set) var statusDetail = "Startet…"
    @Published private(set) var debugLine = ""

    private var accessibilityTimer: Timer?
    private var debugTimer: Timer?

    var menuBarOpacity: Double {
        if !accessibilityTrusted || !enabled || layout == nil {
            return 0.45
        }
        return 1
    }

    var statusTitle: String {
        if !accessibilityTrusted {
            return "Setup"
        }
        if !enabled {
            return "Off"
        }
        if layout == nil {
            return "Paused"
        }
        return "Active"
    }

    private init() {
        enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        MouseCorrector.shared.setEnabled(enabled)
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resolveDisplays()
            }
        }

        accessibilityTrusted = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if !accessibilityTrusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        MouseCorrector.shared.start()
        resolveDisplays()

        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollAccessibility()
            }
        }
        debugTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDebug()
            }
        }
    }

    func resolveDisplays() {
        layout = DisplayResolver.resolve(config)
        MouseCorrector.shared.updateLayout(layout, config: config)
        refreshStatus()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        launchAtLogin = isEnabled
        setLaunchAtLogin(isEnabled)
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for value in urls {
            if let url = URL(string: value) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private func pollAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
            if trusted {
                MouseCorrector.shared.start()
                resolveDisplays()
            }
            refreshStatus()
        } else if trusted && !MouseCorrector.shared.copyStats().tapInstalled {
            MouseCorrector.shared.start()
            resolveDisplays()
            refreshStatus()
        }
    }

    private func refreshDebug() {
        let stats = MouseCorrector.shared.copyStats()
        let mouse = NSEvent.mouseLocation
        var screen = "other"
        if let layout {
            if layout.left.contains(mouse) {
                screen = "left"
            } else if layout.right.contains(mouse) {
                screen = "right"
            }
        }
        debugLine = String(
            format: "tap %@  events %llu  remaps %llu  tap-role %@  mouse %@  (%.0f, %.0f)",
            stats.tapKind,
            stats.eventCount,
            stats.remapCount,
            stats.lastRole,
            screen,
            mouse.x,
            mouse.y
        )
    }

    private func refreshStatus() {
        if !accessibilityTrusted {
            statusDetail = "Grant Accessibility, then quit and reopen."
        } else if !enabled {
            statusDetail = "Pointer correction is off."
        } else if let layout {
            let left = String(format: "%@ %.1f″", layout.leftName, layout.left.inches)
            let right = String(format: "%@ %.1f″", layout.rightName, layout.right.inches)
            statusDetail = layout.measured
                ? "\(left)  →  \(right)"
                : "\(left)  →  \(right)  · sizes from Config"
        } else {
            statusDetail = "The two external displays were not found."
        }
        objectWillChange.send()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[cursorlevel] Launch at login failed: \(error.localizedDescription)")
        }
    }
}
