import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid
import SwiftUI
import UniformTypeIdentifiers

private func detectedM585() -> Bool {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
    return devices.contains { device in
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        return vendor == 0x046d && product?.localizedCaseInsensitiveContains("M585") == true
    }
}

final class MouseMonitor {
    var onButton: ((Int) -> Bool)?
    var onButtonObserved: ((Int) -> Void)?
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
                let handled = monitor.onButton?(number) == true
                monitor.onButtonObserved?(number)
                if handled {
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

final class MouseQuickSwitchApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private enum ActionMode: String {
        case selectedApplication
        case commandTab
    }

    private enum Language: String {
        case system
        case english
        case chinese
    }

    private let defaults = UserDefaults.standard
    private let monitor = MouseMonitor()
    private var statusItem: NSStatusItem!
    private var menu = NSMenu()
    private var setupWindow: NSWindow?
    private var permissionTimer: Timer?
    private let setupState = SetupState()
    private var recording = false
    private var languagePreference: Language {
        Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
    }
    private var language: Language {
        if languagePreference != .system { return languagePreference }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }
    private func tr(_ english: String, _ chinese: String) -> String {
        language == .chinese ? chinese : english
    }
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
        monitor.onButtonObserved = { [weak self] number in self?.observeButton(number) }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemSettingsDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        _ = monitor.start()
        rebuildMenu()
        if buttonNumber == nil || defaults.bool(forKey: "resumeSetupAfterAccess") {
            DispatchQueue.main.async { self.showSetup() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard defaults.bool(forKey: "resumeSetupAfterAccess"),
              setupWindow?.isVisible == false else { return }
        showSetup()
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
            DispatchQueue.main.async {
                self.refreshSetup()
                self.rebuildMenu()
            }
            return true
        }
        guard enabled, buttonNumber == number else { return false }
        if setupWindow?.isKeyWindow == true { return true }
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
            showAlert(tr("Application not found", "找不到应用"),
                      tr("Choose the application again from the MouseQuickSwitch menu.", "请在 MouseQuickSwitch 菜单中重新选择应用。"))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let self, let error else { return }
            DispatchQueue.main.async {
                self.showAlert(self.tr("Could not open application", "无法打开应用"),
                               error.localizedDescription)
            }
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let title = version.map { "MouseQuickSwitch v\($0)" } ?? "MouseQuickSwitch"
        addItem(title, action: nil).isEnabled = false
        menu.addItem(.separator())
        let setup = addItem(tr("Set Up Mouse Button…", "设置鼠标按键…"),
                            action: #selector(showSetupFromMenu))
        setup.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)
        if !monitor.isRunning {
            let hasAccessibility = AXIsProcessTrusted()
            addItem(hasAccessibility ? tr("Mouse access needed", "需要鼠标权限") :
                        tr("Accessibility access needed", "需要辅助功能权限"),
                    action: nil).isEnabled = false
            addItem(hasAccessibility ? tr("Request Mouse Input Access…", "请求鼠标输入权限…") :
                        tr("Grant Accessibility Access…", "授予辅助功能权限…"),
                    action: #selector(requestAccess))
        }
        let description = recording ? tr("Press a side button now…", "请按下要使用的侧键…") :
            (buttonNumber.map { tr("Using button \($0 + 1)", "正在使用侧键 \($0 + 1)") } ??
                tr("No side button set", "尚未设置侧键"))
        addItem(description, action: nil).isEnabled = false
        if recording {
            addItem(tr("Cancel Recording", "取消录制"), action: #selector(toggleRecording))
        }
        menu.addItem(.separator())
        addItem(tr("When I Press It", "按下侧键后"), action: nil).isEnabled = false
        let commandTab = addItem(tr("Switch to Previous App (⌘Tab)", "切换到上一个程序（⌘Tab）"),
                                 action: #selector(selectCommandTabMode))
        commandTab.state = actionMode == .commandTab ? .on : .off
        let selectedApp = addItem(tr("Switch to a Chosen App", "切换到指定程序"),
                                  action: #selector(selectApplicationMode))
        selectedApp.state = actionMode == .selectedApplication ? .on : .off
        menu.addItem(.separator())
        if actionMode == .selectedApplication {
            let target = appURL?.lastPathComponent ?? tr("None", "未选择")
            addItem(tr("Chosen app: \(target)", "指定应用：\(target)"), action: nil).isEnabled = false
            addItem(tr("Choose App…", "选择应用…"), action: #selector(selectApplication))
        }
        let mapping = addItem(tr("Enable Side Button Action", "启用侧键功能"), action: #selector(toggleEnabled))
        mapping.state = enabled ? .on : .off
        menu.addItem(.separator())
        addLanguageMenu()
        menu.addItem(.separator())
        addItem(tr("Quit MouseQuickSwitch", "退出 MouseQuickSwitch"), action: #selector(quit))
    }

    private func addLanguageMenu() {
        let parent = addItem(tr("Language", "语言"), action: nil)
        let submenu = NSMenu()
        for (choice, title) in [
            (Language.system, tr("Follow System", "跟随系统")),
            (.chinese, "简体中文"),
            (.english, "English")
        ] {
            let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = languagePreference == choice ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func requestAccess() {
        showSetup()
        defaults.set(true, forKey: "resumeSetupAfterAccess")
        setupState.feedback = tr(
            "Grant access in the system window. This setup window will be ready when you return.",
            "请在系统弹出的窗口中授权，返回后可继续使用此设置窗口。")
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        } else {
            _ = CGRequestListenEventAccess()
        }
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.setupWindow?.isVisible == true else {
                timer.invalidate()
                return
            }
            if !self.monitor.isRunning { _ = self.monitor.start() }
            self.refreshSetup()
            self.rebuildMenu()
            if self.monitor.isRunning {
                self.setupState.feedback = self.tr(
                    "Mouse access is ready. Continue choosing and testing your side button.",
                    "鼠标权限已就绪，可以继续选择并测试侧键。")
                timer.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    @objc private func toggleRecording() {
        recording.toggle()
        if recording && !monitor.start() {
            recording = false
            requestAccess()
        }
        setupState.lastPressedButton = nil
        setupState.feedback = recording
            ? tr("Waiting for a side-button press…", "正在等待你按下侧键…")
            : tr("Recording cancelled.", "已取消录制。")
        refreshSetup()
        rebuildMenu()
    }

    @objc private func selectApplication() {
        let panel = NSOpenPanel()
        panel.title = tr("Select Application", "选择应用")
        panel.prompt = tr("Select", "选择")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            defaults.set(url.path, forKey: "applicationPath")
            refreshSetup()
            setupState.feedback = tr("Chosen app: \(url.lastPathComponent)",
                                     "已选择应用：\(url.lastPathComponent)")
            rebuildMenu()
        }
    }

    @objc private func selectCommandTabMode() {
        defaults.set(ActionMode.commandTab.rawValue, forKey: "actionMode")
        refreshSetup()
        setupState.feedback = tr("Action set: switch to previous app.", "已设置：切换到上一个程序。")
        rebuildMenu()
    }

    @objc private func selectApplicationMode() {
        defaults.set(ActionMode.selectedApplication.rawValue, forKey: "actionMode")
        refreshSetup()
        setupState.feedback = tr("Action set: switch to a chosen app.", "已设置：切换到指定程序。")
        rebuildMenu()
    }

    @objc private func toggleEnabled() {
        defaults.set(!enabled, forKey: "enabled")
        refreshSetup()
        setupState.feedback = enabled
            ? tr("Side button action enabled.", "已启用侧键功能。")
            : tr("Side button action paused.", "已暂停侧键功能。")
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let choice = Language(rawValue: rawValue) else { return }
        if choice == .system {
            defaults.removeObject(forKey: "language")
        } else {
            defaults.set(choice.rawValue, forKey: "language")
        }
        refreshSetup()
        rebuildMenu()
    }

    @objc private func showSetupFromMenu() { showSetup() }

    @objc private func systemSettingsDidDeactivate(_ notification: Notification) {
        guard defaults.bool(forKey: "resumeSetupAfterAccess"),
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.systempreferences" else { return }
        DispatchQueue.main.async { self.showSetup() }
    }

    private func showSetup() {
        refreshSetup()
        if setupWindow == nil {
            let view = SetupView(state: setupState,
                                 chooseButton: { [weak self] number in self?.chooseButton(number) },
                                 record: { [weak self] in self?.toggleRecording() },
                                 switchApps: { [weak self] in self?.selectCommandTabMode() },
                                 openChosenApp: { [weak self] in self?.selectApplicationMode() },
                                 selectApp: { [weak self] in self?.selectApplication() },
                                 toggleEnabled: { [weak self] in self?.toggleEnabled() },
                                 requestAccess: { [weak self] in self?.requestAccess() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
                                  styleMask: [.titled, .closable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "MouseQuickSwitch"
            window.minSize = NSSize(width: 560, height: 700)
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.delegate = self
            setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func chooseButton(_ number: Int) {
        defaults.set(number, forKey: "buttonNumber")
        recording = false
        refreshSetup()
        setupState.lastPressedButton = nil
        setupState.feedback = number == 3
            ? tr("Back button selected. Press it to check detection.", "已选择后退键。按一下，确认能否检测到。")
            : tr("Forward button selected. Press it to check detection.", "已选择前进键。按一下，确认能否检测到。")
        rebuildMenu()
    }

    private func observeButton(_ number: Int) {
        guard setupWindow?.isVisible == true, number >= 3 else { return }
        DispatchQueue.main.async {
            self.setupState.lastPressedButton = number
            if self.buttonNumber == number {
                self.setupState.feedback = self.tr(
                    "Detected button \(number + 1) — this is your chosen button.",
                    "检测到侧键 \(number + 1)，与当前选择一致。")
            } else {
                self.setupState.feedback = self.tr(
                    "Detected button \(number + 1). Use “Record by pressing a button” to choose it.",
                    "检测到侧键 \(number + 1)。如需使用它，请点“按下侧键录制”。")
            }
        }
    }

    private func refreshSetup() {
        setupState.chinese = language == .chinese
        setupState.detected = detectedM585()
        setupState.buttonNumber = buttonNumber
        setupState.recording = recording
        setupState.canListen = monitor.isRunning
        setupState.hasAccessibility = AXIsProcessTrusted()
        setupState.switchApps = actionMode == .commandTab
        setupState.targetName = appURL?.lastPathComponent
        setupState.enabled = enabled
    }

    func windowWillClose(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if monitor.isRunning {
            defaults.removeObject(forKey: "resumeSetupAfterAccess")
        }
        if recording {
            recording = false
            refreshSetup()
            rebuildMenu()
        }
    }

    @objc private func quit() {
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }

    private func showAlert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: tr("OK", "确定"))
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
