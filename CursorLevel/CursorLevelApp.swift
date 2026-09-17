import AppKit
import SwiftUI

private enum MenuBarIcon {
    static var image: NSImage {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(size: NSSize(width: 22, height: 22))
        image.isTemplate = true
        image.size = NSSize(width: 22, height: 22)
        return image
    }
}

@main
struct CursorLevelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(state: state)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
                .opacity(state.menuBarOpacity)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppState.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MouseCorrector.shared.stop()
    }
}
