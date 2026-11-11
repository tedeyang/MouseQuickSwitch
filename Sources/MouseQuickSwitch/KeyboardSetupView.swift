import SwiftUI

struct KeyMapping: Codable, Equatable {
    var source: Int?
    var target: Int?
    var sourceName = ""
    var targetName = ""
}

final class KeyboardSetupState: ObservableObject {
    @Published var chinese = false
    @Published var appName: String?
    @Published var mappings = Array(repeating: KeyMapping(), count: 3)
    @Published var visibleRows = 1
    @Published var enabled = false
    @Published var canListen = false
    @Published var recordingIndex: Int?
    @Published var recordingTarget = false
    @Published var feedback: String?

    func text(_ english: String, _ chinese: String) -> String {
        self.chinese ? chinese : english
    }
}

struct KeyboardSetupView: View {
    @ObservedObject var state: KeyboardSetupState
    let chooseApp: () -> Void
    let record: (Int, Bool) -> Void
    let clear: (Int) -> Void
    let toggle: () -> Void
    let requestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.text("Keyboard key mappings", "键盘按键映射"))
                .font(.title2.bold())
            Text(state.text("Mappings work only while the chosen app is in front.",
                            "仅当指定程序位于最前方时，映射才会生效。"))
                .foregroundStyle(.secondary)

            HStack {
                Text(state.appName.map { state.text("App: \($0)", "目标程序：\($0)") } ??
                     state.text("No app selected", "尚未选择目标程序"))
                Spacer()
                Button(state.text("Choose App…", "选择程序…"), action: chooseApp)
            }

            if !state.canListen {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                    Text(state.text("Allow keyboard access before recording keys.",
                                    "录制按键前，请先授权键盘输入权限。"))
                    Spacer()
                    Button(state.text("Grant Access…", "去授权…"), action: requestAccess)
                }
                .padding(12)
                .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            }

            Divider()
            ForEach(0..<state.visibleRows, id: \.self) { index in
                mappingRow(index)
            }
            if state.visibleRows < 3 {
                Button {
                    state.visibleRows += 1
                } label: {
                    Label(state.text("Add mapping", "添加映射"), systemImage: "plus")
                }
            }
            Divider()

            Toggle(state.text("Enable keyboard mappings", "启用键盘映射"),
                   isOn: Binding(get: { state.enabled }, set: { _ in toggle() }))
                .disabled(!state.enabled && (state.appName == nil || !state.canListen ||
                          !state.mappings.contains(where: { $0.source != nil && $0.target != nil }))
                )
            Text(state.feedback ?? state.text(
                "Choose an app, record both keys in a row, then enable mapping.",
                "先选择程序，再录制一组源按键和目标按键，最后启用映射。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.text("Shortcuts with ⌘, ⌥, ⌃ or ⇧ keep their original behavior.",
                            "带 ⌘、⌥、⌃ 或 ⇧ 的组合键保留原有行为。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 480,
               maxHeight: .infinity, alignment: .topLeading)
    }

    private func mappingRow(_ index: Int) -> some View {
        let mapping = state.mappings[index]
        return HStack(spacing: 10) {
            Text(state.text("Map \(index + 1)", "映射 \(index + 1)"))
                .frame(width: 65, alignment: .leading)
            Button(recordingTitle(index: index, target: false, value: mapping.sourceName),
                   action: { record(index, false) })
                .frame(maxWidth: .infinity)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Button(recordingTitle(index: index, target: true, value: mapping.targetName),
                   action: { record(index, true) })
                .frame(maxWidth: .infinity)
            Button(action: { clear(index) }) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(state.text("Clear this mapping", "清除这组映射"))
        }
    }

    private func recordingTitle(index: Int, target: Bool, value: String) -> String {
        if state.recordingIndex == index && state.recordingTarget == target {
            return state.text("Press a key…", "请按键…")
        }
        if !value.isEmpty { return value }
        return target ? state.text("Record target", "录制目标键") :
                        state.text("Record source", "录制源键")
    }
}
