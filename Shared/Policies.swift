import Foundation

/// 無料版の制限：同時に存在できるプロジェクト数。
enum EntitlementPolicy {
    static let freeProjectLimit = 1

    static func canCreateProject(existingCount: Int, isUnlocked: Bool) -> Bool {
        isUnlocked || existingCount < freeProjectLimit
    }
}

/// Digital Crown の回転量をためて、一定量ごとに1カウントに変換する。
struct CrownAccumulator {
    /// 1カウントに必要な回転量（要実機調整）
    var threshold: Double
    private var accumulated = 0.0

    init(threshold: Double) {
        self.threshold = threshold
    }

    /// +1 / -1 / 0 を返す。逆方向に回したらためた分は捨てる。
    mutating func feed(_ delta: Double) -> Int {
        if (accumulated > 0 && delta < 0) || (accumulated < 0 && delta > 0) {
            accumulated = 0
        }
        accumulated += delta
        if accumulated >= threshold {
            accumulated = 0
            return 1
        }
        if accumulated <= -threshold {
            accumulated = 0
            return -1
        }
        return 0
    }
}
