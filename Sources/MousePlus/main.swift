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

final class MousePlusApp: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let monitor = MouseMonitor()
    private var statusItem: NSStatusItem!
    private var menu = NSMenu()
    private var recording = false
    private var enabled: Bool { defaults.object(forKey: "enabled") as? Bool ?? true }
    private var buttonNumber: Int? { defaults.object(forKey: "buttonNumber") as? Int }
    private var appURL: URL? {
        guard let path = defaults.string(forKey: "applicationPath") else { return nil }
        return URL(fileURLWithPath: path)
    }
    private var switchToCodex: Bool { defaults.bool(forKey: "switchToCodex") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if defaults.object(forKey: "applicationPath") == nil,
           FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app") {
            defaults.set("/Applications/ChatGPT.app", forKey: "applicationPath")
            defaults.set(true, forKey: "switchToCodex")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "M+"
        statusItem.menu = menu
        monitor.onButton = { [weak self] number in self?.handleButton(number) ?? false }
        _ = monitor.start()
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
        guard enabled, buttonNumber == number, let url = appURL else { return false }
        DispatchQueue.main.async { self.openApplication(url) }
        return true
    }

    private func openApplication(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            showAlert("Application not found", "Choose the application again from the MousePlus menu.")
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
                app?.activate(options: [.activateAllWindows])
                guard self?.switchToCodex == true,
                      url.lastPathComponent.caseInsensitiveCompare("ChatGPT.app") == .orderedSame else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.sendCodexShortcut() }
            }
        }
    }

    private func sendCodexShortcut() {
        // ANSI 3 key. ChatGPT uses Control-3 to select its Codex view.
        let keyCode: CGKeyCode = 0x14
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        addItem("MousePlus", action: nil).isEnabled = false
        menu.addItem(.separator())
        let status = monitor.isRunning ? "Listening for mouse buttons" : "Accessibility permission required"
        addItem(status, action: nil).isEnabled = false
        if !monitor.isRunning { addItem("Grant Accessibility Access…", action: #selector(requestAccess)) }
        let description = recording ? "Press the M585 side button now…" :
            (buttonNumber.map { "Recorded button: \($0 + 1)" } ?? "No side button recorded")
        addItem(description, action: nil).isEnabled = false
        addItem(recording ? "Cancel Recording" : "Record Side Button", action: #selector(toggleRecording))
        menu.addItem(.separator())
        let target = appURL?.lastPathComponent ?? "None"
        addItem("Target: \(target)", action: nil).isEnabled = false
        addItem("Select Application…", action: #selector(selectApplication))
        let codex = addItem("Switch to Codex (ChatGPT only)", action: #selector(toggleCodex))
        codex.state = switchToCodex ? .on : .off
        let mapping = addItem("Mapping Enabled", action: #selector(toggleEnabled))
        mapping.state = enabled ? .on : .off
        menu.addItem(.separator())
        addItem("Quit MousePlus", action: #selector(quit))
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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

    @objc private func toggleCodex() {
        defaults.set(!switchToCodex, forKey: "switchToCodex")
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
        let delegate = MousePlusApp()
        application.delegate = delegate
        application.run()
    }
}
