import Foundation

/// Дерево папок у папки пути над полем ввода — как хлебные крошки VS Code, только папки.
/// Показывает соседей папки (содержимое её родителя), сама она выделена.
/// Клавиши — как в дереве VS Code, кроме двух мест: Enter переходит в папку (как `cd`),
/// а ← на верхнем уровне поднимает дерево на уровень выше.
struct FolderTree: Equatable {
    /// Чьи вложенные папки — верхний уровень дерева.
    private(set) var root: String
    private(set) var expanded: Set<String> = []
    /// Выделенная строка.
    private(set) var focus: String?
    /// Папка пути, к которой сейчас относится дерево (подсвечивается в пути).
    private(set) var crumb: String
    /// Набранные буквы (переход по имени) и когда набрана последняя.
    private(set) var typed = ""
    private var typedAt = Date.distantPast

    /// Через сколько без нажатий набор букв начинается заново.
    static let typingPause: TimeInterval = 0.8

    struct Row: Equatable {
        let path: String
        let depth: Int
        var name: String { (path as NSString).lastPathComponent }
    }

    enum Key: Equatable {
        case up, down, right, left, space
        case character(Character)
    }

    /// Что сделать снаружи: перейти в папку или ничего (дерево поменялось само).
    enum Action: Equatable {
        case none
        case navigate(String)
    }

    /// Вложенные папки (имена) — снаружи: с диска или из теста.
    typealias Children = (String) -> [String]

    init(crumb: String) {
        self.crumb = crumb
        if crumb == "/" {
            // у корня соседей нет — показываем его папки
            root = "/"
            focus = nil
        } else {
            root = Self.parent(of: crumb)
            focus = crumb
        }
    }

    // MARK: - Строки

    func rows(_ children: Children) -> [Row] {
        var result: [Row] = []
        func walk(_ directory: String, depth: Int) {
            for name in children(directory) {
                let path = Self.join(directory, name)
                result.append(Row(path: path, depth: depth))
                if expanded.contains(path) { walk(path, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return result
    }

    func isExpanded(_ path: String) -> Bool { expanded.contains(path) }

    // MARK: - Клавиши

    @discardableResult
    mutating func handle(_ key: Key, children: Children, now: Date = Date()) -> Action {
        let list = rows(children)
        guard !list.isEmpty else {
            if key == .left { liftUp() }
            return .none
        }
        let index = focus.flatMap { f in list.firstIndex { $0.path == f } }
        if case .character = key {} else { typed = "" }

        switch key {
        case .down:
            focus = list[min((index ?? -1) + 1, list.count - 1)].path
        case .up:
            focus = list[max((index ?? list.count) - 1, 0)].path
        case .right:
            // свёрнутую — раскрыть, раскрытую — войти в первую вложенную
            guard let index else { focus = list[0].path; break }
            let row = list[index]
            if !expanded.contains(row.path) {
                expanded.insert(row.path)
            } else if let first = children(row.path).first {
                focus = Self.join(row.path, first)
            }
        case .left:
            guard let index else { liftUp(); break }
            let row = list[index]
            if expanded.contains(row.path) {
                collapse(row.path)
            } else if row.depth > 0 {
                focus = Self.parent(of: row.path)
            } else {
                liftUp()
            }
        case .space:
            guard let index else { break }
            let path = list[index].path
            if expanded.contains(path) { collapse(path) } else { expanded.insert(path) }
        case .character(let character):
            typeAhead(character, list: list, from: index, now: now)
        }
        return .none
    }

    /// Enter: перейти в выделенную папку.
    func enter() -> Action {
        focus.map(Action.navigate) ?? .none
    }

    /// Клик по шеврону: раскрыть или свернуть, строка выделяется.
    mutating func toggle(_ path: String) {
        focus = path
        if expanded.contains(path) { collapse(path) } else { expanded.insert(path) }
    }

    mutating func select(_ path: String) {
        focus = path
    }

    // MARK: - Внутреннее

    /// Верхний уровень и ← : дерево показывает уровень выше, папка остаётся выделенной.
    private mutating func liftUp() {
        guard root != "/" else { return }
        let previous = root
        root = Self.parent(of: previous)
        expanded = []
        focus = previous
        crumb = previous
    }

    /// Свернуть папку; выделение внутри неё переходит на неё саму.
    private mutating func collapse(_ path: String) {
        expanded = expanded.filter { $0 != path && !$0.hasPrefix(path + "/") }
        if let focus, focus.hasPrefix(path + "/") { self.focus = path }
    }

    /// Набор букв: к первой папке, имя которой начинается с набранного (дальше по списку),
    /// иначе — где эти буквы идут по порядку (только от двух букв, как в VS Code).
    private mutating func typeAhead(_ character: Character, list: [Row], from index: Int?, now: Date) {
        let fresh = now.timeIntervalSince(typedAt) > Self.typingPause
        typed = (fresh ? "" : typed) + String(character).lowercased()
        typedAt = now
        // первая буква ищет со следующей строки: повторное нажатие листает папки на эту букву
        let start = (index ?? -1) + (typed.count == 1 ? 1 : 0)
        let ordered = (0..<list.count).map { list[(max(start, 0) + $0) % list.count] }
        let query = typed
        if let hit = ordered.first(where: { $0.name.lowercased().hasPrefix(query) })
            ?? (query.count > 1 ? ordered.first(where: { Self.isSubsequence(query, of: $0.name.lowercased()) }) : nil) {
            focus = hit.path
        }
    }

    static func isSubsequence(_ query: String, of text: String) -> Bool {
        var remaining = Substring(query)
        for character in text where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    static func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/" + name : directory + "/" + name
    }
}
