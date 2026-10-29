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
                HStack(spacing: 6) {
                    NumberField(value: $rowsPerRepeat)
                    Text("段 ×")
                    NumberField(value: $repeatsPerSet)
                    Text("回 ＝ 1セット")
                }
                Text("1セット＝\(max(1, rowsPerRepeat) * max(1, repeatsPerSet))段")
                    .foregroundStyle(.secondary)
                OptionalCountField(title: "目標セット数", unit: "セット", value: $targetSets, defaultValue: 5)
            } else {
                OptionalCountField(title: "目標段数", unit: "段", value: $targetRows, defaultValue: 50)
            }
        }
    }
}

/// 1以上の整数の入力欄。
struct NumberField: View {
    @Binding var value: Int
    var minimum = 1

    var body: some View {
        TextField("", value: $value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .monospacedDigit()
            .onChange(of: value) { _, newValue in
                if newValue < minimum { value = minimum }
            }
    }
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
