import Foundation

/// Как показать вывод в ограниченное число экранных строк: начало, строка «скрыто N», конец.
/// Видно и с чего команда начала, и чем закончила (ошибки, итог, свежий вывод).
/// Длинная строка вывода переносится по словам и занимает несколько экранных строк.
enum OutputPreview {
    struct Layout: Equatable {
        var head: [String]
        /// Сколько экранных строк показать у каждой строки начала: меньше, чем она занимает, — обрезана.
        var headRows: [Int]
        /// Сколько строк вывода между началом и концом не показано (0 — вывод целиком).
        var hidden: Int
        var tail: [String]
        var tailRows: [Int]
    }

    /// - Parameters:
    ///   - lines: строки вывода (у превью работающей команды — уже без середины, см. `gap`);
    ///   - maxLines: сколько экранных строк есть на показ, включая строку «скрыто N»;
    ///   - rows: сколько экранных строк займёт строка вывода (с переносами); можно не считать
    ///     дальше `maxLines + 1` — больше всё равно не покажется.
    static func layout(lines: [String], gap: OutputGap?, maxLines: Int,
                       rows: (String) -> Int = { _ in 1 }) -> Layout {
        let rowsOf = { (line: String) in max(1, rows(line)) }
        let gapCount = gap?.count ?? 0
        let after = gap.map { min($0.after, lines.count) } ?? lines.count
        let head = Array(lines.prefix(after))
        let tail = Array(lines.dropFirst(after))

        // влезает целиком (у работающей команды — всё, кроме пропущенной середины)
        let room = gapCount == 0 ? maxLines : maxLines - 1
        if fits(head + tail, rows: rowsOf, budget: room) {
            return Layout(head: head, headRows: head.map(rowsOf), hidden: gapCount,
                          tail: tail, tailRows: tail.map(rowsOf))
        }

        let headBudget = max(1, (maxLines - 1) / 2)
        let tailBudget = max(1, maxLines - 1 - headBudget)
        let total = head.count + gapCount + tail.count
        var result = split(head: head, tail: tail, gapCount: gapCount, total: total,
                           headBudget: headBudget, tailBudget: tailBudget, rows: rowsOf)
        // скрывать нечего, просто строки длинные и обрезаны: строка «скрыто N» не нужна,
        // её место отдаём началу
        if result.hidden == 0 {
            result = split(head: head, tail: tail, gapCount: gapCount, total: total,
                           headBudget: headBudget + 1, tailBudget: tailBudget, rows: rowsOf)
        }
        return result
    }

    private static func split(head: [String], tail: [String], gapCount: Int, total: Int,
                              headBudget: Int, tailBudget: Int, rows: (String) -> Int) -> Layout {
        let front = pick(head, budget: headBudget, rows: rows)
        // без пропуска конец берётся из тех же строк, после показанных в начале
        let backSource = gapCount > 0 ? tail : Array(head.dropFirst(front.lines.count))
        let back = pick(backSource.reversed(), budget: tailBudget, rows: rows)
        return Layout(head: front.lines, headRows: front.rows,
                      hidden: total - front.lines.count - back.lines.count,
                      tail: back.lines.reversed(), tailRows: back.rows.reversed())
    }

    /// Строки по порядку, пока хватает места; последняя может войти обрезанной.
    private static func pick<S: Sequence>(_ lines: S, budget: Int,
                                         rows: (String) -> Int) -> (lines: [String], rows: [Int]) where S.Element == String {
        var picked: [String] = [], shown: [Int] = [], used = 0
        for line in lines {
            guard used < budget else { break }
            let n = min(rows(line), budget - used)
            picked.append(line)
            shown.append(n)
            used += n
        }
        return (picked, shown)
    }

    /// Влезают ли строки в бюджет; считает только до переполнения — длинный вывод не обходит весь.
    private static func fits(_ lines: [String], rows: (String) -> Int, budget: Int) -> Bool {
        var used = 0
        for line in lines {
            used += rows(line)
            if used > budget { return false }
        }
        return true
    }
}

/// Перенос строки по словам для моноширинного шрифта: экранные строки как диапазоны символов.
enum OutputWrap {
    /// - Parameters:
    ///   - columns: сколько символов влезает в экранную строку;
    ///   - limit: дальше не считать (огромная строка без переносов не обходится целиком).
    static func rows(_ text: String, columns: Int, limit: Int = .max) -> [Range<Int>] {
        let chars = Array(text)
        let columns = max(1, columns)
        guard chars.count > columns else { return [0..<chars.count] }
        var result: [Range<Int>] = []
        var start = 0
        while start < chars.count, result.count < limit {
            if chars.count - start <= columns {
                result.append(start..<chars.count)
                break
            }
            // последний пробел, на котором строка ещё влезает; без пробела — режем по ширине
            var end = start + columns
            if let space = (start + 1...start + columns).last(where: { chars[$0] == " " }) {
                end = space
            }
            result.append(start..<end)
            start = end
            // перенос съедает пробелы в начале следующей строки
            while start < chars.count, chars[start] == " " { start += 1 }
        }
        return result
    }
}
