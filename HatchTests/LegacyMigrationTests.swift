import XCTest
@testable import Hatch

/// Переход с прежнего имени (MacUtils): история и настройки не теряются.
final class LegacyMigrationTests: XCTestCase {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testHistoryIsCopiedOnce() throws {
        let support = try tempDir()
        let old = support.appendingPathComponent("MacUtils/history.json")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[old]".utf8).write(to: old)

        LegacyMigration.migrateHistory(applicationSupport: support)
        let new = support.appendingPathComponent("Hatch/history.json")
        XCTAssertEqual(try String(contentsOf: new, encoding: .utf8), "[old]")

        // новая история уже есть — не перезаписываем
        try Data("[new]".utf8).write(to: new)
        LegacyMigration.migrateHistory(applicationSupport: support)
        XCTAssertEqual(try String(contentsOf: new, encoding: .utf8), "[new]")
    }

    func testNoOldHistoryIsFine() throws {
        let support = try tempDir()
        LegacyMigration.migrateHistory(applicationSupport: support)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("Hatch/history.json").path))
    }

    /// Настройки и позиция панели переносятся; уже заданные под новым именем — не трогаются.
    func testSettingsAreCopiedWithoutOverwriting() {
        let old = UserDefaults(suiteName: "LegacyOld.\(UUID().uuidString)")!
        let new = UserDefaults(suiteName: "LegacyNew.\(UUID().uuidString)")!
        old.set("cmd-shift-space", forKey: "settings.hotkey")
        old.set("dark", forKey: "settings.theme")
        old.set("{10, 20}", forKey: "panel.topLeft")
        old.set("x", forKey: "unrelated.key")
        new.set("light", forKey: "settings.theme")

        LegacyMigration.migrateDefaults(from: old, to: new)

        XCTAssertEqual(new.string(forKey: "settings.hotkey"), "cmd-shift-space")
        XCTAssertEqual(new.string(forKey: "settings.theme"), "light", "своё значение важнее перенесённого")
        XCTAssertEqual(new.string(forKey: "panel.topLeft"), "{10, 20}")
        XCTAssertNil(new.string(forKey: "unrelated.key"))
    }
}
