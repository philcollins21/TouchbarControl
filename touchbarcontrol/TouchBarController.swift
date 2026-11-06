import AppKit
import Combine
import IOKit

extension NSTouchBar {
    /// Undocumented AppKit entry points used by system controls to cover the whole Touch Bar.
    static var canCoverTouchBar: Bool {
        let present = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let dismiss = NSSelectorFromString("dismissSystemModalTouchBar:")
        let meta = self as AnyObject
        return meta.responds(to: present) && meta.responds(to: dismiss)
    }

    static func coverTouchBar(_ touchBar: NSTouchBar, identifier: NSTouchBarItem.Identifier) {
        let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let method = unsafeBitCast(
            (self as AnyObject).method(for: selector),
            to: (@convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void).self
        )
        // Placement 1 replaces the entire Touch Bar, including the Control Strip and Escape.
        method(self, selector, touchBar, 1, identifier.rawValue as NSString)
    }

    static func uncoverTouchBar(_ touchBar: NSTouchBar) {
        let selector = NSSelectorFromString("dismissSystemModalTouchBar:")
        _ = (self as AnyObject).perform(selector, with: touchBar)
    }
}

/// Turns the Touch Bar off by covering it, then restores the previous system layout.
final class TouchBarController: NSObject, ObservableObject, NSTouchBarDelegate {
    @Published private(set) var isAvailable = false
    @Published private(set) var isOn = true
    @Published private(set) var status = ""

    private let enabledKey = "touchBarOn"
    private let savedModeKey = "touchBarSavedPresentationMode"
    private let presentationKey = "PresentationModeGlobal"
    private let touchBarDefaults = UserDefaults(suiteName: "com.apple.touchbar.agent")

    private var modalTouchBar: NSTouchBar?
    private var savedPresentationMode: String?
    private var pendingCover: DispatchWorkItem?
    private var fnMonitor: Any?
    private var localFnMonitor: Any?
    private var fnDown = false

    private enum ItemID {
        static let cover = NSTouchBarItem.Identifier("canosman.touchbarcontrol.cover")
        static let escape = NSTouchBarItem.Identifier("canosman.touchbarcontrol.escape")
    }

    override init() {
        super.init()
        isAvailable = Self.hardwarePresent()
        if let stored = UserDefaults.standard.object(forKey: enabledKey) as? Bool {
            isOn = stored
        }
    }

    func reapplyIfNeeded() {
        guard isAvailable, !isOn else { return }
        cover()
    }

    func setOn(_ on: Bool) {
        apply(on, save: true)
    }

    private func apply(_ on: Bool, save: Bool) {
        guard isAvailable else {
            status = "This Mac has no Touch Bar."
            return
        }
        guard NSTouchBar.canCoverTouchBar else {
            status = "This version of macOS cannot turn the Touch Bar off."
            return
        }
        isOn = on
        if save {
            UserDefaults.standard.set(on, forKey: enabledKey)
        }
        status = ""
        if on {
            uncover(restartControlStrip: true)
        } else {
            cover()
        }
    }

    func toggle() {
        setOn(!isOn)
    }

    /// Puts the system Touch Bar layout back before the app exits. The saved on/off choice stays.
    func restoreForQuit() {
        let changedSystem = modalTouchBar != nil
            || pendingCover != nil
            || savedPresentationMode != nil
            || UserDefaults.standard.string(forKey: savedModeKey) != nil
        guard changedSystem else { return }
        uncover(restartControlStrip: true)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        item.view = view
        return item
    }

    private func cover() {
        guard modalTouchBar == nil else { return }
        pendingCover?.cancel()
        rememberPresentationMode()
        touchBarDefaults?.set("app", forKey: presentationKey)
        touchBarDefaults?.synchronize()
        startFnMonitor()

        let work = DispatchWorkItem { [weak self] in
            self?.presentCover()
        }
        pendingCover = work
        ControlStripProcess.restart()

        DispatchQueue.global(qos: .userInteractive).async {
            let deadline = Date().addingTimeInterval(0.6)
            while Date() < deadline {
                if work.isCancelled { return }
                if ControlStripProcess.isRunning { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
            Thread.sleep(forTimeInterval: 0.15)
            guard !work.isCancelled else { return }
            DispatchQueue.main.async(execute: work)
        }
    }

    private func presentCover() {
        pendingCover = nil
        guard !isOn else { return }
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [ItemID.cover]
        bar.escapeKeyReplacementItemIdentifier = ItemID.escape
        modalTouchBar = bar
        guard !fnDown else { return }
        NSTouchBar.coverTouchBar(bar, identifier: ItemID.cover)
    }

    private func uncover(restartControlStrip: Bool) {
        pendingCover?.cancel()
        pendingCover = nil
        if let bar = modalTouchBar {
            NSTouchBar.uncoverTouchBar(bar)
            modalTouchBar = nil
        }
        let mode = savedPresentationMode
            ?? UserDefaults.standard.string(forKey: savedModeKey)
            ?? "appWithControlStrip"
        touchBarDefaults?.set(mode, forKey: presentationKey)
        touchBarDefaults?.synchronize()
        savedPresentationMode = nil
        UserDefaults.standard.removeObject(forKey: savedModeKey)
        if restartControlStrip {
            ControlStripProcess.restart()
        }
    }

    private func rememberPresentationMode() {
        if let stored = UserDefaults.standard.string(forKey: savedModeKey) {
            savedPresentationMode = stored
            return
        }
        let current = touchBarDefaults?.string(forKey: presentationKey) ?? "appWithControlStrip"
        let mode = current == "app" ? "appWithControlStrip" : current
        savedPresentationMode = mode
        UserDefaults.standard.set(mode, forKey: savedModeKey)
    }

    private func startFnMonitor() {
        guard fnMonitor == nil else { return }
        fnMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        localFnMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let down = event.modifierFlags.contains(.function)
        guard down != fnDown else { return }
        fnDown = down
        guard !isOn, let bar = modalTouchBar else { return }
        if down {
            NSTouchBar.uncoverTouchBar(bar)
        } else {
            NSTouchBar.coverTouchBar(bar, identifier: ItemID.cover)
        }
    }

    private static func hardwarePresent() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOUSBHostDevice"),
            &iterator
        ) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if !found,
               let product = IORegistryEntryCreateCFProperty(
                   service,
                   "USB Product Name" as CFString,
                   kCFAllocatorDefault,
                   0
               )?.takeRetainedValue() as? String,
               product == "Touch Bar Display" {
                found = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return found
    }
}

private enum ControlStripProcess {
    static func restart() {
        run("/usr/bin/killall", arguments: ["ControlStrip"])
    }

    static var isRunning: Bool {
        run("/usr/bin/pgrep", arguments: ["-x", "ControlStrip"]) == 0
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
