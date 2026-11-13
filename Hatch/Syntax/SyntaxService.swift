import Foundation
import Observation

/// Настройки, от которых зависит результат форматирования.
struct SyntaxOptions: Hashable, Sendable {
    var allowed: Set<SyntaxKind>
    /// Регистр ключевых слов SQL: "upper", "lower", "preserve".
    var sqlCase: String = "upper"
    /// Диалект sql-formatter: "sql", "postgresql", "mysql", "clickhouse"…
    var sqlDialect: String = "sql"
}

enum SyntaxMode: Hashable, Sendable {
    /// Целиком: отформатировано (окно просмотра, блок команды).
    case full
    /// Для строки списка: JSON и SQL — в одну строку.
    case compact
}

/// Формат текста и готовая подсветка — с запоминанием: строки списка и блоки спрашивают при каждой
/// отрисовке. Считается в фоне; пока не готово — nil, вид показывает текст как есть и обновится сам.
@MainActor @Observable
final class SyntaxService {
    static let shared = SyntaxService()

    private struct Key: Hashable {
        let text: Int
        let count: Int
        let kind: SyntaxKind
        let mode: SyntaxMode
        let options: SyntaxOptions
    }

    private struct KindKey: Hashable {
        let text: Int
        let count: Int
        let allowed: Set<SyntaxKind>
    }

    private var results: [Key: Highlighted] = [:]
    /// Язык кода по тексту ("" — не код).
    private var codeLanguages: [Int: String] = [:]
    @ObservationIgnored private var kinds: [KindKey: SyntaxKind?] = [:]
    @ObservationIgnored private var pending: Set<Key> = []
    @ObservationIgnored private var pendingCode: Set<Int> = []
    private static let limit = 600

    /// Формат текста; код узнаётся в фоне (до тех пор — nil).
    func kind(of text: String, options: SyntaxOptions) -> SyntaxKind? {
        let key = KindKey(text: text.hashValue, count: text.utf16.count, allowed: options.allowed)
        let detected: SyntaxKind?
        if let cached = kinds[key] {
            detected = cached
        } else {
            if kinds.count > Self.limit * 4 { kinds = [:] }
            detected = SyntaxDetector.detect(text, allowed: options.allowed)
            kinds[key] = detected
        }
        if let detected { return detected }
        guard options.allowed.contains(.code) else { return nil }
        return codeLanguage(of: text) == nil ? nil : .code
    }

    /// Язык кода (highlight.js угадывает его в фоне).
    func codeLanguage(of text: String) -> String? {
        let hash = text.hashValue
        if let language = codeLanguages[hash] { return language.isEmpty ? nil : language }
        // однострочник кодом не считаем: угадывание на коротком тексте ошибается
        guard text.utf8.count <= SyntaxEngine.maxHighlightBytes, text.split(whereSeparator: \.isNewline).count >= 3,
              !pendingCode.contains(hash) else { return nil }
        pendingCode.insert(hash)
        DispatchQueue.global(qos: .userInitiated).async {
            let language = SyntaxEngine.shared.detectCode(text) ?? ""
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.pendingCode.remove(hash)
                    if self.codeLanguages.count > Self.limit { self.codeLanguages = [:] }
                    self.codeLanguages[hash] = language
                }
            }
        }
        return nil
    }

    /// Отформатированный и подсвеченный текст; nil — ещё считается.
    func rendered(_ text: String, kind: SyntaxKind, mode: SyntaxMode, options: SyntaxOptions) -> Highlighted? {
        let key = Key(text: text.hashValue, count: text.utf16.count, kind: kind, mode: mode, options: options)
        if let result = results[key] { return result }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let language = kind == .code ? codeLanguage(of: text) : nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.compute(text, kind: kind, mode: mode, options: options, language: language)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.pending.remove(key)
                    if self.results.count > Self.limit { self.results = [:] }
                    self.results[key] = result
                }
            }
        }
        return nil
    }

    @ObservationIgnored private var ansiCache: [Key: String] = [:]

    /// Для вывода команд: отформатировано и раскрашено цветами ANSI; nil — ещё считается.
    func renderedANSI(_ text: String, kind: SyntaxKind, options: SyntaxOptions) -> String? {
        let key = Key(text: text.hashValue, count: text.utf16.count, kind: kind, mode: .full, options: options)
        if let cached = ansiCache[key] { return cached }
        guard let result = rendered(text, kind: kind, mode: .full, options: options) else { return nil }
        if ansiCache.count > 100 { ansiCache = [:] }
        let ansi = SyntaxRender.ansi(result)
        ansiCache[key] = ansi
        return ansi
    }

    /// Посчитать сразу (тесты, копирование того, что видно).
    nonisolated static func compute(_ text: String, kind: SyntaxKind, mode: SyntaxMode, options: SyntaxOptions,
                                    language: String?) -> Highlighted {
        let engine = SyntaxEngine.shared
        func highlight(_ shown: String, _ language: String?) -> Highlighted {
            guard let language else { return Highlighted(text: shown) }
            return engine.highlight(shown, language: language) ?? Highlighted(text: shown)
        }
        switch kind {
        case .json:
            return JSONSyntax.format(text, compact: mode == .compact)
        case .jsonLines:
            return JSONSyntax.highlight(text)
        case .sql:
            let formatted = engine.formatSQL(text, keywordCase: options.sqlCase, dialect: options.sqlDialect) ?? text
            let shown = mode == .compact ? collapsed(formatted) : formatted
            return highlight(shown, "sql")
        case .xml:
            return highlight(mode == .full ? (XMLSyntax.format(text) ?? text) : text, "xml")
        case .yaml:
            return highlight(text, "yaml")
        case .code:
            return highlight(text, language)
        }
    }

    /// Пробелы и переносы — по одному пробелу (SQL в одну строку).
    nonisolated static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0.isNewline || $0 == "\t" }).joined(separator: " ")
    }
}
