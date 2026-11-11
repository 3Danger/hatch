import Foundation

/// Переход с прежнего имени приложения (MacUtils → Hatch): при первом запуске переносятся
/// история сессий и настройки. Новые данные, если они уже есть, не перезаписываются.
enum LegacyMigration {
    static let legacyName = "MacUtils"
    static let legacyBundleID = "com.example.MacUtils"

    static func run() {
        // под тестами приложение тоже запускается — настоящие данные пользователя не трогаем
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            migrateHistory(applicationSupport: support)
        }
        if let legacy = UserDefaults(suiteName: legacyBundleID) {
            migrateDefaults(from: legacy, to: .standard)
        }
    }

    static func migrateHistory(applicationSupport: URL) {
        let fileManager = FileManager.default
        let old = applicationSupport.appendingPathComponent("\(legacyName)/history.json")
        let new = applicationSupport.appendingPathComponent("Hatch/history.json")
        guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.copyItem(at: old, to: new)
    }

    /// Только ключи приложения: настройки и позиция панели.
    static func migrateDefaults(from old: UserDefaults, to new: UserDefaults) {
        for (key, value) in old.dictionaryRepresentation()
        where (key.hasPrefix("settings.") || key.hasPrefix("panel.")) && new.object(forKey: key) == nil {
            new.set(value, forKey: key)
        }
    }
}
