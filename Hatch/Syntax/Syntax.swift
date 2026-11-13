import Foundation
import AppKit
import SwiftUI
import JavaScriptCore

// Форматирование и подсветка текста в буфере и в выводе команд: JSON, SQL, YAML, XML, код.
// Формат узнаётся здесь же; JSON форматируется своим кодом (быстро, порядок ключей как в исходнике),
// SQL — sql-formatter, XML — средствами macOS, подсветка YAML, SQL, XML и кода — highlight.js
// (оба — JavaScript, во встроенном в macOS JavaScriptCore, в фоне).

/// Что за текст.
enum SyntaxKind: String, Codable, CaseIterable, Sendable {
    case json, jsonLines, sql, yaml, xml, code

    /// Какой переключатель настроек за него отвечает: логи из JSON-строк — тот же JSON.
    var setting: String { self == .jsonLines ? SyntaxKind.json.rawValue : rawValue }

    /// Меняет ли форматирование сам текст (а не только цвет).
    var reformats: Bool { self == .json || self == .sql || self == .xml }

    /// Язык highlight.js.
    var highlightLanguage: String? {
        switch self {
        case .sql: "sql"
        case .yaml: "yaml"
        case .xml: "xml"
        default: nil
        }
    }

    func label(code language: String?) -> String {
        switch self {
        case .json, .jsonLines: "JSON"
        case .sql: "SQL"
        case .yaml: "YAML"
        case .xml: "XML"
        case .code: SyntaxKind.languageNames[language ?? ""] ?? (language ?? "").capitalized
        }
    }

    static let languageNames = ["bash": "Shell", "shell": "Shell", "cpp": "C++", "csharp": "C#", "go": "Go",
                                "javascript": "JS", "typescript": "TS", "objectivec": "Obj-C", "python": "Python",
                                "php": "PHP", "css": "CSS", "scss": "SCSS", "ini": "INI", "graphql": "GraphQL",
                                "makefile": "Make", "markdown": "Markdown", "diff": "Diff", "rust": "Rust",
                                "swift": "Swift", "kotlin": "Kotlin", "java": "Java", "ruby": "Ruby", "lua": "Lua"]
}

/// Вид участка текста для цвета.
enum SyntaxToken: Sendable, Equatable {
    case key, string, number, literal, keyword, function, punctuation, comment, tag, attribute
}

/// Текст и его цветные участки (диапазоны в UTF-16, как у NSString).
struct Highlighted: Sendable, Equatable {
    struct Span: Sendable, Equatable {
        var location: Int
        var length: Int
        var token: SyntaxToken
    }

    var text: String
    var spans: [Span] = []
}

// MARK: - Какой формат

enum SyntaxDetector {
    /// Больше — как есть: форматирование и подсветка не должны тормозить.
    static let maxBytes = 1_000_000

    /// Формат текста среди разрешённых; код (`.code`) так не узнаётся — его угадывает highlight.js.
    static func detect(_ text: String, allowed: Set<SyntaxKind>) -> SyntaxKind? {
        guard text.utf8.count <= maxBytes else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let first = trimmed.first else { return nil }
        if allowed.contains(.json), first == "{" || first == "[" {
            if isJSON(trimmed) { return .json }
            if first == "{", isJSONLines(trimmed) { return .jsonLines }
        }
        if allowed.contains(.xml), first == "<", isXML(trimmed) { return .xml }
        if allowed.contains(.sql), isSQL(trimmed) { return .sql }
        if allowed.contains(.yaml), isYAML(trimmed) { return .yaml }
        return nil
    }

    static func isJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// Логи: каждая непустая строка — объект JSON, строк хотя бы две.
    static func isJSONLines(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        return lines.allSatisfy { $0.hasPrefix("{") && isJSON($0) }
    }

    static func isXML(_ text: String) -> Bool {
        let lower = text.prefix(64).lowercased()
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") {
            return (try? XMLDocument(xmlString: text, options: [.documentTidyHTML])) != nil
        }
        guard let document = try? XMLDocument(xmlString: text, options: []) else { return false }
        return document.rootElement() != nil
    }

    private static let sqlStart = try! NSRegularExpression(
        pattern: #"^(select|with|insert\s+into|update|delete\s+from|create\s+(or\s+replace\s+)?(table|index|view|unique|materialized)|alter\s+table|drop\s+(table|index|view)|explain|truncate)\b"#,
        options: [.caseInsensitive])

    /// Запрос, а не текст со словом «select»: начинается с команды SQL и у неё есть своя вторая часть.
    static func isSQL(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = sqlStart.firstMatch(in: text, range: range),
              let word = Range(match.range(at: 1), in: text).map({ text[$0].lowercased() }) else { return false }
        let has = { (pattern: String) in text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if word.hasPrefix("select") { return has(#"\bfrom\b"#) || has(#"^select\s+[\w'"(@:$-]"#) && !has(#"[.!?]\s*$"#) && text.count < 400 }
        if word.hasPrefix("with") { return has(#"\bas\s*\("#) }
        if word.hasPrefix("insert") { return has(#"\b(values|select)\b"#) }
        if word.hasPrefix("update") { return has(#"\bset\b"#) }
        return true
    }

    private static let yamlKey = try! NSRegularExpression(pattern: #"^\s*(- +)?[A-Za-z_][\w.\-/]*\s*:(\s|$)"#)
    private static let yamlItem = try! NSRegularExpression(pattern: #"^\s*- +\S"#)

    /// «ключ: значение» и «- элемент» почти в каждой строке, ключи — латиницей (русское «Повестка:» — не YAML).
    static func isYAML(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        guard lines.count >= 2 else { return false }
        let matches = { (regex: NSRegularExpression, line: String) in
            regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        let body = lines.first == "---" ? Array(lines.dropFirst()) : lines
        guard let first = body.first, matches(yamlKey, first) else { return false }
        let fitting = body.filter { matches(yamlKey, $0) || matches(yamlItem, $0) || $0 == "---" }.count
        return Double(fitting) / Double(body.count) >= 0.8
    }
}

// MARK: - JSON

/// JSON своими силами: быстро даже на мегабайте, ключи в исходном порядке (разбор в словарь его теряет).
enum JSONSyntax {
    private enum Kind { case string, number, literal, open, close, comma, colon }

    private struct Token {
        var kind: Kind
        var start: Int
        var end: Int
    }

    private static func tokens(_ u: [UInt16]) -> [Token] {
        var result: [Token] = []
        var i = 0
        let n = u.count
        while i < n {
            let c = u[i]
            switch c {
            case 0x20, 0x09, 0x0A, 0x0D:
                i += 1
            case 0x22: // "
                var j = i + 1
                while j < n, u[j] != 0x22 { j += u[j] == 0x5C ? 2 : 1 }
                j = min(j + 1, n)
                result.append(Token(kind: .string, start: i, end: j))
                i = j
            case 0x7B, 0x5B: result.append(Token(kind: .open, start: i, end: i + 1)); i += 1
            case 0x7D, 0x5D: result.append(Token(kind: .close, start: i, end: i + 1)); i += 1
            case 0x2C: result.append(Token(kind: .comma, start: i, end: i + 1)); i += 1
            case 0x3A: result.append(Token(kind: .colon, start: i, end: i + 1)); i += 1
            default:
                var j = i
                while j < n, ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x3A, 0x7B, 0x7D, 0x5B, 0x5D, 0x22].contains(u[j]) { j += 1 }
                if j == i { j += 1 }
                let isNumber = (0x30...0x39).contains(u[i]) || u[i] == 0x2D
                result.append(Token(kind: isNumber ? .number : .literal, start: i, end: j))
                i = j
            }
        }
        return result
    }

    private static func token(_ kind: Kind, isKey: Bool) -> SyntaxToken {
        switch kind {
        case .string: isKey ? .key : .string
        case .number: .number
        case .literal: .literal
        default: .punctuation
        }
    }

    /// Отступы по 2 пробела (`compact` — в одну строку, с пробелами после «,» и «:»).
    static func format(_ text: String, compact: Bool = false) -> Highlighted {
        let u = Array(text.utf16)
        let list = tokens(u)
        var out: [UInt16] = []
        out.reserveCapacity(u.count + u.count / 4)
        var spans: [Highlighted.Span] = []
        var depth = 0
        let space: UInt16 = 0x20, newline: UInt16 = 0x0A
        func newLine() {
            guard !compact else { return }
            out.append(newline)
            out.append(contentsOf: repeatElement(space, count: depth * 2))
        }
        func emit(_ t: Token, isKey: Bool) {
            let location = out.count
            out.append(contentsOf: u[t.start..<t.end])
            spans.append(.init(location: location, length: t.end - t.start, token: token(t.kind, isKey: isKey)))
        }
        for (index, t) in list.enumerated() {
            let next = index + 1 < list.count ? list[index + 1] : nil
            switch t.kind {
            case .open:
                emit(t, isKey: false)
                if next?.kind != .close { depth += 1; newLine() }
            case .close:
                if index > 0, list[index - 1].kind != .open { depth = max(0, depth - 1); newLine() }
                emit(t, isKey: false)
            case .comma:
                emit(t, isKey: false)
                if compact { out.append(space) } else { newLine() }
            case .colon:
                emit(t, isKey: false)
                out.append(space)
            case .string:
                emit(t, isKey: next?.kind == .colon)
            default:
                emit(t, isKey: false)
            }
        }
        return Highlighted(text: String(decoding: out, as: UTF16.self), spans: merged(spans))
    }

    /// Подсветка без изменения текста (логи из JSON-строк).
    static func highlight(_ text: String) -> Highlighted {
        let u = Array(text.utf16)
        let list = tokens(u)
        var spans: [Highlighted.Span] = []
        for (index, t) in list.enumerated() {
            let isKey = index + 1 < list.count && list[index + 1].kind == .colon
            spans.append(.init(location: t.start, length: t.end - t.start, token: token(t.kind, isKey: isKey)))
        }
        return Highlighted(text: text, spans: merged(spans))
    }

    static func merged(_ spans: [Highlighted.Span]) -> [Highlighted.Span] {
        var result: [Highlighted.Span] = []
        for span in spans where span.length > 0 {
            if var last = result.last, last.token == span.token, last.location + last.length == span.location {
                last.length += span.length
                result[result.count - 1] = last
            } else {
                result.append(span)
            }
        }
        return result
    }
}

// MARK: - XML

enum XMLSyntax {
    /// Отступы средствами macOS; не разобралось — nil.
    static func format(_ text: String) -> String? {
        let lower = text.prefix(64).lowercased()
        let html = lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html")
        guard let document = try? XMLDocument(xmlString: text, options: html ? [.documentTidyHTML] : []) else { return nil }
        let options: XMLNode.Options = [.nodePrettyPrint, .nodeCompactEmptyElement]
        let declaration = text.trimmingCharacters(in: .whitespaces).hasPrefix("<?xml")
        let result = declaration ? document.xmlString(options: options) : (document.rootElement()?.xmlString(options: options) ?? "")
        return result.isEmpty ? nil : result
    }
}

// MARK: - JavaScript: sql-formatter и highlight.js

/// sql-formatter и highlight.js в своём JavaScriptCore, на своей очереди: JSContext нельзя делить между потоками.
final class SyntaxEngine: @unchecked Sendable {
    static let shared = SyntaxEngine()
    /// Подсветка highlight.js на мегабайте JSON — секунды: больше этого — без цвета.
    static let maxHighlightBytes = 200_000

    let queue = DispatchQueue(label: "hatch.syntax", qos: .userInitiated)
    private var context: JSContext?

    private func loaded() -> JSContext? {
        if let context { return context }
        guard let context = JSContext() else { return nil }
        for name in ["sql-formatter.min", "highlight.min"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            context.evaluateScript(script)
        }
        context.exceptionHandler = { context, _ in context?.exception = nil }
        self.context = context
        return context
    }

    /// SQL с переносами по предложениям; ключевые слова — `keywordCase` ("upper", "lower", "preserve").
    func formatSQL(_ sql: String, keywordCase: String, dialect: String) -> String? {
        queue.sync {
            guard let context = loaded(), let formatter = context.objectForKeyedSubscript("sqlFormatter") else { return nil }
            let options: [String: Any] = ["language": dialect, "keywordCase": keywordCase,
                                          "functionCase": keywordCase, "dataTypeCase": keywordCase,
                                          "tabWidth": 2]
            context.exception = nil
            let result = formatter.invokeMethod("format", withArguments: [sql, options])
            guard context.exception == nil, let text = result?.toString(), result?.isString == true else { return nil }
            return text
        }
    }

    /// Подсветка текста как `language`; nil — язык не тот или текст великоват.
    func highlight(_ text: String, language: String) -> Highlighted? {
        guard text.utf8.count <= Self.maxHighlightBytes else { return nil }
        return queue.sync {
            guard let context = loaded(), let hljs = context.objectForKeyedSubscript("hljs") else { return nil }
            let result = hljs.invokeMethod("highlight", withArguments: [text, ["language": language, "ignoreIllegals": true]])
            guard let html = result?.objectForKeyedSubscript("value")?.toString() else { return nil }
            return Self.parse(html: html)
        }
    }

    /// Какой это язык программирования; nil — не похоже на код.
    func detectCode(_ text: String) -> String? {
        guard text.utf8.count <= Self.maxHighlightBytes else { return nil }
        return queue.sync {
            guard let context = loaded(), let hljs = context.objectForKeyedSubscript("hljs") else { return nil }
            let languages = ["bash", "go", "python", "javascript", "typescript", "swift", "kotlin", "java", "rust", "ruby",
                             "php", "cpp", "csharp", "css", "ini", "diff", "makefile", "lua", "graphql"]
            let result = hljs.invokeMethod("highlightAuto", withArguments: [text, languages])
            let relevance = result?.objectForKeyedSubscript("relevance")?.toInt32() ?? 0
            guard relevance >= 8, let language = result?.objectForKeyedSubscript("language")?.toString(),
                  language != "undefined" else { return nil }
            return language
        }
    }

    /// Разметка highlight.js (`<span class="hljs-…">`) — в текст и цветные участки.
    static func parse(html: String) -> Highlighted {
        var out: [UInt16] = []
        var spans: [Highlighted.Span] = []
        var stack: [SyntaxToken?] = []
        let u = Array(html.utf16)
        var i = 0
        let lt: UInt16 = 0x3C, amp: UInt16 = 0x26
        func current() -> SyntaxToken? { stack.last(where: { $0 != nil }) ?? nil }
        func append(_ units: [UInt16]) {
            if let token = current() { spans.append(.init(location: out.count, length: units.count, token: token)) }
            out.append(contentsOf: units)
        }
        while i < u.count {
            if u[i] == lt {
                var j = i
                while j < u.count, u[j] != 0x3E { j += 1 }
                let tag = String(decoding: u[i...min(j, u.count - 1)], as: UTF16.self)
                if tag.hasPrefix("</") {
                    _ = stack.popLast()
                } else if let range = tag.range(of: #"class="([^"]+)""#, options: .regularExpression) {
                    let classes = tag[range].dropFirst(7).dropLast()
                    stack.append(token(forClasses: String(classes)))
                } else {
                    stack.append(nil)
                }
                i = j + 1
            } else if u[i] == amp {
                var j = i
                while j < u.count, u[j] != 0x3B, j - i < 10 { j += 1 }
                let entity = String(decoding: u[i...min(j, u.count - 1)], as: UTF16.self)
                let decoded: String = switch entity {
                case "&lt;": "<"
                case "&gt;": ">"
                case "&amp;": "&"
                case "&quot;": "\""
                case "&#x27;", "&#39;": "'"
                default: entity
                }
                append(Array(decoded.utf16))
                i = j + 1
            } else {
                var j = i
                while j < u.count, u[j] != lt, u[j] != amp { j += 1 }
                append(Array(u[i..<j]))
                i = j
            }
        }
        return Highlighted(text: String(decoding: out, as: UTF16.self), spans: JSONSyntax.merged(spans))
    }

    private static func token(forClasses classes: String) -> SyntaxToken? {
        let names = classes.split(separator: " ").map { $0.replacingOccurrences(of: "hljs-", with: "") }
        for name in names {
            switch name {
            case "attr": return .key
            case "string", "regexp", "template-tag", "addition": return .string
            case "number": return .number
            case "literal", "deletion": return .literal
            case "keyword", "selector-tag", "doctag", "section": return .keyword
            case "built_in", "title", "title.function", "title.class", "type", "variable", "template-variable": return .function
            case "comment", "quote", "meta": return .comment
            case "punctuation", "bullet", "symbol", "operator": return .punctuation
            case "tag", "name", "selector-id", "selector-class": return .tag
            case "attribute", "property", "params": return .attribute
            default: continue
            }
        }
        return nil
    }
}

// MARK: - Цвета

enum SyntaxPalette {
    /// Цвет участка: тёмная и светлая тема Hatch.
    static func color(_ token: SyntaxToken) -> NSColor {
        let (dark, light) = rgb(token)
        return NSColor(name: nil) { appearance in
            let pair = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(pair.0) / 255, green: CGFloat(pair.1) / 255, blue: CGFloat(pair.2) / 255, alpha: 1)
        }
    }

    typealias RGB = (Int, Int, Int)

    static func rgb(_ token: SyntaxToken) -> (dark: RGB, light: RGB) {
        switch token {
        case .key, .function, .attribute: ((0x7C, 0xC4, 0xFF), (0x1F, 0x6F, 0xC5))
        case .string: ((0x8F, 0xE3, 0xA6), (0x1E, 0x7F, 0x3C))
        case .number: ((0xF5, 0xB9, 0x71), (0xB0, 0x5A, 0x00))
        case .literal: ((0xFF, 0x8F, 0x8F), (0xC4, 0x2B, 0x2B))
        case .keyword, .tag: ((0xD0, 0xA2, 0xFF), (0x89, 0x44, 0xAB))
        case .punctuation: ((0x8E, 0x8E, 0x93), (0x6E, 0x6E, 0x73))
        case .comment: ((0x6F, 0x6F, 0x75), (0x8E, 0x8E, 0x93))
        }
    }
}

enum SyntaxRender {
    static func attributed(_ h: Highlighted, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: h.text, attributes: [.font: font, .foregroundColor: color])
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let length = result.length
        for span in h.spans where span.location + span.length <= length {
            let range = NSRange(location: span.location, length: span.length)
            result.addAttribute(.foregroundColor, value: SyntaxPalette.color(span.token), range: range)
            if span.token == .keyword { result.addAttribute(.font, value: bold, range: range) }
        }
        return result
    }

    /// Для строк SwiftUI (`Text`): только цвета, шрифт задаёт сам вид.
    static func swiftUI(_ h: Highlighted) -> AttributedString {
        let source = NSMutableAttributedString(string: h.text)
        for span in h.spans where span.location + span.length <= source.length {
            source.addAttribute(.foregroundColor, value: SyntaxPalette.color(span.token),
                                range: NSRange(location: span.location, length: span.length))
        }
        return (try? AttributedString(source, including: \.appKit)) ?? AttributedString(h.text)
    }

    /// Для вывода команд — цветами ANSI (24 бита): дальше его рисует то же, что и цветной вывод программ.
    static func ansi(_ h: Highlighted) -> String {
        let text = h.text as NSString
        var result = ""
        var cursor = 0
        for span in h.spans where span.location >= cursor && span.location + span.length <= text.length {
            result += text.substring(with: NSRange(location: cursor, length: span.location - cursor))
            let (r, g, b) = SyntaxPalette.rgb(span.token).dark
            let bold = span.token == .keyword ? "1;" : ""
            // каждую строку — отдельно: превью вывода разбирает цвета построчно
            let piece = text.substring(with: NSRange(location: span.location, length: span.length))
            result += piece.components(separatedBy: "\n")
                .map { $0.isEmpty ? "" : "\u{1B}[\(bold)38;2;\(r);\(g);\(b)m" + $0 + "\u{1B}[0m" }
                .joined(separator: "\n")
            cursor = span.location + span.length
        }
        result += text.substring(from: cursor)
        return result
    }
}
