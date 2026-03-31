import SwiftUI
import AppKit

@main
struct CodexSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store: AppStore { AppStore.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusLabel),
            name: .profileChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppearanceChanged),
            name: .appearanceChanged,
            object: nil
        )
        updateStatusLabel()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    @objc func updateStatusLabel() {
        guard let button = statusItem.button else { return }
        let profile = store.activeProfile
        let exhausted = store.allExhausted

        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let icon = NSImage(
            systemSymbolName: exhausted ? "exclamationmark.circle.fill" : "arrow.triangle.2.circlepath",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(cfg)

        button.image = icon
        button.imagePosition = .imageOnly
        button.title = ""
    }

    // MARK: - Popover

    private func setupPopover() {
        let content = MenuContentView().environmentObject(store)
        let controller = NSHostingController(rootView: content)

        popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true

        let isDark = UserDefaults.standard.object(forKey: "isDarkMode") as? Bool ?? true
        popover.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        popover.contentSize = NSSize(width: 340, height: 500)
    }

    @objc func handleAppearanceChanged() {
        let isDark = UserDefaults.standard.object(forKey: "isDarkMode") as? Bool ?? true
        popover.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    @objc func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            Task {
                await store.fetchAllRateLimits()
                store.refreshActiveTurns()
            }
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}

extension Notification.Name {
    static let profileChanged  = Notification.Name("ProfileChanged")
    static let appearanceChanged = Notification.Name("AppearanceChanged")
}
