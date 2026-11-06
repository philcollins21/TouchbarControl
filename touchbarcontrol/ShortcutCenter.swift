import AppKit
import ApplicationServices
import Combine

/// Toggles the Touch Bar when Shift is tapped twice in a row.
final class ShortcutCenter: ObservableObject {
    @Published private(set) var needsPermission = false

    var onToggle: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shiftIsDown = false
    private var firstDown: Date?
    private var firstUp: Date?
    private let maxHold: TimeInterval = 0.3
    private let maxGap: TimeInterval = 0.35

    init() {
        refreshPermission()
        start()
    }

    deinit {
        stop()
    }

    func refreshPermission() {
        needsPermission = !AXIsProcessTrusted()
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermission()
    }

    private func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let down = modifiers.contains(.shift)
        if !modifiers.intersection([.command, .option, .control]).isEmpty {
            shiftIsDown = down
            clearTap()
            return
        }
        guard down != shiftIsDown else { return }
        shiftIsDown = down

        let now = Date()
        if down {
            if let up = firstUp, now.timeIntervalSince(up) <= maxGap {
                clearTap()
                onToggle?()
            } else {
                firstDown = now
                firstUp = nil
            }
        } else if let downAt = firstDown, now.timeIntervalSince(downAt) <= maxHold {
            firstUp = now
        } else {
            clearTap()
        }
    }

    private func clearTap() {
        firstDown = nil
        firstUp = nil
    }
}
