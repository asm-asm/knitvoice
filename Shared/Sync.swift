import Foundation

/// WatchConnectivity でやり取りする辞書のキー。値はJSONの Data。
enum SyncKeys {
    static let snapshot = "snapshot"
    static let command = "command"
}

struct WatchProjectSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var completedRows: Int
    var config: CounterConfig
    var reminders: [ReminderSpec]
    var memos: [MemoSpec]
    var updatedAt: Date
}

/// iPhone → Watch：最新状態（updateApplicationContext）。
struct WatchSnapshot: Codable, Equatable {
    var projects: [WatchProjectSnapshot]
    var generatedAt: Date
}

/// Watch → iPhone：絶対値ではなくコマンドを送る（sendMessage / transferUserInfo）。
struct WatchCommand: Codable, Equatable {
    enum Action: String, Codable {
        case increment
        case decrement
    }

    /// 二重適用を防ぐためのID
    var id: UUID
    var projectID: UUID
    var action: Action
    var issuedAt: Date

    init(projectID: UUID, action: Action, id: UUID = UUID(), issuedAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.action = action
        self.issuedAt = issuedAt
    }
}

enum SyncCoding {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}
