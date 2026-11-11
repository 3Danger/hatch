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
        XCTAssertEqual(store.previewLines, 10)
    }

    /// «Строк в превью» сохраняется; сохранённое вне границ поправляется при чтении.
    func testPreviewLinesPersistAndClamp() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        store.previewLines = 15
        XCTAssertEqual(SettingsStore(defaults: defaults).previewLines, 15)
        defaults.set(500, forKey: "settings.previewLines")
        XCTAssertEqual(SettingsStore(defaults: defaults).previewLines, 30)
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

    // MARK: - Размер панели

    /// Размер, выставленный перетаскиванием края, переживает перезапуск.
    func testPanelSizePersists() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.panelWidth, PanelSize.defaultWidth)
        XCTAssertEqual(store.historyMaxHeight, PanelSize.defaultHistoryHeight)
        store.panelWidth = 900
        store.historyMaxHeight = 640
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.panelWidth, 900)
        XCTAssertEqual(reloaded.historyMaxHeight, 640)
    }

    /// Испорченное или старое значение не делает панель неработающей.
    func testSavedPanelSizeIsClamped() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(10.0, forKey: "settings.panelWidth")
        defaults.set(99_999.0, forKey: "settings.historyMaxHeight")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.panelWidth, PanelSize.widthRange.lowerBound)
        XCTAssertEqual(store.historyMaxHeight, PanelSize.historyHeightRange.upperBound)
    }

    func testResizeFollowsDraggedEdgesOnly() {
        let start = CGSize(width: 720, height: 470)
        let big = CGSize(width: 10_000, height: 10_000)
        let right = PanelSize.resized(start: start, by: CGSize(width: 100, height: 50), room: big, edges: .right)
        XCTAssertEqual(right, CGSize(width: 820, height: 470))
        let bottom = PanelSize.resized(start: start, by: CGSize(width: 100, height: -70), room: big, edges: .bottom)
        XCTAssertEqual(bottom, CGSize(width: 720, height: 400))
        let corner = PanelSize.resized(start: start, by: CGSize(width: -100, height: 30), room: big, edges: [.right, .bottom])
        XCTAssertEqual(corner, CGSize(width: 620, height: 500))
    }

    /// Не за край экрана и не меньше минимума.
    func testResizeStopsAtScreenEdgeAndMinimum() {
        let start = CGSize(width: 720, height: 470)
        let grown = PanelSize.resized(start: start, by: CGSize(width: 500, height: 500),
                                      room: CGSize(width: 80, height: 30), edges: [.right, .bottom])
        XCTAssertEqual(grown, CGSize(width: 800, height: 500))
        let shrunk = PanelSize.resized(start: start, by: CGSize(width: -1000, height: -1000),
                                       room: CGSize(width: 80, height: 30), edges: [.right, .bottom])
        XCTAssertEqual(shrunk, CGSize(width: PanelSize.widthRange.lowerBound,
                                      height: PanelSize.historyHeightRange.lowerBound))
    }
}
