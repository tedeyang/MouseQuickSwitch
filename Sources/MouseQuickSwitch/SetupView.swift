import SwiftUI

final class SetupState: ObservableObject {
    @Published var chinese = false
    @Published var detected = false
    @Published var slot = 0
    @Published var buttonNumber: Int?
    @Published var otherButtonNumber: Int?
    @Published var recording = false
    @Published var canListen = false
    @Published var hasAccessibility = false
    @Published var switchApps = false
    @Published var targetName: String?
    @Published var enabled = true
    @Published var lastPressedButton: Int?
    @Published var feedback: String?

    func text(_ english: String, _ chinese: String) -> String {
        self.chinese ? chinese : english
    }
}

struct SetupView: View {
    @ObservedObject var state: SetupState
    let selectSlot: (Int) -> Void
    let chooseButton: (Int) -> Void
    let record: () -> Void
    let switchApps: () -> Void
    let openChosenApp: () -> Void
    let selectApp: () -> Void
    let toggleEnabled: () -> Void
    let requestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
                Text(state.text("Set up your mouse buttons", "设置鼠标侧键"))
                    .font(.title2.bold())

                Picker(state.text("Button to configure", "要设置的侧键"),
                       selection: Binding(get: { state.slot }, set: { selectSlot($0) })) {
                    Text(state.text("Button 1", "侧键 1")).tag(0)
                    Text(state.text("Button 2", "侧键 2")).tag(1)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(state.text("Button to configure", "要设置的侧键"))

                if !state.canListen {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(state.text("Allow mouse access first", "请先授权鼠标访问"),
                              systemImage: "hand.raised.fill")
                            .font(.headline)
                        Text(state.hasAccessibility
                             ? state.text("Accessibility is allowed, but mouse clicks are still blocked. Allow MouseQuickSwitch in System Settings → Privacy & Security → Input Monitoring. Then reopen the app if needed.",
                                          "辅助功能已授权，但仍无法监听鼠标点击。请在“系统设置 → 隐私与安全性 → 输入监控”中允许 MouseQuickSwitch；如仍无效，退出并重新打开应用。")
                             : state.text("MouseQuickSwitch cannot detect side-button clicks until you allow it in System Settings → Privacy & Security → Accessibility.",
                                          "未授权前，MouseQuickSwitch 无法检测侧键点击。请先在“系统设置 → 隐私与安全性 → 辅助功能”中允许它。"))
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.subheadline)
                        Button(state.hasAccessibility
                               ? state.text("Request mouse input access…", "请求鼠标输入权限…")
                               : state.text("Grant Accessibility access…", "授权辅助功能…"),
                               action: requestAccess)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Label(state.text("Mouse access ready", "鼠标权限已就绪"),
                          systemImage: "checkmark.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                HStack(spacing: 8) {
                    Image(systemName: state.detected ? "checkmark.circle.fill" : "computermouse")
                        .foregroundStyle(state.detected ? .green : .secondary)
                    Text(state.detected
                         ? state.text("Logitech M585 detected", "已识别罗技 M585")
                         : state.text("Mouse model not confirmed", "尚未确认鼠标型号"))
                }
                .font(.subheadline)

                Divider()

                Text(state.text("1. Choose a physical button", "1. 选择鼠标上的按键"))
                    .font(.headline)
                HStack(alignment: .center, spacing: 16) {
                    mouseDiagram
                    VStack(alignment: .leading, spacing: 6) {
                        if state.detected {
                            Text(state.text("Skip recording: choose the button you want to use.",
                                            "无需录制：直接选择要使用的侧键。"))
                                .fixedSize(horizontal: false, vertical: true)
                            Button(state.text("Back button", "后退键")) { chooseButton(3) }
                                .disabled(!state.canListen || state.otherButtonNumber == 3)
                            Button(state.text("Forward button", "前进键")) { chooseButton(4) }
                                .disabled(!state.canListen || state.otherButtonNumber == 4)
                        } else {
                            Text(state.text("Press the side button once to identify it.",
                                            "按一下要使用的侧键，即可完成识别。"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(state.recording
                               ? state.text("Cancel recording", "取消录制")
                               : state.text("Record by pressing a button…", "按下侧键录制…"),
                               action: record)
                            .disabled(!state.canListen)
                        if let other = state.otherButtonNumber {
                            Text(state.text("Button \(other + 1) is already used by Button \(2 - state.slot).",
                                            "按键 \(other + 1) 已分配给侧键 \(2 - state.slot)。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(buttonStatus)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(state.buttonNumber == nil ? .secondary : .primary)
                Label(state.feedback ?? (state.canListen
                                         ? state.text("Press a side button to see it here.",
                                                      "按一下侧键，检测结果会显示在这里。")
                                         : state.text("Grant access before testing side-button clicks.",
                                                      "授权后才能检测侧键点击。")),
                      systemImage: state.lastPressedButton == nil ? "cursorarrow.click" : "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(state.lastPressedButton == nil ? Color.secondary : Color.green)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text(state.text("2. What should this button do?", "2. 这个侧键按下后做什么？"))
                    .font(.headline)
                actionChoice(
                    title: state.text("Switch to previous app", "切换到上一个程序"),
                    detail: state.text("Each press alternates between your two recent apps (⌘Tab).",
                                       "每次按下都在最近使用的两个程序之间切换（⌘Tab）。"),
                    selected: state.switchApps,
                    action: switchApps)
                actionChoice(
                    title: state.text("Switch to a chosen app", "切换到指定程序"),
                    detail: state.text("Each press opens or brings the same app to the front.",
                                       "每次按下都打开或切到你选定的程序。"),
                    selected: !state.switchApps,
                    action: openChosenApp)
                if !state.switchApps {
                    Button(state.targetName.map { state.text("Chosen app: \($0) · Change…",
                                                              "已选程序：\($0) · 更换…") } ??
                           state.text("Choose the app to switch to…", "选择要切到的程序…"),
                           action: selectApp)
                        .disabled(state.buttonNumber == nil)
                }
                Toggle(state.text("Enable this button", "启用此侧键"),
                       isOn: Binding(get: { state.enabled }, set: { _ in toggleEnabled() }))
                    .disabled(state.buttonNumber == nil)
                Text(state.text("Test detection here. Close this window to use the chosen action.",
                                "在这里试按并查看检测结果；关闭窗口后，侧键会执行所选动作。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func actionChoice(title: String, detail: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(state.buttonNumber == nil)
    }

    private var buttonStatus: String {
        if state.recording {
            return state.text("Waiting for Button \(state.slot + 1)…",
                              "正在录制侧键 \(state.slot + 1)…")
        }
        if let number = state.buttonNumber {
            let name = physicalButtonName(number)
            return state.text("Button \(state.slot + 1): \(name) is ready. Try it now.",
                              "侧键 \(state.slot + 1)：\(name)已设置，试按一下。")
        }
        return state.text("Button \(state.slot + 1) is not set yet",
                          "侧键 \(state.slot + 1) 尚未设置")
    }

    private func physicalButtonName(_ number: Int) -> String {
        switch number {
        case 3: return state.text("Back button", "后退键")
        case 4: return state.text("Forward button", "前进键")
        default: return state.text("physical button \(number + 1)", "鼠标按键 \(number + 1)")
        }
    }

    private var mouseDiagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 43)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 43).stroke(.secondary, lineWidth: 2))
                .frame(width: 82, height: 120)
            Capsule()
                .fill(.secondary)
                .frame(width: 5, height: 20)
                .offset(x: 0, y: -34)
            VStack(spacing: 6) {
                sideButton(number: 4)
                sideButton(number: 3)
            }
            .offset(x: -42, y: 9)
        }
        .frame(width: 100, height: 132)
        .accessibilityLabel(state.text("Mouse with two side buttons", "带两个侧键的鼠标示意图"))
    }

    private func sideButton(number: Int) -> some View {
        Capsule()
            .fill(state.lastPressedButton == number ? .green :
                  (state.buttonNumber == number || state.recording ? Color.accentColor : .secondary))
            .frame(width: 19, height: 10)
    }
}
