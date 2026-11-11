import AppKit
import ApplicationServices
import CoreGraphics
import UniformTypeIdentifiers

final class MouseMonitor {
    var onButton: ((Int) -> Bool)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var suppressedButtonUp: Int?

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask((1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue))
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<MouseMonitor>.fromOpaque(pointer).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .otherMouseDown || type == .otherMouseUp else { return Unmanaged.passUnretained(event) }
                let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                if type == .otherMouseUp {
                    if monitor.suppressedButtonUp == number {
                        monitor.suppressedButtonUp = nil
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                }
                if monitor.onButton?(number) == true {
                    monitor.suppressedButtonUp = number
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        runLoopSource = nil
    }
}

final class MouseQuickSwitchApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum ActionMode: String {
        case selectedApplication
        case commandTab
    }

    private let defaults = UserDefaults.standard
    private let monitor = MouseMonitor()
    private var statusItem: NSStatusItem!
    private var menu = NSMenu()
    private var recording = false
    private var enabled: Bool { defaults.object(forKey: "enabled") as? Bool ?? true }
    private var buttonNumber: Int? { defaults.object(forKey: "buttonNumber") as? Int }
    private var actionMode: ActionMode {
        ActionMode(rawValue: defaults.string(forKey: "actionMode") ?? "") ?? .selectedApplication
    }
    private var appURL: URL? {
        guard let path = defaults.string(forKey: "applicationPath") else { return nil }
        return URL(fileURLWithPath: path)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacySettings()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarIcon()
        statusItem.button?.toolTip = "MouseQuickSwitch"
        statusItem.menu = menu
        menu.delegate = self
        monitor.onButton = { [weak self] number in self?.handleButton(number) ?? false }
        _ = monitor.start()
        rebuildMenu()
    }

    private func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 6, y: 1.5, width: 11, height: 17),
                                    xRadius: 5.5, yRadius: 5.5)
            body.lineWidth = 1.6
            body.stroke()
            let wheel = NSBezierPath(roundedRect: NSRect(x: 10.5, y: 11.5, width: 2, height: 4),
                                     xRadius: 1, yRadius: 1)
            NSColor.black.setFill()
            wheel.fill()
            let sideButton = NSBezierPath(roundedRect: NSRect(x: 3.5, y: 8, width: 4, height: 4),
                                          xRadius: 1.5, yRadius: 1.5)
            sideButton.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func migrateLegacySettings() {
        guard defaults.integer(forKey: "settingsMigrationVersion") == 0 else { return }
        for domain in ["dev.mousequick.app", "dev.mouseplus.app"] {
            guard let legacy = UserDefaults(suiteName: domain) else { continue }
            for key in ["enabled", "buttonNumber", "applicationPath", "actionMode"] {
                if defaults.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(1, forKey: "settingsMigrationVersion")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if !monitor.isRunning { _ = monitor.start() }
        rebuildMenu()
    }

    private func handleButton(_ number: Int) -> Bool {
        guard number >= 3 else { return false }
        if recording {
            defaults.set(number, forKey: "buttonNumber")
            recording = false
            DispatchQueue.main.async { self.rebuildMenu() }
            return true
        }
        guard enabled, buttonNumber == number else { return false }
        switch actionMode {
        case .commandTab:
            DispatchQueue.main.async {
                self.sendCommandTab()
            }
        case .selectedApplication:
            guard let url = appURL else { return false }
            DispatchQueue.main.async { self.openApplication(url) }
        }
        return true
    }

    private func sendCommandTab() {
        let commandKey: CGKeyCode = 0x37
        let tabKey: CGKeyCode = 0x30
        guard let commandDown = CGEvent(keyboardEventSource: nil, virtualKey: commandKey, keyDown: true),
              let tabDown = CGEvent(keyboardEventSource: nil, virtualKey: tabKey, keyDown: true),
              let tabUp = CGEvent(keyboardEventSource: nil, virtualKey: tabKey, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: commandKey, keyDown: false) else { return }
        commandDown.flags = .maskCommand
        tabDown.flags = .maskCommand
        tabUp.flags = .maskCommand
        for event in [commandDown, tabDown, tabUp, commandUp] {
            event.post(tap: .cghidEventTap)
        }
    }

    private func openApplication(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            showAlert("Application not found", "Choose the application again from the MouseQuickSwitch menu.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showAlert("Could not open application", error.localizedDescription)
                    return
                }
                guard let app else { return }
                app.activate(options: [.activateAllWindows])
            }
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        addItem("MouseQuickSwitch", action: nil).isEnabled = false
        menu.addItem(.separator())
        let hasAccessibility = AXIsProcessTrusted()
        let status = monitor.isRunning ? "Listening for mouse buttons" :
            (hasAccessibility ? "Mouse input access required" : "Accessibility permission required")
        addItem(status, action: nil).isEnabled = false
        if !monitor.isRunning {
            addItem(hasAccessibility ? "Request Mouse Input Access…" : "Grant Accessibility Access…",
                    action: #selector(requestAccess))
        }
        let description = recording ? "Press the M585 side button now…" :
            (buttonNumber.map { "Recorded button: \($0 + 1)" } ?? "No side button recorded")
        addItem(description, action: nil).isEnabled = false
        addItem(recording ? "Cancel Recording" : "Record Side Button", action: #selector(toggleRecording))
        menu.addItem(.separator())
        addItem("On Button Press", action: nil).isEnabled = false
        let commandTab = addItem("Switch Between Apps (⌘Tab)", action: #selector(selectCommandTabMode))
        commandTab.state = actionMode == .commandTab ? .on : .off
        let selectedApp = addItem("Open Selected Application", action: #selector(selectApplicationMode))
        selectedApp.state = actionMode == .selectedApplication ? .on : .off
        menu.addItem(.separator())
        let target = appURL?.lastPathComponent ?? "None"
        addItem("Target: \(target)", action: nil).isEnabled = false
        addItem("Select Application…", action: #selector(selectApplication))
        let mapping = addItem("Mapping Enabled", action: #selector(toggleEnabled))
        mapping.state = enabled ? .on : .off
        menu.addItem(.separator())
        addItem("Quit MouseQuickSwitch", action: #selector(quit))
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func requestAccess() {
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        } else {
            _ = CGRequestListenEventAccess()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            _ = self.monitor.start()
            self.rebuildMenu()
        }
    }

    @objc private func toggleRecording() {
        recording.toggle()
        if recording && !monitor.start() {
            recording = false
            requestAccess()
        }
        rebuildMenu()
    }

    @objc private func selectApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            defaults.set(url.path, forKey: "applicationPath")
            rebuildMenu()
        }
    }

    @objc private func selectCommandTabMode() {
        defaults.set(ActionMode.commandTab.rawValue, forKey: "actionMode")
        rebuildMenu()
    }

    @objc private func selectApplicationMode() {
        defaults.set(ActionMode.selectedApplication.rawValue, forKey: "actionMode")
        rebuildMenu()
    }

    @objc private func toggleEnabled() {
        defaults.set(!enabled, forKey: "enabled")
        rebuildMenu()
    }

    @objc private func quit() {
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }

    private func showAlert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}

@main
struct Main {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = MouseQuickSwitchApp()
        application.delegate = delegate
        application.run()
    }
}
