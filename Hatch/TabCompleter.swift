import Foundation

/// TAB как в zsh (`auto_menu`):
/// - один вариант — подставить сразу (у папки `/`, следующий TAB покажет её содержимое);
/// - несколько — сначала дописать общую часть; если она уже набрана — показать список,
///   следующие TAB перебирают варианты по кругу (Shift+TAB — назад), не уходя вглубь;
/// - Esc возвращает набранное до перебора; ввод с клавиатуры принимает вариант.
struct TabCompleter {
    enum Direction {
        case forward
        case backward
    }

    /// Перебор вариантов: что было набрано, варианты и выбранный (nil — список показан, но не вставлен).
    struct Menu: Equatable {
        let original: String
        let candidates: [String]
        var index: Int?
    }

    private(set) var menu: Menu?

    /// Новый текст поля или nil, если дополнять нечем.
    /// - Parameter apply: подставить вариант вместо последнего слова.
    mutating func press(_ direction: Direction, text: String, candidates: [String],
                        apply: (String, String) -> String) -> String? {
        if var menu {
            let count = menu.candidates.count
            let next: Int
            switch (direction, menu.index) {
            case (.forward, nil): next = 0
            case (.backward, nil): next = count - 1
            case (.forward, let index?): next = (index + 1) % count
            case (.backward, let index?): next = (index - 1 + count) % count
            }
            menu.index = next
            self.menu = menu
            return apply(menu.original, menu.candidates[next])
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 {
            return apply(text, candidates[0])
        }
        let extended = apply(text, Self.commonPrefix(candidates))
        if extended.count > text.count {
            return extended
        }
        menu = Menu(original: text, candidates: candidates, index: nil)
        return text
    }

    /// Esc: вернуть набранное до перебора; nil — перебора не было.
    mutating func cancel() -> String? {
        defer { menu = nil }
        return menu?.original
    }

    /// Пользователь продолжил ввод — вариант принят, перебор окончен.
    mutating func reset() {
        menu = nil
    }

    static func commonPrefix(_ strings: [String]) -> String {
        guard var prefix = strings.first else { return "" }
        for string in strings.dropFirst() {
            while !string.hasPrefix(prefix) { prefix.removeLast() }
        }
        return prefix
    }
}
