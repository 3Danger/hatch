import Foundation

/// Опечатка в имени команды: шелл ответил «command not found». Такой запуск не остаётся
/// в истории — набранное возвращается в поле, под ним «Команды gti нет. Похоже: git».
struct MissingCommand: Equatable {
    /// Как было набрано: вернётся в поле ввода.
    let command: String
    /// Первое слово, которого нет: `gti`.
    let word: String
}

enum CommandNotFound {
    /// Первое слово команды; переменные окружения перед ним (`FOO=1 cmd`) пропускаются.
    static func firstWord(_ command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first { !isAssignment($0) }
    }

    /// Шелл не нашёл именно первое слово: код 127 и его сообщение про это слово
    /// (zsh: `command not found: gti`, bash: `gti: command not found`, путь: `no such file or directory: ./x`).
    /// Если не нашлась команда внутри скрипта, сообщение про другое имя — блок остаётся.
    static func isMissing(command: String, exitCode: Int32?, output: String) -> Bool {
        guard exitCode == 127, let word = firstWord(command) else { return false }
        return output.split(whereSeparator: \.isNewline).contains { line in
            line.hasSuffix("command not found: \(word)")
                || line.hasSuffix("\(word): command not found")
                || line.hasSuffix("no such file or directory: \(word)")
                || line.hasSuffix("\(word): No such file or directory")
        }
    }

    /// Похожие имена для «Похоже: …», не больше `limit`:
    /// сначала близкие по написанию (`gti` → `git`), затем приложения по началу (`te` → Telegram).
    /// Для имён из одной-двух букв — только приложения по началу.
    /// - Parameters:
    ///   - commands: команды, алиасы, функции шелла;
    ///   - apps: имена приложений и их алиасы (по началу подсказываются только они — команд слишком много).
    static func suggestions(for word: String, commands: [String], apps: [String], limit: Int = 3) -> [String] {
        let lower = word.lowercased()
        guard !lower.isEmpty else { return [] }
        let maxDistance = lower.count <= 4 ? 1 : 2
        var scored: [(name: String, distance: Int)] = []
        // в одной-двух буквах «опечатка» совпадёт с чем угодно (te → tee, TV) — только приложения по началу
        for name in commands + apps where lower.count > 2 && name.lowercased() != lower {
            // длина сильно другая — не опечатка, расстояние не считаем
            guard abs(name.count - lower.count) <= maxDistance else { continue }
            let distance = editDistance(lower, name.lowercased())
            if distance <= maxDistance { scored.append((name, distance)) }
        }
        let close = scored
            .sorted { ($0.distance, $0.name.lowercased()) < ($1.distance, $1.name.lowercased()) }
            .map(\.name)
        let byPrefix = apps
            .filter { $0.lowercased().hasPrefix(lower) && $0.count > lower.count }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var seen = Set<String>()
        return (close + byPrefix).filter { seen.insert($0.lowercased()).inserted }.prefix(limit).map { $0 }
    }

    /// Заменить первое слово (`gti status` → `git status`), остальное как было.
    static func replacingFirstWord(in command: String, with word: String) -> String {
        guard let first = firstWord(command), let range = command.range(of: first) else { return command }
        return command.replacingCharacters(in: range, with: word)
    }

    private static func isAssignment(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "="), eq != token.startIndex else { return false }
        return token[..<eq].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Расстояние Дамерау — Левенштейна: перестановка соседних букв (`gti` → `git`) — одна правка.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
