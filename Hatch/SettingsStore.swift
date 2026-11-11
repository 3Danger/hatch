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
    /// Недавние директории, свежая первой (меню на пути над полем ввода).
    private(set) var recentDirectories: [String] { didSet { defaults.set(recentDirectories, forKey: Keys.recentDirectories) } }
    static let recentDirectoriesLimit = 10

    private let defaults: UserDefaults

    private enum Keys {
        static let hotkey = "settings.hotkey"
        static let theme = "settings.theme"
        static let language = "settings.language"
        static let historyLimit = "settings.historyLimit"
        static let shell = "settings.shell"
        static let timeout = "settings.timeout"
        static let latinLayout = "settings.latinLayoutInInput"
        static let currentDirectory = "settings.currentDirectory"
        static let recentDirectories = "settings.recentDirectories"
        static let panelWidth = "settings.panelWidth"
        static let historyMaxHeight = "settings.historyMaxHeight"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkeyString = defaults.string(forKey: Keys.hotkey) ?? "ctrl-space"
        self.themeRaw = defaults.string(forKey: Keys.theme) ?? "system"
        self.languageCode = defaults.string(forKey: Keys.language) ?? "en"
        let limit = defaults.object(forKey: Keys.historyLimit) as? Int
        self.historyLimit = limit ?? 50
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellPath = defaults.string(forKey: Keys.shell) ?? defaultShell
        let timeout = defaults.object(forKey: Keys.timeout) as? TimeInterval
        self.timeoutSeconds = timeout ?? 0
        self.latinLayoutInInput = defaults.object(forKey: Keys.latinLayout) as? Bool ?? true
        let savedDirectory = defaults.string(forKey: Keys.currentDirectory)
        self.currentDirectory = savedDirectory.flatMap { Self.isDirectory($0) ? $0 : nil } ?? Self.homeDirectory
        self.recentDirectories = defaults.stringArray(forKey: Keys.recentDirectories) ?? []
        let width = defaults.object(forKey: Keys.panelWidth) as? Double
        self.panelWidth = PanelSize.clampWidth(width.map { CGFloat($0) } ?? PanelSize.defaultWidth)
        let height = defaults.object(forKey: Keys.historyMaxHeight) as? Double
        self.historyMaxHeight = PanelSize.clampHistoryHeight(height.map { CGFloat($0) } ?? PanelSize.defaultHistoryHeight)
    }

    /// Перейти в папку, как `cd`: только если она ещё существует. false — папки нет, ничего не меняем.
    @discardableResult
    func navigate(to path: String) -> Bool {
        guard Self.isDirectory(path) else { return false }
        if path != currentDirectory { currentDirectory = path }
        return true
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

    func resetToDefaults() {
        hotkeyString = "ctrl-space"
        themeRaw = "system"
        languageCode = "en"
        historyLimit = 50
        shellPath = "/bin/zsh"
        timeoutSeconds = 0
        latinLayoutInInput = true
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
