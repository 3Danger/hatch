import Foundation

/// Навигация стрелками по командам из истории в порядке блоков:
/// ↓ — следующий (более старый) блок, ↑ — обратно, выше первого — введённый текст.
struct HistoryNavigator {
    struct Entry: Equatable {
        let id: UUID
        let command: String
    }

    /// Снимок порядка на старте навигации: перестройка списка во время шагов не сбивает позицию.
    private var snapshot: [Entry] = []
    private var index: Int?
    private var draft = ""

    var isNavigating: Bool { index != nil }

    var selectedID: UUID? { index.map { snapshot[$0].id } }

    /// ↓: команда следующего блока или nil, если двигаться некуда.
    mutating func older(entries: [Entry], current: String) -> String? {
        if index == nil {
            guard !entries.isEmpty else { return nil }
            snapshot = entries
            draft = current
            index = 0
            return snapshot[0].command
        }
        guard let i = index, i + 1 < snapshot.count else { return nil }
        index = i + 1
        return snapshot[i + 1].command
    }

    /// ↑: команда предыдущего блока, выше первого — введённый текст; nil вне навигации.
    mutating func newer() -> String? {
        guard let i = index else { return nil }
        if i == 0 {
            let text = draft
            reset()
            return text
        }
        index = i - 1
        return snapshot[i - 1].command
    }

    mutating func reset() {
        snapshot = []
        index = nil
        draft = ""
    }
}
