import XCTest
@testable import KnitVoice

final class VoiceCommandTests: XCTestCase {
    private let matcher = VoiceCommandMatcher()

    private func command(_ text: String) -> VoiceCommand? {
        var cursor = TranscriptCursor()
        return cursor.nextCommand(in: text, matcher: matcher)
    }

    func testVocabularyVariants() {
        for word in ["次", "つぎ", "ツギ", "はい", "プラス", "ネクスト"] {
            XCTAssertEqual(command(word), .increment, word)
        }
        for word in ["戻る", "もどる", "モドル", "マイナス", "間違えた", "まちがえた"] {
            XCTAssertEqual(command(word), .decrement, word)
        }
        for word in ["何段", "なんだん", "今どこ", "いまどこ", "何セット", "なんセット"] {
            XCTAssertEqual(command(word), .readPosition, word)
        }
    }

    func testPartialMatchWithSpacesAndPunctuation() {
        XCTAssertEqual(command("えっと、次。"), .increment)
        XCTAssertEqual(command("なん だん"), .readPosition)
        XCTAssertEqual(command("ちょっと間違えたかも"), .decrement)
        XCTAssertNil(command("こんにちは"))
    }

    func testCursorOnlyLooksAtNewText() {
        var cursor = TranscriptCursor()
        XCTAssertEqual(cursor.nextCommand(in: "次", matcher: matcher), .increment)
        // 同じ途中結果がもう一度来てもカウントしない
        XCTAssertNil(cursor.nextCommand(in: "次", matcher: matcher))
        XCTAssertEqual(cursor.nextCommand(in: "次 戻る", matcher: matcher), .decrement)
        XCTAssertNil(cursor.nextCommand(in: "次 戻る", matcher: matcher))
    }

    func testEarliestCommandWins() {
        XCTAssertEqual(command("戻る次"), .decrement)
    }

    func testConsumeAllIgnoresOwnSpeech() {
        var cursor = TranscriptCursor()
        cursor.consumeAll("次の段は増し目です")
        XCTAssertNil(cursor.nextCommand(in: "次の段は増し目です", matcher: matcher))
        XCTAssertEqual(cursor.nextCommand(in: "次の段は増し目です 次", matcher: matcher), .increment)
    }

    func testDebouncer() {
        var debouncer = CommandDebouncer(interval: 1.2)
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(debouncer.shouldAccept(.increment, at: t0))
        XCTAssertFalse(debouncer.shouldAccept(.increment, at: t0.addingTimeInterval(1.0)))
        // 種類が違えば受け付ける
        XCTAssertTrue(debouncer.shouldAccept(.decrement, at: t0.addingTimeInterval(1.0)))
        XCTAssertTrue(debouncer.shouldAccept(.increment, at: t0.addingTimeInterval(1.3)))
    }

    func testEchoGate() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(SpeechEchoGate.shouldIgnore(isSpeaking: true, lastFinishedAt: nil, now: now))
        XCTAssertTrue(SpeechEchoGate.shouldIgnore(isSpeaking: false, lastFinishedAt: now.addingTimeInterval(-0.6), now: now))
        XCTAssertFalse(SpeechEchoGate.shouldIgnore(isSpeaking: false, lastFinishedAt: now.addingTimeInterval(-1.1), now: now))
        XCTAssertFalse(SpeechEchoGate.shouldIgnore(isSpeaking: false, lastFinishedAt: nil, now: now))
    }

    /// 読み上げ中でも、ユーザーの「次」「戻る」は数える
    func testEchoWindowStillAcceptsUserCommands() {
        let echo = matcher.forEchoWindow(spokenText: "2段目")
        var cursor = TranscriptCursor()
        XCTAssertEqual(cursor.nextCommand(in: "2段目 次", matcher: echo), .increment)
        cursor.reset()
        XCTAssertEqual(cursor.nextCommand(in: "2段目 戻る", matcher: echo), .decrement)
    }

    /// 読み上げ中は、読み上げている文の語と「今どこ」系を拾わない
    func testEchoWindowExcludesOwnWords() {
        let reminder = matcher.forEchoWindow(spokenText: "2段目。次の段は増し目です")
        var cursor = TranscriptCursor()
        XCTAssertNil(cursor.nextCommand(in: "2段目次の段は増し目です", matcher: reminder))
        XCTAssertEqual(cursor.nextCommand(in: "2段目次の段は増し目です つぎ", matcher: reminder), .increment)

        let setStarted = matcher.forEchoWindow(spokenText: "3セット目に入りました")
        cursor.reset()
        XCTAssertNil(cursor.nextCommand(in: "3セット目にはいりました", matcher: setStarted))

        cursor.reset()
        XCTAssertNil(cursor.nextCommand(in: "何段目", matcher: matcher.forEchoWindow(spokenText: "2段目")))
    }

    /// 処理済みにするとき末尾を残すので、途中結果で伸びた語も拾える
    func testConsumeAllKeepsTailForGrowingWords() {
        var cursor = TranscriptCursor()
        let echo = matcher.forEchoWindow(spokenText: "2段目")
        XCTAssertNil(cursor.nextCommand(in: "2段目つ", matcher: echo))
        cursor.consumeAll("2段目つ", keepingLast: matcher.maxWordLength - 1)
        XCTAssertEqual(cursor.nextCommand(in: "2段目つぎ", matcher: echo), .increment)
    }
}
