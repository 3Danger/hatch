import Foundation

/// Дерево папок у папки пути над полем ввода — как хлебные крошки VS Code, только папки.
/// Показывает соседей папки (содержимое её родителя), сама она выделена.
/// Клавиши — как в дереве VS Code, кроме двух мест: Enter переходит в папку (как `cd`),
/// а ← на верхнем уровне поднимает дерево на уровень выше. Набор букв фильтрует видимые строки:
/// остаются совпавшие папки и (бледно) их родители.
struct FolderTree: Equatable {
    /// Чьи вложенные папки — верхний уровень дерева.
    private(set) var root: String
    private(set) var expanded: Set<String> = []
    /// Выделенная строка.
    private(set) var focus: String?
    /// Папка пути, к которой сейчас относится дерево (подсвечивается в пути).
    private(set) var crumb: String
    /// Набранный фильтр: в дереве остаются совпавшие папки и их родители.
    private(set) var filter = ""

    struct Row: Equatable {
        let path: String
        let depth: Int
        var name: String { (path as NSString).lastPathComponent }
    }

    enum Key: Equatable {
        case up, down, right, left, space
        /// Буква в фильтр.
        case character(Character)
        /// Стереть букву фильтра (`all` — весь фильтр).
        case backspace(all: Bool)
    }

    /// Строка с фильтром: совпала сама или показана как родитель совпавшей (бледно).
    struct VisibleRow: Equatable {
        let row: Row
        let isContext: Bool
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

    /// Строки с учётом фильтра: совпавшие и родители совпавших (для понимания, где они лежат).
    func visibleRows(_ children: Children) -> [VisibleRow] {
        let all = rows(children)
        guard !filter.isEmpty else { return all.map { VisibleRow(row: $0, isContext: false) } }
        let matches = Set(all.filter { ListFilter.rank(filter, name: $0.name) != nil }.map(\.path))
        return all.compactMap { row in
            if matches.contains(row.path) { return VisibleRow(row: row, isContext: false) }
            let isAncestor = matches.contains { $0.hasPrefix(row.path == "/" ? "/" : row.path + "/") }
            return isAncestor ? VisibleRow(row: row, isContext: true) : nil
        }
    }

    // MARK: - Клавиши

    @discardableResult
    mutating func handle(_ key: Key, children: Children) -> Action {
        let list = rows(children)
        guard !list.isEmpty else {
            if key == .left { liftUp() }
            return .none
        }
        // фильтр: буквы и Backspace меняют его; стрелки ↑/↓ ходят по совпавшим;
        // → ← и Space снимают фильтр и работают как обычно с выделенной папкой
        switch key {
        case .character(let character):
            filter.append(Character(character.lowercased()))
            focusBestMatch(list)
            return .none
        case .backspace(let all):
            guard !filter.isEmpty else { return .none }
            if all { filter = "" } else { filter.removeLast() }
            if !filter.isEmpty { focusBestMatch(list) }
            return .none
        case .up, .down:
            if !filter.isEmpty {
                let matches = visibleRows(children).filter { !$0.isContext }.map(\.row.path)
                guard !matches.isEmpty else { return .none }
                let current = focus.flatMap { matches.firstIndex(of: $0) }
                let next = key == .down ? min((current ?? -1) + 1, matches.count - 1) : max((current ?? matches.count) - 1, 0)
                focus = matches[next]
                return .none
            }
        case .right, .left, .space:
            filter = ""
        }
        let index = focus.flatMap { f in list.firstIndex { $0.path == f } }

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
        case .character, .backspace:
            break
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

    /// Выделение — на лучшее совпадение фильтра (с начала имени выше), при равных — выше в дереве.
    private mutating func focusBestMatch(_ list: [Row]) {
        let best = ListFilter.filter(list, query: filter, name: \.name).first
        if let best { focus = best.path }
    }

    /// Esc: есть фильтр — очистить (true), нет — нечего (false, список закрывается).
    mutating func clearFilter() -> Bool {
        guard !filter.isEmpty else { return false }
        filter = ""
        return true
    }

    static func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/" + name : directory + "/" + name
    }
}
