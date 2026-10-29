import Foundation
import SwiftData

enum AppGroup {
    /// project.yml の entitlements と合わせること
    static let identifier = "group.com.sammy.knitvoice"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// アプリ本体とウィジェット拡張で共有する SwiftData ストア。
enum KnitVoiceStore {
    static let schema = Schema([Project.self, Reminder.self, RowMemo.self, CountEvent.self])
    private static let fileName = "KnitVoice.store"
    private static let legacyMigratedKey = "legacyStoreMigrated"

    static var storeURL: URL {
        if let group = AppGroup.containerURL {
            return group.appending(path: fileName)
        }
        // App Group が使えない環境（entitlement未設定のテスト等）用のフォールバック
        return URL.applicationSupportDirectory.appending(path: fileName)
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// App Group 導入前のストア（Application Support/default.store）をグループコンテナへコピーする。
    /// ストアを開く前に呼ぶこと。元ファイルは念のため残す。
    static func migrateLegacyStoreIfNeeded(fileManager: FileManager = .default) {
        let defaults = AppGroup.defaults
        guard !defaults.bool(forKey: legacyMigratedKey), let group = AppGroup.containerURL else { return }
        defer { defaults.set(true, forKey: legacyMigratedKey) }

        let legacy = URL.applicationSupportDirectory.appending(path: "default.store")
        let destination = group.appending(path: fileName)
        guard fileManager.fileExists(atPath: legacy.path()),
              !fileManager.fileExists(atPath: destination.path()) else { return }

        // SQLite本体と -wal / -shm をまとめてコピー
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(filePath: legacy.path() + suffix)
            let to = URL(filePath: destination.path() + suffix)
            guard fileManager.fileExists(atPath: from.path()) else { continue }
            do {
                try fileManager.copyItem(at: from, to: to)
            } catch {
                // 途中で失敗したら中途半端なコピーを消して次回起動で再試行する
                for cleanup in ["", "-wal", "-shm"] {
                    try? fileManager.removeItem(at: URL(filePath: destination.path() + cleanup))
                }
                defaults.set(false, forKey: legacyMigratedKey)
                return
            }
        }
    }
}

/// ストアを書いたプロセス。
enum StoreWriter: String {
    case app
    case widget
}

/// 別プロセス（ウィジェット）がストアを書いたことを、アプリ本体が検出するための印。
enum StoreChangeMarker {
    private static let tokenKey = "storeWriteToken"
    private static let writerKey = "storeWriter"

    static var currentToken: String? {
        AppGroup.defaults.string(forKey: tokenKey)
    }

    static func markWrite(by writer: StoreWriter) {
        let defaults = AppGroup.defaults
        defaults.set(UUID().uuidString, forKey: tokenKey)
        defaults.set(writer.rawValue, forKey: writerKey)
    }
}

/// ウィジェット未設定時に使う「最後に使ったプロジェクト」。
enum LastUsedProject {
    private static let key = "lastUsedProjectID"

    static var id: UUID? {
        get { AppGroup.defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        set { AppGroup.defaults.set(newValue?.uuidString, forKey: key) }
    }
}
