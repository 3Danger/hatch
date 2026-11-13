import Foundation
import Observation
import CoreGraphics

/// Наблюдаемые настройки приложения (UserDefaults).
@Observable
final class SettingsStore {
    /// Глобальный хоткей (строковое обозначение).
    var hotkeyString: String { didSet { defaults.set(hotkeyString, forKey: Keys.hotkey) } }
    /// Тема: "system" | "dark" | "light".
    var themeRaw: String { didSet { defaults.set(themeRaw, forKey: Keys.theme) } }
    /// Язык интерфейса: "en" | "ru".
    var languageCode: String { didSet { defaults.set(languageCode, forKey: Keys.language) } }
    /// Глубина истории (последние N завершённых).
    var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) } }
    /// Сколько экранных строк вывода в свёрнутом блоке (включая строку «скрыто N»).
    var previewLines: Int { didSet { defaults.set(previewLines, forKey: Keys.previewLines) } }
    static let previewLinesRange = 3...30
    static let defaultPreviewLines = 10
    /// Шелл для скрытого запуска.
    var shellPath: String { didSet { defaults.set(shellPath, forKey: Keys.shell) } }
    /// Тайм-аут фоновых команд в секундах; 0 = нет тайм-аута.
    var timeoutSeconds: TimeInterval { didSet { defaults.set(timeoutSeconds, forKey: Keys.timeout) } }
    /// Включать латинскую раскладку, когда курсор в поле ввода команды.
    var latinLayoutInInput: Bool { didSet { defaults.set(latinLayoutInInput, forKey: Keys.latinLayout) } }
    /// Текущая директория лаунчера: в ней запускаются команды, `cd` её меняет. Переживает перезапуск.
    var currentDirectory: String {
        didSet {
            defaults.set(currentDirectory, forKey: Keys.currentDirectory)
            rememberRecent(currentDirectory)
        }
    }
    /// Ширина панели и предел высоты истории: тянутся за край панели, переживают перезапуск.
    var panelWidth: CGFloat { didSet { defaults.set(Double(panelWidth), forKey: Keys.panelWidth) } }
    var historyMaxHeight: CGFloat { didSet { defaults.set(Double(historyMaxHeight), forKey: Keys.historyMaxHeight) } }
    /// Сочетание для дерева папок (пока открыта панель), формат как у горячей клавиши: "cmd-1".
    var folderTreeShortcut: String { didSet { defaults.set(folderTreeShortcut, forKey: Keys.folderTreeShortcut) } }
    static let defaultHotkey = "alt-space"
    static let defaultFolderTreeShortcut = "cmd-1"
    /// Умолчания до 0.1.3: у тех, кто их не менял, сочетания после обновления остаются прежними.
    static let legacyDefaultHotkey = "ctrl-space"
    static let legacyDefaultFolderTreeShortcut = "cmd-p"
    /// Значок в строке меню. Без него Hatch открывается хоткеем или повторным запуском приложения.
    var showStatusIcon: Bool { didSet { defaults.set(showStatusIcon, forKey: Keys.showStatusIcon) } }
    /// Избранные папки и команды (кнопка ★ в поле ввода), в порядке добавления.
    private(set) var favoriteDirectories: [String] { didSet { defaults.set(favoriteDirectories, forKey: Keys.favoriteDirectories) } }
    private(set) var favoriteCommands: [String] { didSet { defaults.set(favoriteCommands, forKey: Keys.favoriteCommands) } }
    /// Недавние директории, свежая первой (меню на пути над полем ввода).
    private(set) var recentDirectories: [String] { didSet { defaults.set(recentDirectories, forKey: Keys.recentDirectories) } }
    static let recentDirectoriesLimit = 10
    /// Enter по имени или алиасу приложения открывает приложение (как в Spotlight).
    var openAppsFromInput: Bool { didSet { defaults.set(openAppsFromInput, forKey: Keys.openApps) } }
    /// Калькулятор в поле ввода: результат справа, Enter копирует.
    var calculatorInInput: Bool { didSet { defaults.set(calculatorInInput, forKey: Keys.calculator) } }
    /// Разделитель дробной части результата, если во вводе его нет: "." или ",".
    var calculatorSeparator: String { didSet { defaults.set(calculatorSeparator, forKey: Keys.calculatorSeparator) } }
    /// Результат всегда с `calculatorSeparator`, как бы ни было набрано.
    var calculatorForceSeparator: Bool { didSet { defaults.set(calculatorForceSeparator, forKey: Keys.calculatorForce) } }
    /// Алиас → приложение (bundle id или путь): `code` → VS Code.
    private(set) var appAliases: [String: String] { didSet { defaults.set(appAliases, forKey: Keys.appAliases) } }
    /// Имена, которые остаются командами, даже если совпали с приложением (`claude`, `mail`).
    private(set) var appExclusions: [String] { didSet { defaults.set(appExclusions, forKey: Keys.appExclusions) } }
    /// История буфера обмена (⌘4): слежение за копированием в любых приложениях.
    var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled) } }
    /// Сколько дней хранить скопированное.
    var clipboardDays: Int { didSet { defaults.set(clipboardDays, forKey: Keys.clipboardDays) } }
    /// Сохранять картинки (скриншоты, «Скопировать изображение»), если в буфере нет текста.
    var clipboardImages: Bool { didSet { defaults.set(clipboardImages, forKey: Keys.clipboardImages) } }
    /// Распознавать текст на картинках — для поиска (встроенное распознавание macOS, без сети).
    var clipboardRecognizeText: Bool { didSet { defaults.set(clipboardRecognizeText, forKey: Keys.clipboardOCR) } }
    static let clipboardDaysRange = 1...30
    static let defaultClipboardDays = 7
    /// Скриншоты Hatch: область экрана по сочетанию — в буфер и в историю, миниатюра справа внизу.
    var screenshotsEnabled: Bool { didSet { defaults.set(screenshotsEnabled, forKey: Keys.screenshotsEnabled) } }
    /// Сочетание снимка, работает и когда панель скрыта. По умолчанию ⇧⌘4 — его сначала выключают в macOS.
    var screenshotShortcut: String { didSet { defaults.set(screenshotShortcut, forKey: Keys.screenshotShortcut) } }
    /// Сколько секунд миниатюра снимка висит справа внизу.
    var screenshotThumbnailSeconds: Int { didSet { defaults.set(screenshotThumbnailSeconds, forKey: Keys.screenshotSeconds) } }
    static let defaultScreenshotShortcut = "cmd-shift-4"
    static let screenshotSecondsRange = 3...30
    static let defaultScreenshotSeconds = 10
    /// Форматирование и подсветка (JSON, SQL, YAML, XML, код) в буфере и в выводе команд: новые записи и блоки
    /// сразу отформатированы; у каждой кнопка {} (⌘R) меняет для неё.
    var formatByDefault: Bool { didSet { defaults.set(formatByDefault, forKey: Keys.formatByDefault) } }
    /// Какие форматы узнавать: "json", "sql", "yaml", "xml", "code" (код — только подсветка).
    var formatKinds: [String] { didSet { defaults.set(formatKinds, forKey: Keys.formatKinds) } }
    /// Регистр ключевых слов SQL: "upper", "lower", "preserve".
    var sqlKeywordCase: String { didSet { defaults.set(sqlKeywordCase, forKey: Keys.sqlKeywordCase) } }
    /// Формат SQL: "standard" (sql-formatter) или "hatch" — свой, бета: столбцы с запятой в начале,
    /// `WHERE TRUE` и `  AND …` по строке.
    var sqlStyle: String { didSet { defaults.set(sqlStyle, forKey: Keys.sqlStyle) } }
    /// Диалект SQL для форматирования: "sql", "postgresql", "mysql", "clickhouse".
    var sqlDialect: String { didSet { defaults.set(sqlDialect, forKey: Keys.sqlDialect) } }
    /// Команды, вывод которых показывается как есть (`cat`, `less`).
    private(set) var formatExcludedCommands: [String] { didSet { defaults.set(formatExcludedCommands, forKey: Keys.formatExcludedCommands) } }
    /// Приложения (bundle id), скопированное из которых в буфере не форматируется.
    private(set) var formatExcludedApps: [String] { didSet { defaults.set(formatExcludedApps, forKey: Keys.formatExcludedApps) } }
    static let defaultFormatKinds = ["json", "sql", "yaml", "xml"]
    static let defaultFormatExcludedCommands = ["cat", "less"]
    static let sqlDialects = ["sql", "postgresql", "mysql", "clickhouse"]
    /// Приложения (bundle id), из которых скопированное не сохраняется.
    private(set) var clipboardExcludedApps: [String] { didSet { defaults.set(clipboardExcludedApps, forKey: Keys.clipboardExcluded) } }
    /// Менеджеры паролей: их копирование и так помечено скрытым, но бывают старые версии без пометки.
    static let defaultClipboardExcludedApps = ["com.1password.1password", "com.agilebits.onepassword7",
                                               "com.apple.Passwords", "com.apple.keychainaccess"]
    static let defaultAppAliases = ["vscode": "com.microsoft.VSCode", "code": "com.microsoft.VSCode"]
    /// CLI, у которых есть одноимённое приложение: `claude` должен запускать Claude Code, а не Claude.app.
    static let defaultAppExclusions = ["claude", "ollama", "opencode"]

    private let defaults: UserDefaults

    private enum Keys {
        static let hotkey = "settings.hotkey"
        static let theme = "settings.theme"
        static let language = "settings.language"
        static let historyLimit = "settings.historyLimit"
        static let shell = "settings.shell"
        static let previewLines = "settings.previewLines"
        static let timeout = "settings.timeout"
        static let latinLayout = "settings.latinLayoutInInput"
        static let currentDirectory = "settings.currentDirectory"
        static let recentDirectories = "settings.recentDirectories"
        static let panelWidth = "settings.panelWidth"
        static let historyMaxHeight = "settings.historyMaxHeight"
        static let showStatusIcon = "settings.showStatusIcon"
        static let folderTreeShortcut = "settings.folderTreeShortcut"
        static let favoriteDirectories = "settings.favoriteDirectories"
        static let favoriteCommands = "settings.favoriteCommands"
        static let openApps = "settings.openAppsFromInput"
        static let calculator = "settings.calculatorInInput"
        static let calculatorSeparator = "settings.calculatorSeparator"
        static let calculatorForce = "settings.calculatorForceSeparator"
        static let appAliases = "settings.appAliases"
        static let appExclusions = "settings.appExclusions"
        static let clipboardEnabled = "settings.clipboardEnabled"
        static let clipboardDays = "settings.clipboardDays"
        static let clipboardExcluded = "settings.clipboardExcludedApps"
        static let clipboardImages = "settings.clipboardImages"
        static let clipboardOCR = "settings.clipboardRecognizeText"
        static let screenshotsEnabled = "settings.screenshotsEnabled"
        static let formatByDefault = "settings.formatByDefault"
        static let formatKinds = "settings.formatKinds"
        static let sqlKeywordCase = "settings.sqlKeywordCase"
        static let sqlDialect = "settings.sqlDialect"
        static let sqlStyle = "settings.sqlStyle"
        static let formatExcludedCommands = "settings.formatExcludedCommands"
        static let formatExcludedApps = "settings.formatExcludedApps"
        static let screenshotShortcut = "settings.screenshotShortcut"
        static let screenshotSeconds = "settings.screenshotThumbnailSeconds"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.keepLegacyShortcuts(in: defaults)
        self.hotkeyString = defaults.string(forKey: Keys.hotkey) ?? Self.defaultHotkey
        self.themeRaw = defaults.string(forKey: Keys.theme) ?? "system"
        self.languageCode = defaults.string(forKey: Keys.language) ?? "en"
        let limit = defaults.object(forKey: Keys.historyLimit) as? Int
        self.historyLimit = limit ?? 50
        let preview = defaults.object(forKey: Keys.previewLines) as? Int
        self.previewLines = min(max(preview ?? Self.defaultPreviewLines, Self.previewLinesRange.lowerBound),
                                Self.previewLinesRange.upperBound)
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellPath = defaults.string(forKey: Keys.shell) ?? defaultShell
        let timeout = defaults.object(forKey: Keys.timeout) as? TimeInterval
        self.timeoutSeconds = timeout ?? 0
        self.latinLayoutInInput = defaults.object(forKey: Keys.latinLayout) as? Bool ?? true
        let savedDirectory = defaults.string(forKey: Keys.currentDirectory)
        self.currentDirectory = savedDirectory.flatMap { Self.isDirectory($0) ? $0 : nil } ?? Self.homeDirectory
        self.recentDirectories = defaults.stringArray(forKey: Keys.recentDirectories) ?? []
        self.showStatusIcon = defaults.object(forKey: Keys.showStatusIcon) as? Bool ?? true
        self.folderTreeShortcut = defaults.string(forKey: Keys.folderTreeShortcut) ?? Self.defaultFolderTreeShortcut
        self.favoriteDirectories = defaults.stringArray(forKey: Keys.favoriteDirectories) ?? []
        self.favoriteCommands = defaults.stringArray(forKey: Keys.favoriteCommands) ?? []
        self.openAppsFromInput = defaults.object(forKey: Keys.openApps) as? Bool ?? true
        self.calculatorInInput = defaults.object(forKey: Keys.calculator) as? Bool ?? true
        self.calculatorSeparator = defaults.string(forKey: Keys.calculatorSeparator) == "," ? "," : "."
        self.calculatorForceSeparator = defaults.object(forKey: Keys.calculatorForce) as? Bool ?? false
        self.appAliases = defaults.dictionary(forKey: Keys.appAliases) as? [String: String] ?? Self.defaultAppAliases
        self.appExclusions = defaults.stringArray(forKey: Keys.appExclusions) ?? Self.defaultAppExclusions
        self.clipboardEnabled = defaults.object(forKey: Keys.clipboardEnabled) as? Bool ?? true
        let days = defaults.object(forKey: Keys.clipboardDays) as? Int ?? Self.defaultClipboardDays
        self.clipboardDays = min(max(days, Self.clipboardDaysRange.lowerBound), Self.clipboardDaysRange.upperBound)
        self.clipboardExcludedApps = defaults.stringArray(forKey: Keys.clipboardExcluded) ?? Self.defaultClipboardExcludedApps
        self.clipboardImages = defaults.object(forKey: Keys.clipboardImages) as? Bool ?? true
        self.clipboardRecognizeText = defaults.object(forKey: Keys.clipboardOCR) as? Bool ?? true
        self.screenshotsEnabled = defaults.object(forKey: Keys.screenshotsEnabled) as? Bool ?? true
        self.formatByDefault = defaults.object(forKey: Keys.formatByDefault) as? Bool ?? true
        self.formatKinds = defaults.stringArray(forKey: Keys.formatKinds) ?? Self.defaultFormatKinds
        let keywordCase = defaults.string(forKey: Keys.sqlKeywordCase) ?? "upper"
        self.sqlKeywordCase = ["upper", "lower", "preserve"].contains(keywordCase) ? keywordCase : "upper"
        let dialect = defaults.string(forKey: Keys.sqlDialect) ?? "sql"
        self.sqlDialect = Self.sqlDialects.contains(dialect) ? dialect : "sql"
        self.sqlStyle = defaults.string(forKey: Keys.sqlStyle) == "hatch" ? "hatch" : "standard"
        self.formatExcludedCommands = defaults.stringArray(forKey: Keys.formatExcludedCommands) ?? Self.defaultFormatExcludedCommands
        self.formatExcludedApps = defaults.stringArray(forKey: Keys.formatExcludedApps) ?? []
        self.screenshotShortcut = defaults.string(forKey: Keys.screenshotShortcut) ?? Self.defaultScreenshotShortcut
        let seconds = defaults.object(forKey: Keys.screenshotSeconds) as? Int ?? Self.defaultScreenshotSeconds
        self.screenshotThumbnailSeconds = min(max(seconds, Self.screenshotSecondsRange.lowerBound),
                                              Self.screenshotSecondsRange.upperBound)
        let width = defaults.object(forKey: Keys.panelWidth) as? Double
        self.panelWidth = PanelSize.clampWidth(width.map { CGFloat($0) } ?? PanelSize.defaultWidth)
        let height = defaults.object(forKey: Keys.historyMaxHeight) as? Double
        self.historyMaxHeight = PanelSize.clampHistoryHeight(height.map { CGFloat($0) } ?? PanelSize.defaultHistoryHeight)
    }

    /// Умолчания сочетаний сменились (⌃Space → ⌥Space, ⌘P → ⌘1). Новая установка получает новые,
    /// а у прежней (настройки Hatch уже есть) несохранённые сочетания записываются старыми —
    /// иначе после обновления хоткей молча стал бы другим.
    static func keepLegacyShortcuts(in defaults: UserDefaults) {
        let existing = defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("settings.") }
        guard existing else { return }
        if defaults.string(forKey: Keys.hotkey) == nil { defaults.set(legacyDefaultHotkey, forKey: Keys.hotkey) }
        if defaults.string(forKey: Keys.folderTreeShortcut) == nil {
            defaults.set(legacyDefaultFolderTreeShortcut, forKey: Keys.folderTreeShortcut)
        }
    }

    /// Перейти в папку, как `cd`: только если она ещё существует. false — папки нет, ничего не меняем.
    @discardableResult
    func navigate(to path: String) -> Bool {
        guard Self.isDirectory(path) else { return false }
        if path != currentDirectory { currentDirectory = path }
        return true
    }

    // MARK: - Избранное

    /// Добавить папку в избранное или убрать оттуда. true — теперь в избранном.
    @discardableResult
    func toggleFavoriteDirectory(_ path: String) -> Bool {
        if let index = favoriteDirectories.firstIndex(of: path) {
            favoriteDirectories.remove(at: index)
            return false
        }
        favoriteDirectories.append(path)
        return true
    }

    /// Добавить команду в избранное или убрать оттуда. true — теперь в избранном.
    @discardableResult
    func toggleFavoriteCommand(_ command: String) -> Bool {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return false }
        if let index = favoriteCommands.firstIndex(of: command) {
            favoriteCommands.remove(at: index)
            return false
        }
        favoriteCommands.append(command)
        return true
    }

    /// Порядок избранного меняется перетаскиванием и ⌘↑/⌘↓ в списке «Избранное».
    func moveFavoriteDirectory(from source: Int, to destination: Int) {
        favoriteDirectories = Self.moved(favoriteDirectories, from: source, to: destination)
    }

    func moveFavoriteCommand(from source: Int, to destination: Int) {
        favoriteCommands = Self.moved(favoriteCommands, from: source, to: destination)
    }

    /// Элемент `source` встаёт на место `destination` (остальные сдвигаются); вне списка — без изменений.
    static func moved<T>(_ list: [T], from source: Int, to destination: Int) -> [T] {
        guard list.indices.contains(source), list.indices.contains(destination), source != destination else { return list }
        var result = list
        let item = result.remove(at: source)
        result.insert(item, at: destination)
        return result
    }

    func isFavoriteCommand(_ command: String) -> Bool {
        favoriteCommands.contains(command.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Приложения из поля ввода

    /// Алиас без пробелов, в нижнем регистре; занятый алиас переходит к новому приложению.
    func setAlias(_ alias: String, for appID: String) {
        let alias = Self.normalizedName(alias)
        guard !alias.isEmpty, !alias.contains(where: \.isWhitespace) else { return }
        appAliases[alias] = appID
    }

    func removeAlias(_ alias: String) {
        appAliases[alias] = nil
    }

    func addExclusion(_ name: String) {
        let name = Self.normalizedName(name)
        guard !name.isEmpty, !appExclusions.contains(name) else { return }
        appExclusions.append(name)
    }

    func removeExclusion(_ name: String) {
        appExclusions.removeAll { $0 == name }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func addClipboardExclusion(_ bundleID: String) {
        guard !bundleID.isEmpty, !clipboardExcludedApps.contains(bundleID) else { return }
        clipboardExcludedApps.append(bundleID)
    }

    func removeClipboardExclusion(_ bundleID: String) {
        clipboardExcludedApps.removeAll { $0 == bundleID }
    }

    /// Разбор поля ввода с текущими настройками.
    func quickActionResolver(apps: [AppEntry]) -> QuickActionResolver {
        QuickActionResolver(apps: apps, aliases: appAliases, exclusions: appExclusions,
                            appsEnabled: openAppsFromInput, calculatorEnabled: calculatorInInput,
                            decimalSeparator: calculatorSeparator == "," ? "," : ".",
                            forceDecimalSeparator: calculatorForceSeparator)
    }

    private func rememberRecent(_ path: String) {
        var list = recentDirectories.filter { $0 != path }
        list.insert(path, at: 0)
        recentDirectories = Array(list.prefix(Self.recentDirectoriesLimit))
    }

    static var homeDirectory: String { FileManager.default.homeDirectoryForCurrentUser.path }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    var theme: ThemePreference? { ThemePreference(rawValue: themeRaw) }

    // MARK: - Форматирование

    /// Что узнавать и как форматировать. Логи из JSON-строк идут вместе с JSON.
    var syntaxOptions: SyntaxOptions {
        var allowed = Set(formatKinds.compactMap(SyntaxKind.init(rawValue:)))
        if allowed.contains(.json) { allowed.insert(.jsonLines) }
        return SyntaxOptions(allowed: allowed, sqlCase: sqlKeywordCase, sqlDialect: sqlDialect, sqlStyle: sqlStyle)
    }

    func toggleFormatKind(_ kind: String) {
        if formatKinds.contains(kind) { formatKinds.removeAll { $0 == kind } } else { formatKinds.append(kind) }
    }

    /// Форматировать ли скопированное из приложения, пока у записи не нажимали {}.
    func formatsByDefault(bundleID: String?) -> Bool {
        formatByDefault && !(bundleID.map(formatExcludedApps.contains) ?? false)
    }

    /// Форматировать ли вывод команды, пока у блока не нажимали {}: по первому слову (`cat file.json` — нет).
    func formatsByDefault(command: String) -> Bool {
        let word = command.split(whereSeparator: \.isWhitespace).first.map { String($0).split(separator: "/").last.map(String.init) ?? "" } ?? ""
        return formatByDefault && !formatExcludedCommands.contains(word)
    }

    func addFormatExcludedCommand(_ name: String) {
        let word = name.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !formatExcludedCommands.contains(word) else { return }
        formatExcludedCommands.append(word)
    }

    func removeFormatExcludedCommand(_ name: String) { formatExcludedCommands.removeAll { $0 == name } }

    func addFormatExcludedApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !formatExcludedApps.contains(bundleID) else { return }
        formatExcludedApps.append(bundleID)
    }

    func removeFormatExcludedApp(_ bundleID: String) { formatExcludedApps.removeAll { $0 == bundleID } }

    func resetToDefaults() {
        hotkeyString = Self.defaultHotkey
        themeRaw = "system"
        languageCode = "en"
        historyLimit = 50
        previewLines = Self.defaultPreviewLines
        shellPath = "/bin/zsh"
        timeoutSeconds = 0
        latinLayoutInInput = true
        showStatusIcon = true
        openAppsFromInput = true
        calculatorInInput = true
        calculatorSeparator = "."
        calculatorForceSeparator = false
        screenshotsEnabled = true
        formatByDefault = true
        formatKinds = Self.defaultFormatKinds
        sqlKeywordCase = "upper"
        sqlDialect = "sql"
        sqlStyle = "standard"
        formatExcludedCommands = Self.defaultFormatExcludedCommands
        formatExcludedApps = []
        screenshotShortcut = Self.defaultScreenshotShortcut
        screenshotThumbnailSeconds = Self.defaultScreenshotSeconds
        clipboardEnabled = true
        clipboardDays = Self.defaultClipboardDays
        clipboardImages = true
        clipboardRecognizeText = true
        folderTreeShortcut = Self.defaultFolderTreeShortcut
        panelWidth = PanelSize.defaultWidth
        historyMaxHeight = PanelSize.defaultHistoryHeight
    }
}

/// Размер панели: ширина и предел высоты истории (выше — прокрутка). Границы — чтобы панель
/// не стала неработающей: в заголовок блока должны влезать кнопки, в историю — хоть пара блоков.
enum PanelSize {
    static let defaultWidth: CGFloat = 720
    static let defaultHistoryHeight: CGFloat = 470
    static let widthRange: ClosedRange<CGFloat> = 520...2400
    static let historyHeightRange: ClosedRange<CGFloat> = 160...1600

    static func clampWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, widthRange.lowerBound), widthRange.upperBound).rounded()
    }

    static func clampHistoryHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, historyHeightRange.lowerBound), historyHeightRange.upperBound).rounded()
    }

    /// Новый размер при перетаскивании края: от размера в начале на смещение мыши
    /// (`dy` > 0 — вниз), но не за край экрана (`room` — сколько места было до него).
    static func resized(start: CGSize, by delta: CGSize, room: CGSize, edges: ResizeEdges) -> CGSize {
        var size = start
        if edges.contains(.right) {
            size.width = clampWidth(min(start.width + delta.width, start.width + max(room.width, 0)))
        }
        if edges.contains(.bottom) {
            size.height = clampHistoryHeight(min(start.height + delta.height, start.height + max(room.height, 0)))
        }
        return size
    }
}

/// За какие края тянут панель. Верхний левый угол панели закреплён — тянутся правый и нижний.
struct ResizeEdges: OptionSet, Hashable {
    let rawValue: Int
    static let right = ResizeEdges(rawValue: 1)
    static let bottom = ResizeEdges(rawValue: 2)
}

/// Предпочтение темы.
enum ThemePreference: String, CaseIterable, Codable {
    case system
    case dark
    case light
}
