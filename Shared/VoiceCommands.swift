import Foundation

enum VoiceCommand: String, Codable, CaseIterable {
    case increment
    case decrement
    case readPosition
}

/// 認識テキストからコマンド語を部分一致で探す。
struct VoiceCommandMatcher {
    static let defaultVocabulary: [VoiceCommand: [String]] = [
        .increment: ["次", "つぎ", "ツギ", "はい", "プラス", "ネクスト"],
        .decrement: ["戻る", "もどる", "モドル", "マイナス", "間違えた", "まちがえた"],
        .readPosition: ["何段", "なんだん", "今どこ", "いまどこ", "何セット", "なんセット"],
    ]

    let vocabulary: [VoiceCommand: [String]]
    private let entries: [(word: String, command: VoiceCommand)]

    init(vocabulary: [VoiceCommand: [String]] = VoiceCommandMatcher.defaultVocabulary) {
        self.vocabulary = vocabulary
        var seen = Set<String>()
        var entries: [(word: String, command: VoiceCommand)] = []
        for command in VoiceCommand.allCases {
            for word in vocabulary[command] ?? [] {
                let normalized = Self.normalize(word)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                entries.append((normalized, command))
            }
        }
        self.entries = entries
    }

    /// `SFSpeechAudioBufferRecognitionRequest.contextualStrings` に渡す語。
    var contextualStrings: [String] {
        VoiceCommand.allCases.flatMap { vocabulary[$0] ?? [] }
    }

    /// 空白・句読点を除き、カタカナをひらがなにそろえる。1文字ずつの変換なので前方一致が保たれる。
    static func normalize(_ text: String) -> String {
        let stripped = String(text.filter { !$0.isWhitespace && !"、。,.!?！？・".contains($0) })
        let hiragana = stripped.applyingTransform(.hiraganaToKatakana, reverse: true) ?? stripped
        return hiragana.lowercased()
    }

    /// 正規化済みテキストで最初に現れるコマンドと、その語の終わり位置。同じ位置なら長い語を優先。
    func firstMatch(inNormalized text: String) -> (command: VoiceCommand, end: String.Index)? {
        var best: (command: VoiceCommand, range: Range<String.Index>)?
        for entry in entries {
            guard let range = text.range(of: entry.word) else { continue }
            if let current = best {
                let earlier = range.lowerBound < current.range.lowerBound
                let sameStartLonger = range.lowerBound == current.range.lowerBound
                    && range.upperBound > current.range.upperBound
                guard earlier || sameStartLonger else { continue }
            }
            best = (entry.command, range)
        }
        return best.map { ($0.command, $0.range.upperBound) }
    }
}

/// ひとつの認識タスク内で、処理済みの部分を覚えて新しい部分だけを判定する。
struct TranscriptCursor {
    /// 正規化済みテキストで処理済みの文字数
    private(set) var consumedCount = 0

    mutating func nextCommand(in transcript: String, matcher: VoiceCommandMatcher) -> VoiceCommand? {
        let normalized = VoiceCommandMatcher.normalize(transcript)
        guard normalized.count > consumedCount else { return nil }
        let fresh = String(normalized.dropFirst(consumedCount))
        guard let match = matcher.firstMatch(inNormalized: fresh) else { return nil }
        consumedCount += fresh.distance(from: fresh.startIndex, to: match.end)
        return match.command
    }

    /// 読み上げ中など、判定せずにここまでを処理済みにする。
    mutating func consumeAll(_ transcript: String) {
        consumedCount = max(consumedCount, VoiceCommandMatcher.normalize(transcript).count)
    }

    mutating func reset() {
        consumedCount = 0
    }
}

/// 同じ種類のコマンドが短時間に続いたら無視する。
struct CommandDebouncer {
    static let defaultInterval: TimeInterval = 1.2

    var interval: TimeInterval
    private var lastAccepted: [VoiceCommand: Date] = [:]

    init(interval: TimeInterval = CommandDebouncer.defaultInterval) {
        self.interval = interval
    }

    mutating func shouldAccept(_ command: VoiceCommand, at now: Date) -> Bool {
        if let last = lastAccepted[command], now.timeIntervalSince(last) < interval {
            return false
        }
        lastAccepted[command] = now
        return true
    }
}

/// 自分の読み上げを拾ってカウントしないための判定。
enum SpeechEchoGate {
    /// 読み上げ終了後も無視を続ける秒数
    static let defaultTail: TimeInterval = 0.5

    static func shouldIgnore(
        isSpeaking: Bool,
        lastFinishedAt: Date?,
        now: Date,
        tail: TimeInterval = SpeechEchoGate.defaultTail
    ) -> Bool {
        if isSpeaking { return true }
        guard let lastFinishedAt else { return false }
        return now.timeIntervalSince(lastFinishedAt) < tail
    }
}
