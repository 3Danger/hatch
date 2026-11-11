import XCTest
@testable import Hatch

final class SettingsStoreTests: XCTestCase {

    private var suiteName: String { "SettingsStoreTests.\(UUID().uuidString)" }

    func testDefaults() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(store.hotkeyString, "ctrl-space")
        XCTAssertEqual(store.themeRaw, "system")
        XCTAssertEqual(store.languageCode, "en")
        XCTAssertEqual(store.historyLimit, 50)
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        XCTAssertEqual(store.shellPath, defaultShell)
        XCTAssertEqual(store.timeoutSeconds, 0)
    }

    func testPersistenceRoundTrip() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        store.historyLimit = 123
        store.hotkeyString = "cmd-shift-space"
        store.themeRaw = "dark"
        store.languageCode = "ru"
        store.shellPath = "/bin/bash"
        store.timeoutSeconds = 30

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.historyLimit, 123)
        XCTAssertEqual(reloaded.hotkeyString, "cmd-shift-space")
        XCTAssertEqual(reloaded.themeRaw, "dark")
        XCTAssertEqual(reloaded.languageCode, "ru")
        XCTAssertEqual(reloaded.shellPath, "/bin/bash")
        XCTAssertEqual(reloaded.timeoutSeconds, 30)
    }

    func testThemeParse() {
        let system = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(system.theme, .system)
        system.themeRaw = "dark"
        XCTAssertEqual(system.theme, .dark)
    }

    func testCurrentDirectoryDefaultsToHomeAndPersists() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.currentDirectory, FileManager.default.homeDirectoryForCurrentUser.path)

        let dir = FileManager.default.temporaryDirectory.path
        store.currentDirectory = dir
        XCTAssertEqual(SettingsStore(defaults: defaults).currentDirectory, dir)
    }

    /// Сохранённую директорию удалили — стартуем из домашней.
    func testMissingCurrentDirectoryFallsBackToHome() {
        let defaults = UserDefaults(suiteName: suiteName)!
        SettingsStore(defaults: defaults).currentDirectory = "/no/such/dir-\(UUID().uuidString)"
        XCTAssertEqual(SettingsStore(defaults: defaults).currentDirectory,
                       FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// Недавние папки: свежая первой, без повторов, не больше лимита; переживают перезапуск.
    func testRecentDirectories() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        let tmp = FileManager.default.temporaryDirectory.path
        store.currentDirectory = "/usr"
        store.currentDirectory = tmp
        store.currentDirectory = "/usr"

        XCTAssertEqual(Array(store.recentDirectories.prefix(2)), ["/usr", tmp])
        XCTAssertEqual(store.recentDirectories.filter { $0 == "/usr" }.count, 1)
        XCTAssertEqual(SettingsStore(defaults: defaults).recentDirectories.prefix(2), store.recentDirectories.prefix(2))

        for i in 0..<30 { store.currentDirectory = "/tmp/dir-\(i)" }
        XCTAssertLessThanOrEqual(store.recentDirectories.count, SettingsStore.recentDirectoriesLimit)
    }

    /// Латиница в поле ввода: по умолчанию включена, отключение сохраняется.
    func testLatinLayoutSettingDefaultsOnAndPersists() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.latinLayoutInInput)

        store.latinLayoutInInput = false
        XCTAssertFalse(SettingsStore(defaults: defaults).latinLayoutInInput)
    }

    func testTimeoutDefaultZeroByDesign() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(store.timeoutSeconds, 0, "по умолчанию тайм-аута нет")
    }

    /// Клик по папке в блоке — как cd: существующая папка становится текущей и попадает в недавние.
    func testNavigateToExistingFolder() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nav-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(store.navigate(to: folder.path))
        XCTAssertEqual(store.currentDirectory, folder.path)
        XCTAssertEqual(store.recentDirectories.first, folder.path)
    }

    /// Папку с тех пор удалили — остаёмся, где были.
    func testNavigateToMissingFolderKeepsCurrent() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        let before = store.currentDirectory
        XCTAssertFalse(store.navigate(to: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertEqual(store.currentDirectory, before)
    }
}
