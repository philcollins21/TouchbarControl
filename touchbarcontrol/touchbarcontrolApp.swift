import AppKit
import SwiftUI

@main
struct touchbarcontrolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: appDelegate.touchBar, shortcuts: appDelegate.shortcuts) {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            StatusIcon(controller: appDelegate.touchBar)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let touchBar = TouchBarController()
    let shortcuts = ShortcutCenter()

    override init() {
        super.init()
        shortcuts.onToggle = { [weak self] in
            self?.touchBar.toggle()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        touchBar.reapplyIfNeeded()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(turnTouchBarOff),
            name: Notification.Name("com.apple.screensaver.didstart"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(turnTouchBarOff),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(turnTouchBarOn),
            name: Notification.Name("com.apple.screensaver.didstop"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(turnTouchBarOn),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(turnTouchBarOn),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func turnTouchBarOff() {
        touchBar.suspendForIdle()
    }

    @objc private func turnTouchBarOn() {
        touchBar.resumeAfterIdle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.restoreForQuit()
    }
}

private struct StatusIcon: View {
    @ObservedObject var controller: TouchBarController

    var body: some View {
        Image(systemName: controller.isOn ? "keyboard" : "keyboard.slash")
            .accessibilityLabel(controller.isOn ? "Touch Bar on" : "Touch Bar off")
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
                    ? "The Touch Bar is on. It turns off for the screensaver and sleep, then turns back on."
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
