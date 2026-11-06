import AppKit
import Combine
import SwiftUI

private let appDelegate = AppDelegate()

@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let touchBar = TouchBarController()
    let shortcuts = ShortcutCenter()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var iconObserver: AnyCancellable?

    override init() {
        super.init()
        shortcuts.onToggle = { [weak self] in
            self?.touchBar.toggle()
            self?.keepStatusItemVisible()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        iconObserver = touchBar.$isOn.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateIcon()
            self?.keepStatusItemVisible()
        }
        touchBar.reapplyIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.restoreForQuit()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(toggleMenu(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuView(controller: touchBar, shortcuts: shortcuts) {
                NSApplication.shared.terminate(nil)
            }
        )
        if #available(macOS 13.0, *) {
            (popover.contentViewController as? NSHostingController<MenuView>)?.sizingOptions = .preferredContentSize
        }
        self.popover = popover
    }

    /// Covering the Touch Bar can drop a SwiftUI menu-bar extra. Recreate this item if that happens.
    private func keepStatusItemVisible() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.statusItem == nil || self.statusItem?.button == nil {
                self.installStatusItem()
            }
            self.statusItem?.isVisible = true
            self.updateIcon()
        }
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                if self.statusItem?.button == nil {
                    self.installStatusItem()
                }
                self.statusItem?.isVisible = true
                self.updateIcon()
            }
        }
    }

    private func updateIcon() {
        let on = touchBar.isOn
        let symbol = on ? "keyboard" : "keyboard.slash"
        let description = on ? "Touch Bar on" : "Touch Bar off"
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "TouchbarControl"
    }

    @objc private func toggleMenu(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct MenuView: View {
    @ObservedObject var controller: TouchBarController
    @ObservedObject var shortcuts: ShortcutCenter
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Touch Bar")
                .font(.headline)

            if controller.isAvailable {
                Toggle("On", isOn: Binding(
                    get: { controller.isOn },
                    set: { controller.setOn($0) }
                ))
                .toggleStyle(.switch)

                Text(controller.isOn
                    ? "The Touch Bar is on."
                    : "The Touch Bar is off. Hold Fn to show the function keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This Mac has no Touch Bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcut")
                Text("Double-tap the Shift key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if shortcuts.needsPermission {
                    Text("Accessibility permission is required for the shortcut to work in other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Allow") {
                        shortcuts.requestPermission()
                    }
                }
            }
            .onAppear {
                shortcuts.refreshPermission()
            }

            if !controller.status.isEmpty {
                Text(controller.status)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit", action: onQuit)
        }
        .padding(16)
        .frame(width: 300)
    }
}
