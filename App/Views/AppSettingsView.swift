import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(PurchaseManager.self) private var purchases
    @State private var showingPaywall = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("段の読み上げ", selection: $settings.rowReadingStyle) {
                        ForEach(RowReadingStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    Toggle("メモを読み上げる", isOn: $settings.speakMemos)
                } header: {
                    Text("読み上げ")
                } footer: {
                    Text("「数字だけ」「読み上げない」でも、回・セットの区切り、完了、リマインドは読み上げます。")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("連続コマンドを無視する時間：\(settings.commandDebounceInterval, specifier: "%.1f")秒")
                        Slider(value: $settings.commandDebounceInterval, in: 0.5...3.0, step: 0.1)
                    }
                    DisclosureGroup("使える言葉") {
                        commandWords("＋1", .increment)
                        commandWords("−1", .decrement)
                        commandWords("今どこ", .readPosition)
                    }
                } header: {
                    Text("音声コマンド")
                } footer: {
                    Text("同じ言葉が続けて聞こえたときの二重カウントを防ぎます。短くすると反応が速くなります。")
                }

                Section {
                    Toggle("イヤホンのボタンでカウント", isOn: $settings.earphoneButtonsEnabled)
                } header: {
                    Text("イヤホンのボタン")
                } footer: {
                    Text("再生／一時停止・次の曲で＋1、前の曲で−1。オンにすると、カウンター画面を開いている間は他のアプリの音楽が止まります。")
                }

                Section("購入") {
                    if purchases.isUnlocked {
                        Label("プロジェクト無制限（購入済み）", systemImage: "checkmark.seal.fill")
                    } else {
                        Button("プロジェクトを無制限にする") { showingPaywall = true }
                    }
                    Button("購入を復元") {
                        Task { await purchases.restore() }
                    }
                }

                Section("このアプリについて") {
                    Link("サポート・よくある質問", destination: AppConstants.supportURL)
                    Link("プライバシーポリシー", destination: AppConstants.privacyPolicyURL)
                    Link("利用規約", destination: AppConstants.termsURL)
                    LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private func commandWords(_ title: String, _ command: VoiceCommand) -> some View {
        LabeledContent(title) {
            Text((VoiceCommandMatcher.defaultVocabulary[command] ?? []).joined(separator: "・"))
                .font(.caption)
        }
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "infinity.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("プロジェクトを無制限に")
                    .font(.title.bold())
                Text("無料版では同時に1つのプロジェクトまで作れます（音声・リマインド・Watch・ウィジェットなどの機能はすべて使えます）。\nアンロックすると、いくつでも作れます。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await purchases.purchase() }
                } label: {
                    Group {
                        if let product = purchases.product {
                            Text("\(product.displayPrice)で購入（買い切り）")
                        } else if DemoMode.isEnabled {
                            Text("¥500で購入（買い切り）")
                        } else {
                            Text("価格を読み込み中…")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled((purchases.product == nil && !DemoMode.isEnabled) || purchases.isPurchasing)

                Button("購入を復元") {
                    Task { await purchases.restore() }
                }

                if let message = purchases.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 16) {
                    Link("利用規約", destination: AppConstants.termsURL)
                    Link("プライバシーポリシー", destination: AppConstants.privacyPolicyURL)
                }
                .font(.footnote)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                if purchases.product == nil { await purchases.load() }
            }
        }
        .onChange(of: purchases.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }
}

/// 初めてマイクをオンにするとき、権限をリクエストする前に理由を説明する。
/// 審査ガイドライン 5.1.1(iv) に合わせ、ボタンは「次へ」だけ（「許可」という言葉や、飛ばす・後回しにするボタンは置かない）。
struct PermissionIntroView: View {
    /// 権限の確認が終わったとき（許可・不許可どちらでも）
    let onFinish: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.tint)
            Text("声で段数を数えます")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 18) {
                reason(
                    "mic",
                    "マイク",
                    "編みながら「次」「戻る」「今どこ」と話しかけるだけで、手を止めずにカウントできます。"
                )
                reason(
                    "waveform",
                    "音声認識",
                    "聞き取った声を文字にして、コマンドかどうかを判定します。対応端末では端末内だけで処理します。音声を保存することはありません。"
                )
            }
            Text("このあと、マイクと音声認識の使用について確認が表示されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                requesting = true
                Task {
                    _ = await Permissions.requestAll()
                    settings.hasSeenPermissionIntro = true
                    onFinish()
                }
            } label: {
                Text("次へ")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(requesting)
        }
        .padding(24)
    }

    private func reason(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
