import Foundation

/// Как показать вывод в ограниченное число строк: начало, строка «скрыто N», конец.
/// Видно и с чего команда начала, и чем закончила (ошибки, итог, свежий вывод).
enum OutputPreview {
    struct Layout: Equatable {
        var head: [String]
        /// Сколько строк между началом и концом не показано (0 — вывод целиком).
        var hidden: Int
        var tail: [String]
    }

    /// - Parameters:
    ///   - lines: строки вывода (у превью работающей команды — уже без середины, см. `gap`);
    ///   - maxLines: сколько строк есть на показ, включая строку «скрыто N».
    static func layout(lines: [String], gap: OutputGap?, maxLines: Int) -> Layout {
        let gapCount = gap?.count ?? 0
        let after = gap.map { min($0.after, lines.count) } ?? lines.count
        let head = Array(lines.prefix(after))
        let tail = Array(lines.dropFirst(after))

        if gapCount == 0, head.count <= maxLines {
            return Layout(head: head, hidden: 0, tail: [])
        }
        if gapCount > 0, head.count + tail.count + 1 <= maxLines {
            return Layout(head: head, hidden: gapCount, tail: tail)
        }

        let headCount = max(1, (maxLines - 1) / 2)
        let tailCount = max(1, maxLines - 1 - headCount)
        let total = head.count + gapCount + tail.count
        let shownHead = Array(head.prefix(headCount))
        let shownTail = gapCount > 0 ? Array(tail.suffix(tailCount)) : Array(head.suffix(tailCount))
        return Layout(head: shownHead, hidden: total - shownHead.count - shownTail.count, tail: shownTail)
    }
}
