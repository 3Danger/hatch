import Foundation

/// Автодополнение как в zsh, но без запуска шелла на каждое нажатие:
/// - команды и алиасы — из списка, который один раз собирает шелл пользователя (с его rc)
///   и который потом обновляется в фоне;
/// - файлы и папки — чтением директории прямо в приложении: у папки `/` в конце,
///   после `/` — её содержимое, скрытые — если набрана точка.
final class ShellCompletionEngine {
    private let commandIndex: CommandIndex
    /// Директория, от которой дополняются относительные пути (текущая директория лаунчера).
    var directory: String?

    init(shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") {
        self.commandIndex = CommandIndex.shared(for: shellPath)
    }

    /// Подсказка (одно лучшее совпадение) для текущего буфера.
    func suggestion(for buffer: String) -> String? {
        completions(for: buffer).first
    }

    /// Полная строка после применения подсказки (сохраняет предыдущие слова).
    func completionLine(for buffer: String) -> String? {
        suggestion(for: buffer).map { applyCandidate(buffer, candidate: $0) }
    }

    /// Все варианты для последнего слова буфера.
    func completions(for buffer: String) -> [String] {
        let words = Self.words(buffer)
        let token = words[words.count - 1]
        if words.count == 1 {
            // первое слово — команда; путь (`./run.sh`, `~/bin/x`) — как файл
            if token.contains("/") || token.hasPrefix("~") {
                return pathCompletions(for: token, directoriesOnly: false)
            }
            return token.isEmpty ? [] : commandIndex.commands(withPrefix: token)
        }
        return pathCompletions(for: token, directoriesOnly: words[0] == "cd")
    }

    /// Подставляет вариант вместо последнего слова (после пробела — новым словом).
    func applyCandidate(_ buffer: String, candidate: String) -> String {
        var words = Self.words(buffer)
        words[words.count - 1] = candidate
        return words.joined(separator: " ")
    }

    /// Команды и алиасы по началу имени (для проверок и selftest).
    func commandCompletions(prefix: String) -> [String] {
        commandIndex.commands(withPrefix: prefix)
    }

    /// Приводит путь под домашней директорией к виду `~/...`.
    static func normalizeHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    // MARK: - Слова

    /// Слова буфера; последнее — дополняемое (пустое, если буфер кончается пробелом).
    private static func words(_ buffer: String) -> [String] {
        var words = buffer.split(separator: " ").map(String.init)
        if words.isEmpty || buffer.hasSuffix(" ") { words.append("") }
        return words
    }

    // MARK: - Файлы и папки

    private func pathCompletions(for token: String, directoriesOnly: Bool) -> [String] {
        if token == "~" { return ["~/"] }
        // «папка/» — где искать (как набрано), остаток — начало имени
        let slash = token.lastIndex(of: "/")
        let typedDirectory = slash.map { String(token[...$0]) } ?? ""
        let namePrefix = slash.map { String(token[token.index(after: $0)...]) } ?? token
        let showHidden = namePrefix.hasPrefix(".")

        return DirectoryCache.shared.entries(in: resolve(typedDirectory))
            .filter { entry in
                (showHidden || !entry.name.hasPrefix("."))
                    && entry.name.hasPrefix(namePrefix)
                    && (!directoriesOnly || entry.isDirectory)
            }
            .map { typedDirectory + $0.name + ($0.isDirectory ? "/" : "") }
            .filter { $0 != token } // набранное целиком дополнять нечем
    }

    /// Набранная часть пути → путь в файловой системе.
    private func resolve(_ typedDirectory: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = directory ?? home
        if typedDirectory.isEmpty { return base }
        if typedDirectory.hasPrefix("~/") { return home + "/" + typedDirectory.dropFirst(2) }
        if typedDirectory.hasPrefix("/") { return typedDirectory }
        return (base as NSString).appendingPathComponent(typedDirectory)
    }
}

// MARK: - Команды

/// Команды и алиасы из шелла пользователя: собираются один раз (с его rc), дальше —
/// поиск в памяти. Раз в несколько минут список обновляется в фоне (новые программы, алиасы).
final class CommandIndex {
    private static var instances: [String: CommandIndex] = [:]
    private static let instancesLock = NSLock()

    static func shared(for shellPath: String) -> CommandIndex {
        instancesLock.lock()
        defer { instancesLock.unlock() }
        if let index = instances[shellPath] { return index }
        let index = CommandIndex(shellPath: shellPath)
        instances[shellPath] = index
        return index
    }

    /// Через сколько список считается устаревшим и обновляется в фоне.
    private static let refreshInterval: TimeInterval = 300

    private let shellPath: String
    private let lock = NSLock()
    private var commands: [String]?
    private var loadedAt = Date.distantPast
    private var refreshing = false

    private init(shellPath: String) {
        self.shellPath = shellPath
    }

    /// Собрать список заранее (при запуске приложения), чтобы первое нажатие было мгновенным.
    func prewarm() {
        DispatchQueue.global(qos: .utility).async { [self] in
            _ = currentCommands()
        }
    }

    func commands(withPrefix prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        return currentCommands().filter { $0.hasPrefix(prefix) }
    }

    private func currentCommands() -> [String] {
        lock.lock()
        let cached = commands
        let stale = Date().timeIntervalSince(loadedAt) > Self.refreshInterval
        lock.unlock()

        guard let cached else {
            // самый первый раз (не успели прогреть) — один синхронный сбор
            let fresh = load()
            store(fresh)
            return fresh
        }
        if stale { refreshInBackground() }
        return cached
    }

    private func refreshInBackground() {
        lock.lock()
        guard !refreshing else { lock.unlock(); return }
        refreshing = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            store(load())
            lock.lock()
            refreshing = false
            lock.unlock()
        }
    }

    private func store(_ list: [String]) {
        lock.lock()
        commands = list
        loadedAt = Date()
        lock.unlock()
    }

    private func load() -> [String] {
        let isZsh = (shellPath as NSString).lastPathComponent.lowercased().contains("zsh")
        let script = isZsh
            ? #"emulate -L zsh; [ -r "${ZDOTDIR:-$HOME}/.zshrc" ] && source "${ZDOTDIR:-$HOME}/.zshrc"; print -rl -- ${(k)commands} ${(k)aliases}"#
            : #"[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"; compgen -c; compgen -a"#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", script]
        var env = ProcessInfo.processInfo.environment
        env["DISABLE_AUTO_UPDATE"] = "true" // oh-my-zsh не должен спрашивать про обновление
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Array(Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)))
            .sorted()
    }
}

// MARK: - Папки

/// Содержимое папок с коротким кешем: пока набирается одно слово, папка читается один раз.
final class DirectoryCache {
    static let shared = DirectoryCache()

    struct Entry {
        let name: String
        let isDirectory: Bool
    }

    private static let ttl: TimeInterval = 2
    private let lock = NSLock()
    private var cache: [String: (date: Date, entries: [Entry])] = [:]

    func entries(in path: String) -> [Entry] {
        let key = (path as NSString).standardizingPath
        lock.lock()
        if let hit = cache[key], Date().timeIntervalSince(hit.date) < Self.ttl {
            lock.unlock()
            return hit.entries
        }
        lock.unlock()

        let url = URL(fileURLWithPath: key, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys), options: [])) ?? []
        let entries = items
            .map { item in Entry(name: item.lastPathComponent, isDirectory: Self.isDirectory(item, keys: keys)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        lock.lock()
        cache[key] = (Date(), entries)
        lock.unlock()
        return entries
    }

    /// Ссылка на папку (`/tmp` → `/private/tmp`) — тоже папка, как в zsh.
    private static func isDirectory(_ item: URL, keys: Set<URLResourceKey>) -> Bool {
        guard let values = try? item.resourceValues(forKeys: keys) else { return false }
        if values.isSymbolicLink == true {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) && isDir.boolValue
        }
        return values.isDirectory == true
    }
}
