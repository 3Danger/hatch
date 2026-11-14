import Foundation

/// Свой формат SQL (бета, включается в настройках): предложения с начала строки, столбцы с запятой
/// в начале, условия — `WHERE TRUE` и `  AND …`, длинные OR в скобках — `(FALSE` и `OR …`.
///
/// Запрос по смыслу не меняется никогда: результат разбирается заново и сверяется с исходным
/// слово в слово (без учёта пробелов, переносов и регистра ключевых слов, за вычетом добавленных
/// `TRUE`/`FALSE` и ведущих `AND`/`OR`). Не сошлось или конструкция незнакомая — nil, и тогда
/// показывается обычный формат (sql-formatter).
enum HatchPG {
    /// - Parameters:
    ///   - keywordCase: "upper", "lower", "preserve";
    ///   - dialect: "sql", "postgresql", "mysql", "clickhouse".
    static func format(_ sql: String, keywordCase: String = "upper", dialect: String = "sql") -> String? {
        let options = Options(keywordCase: keywordCase, dialect: dialect)
        var lexer = Lexer(sql, options: options)
        guard let tokens = lexer.run(), !tokens.isEmpty,
              let statements = Parser.statements(tokens) else { return nil }
        var formatter = Formatter(options: options)
        // скрипт: запросы форматируются, остальное (BEGIN, TRUNCATE, VACUUM, команды psql) — как написано
        var formattedAny = false
        do {
            for (index, statement) in statements.enumerated() {
                if index > 0 {
                    // между запросами — пустая строка, как всегда; вокруг команд psql и прочих инструкций —
                    // как во входе: «\if … \else … \endif» строка за строкой не разъезжаются
                    let blank = Formatter.isQuery(statements[index - 1].nodes) && Formatter.isQuery(statement.nodes)
                        || Formatter.flatten(statement.nodes).first?.blankBefore == true
                    if blank { formatter.out.blankLine() } else { formatter.out.newline(0) }
                }
                if Formatter.isQuery(statement.nodes) {
                    // не справились с одним запросом скрипта — он как написан, остальные форматируются
                    let saved = formatter.out
                    do {
                        try formatter.statement(statement.nodes)
                        formattedAny = true
                    } catch {
                        formatter.out = saved
                        formatter.verbatim(statement.nodes)
                    }
                } else {
                    formatter.verbatim(statement.nodes)
                }
                formatter.out.continuation = 0
                if let semicolon = statement.semicolon { formatter.out.token(semicolon, space: false) }
            }
        } catch {
            return nil
        }
        // ни одного запроса — форматировать нечего, пусть пробует обычный форматтер
        guard formattedAny else { return nil }
        let result = formatter.out.text
        guard verify(original: tokens, emitted: formatter.out.tokens, dropped: formatter.out.dropped, output: result,
                     options: options) else { return nil }
        return result
    }

    /// Сверка: вывод разбирается так же, как мы его писали, и это те же слова, что во входе.
    /// `dropped` — слова, которые форматтер убрал намеренно и без смены смысла (`1` в `EXISTS (SELECT 1 …)`):
    /// во входе они пропускаются по порядку, остальное — слово в слово.
    static func verify(original: [Token], emitted: [Token], dropped: [Token] = [], output: String, options: Options) -> Bool {
        var lexer = Lexer(output, options: options)
        guard let relexed = lexer.run() else { return false }
        guard relexed.map(\.text) == emitted.map({ $0.rendered(options) }) else { return false }
        let kept = emitted.filter { !$0.synthetic }
        guard kept.count + dropped.count == original.count else { return false }
        func same(_ a: Token, _ b: Token) -> Bool {
            guard a.kind == b.kind else { return false }
            return a.text == b.text || (a.isCaseable(options) && a.text.uppercased() == b.text.uppercased())
        }
        var k = 0, d = 0
        for token in original {
            if k < kept.count, same(kept[k], token) {
                k += 1
            } else if d < dropped.count, dropped[d].kind == token.kind, dropped[d].text == token.text {
                d += 1
            } else {
                return false
            }
        }
        return k == kept.count && d == dropped.count
    }

    // MARK: - Слова

    struct Options {
        var keywordCase: String
        var dialect: String
        /// Обратная косая черта экранирует кавычку в строке (MySQL, ClickHouse).
        var backslashEscapes: Bool { dialect == "mysql" || dialect == "clickhouse" }
        /// `SELECT FROM t` без столбцов — PostgreSQL (HatchPG — для него); в MySQL и ClickHouse это ошибка.
        var allowsEmptySelect: Bool { dialect != "mysql" && dialect != "clickhouse" }
        /// В ClickHouse имена функций чувствительны к регистру, а в JOIN … ON нужны равенства.
        var isClickHouse: Bool { dialect == "clickhouse" }
    }

    struct Token: Equatable {
        enum Kind: Equatable {
            case word, quoted, string, number, lineComment, blockComment, op, comma, open, close, semicolon, dot
            /// Команда psql (`\set ON_ERROR_STOP on`, `\timing`): своя строка, до конца строки, как есть.
            case meta
        }
        var kind: Kind
        var text: String
        /// Перед словом во входе был пробел или перенос.
        var spaceBefore = false
        /// …и это был перенос (комментарий на своей строке так и остаётся).
        var newlineBefore = false
        /// Отступ строки во входе, если слово первое на строке (запрос, который не форматируем, — как был).
        var indent = 0
        /// Перед словом во входе — пустая строка (между инструкциями скрипта она сохраняется, лишняя не появляется).
        var blankBefore = false
        /// Сразу за словом — `(`: вызов функции.
        var isCall = false
        /// Добавлено форматтером: TRUE, FALSE, ведущие AND и OR.
        var synthetic = false

        var upper: String { text.uppercased() }
        var isComment: Bool { kind == .lineComment || kind == .blockComment }

        func isWord(_ word: String) -> Bool { kind == .word && upper == word }

        /// Регистр этого слова можно менять: ключевое слово или известная функция (кроме ClickHouse).
        func isCaseable(_ options: Options) -> Bool {
            guard kind == .word else { return false }
            if HatchPG.keywords.contains(upper) { return true }
            return isCall && !options.isClickHouse && HatchPG.functions.contains(upper)
        }

        func rendered(_ options: Options) -> String {
            // добавленные TRUE/AND — заглавными и при «не менять» (исходного написания у них нет)
            if synthetic { return options.keywordCase == "lower" ? text.lowercased() : text.uppercased() }
            guard options.keywordCase != "preserve", isCaseable(options) else { return text }
            return options.keywordCase == "lower" ? text.lowercased() : text.uppercased()
        }

        static func synthetic(_ word: String) -> Token { Token(kind: .word, text: word, synthetic: true) }
    }

    static let keywords: Set<String> = [
        "SELECT", "DISTINCT", "ALL", "FROM", "WHERE", "PREWHERE", "AND", "OR", "NOT", "IN", "IS", "NULL", "TRUE", "FALSE",
        "AS", "ON", "USING", "JOIN", "LEFT", "RIGHT", "FULL", "INNER", "OUTER", "CROSS", "NATURAL", "LATERAL", "SEMI",
        "ANTI", "ANY", "ASOF", "GLOBAL", "ARRAY", "GROUP", "BY", "ORDER", "HAVING", "QUALIFY", "LIMIT", "OFFSET", "FETCH",
        "FIRST", "NEXT", "ROW", "ROWS", "ONLY", "TIES", "UNION", "INTERSECT", "EXCEPT", "WITH", "RECURSIVE", "MATERIALIZED",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "RETURNING", "CONFLICT", "DO", "NOTHING", "DEFAULT",
        "CASE", "WHEN", "THEN", "ELSE", "END", "BETWEEN", "SYMMETRIC", "LIKE", "ILIKE", "SIMILAR", "TO", "ESCAPE",
        "EXISTS", "ASC", "DESC", "NULLS", "LAST", "INTERVAL", "OVER", "PARTITION", "RANGE", "GROUPS", "PRECEDING",
        "FOLLOWING", "CURRENT", "UNBOUNDED", "WINDOW", "FILTER", "WITHIN", "SOME", "FOR", "SHARE", "NOWAIT", "SKIP",
        "LOCKED", "KEY", "SETTINGS", "FORMAT", "COLLATE", "AT", "TIME", "ZONE", "CAST", "EXTRACT", "TRIM", "LEADING",
        "TRAILING", "BOTH", "OVERLAPS", "UNKNOWN", "ISNULL", "NOTNULL", "STRAIGHT_JOIN",
        // заголовки инструкций с запросом: CREATE [TEMP] TABLE … AS, EXPLAIN [ANALYZE]
        "CREATE", "TEMP", "TEMPORARY", "UNLOGGED", "TABLE", "VIEW", "EXPLAIN", "ANALYZE",
    ]

    static let functions: Set<String> = [
        "SUM", "COUNT", "AVG", "MIN", "MAX", "NOW", "COALESCE", "NULLIF", "GREATEST", "LEAST", "LOWER", "UPPER",
        "LENGTH", "SUBSTRING", "SUBSTR", "REPLACE", "CONCAT", "ROUND", "FLOOR", "CEIL", "ABS", "DATE_TRUNC",
        "DATE_PART", "TO_CHAR", "TO_DATE", "TO_TIMESTAMP", "ROW_NUMBER", "RANK", "DENSE_RANK", "LAG", "LEAD",
        "FIRST_VALUE", "LAST_VALUE", "STRING_AGG", "ARRAY_AGG", "JSON_AGG", "JSONB_AGG", "BOOL_AND", "BOOL_OR",
        "CURRENT_DATE", "CURRENT_TIMESTAMP", "DATE", "IFNULL", "NVL", "IF",
    ]

    // MARK: - Разбор на слова

    struct Lexer {
        let chars: [Character]
        let options: Options
        var i = 0

        init(_ text: String, options: Options) {
            chars = Array(text)
            self.options = options
        }

        mutating func run() -> [Token]? {
            var tokens: [Token] = []
            var space = false, newline = false, indent = 0, newlines = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace {
                    space = true
                    if c.isNewline { newline = true; indent = 0; newlines += 1 } else { indent += 1 }
                    i += 1
                    continue
                }
                // команда psql — только в начале строки: «\» внутри запроса — ошибка разбора, как раньше
                let lineStart = tokens.isEmpty || newline
                guard var token = c == "\\" && lineStart ? Token(kind: .meta, text: take(while: { !$0.isNewline }))
                                                           : next() else { return nil }
                token.spaceBefore = space
                token.newlineBefore = newline
                token.indent = newline ? indent : 0
                token.blankBefore = newlines >= 2
                // E'…' (PostgreSQL), N'…', X'…', B'…': префикс и строка — одно слово
                if token.kind == .string, !space, let last = tokens.last, last.kind == .word,
                   ["E", "N", "X", "B", "U&"].contains(last.upper) {
                    token.text = last.text + token.text
                    token.spaceBefore = last.spaceBefore
                    token.newlineBefore = last.newlineBefore
                    tokens.removeLast()
                }
                if token.kind == .open, !space, let index = tokens.indices.last, tokens[index].kind == .word {
                    tokens[index].isCall = true
                }
                tokens.append(token)
                space = false
                newline = false
                newlines = 0
            }
            return tokens
        }

        private func at(_ offset: Int) -> Character? { i + offset < chars.count ? chars[i + offset] : nil }

        private mutating func take(while condition: (Character) -> Bool) -> String {
            let start = i
            while i < chars.count, condition(chars[i]) { i += 1 }
            return String(chars[start..<i])
        }

        private mutating func next() -> Token? {
            let c = chars[i]
            if c == "-", at(1) == "-" {
                return Token(kind: .lineComment, text: take(while: { !$0.isNewline }))
            }
            if c == "/", at(1) == "*" { return blockComment() }
            if c == "'" { return quoted("'", kind: .string, backslash: options.backslashEscapes || isEscapeString) }
            if c == "\"" { return quoted("\"", kind: .quoted, backslash: false) }
            if c == "`" { return quoted("`", kind: .quoted, backslash: false) }
            if c == "$", let dollar = dollarQuoted() { return dollar }
            if c.isNumber || (c == "." && at(1)?.isNumber == true) { return number() }
            if c.isLetter || c == "_" { return Token(kind: .word, text: take(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" })) }
            // переменные psql: :'name' (строкой), :"name" (именем) — одно слово, как :name
            if c == ":", at(1) == "'" || at(1) == "\"", let quote = at(1) {
                let start = i
                i += 2
                while i < chars.count, chars[i] != quote, !chars[i].isNewline { i += 1 }
                guard i < chars.count, chars[i] == quote else { return nil }
                i += 1
                return Token(kind: .word, text: String(chars[start..<i]))
            }
            // параметры: $1, :name, @var, ?
            let nameStart = at(1).map { $0.isLetter || $0 == "_" } == true
            if (c == "$" && at(1)?.isNumber == true) || (c == "@" && (nameStart || at(1) == "@")) || (c == ":" && nameStart) {
                i += 1
                return Token(kind: .word, text: String(c) + take(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
            }
            switch c {
            case "(": i += 1; return Token(kind: .open, text: "(")
            case ")": i += 1; return Token(kind: .close, text: ")")
            case ",": i += 1; return Token(kind: .comma, text: ",")
            case ";": i += 1; return Token(kind: .semicolon, text: ";")
            case ".": i += 1; return Token(kind: .dot, text: ".")
            default: break
            }
            for op in ["<=>", "->>", "#>>", "!~*", "::", "<=", ">=", "<>", "!=", "||", "->", "#>", "@>", "<@", "&&",
                       "=>", ":=", "~*", "!~", "<<", ">>", "**"] where matches(op) {
                i += op.count
                return Token(kind: .op, text: op)
            }
            i += 1
            return Token(kind: .op, text: String(c))
        }

        /// Строка E'…' — с обратной косой чертой (префикс уже прочитан словом перед ней).
        private var isEscapeString: Bool {
            guard i > 0, chars[i - 1] == "E" || chars[i - 1] == "e" else { return false }
            return i == 1 || !(chars[i - 2].isLetter || chars[i - 2].isNumber || chars[i - 2] == "_")
        }

        private func matches(_ op: String) -> Bool {
            let opChars = Array(op)
            guard i + opChars.count <= chars.count else { return false }
            return Array(chars[i..<i + opChars.count]) == opChars
        }

        private mutating func quoted(_ quote: Character, kind: Token.Kind, backslash: Bool) -> Token? {
            let start = i
            i += 1
            while i < chars.count {
                if backslash, chars[i] == "\\" { i += 2; continue }
                if chars[i] == quote {
                    if at(1) == quote { i += 2; continue } // '' внутри строки
                    i += 1
                    return Token(kind: kind, text: String(chars[start..<i]))
                }
                i += 1
            }
            return nil // строка не закрыта
        }

        private mutating func blockComment() -> Token? {
            let start = i
            var depth = 0
            while i < chars.count {
                if chars[i] == "/", at(1) == "*" { depth += 1; i += 2; continue }
                if chars[i] == "*", at(1) == "/" {
                    depth -= 1
                    i += 2
                    if depth == 0 { return Token(kind: .blockComment, text: String(chars[start..<i])) }
                    continue
                }
                i += 1
            }
            return nil
        }

        /// $$…$$ и $tag$…$tag$ (PostgreSQL).
        private mutating func dollarQuoted() -> Token? {
            var j = i + 1
            while j < chars.count, chars[j].isLetter || chars[j] == "_" || (j > i + 1 && chars[j].isNumber) { j += 1 }
            guard j < chars.count, chars[j] == "$" else { return nil }
            let tag = Array(chars[i...j])
            var k = j + 1
            while k + tag.count <= chars.count {
                if Array(chars[k..<k + tag.count]) == tag {
                    let token = Token(kind: .string, text: String(chars[i..<k + tag.count]))
                    i = k + tag.count
                    return token
                }
                k += 1
            }
            return nil
        }

        private mutating func number() -> Token {
            if chars[i] == "0", at(1) == "x" || at(1) == "X" {
                i += 2
                return Token(kind: .number, text: "0x" + take(while: { $0.isHexDigit }))
            }
            var text = take(while: { $0.isNumber || $0 == "_" })
            if i < chars.count, chars[i] == ".", at(1)?.isNumber ?? true {
                i += 1
                text += "." + take(while: { $0.isNumber || $0 == "_" })
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E",
               at(1)?.isNumber == true || ((at(1) == "+" || at(1) == "-") && at(2)?.isNumber == true) {
                text += String(chars[i])
                i += 1
                if chars[i] == "+" || chars[i] == "-" { text += String(chars[i]); i += 1 }
                text += take(while: { $0.isNumber })
            }
            return Token(kind: .number, text: text)
        }
    }

    // MARK: - Скобки

    indirect enum Node {
        case token(Token)
        case group(open: Token, items: [Node], close: Token)

        var token: Token? { if case .token(let token) = self { return token }; return nil }

        func isWord(_ word: String) -> Bool { token?.isWord(word) ?? false }

        var isComment: Bool { token?.isComment ?? false }

        /// Подзапрос: в скобках SELECT или WITH.
        var isSubquery: Bool {
            guard case .group(_, let items, _) = self else { return false }
            guard let first = items.first(where: { !$0.isComment }) else { return false }
            return first.isWord("SELECT") || first.isWord("WITH")
        }
    }

    struct Statement {
        var nodes: [Node]
        var semicolon: Token?
    }

    enum Parser {
        static func statements(_ tokens: [Token]) -> [Statement]? {
            var stack: [(open: Token?, items: [Node])] = [(nil, [])]
            var result: [Statement] = []
            for token in tokens {
                switch token.kind {
                case .open:
                    stack.append((token, []))
                case .close:
                    guard stack.count > 1, let open = stack.last?.open else { return nil }
                    let items = stack.removeLast().items
                    stack[stack.count - 1].items.append(.group(open: open, items: items, close: token))
                case .meta:
                    // команда psql — отдельной «инструкцией» вместе с комментариями над ней
                    guard stack.count == 1 else { return nil }
                    if stack[0].items.contains(where: { !$0.isComment }) {
                        result.append(Statement(nodes: stack[0].items, semicolon: nil))
                        stack[0].items = []
                    }
                    result.append(Statement(nodes: stack[0].items + [.token(token)], semicolon: nil))
                    stack[0].items = []
                case .semicolon where stack.count == 1:
                    guard stack[0].items.contains(where: { !$0.isComment }) else { return nil }
                    result.append(Statement(nodes: stack[0].items, semicolon: token))
                    stack[0].items = []
                default:
                    stack[stack.count - 1].items.append(.token(token))
                }
            }
            guard stack.count == 1 else { return nil } // скобка не закрыта
            if !stack[0].items.isEmpty {
                guard stack[0].items.contains(where: { !$0.isComment }) else { return nil }
                result.append(Statement(nodes: stack[0].items, semicolon: nil))
            }
            return result
        }
    }

    // MARK: - Запись

    struct Output {
        var text = ""
        var tokens: [Token] = []
        /// Убранные намеренно (константа в `EXISTS (SELECT 1 …)`) — для сверки со входом.
        var dropped: [Token] = []
        let options: Options
        /// Колонка, с которой продолжать строку после однострочного комментария посреди выражения.
        var continuation = 0
        private(set) var column = 0
        private var afterLineComment = false
        private(set) var lineEmpty = true

        init(options: Options) { self.options = options }

        mutating func newline(_ indent: Int, blank: Bool = false) {
            guard !text.isEmpty else { return }
            text += (blank ? "\n\n" : "\n") + String(repeating: " ", count: indent)
            column = indent
            afterLineComment = false
            lineEmpty = true
        }

        mutating func blankLine() {
            text += "\n"
            newline(0)
        }

        /// Слово: пробел перед ним — если `space` и строка не пуста. После «-- …» — сначала перенос.
        mutating func token(_ token: Token, space: Bool) {
            if afterLineComment || (token.isComment && token.newlineBefore && !lineEmpty) {
                newline(continuation)
            } else if space, !lineEmpty {
                append(" ")
            }
            append(token.rendered(options))
            tokens.append(token)
            lineEmpty = false
            afterLineComment = token.kind == .lineComment
        }

        private mutating func append(_ string: String) {
            text += string
            column += string.count
        }
    }

    enum Failure: Error { case unsupported }

    struct Formatter {
        var out: Output
        let options: Options

        init(options: Options) {
            self.options = options
            out = Output(options: options)
        }

        static let queryWords = ["SELECT", "WITH", "INSERT", "UPDATE", "DELETE"]

        /// Запрос, который форматируем: SELECT, WITH, INSERT, UPDATE, DELETE — или он же
        /// за заголовком `CREATE [TEMP] TABLE|VIEW … AS` и `EXPLAIN [ANALYZE]`.
        static func isQuery(_ nodes: [Node]) -> Bool {
            guard let first = nodes.first(where: { !$0.isComment }) else { return false }
            return queryWords.contains(where: { first.isWord($0) }) || headerEnd(nodes) != nil
        }

        /// Где начинается запрос после заголовка: `CREATE … AS SELECT` — после AS, `EXPLAIN … SELECT` — на SELECT.
        static func headerEnd(_ nodes: [Node]) -> Int? {
            guard let start = nodes.firstIndex(where: { !$0.isComment }) else { return nil }
            let isQueryWord = { (node: Node) in queryWords.contains(where: { node.isWord($0) }) }
            if nodes[start].isWord("CREATE") {
                guard let asIndex = nodes[start...].firstIndex(where: { $0.isWord("AS") }), asIndex + 1 < nodes.count,
                      nodes[asIndex + 1].isWord("SELECT") || nodes[asIndex + 1].isWord("WITH") else { return nil }
                return asIndex + 1
            }
            if nodes[start].isWord("EXPLAIN") {
                return nodes[(start + 1)...].firstIndex(where: isQueryWord)
            }
            return nil
        }

        /// Запрос верхнего уровня; заголовок (`CREATE TEMP TABLE x AS`) — своей строкой над ним, запрос — на 2 глубже.
        mutating func statement(_ nodes: [Node]) throws {
            guard Self.isQuery(nodes) else { throw Failure.unsupported }
            guard let queryStart = Self.headerEnd(nodes), let start = nodes.firstIndex(where: { !$0.isComment }) else {
                try query(nodes, indent: 0)
                return
            }
            for comment in nodes[..<start] {
                out.continuation = 0
                emit(comment, space: true)
                out.newline(0)
            }
            for (offset, node) in nodes[start..<queryStart].enumerated() {
                // комментарий внутри заголовка — не разбираем
                guard !node.isComment else { throw Failure.unsupported }
                emit(node, space: offset > 0)
            }
            // CREATE … AS — новый уровень: запрос под заголовком на 2 глубже; EXPLAIN — тот же запрос, на месте
            let level = nodes[start].isWord("CREATE") ? 2 : 0
            out.newline(level)
            try query(Array(nodes[queryStart...]), indent: level)
        }

        /// Инструкция, которую не форматируем (BEGIN, DROP, VACUUM, команда psql): слова, переносы и отступы
        /// строк — как во входе; регистр ключевых слов — по настройке.
        mutating func verbatim(_ nodes: [Node]) {
            for token in Self.flatten(nodes) {
                if token.newlineBefore, !out.lineEmpty {
                    out.newline(token.indent, blank: token.blankBefore)
                    out.token(token, space: false)
                } else {
                    out.token(token, space: token.spaceBefore)
                }
            }
        }

        static func flatten(_ nodes: [Node]) -> [Token] {
            nodes.flatMap { node -> [Token] in
                switch node {
                case .token(let token): return [token]
                case .group(let open, let items, let close): return [open] + flatten(items) + [close]
                }
            }
        }

        // MARK: Предложения

        enum Clause { case with, select, from, join, conditions, list, inline, setOperation, values, set }

        /// Где начинается предложение и сколько в его ключевых словах элементов.
        func clause(at i: Int, in items: [Node], current: Clause?) -> (count: Int, kind: Clause)? {
            guard let token = items[i].token, token.kind == .word else { return nil }
            // в начале запроса (до него — только комментарии)
            let isStart = items[..<i].allSatisfy(\.isComment)
            func word(_ offset: Int) -> String? {
                guard i + offset < items.count, let token = items[i + offset].token, token.kind == .word else { return nil }
                return token.upper
            }
            switch token.upper {
            case "WITH": return isStart ? (1, .with) : nil
            case "SELECT": return (1, .select)
            case "FROM":
                // a IS [NOT] DISTINCT FROM b — не предложение
                if i >= 1, items[i - 1].isWord("DISTINCT") { return nil }
                return (1, .from)
            case "WHERE", "PREWHERE", "HAVING", "QUALIFY": return (1, .conditions)
            case "GROUP", "ORDER": return word(1) == "BY" ? (2, .list) : nil
            case "LIMIT", "OFFSET", "FETCH", "WINDOW", "SETTINGS", "FORMAT": return (1, .inline)
            case "FOR": return ["UPDATE", "SHARE", "NO", "KEY"].contains(word(1) ?? "") ? (1, .inline) : nil
            case "UNION", "INTERSECT", "EXCEPT":
                return ["ALL", "DISTINCT"].contains(word(1) ?? "") ? (2, .setOperation) : (1, .setOperation)
            case "INSERT": return word(1) == "INTO" ? (2, .inline) : (1, .inline)
            case "VALUES": return (1, .values)
            case "UPDATE": return isStart ? (1, .inline) : nil
            case "DELETE": return isStart ? (word(1) == "FROM" ? (2, .inline) : (1, .inline)) : nil
            case "SET": return current == .inline || current == nil || current == .set ? (1, .set) : nil
            case "RETURNING": return (1, .list)
            case "ON": return word(1) == "CONFLICT" ? (2, .inline) : nil
            case "STRAIGHT_JOIN": return (1, .join)
            default:
                // [LEFT|RIGHT|FULL|INNER|CROSS|NATURAL|OUTER|SEMI|ANTI|ANY|ALL|ASOF|GLOBAL|ARRAY|PASTE]* JOIN
                var offset = 0
                while let next = word(offset), Self.joinModifiers.contains(next) { offset += 1 }
                if word(offset) == "JOIN" { return (offset + 1, .join) }
                return nil
            }
        }

        static let joinModifiers: Set<String> = ["LEFT", "RIGHT", "FULL", "INNER", "CROSS", "NATURAL", "OUTER", "SEMI",
                                                 "ANTI", "ANY", "ALL", "ASOF", "GLOBAL", "ARRAY", "PASTE"]

        /// Запрос одного уровня (весь или в скобках): по предложению с начала строки `indent`.
        mutating func query(_ items: [Node], indent: Int) throws {
            var clauses: [(kind: Clause, keyword: [Node], body: [Node])] = []
            var leading: [Node] = []
            var i = 0
            while i < items.count {
                if let found = clause(at: i, in: items, current: clauses.last?.kind) {
                    clauses.append((found.kind, Array(items[i..<i + found.count]), []))
                    i += found.count
                    continue
                }
                if clauses.isEmpty {
                    // до первого предложения — только комментарии
                    guard items[i].isComment else { throw Failure.unsupported }
                    leading.append(items[i])
                } else {
                    clauses[clauses.count - 1].body.append(items[i])
                }
                i += 1
            }
            guard let first = clauses.first, first.kind == .with || first.kind == .select
                    || first.keyword.contains(where: { $0.isWord("INSERT") || $0.isWord("UPDATE") || $0.isWord("DELETE") })
            else { throw Failure.unsupported }

            for comment in leading {
                out.continuation = indent
                emit(comment, space: true)
                out.newline(indent)
            }
            // комментарий на своей строке перед предложением (в конце тела предыдущего) — так и остаётся:
            // своей строкой перед ним, с его отступом
            var before: [[Node]] = Array(repeating: [], count: clauses.count)
            for index in clauses.indices.dropFirst() {
                while let last = clauses[index - 1].body.last, last.isComment, last.token?.newlineBefore == true {
                    before[index].insert(clauses[index - 1].body.removeLast(), at: 0)
                }
            }
            for (index, clause) in clauses.enumerated() {
                // `SELECT FROM t` (EXISTS): FROM — на строке SELECT без столбцов
                let afterEmptySelect = index > 0 && clauses[index - 1].kind == .select
                    && clauses[index - 1].body.isEmpty && clause.kind == .from && before[index].isEmpty
                if index > 0, !afterEmptySelect { out.newline(indent) }
                for comment in before[index] {
                    out.continuation = indent
                    emit(comment, space: false)
                    out.newline(indent)
                }
                out.continuation = indent + 2
                for (k, word) in clause.keyword.enumerated() { emit(word, space: k > 0 || afterEmptySelect) }
                let keywordLength = clause.keyword.compactMap(\.token).map(\.text.count).reduce(0, +) + clause.keyword.count - 1
                switch clause.kind {
                case .with: try with(clause.body, indent: indent)
                case .select:
                    if clause.body.isEmpty {
                        guard options.allowsEmptySelect else { throw Failure.unsupported }
                    } else {
                        try select(clause.body, indent: indent)
                    }
                case .from: try list(clause.body, indent: indent, commaColumn: indent + 3, block: indent)
                case .join: try join(clause.body, indent: indent)
                case .conditions: try conditions(clause.body, indent: indent, anchor: true)
                case .list: try shortList(clause.body, indent: indent, keywordLength: keywordLength)
                case .values: try list(clause.body, indent: indent, commaColumn: indent + 5, block: indent)
                case .set: try list(clause.body, indent: indent, commaColumn: indent + 2, block: indent)
                case .setOperation:
                    guard clause.body.allSatisfy(\.isComment) else { throw Failure.unsupported }
                    try inline(clause.body, block: indent)
                case .inline: try inline(clause.body, block: indent, leadingSpace: true)
                }
            }
        }

        // MARK: WITH

        /// `WITH a AS (` … `)`, следующие — `), b AS (`: запятая сразу за скобкой предыдущего.
        mutating func with(_ body: [Node], indent: Int) throws {
            var items = body
            if let first = items.first, first.isWord("RECURSIVE") {
                emit(first, space: true)
                items.removeFirst()
            }
            let definitions = split(items, by: { $0.token?.kind == .comma })
            guard !definitions.terms.isEmpty else { throw Failure.unsupported }
            for (index, definition) in definitions.terms.enumerated() {
                if index > 0 {
                    // после «-- …» за скобкой запятая переносится — на уровень WITH
                    out.continuation = indent
                    emit(definitions.separators[index - 1], space: false)
                }
                guard let last = definition.lastIndex(where: { !$0.isComment }),
                      case .group(let open, let inner, let close) = definition[last], definition[last].isSubquery,
                      definition[..<last].contains(where: { $0.isWord("AS") }) else { throw Failure.unsupported }
                try inline(Array(definition[..<last]), block: indent, leadingSpace: true)
                emit(.token(open), space: true)
                out.newline(indent + 2)
                try query(inner, indent: indent + 2)
                out.newline(indent)
                emit(.token(close), space: false)
                try inline(Array(definition[(last + 1)...]), block: indent, leadingSpace: true)
            }
        }

        // MARK: SELECT

        mutating func select(_ body: [Node], indent: Int) throws {
            var items = body
            // DISTINCT, ALL, DISTINCT ON (…) — на строке SELECT
            if let first = items.first, first.isWord("DISTINCT") || first.isWord("ALL") {
                emit(first, space: true)
                items.removeFirst()
                if items.count > 1, items[0].isWord("ON"), case .group = items[1] {
                    emit(items[0], space: true)
                    try inline([items[1]], block: indent, leadingSpace: true)
                    items.removeFirst(2)
                }
            }
            let columns = split(items, by: { $0.token?.kind == .comma })
            for (index, column) in columns.terms.enumerated() {
                if index > 0 {
                    out.newline(indent + 5)
                    emit(columns.separators[index - 1], space: false)
                }
                out.continuation = indent + 7
                if let caseIndex = column.firstIndex(where: { !$0.isComment }), column[caseIndex].isWord("CASE") {
                    try inline(Array(column[..<caseIndex]), block: indent + 5, leadingSpace: true)
                    try caseExpression(Array(column[caseIndex...]), endColumn: indent + 5, block: indent + 5)
                } else {
                    try inline(column, block: indent + 5, leadingSpace: true)
                }
            }
        }

        /// CASE по строкам: `CASE WHEN …` на месте, THEN, следующие WHEN и ELSE — под CASE, END — под запятой.
        mutating func caseExpression(_ items: [Node], endColumn: Int, block: Int) throws {
            // где кончается этот CASE (вложенные CASE — внутри)
            var depth = 0
            var endIndex: Int?
            for (index, item) in items.enumerated() {
                if item.isWord("CASE") { depth += 1 }
                if item.isWord("END") {
                    depth -= 1
                    if depth == 0 { endIndex = index; break }
                }
            }
            guard let endIndex, items.contains(where: { $0.isWord("WHEN") }),
                  !items[..<endIndex].contains(where: { $0.token?.kind == .lineComment }) else {
                try inline(items, block: block, leadingSpace: true)
                return
            }
            emit(items[0], space: true)
            let caseColumn = out.column - (items[0].token?.text.count ?? 4)
            var part: [Node] = []
            var seenWhen = false
            depth = 0
            func flush(_ formatter: inout Formatter) throws {
                try formatter.inline(part, block: block, leadingSpace: true)
                part = []
            }
            for item in items[1..<endIndex] {
                // вложенный CASE — целиком в строку
                if item.isWord("CASE") { depth += 1; part.append(item); continue }
                if item.isWord("END"), depth > 0 { depth -= 1; part.append(item); continue }
                guard depth == 0, item.isWord("WHEN") || item.isWord("THEN") || item.isWord("ELSE") else {
                    part.append(item)
                    continue
                }
                try flush(&self)
                if item.isWord("WHEN"), !seenWhen {
                    // первый WHEN — на строке CASE
                    seenWhen = true
                    emit(item, space: true)
                } else {
                    out.newline(caseColumn)
                    emit(item, space: false)
                }
            }
            try flush(&self)
            out.newline(endColumn)
            emit(items[endIndex], space: false)
            try inline(Array(items[(endIndex + 1)...]), block: block, leadingSpace: true)
        }

        // MARK: Списки

        /// Через запятую: первый — на строке предложения, следующие — `, …` с колонки `commaColumn`.
        mutating func list(_ body: [Node], indent: Int, commaColumn: Int, block: Int) throws {
            let parts = split(body, by: { $0.token?.kind == .comma })
            for (index, part) in parts.terms.enumerated() {
                if index > 0 {
                    out.newline(commaColumn)
                    emit(parts.separators[index - 1], space: false)
                }
                out.continuation = commaColumn + 2
                try inline(part, block: block, leadingSpace: true)
            }
        }

        /// GROUP BY, ORDER BY, RETURNING: до 80 символов — в строку, длиннее — как список SELECT.
        mutating func shortList(_ body: [Node], indent: Int, keywordLength: Int) throws {
            var probe = Formatter(options: options)
            try probe.inline(body, block: 0, leadingSpace: false)
            let oneLine = !probe.out.text.contains("\n") && keywordLength + 1 + probe.out.text.count <= 80
            if oneLine {
                try inline(body, block: indent, leadingSpace: true)
            } else {
                try list(body, indent: indent, commaColumn: indent + keywordLength - 1, block: indent)
            }
        }

        // MARK: JOIN

        /// `JOIN t ON …`: условия — как у WHERE; в ClickHouse без TRUE (в ON нужны равенства).
        mutating func join(_ body: [Node], indent: Int) throws {
            guard let on = body.firstIndex(where: { $0.isWord("ON") }) else {
                try inline(body, block: indent, leadingSpace: true)
                return
            }
            try inline(Array(body[..<on]), block: indent, leadingSpace: true)
            emit(body[on], space: true)
            try conditions(Array(body[(on + 1)...]), indent: indent, anchor: !options.isClickHouse)
        }

        // MARK: Условия

        /// Одно условие — в строку. Два и больше через AND — `TRUE` и `  AND …` по строке; через OR
        /// (три и больше или вперемешку с AND) — `FALSE` и `  OR …`. Свой TRUE или 1 = 1 — не дублируем.
        mutating func conditions(_ body: [Node], indent: Int, anchor: Bool) throws {
            guard body.contains(where: { !$0.isComment }) else { throw Failure.unsupported }
            let ors = split(body, by: { $0.isWord("OR") }, skipBetween: false)
            let ands = split(body, by: { $0.isWord("AND") }, skipBetween: true)
            if ors.terms.count >= 3 || (ors.terms.count >= 2 && ands.terms.count >= 2) {
                try chain(ors, word: "OR", anchorWord: "FALSE", indent: indent, anchor: anchor)
            } else if ands.terms.count >= 2 {
                try chain(ands, word: "AND", anchorWord: "TRUE", indent: indent, anchor: anchor)
            } else {
                try condition(body, block: indent)
            }
        }

        private mutating func chain(_ parts: (terms: [[Node]], separators: [Node]), word: String, anchorWord: String,
                                    indent: Int, anchor: Bool) throws {
            var terms = parts.terms
            var separators: [Node?] = [nil] + parts.separators.map { Optional($0) }
            // комментарий своей строкой между условиями — над следующим «AND …», на его отступе
            // (а не хвостом предыдущего условия на отступе его продолжения)
            var commentsBefore: [[Node]] = Array(repeating: [], count: terms.count)
            for index in terms.indices.dropFirst() {
                while let last = terms[index - 1].last, last.isComment, last.token?.newlineBefore == true {
                    commentsBefore[index].insert(terms[index - 1].removeLast(), at: 0)
                }
            }
            if isAnchor(terms[0], word: anchorWord) {
                // своё TRUE или 1 = 1 уже есть — оно и остаётся на строке предложения
                try inline(terms[0], block: indent, leadingSpace: true)
                terms.removeFirst()
                separators.removeFirst()
                commentsBefore.removeFirst()
            } else if anchor {
                emit(.token(.synthetic(anchorWord)), space: true)
            } else {
                // без TRUE (ClickHouse JOIN): первое условие — на строке предложения
                try condition(terms[0], block: indent)
                terms.removeFirst()
                separators.removeFirst()
                commentsBefore.removeFirst()
            }
            for (index, term) in terms.enumerated() {
                for comment in commentsBefore[index] {
                    out.newline(indent + 2)
                    out.continuation = indent + 2
                    emit(comment, space: false)
                }
                out.newline(indent + 2)
                out.continuation = indent + 4
                emit(separators[index] ?? .token(.synthetic(word)), space: false)
                try condition(term, block: indent + 2)
            }
        }

        private func isAnchor(_ term: [Node], word: String) -> Bool {
            let tokens = term.filter { !$0.isComment }.compactMap(\.token)
            guard tokens.count == term.filter({ !$0.isComment }).count else { return false }
            let texts = tokens.map(\.upper)
            if word == "TRUE" { return texts == ["TRUE"] || texts == ["1", "=", "1"] }
            return texts == ["FALSE"] || texts == ["1", "=", "0"]
        }

        /// Условие: скобки с тремя и больше OR — `(FALSE` и `OR …` по строке; с тремя и больше AND (или AND
        /// с подзапросом) — `(TRUE` и `AND …`. Перед скобками может стоять NOT. Закрывающая — под началом строки.
        mutating func condition(_ term: [Node], block: Int) throws {
            let meaningful = term.indices.filter { !term[$0].isComment }
            if let groupIndex = meaningful.last, case .group(let open, let inner, let close) = term[groupIndex],
               !term[groupIndex].isSubquery, meaningful.dropLast().allSatisfy({ term[$0].isWord("NOT") }),
               !inner.contains(where: { $0.token?.kind == .lineComment }) {
                let ors = split(inner, by: { $0.isWord("OR") }, skipBetween: false)
                let ands = split(inner, by: { $0.isWord("AND") }, skipBetween: true)
                let hasSubquery = inner.contains { node in
                    if node.isSubquery { return true }
                    if case .group(_, let nested, _) = node { return nested.contains(where: \.isSubquery) }
                    return false
                }
                if ors.terms.count >= 3 {
                    try anchoredGroup(prefix: Array(term[..<groupIndex]), open: open, close: close, parts: ors,
                                      word: "OR", anchorWord: "FALSE", block: block)
                    return
                }
                if ors.terms.count == 1, ands.terms.count >= 3 || (ands.terms.count >= 2 && hasSubquery) {
                    try anchoredGroup(prefix: Array(term[..<groupIndex]), open: open, close: close, parts: ands,
                                      word: "AND", anchorWord: "TRUE", block: block)
                    return
                }
            }
            try inline(term, block: block, leadingSpace: true)
        }

        /// `(FALSE` / `(TRUE`, затем `OR …` / `AND …` по строке под скобкой, закрывающая — с колонки `block`.
        /// Своё FALSE (TRUE) или 1 = 0 (1 = 1) в начале уже есть — не дублируем.
        private mutating func anchoredGroup(prefix: [Node], open: Token, close: Token,
                                            parts: (terms: [[Node]], separators: [Node]),
                                            word: String, anchorWord: String, block: Int) throws {
            try inline(prefix, block: block, leadingSpace: true)
            emit(.token(open), space: true)
            let column = out.column
            var terms = parts.terms
            var separators: [Node?] = [nil] + parts.separators.map { Optional($0) }
            if isAnchor(terms[0], word: anchorWord) {
                try inline(terms[0], block: column, leadingSpace: false)
                terms.removeFirst()
                separators.removeFirst()
            } else {
                emit(.token(.synthetic(anchorWord)), space: false)
            }
            for (index, part) in terms.enumerated() {
                out.newline(column)
                out.continuation = column + word.count + 1
                emit(separators[index] ?? .token(.synthetic(word)), space: false)
                try inline(part, block: column, leadingSpace: true)
            }
            out.newline(block)
            emit(.token(close), space: false)
        }

        // MARK: В строку

        /// Выражение в строку. Подзапрос в скобках — с новой строки на 2 глубже `block`,
        /// закрывающая скобка — с колонки `block`.
        mutating func inline(_ items: [Node], block: Int, leadingSpace: Bool = false) throws {
            var previous: Token?
            for (index, item) in items.enumerated() {
                let space = index == 0 ? leadingSpace : spacing(after: previous, before: item)
                switch item {
                case .token(let token):
                    emit(item, space: space)
                    previous = token
                case .group(let open, let inner, let close):
                    if !item.isSubquery, try wrappedList(open: open, inner: inner, close: close, block: block, space: space) {
                        previous = close
                        continue
                    }
                    emit(.token(open), space: space)
                    if item.isSubquery {
                        // EXISTS: столбцы не нужны — `SELECT FROM t` (константа убирается, в сверке учтена)
                        var body = inner
                        if previous?.isWord("EXISTS") == true, options.allowsEmptySelect,
                           let constant = Self.existsConstant(in: inner) {
                            out.dropped.append(inner[constant].token!)
                            body.remove(at: constant)
                        }
                        if try !shortSubquery(body) {
                            out.newline(block + 2)
                            try query(body, indent: block + 2)
                            out.newline(block)
                        }
                    } else {
                        try inline(inner, block: block, leadingSpace: false)
                    }
                    emit(.token(close), space: false)
                    previous = close
                }
            }
        }

        /// Константа единственным столбцом подзапроса (`SELECT 1`, `SELECT *`, `SELECT NULL`) — индекс в `inner`.
        static func existsConstant(in inner: [Node]) -> Int? {
            let meaningful = inner.indices.filter { !inner[$0].isComment }
            guard meaningful.count >= 3, inner[meaningful[0]].isWord("SELECT"), inner[meaningful[2]].isWord("FROM"),
                  let token = inner[meaningful[1]].token else { return nil }
            let isConstant = token.kind == .number || token.isWord("NULL") || (token.kind == .op && token.text == "*")
            return isConstant ? meaningful[1] : nil
        }

        /// Короткий подзапрос — в строку: `(SELECT guid FROM d_rr)`. Один столбец (или без столбцов у EXISTS),
        /// одна таблица, без условий и соединений, без комментариев, и строка влезает в ширину.
        /// false — не короткий, пусть идёт с новой строки.
        private mutating func shortSubquery(_ inner: [Node]) throws -> Bool {
            guard inner.allSatisfy({ $0.token != nil && !$0.isComment }),
                  let from = inner.firstIndex(where: { $0.isWord("FROM") }), inner.first?.isWord("SELECT") == true else { return false }
            let columns = inner[1..<from], table = inner[(from + 1)...]
            guard columns.count <= 3, !columns.contains(where: { $0.token?.kind == .comma }),
                  !columns.contains(where: { $0.isWord("DISTINCT") }),
                  (1...4).contains(table.count),
                  table.allSatisfy({ node in
                      guard let token = node.token else { return false }
                      return token.kind == .dot || token.kind == .quoted
                          || (token.kind == .word && (!HatchPG.keywords.contains(token.upper) || token.upper == "AS"))
                  }) else { return false }
            var probe = Formatter(options: options)
            try probe.inline(inner, block: 0, leadingSpace: false)
            guard out.column + probe.out.text.count + 1 <= Self.lineWidth else { return false }
            try inline(inner, block: out.column, leadingSpace: false)
            return true
        }

        /// Длинный список в скобках (столбцы INSERT, VALUES, SET (…) = (…), IN, аргументы): не влезает в 80
        /// символов — внутри с новой строки на 2 глубже `block`, по нескольку через запятую до 80,
        /// закрывающая скобка — своей строкой с колонки `block`. false — влезает или не список.
        private mutating func wrappedList(open: Token, inner: [Node], close: Token, block: Int, space: Bool) throws -> Bool {
            let parts = split(inner, by: { $0.token?.kind == .comma })
            guard parts.terms.count >= 2, !inner.contains(where: { $0.token?.kind == .lineComment }) else { return false }
            var widths: [Int] = []
            for term in parts.terms {
                var probe = Formatter(options: options)
                try probe.inline(term, block: 0, leadingSpace: false)
                guard !probe.out.text.contains("\n") else { return false }
                widths.append(probe.out.text.count)
            }
            let inlineWidth = widths.reduce(0, +) + 2 * (widths.count - 1) + 2
            guard out.column + (space ? 1 : 0) + inlineWidth > Self.lineWidth else { return false }
            emit(.token(open), space: space)
            out.newline(block + 2)
            for (index, term) in parts.terms.enumerated() {
                if index > 0 {
                    emit(parts.separators[index - 1], space: false)
                    if out.column + 1 + widths[index] > Self.lineWidth { out.newline(block + 2) }
                }
                out.continuation = block + 4
                try inline(term, block: block + 2, leadingSpace: true)
            }
            out.newline(block)
            emit(.token(close), space: false)
            return true
        }

        static let lineWidth = 80

        /// Пробел между словами — как во входе; после запятой — всегда, перед запятой, точкой и
        /// закрывающей скобкой и после открывающей и точки — никогда; знаки сравнения — с пробелами.
        private func spacing(after previous: Token?, before item: Node) -> Bool {
            let token: Token
            switch item {
            case .token(let t): token = t
            case .group(let open, _, _): token = open
            }
            guard let previous else { return token.spaceBefore }
            if token.isComment { return true }
            if [.comma, .close, .dot].contains(token.kind) { return false }
            if previous.kind == .comma { return true }
            if previous.kind == .open || previous.kind == .dot { return false }
            let comparison: Set<String> = ["=", "<>", "!=", "<", ">", "<=", ">=", "<=>"]
            if token.kind == .op, comparison.contains(token.text) { return true }
            if previous.kind == .op, comparison.contains(previous.text) { return true }
            return token.spaceBefore
        }

        mutating func emit(_ node: Node, space: Bool) {
            switch node {
            case .token(let token): out.token(token, space: space)
            case .group(let open, let inner, let close):
                // группа как одно целое (модификаторы SELECT) — без переносов
                out.token(open, space: space)
                try? inline(inner, block: out.column, leadingSpace: false)
                out.token(close, space: false)
            }
        }

        // MARK: Разбиение

        /// Части между разделителями этого уровня. `skipBetween` — AND после BETWEEN не делит;
        /// внутри CASE … END не делим.
        func split(_ items: [Node], by isSeparator: (Node) -> Bool, skipBetween: Bool = false)
            -> (terms: [[Node]], separators: [Node]) {
            var terms: [[Node]] = [[]]
            var separators: [Node] = []
            var caseDepth = 0
            var betweenPending = false
            for item in items {
                if item.isWord("CASE") { caseDepth += 1 }
                if item.isWord("END"), caseDepth > 0 { caseDepth -= 1 }
                if item.isWord("BETWEEN") { betweenPending = true }
                if caseDepth == 0, isSeparator(item) {
                    if skipBetween, betweenPending, item.isWord("AND") {
                        betweenPending = false
                        terms[terms.count - 1].append(item)
                        continue
                    }
                    separators.append(item)
                    terms.append([])
                    continue
                }
                terms[terms.count - 1].append(item)
            }
            return (terms, separators)
        }
    }
}

