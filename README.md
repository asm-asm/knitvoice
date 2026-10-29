# KnitVoice（仮）

日本語の音声コマンドで段数を数える、棒針・かぎ針編み用の iOS カウンター。Apple Watch・イヤホンボタン・ホーム／ロック画面ウィジェット対応。

## ビルド

macOS + Xcode 16 以上（iOS 18 SDK。iOS 18 のコントロールウィジェットのため）と [XcodeGen](https://github.com/yonaskolb/XcodeGen) が必要です。watchOS シミュレータのランタイムも入れておいてください（アプリ本体のビルドで Watch アプリも一緒にビルドされます）。

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -project KnitVoice.xcodeproj -scheme KnitVoice \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

実機で動かす前に：
- `project.yml` の `DEVELOPMENT_TEAM` と、`com.sammy` のバンドルID・App Group（`group.com.sammy.knitvoice`）を自分のものに変える。App Group は `SharedData/Store.swift` の `AppGroup.identifier` にもあるので、そちらもそろえる
- `App/AppConstants.swift` のプライバシーポリシーURL
- アプリアイコン（未作成）

StoreKit はスキームに `KnitVoice.storekit` を設定してあるので、Xcode から実行すればローカルで購入を試せます。

## 構成

| フォルダ | 対象 | 内容 |
|---|---|---|
| `Shared/` | iOS・Watch・ウィジェット | 純粋なロジック：位置の計算、読み上げ文言、リマインド判定、音声コマンド判定、同期の型 |
| `SharedData/` | iOS・ウィジェット | SwiftData モデル、`CounterService`（カウント変更の唯一の経路）、App Group ストア |
| `App/` | iOS | 画面、読み上げ、音声認識、イヤホンボタン、StoreKit、Watch 同期 |
| `Widget/` | ウィジェット拡張 | ホーム／ロック画面ウィジェット、App Intents、iOS 18 コントロール |
| `Watch/` | watchOS | Watch アプリ |
| `Tests/` | | ユニットテスト（仕様書 3章のテストケース表を含む） |

### 設計上のポイント
- 保存するカウント値は `Project.completedRows` だけ。セット・回・段の表示はすべて `CounterEngine` で計算する。
- カウントの変更は、タップ・音声・イヤホン・Watch・ウィジェットのすべてが `CounterService` を通る。現在値を読んで ±1 し、`CountEvent` を記録して、1回の保存で書き込む。
- ウィジェット拡張は毎回ストアを開き直す。ウィジェットが書き込むと App Group の UserDefaults に印（`StoreChangeMarker`）が付き、アプリ本体は前面に戻ったとき・書き込む前にそれを確認して、ストアを読み直す（`AppServices.reloadIfChangedExternally`）。ナビゲーションはプロジェクトIDで持っているので、読み直してビュー階層を作り直しても、開いていた画面はそのまま残る。
- 音声認識は `SpeechRecognitionEngine` プロトコルで抽象化してある（将来 `SpeechAnalyzer` へ差し替えるため）。
- Watch からは絶対値ではなくコマンドを送る（コマンドIDで重複を除く）。iPhone 側では `source: .watch` として記録する。

### 仕様から判断して決めたこと
- 読み上げ設定の「数字だけ」「読み上げない」は「○段目」の部分にだけ効く。回・セットの区切り、完了、リマインドはこの設定でも読み上げる。カウンター画面のスピーカーボタンを OFF にすると、全部黙る（「今どこ」への返事だけは読む）。
- リセットは `kind: .reset`、`delta` は変更前の段数をマイナスにした値で記録する。履歴の日別合計には含めない。
- ウィジェットのプロジェクト候補が無料枠で制限されることはない（無料ユーザーも自分の1プロジェクトに使える）。

## 実機で確認すること

仕様書 10章・追加仕様 E章の項目に加えて：
- [ ] `AudioSession` で `setVoiceProcessingEnabled(true)` の有無：エコーキャンセルの効果と、ほかの音への影響
- [ ] イヤホンボタンモード：無音ループの再生で「再生中アプリ」になれるか。HFP 接続中にリモートコマンドが届くか（届かなければ音声とイヤホンボタンを排他にする）
- [ ] Digital Crown の感度（`WatchCounterView.crownStepThreshold`）
- [ ] ロック画面ウィジェットのボタン：今はタップでアプリを開くだけ
- [ ] アプリが前面にある間にコントロールセンターから＋1したとき：アプリ側の表示は、次の操作か次に前面へ戻るまで古いまま（値自体は書き込み前に読み直すのでずれない）
- [ ] XcodeGen での Watch アプリの埋め込み（Embed Watch Content）が正しく生成されるか
