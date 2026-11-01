import SwiftUI

/// 「［2］段 × ［3］回 ＝ 1セット」の式入力と目標。
struct CounterConfigSection: View {
    @Binding var mode: CountMode
    @Binding var rowsPerRepeat: Int
    @Binding var repeatsPerSet: Int
    @Binding var targetSets: Int?
    @Binding var targetRows: Int?

    var body: some View {
        Section("数え方") {
            Picker("モード", selection: $mode) {
                ForEach(CountMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if mode == .set {
                CountStepperRow(title: "1回の段数", unit: "段", value: $rowsPerRepeat)
                CountStepperRow(title: "1セットの回数", unit: "回", value: $repeatsPerSet)
                Text("\(max(1, rowsPerRepeat))段 × \(max(1, repeatsPerSet))回 ＝ 1セット（\(max(1, rowsPerRepeat) * max(1, repeatsPerSet))段）")
                    .font(.headline)
                    .foregroundStyle(.tint)
                OptionalCountField(title: "目標セット数", unit: "セット", value: $targetSets, defaultValue: 5)
            } else {
                OptionalCountField(title: "目標段数", unit: "段", value: $targetRows, defaultValue: 50)
            }
        }
    }
}

/// 「1回の段数　［2］段　［−｜＋］」の1行。
struct CountStepperRow: View {
    let title: String
    let unit: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            NumberField(value: $value)
            Text(unit)
            Stepper("", value: $value, in: 1...999)
                .labelsHidden()
        }
    }
}

/// 1以上の整数の入力欄。
/// 押すと中身を空にして、打った数字に置き換える（後ろに足されて「2」→「24」にならないように）。
/// 打った数字はその場で反映し、何も打たずに離れたら元の数字に戻す。
struct NumberField: View {
    @Binding var value: Int
    var minimum = 1

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("\(value)", text: $text)
            .keyboardType(.numberPad)
            .focused($focused)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .monospacedDigit()
            .onAppear { text = "\(value)" }
            .onChange(of: focused) { _, isFocused in
                text = isFocused ? "" : "\(value)"
            }
            .onChange(of: text) { _, newText in
                let digits = String(newText.filter(\.isASCIIDigit).prefix(5))
                if digits != newText {
                    text = digits
                    return
                }
                if let number = Int(digits), number >= minimum {
                    value = number
                }
            }
            .onChange(of: value) { _, newValue in
                if !focused { text = "\(newValue)" }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focused {
                        Spacer()
                        Button("完了") { focused = false }
                    }
                }
            }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// 「なし」にできる目標値。
struct OptionalCountField: View {
    let title: String
    let unit: String
    @Binding var value: Int?
    var defaultValue = 5

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { value != nil },
            set: { value = $0 ? (value ?? defaultValue) : nil }
        ))
        if let current = value {
            HStack {
                NumberField(value: Binding(get: { current }, set: { value = $0 }))
                Text(unit)
                Spacer()
                Stepper("", value: Binding(get: { current }, set: { value = max(1, $0) }), in: 1...99_999)
                    .labelsHidden()
            }
        }
    }
}

/// 段の指定。setモードでは「○セット目○回目○段目」でも指定でき、通算に変換して保持する。
struct RowInputView: View {
    let title: String
    @Binding var row: Int
    let config: CounterConfig
    @State private var useSetNotation = false

    private var position: CounterPosition {
        CounterEngine.position(completedRows: row - 1, config: config)
    }

    var body: some View {
        if config.mode == .set {
            Picker("指定方法", selection: $useSetNotation) {
                Text("通算").tag(false)
                Text("セット・回・段").tag(true)
            }
            .pickerStyle(.segmented)
        }

        if config.mode == .set && useSetNotation {
            Stepper("\(position.set)セット目", value: setBinding, in: 1...9_999)
            Stepper("\(position.repeatIndex)回目", value: repeatBinding, in: 1...config.safeRepeatsPerSet)
            Stepper("\(position.rowInRepeat)段目", value: rowInRepeatBinding, in: 1...config.safeRowsPerRepeat)
            Text("＝ 通算 \(row) 段目")
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Text(title)
                Spacer()
                Text("通算")
                NumberField(value: $row)
                Text("段目")
            }
            if config.mode == .set {
                Text("＝ \(position.set)セット目 \(position.repeatIndex)回目 \(position.rowInRepeat)段目")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var setBinding: Binding<Int> {
        Binding(
            get: { position.set },
            set: { row = CounterEngine.absoluteRow(set: $0, repeatIndex: position.repeatIndex, rowInRepeat: position.rowInRepeat, config: config) }
        )
    }

    private var repeatBinding: Binding<Int> {
        Binding(
            get: { position.repeatIndex },
            set: { row = CounterEngine.absoluteRow(set: position.set, repeatIndex: $0, rowInRepeat: position.rowInRepeat, config: config) }
        )
    }

    private var rowInRepeatBinding: Binding<Int> {
        Binding(
            get: { position.rowInRepeat },
            set: { row = CounterEngine.absoluteRow(set: position.set, repeatIndex: position.repeatIndex, rowInRepeat: $0, config: config) }
        )
    }
}
