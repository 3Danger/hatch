import Foundation

/// Персистентность истории сессий в JSON-файл.
final class HistoryStore {
    /// Лимит завершённых сессий по умолчанию.
    static let defaultLimit = 50

    private let fileURL: URL
    private let defaultLimit: Int

    init(fileURL: URL? = nil, defaultLimit: Int = HistoryStore.defaultLimit) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = base.appendingPathComponent("Hatch", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("history.json")
        }
        self.defaultLimit = defaultLimit
    }

    func load(limit: Int? = nil) -> [Session] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Session].self, from: data) else {
            return []
        }
        return applyCap(to: decoded, limit: limit ?? defaultLimit)
    }

    /// Сколько раз история реально записывалась на диск (для тестов).
    private(set) var writeCount = 0
    private var lastWritten: Data?

    func save(_ sessions: [Session], limit: Int? = nil) {
        let capped = applyCap(to: sessions, limit: limit ?? defaultLimit)
        // ключи по порядку: одинаковая история — одинаковые байты, иначе «не изменилось» не узнать
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(capped), data != lastWritten else { return }
        try? data.write(to: fileURL, options: .atomic)
        lastWritten = data
        writeCount += 1
    }

    /// Завершённые ограничиваются до `limit` (последние по времени); активные и закреплённые
    /// сохраняются все — закрепление защищает от удаления.
    func applyCap(to sessions: [Session], limit: Int) -> [Session] {
        var active: [Session] = []
        var finished: [Session] = []
        for s in sessions {
            if s.state.isActive || s.isPinned { active.append(s) } else { finished.append(s) }
        }
        finished.sort { $0.createdAt > $1.createdAt }
        if finished.count > limit {
            finished = Array(finished.prefix(limit))
        }
        return active + finished
    }
}
