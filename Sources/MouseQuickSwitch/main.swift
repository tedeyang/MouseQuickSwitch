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
    private let keyboardMonitor = KeyboardMonitor()
    private let keyboardState = KeyboardSetupState()
    private var keyboardWindow: NSWindow?
    private var keyboardPermissionTimer: Timer?
    private var recordingKeyUp: Int?
    private var activeKeyboardRemaps: [Int: Int] = [:]
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
        keyboardMonitor.onKey = { [weak self] type, event in
            self?.handleKey(type, event) ?? false
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemSettingsDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        _ = monitor.start()
        loadKeyboardSettings()
        if keyboardState.enabled { _ = keyboardMonitor.start() }
        refreshKeyboardSetup()
        rebuildMenu()
        if buttonNumber == nil || defaults.bool(forKey: "resumeSetupAfterAccess") {
            DispatchQueue.main.async { self.showSetup() }
        }
        if defaults.bool(forKey: "resumeKeyboardSetupAfterAccess") {
            DispatchQueue.main.async { self.showKeyboardSetup() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if defaults.bool(forKey: "resumeKeyboardSetupAfterAccess"),
           keyboardWindow?.isVisible == false {
            showKeyboardSetup()
        } else if defaults.bool(forKey: "resumeSetupAfterAccess"),
                  setupWindow?.isVisible == false {
            showSetup()
        }
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
        if keyboardState.enabled && !keyboardMonitor.isRunning {
            _ = keyboardMonitor.start()
            refreshKeyboardSetup()
        }
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

        addItem(tr("Mouse Button", "鼠标按键"), action: nil).isEnabled = false
        addItem(tr("Set Up Mouse Button…", "设置鼠标按键…"),
                action: #selector(showSetupFromMenu)).indentationLevel = 1
        let buttonDescription = recording ? tr("Press a side button now…", "请按下要使用的侧键…") :
            (buttonNumber.map { tr("Button \($0 + 1) selected", "已选择侧键 \($0 + 1)") } ??
                tr("No button selected", "尚未选择按键"))
        let buttonStatus = addItem(buttonDescription, action: nil)
        buttonStatus.isEnabled = false
        buttonStatus.indentationLevel = 1
        if recording {
            addItem(tr("Cancel Recording", "取消录制"),
                    action: #selector(toggleRecording)).indentationLevel = 1
        }
        if !monitor.isRunning {
            let hasAccessibility = AXIsProcessTrusted()
            addItem(hasAccessibility ? tr("Request Mouse Input Access…", "请求鼠标输入权限…") :
                        tr("Grant Accessibility Access…", "授予辅助功能权限…"),
                    action: #selector(requestAccess)).indentationLevel = 1
        }
        let actionTitle = actionMode == .commandTab
            ? tr("Action: Previous App", "动作：切换到上一个程序")
            : tr("Action: Chosen App", "动作：切换到指定程序")
        let actionMenuItem = addItem(actionTitle, action: nil)
        actionMenuItem.indentationLevel = 1
        let actionMenu = NSMenu()
        let commandTab = addItem(tr("Switch to Previous App (⌘Tab)", "切换到上一个程序（⌘Tab）"),
                                 action: #selector(selectCommandTabMode), to: actionMenu)
        commandTab.state = actionMode == .commandTab ? .on : .off
        let selectedApp = addItem(tr("Switch to a Chosen App", "切换到指定程序"),
                                  action: #selector(selectApplicationMode), to: actionMenu)
        selectedApp.state = actionMode == .selectedApplication ? .on : .off
        actionMenuItem.submenu = actionMenu
        if actionMode == .selectedApplication {
            let target = appURL?.lastPathComponent ?? tr("None", "未选择")
            let targetItem = addItem(tr("Chosen app: \(target)", "指定程序：\(target)"), action: nil)
            targetItem.isEnabled = false
            targetItem.indentationLevel = 1
            addItem(tr("Choose App…", "选择程序…"),
                    action: #selector(selectApplication)).indentationLevel = 1
        }
        let mapping = addItem(tr("Enable Side Button Action", "启用侧键功能"), action: #selector(toggleEnabled))
        mapping.state = enabled ? .on : .off
        mapping.indentationLevel = 1

        menu.addItem(.separator())
        addItem(tr("Keyboard Mappings", "键盘映射"), action: nil).isEnabled = false
        addItem(tr("Set Up Keyboard Keys…", "设置键盘按键…"),
                action: #selector(showKeyboardSetupFromMenu)).indentationLevel = 1
        let configuredCount = keyboardState.mappings.filter {
            $0.source != nil && $0.target != nil
        }.count
        let keyboardSummary = keyboardState.appName.map {
            tr("\($0): \(configuredCount) mappings", "\($0)：已设置 \(configuredCount) 组")
        } ?? tr("No app selected", "尚未选择目标程序")
        let keyboardStatus = addItem(keyboardSummary, action: nil)
        keyboardStatus.isEnabled = false
        keyboardStatus.indentationLevel = 1
        let keyboardToggle = addItem(tr("Enable Keyboard Mappings", "启用键盘映射"),
                                     action: #selector(toggleKeyboardFromMenu))
        keyboardToggle.state = keyboardState.enabled ? .on : .off
        keyboardToggle.indentationLevel = 1
        if keyboardState.enabled && !keyboardMonitor.isRunning {
            let access = addItem(tr("Keyboard access required", "需要键盘输入权限"), action: nil)
            access.isEnabled = false
            access.indentationLevel = 1
        }
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
    private func addItem(_ title: String, action: Selector?, to parent: NSMenu? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        (parent ?? menu).addItem(item)
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

    @objc private func showKeyboardSetupFromMenu() { showKeyboardSetup() }

    @objc private func toggleKeyboardFromMenu() {
        if !keyboardState.enabled &&
           (keyboardState.appName == nil ||
            !keyboardState.mappings.contains(where: { $0.source != nil && $0.target != nil })) {
            showKeyboardSetup()
            keyboardState.feedback = tr("Choose an app and record both keys first.",
                                        "请先选择程序并录制一组完整的按键。")
            return
        }
        if !keyboardState.enabled && !keyboardMonitor.start() {
            showKeyboardSetup()
            return
        }
        refreshKeyboardSetup()
        toggleKeyboardMappings()
        rebuildMenu()
    }

    private func loadKeyboardSettings() {
        if let data = defaults.data(forKey: "keyboardMappings"),
           let mappings = try? JSONDecoder().decode([KeyMapping].self, from: data) {
            keyboardState.mappings = Array(mappings.prefix(3))
            while keyboardState.mappings.count < 3 {
                keyboardState.mappings.append(KeyMapping())
            }
            keyboardState.visibleRows = max(
                1, (keyboardState.mappings.lastIndex(where: {
                    $0.source != nil || $0.target != nil
                }) ?? 0) + 1)
        }
        keyboardState.appName = defaults.string(forKey: "keyboardAppPath")
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        keyboardState.enabled = defaults.bool(forKey: "keyboardEnabled")
    }

    private func saveKeyboardMappings() {
        guard let data = try? JSONEncoder().encode(keyboardState.mappings) else { return }
        defaults.set(data, forKey: "keyboardMappings")
    }

    private func refreshKeyboardSetup() {
        keyboardState.chinese = language == .chinese
        keyboardState.canListen = keyboardMonitor.isRunning
    }

    private func showKeyboardSetup() {
        if !keyboardMonitor.isRunning { _ = keyboardMonitor.start() }
        refreshKeyboardSetup()
        if keyboardWindow == nil {
            let view = KeyboardSetupView(
                state: keyboardState,
                chooseApp: { [weak self] in self?.chooseKeyboardApp() },
                record: { [weak self] index, target in self?.recordKeyboardKey(index, target: target) },
                clear: { [weak self] index in self?.clearKeyboardMapping(index) },
                toggle: { [weak self] in self?.toggleKeyboardMappings() },
                requestAccess: { [weak self] in self?.requestKeyboardAccess() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                                  styleMask: [.titled, .closable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = tr("Keyboard Key Mappings", "键盘按键映射")
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.delegate = self
            keyboardWindow = window
        }
        keyboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func chooseKeyboardApp() {
        keyboardState.recordingIndex = nil
        let panel = NSOpenPanel()
        panel.title = tr("Choose App for Keyboard Mappings", "选择键盘映射生效的程序")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.path, forKey: "keyboardAppPath")
        defaults.set(Bundle(url: url)?.bundleIdentifier, forKey: "keyboardAppID")
        keyboardState.appName = url.lastPathComponent
        keyboardState.feedback = tr("Keyboard mappings will work in \(url.lastPathComponent).",
                                    "键盘映射只在 \(url.lastPathComponent) 中生效。")
    }

    private func recordKeyboardKey(_ index: Int, target: Bool) {
        guard keyboardMonitor.start() else {
            requestKeyboardAccess()
            return
        }
        keyboardState.recordingIndex = index
        keyboardState.recordingTarget = target
        keyboardState.feedback = target
            ? tr("Press the key to send.", "请按要输出的目标键。")
            : tr("Press the key to replace.", "请按要替换的源按键。")
    }

    private func clearKeyboardMapping(_ index: Int) {
        keyboardState.mappings[index] = KeyMapping()
        keyboardState.recordingIndex = nil
        saveKeyboardMappings()
        keyboardState.feedback = tr("Mapping \(index + 1) cleared.", "已清除映射 \(index + 1)。")
    }

    private func toggleKeyboardMappings() {
        let hasCompleteMapping = keyboardState.mappings.contains {
            $0.source != nil && $0.target != nil
        }
        guard keyboardState.enabled ||
              (keyboardState.appName != nil && hasCompleteMapping && keyboardMonitor.isRunning) else {
            keyboardState.feedback = tr("Choose an app and record both keys first.",
                                        "请先选择程序并录制一组完整的按键。")
            return
        }
        keyboardState.enabled.toggle()
        defaults.set(keyboardState.enabled, forKey: "keyboardEnabled")
        rebuildMenu()
        keyboardState.feedback = keyboardState.enabled
            ? tr("Keyboard mappings enabled.", "已启用键盘映射。")
            : tr("Keyboard mappings paused.", "已暂停键盘映射。")
    }

    private func requestKeyboardAccess() {
        showKeyboardSetup()
        defaults.set(true, forKey: "resumeKeyboardSetupAfterAccess")
        keyboardState.feedback = tr("Grant access in System Settings, then return here.",
                                    "请在系统设置中授权，然后回到这里继续。")
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        } else {
            _ = CGRequestListenEventAccess()
        }
        keyboardPermissionTimer?.invalidate()
        keyboardPermissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.keyboardWindow?.isVisible == true else {
                timer.invalidate()
                return
            }
            if !self.keyboardMonitor.isRunning { _ = self.keyboardMonitor.start() }
            self.refreshKeyboardSetup()
            if self.keyboardMonitor.isRunning {
                self.keyboardState.feedback = self.tr("Keyboard access is ready. Record your keys.",
                                                      "键盘权限已就绪，可以录制按键。")
                timer.invalidate()
                self.keyboardPermissionTimer = nil
            }
        }
    }

    private func handleKey(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp,
              event.getIntegerValueField(.eventSourceUserData) != 0x4D51534B else { return false }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, recordingKeyUp == code {
            recordingKeyUp = nil
            return true
        }
        if type == .keyDown, let index = keyboardState.recordingIndex {
            let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty else { return false }
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
            let target = keyboardState.recordingTarget
            let other = target ? keyboardState.mappings[index].source : keyboardState.mappings[index].target
            guard other != code else {
                keyboardState.feedback = tr("Choose two different keys.", "源按键和目标按键不能相同。")
                return true
            }
            if !target && keyboardState.mappings.enumerated().contains(where: {
                $0.offset != index && $0.element.source == code
            }) {
                keyboardState.feedback = tr("This source key is already mapped.", "这个源按键已用于另一组映射。")
                return true
            }
            let name = keyName(code, event: event)
            if target {
                keyboardState.mappings[index].target = code
                keyboardState.mappings[index].targetName = name
            } else {
                keyboardState.mappings[index].source = code
                keyboardState.mappings[index].sourceName = name
            }
            keyboardState.recordingIndex = nil
            recordingKeyUp = code
            saveKeyboardMappings()
            keyboardState.feedback = tr("Recorded \(name).", "已录制 \(name)。")
            return true
        }
        if type == .keyUp, let target = activeKeyboardRemaps.removeValue(forKey: code) {
            postKeyboardKey(target, down: false)
            return true
        }
        if type == .keyDown, let target = activeKeyboardRemaps[code] {
            postKeyboardKey(target, down: true,
                            repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            return true
        }
        guard type == .keyDown, keyboardState.enabled,
              keyboardWindow?.isKeyWindow != true,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              let appPath = defaults.string(forKey: "keyboardAppPath") else { return false }
        let appID = defaults.string(forKey: "keyboardAppID")
        guard (appID != nil && frontmost.bundleIdentifier == appID) ||
                frontmost.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: appPath).standardizedFileURL.path
        else { return false }
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard event.flags.intersection(modifiers).isEmpty else { return false }
        guard let mapping = keyboardState.mappings.first(where: { $0.source == code && $0.target != nil }),
              let target = mapping.target else { return false }
        activeKeyboardRemaps[code] = target
        postKeyboardKey(target, down: true,
                        repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        return true
    }

    private func postKeyboardKey(_ code: Int, down: Bool, repeatKey: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(code), keyDown: down) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: 0x4D51534B)
        if repeatKey { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cghidEventTap)
    }

    private func keyName(_ code: Int, event: CGEvent) -> String {
        switch code {
        case 49: return tr("Space", "空格")
        case 36: return tr("Return", "回车")
        case 53: return "Esc"
        case 48: return "Tab"
        case 51: return tr("Delete", "删除")
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
            let value = characters.unicodeScalars.first?.value ?? 0
            return characters.count == 1 && (33...126).contains(value)
                ? characters.uppercased() : tr("Key \(code)", "按键 \(code)")
        }
    }

    @objc private func systemSettingsDidDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.systempreferences" else { return }
        DispatchQueue.main.async {
            if self.defaults.bool(forKey: "resumeKeyboardSetupAfterAccess") {
                self.showKeyboardSetup()
            } else if self.defaults.bool(forKey: "resumeSetupAfterAccess") {
                self.showSetup()
            }
        }
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
        if (notification.object as? NSWindow) === keyboardWindow {
            keyboardState.recordingIndex = nil
            recordingKeyUp = nil
            keyboardPermissionTimer?.invalidate()
            keyboardPermissionTimer = nil
            if keyboardMonitor.isRunning {
                defaults.removeObject(forKey: "resumeKeyboardSetupAfterAccess")
            }
            return
        }
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
        for target in activeKeyboardRemaps.values {
            postKeyboardKey(target, down: false)
        }
        activeKeyboardRemaps.removeAll()
        keyboardMonitor.stop()
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
