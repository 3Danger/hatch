import AppKit
import Observation

/// Приложение, которое открывается из поля ввода по имени или алиасу.
struct AppEntry: Hashable {
    let url: URL
    let bundleID: String?
    /// Имя файла без `.app`: «Calculator».
    let name: String
    /// Имя на языке системы, если отличается: «Калькулятор».
    let localizedName: String?

    /// Как показывать в подписи и настройках.
    var title: String { localizedName ?? name }
    /// Под какими именами искать: оба варианта.
    var names: [String] { [name] + (localizedName.map { [$0] } ?? []) }
    /// Ключ для алиаса в настройках: bundle id переживает переезд приложения, путь — запасной.
    var identifier: String { bundleID ?? url.path }
}

/// Список установленных приложений: «Программы», системные и `~/Applications`,
/// в каждой — ещё на уровень вглубь («Утилиты», папки вроде «Chrome Apps»).
@Observable
final class AppCatalog {
    static let shared = AppCatalog()

    private(set) var apps: [AppEntry] = []
    @ObservationIgnored private var scanning = false

    static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    /// Перечитать в фоне (при каждом показе панели: приложения ставят и удаляют).
    func refresh() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let found = Self.scan(Self.defaultRoots)
            DispatchQueue.main.async {
                if found != self.apps { self.apps = found }
                self.scanning = false
            }
        }
    }

    static func scan(_ roots: [URL], languages: [String] = Locale.preferredLanguages) -> [AppEntry] {
        var seen = Set<String>()
        var result: [AppEntry] = []
        for root in roots {
            for url in bundles(in: root, depth: 1) {
                let entry = entry(for: url, languages: languages)
                // одно приложение в двух местах (системное и копия) — первым найденное
                guard seen.insert(entry.identifier).inserted else { continue }
                result.append(entry)
            }
        }
        return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func bundles(in folder: URL, depth: Int) -> [URL] {
        // без .skipsHiddenFiles: /Applications/Safari.app — скрытая ссылка в системный раздел
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
        var found: [URL] = []
        for item in items where !item.lastPathComponent.hasPrefix(".") {
            if item.pathExtension == "app" {
                found.append(item)
            } else if depth > 0, (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                found += bundles(in: item, depth: depth - 1)
            }
        }
        return found
    }

    private static func entry(for url: URL, languages: [String]) -> AppEntry {
        let name = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        var localized: String?
        if let bundle {
            // имя на языке системы, а не Hatch: у Hatch только английская локализация
            let preferred = languages.map { Locale.Language(identifier: $0) }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                // невидимые символы направления текста («‎WhatsApp») мешают сравнивать имена
                let value = bundle.localizedString(forKey: key, value: "", table: "InfoPlist", localizations: preferred)
                    .unicodeScalars.filter { $0.properties.generalCategory != .format }
                    .reduce(into: "") { $0.unicodeScalars.append($1) }
                if !value.isEmpty, value != key {
                    localized = value
                    break
                }
            }
        }
        if let value = localized, value.compare(name, options: .caseInsensitive) == .orderedSame { localized = nil }
        return AppEntry(url: url, bundleID: bundle?.bundleIdentifier, name: name, localizedName: localized)
    }
}

/// Подсказка приложения по началу имени: «saf» → Safari.
struct AppSuggestion: Equatable {
    let app: AppEntry
    /// Строка после дописывания: набранное как есть плюс остаток имени («saf» → «safari»).
    let completion: String
    /// Имя или алиас, до которого дописывается («Safari», «code»).
    let name: String
    /// Сколько ещё приложений начинаются так же («te»: Telegram и ещё 2).
    let others: Int
    /// Вариант один и набранное ни с чем не совпадает полностью — Enter дописывает имя.
    let completesOnEnter: Bool
}

/// Что сделает Enter для набранного (подпись справа в поле). nil — выполнить как команду.
enum QuickAction: Equatable {
    /// По началу имени: Tab или → дописывают имя; Enter — тоже, если вариант один.
    case suggestApp(AppSuggestion)
    case openApp(AppEntry)
    /// Имя и существующие пути: `code .` открывает текущую папку в VS Code.
    case openPaths(AppEntry, [URL])
    case calculate(Double)
    case divisionByZero

    /// Enter делает своё, а не выполняет команду.
    var handlesEnter: Bool {
        if case .suggestApp = self { return false }
        return true
    }
}

/// Разбор набранного: расчёт, приложение по имени или алиасу, подсказка по началу имени.
struct QuickActionResolver {
    var apps: [AppEntry] = []
    /// Алиас → приложение (`AppEntry.identifier`).
    var aliases: [String: String] = [:]
    /// Имена, которые всегда остаются командами.
    var exclusions: [String] = []
    var appsEnabled = true
    var calculatorEnabled = true
    /// Шелл знает это имя (команда, алиас, функция): тогда Enter его выполняет, а не дописывает.
    var isCommand: (String) -> Bool = { _ in false }
    /// С какого числа букв подсказывать приложение по началу имени.
    static let minimumPrefix = 2

    func resolve(_ text: String, directory: String) -> QuickAction? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if calculatorEnabled, let outcome = Calculator.evaluate(trimmed) {
            switch outcome {
            case .value(let value): return .calculate(value)
            case .divisionByZero: return .divisionByZero
            }
        }
        guard appsEnabled, !apps.isEmpty else { return nil }
        let excluded = Set(exclusions.map { $0.lowercased() })
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        // имя может быть из нескольких слов («visual studio code .»): сначала самое длинное
        for count in stride(from: tokens.count, through: 1, by: -1) {
            let name = tokens[0..<count].joined(separator: " ").lowercased()
            guard !excluded.contains(name), let app = app(named: name) else { continue }
            let rest = tokens[count...]
            if rest.isEmpty { return .openApp(app) }
            let urls = rest.compactMap { Self.existingPath($0, directory: directory) }
            if urls.count == rest.count { return .openPaths(app, urls) }
        }
        // подсказка — пока набирается первое слово имени, без пробела в конце
        guard !text.hasSuffix(" "), trimmed.count >= Self.minimumPrefix,
              let suggestion = suggestion(for: trimmed, excluded: excluded) else { return nil }
        return .suggestApp(suggestion)
    }

    /// Приложение по алиасу или по полному имени (без учёта регистра).
    func app(named name: String) -> AppEntry? {
        let name = name.lowercased()
        if let id = aliases.first(where: { $0.key.lowercased() == name })?.value,
           let app = apps.first(where: { $0.identifier == id }) {
            return app
        }
        return apps.first { $0.names.contains { $0.lowercased() == name } }
    }

    /// Самое короткое имя или алиас, начинающиеся с набранного: «saf» → «safari».
    private func suggestion(for typed: String, excluded: Set<String>) -> AppSuggestion? {
        let lower = typed.lowercased()
        var candidates: [(app: AppEntry, name: String)] = []
        for (alias, id) in aliases {
            if let app = apps.first(where: { $0.identifier == id }) { candidates.append((app, alias)) }
        }
        for app in apps { for name in app.names { candidates.append((app, name)) } }
        let matching = candidates
            .filter { $0.name.count > typed.count && $0.name.lowercased().hasPrefix(lower) && !excluded.contains($0.name.lowercased()) }
        guard let best = matching.min(by: { ($0.name.count, $0.name.lowercased()) < ($1.name.count, $1.name.lowercased()) })
        else { return nil }
        // алиас и имя одного приложения — один вариант (code и Visual Studio Code)
        let others = Set(matching.map(\.app.identifier)).count - 1
        return AppSuggestion(app: best.app,
                             completion: typed + best.name.dropFirst(typed.count), // набранное как есть
                             name: best.name, others: others,
                             completesOnEnter: others == 0 && !isCommand(typed))
    }

    /// Аргумент — существующий файл или папка: `.`, `~/proj`, `src/main.go`.
    static func existingPath(_ token: String, directory: String) -> URL? {
        var path = token
        if path.count >= 2, let first = path.first, (first == "\"" || first == "'"), path.last == first {
            path = String(path.dropFirst().dropLast())
        }
        if path == "~" || path.hasPrefix("~/") {
            path = FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst()
        }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                                      : URL(fileURLWithPath: directory).appendingPathComponent(path)
        let standardized = url.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }
}

extension QuickAction {
    /// Выполнить по Enter. false — Enter не для нас (выполнить команду).
    @discardableResult
    func perform() -> Bool {
        switch self {
        case .openApp(let app):
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        case .openPaths(let app, let urls):
            NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
        case .calculate(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Calculator.clipboard(value), forType: .string)
        case .divisionByZero:
            NSSound.beep()
        case .suggestApp:
            return false
        }
        return true
    }
}
